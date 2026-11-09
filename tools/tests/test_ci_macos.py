"""tools/ci_macos.sh: the phases of the one hosted macOS job, run against stub scripts (no simulator, no Xcode)."""

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "ci_macos.sh"

#: Logs its arguments; fails when STUB_FAIL names the script (e.g. "settle").
STUB = '#!/bin/bash\necho "$(basename "$0") $*${FENTON_SIM_SLIM:+ [FENTON_SIM_SLIM=$FENTON_SIM_SLIM]}" >> "$STUB_LOG"\n[ "$STUB_FAIL" = "$(basename "$0")" ] && exit "${STUB_RC:-1}"\nexit 0\n'
HEARTBEAT = '#!/bin/bash\necho "heartbeat $*" >> "$STUB_LOG"\nshift 2\nexec "$@"\n'
#: A selection tool: prints STUB_RUNNABLE for a --plan Gate call and STUB_ALL otherwise.
AFFECTED = '#!/bin/bash\nfor a in "$@"; do [ "$a" = Gate ] && { echo -n "$STUB_RUNNABLE"; exit "${STUB_AFFECTED_RC:-0}"; }; done\necho -n "$STUB_ALL"\n'


class CiMacosTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        for name, body in (("uitest", STUB), ("settle", STUB), ("slim", STUB), ("heartbeat", HEARTBEAT), ("affected", AFFECTED), ("release", STUB), ("swift", STUB)):
            (self.dir / name).write_text(body)
            (self.dir / name).chmod(0o755)
        self.log = self.dir / "log"
        self.timings = self.dir / "timings.tsv"

    def run_script(self, *args, **extra):
        env = {"CI_MACOS_UITEST": str(self.dir / "uitest"), "CI_MACOS_SETTLE": str(self.dir / "settle"), "CI_MACOS_SLIM": str(self.dir / "slim"),
               "CI_MACOS_HEARTBEAT": str(self.dir / "heartbeat"), "CI_MACOS_AFFECTED": str(self.dir / "affected"),
               "CI_MACOS_TIMINGS": str(self.timings), "CI_MACOS_RELEASE": str(self.dir / "release"), "CI_MACOS_SWIFT": str(self.dir / "swift"), "FENTON_AFFECTED_BASE": "", "STUB_LOG": str(self.log), "STUB_FAIL": "", "STUB_RUNNABLE": "", "STUB_ALL": "",
               "GITHUB_STEP_SUMMARY": str(self.dir / "summary")}
        env.update(extra)
        with mock.patch.dict("os.environ", env):
            out = subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True, timeout=60)
        return out, (self.log.read_text() if self.log.exists() else "")

    def phases(self):
        return [line.split("\t") for line in self.timings.read_text().splitlines()] if self.timings.exists() else []

    def test_build_runs_once_build_only_under_the_heartbeat_and_is_timed(self):
        out, log = self.run_script("build")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("uitest --only iphone --plan Smoke --force --build-only", log)
        self.assertTrue(log.startswith("heartbeat run"))
        self.assertEqual([p[0] for p in self.phases()], ["build"])

    def test_one_device_boots_and_settles_before_its_smoke_run(self):
        out, log = self.run_script("smoke", "duo")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertLess(log.index("settle duo"), log.index("uitest --only duo --plan Smoke --force"))
        self.assertEqual([p[0] for p in self.phases()], ["slim-duo", "boot-duo", "smoke-duo"])

    def test_a_device_is_slimmed_after_the_idle_runner_and_before_it_settles(self):
        _, log = self.run_script("smoke", "iphone")
        self.assertLess(log.index("release"), log.index("slim iphone"))
        self.assertLess(log.index("slim iphone"), log.index("settle iphone"))

    def test_a_slimmed_device_is_recorded_slimmed_and_its_smoke_run_is_untouched(self):
        out, log = self.run_script("smoke", "duo")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(self.phases()[0][0::2], ["slim-duo", "slimmed"])
        self.assertNotIn("FENTON_SIM_SLIM", log)

    def test_a_device_left_stock_is_recorded_stock_and_its_smoke_run_is_told_not_to_slim(self):
        out, log = self.run_script("smoke", "ipad", STUB_FAIL="slim", STUB_RC="3")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(self.phases()[0][0::2], ["slim-ipad", "stock"])
        self.assertIn("uitest --only ipad --plan Smoke --force [FENTON_SIM_SLIM=0]", log)

    def test_a_slim_the_check_could_not_confirm_is_recorded_and_not_slimmed_again(self):
        out, log = self.run_script("smoke", "duo", STUB_FAIL="slim", STUB_RC="4")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(self.phases()[0][0::2], ["slim-duo", "slimmed-unverified"])
        self.assertIn("[FENTON_SIM_SLIM=0]", log)

    def test_a_failed_slim_leaves_the_device_stock_and_the_run_goes_ahead(self):
        out, log = self.run_script("smoke", "ipad", STUB_FAIL="slim")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("uitest --only ipad --plan Smoke --force", log)

    def test_a_failed_settle_does_not_stop_the_smoke_run_and_a_failed_run_fails_the_step(self):
        out, log = self.run_script("smoke", "ipad", STUB_FAIL="settle")
        self.assertEqual(out.returncode, 0)
        self.assertIn("uitest --only ipad", log)
        out, _ = self.run_script("smoke", "ipad", STUB_FAIL="uitest")
        self.assertEqual(out.returncode, 1)
        self.assertEqual(self.phases()[-1][2], "1")

    def test_all_is_not_a_device(self):
        self.assertEqual(self.run_script("smoke", "all")[0].returncode, 2)
        self.assertEqual(self.run_script("journeys", "all")[0].returncode, 2)

    def test_journeys_run_when_the_diff_reaches_a_runnable_one(self):
        out, log = self.run_script("journeys", "iphone", STUB_RUNNABLE="A", STUB_ALL="A")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("uitest --only iphone --changed --force", log)

    def test_journeys_skip_when_gate_runs_none_of_the_ones_the_diff_reaches(self):
        out, log = self.run_script("journeys", "duo", STUB_RUNNABLE="", STUB_ALL="LiveOnly")
        self.assertEqual(out.returncode, 0)
        self.assertIn("skipped", out.stdout)
        self.assertNotIn("uitest", log)

    def test_journeys_skip_when_the_diff_reaches_no_journey_at_all(self):
        out, log = self.run_script("journeys", "iphone", STUB_RUNNABLE="", STUB_ALL="")
        self.assertEqual(out.returncode, 0)
        self.assertIn("skipped", out.stdout)
        self.assertNotIn("uitest", log)

    def test_journeys_with_a_file_needing_a_pick_still_go_to_the_runner(self):
        """Exit 3 from the selection tool falls through: the runner fails on it, CI never guesses."""
        out, log = self.run_script("journeys", "ipad", STUB_RUNNABLE="", STUB_ALL="", STUB_AFFECTED_RC="3")
        self.assertEqual(out.returncode, 0)
        self.assertIn("uitest --only ipad --changed --force", log)

    def test_a_crash_of_the_selection_tool_fails_the_step(self):
        out, _ = self.run_script("journeys", "iphone", STUB_AFFECTED_RC="2")
        self.assertEqual(out.returncode, 2)

    def test_each_device_starts_on_an_idle_runner_and_swift_test_too(self):
        _, log = self.run_script("smoke", "duo")
        self.assertLess(log.index("release"), log.index("settle duo"))
        _, log = self.run_script("swift-test")
        self.assertIn("release", log)
        self.assertIn("swift test", log)

    def test_swift_test_on_a_pull_request_runs_the_affected_suites_only(self):
        out, log = self.run_script("swift-test", FENTON_AFFECTED_BASE="origin/main", STUB_ALL="--filter A")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("swift test --filter A", log)

    def test_swift_test_on_a_pull_request_is_skipped_when_no_suite_is_reached(self):
        out, log = self.run_script("swift-test", FENTON_AFFECTED_BASE="origin/main", STUB_ALL="")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("skipped", out.stdout)
        self.assertNotIn("swift test", log)

    def test_summary_prints_a_table_of_the_phases(self):
        self.timings.write_text("build\t120\t0\nsmoke-duo\t150\t1\n")
        out, _ = self.run_script("summary")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("| build | 120 | 0 |", out.stdout)
        self.assertIn("| smoke-duo | 150 | 1 |", out.stdout)
        self.assertIn("Timing by phase", (self.dir / "summary").read_text())

    def test_an_unknown_command_or_device_is_a_usage_error(self):
        self.assertEqual(self.run_script("nothing")[0].returncode, 2)
        self.assertEqual(self.run_script("smoke", "watch")[0].returncode, 2)


if __name__ == "__main__":
    unittest.main()
