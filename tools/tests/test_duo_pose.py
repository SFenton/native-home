"""Argument handling, hold check and missing-dependency path of tools/duo_pose.py (no simulator)."""
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import duo_pose  # noqa: E402


def run(argv, env):
    err = io.StringIO()
    with redirect_stderr(err):
        code = duo_pose.main(argv, env)
    return code, err.getvalue()


class DuoPoseTests(unittest.TestCase):
    def test_bad_pose_is_usage_error(self):
        code, _ = run(["--sim", "U", "--set", "sideways"], {})
        self.assertEqual(code, duo_pose.EXIT_USAGE)

    def test_missing_sim_is_usage_error(self):
        code, _ = run(["--set", "folded"], {})
        self.assertEqual(code, duo_pose.EXIT_USAGE)

    def test_refuses_without_hold(self):
        code, err = run(["--sim", "U", "--set", "folded"], {})
        self.assertEqual(code, duo_pose.EXIT_NO_HOLD)
        self.assertIn("devcap.py run --sim U", err)

    def test_hold_detection(self):
        self.assertTrue(duo_pose.in_hold({"DEVCAP_HELD": "build,simulator"}))
        self.assertFalse(duo_pose.in_hold({"DEVCAP_HELD": "build"}))

    def test_missing_dependency_fails_clearly(self):
        with tempfile.TemporaryDirectory() as d:
            env = {"DEVCAP_HELD": "simulator", duo_pose.REPO_ENV: d}
            code, err = run(["--sim", "U", "--set", "half"], env)
        self.assertEqual(code, duo_pose.EXIT_NO_DEP)
        self.assertIn(duo_pose.REPO_ENV, err)

    def test_script_path_default_and_override(self):
        self.assertEqual(duo_pose.fst_script({duo_pose.REPO_ENV: "/x"}), Path("/x/tools/ios_sim.py"))
        self.assertTrue(str(duo_pose.fst_script({})).endswith("FestivalNativeApps/tools/ios_sim.py"))


if __name__ == "__main__":
    unittest.main()
