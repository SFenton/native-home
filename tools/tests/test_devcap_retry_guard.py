"""``tools/hooks/devcap_retry_guard.py``: no blind rebuild after a devcap hold timeout."""

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import devcap_retry_guard as guard  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from redact import redact, redact_lines  # noqa: E402

HEAVY = "tools/bg_run.py uitest -- tools/ios_uitest.sh --changed"
TIMEOUT_OUT = ("devcap: HOLD TIMEOUT: held device-5F3A9C2E-1B4D-4E6F-8A7B-0C9D1E2F3A4B,simulator longer than 40m; releasing.")
T0 = 1_000_000.0


class RetryGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.clock = T0
        self.load = 60.0
        for name, value in (("now", lambda: self.clock), ("load1", lambda: self.load), ("repo_root", lambda cwd: self.root)):
            patcher = mock.patch.object(guard, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)
        self.marker = guard.marker_path(self.root)

    def run_hook(self, payload):
        """The exit code and stderr of ``main`` for ``payload``."""
        err = io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO(payload if isinstance(payload, str) else json.dumps(payload))), redirect_stderr(err):
            code = guard.main([])
        return code, err.getvalue()

    def pre(self, command):
        return self.run_hook({"tool_name": "Bash", "hook_event_name": "PreToolUse", "tool_input": {"command": command}, "cwd": self.root})

    def post(self, command, response, event="PostToolUse"):
        return self.run_hook({"tool_name": "Bash", "hook_event_name": event, "tool_input": {"command": command},
                              "tool_response": response, "cwd": self.root})

    def arm(self, age=600, load=60.0):
        os.makedirs(os.path.dirname(self.marker), exist_ok=True)
        Path(self.marker).write_text(json.dumps({"time": T0 - age, "load1": load, "command": "x"}))

    def test_timeout_output_writes_marker(self):
        """Fails if: a hold timeout in the tool output leaves no marker, or the marker loses the time, load or command."""
        self.assertEqual(self.post(HEAVY, {"stdout": "", "stderr": TIMEOUT_OUT})[0], 0)
        data = json.loads(Path(self.marker).read_text())
        self.assertEqual((data["time"], data["load1"], data["command"]), (T0, 60.0, HEAVY))

    def test_failure_event_and_exit_124_write_marker(self):
        """Fails if: a failed call (PostToolUseFailure, a string error) or exit 124 of a heavy command is missed."""
        self.post(HEAVY, "Exit code 124\nstuff", event="PostToolUseFailure")
        self.assertTrue(os.path.exists(self.marker))
        os.remove(self.marker)
        self.run_hook({"tool_name": "Bash", "hook_event_name": "PostToolUseFailure", "tool_input": {"command": HEAVY},
                       "error": "Exit code 124", "cwd": self.root})
        self.assertTrue(os.path.exists(self.marker))

    def test_command_is_cut_to_200_chars(self):
        """Fails if: the stored command is not truncated."""
        self.post(HEAVY + " " + "x" * 400, TIMEOUT_OUT)
        self.assertEqual(len(json.loads(Path(self.marker).read_text())["command"]), 200)

    def test_ordinary_output_and_exit_124_of_a_light_command_write_nothing(self):
        """Fails if: a normal run, or exit 124 of a non-heavy command (a plain `timeout`), arms the guard."""
        self.post(HEAVY, {"stdout": "all passed"})
        self.post("timeout 5 sleep 9", "Exit code 124", event="PostToolUseFailure")
        self.assertFalse(os.path.exists(self.marker))

    def test_refused_under_equal_load(self):
        """Fails if: a heavy command after a timeout at the same load is allowed, or the message omits the cause or the override."""
        self.arm()
        code, err = self.pre(HEAVY)
        self.assertEqual(code, 2)
        self.assertIn("blocked: load (a devcap hold timed out 10m ago at load 60.0, now 60.0)", err)
        self.assertIn("shared-Mac load", err)
        self.assertIn("# devcap-retry-ok: <reason>", err)

    def test_allowed_when_load_falls(self):
        """Fails if: the refusal ignores the load, or the 0.8 x boundary is off (47.9 passes, 48.0 is refused)."""
        self.arm()
        self.load = 47.9
        self.assertEqual(self.pre(HEAVY)[0], 0)
        self.load = 48.0
        self.assertEqual(self.pre(HEAVY)[0], 2)

    def test_override_allows_and_removes_marker(self):
        """Fails if: the override comment does not let the run through, or leaves the marker behind."""
        self.arm()
        self.assertEqual(self.pre(HEAVY + " # devcap-retry-ok: load cleared")[0], 0)
        self.assertFalse(os.path.exists(self.marker))
        self.assertEqual(self.pre(HEAVY)[0], 0)

    def test_stale_marker_is_deleted_and_ignored(self):
        """Fails if: a marker over two hours old still blocks or stays on disk."""
        self.arm(age=2 * 3600 + 1)
        self.assertEqual(self.pre(HEAVY)[0], 0)
        self.assertFalse(os.path.exists(self.marker))

    def test_non_heavy_never_refused(self):
        """Fails if: any non-heavy command is refused, or one that only names a script (grep, quote, heredoc) counts as running it."""
        self.arm()
        for command in ("git status", "swift test --filter X", "grep ios_uitest.sh PROGRESS.md", "bash -n tools/ios_uitest.sh",
                        "gh issue create --body 'tools/ios_uitest.sh again'", "python3 tools/devcap.py status",
                        "cat <<EOF\ntools/ios_uitest.sh --changed\nEOF"):
            with self.subTest(command=command):
                self.assertEqual(self.pre(command)[0], 0)
        self.assertTrue(os.path.exists(self.marker))

    def test_heavy_shapes_are_refused(self):
        """Fails if: a devcap run, the coverage script or a wrapped journey run slips through."""
        self.arm()
        for command in ("python3 tools/devcap.py run --sim U -- xcodebuild test", "tools/apple_coverage.sh --changed",
                        "bash -c 'tools/ios_uitest.sh --changed'", "FENTON_X=1 nohup tools/ios_uitest.sh --changed &"):
            with self.subTest(command=command):
                self.assertEqual(self.pre(command)[0], 2)

    def test_no_marker_allows(self):
        """Fails if: a heavy command is refused with no marker."""
        self.assertEqual(self.pre(HEAVY)[0], 0)

    def test_fails_open(self):
        """Fails if: a malformed marker, bad JSON input, another tool, no repo or an internal error blocks."""
        os.makedirs(os.path.dirname(self.marker), exist_ok=True)
        for text in ("{not json", "[]", json.dumps({"time": "x", "load1": 1})):
            Path(self.marker).write_text(text)
            with self.subTest(marker=text):
                self.assertEqual(self.pre(HEAVY)[0], 0)
        self.assertEqual(self.run_hook("garbage")[0], 0)
        self.assertEqual(self.run_hook({"tool_name": "Read", "tool_input": {}})[0], 0)
        self.arm()
        with mock.patch.object(guard, "repo_root", lambda cwd: None):
            self.assertEqual(self.pre(HEAVY)[0], 0)
        with mock.patch.object(guard, "load1", side_effect=OSError):
            self.assertEqual(self.pre(HEAVY)[0], 0)

    def test_quoting_the_line_writes_no_marker(self):
        """Fails if: a cat or grep of the hook, its test or the doc, or a diff of them, arms the guard."""
        root = Path(__file__).resolve().parents[2]
        files = ["tools/hooks/devcap_retry_guard.py", "tools/tests/test_devcap_retry_guard.py", ".agents/workflow/token-economy.md"]
        for rel in files:
            text = (root / rel).read_text()
            lines = [f"{n}:{line}" for n, line in enumerate(text.splitlines(), 1)]
            diff = "\n".join("+" + line for line in text.splitlines())
            for shape in (text, "\n".join(f"{rel}:{line}" for line in lines), diff):
                with self.subTest(file=rel):
                    self.post("cat " + rel, {"stdout": shape})
                    self.assertFalse(os.path.exists(self.marker))
        self.post("echo", "see `devcap: HOLD TIMEOUT` in the docs")
        self.assertFalse(os.path.exists(self.marker))

    def test_real_line_in_any_tail_shape_arms(self):
        """Fails if: devcap's real line misses in a raw tail, a multi-line stdout or grep -n / grep -H output."""
        for shape in (TIMEOUT_OUT, "building\n" + TIMEOUT_OUT + "\n", "12:" + TIMEOUT_OUT, "build/runs/x.log:" + TIMEOUT_OUT,
                      "build/runs/x.log:12:" + TIMEOUT_OUT):
            with self.subTest(shape=shape):
                self.post("tail -5 build/runs/x.log", {"stdout": "a\n" + shape})
                self.assertTrue(os.path.exists(self.marker))
                os.remove(self.marker)

    def test_redacted_line_arms_through_the_post_hook(self):
        """Fails if: the line as bg_run logs it after redaction (UDID replaced by [redacted]) no longer arms the Post hook."""
        redacted = redact(TIMEOUT_OUT)
        self.assertIn("[redacted]", redacted)
        self.assertNotIn("5F3A9C2E", redacted)
        self.post("tail -5 build/runs/x.log", {"stdout": "a\n" + redacted})
        self.assertTrue(os.path.exists(self.marker))

    def test_redacted_line_arms_through_arm_from_log(self):
        """Fails if: arm_from_log misses the redacted form of devcap's line (also via redact_lines)."""
        for text in (redact(TIMEOUT_OUT), redact_lines(TIMEOUT_OUT + "\n")):
            with self.subTest(text=text):
                self.assertTrue(guard.arm_from_log(self.root, "cmd", 1, text))
                self.assertTrue(os.path.exists(self.marker))
                os.remove(self.marker)

    def test_post_resolves_the_worktree_only_on_a_hit(self):
        """Fails if: a Post call without the timeout text runs git rev-parse."""
        with mock.patch.object(guard, "repo_root", side_effect=AssertionError):
            self.assertEqual(self.post("ls", {"stdout": "fine"})[0], 0)

    def test_option_flags_do_not_hide_a_heavy_run(self):
        """Fails if: `bash -x script`, `python3 -u tools/devcap.py run` or similar flag-led shapes slip through."""
        self.arm()
        for command in ("bash -x tools/ios_uitest.sh --changed", "bash -e -x tools/apple_coverage.sh", "bash -o pipefail tools/ios_uitest.sh",
                        "python3 -u tools/devcap.py run --sim U -- echo", "python3 -W ignore -u tools/devcap.py run --sim U -- x",
                        "bash -xc 'tools/ios_uitest.sh'"):
            with self.subTest(command=command):
                self.assertEqual(self.pre(command)[0], 2)
        for command in ("bash -nx tools/ios_uitest.sh", "python3 -u tools/devcap.py status", "python3 -m pytest tools/ios_uitest.sh",
                        "python3 -c 'print(1)' tools/ios_uitest.sh"):
            with self.subTest(command=command):
                self.assertEqual(self.pre(command)[0], 0)


class BgRunArmTests(unittest.TestCase):
    """``tools/bg_run.py`` arms the marker from the artifact: a non-zero exit plus devcap's real line in the log."""

    def run_bg(self, script):
        import subprocess
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        subprocess.run(["git", "init", "-q", tmp.name], check=True)
        bg = Path(__file__).resolve().parents[1] / "bg_run.py"
        subprocess.run([sys.executable, str(bg), "t", "--dir", os.path.join(tmp.name, "runs"), "--", "sh", "-c", script],
                       cwd=tmp.name, capture_output=True, text=True, timeout=120)
        return os.path.exists(guard.marker_path(os.path.realpath(tmp.name)))

    def test_exit_124_with_the_real_line_writes_the_marker(self):
        """Fails if: a background devcap timeout leaves no marker."""
        self.assertTrue(self.run_bg("echo; echo '" + TIMEOUT_OUT + "'; exit 124"))

    def test_other_shapes_write_nothing(self):
        """Fails if: exit 124 without the line, or the line with exit 0, or only quoted text arms the guard."""
        self.assertFalse(self.run_bg("echo plain; exit 124"))
        self.assertFalse(self.run_bg("echo '" + TIMEOUT_OUT + "'; exit 0"))
        self.assertFalse(self.run_bg("echo 'the text devcap: HOLD TIMEOUT is quoted'; exit 124"))

    def test_coverage_shape_exit_1_with_the_real_line_arms(self):
        """Fails if: the coverage script's exit 1 after a part's hold timeout leaves no marker."""
        self.assertTrue(self.run_bg("echo part 3; echo '" + TIMEOUT_OUT + "'; exit 1"))

    def test_clean_run_skips_the_hook_import_and_repo_root(self):
        """Fails if: a clean or line-less run imports the hook or calls repo_root before checking status and line."""
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        import bg_run
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        for script, expect_call in (("echo ok", False), ("echo plain; exit 1", False), ("echo '" + TIMEOUT_OUT + "'; exit 1", True)):
            with mock.patch.object(guard, "repo_root", return_value=None) as root:
                bg_run.run("t", ["sh", "-c", script], Path(tmp.name), None)
            self.assertEqual(root.called, expect_call, script)


class MarkerRedactionTests(unittest.TestCase):
    def test_token_in_the_command_does_not_reach_the_marker(self):
        """Fails if: a credential-shaped string in the command is written to the marker, or the 200-character cut is lost."""
        secret = "ghp_" + "g" * 30
        with tempfile.TemporaryDirectory() as root:
            guard.write_marker(root, "tools/ios_uitest.sh gh " + secret + " " + "x" * 400)
            with open(guard.marker_path(root), encoding="utf-8") as handle:
                stored = json.load(handle)["command"]
        self.assertNotIn(secret, stored)
        self.assertLessEqual(len(stored), 200)


if __name__ == "__main__":
    unittest.main()
