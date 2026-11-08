"""tools/sim_slim.sh: a stock-simulator fallback is quiet by default and a failure under FENTON_REQUIRE_SIMSLIM=1."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "sim_slim.sh"
XCRUN = "#!/bin/bash\nexit 0\n"


def simslim(on_rc: int, verify_rc: int) -> str:
    return '#!/bin/bash\ncase "$1" in on) echo on-output; exit %d;; verify) exit %d;; *) exit 0;; esac\n' % (on_rc, verify_rc)


class SimSlimTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = Path(self.tmp.name)
        self.write("xcrun", XCRUN)

    def write(self, name, body):
        path = self.bin / name
        path.write_text(body, encoding="utf-8")
        path.chmod(0o755)

    def run_script(self, require, with_simslim=True):
        # A PATH of the stub directory plus the system tools the script needs (dirname, basename), never a real simslim.
        env = {"PATH": "%s:/usr/bin:/bin" % self.bin, "HOME": self.tmp.name}
        if require:
            env["FENTON_REQUIRE_SIMSLIM"] = "1"
        return subprocess.run(["/bin/bash", str(SCRIPT), "UDID-1"], env=env, capture_output=True, text=True)

    def test_a_missing_simslim_is_a_warning_by_default(self):
        out = self.run_script(require=False)
        self.assertEqual(out.returncode, 0)
        self.assertIn("continuing stock", out.stderr)

    def test_a_missing_simslim_fails_when_required(self):
        out = self.run_script(require=True)
        self.assertEqual(out.returncode, 1)
        self.assertIn("FENTON_REQUIRE_SIMSLIM=1: failing", out.stderr)

    def test_a_failed_slimming_is_quiet_by_default_and_loud_when_required(self):
        self.write("simslim", simslim(on_rc=1, verify_rc=1))
        self.assertEqual(self.run_script(require=False).returncode, 0)
        out = self.run_script(require=True)
        self.assertEqual(out.returncode, 1)
        self.assertIn("on-output", out.stderr)

    def test_a_simulator_that_does_not_verify_after_slimming_fails_when_required(self):
        self.write("simslim", simslim(on_rc=0, verify_rc=1))
        self.assertEqual(self.run_script(require=False).returncode, 0)
        out = self.run_script(require=True)
        self.assertEqual(out.returncode, 1)
        self.assertIn("is not slim after simslim on", out.stderr)

    def test_a_slim_simulator_passes_when_required(self):
        self.write("simslim", simslim(on_rc=0, verify_rc=0))
        self.assertEqual(self.run_script(require=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
