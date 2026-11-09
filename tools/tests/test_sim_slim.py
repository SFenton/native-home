"""tools/sim_slim.sh: it leaves a simulator stock, quietly, on a hosted runner, and warns (never fails) when simslim is missing."""
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "sim_slim.sh"


class SimSlimTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = Path(self.tmp.name)
        # A stub xcrun that records its use, so a test can see that the script stopped before touching a simulator.
        (self.bin / "xcrun").write_text('#!/bin/bash\necho "$@" >> "%s/xcrun.log"\nexit 0\n' % self.bin, encoding="utf-8")
        (self.bin / "xcrun").chmod(0o755)

    def run_script(self, **env):
        # A PATH of the stub directory plus the system tools the script needs, never a real simslim.
        full = {"PATH": "%s:/usr/bin:/bin" % self.bin, "HOME": self.tmp.name, **env}
        return subprocess.run(["/bin/bash", str(SCRIPT), "UDID-1"], env=full, capture_output=True, text=True)

    def test_a_hosted_runner_leaves_the_simulator_stock_in_one_quiet_line(self):
        out = self.run_script(FENTON_CI_HOSTED="1")
        self.assertEqual(out.returncode, 0)
        self.assertEqual(out.stdout.strip().count("\n"), 0)
        self.assertIn("hosted runner", out.stdout)
        self.assertEqual(out.stderr, "")
        self.assertFalse((self.bin / "xcrun.log").exists())

    def test_a_missing_simslim_is_a_warning_not_a_failure(self):
        out = self.run_script()
        self.assertEqual(out.returncode, 0)
        self.assertIn("simslim not installed", out.stderr)

    def test_opting_out_leaves_the_simulator_stock(self):
        out = self.run_script(FENTON_SIM_SLIM="0")
        self.assertEqual(out.returncode, 0)
        self.assertIn("FENTON_SIM_SLIM=0", out.stdout)


if __name__ == "__main__":
    unittest.main()
