"""Phase 1 retro tooling: custom ledger check ids, the review round cap, bg_run's running marker."""

import io
import json
import os
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "review"))
import bg_run  # noqa: E402
import record  # noqa: E402
import tasks  # noqa: E402


class CustomCheckIds(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        patch = mock.patch.dict(os.environ, {"TASKS_DIR": str(Path(self.tmp.name) / "tasks")})
        patch.start()
        self.addCleanup(patch.stop)
        self.addCleanup(self.tmp.cleanup)

    def cli(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out):
            code = tasks.main(list(argv))
        return code, out.getvalue()

    def ids(self):
        return [c["id"] for c in json.loads(self.cli("show", "T-1")[1])["acceptance"]]

    def new(self, *checks):
        args = ["new", "T-1", "--intake", "i", "--level", "L1", "--brief", "b"]
        for c in checks:
            args += ["--check", c]
        return self.cli(*args)

    def test_custom_and_auto_ids_mix(self):
        self.new("r1=review round 1", "plain one", "plain two", "x-y_2=other")
        self.assertEqual(self.ids(), ["r1", "a1", "a2", "x-y_2"])
        entry = json.loads(self.cli("show", "T-1")[1])
        self.assertEqual(entry["acceptance"][0]["check"], "review round 1")

    def test_text_containing_equals_after_a_space_stays_plain(self):
        self.new("iPhone shows x=1")
        self.assertEqual(self.ids(), ["a1"])

    def test_prose_with_spaced_equals_or_long_head_or_empty_text_stays_auto(self):
        self.new("x = y", "count = 3 tiles", "averyveryverylongheadname=thing", "r9=")
        self.assertEqual(self.ids(), ["a1", "a2", "a3", "a4"])

    def test_every_check_prints_the_id_used(self):
        code, out = self.cli("new", "T-9", "--intake", "i", "--level", "L1", "--brief", "b",
                             "--check", "r1=first", "--check", "plain")
        self.assertIn("added r1: first", out)
        self.assertIn("added a1: plain", out)

    def test_duplicate_id_refused(self):
        with self.assertRaises(SystemExit) as ctx:
            self.new("r1=a", "r1=b")
        self.assertIn("already exists", str(ctx.exception))

    def test_bad_id_refused(self):
        with self.assertRaises(SystemExit) as ctx:
            self.new("R1=upper")
        self.assertIn("[a-z][a-z0-9_-]{0,15}", str(ctx.exception))

    def test_add_check_accepts_both_forms(self):
        self.new("one")
        self.assertEqual(self.cli("add-check", "T-1", "r2=second")[1].strip(), "added r2: second")
        self.assertEqual(self.cli("add-check", "T-1", "plain")[1].strip(), "added a2: plain")
        with self.assertRaises(SystemExit):
            self.cli("add-check", "T-1", "r2=again")
        self.assertEqual(self.ids(), ["a1", "r2", "a2"])

    def test_flip_works_on_a_custom_id_and_schema_pattern_allows_it(self):
        import re
        self.new("r1=thing")
        evidence = Path(self.tmp.name) / "e.txt"
        evidence.write_text("x")
        self.assertEqual(self.cli("flip", "T-1", "r1", "--evidence", str(evidence))[0], 0)
        schema = json.loads((TOOLS.parent / "contracts" / "task-ledger.schema.json").read_text())
        pattern = schema["properties"]["acceptance"]["items"]["properties"]["id"]["pattern"]
        for good in ("a1", "r1", "x-y_2"):
            self.assertTrue(re.match(pattern, good), good)
        self.assertFalse(re.match(pattern, "R1"))


class ReviewRoundCap(unittest.TestCase):
    def test_refusal_rules(self):
        self.assertIsNone(record.round_refusal(1, None))
        self.assertIsNone(record.round_refusal(2, None))
        self.assertIn("Needs Decision", record.round_refusal(3, None))
        self.assertIn("--confirm-round", record.round_refusal(3, "  "))
        self.assertIsNone(record.round_refusal(3, "confirmation pass, no blockers"))

    def run_record(self, previous, *extra):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        out = root / "build" / "review" / "b.json"
        out.parent.mkdir(parents=True)
        out.write_text(json.dumps(previous))
        verdict = Path(tmp.name) / "v.json"
        verdict.write_text(json.dumps({"verdict": "pass", "findings": []}))

        def fake_git(*args):
            return {"rev-parse --abbrev-ref HEAD": "b", "rev-parse HEAD": "newhead",
                    "rev-parse --show-toplevel": str(root)}[" ".join(args)]

        err, outbuf = io.StringIO(), io.StringIO()
        with mock.patch.object(record, "git", fake_git), mock.patch.object(record, "review_file_name", lambda b: "b.json"), \
                mock.patch.object(record, "reviewer_identity", lambda: {"agent_type": "reviewer", "session_id": "s", "agent_id": ""}), \
                mock.patch("sys.stderr", err), redirect_stdout(outbuf):
            code = record.main([str(verdict), *extra])
        return code, err.getvalue(), out

    def test_round_three_needs_confirmation(self):
        previous = {"round": 2, "head": "oldhead", "verdict": "changes"}
        code, err, out = self.run_record(previous)
        self.assertEqual(code, 2)
        self.assertIn("2-round rule", err)
        self.assertEqual(json.loads(out.read_text())["round"], 2)  # not overwritten

    def test_round_three_with_reason_is_recorded(self):
        previous = {"round": 2, "head": "oldhead", "verdict": "changes"}
        code, err, out = self.run_record(previous, "--confirm-round", "confirmation after round 2, no blockers")
        self.assertEqual(code, 0, err)
        data = json.loads(out.read_text())
        self.assertEqual((data["round"], data["round_confirmation"]), (3, "confirmation after round 2, no blockers"))

    def run_with_verdict(self, verdict, findings, *extra):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        out = root / "build" / "review" / "b.json"
        out.parent.mkdir(parents=True)
        out.write_text(json.dumps({"round": 2, "head": "oldhead", "verdict": "changes"}))
        f = root / "v.json"
        f.write_text(json.dumps({"verdict": verdict, "findings": findings}))
        fake = lambda *a: {"rev-parse --abbrev-ref HEAD": "b", "rev-parse HEAD": "newhead",
                           "rev-parse --show-toplevel": str(root)}[" ".join(a)]
        err = io.StringIO()
        with mock.patch.object(record, "git", fake), mock.patch.object(record, "review_file_name", lambda b: "b.json"), \
                mock.patch.object(record, "reviewer_identity", lambda: {"agent_type": "reviewer", "session_id": "s", "agent_id": ""}), \
                mock.patch("sys.stderr", err), redirect_stdout(io.StringIO()):
            code = record.main([str(f), *extra])
        return code, err.getvalue(), out

    def test_blocker_after_round_two_refused_even_with_confirm(self):
        finding = [{"severity": "blocker", "rule": "r", "detail": "d"}]
        code, err, out = self.run_with_verdict("blocker", finding, "--confirm-round", "one more pass")
        self.assertEqual(code, 2)
        self.assertIn("Needs Decision", err)
        self.assertEqual(json.loads(out.read_text())["round"], 2)

    def test_confirmation_pass_without_blockers_records_with_reason(self):
        finding = [{"severity": "major", "rule": "r", "detail": "d"}]
        code, err, out = self.run_with_verdict("changes", finding, "--confirm-round", "confirmation pass")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out.read_text())["round_confirmation"], "confirmation pass")

    def test_round_two_needs_nothing(self):
        code, err, out = self.run_record({"round": 1, "head": "oldhead", "verdict": "changes"})
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out.read_text())["round"], 2)


class BgRunMarker(unittest.TestCase):
    def test_marker_exists_while_running_and_is_removed_after(self):
        with TemporaryDirectory() as tmp:
            directory = Path(tmp)
            code = bg_run.run("mk", [sys.executable, "-c",
                                     "import json,sys; m=json.load(open(sys.argv[1])); "
                                     "sys.exit(0 if m['label']=='mk' and m['pid'] else 1)",
                                     str(directory / "mk.running")], directory, 30)
            self.assertEqual(code, 0)
            self.assertFalse((directory / "mk.running").exists())
            self.assertTrue((directory / "mk.digest").exists())

    def test_marker_removed_when_the_command_cannot_start(self):
        with TemporaryDirectory() as tmp:
            directory = Path(tmp)
            with self.assertRaises(OSError):
                bg_run.run("bad", ["/nonexistent/binary"], directory, 30)
            self.assertFalse((directory / "bad.running").exists())

    def test_marker_removed_after_timeout_kill(self):
        with TemporaryDirectory() as tmp:
            directory = Path(tmp)
            code = bg_run.run("slow", [sys.executable, "-c", "import time; time.sleep(60)"], directory, 1)
            self.assertEqual(code, 124)
            self.assertFalse((directory / "slow.running").exists())

    def test_log_and_digest_are_redacted(self):
        with TemporaryDirectory() as tmp:
            directory = Path(tmp)
            bg_run.run("sec", [sys.executable, "-c", "print('FENTON_HASS_TOKEN=" + "abc" * 10 + "'); print('failed')"],
                       directory, 30)
            for name in ("sec.log", "sec.digest"):
                self.assertNotIn("abcabcabc", (directory / name).read_text())


if __name__ == "__main__":
    unittest.main()
