"""``tools/hooks/stop_continue_guard.py``: the continue-don't-stop Stop hook, with JSONL fixture transcripts."""

import json
import os
import sys
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import stop_continue_guard as guard  # noqa: E402


def assistant_text(text):
    return {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": text}]}}


def tool_use(name, inp, tid):
    return {"type": "assistant", "message": {"role": "assistant",
                                             "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}]}}


def tool_result(tid, text):
    return {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": text}]}}


def user_text(text):
    return {"type": "user", "message": {"role": "user", "content": text}}


class StopContinueGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.runs = self.dir / "runs"
        self.runs.mkdir()
        patcher = mock.patch.dict(os.environ, {"BG_RUNS_DIR": str(self.runs), "FENTON_HEADLESS": "1"})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)

    def transcript(self, items, raw=None):
        path = self.dir / "t.jsonl"
        path.write_text(raw if raw is not None else "".join(json.dumps(i) + "\n" for i in items))
        return str(path)

    def event(self, items, **extra):
        return {"transcript_path": self.transcript(items), **extra}

    def marker(self, label, pid):
        (self.runs / f"{label}.running").write_text(json.dumps({"pid": pid, "label": label, "started": time.time()}))

    def test_plain_finish_is_allowed(self):
        self.assertIsNone(guard.decide(self.event([user_text("go"), assistant_text("Done. Tests pass.")])))

    def test_waiting_narration_blocks(self):
        for phrase in ["I'll wait for the build.", "Waiting for the run to finish.", "I will report back soon.",
                       "Once it finishes I will check.", "I'll report back when it completes."]:
            reason = guard.decide(self.event([assistant_text(phrase)]))
            self.assertEqual(reason, guard.WAITING_REASON, phrase)

    def test_tool_only_last_message_is_not_narration(self):
        items = [assistant_text("I'll wait."), tool_use("Bash", {"command": "ls"}, "t1"), tool_result("t1", "x")]
        # the last assistant entry is tool-only, so its text is empty
        self.assertIsNone(guard.decide(self.event(items)))

    def test_live_bg_run_job_from_this_session_blocks(self):
        self.marker("ut1", os.getpid())
        items = [tool_use("Bash", {"command": "tools/bg_run.py ut1 -- swift test", "run_in_background": True}, "t1"),
                 assistant_text("Started.")]
        reason = guard.decide(self.event(items))
        self.assertIn("ut1", reason)

    def test_job_from_another_session_does_not_block(self):
        self.marker("other", os.getpid())
        self.assertIsNone(guard.decide(self.event([assistant_text("Done.")])))

    def test_dead_job_does_not_block(self):
        self.marker("ut2", 2 ** 22 + 12345)
        items = [tool_use("Bash", {"command": "tools/bg_run.py ut2 -- x"}, "t1"), assistant_text("Done.")]
        self.assertIsNone(guard.decide(self.event(items)))

    def test_pending_background_agent_blocks_until_notified(self):
        launch = [tool_use("Agent", {"description": "Coder A", "run_in_background": True, "prompt": "p"}, "a1"),
                  tool_result("a1", "Async agent launched. agentId: abc123def456"), assistant_text("Launched.")]
        self.assertIn("Coder A", guard.decide(self.event(launch)))
        done = launch + [user_text("<task-notification>abc123def456 completed</task-notification>"),
                         assistant_text("Merged.")]
        self.assertIsNone(guard.decide(self.event(done)))

    LAUNCH = [tool_use("Agent", {"description": "Coder A", "run_in_background": True, "prompt": "p"}, "a1"),
              tool_result("a1", "Async agent launched. agentId: abc123def456"), assistant_text("Launched.")]

    def test_queue_operation_notice_clears_agent(self):
        """Fails if: a completion notice stored as a queue-operation entry leaves the agent reported as running."""
        notice = {"type": "queue-operation", "operation": "enqueue", "content":
                  "<task-notification><task-id>abc123def456</task-id><status>completed</status></task-notification>"}
        self.assertIsNone(guard.decide(self.event(self.LAUNCH + [notice, assistant_text("Merged.")])))

    def test_missing_notice_keeps_background_reason(self):
        """Fails if: an agent with no completion notice stops blocking, or the reason loses the agent name."""
        reason = guard.decide(self.event(self.LAUNCH))
        self.assertIn("Coder A", reason)
        self.assertIn("Background work you started is still running", reason)

    def test_attachment_notice_clears_agent(self):
        """Fails if: a completion notice stored as an attachment entry leaves the agent reported as running."""
        notice = {"type": "attachment", "attachment": {"type": "queued_command", "prompt":
                  "<task-notification><task-id>abc123def456</task-id><status>completed</status></task-notification>"}}
        self.assertIsNone(guard.decide(self.event(self.LAUNCH + [notice, assistant_text("Merged.")])))

    def test_reason_tells_headless_agent_not_to_wait(self):
        """Fails if: the block reason mentions waiting_bg no more, or again says to wait for a notification."""
        reason = guard.decide(self.event(self.LAUNCH))
        self.assertIn("waiting_bg", reason)
        self.assertNotIn("Wait for its notification", reason)

    NOTICE = "<task-notification><task-id>%s</task-id><status>completed</status></task-notification>"

    def test_user_content_task_id_notice_clears_agent(self):
        """Fails if: a user-content notice naming the agent by <task-id> leaves it reported as running."""
        done = self.LAUNCH + [user_text(self.NOTICE % "abc123def456"), assistant_text("Merged.")]
        self.assertIsNone(guard.decide(self.event(done)))

    def test_launch_entry_with_notification_prompt_still_blocks(self):
        """Fails if: toolUseResult metadata on the launch entry (a prompt mentioning task-notification) clears the agent."""
        launch = dict(self.LAUNCH[1], toolUseResult={"prompt": self.NOTICE % "abc123def456", "agentId": "abc123def456"})
        items = [self.LAUNCH[0], launch, assistant_text("Launched.")]
        self.assertIn("Coder A", guard.decide(self.event(items)))

    def test_other_agents_notice_with_metadata_id_still_blocks(self):
        """Fails if: gitBranch/cwd metadata holding the running id lets another agent's notice clear it."""
        notice = {"type": "queue-operation", "operation": "enqueue", "content": self.NOTICE % "zzz999yyy888",
                  "gitBranch": "worktree-agent-abc123def456", "cwd": "/w/worktree-agent-abc123def456",
                  "origin": {"kind": "task-notification"}}
        user = dict(user_text(self.NOTICE % "zzz999yyy888"), gitBranch="worktree-agent-abc123def456",
                    cwd="/w/worktree-agent-abc123def456", origin={"kind": "task-notification"})
        self.assertIn("Coder A", guard.decide(self.event(self.LAUNCH + [notice, user])))

    def test_compact_summary_still_blocks(self):
        """Fails if: a compact-summary entry (turnOrigin task_notification) naming the running id clears the agent."""
        summary = dict(user_text("Summary: task-notification pending, lane abc123def456 still running"),
                       isCompactSummary=True, turnOrigin="task_notification")
        self.assertIn("Coder A", guard.decide(self.event(self.LAUNCH + [summary])))

    def test_notices_for_other_task_ids_still_block(self):
        """Fails if: a queue-operation or attachment notice for a different task-id clears the agent."""
        queue = {"type": "queue-operation", "operation": "enqueue", "content": self.NOTICE % "zzz999yyy888"}
        attach = {"type": "attachment", "attachment": {"type": "queued_command", "prompt": self.NOTICE % "zzz999yyy888"}}
        self.assertIn("Coder A", guard.decide(self.event(self.LAUNCH + [queue, attach])))

    def test_waiting_reason_headless(self):
        """Fails if: WAITING_REASON again promises a notification will wake the agent or drops waiting_bg."""
        self.assertIn("waiting_bg", guard.WAITING_REASON)
        self.assertNotIn("will wake you", guard.WAITING_REASON.replace("no notification will wake you", ""))
        self.assertIn("no notification will wake you", guard.WAITING_REASON)

    def test_foreground_agent_does_not_block(self):
        items = [tool_use("Agent", {"description": "x", "prompt": "p"}, "a1"),
                 tool_result("a1", "agentId: abc123def456"), assistant_text("Done.")]
        self.assertIsNone(guard.decide(self.event(items)))

    def test_stop_hook_active_allows(self):
        self.marker("ut3", os.getpid())
        items = [tool_use("Bash", {"command": "tools/bg_run.py ut3 -- x"}, "t1"), assistant_text("I'll wait.")]
        self.assertIsNone(guard.decide(self.event(items, stop_hook_active=True)))

    def test_malformed_input_allows(self):
        self.assertIsNone(guard.decide({}))
        self.assertIsNone(guard.decide({"transcript_path": "/nonexistent/x.jsonl"}))
        self.assertIsNone(guard.decide({"transcript_path": self.transcript([], raw="not json\n{bad\n\x00\n")}))

    def test_main_prints_block_json_and_swallows_errors(self):
        import io
        path = self.transcript([assistant_text("I'll wait.")])
        with mock.patch("sys.stdin", io.StringIO(json.dumps({"transcript_path": path}))), \
                mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            self.assertEqual(guard.main(), 0)
        self.assertEqual(json.loads(out.getvalue())["decision"], "block")
        with mock.patch("sys.stdin", io.StringIO("garbage")), mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            self.assertEqual(guard.main(), 0)
        self.assertEqual(out.getvalue(), "")

    def test_main_allows_without_headless_env_even_with_live_marker_and_waiting(self):
        import io
        (self.runs / "ut3.running").write_text(str(os.getpid()))
        items = [tool_use("Bash", {"command": "tools/bg_run.py ut3 -- x"}, "t1"), assistant_text("I'll wait.")]
        payload = json.dumps({"transcript_path": self.transcript(items)})
        for value in (None, "0", ""):
            env = {k: v for k, v in os.environ.items() if k != "FENTON_HEADLESS"}
            if value is not None:
                env["FENTON_HEADLESS"] = value
            with mock.patch.dict(os.environ, env, clear=True), mock.patch("sys.stdin", io.StringIO(payload)), \
                    mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                self.assertEqual(guard.main(), 0)
            self.assertEqual(out.getvalue(), "")
        with mock.patch("sys.stdin", io.StringIO(payload)), mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            self.assertEqual(guard.main(), 0)
        self.assertEqual(json.loads(out.getvalue())["decision"], "block")

    def test_large_transcript_is_fast(self):
        line = json.dumps(assistant_text("x" * 900)) + "\n"
        raw = line * 60000 + json.dumps(assistant_text("Done.")) + "\n"  # about 55 MB
        path = self.transcript([], raw=raw)
        start = time.perf_counter()
        self.assertIsNone(guard.decide({"transcript_path": path}))
        self.assertLess(time.perf_counter() - start, 0.5)


if __name__ == "__main__":
    unittest.main()
