"""``tools/hooks/tier_guard.py``: no unfiltered journey run outside the nightly and release tiers."""

import io
import json
import os
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import tier_guard  # noqa: E402

BLOCKED = [
    "tools/ios_uitest.sh",
    "tools/ios_uitest.sh --only iphone",
    "./tools/ios_uitest.sh --env shell --only duo --force",
    "tools/bg_run.py uitest-iphone -- tools/ios_uitest.sh --only iphone",
    "python3 tools/bg_run.py uitest -- tools/ios_uitest.sh",
    "FENTON_DEVCAP_HOLD=7200 tools/ios_uitest.sh --only ipad",
    "cd apple && ../tools/ios_uitest.sh",
    "bash -c 'tools/ios_uitest.sh --only iphone'",
    "tools/ios_uitest.sh --plan Gate",
    "tools/ios_uitest.sh --full",
]
ALLOWED = [
    "tools/ios_uitest.sh --changed",
    "tools/ios_uitest.sh --only duo --changed",
    "tools/ios_uitest.sh --only ipad -only-testing:FentonHomeUITests/ChoresSwipeJourneyTests",
    "tools/ios_uitest.sh -only-testing:FentonHomeUITests/A/testB",
    "tools/ios_uitest.sh --only duo --plan Smoke",
    "tools/ios_uitest.sh --plan=Perf",
    "tools/bg_run.py uitest -- tools/ios_uitest.sh --changed --only iphone",
    "tools/apple_coverage.sh",
    "tools/apple_coverage.sh --changed",
    "tools/bg_run.py cov -- tools/apple_coverage.sh",
    "nohup tools/apple_coverage.sh > out.log 2>&1 &",
    "FENTON_TIER=nightly tools/ios_uitest.sh --only iphone",
    "FENTON_TIER=release tools/apple_coverage.sh",
    "tools/ios_uitest.sh --full  # full-ok: release candidate sign-off",
    "tools/ios_uitest.sh --help",
    "grep -n changed tools/ios_uitest.sh",
    "cat tools/apple_coverage.sh | head",
    "git add tools/ios_uitest.sh",
    "bash -n tools/ios_uitest.sh",
    "swift test --filter Foo",
    "echo hello",
]


def run(command, tool="Bash"):
    err = io.StringIO()
    payload = json.dumps({"tool_name": tool, "tool_input": {"command": command}})
    with mock.patch.object(sys, "stdin", io.StringIO(payload)), redirect_stderr(err), \
            mock.patch.dict(os.environ, {}, clear=False):
        os.environ.pop("FENTON_TIER", None)
        status = tier_guard.main()
    return status, err.getvalue()


class TierGuardTests(unittest.TestCase):
    def test_blocks_unfiltered_runs(self):
        for command in BLOCKED:
            with self.subTest(command=command):
                status, message = run(command)
                self.assertEqual(status, 2, message)
                self.assertIn("--changed", message)
                self.assertIn("nightly", message)

    def test_allows_filtered_nightly_and_overridden_runs(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                self.assertEqual(run(command)[0], 0)

    def test_full_without_a_reason_is_refused(self):
        self.assertEqual(run("tools/ios_uitest.sh --full # full-ok:")[0], 2)

    def test_the_environment_tier_lifts_the_block(self):
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "tools/ios_uitest.sh"}})
        with mock.patch.object(sys, "stdin", io.StringIO(payload)), mock.patch.dict(os.environ, {"FENTON_TIER": "nightly"}):
            self.assertEqual(tier_guard.main(), 0)

    def test_the_coverage_script_is_no_longer_guarded(self):
        """It is the host-only logic gate now (owner, 2026-11-10): no simulator, about ten minutes."""
        self.assertEqual(run("tools/apple_coverage.sh"), (0, ""))

    def test_ignores_other_tools_and_bad_input(self):
        self.assertEqual(run("tools/ios_uitest.sh", tool="Read")[0], 0)
        with mock.patch.object(sys, "stdin", io.StringIO("not json")):
            self.assertEqual(tier_guard.main(), 0)


class SettingsTests(unittest.TestCase):
    def test_the_hook_is_registered_for_bash(self):
        settings = json.loads((Path(__file__).resolve().parents[2] / ".claude" / "settings.json").read_text())
        commands = [h["command"] for g in settings["hooks"]["PreToolUse"] if g["matcher"] == "Bash" for h in g["hooks"]]
        self.assertTrue(any("tier_guard.py" in c for c in commands))


if __name__ == "__main__":
    unittest.main()
