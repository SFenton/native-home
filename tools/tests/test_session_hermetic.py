"""The tool tests that read agent-session state pass in any environment.

Agent sessions export markers (``FENTON_HEADLESS``, ``HASS_TRIAGE_*``, ``T3CODE_*``) and are registered by worktree, and the lander runs the
tool tests from a launchd job with only ``PATH`` and ``HOME``. A module that depends on either fails wherever it is run, and a failure
that appears only in one place makes the lander's base-versus-lane comparison refuse a lane that broke nothing. Each module that
``session_markers`` pins is run here as a child process in two environments built in this test, and must exit 0 with no ``FAIL:`` or
``ERROR:`` line:

* **marked**: the current environment plus ``FENTON_HEADLESS=1``, ``HASS_TRIAGE_ISSUE=9`` and ``T3CODE_THREAD_ID=x``;
* **bare**: ``PATH``, ``HOME`` and ``PYTHONDONTWRITEBYTECODE=1`` only, as ``lane_land._run_fixed`` gives the runner's test run.

The children run concurrently (the slowest module, ``test_lane_land``, sets the total: about four minutes on a quiet machine). This module is
not in its own list, so it never runs itself.
"""

import os
import re
import subprocess
import sys
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Dict, List, Tuple

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

#: ``(directory, file)`` of every module that calls ``session_markers.pin``; the pin-list test keeps this equal to the source.
PINNED = tuple(("tools/tests", name) for name in (
    "test_autonomy_kept_set.py", "test_denylist_layers.py", "test_lane_land.py", "test_merge_guard_admin.py", "test_pr_land.py",
    "test_pr_note.py", "test_signing_guard.py", "test_stop_continue_guard.py")) + (
    ("tools/triage/tests", "test_retro_p3.py"), ("tools/triage/tests", "test_retro_p4.py"))

#: Added to the current environment for the marked run.
MARKED = {"FENTON_HEADLESS": "1", "HASS_TRIAGE_ISSUE": "9", "T3CODE_THREAD_ID": "x"}

FAILURE = re.compile(r"^(?:FAIL|ERROR):", re.M)
TIMEOUT = 1800.0


def environments() -> Dict[str, Dict[str, str]]:
    """The two child environments, keyed by name."""
    bare = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.environ.get("HOME", str(Path.home())),
            "PYTHONDONTWRITEBYTECODE": "1"}
    return {"marked": {**os.environ, **MARKED}, "bare": bare}


def run_child(directory: str, name: str, env: Dict[str, str]) -> Tuple[int, str]:
    """Run one test module as ``python3 -m unittest discover -s DIR -p FILE`` from the repository root; return its exit code and output."""
    try:
        done = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", directory, "-p", name], cwd=ROOT, env=env,
                              capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {TIMEOUT:.0f} s"
    return done.returncode, done.stdout + done.stderr


class SessionHermeticTests(unittest.TestCase):
    """Each pinned module passes with session markers set and with the runner's bare environment."""

    results: Dict[Tuple[str, str, str], Tuple[int, str]] = {}

    @classmethod
    def setUpClass(cls):
        jobs = [(directory, name, label, env) for directory, name in PINNED for label, env in environments().items()]
        with ThreadPoolExecutor(max_workers=min(len(jobs), max(2, os.cpu_count() or 2))) as pool:
            done = list(pool.map(lambda job: run_child(job[0], job[1], job[3]), jobs))
        cls.results = {(directory, name, label): result for (directory, name, label, _), result in zip(jobs, done)}

    def test_every_pinned_module_passes_in_both_environments(self):
        for (directory, name, label), (code, output) in sorted(self.results.items()):
            with self.subTest(module=name, environment=label):
                failing = FAILURE.findall(output)
                self.assertEqual(code, 0, output[-2000:])
                self.assertEqual(failing, [], output[-2000:])

    def test_the_pin_list_is_every_module_that_pins(self):
        pinned = sorted(
            path.name for base in ("tools/tests", "tools/triage/tests") for path in (ROOT / base).glob("test_*.py")
            if re.search(r"^(?:from session_markers import|import session_markers)\b", path.read_text(), re.M))
        self.assertEqual(sorted(name for _, name in PINNED), pinned)
        self.assertNotIn(Path(__file__).name, pinned, "this module must not run itself")

    def test_the_environments_are_what_the_runner_has(self):
        envs = environments()
        self.assertEqual(sorted(envs["bare"]), ["HOME", "PATH", "PYTHONDONTWRITEBYTECODE"])
        self.assertEqual({k: envs["marked"][k] for k in MARKED}, MARKED)


if __name__ == "__main__":
    unittest.main()
