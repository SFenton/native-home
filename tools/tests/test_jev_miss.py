"""Tests for tools/jev_miss.py: miss kinds, truth sources, excluded sources, redaction, split, missing files."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import jev_miss  # noqa: E402

BRANCH = "agents/topic-2026-11-05"
STATE = "pr_title: Add thing\nfiles: a.py"


def write_jsonl(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")


def gate(question, subject, value, p, at="2026-11-05T10:00:00Z", **extra):
    return {"at": at, "question": question + "@1", "subject": subject, "value": value, "p": p, "printed": False,
            **extra}


def read(path: Path):
    return [json.loads(line) for line in path.read_text().splitlines()]


class JevMissTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.home = self.root / "build" / "jev"

    def tearDown(self):
        self.tmp.cleanup()

    def runner(self, view=None):
        def fake(args):
            if "headRefName" in args:
                return json.dumps({"headRefName": BRANCH})
            return json.dumps(view or {"commits": [], "files": []})
        return fake

    def record(self, findings, verdict="changes"):
        """A Reviewer record in the shape tools/review/record.py writes."""
        path = self.root / "build" / "review" / (BRANCH.replace("/", "__") + ".json")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"verdict": verdict, "findings": findings, "branch": BRANCH, "head": "abc",
                                    "round": 1}))

    def test_ledger_level_is_a_self_influenced_signal_never_harvested(self):
        write_jsonl(self.home / "gate.jsonl", [gate("design.user_visible", "T-1", "false", 0.1, state=STATE)])
        ledger = self.root / "build" / "tasks"
        ledger.mkdir(parents=True)
        (ledger / "T-1.json").write_text(json.dumps({"id": "T-1", "level": "L2"}))
        counts = jev_miss.run(self.root, task="T-1", use_gh=False)
        miss = read(self.home / "misses.jsonl")[0]
        self.assertEqual((miss["kind"], miss["suggestion"], miss["truth_source"], miss["self_influenced"]),
                         ("false_negative", "add_question", "ledger_final_level", True))
        self.assertEqual(counts["harvested"], 0)

    def test_tests_true_without_a_tests_finding_is_false_positive(self):
        write_jsonl(self.home / "gate.jsonl", [gate("check.tests", "pr:7", "true", 0.95, state=STATE)])
        self.record([{"severity": "major", "rule": "naming", "detail": "rename x"}])
        jev_miss.run(self.root, runner=self.runner())
        miss = read(self.home / "misses.jsonl")[0]
        self.assertEqual((miss["kind"], miss["truth"], miss["truth_source"], miss["suggestion"]),
                         ("false_positive", False, "review_verdict", "tighten_or_remove"))

    def test_tests_false_with_a_tests_finding_is_false_negative(self):
        write_jsonl(self.home / "gate.jsonl", [gate("check.tests", "pr:7", "false", 0.05, state=STATE)])
        self.record([{"severity": "major", "rule": "tests", "detail": "no accessibility test on iPad"}])
        jev_miss.run(self.root, runner=self.runner())
        miss = read(self.home / "misses.jsonl")[0]
        self.assertEqual((miss["kind"], miss["truth"]), ("false_negative", True))

    def test_green_ci_is_not_a_truth_for_tests(self):
        write_jsonl(self.home / "gate.jsonl", [gate("check.tests", "pr:7", "true", 0.95)])
        self.assertEqual(jev_miss.run(self.root, runner=self.runner())["misses"], 0)

    def test_agreeing_row_and_unsure_band_are_harvested_with_state(self):
        write_jsonl(self.home / "gate.jsonl", [gate("check.tests", "pr:7", "true", 0.95, state=STATE, head="abc"),
                                               gate("check.tests", "pr:7", "true", 0.5, at="2026-11-05T11:00:00Z",
                                                    state=STATE, head="abc")])
        self.record([{"severity": "major", "rule": "tests", "detail": "missing unit test"}])
        jev_miss.run(self.root, runner=self.runner())
        self.assertEqual(sorted(r["kind"] for r in read(self.home / "misses.jsonl")), ["agree", "unsure_band"])
        staged = read(self.home / "harvest" / "check.tests.jsonl")
        self.assertEqual(len(staged), 2)
        self.assertEqual(staged[0]["text"], STATE)

    def test_rows_without_state_need_state_and_are_not_staged(self):
        write_jsonl(self.home / "gate.jsonl", [gate("check.tests", "pr:7", "true", 0.95)])
        self.record([{"severity": "major", "rule": "tests", "detail": "missing unit test"}])
        counts = jev_miss.run(self.root, runner=self.runner())
        self.assertTrue(read(self.home / "misses.jsonl")[0]["needs_state"])
        self.assertEqual(counts["harvested"], 0)

    def test_ui_path_gives_no_truth_and_is_not_staged(self):
        view = {"commits": [], "files": [{"path": "apple/Sources/HassUI/UIKitPort/X.swift"}]}
        write_jsonl(self.home / "shadow.jsonl", [{"at": "2026-11-05T10:00:00Z", "question": "design.user_visible@1",
                                                  "subject": "pr:9", "value": "false", "state": STATE,
                                                  "probabilities": {"true": 0.2}}])
        counts = jev_miss.run(self.root, runner=self.runner(view))
        miss = read(self.home / "misses.jsonl")[0]
        self.assertEqual((miss["no_truth"], miss["truth"], miss["truth_source"]), (True, None, "release_note_ui_diff"))
        self.assertEqual(counts["harvested"], 0)

    def test_release_note_gives_no_truth(self):
        view = {"commits": [{"messageHeadline": "x", "messageBody": "Release-Note: Faster launch\n"}],
                "files": [{"path": "tools/x.py"}]}
        write_jsonl(self.home / "gate.jsonl", [gate("design.user_visible", "pr:9", "false", 0.1, state=STATE)])
        counts = jev_miss.run(self.root, runner=self.runner(view))
        self.assertTrue(read(self.home / "misses.jsonl")[0]["no_truth"])
        self.assertEqual(counts["harvested"], 0)

    def test_no_ui_path_and_no_note_is_a_false_label_and_staged(self):
        view = {"commits": [{"messageHeadline": "x", "messageBody": "Release-Note: none\n"}],
                "files": [{"path": "tools/x.py"}]}
        write_jsonl(self.home / "gate.jsonl", [gate("design.user_visible", "pr:9", "true", 0.9, state=STATE)])
        counts = jev_miss.run(self.root, runner=self.runner(view))
        miss = read(self.home / "misses.jsonl")[0]
        self.assertEqual((miss["kind"], miss["truth"], miss["no_truth"]), ("false_positive", False, False))
        self.assertEqual(counts["harvested"], 1)

    def test_tests_rule_field_only_and_head_tie(self):
        flags = jev_miss.review_flags_tests
        self.assertFalse(flags({"findings": [{"rule": "naming", "detail": "add a test for this"}]}))
        self.assertTrue(flags({"findings": [{"rule": "tests", "detail": "x"}]}))
        self.assertTrue(flags({"findings": [{"rule": "x", "category": "tests.missing", "detail": "x"}]}))
        self.assertFalse(flags({"findings": [{"rule": "contests", "detail": "x"}]}))
        write_jsonl(self.home / "gate.jsonl", [gate("check.tests", "pr:7", "true", 0.95, state=STATE),
                                               gate("check.tests", "pr:7", "true", 0.95, state=STATE, head="abc",
                                                    at="2026-11-05T11:00:00Z")])
        self.record([{"severity": "major", "rule": "tests", "detail": "x"}])
        counts = jev_miss.run(self.root, runner=self.runner())
        stale = sorted(r["stale_truth"] for r in read(self.home / "misses.jsonl"))
        self.assertEqual(stale, [False, True])
        self.assertEqual(counts["harvested"], 1)

    def test_release_note_none_with_docs_only_is_not_visible(self):
        view = {"commits": [{"messageHeadline": "x", "messageBody": "Release-Note: none\n"}],
                "files": [{"path": "tools/x.py"}]}
        write_jsonl(self.home / "gate.jsonl", [gate("design.user_visible", "pr:9", "false", 0.1)])
        jev_miss.run(self.root, runner=self.runner(view))
        self.assertEqual(read(self.home / "misses.jsonl")[0]["kind"], "agree")

    def test_text_reading_questions_are_never_harvested(self):
        write_jsonl(self.home / "gate.jsonl", [gate("owner_msg.kind", "T-2", "bug", 0.9, state=STATE),
                                               gate("research.evidence", "T-2", "true", 0.9, state=STATE)])
        counts = jev_miss.run(self.root, use_gh=False)
        self.assertEqual((counts["harvested"], counts["needs_blind_label"]), (0, 2))
        self.assertFalse((self.home / "harvest").exists())
        self.assertEqual({r["truth_source"] for r in read(self.home / "misses.jsonl")}, {"needs_blind_label"})

    def test_secret_in_snippet_is_redacted(self):
        secret = "Bearer abcdef1234567890abcdef1234567890"
        miss = {"id": "abc", "question": "check.tests", "subject": "pr:1", "jev": "true", "p": 0.9, "truth": False,
                "truth_source": "review_verdict", "kind": "false_positive"}
        row = jev_miss.harvest_row(miss, f"tests ok {secret}")
        self.assertNotIn("abcdef1234567890", json.dumps(row))
        self.assertIn("[redacted]", row["text"])

    def test_split_is_deterministic_and_mixed(self):
        self.assertEqual(jev_miss.split_of("x1"), jev_miss.split_of("x1"))
        self.assertEqual({jev_miss.split_of(f"id{i}") for i in range(50)}, {"train", "heldout"})

    def test_rerun_does_not_duplicate(self):
        write_jsonl(self.home / "gate.jsonl", [gate("check.tests", "pr:7", "true", 0.95, state=STATE)])
        self.record([{"severity": "major", "rule": "tests", "detail": "missing"}])
        jev_miss.run(self.root, runner=self.runner())
        again = jev_miss.run(self.root, runner=self.runner())
        self.assertEqual((again["misses"], again["harvested"]), (0, 0))

    def test_missing_files_and_gh_are_not_fatal(self):
        self.assertEqual(jev_miss.main(["--root", str(self.root), "--task", "T-9"]), 0)
        write_jsonl(self.home / "gate.jsonl", [gate("check.tests", "pr:7", "true", 0.9)])

        def broken(args):
            raise OSError("no gh")
        self.assertEqual(jev_miss.run(self.root, runner=broken)["misses"], 0)

    def test_machinery_only_reports_a_false_negative(self):
        write_jsonl(self.home / "gate.jsonl", [gate("code.custom_machinery", "pr:7", "false", 0.1, state=STATE)])
        self.record([{"severity": "major", "rule": "rung-0", "detail": "custom blur machinery"}])
        jev_miss.run(self.root, runner=self.runner())
        self.assertEqual(read(self.home / "misses.jsonl")[0]["kind"], "false_negative")
        (self.home / "misses.jsonl").unlink()
        self.record([{"severity": "minor", "rule": "naming", "detail": "x"}], verdict="pass")
        self.assertEqual(jev_miss.run(self.root, runner=self.runner())["misses"], 0)

    def test_since_uses_utc_and_task_includes_its_pr_rows(self):
        write_jsonl(self.home / "gate.jsonl", [
            gate("check.tests", "pr:7", "true", 0.95, state=STATE),
            gate("check.tests", "pr:7", "true", 0.95, at="2020-01-01T00:00:00Z", state=STATE),
            gate("check.tests", "pr:8", "true", 0.95, state=STATE)])
        self.record([{"severity": "major", "rule": "tests", "detail": "missing"}])
        ledger = self.root / "build" / "tasks"
        ledger.mkdir(parents=True)
        (ledger / "T-3.json").write_text(json.dumps({"id": "T-3", "evidence": "https://github.com/SFenton/native-home/pull/7 and https://github.com/o/r/pull/8"}))
        self.assertEqual(jev_miss.Outcomes(self.root).pr_numbers("T-3"), ["7"])
        counts = jev_miss.run(self.root, task="T-3", since="1000000d", runner=self.runner())
        self.assertEqual(counts["rows"], 2)
        self.assertGreater(jev_miss.row_time({"at": "1970-01-02T00:00:00Z"}), 86399)
        self.assertEqual(jev_miss.row_time({"at": "1970-01-02T00:00:00Z"}), 86400)

    def test_bad_since_is_reported_not_raised(self):
        self.assertEqual(jev_miss.main(["--root", str(self.root), "--since", "soon"]), 0)


if __name__ == "__main__":
    unittest.main()
