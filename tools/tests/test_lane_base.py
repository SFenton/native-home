"""``tools/lane_base.py``: base resolution order and the base-failure store, against throwaway repositories."""

import importlib.util
import json
import shutil
import subprocess
import sys
import unittest
from unittest import mock
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("lane_base", TOOLS / "lane_base.py")
lane_base = importlib.util.module_from_spec(_spec)
sys.modules["lane_base"] = lane_base
_spec.loader.exec_module(lane_base)

NO_PR = lambda root: None


def git(root, *args):
    return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=root, check=True,
                          capture_output=True, text=True).stdout.strip()


def commit(root, name):
    (root / name).write_text(name)
    git(root, "add", "-A")
    git(root, "commit", "-qm", name)


def make_repo(tmp, workflow_base="claude/uikit-port"):
    """A clone with origin/main and origin/claude/uikit-port (two commits past main); HEAD on main."""
    origin = Path(tmp) / "origin.git"
    git(tmp, "init", "-q", "--bare", "-b", "main", str(origin))
    clone = Path(tmp) / "clone"
    git(tmp, "clone", "-q", str(origin), str(clone))
    (clone / "tools" / "triage").mkdir(parents=True)
    (clone / "tools" / "triage" / "config.json").write_text(json.dumps({"product_base": "main", "workflow_base": workflow_base}))
    shutil.copy(TOOLS / "lane_base.py", clone / "tools" / "lane_base.py")
    commit(clone, "base")
    git(clone, "push", "-q", "-u", "origin", "main")
    git(clone, "remote", "set-head", "origin", "main")
    git(clone, "checkout", "-q", "-b", "claude/uikit-port")
    commit(clone, "port1")
    commit(clone, "port2")
    git(clone, "push", "-q", "-u", "origin", "claude/uikit-port")
    git(clone, "checkout", "-q", "main")
    return clone


class ResolveTests(unittest.TestCase):
    def resolve(self, root, env=None, pr=NO_PR):
        return lane_base.resolve(root, env or {}, pr)

    def test_environment_wins(self):
        with TemporaryDirectory() as tmp:
            clone = make_repo(tmp)
            git(clone, "checkout", "-q", "-b", "lane", "claude/uikit-port")
            self.assertEqual(self.resolve(clone, {"FENTON_AFFECTED_BASE": "origin/main"}, lambda r: "claude/uikit-port"),
                             ("origin/main", "FENTON_AFFECTED_BASE"))

    def test_open_pr_base_beats_recorded_parent_and_proximity(self):
        with TemporaryDirectory() as tmp:
            clone = make_repo(tmp)
            git(clone, "checkout", "-q", "-b", "lane", "claude/uikit-port")
            git(clone, "config", "branch.lane.sh-base", "origin/main")
            ref, why = self.resolve(clone, pr=lambda r: "main")
            self.assertEqual(ref, "origin/main")
            self.assertIn("open PR base", why)

    def test_pr_base_that_does_not_exist_is_skipped(self):
        with TemporaryDirectory() as tmp:
            clone = make_repo(tmp)
            git(clone, "checkout", "-q", "-b", "lane", "claude/uikit-port")
            ref, why = self.resolve(clone, pr=lambda r: "gone/branch")
            self.assertEqual(ref, "origin/claude/uikit-port")
            self.assertIn("nearest", why)

    def test_recorded_parent(self):
        with TemporaryDirectory() as tmp:
            clone = make_repo(tmp)
            git(clone, "checkout", "-q", "-b", "lane", "claude/uikit-port")
            git(clone, "config", "branch.lane.sh-base", "origin/main")
            ref, why = self.resolve(clone)
            self.assertEqual(ref, "origin/main")
            self.assertIn("recorded parent", why)

    def test_nearest_long_lived_branch_wins(self):
        with TemporaryDirectory() as tmp:
            clone = make_repo(tmp)
            git(clone, "checkout", "-q", "-b", "from-port", "claude/uikit-port")
            commit(clone, "lane work")
            self.assertEqual(self.resolve(clone)[0], "origin/claude/uikit-port")
            git(clone, "checkout", "-q", "-b", "from-main", "main")
            commit(clone, "lane work")
            self.assertEqual(self.resolve(clone)[0], "origin/main")

    def test_tie_goes_to_the_default_branch(self):
        with TemporaryDirectory() as tmp:
            clone = make_repo(tmp)
            git(clone, "push", "-q", "origin", "main:refs/heads/claude/sibling")
            git(clone, "fetch", "-q", "origin")
            (clone / "tools" / "triage" / "config.json").write_text(json.dumps({"product_base": "main", "workflow_base": "claude/sibling"}))
            git(clone, "checkout", "-q", "-b", "lane", "main")
            commit(clone, "work")
            self.assertEqual(self.resolve(clone)[0], "origin/main")

    def test_missing_long_lived_branch_is_skipped(self):
        with TemporaryDirectory() as tmp:
            clone = make_repo(tmp, workflow_base="claude/retired")
            git(clone, "push", "-q", "origin", ":claude/uikit-port")
            git(clone, "fetch", "-q", "--prune", "origin")
            git(clone, "branch", "-q", "-D", "claude/uikit-port")
            git(clone, "checkout", "-q", "-b", "lane", "main")
            commit(clone, "work")
            ref, why = self.resolve(clone)
            self.assertEqual(ref, "origin/main")
            self.assertNotIn("retired", why)

    def test_nothing_resolves(self):
        with TemporaryDirectory() as tmp:
            git(tmp, "init", "-q", "-b", "main")
            with self.assertRaises(LookupError):
                self.resolve(Path(tmp))

    def test_cli_prints_ref_and_reason(self):
        out = subprocess.run([sys.executable, str(TOOLS / "lane_base.py"), "--why"], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#", out.stdout)


XC_KNOWN = "Test Case '-[HassUITests.FooTests testBar]' failed (3.2 seconds).\n"
XC_ERROR = "/x/Foo.swift:9: error: -[HassUITests.FooTests testBar] : XCTAssertTrue failed\n"
XC_TOTAL = "Test Suite 'Selected tests' failed at 2026-11-04 10:00:00.000.\n\t Executed 4 tests, with {} failures (0 unexpected) in 3.0 (3.1) seconds\n"
ST_FAIL = "\u2718 Test baz() failed after 0.002 seconds with 1 issue.\n"
ST_RUN = "\u2718 Test run with 3 tests in 1 suites failed after 0.010 seconds with {} issues.\n"


class ParseLogTests(unittest.TestCase):
    def test_xctest_with_matching_totals_is_accounted(self):
        ids, problem = lane_base.parse_log(XC_KNOWN + XC_ERROR + XC_TOTAL.format(1))
        self.assertEqual((ids, problem), (["HassUITests.FooTests.testBar"], None))

    def test_module_stays_in_the_id(self):
        log = (XC_KNOWN.replace("HassUITests", "OtherTests") + XC_ERROR.replace("HassUITests", "OtherTests") + XC_TOTAL.format(1))
        self.assertEqual(lane_base.parse_log(log)[0], ["OtherTests.FooTests.testBar"])

    def test_swift_testing_is_parsed(self):
        ids, problem = lane_base.parse_log(ST_FAIL + ST_RUN.format(1))
        self.assertEqual((ids, problem), (["swift-testing:baz()"], None))

    def test_swift_testing_issue_count_mismatch_is_refused(self):
        self.assertIsNotNone(lane_base.parse_log(ST_FAIL + ST_RUN.format(2))[1])
        self.assertIsNotNone(lane_base.parse_log(ST_FAIL)[1])

    def test_reviewers_three_failure_log_is_refused(self):
        log = (XC_KNOWN + XC_ERROR + ST_FAIL + ST_RUN.format(1) + "Test Case '-[HassUITests.CrashTests testBoom]' started.\n"
               "error: Exited with unexpected signal code 11\n" + XC_TOTAL.format(2))
        self.assertIsNotNone(lane_base.parse_log(log)[1])

    def test_each_crash_and_infra_marker_is_refused(self):
        for marker in ("error: Exited with unexpected signal code 11", "Restarting after unexpected exit, crash, or test timeout",
                       "GAP: no available simulator named 'x' for ipad (a gap, not a pass)", "EMPTY: no tests ran",
                       "INFRA: hung (no output)", "/x/A.swift:3:4: error: cannot find 'x' in scope"):
            log = XC_KNOWN + XC_ERROR + XC_TOTAL.format(1) + marker + "\n"
            self.assertIsNotNone(lane_base.parse_log(log)[1], marker)

    def test_failures_without_a_totals_line_or_with_a_count_mismatch_are_refused(self):
        self.assertIsNotNone(lane_base.parse_log(XC_KNOWN + XC_ERROR)[1])
        self.assertIsNotNone(lane_base.parse_log(XC_KNOWN + XC_ERROR + XC_TOTAL.format(3))[1])
        self.assertIsNotNone(lane_base.parse_log(XC_TOTAL.format(1))[1])  # a failure nobody named

    def test_swift_testing_parses_with_or_without_the_sf_symbol_glyph(self):
        plain = "Test baz() failed after 0.002 seconds with 1 issue.\n" + "Test run with 3 tests in 1 suites failed after 0.010 seconds with 1 issues.\n"
        self.assertEqual(lane_base.parse_log(plain), (["swift-testing:baz()"], None))
        glyph = "\U0010009b Test baz() failed after 0.002 seconds with 1 issue.\n\U0010009b Test run with 3 tests failed after 0.010 seconds with 1 issues.\n"
        self.assertEqual(lane_base.parse_log(glyph), (["swift-testing:baz()"], None))

    def test_clean_log_has_no_ids(self):
        self.assertEqual(lane_base.parse_log("Test Case '-[A.B testC]' passed (1.0 seconds).\n"), ([], None))


class BaselineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.clone = make_repo(self.tmp.name)
        self.ref = "origin/claude/uikit-port"
        patch = mock.patch.dict("os.environ", {"FENTON_AFFECTED_BASE": self.ref})
        patch.start()
        self.addCleanup(patch.stop)
        # A checkout exactly at the base commit (where baselines are recorded) and a lane one commit past it.
        self.base = Path(self.tmp.name) / "base"
        git(self.clone, "worktree", "add", "-q", "--detach", str(self.base), self.ref)
        git(self.clone, "checkout", "-q", "-b", "lane", self.ref)
        commit(self.clone, "work")
        self.sha = git(self.clone, "rev-parse", self.ref)

    def log(self, name, text):
        path = Path(self.tmp.name) / name
        path.write_text(text)
        return str(path)

    def cli(self, cwd, *args):
        env = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "FENTON_AFFECTED_BASE": self.ref, "HOME": self.tmp.name}
        return subprocess.run([sys.executable, str(cwd / "tools" / "lane_base.py"), *args], cwd=cwd, env=env, capture_output=True, text=True)

    def record(self, command, text, *extra):
        return self.cli(self.base, "baseline", "record", "--command", command, "--log", self.log("rec.log", text), *extra)

    def test_store_lives_in_the_main_checkout_for_a_worktree(self):
        self.assertEqual(lane_base.store_dir(self.base), (self.clone / "build" / "baselines").resolve())

    def test_record_takes_ids_from_a_log_only(self):
        no_log = self.cli(self.base, "baseline", "record", "--command", "swift_test", "FooTests.testBar")
        self.assertNotEqual(no_log.returncode, 0)
        self.assertFalse(lane_base.load(self.sha, self.clone)["commands"])
        ok = self.record("swift_test", XC_KNOWN + XC_ERROR + XC_TOTAL.format(1))
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertEqual(lane_base.load(self.sha, self.clone)["commands"]["swift_test"]["failing"], ["HassUITests.FooTests.testBar"])

    def test_record_refuses_off_the_base_commit_or_for_an_unaccounted_log(self):
        off = self.cli(self.clone, "baseline", "record", "--command", "swift_test", "--log",
                       self.log("a.log", XC_KNOWN + XC_ERROR + XC_TOTAL.format(1)))
        self.assertEqual(off.returncode, 2, off.stdout)
        (self.base / "dirty.txt").write_text("x")
        self.assertEqual(self.record("swift_test", XC_KNOWN + XC_ERROR + XC_TOTAL.format(1)).returncode, 2)
        (self.base / "dirty.txt").unlink()
        self.assertEqual(self.record("swift_test", XC_KNOWN + XC_ERROR + XC_TOTAL.format(3)).returncode, 3)
        self.assertFalse(lane_base.load(self.sha, self.clone)["commands"])

    def test_summary_splits_inherited_new_and_unaccounted_and_always_exits_zero(self):
        self.record("swift_test", XC_KNOWN + XC_ERROR + XC_TOTAL.format(1))
        both = XC_KNOWN + XC_ERROR + ST_FAIL + ST_RUN.format(1) + XC_TOTAL.format(1)
        run = self.cli(self.clone, "baseline", "summary", "--command", "swift_test", "--log", self.log("a.log", both))
        self.assertEqual(run.returncode, 0)
        self.assertIn("Already failing on origin/claude/uikit-port", run.stdout)
        self.assertIn("(inherited): HassUITests.FooTests.testBar", run.stdout)
        self.assertIn("New failures: swift-testing:baz()", run.stdout)
        crash = self.cli(self.clone, "baseline", "summary", "--command", "swift_test",
                         "--log", self.log("b.log", XC_KNOWN + XC_ERROR + "error: Exited with unexpected signal code 11\n"))
        self.assertEqual(crash.returncode, 0)
        self.assertIn("Unaccounted:", crash.stdout)
        self.assertNotIn("inherited", crash.stdout)

    def test_summary_without_a_baseline_says_so(self):
        run = self.cli(self.clone, "baseline", "summary", "--command", "swift_test",
                       "--log", self.log("a.log", XC_KNOWN + XC_ERROR + XC_TOTAL.format(1)))
        self.assertEqual(run.returncode, 0)
        self.assertIn("New failures:", run.stdout)
        self.assertIn("no swift_test baseline recorded", run.stdout)

    def test_summary_of_a_missing_or_clean_log_is_silent_and_zero(self):
        for log in (str(Path(self.tmp.name) / "missing.log"), self.log("ok.log", "Test Case '-[A.B testC]' passed (1.0 seconds).\n")):
            run = self.cli(self.clone, "baseline", "summary", "--command", "swift_test", "--log", log)
            self.assertEqual((run.returncode, run.stdout), (0, ""))

    def test_journey_summary_is_per_family(self):
        iphone = "== iphone: iPhone pool (X)\n" + XC_KNOWN + XC_ERROR + XC_TOTAL.format(1)
        ipad = "===== ipad (exit 1) =====\n== ipad: iPad pool (Y)\nGAP: no available simulator named 'x' for ipad (a gap, not a pass)\nTest Case 'x' failed\n"
        self.record("ios_uitest", "== ipad: pool\n" + XC_KNOWN + XC_ERROR + XC_TOTAL.format(1), "--family", "iphone")
        run = self.cli(self.clone, "baseline", "summary", "--command", "ios_uitest", "--log", self.log("run.log", iphone + ipad))
        self.assertEqual(run.returncode, 0)
        self.assertIn("(inherited): iphone:HassUITests.FooTests.testBar", run.stdout)
        self.assertIn("Unaccounted: ipad:", run.stdout)

    def test_a_summary_on_the_base_commit_records_the_baseline(self):
        run = self.cli(self.base, "baseline", "summary", "--command", "swift_test",
                       "--log", self.log("a.log", XC_KNOWN + XC_ERROR + XC_TOTAL.format(1)))
        self.assertEqual(run.returncode, 0)
        self.assertIn("Recorded as the baseline", run.stdout)
        self.assertEqual(lane_base.load(self.sha, self.clone)["commands"]["swift_test"]["failing"], ["HassUITests.FooTests.testBar"])


class ScriptStatusTests(unittest.TestCase):
    """Base-failure reporting must never change a script's pass or fail."""

    ORIGINAL = {
        "ios_uitest.sh": ['STATUS="$(worst "$STATUS" "$fs")"', "fs=0; process_family \"$family\" || fs=$?",
                          "fs=0; wait \"${PIDS[$i]}\" || fs=$?", "exit $STATUS", "if [[ $STATUS == 0 && $ALLOW_EMPTY == 0 ]]; then", "    STATUS=1"],
        "apple_coverage.sh": ["TEST_STATUS=$COV_PHASE_STATUS", "cov_phase swift swift \"$CLASS_DIR/swift-test.log\" -- \\",
                              "if (( TEST_STATUS == 1 )) && python3 \"$ROOT/tools/uitest_support.py\" tally-empty \"$ROOT/apple/.build/swifttest.tally\"; then",
                              "cov_verdict || CLASS_STATUS=$?", "exit \"$CLASS_STATUS\"", "exit \"$GATE_STATUS\""],
    }

    def lines(self, name):
        return (TOOLS / name).read_text().splitlines()

    def test_the_original_status_lines_are_untouched(self):
        for name, wanted in self.ORIGINAL.items():
            lines = [l.strip() for l in self.lines(name)]
            for line in wanted:
                self.assertIn(line.strip(), lines, f"{name}: {line}")

    def test_no_line_that_calls_the_baseline_assigns_a_status_and_each_ends_in_or_true(self):
        for name in self.ORIGINAL:
            calls = [l for l in self.lines(name) if "lane_base.py" in l and "baseline" in l]
            self.assertTrue(calls, name)
            for line in calls:
                self.assertTrue(line.rstrip().endswith("|| true; fi"), line)
                self.assertNotRegex(line, r"(?<![A-Z_])(TEST_)?STATUS=")

    def test_the_glyph_is_not_switched_off(self):
        # log_digest and the coverage classifier read the Swift Testing glyph; the summary parser copes without touching it.
        for name in self.ORIGINAL:
            self.assertNotIn("SWT_SF_SYMBOLS_ENABLED", (TOOLS / name).read_text())

    def test_nothing_else_mentions_lane_base_with_a_status(self):
        for name in self.ORIGINAL:
            text = (TOOLS / name).read_text()
            self.assertNotIn("SUB_RC", text)
            self.assertNotIn("subtract", text)


class IntegrationTests(unittest.TestCase):
    def test_lane_new_records_the_base_and_resolver_reads_it(self):
        with TemporaryDirectory() as tmp:
            clone = make_repo(tmp)
            shutil.copy(TOOLS / "lane_new.sh", clone / "tools" / "lane_new.sh")
            (clone / ".gitignore").write_text(".claude/worktrees/\n")
            git(clone, "add", "-A")
            git(clone, "commit", "-qm", "tools")
            env = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": tmp,
                   "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
            run = subprocess.run(["bash", "tools/lane_new.sh", "w", "--base", "origin/claude/uikit-port"], cwd=clone,
                                 env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(git(clone, "config", "--get", "branch.claude/w.sh-base"), "origin/claude/uikit-port")
            lane = clone / ".claude" / "worktrees" / "w"
            ref, why = lane_base.resolve(lane, {}, NO_PR)
            self.assertEqual(ref, "origin/claude/uikit-port")
            self.assertIn("recorded parent", why)

    def test_lane_new_leaves_an_existing_branchs_recorded_parent_alone(self):
        with TemporaryDirectory() as tmp:
            clone = make_repo(tmp)
            shutil.copy(TOOLS / "lane_new.sh", clone / "tools" / "lane_new.sh")
            (clone / ".gitignore").write_text(".claude/worktrees/\n")
            git(clone, "add", "-A")
            git(clone, "commit", "-qm", "tools")
            git(clone, "branch", "claude/old", "origin/claude/uikit-port")
            git(clone, "config", "branch.claude/old.sh-base", "origin/claude/uikit-port")
            env = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": tmp,
                   "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
            run = subprocess.run(["bash", "tools/lane_new.sh", "old"], cwd=clone, env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(git(clone, "config", "--get", "branch.claude/old.sh-base"), "origin/claude/uikit-port")


if __name__ == "__main__":
    unittest.main()
