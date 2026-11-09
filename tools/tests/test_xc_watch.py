"""Hang watchdogs (``tools/xc_watch.py``) and the UI test helpers (``tools/uitest_support.py``)."""

import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import uitest_support  # noqa: E402
import xc_watch  # noqa: E402


def watch(script, **kwargs):
    """Run a python one-liner under the watchdog (as the scripts do); return (status, stdout)."""
    flags = []
    for name, value in (("--silence", kwargs.get("silence")), ("--wall", kwargs.get("wall")), ("--exit-cap", kwargs.get("exit_cap"))):
        if value is not None:
            flags += [name, str(value)]
    if kwargs.get("expect_tests"):
        flags += ["--expect-tests", str(kwargs["expect_tests"])]
    if kwargs.get("require_tests"):
        flags.append("--require-tests")
    out = subprocess.run([sys.executable, str(TOOLS / "xc_watch.py"), *flags, "--", sys.executable, "-u", "-c", script],
                         capture_output=True, text=True, timeout=120)
    return out.returncode, out.stdout


class WatchTests(unittest.TestCase):
    def test_passes_the_commands_status_and_output_through(self):
        status, text = watch("print('hello'); raise SystemExit(3)", silence=30)
        self.assertEqual((status, text.strip()), (3, "hello"))

    def test_silence_kills_a_hung_command_with_125(self):
        status, text = watch("import time; print('start'); time.sleep(60)", silence=2)
        self.assertEqual(status, xc_watch.HUNG_STATUS)
        self.assertIn("INFRA: hung (no output 2s)", text)

    def test_slow_exit_after_the_suite_passed_takes_the_suites_result(self):
        status, text = watch("import time; print(\"Test Suite 'Selected tests' passed at x\"); time.sleep(60)", exit_cap=2)
        self.assertEqual(status, 0)
        self.assertIn("INFRA: slow exit", text)

    def test_slow_exit_after_the_suite_failed_is_a_failure(self):
        status, _ = watch("import time; print(\"Test Suite 'All tests' failed at x\"); time.sleep(60)", exit_cap=2)
        self.assertEqual(status, 1)

    def test_a_later_bundle_stops_the_exit_clock(self):
        # A plan with a unit-test bundle and a UI-test bundle prints a suite end per bundle; the run is over only after the last.
        script = ("import time; print(\"Test Suite 'All tests' passed at x\"); time.sleep(1); "
                  "print(\"Test Suite 'Selected tests' started at y\"); time.sleep(5); print('Test Case done'); raise SystemExit(0)")
        status, text = watch(script, exit_cap=3)
        self.assertEqual(status, 0)
        self.assertNotIn("INFRA: slow exit", text)
        self.assertIn("Test Case done", text)

    def test_slow_exit_after_only_the_first_bundle_is_not_a_pass(self):
        # Bundle one ends and prints its total; bundle two never starts within the cap.
        script = ("import time; print(\"Test Suite 'All tests' passed at x\"); "
                  "print('\\t Executed 3 tests, with 0 failures'); time.sleep(60)")
        status, text = watch(script, exit_cap=2, expect_tests=10)
        self.assertEqual(status, 1)
        self.assertIn("only 3 of 10 selected tests ran", text)

    def test_slow_exit_with_every_expected_test_run_still_passes(self):
        script = ("import time; print(\"Test Suite 'All tests' passed at x\"); "
                  "print('\\t Executed 3 tests, with 0 failures'); time.sleep(60)")
        status, _ = watch(script, exit_cap=2, expect_tests=3)
        self.assertEqual(status, 0)

    def test_a_failed_bundle_keeps_a_slow_exit_failed(self):
        script = ("import time; print(\"Test Suite 'All tests' failed at x\"); print(\"Test Suite 'Selected tests' started\"); "
                  "print(\"Test Suite 'Selected tests' passed at z\"); time.sleep(60)")
        status, text = watch(script, exit_cap=2)
        self.assertEqual(status, 1)
        self.assertIn("after the suite failed", text)

    def test_a_selection_that_ran_no_tests_fails_when_tests_are_required(self):
        empty = "print(\"Test Suite 'Selected tests' passed at x\"); print('\\t Executed 0 tests, with 0 failures (0 unexpected) in 0.0')"
        status, text = watch(empty, require_tests=True)
        self.assertEqual(status, 1)
        self.assertIn("EMPTY: no tests ran", text)
        self.assertEqual(watch(empty)[0], 0)

    def test_a_family_where_every_test_skipped_passes_with_a_note(self):
        skipped = ("print('\\t Executed 3 tests, with 3 tests skipped and 0 failures (0 unexpected) in 0.1 (0.2) seconds')")
        status, text = watch(skipped, require_tests=True)
        self.assertEqual(status, 0)  # family-gated journeys skip on other families: decided over the whole run
        self.assertIn("NOTE: every selected test skipped", text)
        self.assertNotIn("EMPTY:", text)

    def test_the_tally_records_ran_and_skipped_per_run(self):
        with TemporaryDirectory() as tmp:
            tally = Path(tmp) / "t"
            script = "print('\\t Executed 3 tests, with 3 tests skipped and 0 failures')"
            subprocess.run([sys.executable, str(TOOLS / "xc_watch.py"), "--require-tests", "--tally", str(tally), "--label", "xcodebuild ipad",
                            "--", sys.executable, "-c", script], capture_output=True, text=True, timeout=60)
            subprocess.run([sys.executable, str(TOOLS / "xc_watch.py"), "--require-tests", "--tally", str(tally), "--label", "x iphone",
                            "--", sys.executable, "-c", "print('Executed 0 tests, with 0 failures')"], capture_output=True, text=True, timeout=60)
            self.assertEqual(tally.read_text().splitlines(), ["xcodebuild_ipad 0 3", "x_iphone 0 0 empty"])

    def test_passed_case_lines_floor_the_ran_count(self):
        with TemporaryDirectory() as tmp:
            tally = Path(tmp) / "t"
            script = ("print(\"Test Case '-[A a]' passed (0.1 seconds).\"); print(\"Test Case '-[A b]' skipped (0.1 seconds).\");"
                      "print('\\t Executed 1 test, with 1 test skipped and 0 failures')")
            subprocess.run([sys.executable, str(TOOLS / "xc_watch.py"), "--require-tests", "--tally", str(tally), "--", sys.executable, "-c", script],
                           capture_output=True, text=True, timeout=60)
            self.assertEqual(tally.read_text().split()[1:3], ["1", "1"])

    def test_skipped_test_case_lines_alone_are_not_empty_but_nothing_at_all_is(self):
        script = "print(\"Test Case '-[A a]' skipped (0.1 seconds).\")"
        self.assertEqual(watch(script, require_tests=True)[0], 0)
        self.assertEqual(watch("print('nothing')", require_tests=True)[0], 1)

    def test_some_skipped_and_some_run_is_not_empty(self):
        script = "print('\\t Executed 4 tests, with 1 test skipped and 0 failures (0 unexpected) in 1.0 (1.0) seconds')"
        self.assertEqual(watch(script, require_tests=True)[0], 0)

    def test_swift_testing_tests_count_as_executed(self):
        script = "print('\\t Executed 0 tests, with 0 failures'); print('Test run with 12 tests in 3 suites passed after 1.0 seconds.')"
        self.assertEqual(watch(script, require_tests=True)[0], 0)
        self.assertEqual(watch("print('Test run with 0 tests in 0 suites passed after 0.0 seconds.')", require_tests=True)[0], 1)

    def test_a_later_bundle_that_ran_tests_counts(self):
        both = ("print('\\t Executed 0 tests, with 0 failures'); print('\\t Executed 4 tests, with 0 failures');"
                "print('\\t Executed 0 tests, with 0 failures')")
        self.assertEqual(watch(both, require_tests=True)[0], 0)

    def test_wall_limit_is_124(self):
        status, text = watch("import time; time.sleep(60)", wall=1)
        self.assertEqual(status, xc_watch.WALL_STATUS)
        self.assertIn("exceeded 1s", text)

    def test_cli_requires_a_command(self):
        self.assertEqual(xc_watch.main(["--silence", "5", "--"]), 2)


class SupportTests(unittest.TestCase):
    def make_tree(self, root: Path) -> None:
        tests = root / uitest_support.TEST_DIR
        tests.mkdir(parents=True)
        (tests / "A.swift").write_text("final class AJourneyTests: JourneyTestCase {\n    func testOne() {}\n    func testTwo() {}\n    func helper() {}\n}\n"
                                       "extension AJourneyTests {\n    func testThree() {}\n}\n", encoding="utf-8")
        (tests / "B.swift").write_text("final class BJourneyTests: XCTestCase {\n    func testOnly() {}\n}\n", encoding="utf-8")

    def test_counts_classes_methods_extensions_and_unknowns(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_tree(root)
            self.assertEqual(uitest_support.count([], None, root), 4)
            self.assertEqual(uitest_support.count(["-only-testing:T/AJourneyTests"], None, root), 3)
            self.assertEqual(uitest_support.count(["-only-testing:T/AJourneyTests/testOne", "-only-testing:T/BJourneyTests"], None, root), 2)
            self.assertEqual(uitest_support.count(["-only-testing:T/Missing"], None, root), uitest_support.UNKNOWN_CLASS)

    def test_hosted_hold_counts_the_hosted_tests(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            hosted = root / uitest_support.HOSTED_DIR
            hosted.mkdir(parents=True)
            many = "".join(f"    func testCase{i}() {{}}\n" for i in range(400))
            (hosted / "A.swift").write_text(f"final class AHostedTests: XCTestCase {{\n{many}}}\n", encoding="utf-8")
            (hosted / "B.swift").write_text("final class BHostedTests: XCTestCase {\n    func testOnly() {}\n}\n", encoding="utf-8")
            # 401 tests: 6 s each plus ten minutes, above the 1800 s floor.
            self.assertEqual(uitest_support.hosted_hold([], root), 6 * 401 + 600)
            self.assertEqual(uitest_support.hosted_hold(["BHostedTests"], root), uitest_support.HOSTED_FLOOR)
            self.assertEqual(uitest_support.hosted_hold(["AHostedTests", "Missing"], root), 6 * (400 + uitest_support.UNKNOWN_CLASS) + 600)
            (hosted / "C.swift").write_text("final class CHostedTests: XCTestCase {\n" + many * 3 + "}\n", encoding="utf-8")
            self.assertEqual(uitest_support.hosted_hold([], root), uitest_support.HOLD_CAP)

    def test_plan_selected_tests_bound_the_count(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_tree(root)
            plan = root / "Smoke.xctestplan"
            plan.write_text('{"testTargets": [{"selectedTests": ["BJourneyTests", "AJourneyTests/testOne()"]}]}', encoding="utf-8")
            self.assertEqual(uitest_support.count([], plan, root), 2)
            self.assertEqual(uitest_support.count([], root / "missing.xctestplan", root), 4)

    def test_hold_is_120_per_test_plus_five_minutes_floored_and_capped(self):
        self.assertEqual(uitest_support.hold_for(1), 600)
        self.assertEqual(uitest_support.hold_for(10), 1500)
        self.assertEqual(uitest_support.hold_for(10_000), 7200)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: products_cache.products_key raises without xcodebuild; follow-up hosted-ci-linux-portability")
    def test_products_key_changes_with_settings_and_is_stable_otherwise(self):
        one = uitest_support.products_key(["A=1"])
        self.assertEqual(one, uitest_support.products_key(["A=1"]))
        self.assertNotEqual(one, uitest_support.products_key(["A=2"]))


if __name__ == "__main__":
    unittest.main()
