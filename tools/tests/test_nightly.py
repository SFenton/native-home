"""Nightly shard planning (tools/nightly_plan.py) and result/issue handling (tools/nightly_report.py)."""

import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import nightly_plan  # noqa: E402
import nightly_report as report  # noqa: E402

FAIL_LOG = """\
Test Case '-[FentonHomeUITests.RoomsJourneyTests testOpen]' started.
/x/RoomsJourneyTests.swift:12: error: -[FentonHomeUITests.RoomsJourneyTests testOpen] : XCTAssertTrue failed
Test Case '-[FentonHomeUITests.RoomsJourneyTests testOpen]' failed (3.0 seconds).
** TEST FAILED **
"""
PASS_LOG = "Test Case '-[FentonHomeUITests.A testB]' passed (1.0 seconds).\n** TEST SUCCEEDED **\n"


class PlanTests(unittest.TestCase):
    def test_scan_counts_tests_per_class(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "A.swift").write_text(
                "final class AJourneyTests: XCTestCase {\n func testOne() {}\n func testTwo() {}\n}\n"
                "final class BJourneyTests: XCTestCase {\n func testThree() {}\n}\n")
            (Path(tmp) / "Helper.swift").write_text("struct Helper { func testNothing() {} }\n")
            self.assertEqual(nightly_plan.scan(Path(tmp)),
                             {"AJourneyTests": ["testOne", "testTwo"], "BJourneyTests": ["testThree"]})

    def test_shards_never_exceed_the_limit_and_split_big_classes(self):
        classes = {"A": ["t%d" % i for i in range(25)], "B": ["t%d" % i for i in range(25)],
                   "C": ["t%d" % i for i in range(25)], "Big": ["m%d" % i for i in range(70)]}
        packed = nightly_plan.shards(classes, 60)
        self.assertTrue(all(s["tests"] <= 60 for s in packed))
        self.assertEqual(sum(s["tests"] for s in packed), 145)
        flat = [f for s in packed for f in s["filters"]]
        self.assertIn("-only-testing:FentonHomeUITests/A", flat)
        self.assertIn("-only-testing:FentonHomeUITests/Big/m0", flat)
        self.assertNotIn("-only-testing:FentonHomeUITests/Big", flat)

    def test_plan_matrix_has_a_shard_per_plan_group_and_marks_the_last_shard(self):
        doc = nightly_plan.plan({"Gate": {"A": ["a"] * 40, "B": ["b"] * 40}, "Live": {"C": ["c"] * 5}}, 60)
        self.assertEqual([(i["plan"], i["shard"], i["last"]) for i in doc["include"]],
                         [("Gate", 1, False), ("Gate", 2, False), ("Live", 3, True)])
        self.assertTrue(all("family" not in i for i in doc["include"]))
        self.assertEqual(nightly_plan.plan({"Gate": {"A": ["a"]}}, 60, "zzz")["include"], [])

    def test_the_real_ui_tests_fit_the_limit(self):
        classes = nightly_plan.scan()
        self.assertGreater(len(classes), 20)
        self.assertTrue(all(s["tests"] <= 60 for s in nightly_plan.shards(classes, 60)))
        include = nightly_plan.plan(nightly_plan.scan_plans(["Gate", "Live", "Capture"]), 60)["include"]
        self.assertEqual({i["plan"] for i in include}, {"Gate", "Live", "Capture"})
        self.assertTrue(all(i["tests"] <= 60 for i in include))

    def test_main_prints_json_and_fails_on_an_empty_filter(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(nightly_plan.main(["--filter", "Bedroom", "--plans", "Gate"]), 0)
        self.assertEqual([i["plan"] for i in json.loads(out.getvalue())["include"]], ["Gate"])
        self.assertEqual(nightly_plan.main(["--filter", "NoSuchClassAnywhere"]), 1)


class FakeGitHub:
    def __init__(self, issues=()):
        self.issues = list(issues)
        self.calls = []

    def open_issues(self):
        return self.issues

    def ensure_label(self):
        self.calls.append(("label",))

    def create(self, title, body):
        self.calls.append(("create", title, body))

    def comment(self, number, body):
        self.calls.append(("comment", number, body))

    def unlabel(self, number, label):
        self.calls.append(("unlabel", number, label))

    def close(self, number):
        self.calls.append(("close", number))


class ReportTests(unittest.TestCase):
    def test_an_empty_run_is_infra_with_a_note_never_a_failing_issue(self):
        empty = report.make_result("journeys-iphone", "EMPTY: no tests ran (xcodebuild iphone): the selection matched nothing\n", 1, 5)
        self.assertEqual(empty["status"], "infra")
        self.assertEqual(empty["failed"], {})
        self.assertTrue(any(note.startswith("EMPTY:") for note in empty["notes"]))
        self.assertIn("RESULT: EMPTY", empty["digest"])

    def test_a_run_where_all_three_families_skipped_everything_reports_empty_for_each_area(self):
        note = ("Test Case '-[ClimateWideLayoutJourneyTests testA]' skipped (0.1 seconds).\n"
                "\t Executed 2 tests, with 2 tests skipped and 0 failures (0 unexpected)\n"
                "NOTE: every selected test skipped (xcodebuild %s): 2 skipped, none ran\n** TEST SUCCEEDED **\n")
        run_level = "EMPTY: no family ran a test, every selected test skipped (xcodebuild_iphone ran 0, skipped 2); --allow-empty if intended\n"
        for family in ("iphone", "duo", "ipad"):
            # each family exits 0 with its own log; ios_uitest.sh appends the run-level EMPTY line to every family log
            result = report.make_result("journeys-" + family, note % family + run_level, 0, 5)
            self.assertEqual(result["status"], "infra", family)
            self.assertIn("RESULT: EMPTY", result["digest"])
            self.assertEqual(result["failed"], {})
        script = (Path(__file__).resolve().parents[1] / "ios_uitest.sh").read_text()
        self.assertIn('echo "$TALLY_OUT" >> "$ROOT/apple/.build/uitest-$family.log"', script)
        # Only a parallel run rewrites the family logs, so only this run's families get the line.
        self.assertIn('for family in "${FAMILIES[@]}"; do', script)
        self.assertIn('if [[ $PARALLEL == 1 && ${#FAMILIES[@]} -gt 1 ]]; then', script)

    def test_a_shard_that_skipped_everything_but_exited_zero_is_not_empty(self):
        log = "\t Executed 2 tests, with 2 tests skipped and 0 failures (0 unexpected)\n** TEST SUCCEEDED **\n"
        result = report.make_result("journeys-duo", log, 0, 5)
        self.assertEqual((result["status"], result["notes"]), ("pass", []))

    def test_result_statuses(self):
        self.assertEqual(report.make_result("journeys-iphone", PASS_LOG, 0, 5)["status"], "pass")
        failed = report.make_result("journeys-iphone", FAIL_LOG, 65, 5, "s1")
        self.assertEqual(failed["status"], "fail")
        self.assertIn("RoomsJourneyTests.testOpen", failed["failed"])
        infra = report.make_result("journeys-duo", "devcap: hold timeout after 3600s\n", 124, 5)
        self.assertEqual(infra["status"], "infra")
        build = report.make_result("journeys-ipad", "Foo.swift:3:4: error: boom\n** BUILD FAILED **\n", 65, 5)
        self.assertEqual(build["status"], "fail")
        self.assertTrue(next(iter(build["failed"])).startswith("build: "))

    def test_coverage_result_keeps_the_gate_lines(self):
        log = "swift.logic: 90/100 lines = 90.00% across 3 files (need 95%)\nERROR: swift.logic: 90.00% is below 95%\n"
        result = report.make_result("coverage", log, 1, 5)
        self.assertEqual(result["status"], "fail")
        self.assertEqual(len(result["notes"]), 2)

    def test_merge_fail_beats_infra_beats_pass(self):
        results = [{"area": "a", "status": "pass", "failed": {}}, {"area": "a", "status": "infra", "failed": {}},
                   {"area": "b", "status": "infra", "failed": {}}, {"area": "b", "status": "fail", "failed": {"t": "m"}},
                   {"area": "c", "status": "pass", "failed": {}}]
        areas = report.merge(results)
        self.assertEqual({k: v["status"] for k, v in areas.items()}, {"a": "infra", "b": "fail", "c": "pass"})

    def test_missing_shards_cannot_pass(self):
        results = [{"area": "a", "status": "pass", "failed": {}}]
        areas = report.merge(results)
        report.require_complete(areas, {"a": 2, "coverage": 1}, results)
        self.assertEqual((areas["a"]["status"], areas["coverage"]["status"]), ("infra", "infra"))

    def test_failing_area_opens_one_issue_and_dedupes_by_title(self):
        areas = {"journeys-iphone": {"status": "fail", "failed": {"A.testB": "boom"}, "notes": [], "digests": []}}
        gh = FakeGitHub()
        self.assertEqual(report.sync_issues(gh, areas, "http://run", "abcdef1234567"), ["journeys-iphone: issue opened"])
        self.assertEqual([c[0] for c in gh.calls], ["label", "create"])
        self.assertEqual(gh.calls[1][1], "Nightly: journeys-iphone failing")
        self.assertIn("A.testB", gh.calls[1][2])
        again = FakeGitHub([{"number": 7, "title": "Nightly: journeys-iphone failing",
                             "labels": [{"name": "Nightly Fix"}, {"name": "Awaiting Nightly"}]}])
        self.assertEqual(report.sync_issues(again, areas, "http://run", "abc"), ["journeys-iphone: still failing (#7)"])
        self.assertEqual([c[0] for c in again.calls], ["comment", "unlabel"])
        self.assertIn("A.testB", again.calls[0][2])

    def test_passing_area_closes_its_issue_and_infra_leaves_it(self):
        gh = FakeGitHub([{"number": 3, "title": "Nightly: coverage failing", "labels": []},
                         {"number": 4, "title": "Nightly: journeys-duo failing", "labels": []}])
        areas = {"coverage": {"status": "pass", "failed": {}, "notes": [], "digests": []},
                 "journeys-duo": {"status": "infra", "failed": {}, "notes": [], "digests": []},
                 "journeys-ipad": {"status": "pass", "failed": {}, "notes": [], "digests": []}}
        partial = FakeGitHub([{"number": 3, "title": "Nightly: coverage failing", "labels": []}])
        self.assertIn("stays open", report.sync_issues(partial, areas, "http://run", "abc")[0])
        self.assertEqual(partial.calls, [], "a run without --full-run never comments or closes")
        self.assertEqual(report.sync_issues(gh, areas, "http://run", "abc", allow_close=True), ["coverage: passed, closed #3"])
        self.assertEqual([c[0] for c in gh.calls], ["comment", "close"])

    def test_cli_result_then_issues_dry_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "log.txt"
            log.write_text(FAIL_LOG)
            out = io.StringIO()
            with redirect_stdout(out):
                self.assertEqual(report.main(["result", "--area", "journeys-iphone", "--shard", "1", "--log", str(log),
                                              "--exit-code", "65", "--out", str(Path(tmp) / "r" / "result-a-1.json")]), 0)
                self.assertEqual(report.main(["issues", "--results", tmp, "--expect", "journeys-iphone=2"]), 0)
            self.assertIn("| journeys-iphone | FAIL | 1 |", out.getvalue())
            self.assertIn("only 1 of 2 shard results arrived", out.getvalue())

    def test_summary_lists_failures(self):
        text = report.summary({"x": {"status": "fail", "failed": {"T.t": "m"}, "notes": ["n"], "digests": ["d"]}}, "u")
        self.assertIn("### x (fail)", text)
        self.assertIn("`T.t` m", text)


class DispatchTests(unittest.TestCase):
    """tools/nightly_dispatch.sh against a stub `gh` and `caffeinate` on PATH."""

    def run_script(self, tmp, kill=False):
        bin_dir = Path(tmp) / "bin"
        bin_dir.mkdir()
        calls = Path(tmp) / "calls.txt"
        (bin_dir / "gh").write_text('#!/bin/sh\necho "gh $*" >> "%s"\n' % calls)
        (bin_dir / "caffeinate").write_text('#!/bin/sh\necho "caffeinate $*" >> "%s"\nshift; exec "$@"\n' % calls)
        for stub in bin_dir.iterdir():
            stub.chmod(0o755)
        kill_file = Path(tmp) / "NO_NIGHTLY"
        if kill:
            kill_file.write_text("")
        env = dict(os.environ, PATH="%s:%s" % (bin_dir, os.environ["PATH"]), HASS_NIGHTLY_KILL_FILE=str(kill_file),
                   HASS_NIGHTLY_WATCH="0", HOME=tmp)
        proc = subprocess.run(["bash", str(TOOLS / "nightly_dispatch.sh")], env=env, capture_output=True, text=True)
        return proc, calls.read_text() if calls.exists() else ""

    def test_dispatches_nightly_on_main_under_caffeinate(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc, calls = self.run_script(tmp)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("caffeinate -i gh workflow run nightly.yml --repo SFenton/native-home --ref main", calls)

    def test_kill_file_stops_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc, calls = self.run_script(tmp, kill=True)
            self.assertEqual(proc.returncode, 0)
            self.assertIn("paused", proc.stdout)
            self.assertEqual(calls, "")

    def test_install_dry_run_renders_a_two_am_plist(self):
        proc = subprocess.run(["bash", str(TOOLS / "nightly_install.sh"), "--dry-run"], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("com.sfenton.hass-nightly", proc.stdout)
        self.assertIn("<key>Hour</key><integer>2</integer><key>Minute</key><integer>0</integer>", proc.stdout)
        self.assertIn("nightly_dispatch.sh", proc.stdout)


if __name__ == "__main__":
    unittest.main()
