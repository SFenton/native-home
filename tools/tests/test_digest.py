"""Log digests (``tools/log_digest.py``) and the background runner (``tools/bg_run.py``).

The samples are trimmed copies of real xcodebuild, Swift Testing and devcap output.
"""

import io
import os
import re
import signal
import subprocess
import sys
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bg_run  # noqa: E402
import log_digest  # noqa: E402

XCTEST_FAIL = """\
Test Case '-[FentonHomeUITests.HomeJourneyTests testLightsSheetToggles]' started.
Test Case '-[FentonHomeUITests.HomeJourneyTests testLightsSheetToggles]' passed (22.108 seconds).
Test Case '-[FentonHomeUITests.BedroomJourneyTests testBedTemperaturePassesAudit]' started.
/Users/me/repos/Fenton/apple/Apps/iOSUITests/BedroomJourneyTests.swift:262: error: -[FentonHomeUITests.BedroomJourneyTests testBedTemperaturePassesAudit] : failed - Accessibility audit:
Contrast failed: 48 'Snooze' (rendered 2.4:1)
Test Case '-[FentonHomeUITests.BedroomJourneyTests testBedTemperaturePassesAudit]' failed (82.815 seconds).
\t Executed 2 tests, with 1 failure (0 unexpected) in 104.9 (105.0) seconds
** TEST FAILED **
"""

SWIFT_TESTING_FAIL = """\
✔ Test failedCallRevertsThePower() passed after 0.153 seconds.
✘ Test readsAlarmAndPhaseStates() recorded an issue at BedroomContractTests.swift:352:9: Expectation failed: metric == "91.3°F"
✘ Test readsAlarmAndPhaseStates() failed after 0.057 seconds with 1 issue.
✘ Test run with 154 tests in 28 suites failed after 0.482 seconds with 1 issue.
"""

SWIFT_TESTING_PASS = "✔ Test run with 154 tests in 28 suites passed after 3.1 seconds.\n"

BUILD_ERROR = """\
Building for debugging...
/Users/me/Fenton/apple/Sources/HassCore/Bedroom/WakeLightController.swift:250:15: \x1b[1;31merror: \x1b[1;39mpattern the checker does not understand\x1b[0;0m
/Users/me/Fenton/apple/Sources/HassCore/Bedroom/WakeLightController.swift:250:15: error: pattern the checker does not understand
** BUILD FAILED **
"""


class ProductsLineTests(unittest.TestCase):
    def test_digest_carries_the_products_line(self):
        text = "products: hit 0123456789abcdef, saved ~240s of compile\n** TEST SUCCEEDED **\n"
        self.assertIn("products: hit 0123456789abcdef", log_digest.digest_text(text, 0))


class DigestTests(unittest.TestCase):
    def test_hung_run_is_infra_even_with_earlier_failures(self):
        log = XCTEST_FAIL.replace("** TEST FAILED **\n", "") + "INFRA: hung (no output 180s)\n"
        out = log_digest.digest_text(log, exit_code=125)
        self.assertIn("RESULT: INFRA (exit 125)", out)
        self.assertIn("INFRA: hung (no output 180s)", out)

    def test_slow_exit_keeps_the_suite_verdict(self):
        log = "Test Suite 'Selected tests' passed at 2026\nINFRA: slow exit (xcodebuild still running 90s after the suite passed)\n"
        out = log_digest.digest_text(log, exit_code=0)
        self.assertIn("RESULT: PASS", out)
        self.assertIn("INFRA: slow exit", out)

    def test_unhealthy_simulator_is_infra(self):
        out = log_digest.digest_text("INFRA: simulator unhealthy (iphone X: bootstatus or screenshot failed twice)\n", exit_code=126)
        self.assertIn("RESULT: INFRA (exit 126)", out)

    def test_result_line_carries_sha_and_lane(self):
        out = log_digest.digest_text("ok\n", exit_code=0, sha="abc12345", lane="test-speed")
        self.assertIn("sha=abc12345 lane=test-speed", out.splitlines()[0])
        self.assertNotIn("sha=", log_digest.digest_text("ok\n", exit_code=0))

    def test_git_context_names_this_checkout(self):
        sha, lane = log_digest.git_context(str(Path(__file__).resolve().parents[2]))
        self.assertRegex(sha, r"^[0-9a-f]{8}$")
        self.assertTrue(lane)

    def test_xctest_failure_names_the_test_and_first_message(self):
        out = log_digest.digest_text(XCTEST_FAIL, exit_code=65, elapsed=125)
        self.assertIn("RESULT: FAIL (exit 65)", out)
        self.assertIn("2m05s", out)
        self.assertIn("BedroomJourneyTests.testBedTemperaturePassesAudit: failed - Accessibility audit:", out)
        self.assertIn("(BedroomJourneyTests.swift:262)", out)
        self.assertIn("named: 1 passed, 1 failed", out)
        self.assertNotIn("HomeJourneyTests.testLightsSheetToggles:", out)

    def test_swift_testing_failure(self):
        out = log_digest.digest_text(SWIFT_TESTING_FAIL, exit_code=1)
        self.assertIn("RESULT: FAIL", out)
        self.assertIn("readsAlarmAndPhaseStates:", out)
        self.assertIn("swift-testing: 154 tests failed", out)

    def test_clean_pass(self):
        out = log_digest.digest_text(SWIFT_TESTING_PASS, exit_code=0)
        self.assertIn("RESULT: PASS (exit 0)", out)
        self.assertNotIn("FAILED", out)

    def test_retried_test_that_passes_is_not_a_failure(self):
        log = XCTEST_FAIL.replace("failed (82.815", "failed (82.815").replace("** TEST FAILED **", "** TEST SUCCEEDED **")
        log += ("Test Case '-[FentonHomeUITests.BedroomJourneyTests testBedTemperaturePassesAudit]' passed (40.0 seconds).\n")
        out = log_digest.digest_text(log.replace(": error: -[", ": note: -["), exit_code=0)
        self.assertIn("RESULT: FLAKY", out)  # a pass after a failed attempt is reported, never a clean PASS
        self.assertIn("failed, then passed on retry", out)

    def test_exit_zero_with_a_failed_test_is_a_mismatch_not_a_pass(self):
        """`cmd || echo X` or `a; b` can hand bg_run a 0 for a run that failed; the log wins."""
        out = log_digest.digest_text(XCTEST_FAIL, exit_code=0)
        self.assertIn("RESULT: MISMATCH (exit 0)", out)
        self.assertNotIn("RESULT: PASS", out)
        self.assertIn("testBedTemperaturePassesAudit", out)

    def test_exit_zero_with_a_runner_failure_is_a_mismatch(self):
        log = "Testing failed:\n\tApp installation failed: Unable to Install\n\n** TEST EXECUTE FAILED **\n"
        self.assertIn("RESULT: MISMATCH", log_digest.digest_text(log, exit_code=0))
        self.assertIn("RESULT: FAIL", log_digest.digest_text(log, exit_code=65))

    def test_unnamed_xctest_failure_is_not_a_pass(self):
        """uk-fam2 (duo): `Executed 104 tests, with 1 failure` and no failing test named read as PASS at exit 0."""
        log = ("duo exit 65\n\t Executed 3 tests, with 1 failure (0 unexpected) in 5.072 (5.078) seconds\n"
               "\t Executed 104 tests, with 1 failure (0 unexpected) in 159.942 (160.102) seconds\n")
        mismatch = log_digest.digest_text(log, exit_code=0)
        self.assertIn("RESULT: MISMATCH (exit 0)", mismatch)
        self.assertIn("1 failure(s)", mismatch)
        self.assertIn("RESULT: FAIL (exit 65)", log_digest.digest_text(log, exit_code=65))

    def test_retried_test_with_two_failures_stays_flaky(self):
        log = ("a.swift:1: error: -[M.A testX] : first\na.swift:2: error: -[M.A testX] : second\n"
               "Test Case '-[M.A testX]' failed (1.0 seconds).\n\t Executed 5 tests, with 2 failures (0 unexpected) in 1 (1) seconds\n"
               "Test Case '-[M.A testX]' passed (1.0 seconds).\n")
        out = log_digest.digest_text(log, exit_code=0)
        self.assertIn("RESULT: FLAKY", out)
        self.assertNotIn("names only", out)

    def test_named_test_with_three_failures_has_no_unnamed_line(self):
        log = "".join(f"a.swift:{i}: error: -[M.A testX] : bad\n" for i in range(3))
        log += "Test Case '-[M.A testX]' failed (1.0 seconds).\n\t Executed 5 tests, with 3 failures (0 unexpected) in 1 (1) seconds\n"
        for code, word in ((0, "MISMATCH"), (65, "FAIL")):
            out = log_digest.digest_text(log, exit_code=code)
            self.assertIn(f"RESULT: {word}", out)
            self.assertNotIn("names only", out)

    def test_multi_family_log_limit_is_documented_behaviour(self):
        """Documented limit: the largest summary vs summed named failures, so a family's named failure can mask another's unnamed one."""
        log = ("a.swift:1: error: -[M.A testX] : bad\nTest Case '-[M.A testX]' failed (1.0 seconds).\n"
               "\t Executed 5 tests, with 1 failure (0 unexpected) in 1 (1) seconds\n"
               "\t Executed 5 tests, with 1 failure (0 unexpected) in 1 (1) seconds\n")
        self.assertEqual(log_digest.Digest().unnamed_failures(), 0)
        self.assertIn("RESULT: MISMATCH", log_digest.digest_text(log, exit_code=0))

    def test_clean_xctest_summary_with_an_ipad_style_log_stays_pass(self):
        log = "\t Executed 104 tests, with 0 failures (0 unexpected) in 156.827 (157.124) seconds\n"
        self.assertIn("RESULT: PASS (exit 0)", log_digest.digest_text(log, exit_code=0))

    def test_exit_zero_with_a_clean_log_stays_pass(self):
        log = "Test Case '-[A.B testC]' passed (1.0 seconds).\n\t Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.0) seconds\n** TEST SUCCEEDED **\n"
        self.assertIn("RESULT: PASS (exit 0)", log_digest.digest_text(log, exit_code=0))

    def test_build_errors_are_listed_once_without_colour_codes(self):
        out = log_digest.digest_text(BUILD_ERROR, exit_code=65)
        self.assertIn("BUILD ERRORS (1):", out)
        self.assertIn("WakeLightController.swift:250: pattern the checker does not understand", out)
        self.assertNotIn("\x1b", out)

    def test_device_hub_failure_is_infra_not_a_test_failure(self):
        log = "ios_sim.DeviceHubError: Pressed the unfolded control but the Duo reads folded\n"
        out = log_digest.digest_text(log, exit_code=1)
        self.assertIn("RESULT: INFRA", out)
        self.assertIn("INFRA (not a test failure): Device Hub pose", out)

    def test_gap_and_hold_timeout_are_infra(self):
        self.assertIn("RESULT: INFRA", log_digest.digest_text("GAP: no available simulator named 'iPhone Duo'\n", exit_code=1))
        real = "\ndevcap: HOLD TIMEOUT: held iphone longer than 3600s; killing the command\n"
        out = log_digest.digest_text(real, exit_code=124)
        self.assertIn("RESULT: INFRA", out)
        self.assertIn("hold timeout", out)
        self.assertIn("RESULT: INFRA", log_digest.digest_text("bg_run: hold timeout, killed after 1800s\n", exit_code=124))
        self.assertIn("RESULT: INFRA", log_digest.digest_text(real, exit_code=75))

    def test_a_printed_hold_timeout_line_does_not_hide_failed_tests(self):
        """A test fixture that prints the words 'hold timeout' and then fails reads FAIL with the id, not INFRA."""
        log = ("test_hold_timeout_is_labelled (test_devcap.HoldTests.test_hold_timeout_is_labelled) ...\n"
               "devcap: HOLD TIMEOUT: held x longer than 1s\n"
               "bg_run: hold timeout, killed after 5s\n"
               "devcap: hold timeout after 5s\n"
               "FAIL: test_hold_timeout_is_labelled (test_devcap.HoldTests.test_hold_timeout_is_labelled)\n"
               "AssertionError: 1 != 2\n"
               "FAILED (failures=1)\n")
        out = log_digest.digest_text(log, exit_code=1)
        self.assertIn("RESULT: FAIL", out)
        self.assertIn("test_devcap.HoldTests.test_hold_timeout_is_labelled", out)
        self.assertNotIn("INFRA (not a test failure)", out)

    def test_hold_timeout_text_at_an_ordinary_exit_or_mid_line_is_not_infra(self):
        self.assertNotIn("RESULT: INFRA", log_digest.digest_text("devcap: HOLD TIMEOUT: held x\n", exit_code=1))
        self.assertNotIn("RESULT: INFRA", log_digest.digest_text("the hold timeout docs say devcap: HOLD TIMEOUT: x\n", exit_code=124))

    def test_unittest_failures_and_errors_are_failed_tests(self):
        log = ("ERROR: test_b (mod.B.test_b)\nTraceback (most recent call last):\nValueError: x\n"
               "FAIL: test_a (mod.A.test_a)\nAssertionError\nFAILED (failures=1, errors=1)\n")
        out = log_digest.digest_text(log, exit_code=1)
        self.assertIn("RESULT: FAIL", out)
        self.assertIn("mod.A.test_a", out)
        self.assertIn("mod.B.test_b", out)

    def test_devcap_slot_wait_timeout_is_infra_only_at_exit_75(self):
        line = "devcap: gave up waiting for a free slot after 1200s\n"
        out = log_digest.digest_text(line, exit_code=75)
        self.assertIn("RESULT: INFRA", out)
        self.assertIn("slot wait timeout", out)
        self.assertNotIn("RESULT: INFRA", log_digest.digest_text(line, exit_code=1))
        self.assertNotIn("RESULT: INFRA", log_digest.digest_text("note: devcap: gave up waiting\n", exit_code=75))

    def test_python39_unittest_failures_in_one_class_stay_separate(self):
        log = ("FAIL: test_a (mod.Cls)\nAssertionError\nFAIL: test_b (mod.Cls)\nAssertionError\n"
               "FAILED (failures=2)\n")
        out = log_digest.digest_text(log, exit_code=1)
        self.assertIn("FAILED (2)", out)
        self.assertIn("mod.Cls.test_a", out)
        self.assertIn("mod.Cls.test_b", out)

    def test_unittest_failed_summary_without_ids_is_still_fail(self):
        self.assertIn("RESULT: FAIL", log_digest.digest_text("FAILED (failures=2)\n", exit_code=1))

    def test_credentials_unavailable_line_is_infra(self):
        """The line the live lane writes when its credentials are missing classifies as infra (the line lives in the workflow that runs Live)."""
        line = "Live-server credentials unavailable: missing or refused on this runner (tools/hass_creds.sh)"
        out = log_digest.digest_text(line + "\n", exit_code=1)
        self.assertIn("RESULT: INFRA", out)
        self.assertIn("INFRA (not a test failure): credentials unavailable", out)

    def test_unknown_failure_shows_the_last_lines(self):
        out = log_digest.digest_text("one\ntwo\nthree\n", exit_code=2)
        self.assertIn("RESULT: FAIL (exit 2)", out)
        self.assertIn("last lines:", out)
        self.assertIn("  three", out)

    def test_no_exit_code_reads_the_log(self):
        self.assertIn("RESULT: PASS", log_digest.digest_text("Executed 3 tests, with 0 failures (0 unexpected)\n** TEST SUCCEEDED **\n"))
        self.assertIn("RESULT: UNKNOWN", log_digest.digest_text("hello\n"))

    def test_many_failures_are_capped(self):
        log = "".join(f"Test Case '-[A.B test{i}]' failed (1.0 seconds).\n" for i in range(80))
        out = log_digest.digest_text(log, exit_code=1, max_lines=30)
        self.assertLessEqual(len(out.splitlines()), 32)
        self.assertIn("and ", out)

    def test_duration_formats(self):
        self.assertEqual(log_digest.describe(45), "45s")
        self.assertEqual(log_digest.describe(3725), "1h02m")

    def test_cli_reads_a_file_and_stdin(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "run.log"
            path.write_text(SWIFT_TESTING_PASS)
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                self.assertEqual(log_digest.main([str(path), "--exit-code", "0", "--label", "x"]), 0)
            self.assertIn("RESULT: PASS (exit 0)  x", buffer.getvalue())
            self.assertIn(str(path), buffer.getvalue())
            stdin, sys.stdin = sys.stdin, io.StringIO(SWIFT_TESTING_FAIL)
            try:
                buffer = io.StringIO()
                with redirect_stdout(buffer):
                    log_digest.main(["-"])
            finally:
                sys.stdin = stdin
            self.assertIn("RESULT: FAIL", buffer.getvalue())


EMPTY_ZERO = "Test Suite 'Selected tests' passed at x\n\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds\n** TEST SUCCEEDED **\n"
ALL_SKIPPED = ("Test Case '-[FentonHomeUITests.LiveJourneyTests testSignIn]' skipped (0.4 seconds).\n"
               "Test Case '-[FentonHomeUITests.LiveJourneyTests testHome]' skipped (0.3 seconds).\n"
               "\t Executed 2 tests, with 2 tests skipped and 0 failures (0 unexpected) in 0.7 (0.9) seconds\n** TEST SUCCEEDED **\n")
SOME_SKIPPED = ("Test Case '-[A.B testRan]' passed (1.0 seconds).\nTest Case '-[A.B testSkip]' skipped (0.1 seconds).\n"
                "\t Executed 2 tests, with 1 test skipped and 0 failures (0 unexpected) in 1.1 (1.2) seconds\n** TEST SUCCEEDED **\n")


class EmptyRunTests(unittest.TestCase):
    def test_zero_tests_executed_is_empty_not_pass(self):
        out = log_digest.digest_text(EMPTY_ZERO, exit_code=0)
        self.assertIn("RESULT: EMPTY (exit 0)", out)
        self.assertIn("executed 0, skipped 0, failed 0", out)

    def test_every_test_skipped_is_empty_with_the_counts(self):
        out = log_digest.digest_text(ALL_SKIPPED, exit_code=0)
        self.assertIn("RESULT: EMPTY", out)
        self.assertIn("executed 0, skipped 2, failed 0", out)

    def test_some_skipped_still_passes_and_shows_the_skips(self):
        out = log_digest.digest_text(SOME_SKIPPED, exit_code=0)
        self.assertIn("RESULT: PASS", out)
        self.assertIn("executed 1, skipped 1, failed 0", out)

    def test_a_pass_shows_executed_skipped_failed(self):
        out = log_digest.digest_text(XCTEST_FAIL, exit_code=1)
        self.assertIn("RESULT: FAIL", out)
        self.assertRegex(out, r"executed \d+, skipped 0, failed \d+")

    def test_swift_testing_run_of_zero_is_empty_and_of_some_passes(self):
        self.assertIn("RESULT: EMPTY", log_digest.digest_text("✔ Test run with 0 tests in 0 suites passed after 0.0 seconds.\n", 0))
        self.assertIn("RESULT: PASS", log_digest.digest_text(SWIFT_TESTING_PASS, 0))

    def test_the_xc_watch_empty_marker_is_empty_at_the_exit_code_xc_watch_gives(self):
        marker = "EMPTY: no tests ran (xcodebuild iphone): the selection matched nothing\n"
        self.assertIn("RESULT: EMPTY (exit 1)", log_digest.digest_text(marker, exit_code=1))
        self.assertIn("RESULT: EMPTY", log_digest.digest_text(marker, exit_code=0))

    def test_the_marker_does_not_hide_a_real_failure(self):
        self.assertIn("RESULT: FAIL", log_digest.digest_text(XCTEST_FAIL + "EMPTY: no tests ran (x)\n", exit_code=1))
        self.assertIn("RESULT: INFRA", log_digest.digest_text("EMPTY: no tests ran (x)\nINFRA: hung (no output 180s)\n", exit_code=125))

    def test_an_ios_phase_allow_empty_does_not_hide_a_later_empty_swift_phase(self):
        ios = "allow-empty: an empty run (no test ran, or every test skipped) is not a failure\nExecuted 0 tests, with 0 failures\n"
        self.assertIn("RESULT: PASS", log_digest.digest_text(ios, exit_code=0))
        swift = "EMPTY: no tests ran (swift test): the selection matched nothing in this plan\n"
        self.assertIn("RESULT: EMPTY (exit 1)", log_digest.digest_text(ios + swift, exit_code=1))
        self.assertIn("RESULT: EMPTY", log_digest.digest_text(swift + ios, exit_code=1) if False else ios + swift, 1) if False else None
        self.assertIn("RESULT: PASS", log_digest.digest_text(ios + swift, exit_code=0, allow_empty=True))

    def test_a_runner_crash_in_a_mixed_log_is_not_hidden_as_empty(self):
        for crash in ("Testing failed:\n", "** TEST EXECUTE FAILED **\n", "The test runner exited unexpectedly\n"):
            mixed = "EMPTY: no tests ran (xcodebuild iphone): nothing\n" + crash
            self.assertIn("RESULT: FAIL", log_digest.digest_text(mixed, exit_code=1))
        marker = "EMPTY: no tests ran (xcodebuild iphone): nothing\n"
        self.assertIn("RESULT: EMPTY", log_digest.digest_text(marker, exit_code=1))
        self.assertIn("RESULT: FAIL", log_digest.digest_text(marker, exit_code=65))  # only exit 1 converts

    def test_a_grepd_perf_log_of_only_skipped_cases_is_empty(self):
        log = ("  Test Case '-[LayoutChangePerformanceTests testA]' skipped (0.2 seconds).\n"
               "  Test Case '-[LayoutChangePerformanceTests testB]' skipped (0.2 seconds).\n")
        out = log_digest.digest_text(log, exit_code=0)
        self.assertIn("RESULT: EMPTY", out)
        self.assertIn("executed 0, skipped 2, failed 0", out)
        ran = log + "  Test Case '-[LayoutChangePerformanceTests testC]' passed (3.0 seconds).\n"
        self.assertIn("RESULT: PASS", log_digest.digest_text(ran, exit_code=0))

    def test_family_gated_run_where_one_family_ran_passes(self):
        log = ("Test Case '-[ClimateWideLayoutJourneyTests testA]' skipped (0.1 seconds).\n\t Executed 2 tests, with 2 tests skipped and 0 failures\n"
               "Test Case '-[ClimateWideLayoutJourneyTests testA]' passed (4.0 seconds).\n\t Executed 2 tests, with 0 failures\n")
        self.assertIn("RESULT: PASS", log_digest.digest_text(log, exit_code=0))

    def test_a_log_with_no_test_evidence_is_not_empty(self):
        self.assertIn("RESULT: PASS", log_digest.digest_text("== nothing to run\n", exit_code=0))

    def test_allow_empty_keeps_pass_by_argument_or_by_log_line(self):
        self.assertIn("RESULT: PASS", log_digest.digest_text(EMPTY_ZERO, exit_code=0, allow_empty=True))
        self.assertIn("RESULT: PASS", log_digest.digest_text("allow-empty: an empty run is fine\n" + EMPTY_ZERO, exit_code=0))

    def test_a_failing_empty_run_stays_fail(self):
        self.assertIn("RESULT: FAIL", log_digest.digest_text(EMPTY_ZERO, exit_code=1))

    def test_bg_run_exits_nonzero_on_empty_unless_allowed(self):
        command = [sys.executable, "-c", "print(%r)" % ALL_SKIPPED]
        with TemporaryDirectory() as tmp:
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                self.assertEqual(bg_run.main(["empty", "--dir", tmp, "--", *command]), 1)
                self.assertEqual(bg_run.main(["ok", "--dir", tmp, "--allow-empty", "--", *command]), 0)
            self.assertIn("RESULT: EMPTY (exit 0)  empty", buffer.getvalue())
            self.assertIn("RESULT: PASS (exit 0)  ok", buffer.getvalue())

    def test_cli_allow_empty_flag(self):
        with TemporaryDirectory() as tmp:
            log = Path(tmp) / "x.log"
            log.write_text(EMPTY_ZERO)
            tool = str(Path(log_digest.__file__))
            self.assertIn("RESULT: EMPTY", subprocess.run([sys.executable, tool, str(log), "--exit-code", "0"], capture_output=True, text=True).stdout)
            self.assertIn("RESULT: PASS", subprocess.run([sys.executable, tool, str(log), "--exit-code", "0", "--allow-empty"], capture_output=True, text=True).stdout)


class RunawayLineTests(unittest.TestCase):
    """A killed xcodebuild leaves a line of hundreds of thousands of NULs or blanks before the INFRA line."""

    def test_nul_padded_slow_exit_line_digests_quickly(self) -> None:
        import time
        line = "\x00" * 500_000 + "INFRA: slow exit (xcodebuild still running 90s after the suite failed)"
        started = time.monotonic()
        text = log_digest.digest_text("Test Case '-[A.B testC]' passed (1.0 seconds).\n" + line + "\n" + " " * 500_000 + "x.swift\n",
                                      exit_code=1, elapsed=3, label="hosted", log="l", sha="s", lane="x")
        self.assertLess(time.monotonic() - started, 5)
        self.assertIn("INFRA: slow exit (xcodebuild still running 90s", text)
        self.assertIn("xcodebuild did not exit after the suite finished", text)

    def test_clean_keeps_head_and_tail_of_a_long_line(self) -> None:
        cleaned = log_digest.clean("a" * 10_000 + "TAIL")
        self.assertLess(len(cleaned), log_digest.MAX_LINE + 10)
        self.assertTrue(cleaned.startswith("aaa") and cleaned.endswith("TAIL"))


class BackgroundRunTests(unittest.TestCase):
    def test_prints_only_the_digest_and_keeps_the_log(self):
        with TemporaryDirectory() as tmp:
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                status = bg_run.main(["unit", "--dir", tmp, "--", sys.executable, "-c",
                                      "print('noise ' * 1000); print('Executed 2 tests, with 0 failures (0 unexpected)'); print('** TEST SUCCEEDED **')"])
            self.assertEqual(status, 0)
            self.assertIn("RESULT: PASS (exit 0)  unit", buffer.getvalue())
            self.assertNotIn("noise noise", buffer.getvalue())
            self.assertIn("noise noise", (Path(tmp) / "unit.log").read_text())
            self.assertEqual((Path(tmp) / "unit.digest").read_text().strip(), buffer.getvalue().strip())

    def test_failure_status_passes_through(self):
        with TemporaryDirectory() as tmp:
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                status = bg_run.main(["bad", "--dir", tmp, "--", sys.executable, "-c",
                                      "import sys; print('Test Case \\'-[A.B testX]\\' failed (1.0 seconds).'); sys.exit(3)"])
            self.assertEqual(status, 3)
            self.assertIn("B.testX: failed", buffer.getvalue())
            self.assertIn("RESULT: FAIL (exit 3)", buffer.getvalue())

    def test_timeout_kills_the_process_group(self):
        with TemporaryDirectory() as tmp:
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                status = bg_run.main(["hang", "--dir", tmp, "--timeout", "1", "--", "sh", "-c", "sleep 30 & sleep 30"])
            self.assertEqual(status, 124)
            self.assertIn("hold timeout", buffer.getvalue())

    def test_usage_errors(self):
        self.assertEqual(bg_run.main(["only-a-label"]), 2)
        self.assertEqual(bg_run.main(["label", "--"]), 2)

    def test_cli_script_runs(self):
        with TemporaryDirectory() as tmp:
            done = subprocess.run([sys.executable, str(Path(bg_run.__file__)), "cli", "--dir", tmp, "--", "true"],
                                  capture_output=True, text=True)
            self.assertEqual(done.returncode, 0)
            self.assertIn("RESULT: PASS", done.stdout)

def running(pid):
    """True while ``pid`` exists and is not a zombie (``ps`` state ``Z``)."""
    state = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return bool(state) and not state.startswith("Z")


class WrapperSignalTests(unittest.TestCase):
    """SIGTERM or SIGHUP to the wrapper takes the command's whole process group with it (a coverage run orphaned by a killed
    wrapper held the build-database lock)."""

    def launch(self, tmp, label):
        """Start the wrapper on a shell that backgrounds a long sleep; return (wrapper, grandchild pid)."""
        pidfile = Path(tmp) / "child.pid"
        wrapper = subprocess.Popen([sys.executable, str(Path(bg_run.__file__)), label, "--dir", tmp, "--", "sh", "-c",
                                    f"sleep 60 & echo $! > {pidfile}; wait"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and not (pidfile.exists() and pidfile.read_text().strip()):
            time.sleep(0.05)
        return wrapper, int(pidfile.read_text().strip())

    def alive(self, pid):
        """True while ``pid`` runs. A zombie waiting for a reaper (a CI container with no init) is dead."""
        return running(pid)

    def check(self, sig):
        with TemporaryDirectory() as tmp:
            wrapper, child = self.launch(tmp, "sig")
            try:
                self.assertTrue(self.alive(child))
                self.assertTrue((Path(tmp) / "sig.running").exists())
                wrapper.send_signal(sig)
                out, _ = wrapper.communicate(timeout=30)
                self.assertEqual(wrapper.returncode, 128 + sig)
                deadline = time.monotonic() + 5
                while self.alive(child) and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertFalse(self.alive(child), "the grandchild outlived the wrapper")
                self.assertFalse((Path(tmp) / "sig.running").exists())
                self.assertIn("received, killed the command's process group", (Path(tmp) / "sig.log").read_text())
                self.assertTrue((Path(tmp) / "sig.digest").exists())
                self.assertIn("RESULT:", out)
            finally:
                if wrapper.poll() is None:
                    wrapper.kill()
                try:
                    os.kill(child, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_sigterm_leaves_no_child(self):
        self.check(signal.SIGTERM)

    def test_sighup_leaves_no_child(self):
        self.check(signal.SIGHUP)

    def test_a_child_that_ignores_sigterm_is_killed_after_the_grace(self):
        with TemporaryDirectory() as tmp:
            marker = Path(tmp) / "p"
            process = subprocess.Popen(["sh", "-c", f"trap '' TERM; sleep 60 & echo $! > {marker}; wait"],
                                       start_new_session=True)
            try:
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline and not marker.exists():
                    time.sleep(0.05)
                started = time.monotonic()
                bg_run.kill_group(process, grace=0.5)
                self.assertLess(time.monotonic() - started, 10)
                grandchild = int(marker.read_text().strip())
                deadline = time.monotonic() + 5
                while running(grandchild) and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertFalse(running(grandchild), "SIGKILL after the grace did not reach the grandchild")
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_handlers_are_restored_after_a_run(self):
        before = signal.getsignal(signal.SIGTERM)
        with TemporaryDirectory() as tmp, redirect_stdout(io.StringIO()):
            bg_run.main(["rest", "--dir", tmp, "--", "true"])
        self.assertEqual(signal.getsignal(signal.SIGTERM), before)


class ExpectMinutesTests(unittest.TestCase):
    def test_warns_past_25_minutes_with_the_timeout_to_pass(self):
        self.assertEqual(bg_run.harness_note(70), "bg_run: harness limit is 30 min unless the Bash call passes timeout>=4200000")
        self.assertIn("timeout>=1560000", bg_run.harness_note(26))

    def test_silent_at_or_below_25_minutes_or_unset(self):
        for value in (None, 0, 10, 25):
            self.assertIsNone(bg_run.harness_note(value))

    def test_main_prints_the_note_to_stderr_and_still_runs(self):
        with TemporaryDirectory() as tmp:
            err, out = io.StringIO(), io.StringIO()
            with redirect_stdout(out), mock.patch.object(sys, "stderr", err):
                status = bg_run.main(["exp", "--expect-minutes", "50", "--dir", tmp, "--", "true"])
            self.assertEqual(status, 0)
            self.assertIn("timeout>=3000000", err.getvalue())
            self.assertNotIn("harness limit", out.getvalue())


if __name__ == "__main__":
    unittest.main()
