"""Agent hooks: ``no_poll.py`` and ``agent_model.py``."""

import io
import json
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import agent_model  # noqa: E402
import no_poll  # noqa: E402

#: Commands lifted from the transcripts that cost a turn per ten minutes.
POLLS = [
    'until grep -q "exited with code" /private/tmp/x/tasks/bl0h.output 2>/dev/null; do sleep 15; done; cat /private/tmp/x/tasks/bl0h.output',
    "for i in $(seq 1 58); do [ -f $D/r.done ] && break; sleep 10; done; cat $D/r.log",
    "L=build1.log; until grep -qE '^rc=' $L; do sleep 5; done; tail -3 $L",
    "i=0; until grep -q done $L || [ $i -ge 38 ]; do sleep 3; i=$((i+1)); done",
    "while kill -0 34497 2>/dev/null; do sleep 5; done; echo done",
    "xcodebuild test ... ; sleep 120; cat out.log",
    "sleep 2m && cat out.log",
    "tail -f build/runs/x.log",
]
#: Ordinary commands, including ones that mention sleeping.
FINE = [
    "sleep 2; ps aux | grep -c '[s]wift-build'",
    "git status --short",
    "tools/bg_run.py uitest-iphone -- tools/ios_uitest.sh --only iphone",
    "python3 - <<'EOF'\nimport time\nwhile True:\n    do = 1\n    sleep 60\nEOF\necho ok",
    "grep -n 'Task.sleep' apple/Sources/HassCore/*.swift | head",
    "until grep -q ready log; do sleep 5; done  # poll-ok: sim boot, 20 s at most",
]


def run_hook(payload):
    err = io.StringIO()
    with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), redirect_stderr(err):
        status = no_poll.main()
    return status, err.getvalue()


class NoPollTests(unittest.TestCase):
    def test_blocks_polls_seen_in_the_transcripts(self):
        for command in POLLS:
            with self.subTest(command=command[:50]):
                status, message = run_hook({"tool_name": "Bash", "tool_input": {"command": command}})
                self.assertEqual(status, 2)
                self.assertIn("run_in_background", message)

    def test_allows_ordinary_commands(self):
        for command in FINE:
            with self.subTest(command=command[:50]):
                self.assertEqual(run_hook({"tool_name": "Bash", "tool_input": {"command": command}})[0], 0)

    def test_ignores_other_tools_and_bad_input(self):
        self.assertEqual(run_hook({"tool_name": "Read", "tool_input": {"file_path": "x"}})[0], 0)
        with mock.patch.object(sys, "stdin", io.StringIO("not json")):
            self.assertEqual(no_poll.main(), 0)


def run_agent_hook(tool_input, tool_name="Agent"):
    err = io.StringIO()
    with mock.patch.object(sys, "stdin", io.StringIO(json.dumps({"tool_name": tool_name, "tool_input": tool_input}))), redirect_stderr(err):
        return agent_model.main(), err.getvalue()


class AgentModelTests(unittest.TestCase):
    def test_lane_agents_and_cheap_models_pass(self):
        for spec in ({"subagent_type": "coder"}, {"subagent_type": "menial"}, {"subagent_type": "Explore"},
                     {"subagent_type": "Plan"}, {"subagent_type": "general-purpose", "model": "sonnet"},
                     {"model": "haiku"}, {"subagent_type": "general-purpose", "model": "gh/claude-sonnet-5.5"}):
            with self.subTest(spec=spec):
                self.assertEqual(run_agent_hook({**spec, "prompt": "do it"})[0], 0)

    def test_inherited_or_explicit_opus_is_refused(self):
        for spec in ({"subagent_type": "general-purpose"}, {}, {"model": "opus"}, {"subagent_type": "coder", "model": "opus"},
                     {"subagent_type": "general-purpose", "model": "gh/claude-opus-5.5"}):
            with self.subTest(spec=spec):
                status, message = run_agent_hook({**spec, "prompt": "do it"})
                self.assertEqual(status, 2)
                self.assertIn("coder", message)

    def test_fable_only_for_designer_and_explicit_coder_researcher(self):
        """Fails if supported Fable aliases are blocked or leak into unchanged roles."""
        for model in ("fable", "claude-fable-5-2"):
            for kind in ("designer", "coder", "researcher"):
                for effort in ("medium", "high"):
                    with self.subTest(model=model, kind=kind, effort=effort):
                        self.assertEqual(run_agent_hook({"subagent_type": kind, "model": model,
                                                         "effort": effort, "prompt": "go"})[0], 0)
        for kind in ("reviewer", "verifier", "steward", "menial", "general-purpose", None):
            with self.subTest(kind=kind):
                self.assertEqual(run_agent_hook({"subagent_type": kind, "model": "claude-fable-5-2", "prompt": "opus-ok: x"})[0], 2)

    def test_designer_still_refuses_explicit_opus(self):
        self.assertEqual(run_agent_hook({"subagent_type": "designer", "model": "opus", "prompt": "go"})[0], 2)

    def test_opus_ok_in_the_prompt_allows_the_final_reviewer(self):
        self.assertEqual(run_agent_hook({"subagent_type": "general-purpose", "model": "opus",
                                         "prompt": "Review the diff. opus-ok: final review"})[0], 0)

    def test_opus_ok_cannot_approve_inherited_fable(self):
        """Fails if approval without an Opus model permits inherited Fable."""
        for kind in ("general-purpose", "coder", None):
            with self.subTest(kind=kind):
                self.assertEqual(run_agent_hook({"subagent_type": kind,
                                                 "prompt": "opus-ok: final review"})[0], 2)
        self.assertEqual(run_agent_hook({"subagent_type": "reviewer",
                                         "prompt": "opus-ok: final review"})[0], 0)

    def test_other_tools_and_bad_input_pass(self):
        self.assertEqual(run_agent_hook({"command": "ls"}, tool_name="Bash")[0], 0)
        self.assertEqual(run_agent_hook({"subagent_type": "general-purpose"}, tool_name="Task")[0], 2)
        with mock.patch.object(sys, "stdin", io.StringIO("nope")):
            self.assertEqual(agent_model.main(), 0)


if __name__ == "__main__":
    unittest.main()
