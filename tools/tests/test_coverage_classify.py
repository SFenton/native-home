"""Coverage failure classification (``tools/coverage_classify.py``), driven by fixture logs and digests."""

import contextlib
import io
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

from tools import coverage_classify as cc

FAIL_LOG = """\
Test Case '-[FentonHomeTests.CustomLightTests testRamp]' failed (2.1 seconds).
Test Case '-[FentonHomeTests.CustomLightTests testOff]' passed (0.1 seconds).
Test Case '-[FentonHomeTests.HostedSectionTests testSides]' failed (9.0 seconds).
✘ Test sidesLayout() failed after 0.4 seconds with 1 issue.
✘ Test rampValue(x:) failed after 0.1 seconds with 1 issue.
"""

PASS_LOG = """\
Test Case '-[FentonHomeTests.CustomLightTests testRamp]' passed (0.5 seconds).
✔ Test sidesLayout() passed after 0.1 seconds.
✔ Test rampValue(x:) passed after 0.1 seconds.
"""


def open_issue(_number: int) -> tuple[str, list[str]]:
    return "OPEN", ["Workflow"]


class ExtractTests(unittest.TestCase):
    """Failing and passed ids come out of XCTest and Swift Testing lines, parameterised names included."""

    def test_extracts_failed_cases_only(self) -> None:
        self.assertEqual(cc.extract_failed(FAIL_LOG), ["CustomLightTests/testRamp", "HostedSectionTests/testSides",
                                                      "rampValue", "sidesLayout"])

    def test_passed_ids(self) -> None:
        failed, passed = cc.parse_log(PASS_LOG)
        self.assertEqual((failed, passed), ([], ["CustomLightTests/testRamp", "rampValue", "sidesLayout"]))

    def test_clean_log_has_no_ids(self) -> None:
        self.assertEqual(cc.parse_log("all quiet\n"), ([], []))


class FilterTests(unittest.TestCase):
    """The swift test filters match XCTest ids and Swift Testing's ``Module.Suite/name()`` ids."""

    def test_filters(self) -> None:
        self.assertEqual(cc.swift_filters(["A/a", "sidesLayout"]), ["A/a$", "/sidesLayout\\("])

    def test_swift_testing_filter_matches_real_id(self) -> None:
        import re
        pattern = cc.swift_filters(["sidesLayout"])[0]
        self.assertTrue(re.search(pattern, "HassCoreTests.SidesSuite/sidesLayout()"))
        self.assertFalse(re.search(pattern, "HassCoreTests.SidesSuite/sidesLayoutWide()"))


class ClassifyTests(unittest.TestCase):
    """coverage-only needs a passed line in the rerun; anything else is real."""

    def test_split(self) -> None:
        self.assertEqual(cc.classify(["A/a", "B/b", "C/c"], ["A/a", "C/c"], ["B/b"]), (["A/a", "C/c"], ["B/b"]))

    def test_unreported_id_is_real(self) -> None:
        self.assertEqual(cc.classify(["A/a"], [], []), ([], ["A/a"]))

    def test_passed_and_failed_is_real(self) -> None:
        self.assertEqual(cc.classify(["A/a"], ["A/a"], ["A/a"]), ([], ["A/a"]))

    def test_digest_real_fails(self) -> None:
        lines, status = cc.digest([], ["B/b"], False, set(), [])
        self.assertEqual(status, 1)
        self.assertIn("real: B/b", lines)
        self.assertIn("timeout: no", lines)

    def test_digest_unquarantined_coverage_only_fails(self) -> None:
        lines, status = cc.digest(["A/a"], [], False, set(), [])
        self.assertEqual(status, 1)
        self.assertTrue(any(line.startswith("unquarantined coverage-only: A/a") for line in lines))

    def test_digest_quarantined_coverage_only_passes(self) -> None:
        self.assertEqual(cc.digest(["A/a"], [], False, {"A/a"}, [])[1], 0)

    def test_timeout_fails_even_when_quarantined(self) -> None:
        lines, status = cc.digest(["A/a"], [], True, {"A/a"}, [])
        self.assertEqual(status, 1)
        self.assertIn("timeout: yes", lines)

    def test_quarantine_problems_are_warnings_on_a_green_run(self) -> None:
        lines, status = cc.digest([], [], False, set(), ["A/a: bad"], warn_only=True)
        self.assertEqual(status, 0)
        self.assertIn("warning: quarantine: A/a: bad", lines)

    def test_digest_clean(self) -> None:
        self.assertEqual(cc.digest([], [], False, set(), [])[1], 0)


class PhaseTests(unittest.TestCase):
    """Each phase run is judged on its own exit status and the ids it named."""

    def test_clean_and_named_failures_are_fine(self) -> None:
        self.assertEqual(cc.phase_problems(["swift 0 0", "swift-2 1 2", "swift-3 1 1"]), ([], False))

    def test_silent_failure_is_a_problem(self) -> None:
        problems, timed_out = cc.phase_problems(["swift 1 1", "swift-2 65 0"])
        self.assertEqual(len(problems), 1)
        self.assertIn("swift-2", problems[0])
        self.assertFalse(timed_out)

    def test_timeout_crash_and_signal(self) -> None:
        problems, timed_out = cc.phase_problems(["swift-1 124 3", "swift 139 1", "swift-3 125 0", "x 126 1"])
        self.assertEqual(len(problems), 4)
        self.assertTrue(timed_out)

    def test_crash_marker_and_unexplained_count(self) -> None:
        problems, _ = cc.phase_problems(["swift 1 1 1 0", "swift-2 1 1 0 2", "ok 1 1 0 0"])
        self.assertEqual(len(problems), 2)
        self.assertIn("crash marker", problems[0])
        self.assertIn("more failure(s)", problems[1])

    def test_phase_facts(self) -> None:
        log = FAIL_LOG.split("\n", 1)[0] + "\nerror: Exited with unexpected signal code 11\n"
        self.assertEqual(cc.phase_facts(log), (1, 1, 0))
        counted = "Test Case '-[T.A a]' failed (1.0 seconds).\nExecuted 5 tests, with 3 failures (0 unexpected) in 1 (1) seconds\n"
        self.assertEqual(cc.phase_facts(counted)[2], 2)
        issues = ("\u2718 Test x() recorded an issue at A.swift:1:1: no\n\u2718 Test x() failed after 0.1 seconds with 1 issue.\n"
                  "\u2718 Test run with 4 tests in 1 suites failed after 0.2 seconds with 3 issues.\n")
        self.assertEqual(cc.phase_facts(issues), (1, 0, 2))
        self.assertEqual(cc.phase_facts("Restarting after unexpected exit, crash, or test timeout\n")[1], 1)
        self.assertEqual(cc.phase_facts("all quiet\n"), (0, 0, 0))

    def test_unreadable_line(self) -> None:
        self.assertEqual(len(cc.phase_problems(["junk"])[0]), 1)


class QuarantineTests(unittest.TestCase):
    """Every entry needs id, issue number, date and an open Workflow issue."""

    def test_empty_quarantine_is_valid(self) -> None:
        self.assertEqual(cc.validate_quarantine([], open_issue), [])

    def test_entry_without_issue_is_refused(self) -> None:
        problems = cc.validate_quarantine([{"id": "A/a", "date": "2026-11-04"}], open_issue)
        self.assertEqual(len(problems), 1)
        self.assertIn("open Workflow issue", problems[0])

    def test_closed_issue_is_refused(self) -> None:
        problems = cc.validate_quarantine([{"id": "A/a", "issue": 5, "date": "2026-11-04"}],
                                          lambda _n: ("CLOSED", ["Workflow"]))
        self.assertTrue(any("closed" in problem for problem in problems))

    def test_non_workflow_issue_is_refused(self) -> None:
        problems = cc.validate_quarantine([{"id": "A/a", "issue": 5, "date": "2026-11-04"}],
                                          lambda _n: ("OPEN", ["bug"]))
        self.assertTrue(any("Workflow" in problem for problem in problems))

    def test_bad_date_and_duplicate(self) -> None:
        entry = {"id": "A/a", "issue": 5, "date": "yesterday"}
        problems = cc.validate_quarantine([entry, entry], open_issue)
        self.assertTrue(any("date" in problem for problem in problems))
        self.assertTrue(any("twice" in problem for problem in problems))

    def test_unreadable_issue_is_a_problem(self) -> None:
        def broken(_n: int) -> tuple[str, list[str]]:
            raise RuntimeError("no network")
        problems = cc.validate_quarantine([{"id": "A/a", "issue": 5, "date": "2026-11-04"}], broken)
        self.assertTrue(any("unreadable" in problem for problem in problems))

    def test_gh_failures_are_wrapped(self) -> None:
        with mock.patch("subprocess.run", side_effect=FileNotFoundError("gh")):
            with self.assertRaises(RuntimeError):
                cc.gh_issue_state(5)
        bad = mock.Mock(returncode=0, stdout="not json", stderr="")
        with mock.patch("subprocess.run", return_value=bad):
            with self.assertRaises(RuntimeError):
                cc.gh_issue_state(5)
        good = mock.Mock(returncode=0, stdout=json.dumps({"state": "OPEN", "labels": [{"name": "Workflow"}]}), stderr="")
        with mock.patch("subprocess.run", return_value=good):
            self.assertEqual(cc.gh_issue_state(5), ("OPEN", ["Workflow"]))
        failed = mock.Mock(returncode=1, stdout="", stderr="HTTP 404")
        with mock.patch("subprocess.run", return_value=failed):
            with self.assertRaises(RuntimeError):
                cc.gh_issue_state(5)

    def test_lookup_only_for_needed_ids(self) -> None:
        calls = []

        def lookup(number: int) -> tuple[str, list[str]]:
            calls.append(number)
            return "OPEN", ["Workflow"]
        entries = [{"id": "A/a", "issue": 1, "date": "2026-11-04"}, {"id": "B/b", "issue": 2, "date": "2026-11-04"}]
        self.assertEqual(cc.validate_quarantine(entries, lookup, {"B/b"}), [])
        self.assertEqual(calls, [2])
        self.assertEqual(cc.validate_quarantine(entries, lookup, set()), [])
        self.assertEqual(calls, [2])

    def test_missing_file_is_empty_and_non_list_refused(self) -> None:
        self.assertEqual(cc.load_quarantine(Path("/nonexistent/q.json")), [])
        self.assertEqual(len(cc.validate_quarantine({"id": 1}, None)), 1)

    def test_repo_quarantine_parses(self) -> None:
        self.assertEqual(cc.validate_quarantine(cc.load_quarantine(cc.QUARANTINE_DEFAULT), None), [])


class ScriptWiringTests(unittest.TestCase):
    """The host rerun keeps its --require-tests guard, and only the swift kind exists."""

    def test_script_wiring(self) -> None:
        root = Path(__file__).resolve().parents[2] / "tools"
        phases = (root / "coverage_phases.sh").read_text(encoding="utf-8")
        self.assertIn("--require-tests", phases)
        for gone in ("rerun-cmd", "cov_rerun_ios", "hosted", "journey"):
            self.assertNotIn(gone, phases)
        self.assertFalse(hasattr(cc, "rerun_command"))


class CommandLineTests(unittest.TestCase):
    """The commands over fixture files."""

    def setUp(self) -> None:
        self.tmp = TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def write(self, name: str, text: str) -> str:
        path = self.root / name
        path.write_text(text, encoding="utf-8")
        return str(path)

    def run_cli(self, *args: str) -> tuple[int, str]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = cc.main(list(args))
        return status, out.getvalue()

    def quarantine(self, *ids: str) -> str:
        return self.write("q.json", json.dumps([{"id": i, "issue": 7, "date": "2026-11-04"} for i in ids]))

    def test_failed_ids_and_clean_log(self) -> None:
        status, out = self.run_cli("failed-ids", self.write("log.txt", FAIL_LOG))
        self.assertEqual(status, 0)
        self.assertIn("CustomLightTests/testRamp", out.split())
        self.assertEqual(self.run_cli("failed-ids", self.write("ok.txt", "all good\n")), (0, ""))

    def test_swift_filters_command(self) -> None:
        self.assertEqual(self.run_cli("swift-filters", "A/a,sidesLayout"), (0, "A/a$\n/sidesLayout\\(\n"))

    def test_classify_split_with_quarantine_and_timeout(self) -> None:
        failed = self.write("failed.txt", "swift A/a\nswift B/b\n")
        phases = self.write("phases.txt", "swift 1 1\nswift-2 124 1\n")
        again = self.write("again.log", "Test Case '-[T.A a]' passed (1.0 seconds).\n")
        status, out = self.run_cli("classify", "--failed", failed, "--phases", phases, "--quarantine",
                                   self.quarantine("A/a"), "--offline", "--rerun-log", again)
        self.assertEqual(status, 1)
        self.assertIn("coverage-only: A/a", out)
        self.assertIn("real: B/b", out)
        self.assertIn("timeout: yes", out)

    def test_classify_quarantined_with_evidence_passes(self) -> None:
        failed = self.write("failed.txt", "swift A/a\n")
        phases = self.write("phases.txt", "swift 1 1\n")
        again = self.write("again.log", "Test Case '-[T.A a]' passed (1.0 seconds).\n")
        status, _ = self.run_cli("classify", "--failed", failed, "--phases", phases, "--quarantine",
                                 self.quarantine("A/a"), "--offline", "--rerun-log", again)
        self.assertEqual(status, 0)

    def test_classify_without_rerun_evidence_is_real(self) -> None:
        failed = self.write("failed.txt", "swift A/a\n")
        phases = self.write("phases.txt", "swift 1 1\n")
        status, out = self.run_cli("classify", "--failed", failed, "--phases", phases, "--quarantine",
                                   self.quarantine("A/a"), "--offline")
        self.assertEqual(status, 1)
        self.assertIn("real: A/a", out)

    def test_classify_empty_quarantine_refuses_coverage_only(self) -> None:
        failed = self.write("failed.txt", "swift A/a\n")
        again = self.write("again.log", "Test Case '-[T.A a]' passed (1.0 seconds).\n")
        status, out = self.run_cli("classify", "--failed", failed, "--phases", self.write("p.txt", "swift 1 1\n"),
                                   "--quarantine", self.write("q.json", "[]"), "--offline", "--rerun-log", again)
        self.assertEqual(status, 1)
        self.assertIn("unquarantined coverage-only: A/a", out)

    def test_classify_entry_without_issue_fails(self) -> None:
        failed = self.write("failed.txt", "swift A/a\n")
        again = self.write("again.log", "Test Case '-[T.A a]' passed (1.0 seconds).\n")
        quarantine = self.write("q.json", json.dumps([{"id": "A/a", "date": "2026-11-04"}]))
        status, out = self.run_cli("classify", "--failed", failed, "--phases", self.write("p.txt", "swift 1 1\n"),
                                   "--quarantine", quarantine, "--offline", "--rerun-log", again)
        self.assertEqual(status, 1)
        self.assertIn("quarantine: A/a", out)

    def test_classify_clean_run(self) -> None:
        status, out = self.run_cli("classify", "--failed", self.write("f.txt", ""), "--phases",
                                   self.write("p.txt", "swift 0 0\nswift-2 0 0\n"), "--quarantine",
                                   self.write("q.json", "[]"), "--offline")
        self.assertEqual(status, 0)
        self.assertIn("real: none", out)


if __name__ == "__main__":
    unittest.main()
