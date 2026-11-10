"""A T3-launched triage session (a registry record, ``tools/hooks/triage_session.py``) in each hook and tool that reads the headless markers.

For every one of ``merge_guard``, ``push_guard``, ``signing_guard``, ``review_guard``, ``stop_continue_guard``, ``owner_prompt_log``,
``pr_land`` and ``lane_land``: a session with a record behaves as the runner's headless session does, and the same call without a record
behaves as it always did.
"""

import io
import json
import os
import subprocess
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
import lane_land  # noqa: E402
import merge_guard  # noqa: E402
import owner_prompt_log  # noqa: E402
import pr_land  # noqa: E402
import push_guard  # noqa: E402
import review_guard  # noqa: E402
import signing_guard  # noqa: E402
import stop_continue_guard  # noqa: E402
import triage_session as ts  # noqa: E402

RUNNER_ENV = {"FENTON_HEADLESS": "1", "HASS_TRIAGE_ISSUE": "42", "HASS_TRIAGE_STATUS_FILE": "/s", "HASS_TRIAGE_PAUSED_FILE": "/p",
              "HASS_TRIAGE_BIN": "/b"}


class Base(unittest.TestCase):
    """A temp registry; ``self.work`` is the registered worktree, ``self.owner`` an unregistered one."""

    def setUp(self):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(os.path.realpath(tmp.name))
        self.root = self.tmp / "t3"
        self.work = self.tmp / "wt"
        self.owner = self.tmp / "owner"
        self.work.mkdir()
        self.owner.mkdir()
        ts.write_record(ts.build_record("request", 42, "orchestrator", self.work, "report/42", RUNNER_ENV, []), self.root)
        patch = mock.patch.object(ts, "registry_root", return_value=self.root)
        patch.start()
        self.addCleanup(patch.stop)

    def env(self, project):
        return {"CLAUDE_PROJECT_DIR": str(project), "T3CODE_THREAD_ID": "thr-9", "PATH": os.environ.get("PATH", ""),
                "HOME": os.environ.get("HOME", "")}

    def run_main(self, module, payload, project, **kw):
        """``(code, stdout, stderr, FENTON_HEADLESS afterwards)`` of ``module.main()`` for a session in ``project``."""
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, self.env(project), clear=True), mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), \
                redirect_stdout(out), redirect_stderr(err):
            code = module.main(**kw) if kw else module.main()
            marker = os.environ.get("FENTON_HEADLESS")
        return code, out.getvalue(), err.getvalue(), marker


class MarkerTests(Base):
    def test_every_hook_overlays_the_records_env_for_a_registered_session_only(self):
        """Fails if: a hook does not call triage_session.apply first, or applies it to a session with no record."""
        ls = {"tool_name": "Bash", "tool_input": {"command": "ls"}, "cwd": str(REPO), "hook_event_name": "Stop"}
        for module in (merge_guard, push_guard, signing_guard, review_guard, stop_continue_guard):
            with self.subTest(module.__name__):
                self.assertEqual(self.run_main(module, ls, self.work)[3], "1")
                self.assertIsNone(self.run_main(module, ls, self.owner)[3])


class MergeGuardTests(Base):
    def test_a_registered_session_is_headless_to_the_merge_guard(self):
        """Fails if: a T3 triage session may push a non-lane branch (the headless allow-list does not apply)."""
        payload = {"tool_name": "Bash", "tool_input": {"command": "git push origin report/42"}, "cwd": str(REPO)}
        registered = self.run_main(merge_guard, payload, self.work)
        plain = self.run_main(merge_guard, payload, self.owner)
        self.assertEqual(registered[0], 2)
        self.assertIn("only refs/heads/agents/*", registered[2])
        self.assertNotIn("only refs/heads/agents/*", plain[2])

    def test_the_new_markers_cannot_be_unset_or_changed(self):
        """Fails if: a landing command can drop the variables that find the registry record."""
        for command in ("unset T3CODE_THREAD_ID; tools/pr_land.sh 5", "env -u CLAUDE_PROJECT_DIR tools/pr_land.sh 5",
                        "env --unset=CLAUDE_ENV_FILE tools/pr_land.sh 5", "T3CODE_THREAD_ID=x tools/pr_land.sh 5",
                        "CLAUDE_PROJECT_DIR=/tmp tools/pr_land.sh 5", "export -n T3CODE_THREAD_ID"):
            with self.subTest(command):
                self.assertIn("session markers", merge_guard.headless_land_reason(command) or "")
        self.assertNotIn("session markers", merge_guard.headless_land_reason("tools/pr_land.sh 5") or "")


class PushGuardTests(Base):
    def test_the_new_markers_cannot_be_cleared(self):
        """Fails if: push_guard lets a command unset or blank what finds the registry record."""
        for command in ("unset T3CODE_THREAD_ID", "env -u CLAUDE_PROJECT_DIR git status", "git status; unset CLAUDE_ENV_FILE",
                        "T3CODE_THREAD_ID= git status", "CLAUDE_PROJECT_DIR='' git status"):
            with self.subTest(command):
                self.assertIn("agent-session marker", push_guard.command_reason(command))
        self.assertEqual(push_guard.command_reason("CLAUDE_PROJECT_DIR=/x git status"), "")


class SigningGuardTests(Base):
    def test_a_registered_session_is_an_agent_session(self):
        """Fails if: a T3 triage session may run a signing command the headless runner refuses."""
        payload = {"tool_name": "Bash", "tool_input": {"command": "security find-identity -v"}, "cwd": str(REPO)}
        self.assertEqual(self.run_main(signing_guard, payload, self.work)[0], 2)
        self.assertEqual(self.run_main(signing_guard, payload, self.owner)[0], 0)


class ReviewGuardTests(Base):
    def test_a_registered_session_may_not_write_a_review_verdict(self):
        """Fails if: a T3 triage session may write build/review/*.json, which the headless runner may not."""
        def payload(project):
            return {"tool_name": "Write", "tool_input": {"file_path": str(project / "build" / "review" / "pr-1.json")}, "cwd": str(project)}
        self.assertEqual(self.run_main(review_guard, payload(self.work), self.work)[0], 2)
        self.assertEqual(self.run_main(review_guard, payload(self.owner), self.owner)[0], 0)


class StopContinueTests(Base):
    def test_a_registered_session_is_held_to_the_headless_stop_rule(self):
        """Fails if: the Stop hook stays interactive (a no-op) for a T3 triage session."""
        with mock.patch.object(stop_continue_guard, "decide", return_value="keep going") as decide:
            code, out, _err, _ = self.run_main(stop_continue_guard, {"hook_event_name": "Stop"}, self.work)
            self.assertEqual((code, json.loads(out)["decision"]), (0, "block"))
            decide.assert_called_once()
            decide.reset_mock()
            code, out, _err, _ = self.run_main(stop_continue_guard, {"hook_event_name": "Stop"}, self.owner)
            self.assertEqual((code, out), (0, ""))
            decide.assert_not_called()

    def test_an_unreadable_payload_never_fails_the_hook(self):
        """Fails if: a bad Stop payload can trap a session."""
        with mock.patch.dict(os.environ, self.env(self.work), clear=True), mock.patch.object(sys, "stdin", io.StringIO("not json")):
            self.assertEqual(stop_continue_guard.main(), 0)


class OwnerPromptLogTests(Base):
    def test_a_registered_session_prompt_is_never_logged_as_the_owners(self):
        """Fails if: a runner prompt from a T3 triage session lands in the owner-prompts log."""
        env = {**self.env(self.owner), "CLAUDE_CODE_ENTRYPOINT": "cli"}
        payload = {"prompt": "fix the thing", "session_id": "s", "hook_event_name": "UserPromptSubmit"}
        self.assertTrue(owner_prompt_log.should_log(payload, env, ancestors=1, clean=True))
        registered = {**env, "CLAUDE_PROJECT_DIR": str(self.work)}
        self.assertFalse(owner_prompt_log.should_log(payload, registered, ancestors=1, clean=True))
        self.assertFalse(owner_prompt_log.should_log({**payload, "cwd": str(self.work)}, env, ancestors=1, clean=True))

    def test_a_corrupt_record_is_not_logged_either(self):
        """Fails if: a strict (untrusted) session is treated as the owner."""
        (self.root / "worktrees" / f"{ts.worktree_key(self.work)}.json").write_text("{oops")
        env = {**self.env(self.work), "CLAUDE_CODE_ENTRYPOINT": "cli"}
        self.assertFalse(owner_prompt_log.should_log({"prompt": "x", "hook_event_name": "UserPromptSubmit"}, env, ancestors=1, clean=True))

    def test_a_failing_lookup_does_not_log(self):
        """Fails if: an error in the registry lookup logs a prompt that may be a runner's."""
        with mock.patch.object(ts, "resolve", side_effect=RuntimeError("boom")):
            self.assertTrue(owner_prompt_log.registered_session({}, {}))


class LandingToolTests(Base):
    def git(self, path):
        subprocess.run(["git", "init", "-q", str(path)], check=True)

    def test_pr_land_owner_session_refuses_a_registered_session(self):
        """Fails if: ack-base style owner checks pass in a T3 triage session whose environment lost the markers."""
        self.git(self.work)
        self.git(self.owner)
        cwd = os.getcwd()
        self.addCleanup(os.chdir, cwd)
        os.chdir(self.work)
        with mock.patch.dict(os.environ, {"T3CODE_THREAD_ID": "thr-9"}, clear=False):
            os.environ.pop("FENTON_HEADLESS", None)
            os.environ.pop("HASS_TRIAGE_ISSUE", None)
            self.assertFalse(pr_land.owner_session(tty=True))
            os.chdir(self.owner)
            self.assertTrue(pr_land.owner_session(tty=True))
        self.assertTrue(pr_land.owner_session({}, tty=True))  # an explicit environment is judged on its own

    def test_pr_land_fails_closed_when_the_registry_module_is_gone(self):
        """Fails if: an unloadable triage_session lets the owner check pass."""
        with mock.patch.object(pr_land, "_triage_session", side_effect=ImportError("gone")):
            self.assertEqual(pr_land.triage_session_env(), {"FENTON_HEADLESS": "1"})
            self.assertFalse(pr_land.owner_session(tty=True))

    def test_lane_land_refuses_a_registered_session_to_land(self):
        """Fails if: lane_land.land runs for a T3 triage session that has no FENTON_HEADLESS in its tool shell."""
        self.git(self.work)
        cwd = os.getcwd()
        self.addCleanup(os.chdir, cwd)
        os.chdir(self.work)
        with mock.patch.dict(os.environ, {"T3CODE_THREAD_ID": "thr-9"}, clear=False):
            os.environ.pop("FENTON_HEADLESS", None)
            with self.assertRaises(lane_land.Refused) as caught:
                lane_land.land("agents/x", "main", clone=self.work, home=self.tmp, reviews_dir=self.tmp)
        self.assertEqual(caught.exception.kind, "headless")

    def test_lane_land_gate_env_comes_from_the_record(self):
        """Fails if: a T3 triage session's tool shell (no markers) is not given the record's env, or an owner checkout is."""
        self.git(self.work)
        self.git(self.owner)
        cwd = os.getcwd()
        self.addCleanup(os.chdir, cwd)
        with mock.patch.dict(os.environ, {"T3CODE_THREAD_ID": "thr-9"}, clear=False):
            os.chdir(self.work)
            self.assertEqual(lane_land.triage_session_env(), RUNNER_ENV)
            os.chdir(self.owner)
            self.assertIsNone(lane_land.triage_session_env())

    def test_the_tools_load_the_registry_module_by_path_in_a_fresh_interpreter(self):
        """Fails if: tools/hooks is not on the path and the by-path load breaks (it fails closed, so every landing would be refused)."""
        code = "import sys; sys.path[:] = [p for p in sys.path if 'hooks' not in p]; import {0}; print({0}.triage_session_env())"
        for tool in ("lane_land", "pr_land"):
            out = subprocess.run([sys.executable, "-c", code.format(tool)], cwd=str(TOOLS), capture_output=True, text=True,
                                 env={"PATH": os.environ.get("PATH", ""), "HOME": str(self.tmp)})
            self.assertEqual((out.stdout.strip(), out.stderr), ("None", ""), tool)

    def test_lane_land_fails_closed_when_the_registry_module_is_gone(self):
        """Fails if: an unloadable triage_session lets lane_land run as the owner."""
        with mock.patch.object(lane_land, "_triage_session", side_effect=ImportError("gone")):
            self.assertEqual(lane_land.triage_session_env(), {"FENTON_HEADLESS": "1"})


class ProtectedSetTests(unittest.TestCase):
    def test_the_guard_files_are_owner_only(self):
        """Fails if: a runner-landed lane could change the registry, the matcher or the deny hook."""
        for name in ("triage_session.py", "deny_rules.py", "triage_deny.py"):
            self.assertTrue(lane_land.matches(f"tools/hooks/{name}", lane_land.protected_set(REPO)), name)


if __name__ == "__main__":
    unittest.main()
