"""The runner runs ``tools/retro_phase.py --pr N`` for a flow's PR and queues a post-mortem when ``phase_cost`` fires."""
from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_retro_p2 as p2  # noqa: E402

FakeGitHub = p2.FakeGitHub


class RetroPhaseQueueTests(p2.RetroHelpers):
    def archive(self, n, status, phase=None, crash=False, enqueue=True):
        """``archive_evidence`` with a faked ``retro_phase.py`` that writes ``phase`` (or crashes) into ``--out``."""
        runner = self.runner(FakeGitHub([]))
        self.paths.status_file(n).parent.mkdir(parents=True, exist_ok=True)
        self.paths.status_file(n).write_text(json.dumps(status))
        real = runner.run
        self.phase_calls = []

        def run(args, **kw):
            if len(args) > 1 and str(args[1]).endswith("retro_phase.py"):
                self.phase_calls.append(args)
                if crash:
                    raise OSError("boom")
                out = Path(args[args.index("--out") + 1])
                out.mkdir(parents=True, exist_ok=True)
                (out / f"phase-{args[args.index('--pr') + 1]}.json").write_text(json.dumps(phase or {}))
                return subprocess.CompletedProcess(args, 0, "", "")
            return real(args, **kw)

        runner.run = run
        dest = runner.archive_evidence(n, enqueue=enqueue)
        return runner, dest

    def queued(self):
        path = self.paths.state_dir / "state-retro.json"
        return json.loads(path.read_text()).get("queue", []) if path.is_file() else []

    def test_queues_when_only_phase_cost_fires(self):
        _, dest = self.archive(60, {"state": "done", "pr": "https://github.com/o/r/pull/123"}, {"phase_cost": True})
        self.assertEqual(self.phase_calls[0][self.phase_calls[0].index("--pr") + 1], "123")
        self.assertTrue((dest / "retro" / "phase-123.json").is_file())
        self.assertEqual([q["triggers"] for q in self.queued()], [["phase_cost"]])

    def test_does_not_queue_when_neither_fires(self):
        self.archive(61, {"state": "done", "pr": "https://github.com/o/r/pull/124"}, {"phase_cost": False})
        self.assertEqual(self.queued(), [])

    def test_a_flow_without_a_pr_skips_the_script(self):
        self.archive(62, {"state": "blocked"})
        self.assertEqual(self.phase_calls, [])
        self.assertEqual(self.queued(), [])

    def test_a_crashing_script_neither_fails_the_tick_nor_the_queue_decision(self):
        runner, dest = self.archive(63, {"state": "done", "pr": "125"}, crash=True)
        self.assertIsNotNone(dest)
        self.assertEqual(self.queued(), [])
        self.write_digest(dest, runner.task_id(63), ["blocked"])
        self.assertTrue(runner.enqueue_retro(dest, runner.task_id(63)))  # the digest triggers still queue

    def test_a_missing_script_output_or_bad_json_is_ignored(self):
        runner = self.runner(FakeGitHub([]))
        dest = self.paths.root / "archive" / "request-64"
        (dest / "retro").mkdir(parents=True)
        (dest / "retro" / "phase-9.json").write_text("{not json")
        self.assertFalse(runner.enqueue_retro(dest, "R-64"))

    def test_a_retro_archive_does_not_enqueue_or_run_the_script(self):
        _, _ = self.archive(65, {"state": "done", "pr": "126"}, {"phase_cost": True}, enqueue=False)
        self.assertEqual(self.phase_calls, [])
        self.assertEqual(self.queued(), [])


if __name__ == "__main__":
    unittest.main()
