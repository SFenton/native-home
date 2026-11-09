"""tools/sim_slim.sh: exit 0 slimmed, 1 hard failure, 3 left stock; every simslim and boot step runs under a wall; family names resolve."""
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "sim_slim.sh"

#: xcrun stub: logs its arguments; `simctl list` prints one iPhone 17; XCRUN_HANG sleeps, XCRUN_FAIL fails (for bootstatus).
XCRUN = r'''#!/bin/bash
echo "$@" >> "$STUB_DIR/xcrun.log"
if [ "$2" = list ]; then
  echo '{"devices":{"rt":[{"name":"iPhone 17","udid":"UDID-IPHONE"},{"name":"iPad Pro 11-inch (M5)","udid":"UDID-IPAD"}]}}'
  exit 0
fi
[ -n "$XCRUN_HANG" ] && sleep 30
[ -n "$XCRUN_FAIL" ] && exit 1
exit 0
'''
#: simslim stub: logs the subcommand; `verify` fails until a rebooting `on` has run; SIMSLIM_HANG=<subcommand> sleeps; SIMSLIM_HANG_ON_REBOOT
#: hangs only the rebooting `on` (no --no-reboot); SIMSLIM_ON_FAIL makes every `on` fail.
SIMSLIM = r'''#!/bin/bash
sub="$1"; echo "$*" >> "$STUB_DIR/simslim.log"
case " $* " in *" --no-reboot "*) key="on-noreboot" ;; *) key="$sub" ;; esac
[ "$SIMSLIM_HANG" = "$key" ] && sleep 30
if [ "$sub" = on ]; then
  [ -n "$SIMSLIM_ON_FAIL" ] && exit 1
  [ "$key" = on ] && touch "$STUB_DIR/slim"
  exit 0
fi
if [ "$sub" = verify ]; then [ -e "$STUB_DIR/slim" ] || [ -n "$SIMSLIM_SLIM" ]; exit $?; fi
exit 0
'''


class SimSlimTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = Path(self.tmp.name)
        self.put("xcrun", XCRUN)

    def put(self, name, body):
        (self.bin / name).write_text(body, encoding="utf-8")
        (self.bin / name).chmod(0o755)

    def log(self, name):
        path = self.bin / name
        return path.read_text() if path.exists() else ""

    def run_script(self, arg="UDID-1", **env):
        # A PATH of the stub directory plus the system tools the script needs, never a real simslim.
        full = {"PATH": "%s:/usr/bin:/bin" % self.bin, "HOME": self.tmp.name, "STUB_DIR": str(self.bin), **env}
        return subprocess.run(["/bin/bash", str(SCRIPT), arg], env=full, capture_output=True, text=True, timeout=90)

    def with_simslim(self):
        self.put("simslim", SIMSLIM)

    def test_a_hosted_runner_slims_like_any_other_host(self):
        out = self.run_script(FENTON_CI_HOSTED="1")
        self.assertNotIn("hosted runner", out.stdout)
        self.assertIn("simslim not installed", out.stderr)

    def test_a_missing_simslim_leaves_the_simulator_stock_with_exit_3(self):
        out = self.run_script()
        self.assertEqual(out.returncode, 3)
        self.assertIn("simslim not installed", out.stderr)

    def test_opting_out_leaves_the_simulator_stock_with_exit_3(self):
        out = self.run_script(FENTON_SIM_SLIM="0")
        self.assertEqual(out.returncode, 3)
        self.assertIn("FENTON_SIM_SLIM=0", out.stdout)

    def test_an_already_slim_simulator_exits_0_after_one_verify(self):
        self.with_simslim()
        out = self.run_script(SIMSLIM_SLIM="1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("already slim", out.stdout)

    def test_a_stock_simulator_is_slimmed_with_the_reboot_path_and_exits_0(self):
        self.with_simslim()
        out = self.run_script()
        self.assertEqual(out.returncode, 0, out.stderr)
        log = self.log("simslim.log")
        self.assertIn("on UDID-1 --no-reboot", log)
        self.assertIn("on UDID-1 --profile", log)

    def test_a_boot_that_hits_the_wall_leaves_the_simulator_stock_with_exit_3(self):
        self.with_simslim()
        self.put("xcrun", XCRUN)
        out = self.run_script(FENTON_HEALTH_BOOT_WALL="1", XCRUN_HANG="1")
        self.assertEqual(out.returncode, 3, out.stderr)
        self.assertIn("hit the 1s wall; leaving it stock", out.stderr)
        self.assertEqual(self.log("simslim.log"), "")

    def test_a_boot_failure_other_than_the_wall_is_a_hard_failure(self):
        self.with_simslim()
        out = self.run_script(XCRUN_FAIL="1")
        self.assertEqual(out.returncode, 1)
        self.assertIn("would not boot", out.stderr)
        self.assertEqual(self.log("simslim.log"), "")

    def test_a_hanging_rebooting_on_hits_its_wall_and_leaves_the_simulator_stock(self):
        self.with_simslim()
        out = self.run_script(SIMSLIM_HANG="on", FENTON_SLIM_ON_WALL="1")
        self.assertEqual(out.returncode, 3, out.stderr)
        self.assertIn("simslim on on UDID-1 hit the 1s wall", out.stderr)

    def test_a_hanging_verify_or_no_reboot_on_or_doctor_leaves_the_simulator_stock(self):
        self.with_simslim()
        for step, extra in (("verify", {}), ("on-noreboot", {}), ("doctor", {"SIMSLIM_SLIM": "1"})):
            with self.subTest(step=step):
                out = self.run_script(SIMSLIM_HANG=step, FENTON_SLIM_WALL="1", **extra)
                self.assertEqual(out.returncode, 3, out.stderr)
                self.assertIn("hit the 1s wall", out.stderr)

    def test_a_hanging_bootstatus_after_the_reboot_leaves_the_simulator_stock(self):
        self.with_simslim()
        # The first bootstatus passes quickly; the one after `simslim on` hangs: the stub sleeps once the slim marker exists.
        self.put("xcrun", XCRUN.replace('[ -n "$XCRUN_HANG" ]', '[ -e "$STUB_DIR/slim" ]'))
        out = self.run_script(FENTON_HEALTH_BOOT_WALL="1")
        self.assertEqual(out.returncode, 3, out.stderr)
        self.assertIn("after reboot", out.stderr)

    def test_a_failed_simslim_on_leaves_the_simulator_stock_with_exit_3(self):
        self.with_simslim()
        out = self.run_script(SIMSLIM_ON_FAIL="1")
        self.assertEqual(out.returncode, 3)
        self.assertIn("simslim on failed", out.stderr)

    def test_a_family_name_resolves_to_its_simulator(self):
        self.with_simslim()
        out = self.run_script("iphone", SIMSLIM_SLIM="1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("verify UDID-IPHONE", self.log("simslim.log"))
        out = self.run_script("ipad", SIMSLIM_SLIM="1")
        self.assertIn("verify UDID-IPAD", self.log("simslim.log"))

    def test_a_family_with_no_such_simulator_is_a_hard_failure(self):
        self.with_simslim()
        out = self.run_script("duo", SIMSLIM_SLIM="1")
        self.assertEqual(out.returncode, 1)
        self.assertIn("no simulator named iPhone Duo", out.stderr)


if __name__ == "__main__":
    unittest.main()
