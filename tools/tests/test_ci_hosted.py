"""Hosted-CI mode (``FENTON_CI_HOSTED=1``): the devcap stand-in, the hygiene no-op and the run_tool_tests parts."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import ci_hosted  # noqa: E402
import ci_hygiene  # noqa: E402

LISTING = {"devices": {"iOS 27.0": [
    {"name": "iPhone 17", "udid": "AAAAAAAA-0000-0000-0000-000000000001", "isAvailable": True},
    {"name": "iPhone 17 Pro", "udid": "AAAAAAAA-0000-0000-0000-000000000002", "isAvailable": False},
    {"name": "iPad Pro 11-inch (M5)", "udid": "AAAAAAAA-0000-0000-0000-000000000003", "isAvailable": True}]}}


def clean_env(**extra):
    """The test process's settings without any hosted-mode, simulator or devcap variable, plus ``extra``."""
    env = {k: v for k, v in dict(os.environ).items() if not k.startswith(("FENTON_CI_", "FENTON_SIM_", "DEVCAP_", "RUNNER_ENV"))}
    env.update(extra)
    return env


class SwitchTests(unittest.TestCase):
    HOSTED = {"FENTON_CI_HOSTED": "1", "RUNNER_ENVIRONMENT": "github-hosted"}

    def test_only_exactly_one_on_a_github_hosted_runner_turns_it_on(self):
        self.assertTrue(ci_hosted.active(self.HOSTED))
        for value in ("0", "", "true", "yes"):
            self.assertFalse(ci_hosted.active({**self.HOSTED, "FENTON_CI_HOSTED": value}))
        self.assertFalse(ci_hosted.active({}))

    def test_the_variable_alone_never_turns_it_on(self):
        """On the owner's Macs (no RUNNER_ENVIRONMENT, or self-hosted) devcap holds must stay."""
        self.assertFalse(ci_hosted.active({"FENTON_CI_HOSTED": "1"}))
        self.assertFalse(ci_hosted.active({"FENTON_CI_HOSTED": "1", "RUNNER_ENVIRONMENT": "self-hosted"}))

    def test_sim_name_defaults_and_overrides(self):
        self.assertEqual(ci_hosted.sim_name("iphone", {}), "iPhone 17")
        self.assertEqual(ci_hosted.sim_name("duo", {}), "iPhone Duo")
        self.assertEqual(ci_hosted.sim_name("ipad", {}), "iPad Pro 11-inch (M5)")
        self.assertEqual(ci_hosted.sim_name("iphone", {"FENTON_SIM_IPHONE": "iPhone 18 Pro"}), "iPhone 18 Pro")
        self.assertEqual(ci_hosted.sim_name("duo", {"FENTON_SIM_DUO": ""}), "iPhone Duo")

    def test_find_udid_skips_unavailable_and_unknown(self):
        self.assertEqual(ci_hosted.find_udid("iPhone 17", LISTING), "AAAAAAAA-0000-0000-0000-000000000001")
        self.assertIsNone(ci_hosted.find_udid("iPhone 17 Pro", LISTING))
        self.assertIsNone(ci_hosted.find_udid("iPhone Duo", LISTING))

    def test_command_line(self):
        script = str(TOOLS / "ci_hosted.py")
        out = subprocess.run([sys.executable, script, "sim-name", "ipad"], env=clean_env(), capture_output=True, text=True)
        self.assertEqual(out.stdout.strip(), "iPad Pro 11-inch (M5)")
        self.assertEqual(subprocess.run([sys.executable, script, "active"], env=clean_env()).returncode, 1)
        self.assertEqual(subprocess.run([sys.executable, script, "active"],
                                        env=clean_env(FENTON_CI_HOSTED="1", RUNNER_ENVIRONMENT="github-hosted")).returncode, 0)
        self.assertEqual(subprocess.run([sys.executable, script, "bogus"], env=clean_env(), capture_output=True).returncode, 2)


class DevcapStandInTests(unittest.TestCase):
    def test_run_executes_the_command_after_the_dashes(self):
        seen = []
        rc = ci_hosted.devcap_main(["run", "--pool", "build", "--hold", "60", "--purpose", "x", "--", "echo", "hi"],
                                   runner=lambda c: seen.append(c) or 7)
        self.assertEqual((rc, seen), (7, [["echo", "hi"]]))

    def test_run_without_a_command_is_a_usage_error(self):
        self.assertEqual(ci_hosted.devcap_main(["run", "--pool", "build"], runner=lambda c: 0), 2)
        self.assertEqual(ci_hosted.devcap_main(["run", "--"], runner=lambda c: 0), 2)
        self.assertEqual(ci_hosted.devcap_main([]), 2)

    def test_pick_sim_prints_the_existing_udid_or_fails(self):
        self.assertEqual(ci_hosted.devcap_main(["pick-sim", "--name", "iPhone 17", "--pool", "0"], lookup=lambda n: "U-" + n), 0)
        self.assertEqual(ci_hosted.devcap_main(["pick-sim", "--name", "Nope"], lookup=lambda n: None), 1)
        self.assertEqual(ci_hosted.devcap_main(["pick-sim"], lookup=lambda n: "x"), 1)

    def test_status_commands_and_unknown_ones(self):
        for cmd in ("status", "reap", "slots"):
            self.assertEqual(ci_hosted.devcap_main([cmd]), 0)
        self.assertEqual(ci_hosted.devcap_main(["install"]), 2)

    def test_the_command_line_runs_through_without_a_hold(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = clean_env(DEVCAP_DIR=tmp, HOME=tmp)
            out = subprocess.run([sys.executable, str(TOOLS / "ci_hosted.py"), "devcap", "run", "--pool", "build", "--hold", "60", "--", "echo", "ran"],
                                 env=env, capture_output=True, text=True)
            self.assertEqual((out.returncode, out.stdout.strip()), (0, "ran"), out.stderr)
            self.assertEqual(list(Path(tmp).iterdir()), [], "hosted mode must not create devcap gates or state")

    def test_the_vendored_devcap_is_not_hosted_aware(self):
        self.assertNotIn("ci_hosted", (TOOLS / "devcap.py").read_text(encoding="utf-8"))


class HygieneTests(unittest.TestCase):
    def test_every_command_but_rm_dir_is_a_no_op_when_hosted(self):
        old = os.environ.get("FENTON_CI_HOSTED")
        os.environ["FENTON_CI_HOSTED"] = "1"
        old_runner = os.environ.get("RUNNER_ENVIRONMENT")
        os.environ["RUNNER_ENVIRONMENT"] = "github-hosted"
        try:
            for argv in (["preflight", "--min-gb", "100000"], ["sims-clean", "/nonexistent"], ["prune-results"], ["derived-orphans"]):
                self.assertEqual(ci_hygiene.main(argv), 0, argv)
        finally:
            for key, previous in (("FENTON_CI_HOSTED", old), ("RUNNER_ENVIRONMENT", old_runner)):
                if previous is None:
                    del os.environ[key]
                else:
                    os.environ[key] = previous

    def test_the_variable_without_the_hosted_runner_marker_keeps_the_preflight(self):
        for extra in ({}, {"RUNNER_ENVIRONMENT": "self-hosted"}):
            out = subprocess.run([sys.executable, str(TOOLS / "ci_hygiene.py"), "preflight", "--min-gb", "100000000"],
                                 env=clean_env(FENTON_CI_HOSTED="1", **extra), capture_output=True, text=True)
            self.assertNotEqual(out.returncode, 0, extra)

    def test_preflight_still_fails_on_low_disk_when_unset(self):
        out = subprocess.run([sys.executable, str(TOOLS / "ci_hygiene.py"), "preflight", "--min-gb", "100000000"],
                             env=clean_env(), capture_output=True, text=True)
        self.assertNotEqual(out.returncode, 0)


class RunToolTestsPartsTests(unittest.TestCase):
    SCRIPT = TOOLS / "run_tool_tests.sh"

    def test_lists_the_three_parts(self):
        out = subprocess.run(["bash", str(self.SCRIPT), "--list"], capture_output=True, text=True)
        self.assertEqual(out.stdout.split(), ["core", "triage", "release"])

    def test_an_unknown_part_fails(self):
        out = subprocess.run(["bash", str(self.SCRIPT), "bogus"], capture_output=True, text=True)
        self.assertEqual(out.returncode, 1)
        self.assertIn("unknown part 'bogus'", out.stderr)


if __name__ == "__main__":
    unittest.main()
