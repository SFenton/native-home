"""``tools/hooks/bg_timeout_guard.py``: the retry text and the fail-open rule (the command table is guard_tables/bg_timeout_guard.tsv)."""

import io
import json
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import bg_timeout_guard  # noqa: E402

COVERAGE = "tools/ios_uitest.sh --full"


def run_hook(raw):
    err = io.StringIO()
    with mock.patch.object(sys, "stdin", io.StringIO(raw)), redirect_stderr(err):
        status = bg_timeout_guard.main()
    return status, err.getvalue()


def bash(**tool_input):
    return json.dumps({"tool_name": "Bash", "tool_input": tool_input})


class BgTimeoutGuardTests(unittest.TestCase):
    def test_denial_gives_the_exact_retry(self):
        status, message = run_hook(bash(command=COVERAGE, run_in_background=True))
        self.assertEqual(status, 2)
        self.assertIn("run_in_background: true and timeout: 4200000", message)
        self.assertIn("7200000", message)
        self.assertIn(COVERAGE, message)

    def test_a_ci_wait_refusal_names_a_runnable_command(self):
        """ci_wait.py is not executable, so the retry example keeps `python3`."""
        for command in ("python3 tools/ci_wait.py 9", "tools/bg_run.py ci -- python3 tools/ci_wait.py 9"):
            with self.subTest(command=command):
                status, message = run_hook(bash(command=command, run_in_background=True))
                self.assertEqual(status, 2)
                self.assertIn("-- python3 tools/ci_wait.py 9", message)
                self.assertIn("timeout: 4200000", message)

    def test_a_long_enough_timeout_allows(self):
        self.assertEqual(run_hook(bash(command=COVERAGE, run_in_background=True, timeout=4200000))[0], 0)

    def test_a_non_numeric_timeout_counts_as_none(self):
        for value in ("4200000", None, True, [4200000]):
            with self.subTest(value=value):
                self.assertEqual(run_hook(bash(command=COVERAGE, run_in_background=True, timeout=value))[0], 2)

    def test_foreground_is_not_this_guards_business(self):
        self.assertEqual(run_hook(bash(command=COVERAGE))[0], 0)
        self.assertEqual(run_hook(bash(command=COVERAGE, run_in_background=False))[0], 0)

    def test_other_tools_pass(self):
        raw = json.dumps({"tool_name": "Read", "tool_input": {"command": COVERAGE, "run_in_background": True}})
        self.assertEqual(run_hook(raw)[0], 0)

    def test_fails_open_on_its_own_errors(self):
        for raw in ("", "not json", "[]", "null", json.dumps({"tool_name": "Bash", "tool_input": "x"}),
                    json.dumps({"tool_name": "Bash", "tool_input": {"command": 5, "run_in_background": True}})):
            with self.subTest(raw=raw[:20]):
                self.assertEqual(run_hook(raw)[0], 0)

    def test_the_coverage_script_is_not_a_long_job(self):
        """Host-only since 2026-11-10 (about ten minutes): a background run needs no long timeout."""
        self.assertEqual(run_hook(bash(command="tools/apple_coverage.sh", run_in_background=True))[0], 0)

    def test_an_unbalanced_quote_is_still_read(self):
        self.assertEqual(run_hook(bash(command="echo 'x; " + COVERAGE, run_in_background=True))[0], 2)


class SubagentBackgroundTests(unittest.TestCase):
    BG_RUN = "tools/bg_run.py x -- true"

    def payload(self, agent_id=True, **tool_input):
        data = {"tool_name": "Bash", "tool_input": tool_input}
        if agent_id:
            data["agent_id"] = "agent-1"
        return json.dumps(data)

    def test_subagent_background_job_is_denied(self):
        status, message = run_hook(self.payload(command=self.BG_RUN, run_in_background=True))
        self.assertEqual(status, 2)
        self.assertIn("600000", message)
        self.assertIn("blocked", message)

    def test_main_session_background_job_passes(self):
        self.assertEqual(run_hook(self.payload(agent_id=False, command=self.BG_RUN, run_in_background=True))[0], 0)

    def test_subagent_foreground_job_passes(self):
        bounded = "tools/bg_run.py x --timeout 570 -- true"
        self.assertEqual(run_hook(self.payload(command=bounded, timeout=600000))[0], 0)
        self.assertEqual(run_hook(self.payload(command=bounded, timeout=600000, run_in_background=False))[0], 0)


class SubagentForegroundTests(unittest.TestCase):
    """A sub-agent's foreground job must end itself before the call's ``timeout``, or the harness moves it to the background."""

    def payload(self, agent_id=True, **tool_input):
        data = {"tool_name": "Bash", "tool_input": tool_input}
        if agent_id:
            data["agent_id"] = "agent-1"
        return json.dumps(data)

    def test_a_bounded_job_is_allowed(self):
        raw = self.payload(command="tools/bg_run.py x --timeout 570 -- true", timeout=600000)
        self.assertEqual(run_hook(raw)[0], 0)

    def test_an_unbounded_job_is_denied_with_the_fix(self):
        status, message = run_hook(self.payload(command="tools/bg_run.py x -- true", timeout=600000))
        self.assertEqual(status, 2)
        self.assertIn("--timeout S", message)
        self.assertIn("at most 570", message)
        self.assertIn("blocked", message)

    def test_a_bound_at_or_over_the_call_timeout_is_denied(self):
        for seconds in (600, 571, 3000):
            with self.subTest(seconds=seconds):
                raw = self.payload(command=f"tools/bg_run.py x --timeout {seconds} -- true", timeout=600000)
                self.assertEqual(run_hook(raw)[0], 2)

    def test_the_call_timeout_must_be_given_and_is_capped(self):
        self.assertEqual(run_hook(self.payload(command="tools/bg_run.py x --timeout 60 -- true"))[0], 2)
        over = self.payload(command="tools/bg_run.py x --timeout 700 -- true", timeout=900000)
        self.assertEqual(run_hook(over)[0], 2)

    def test_a_bare_full_run_is_denied(self):
        self.assertEqual(run_hook(self.payload(command=COVERAGE, timeout=600000))[0], 2)

    def test_the_main_session_is_unaffected(self):
        for tool_input in ({"command": "tools/bg_run.py x -- true"}, {"command": COVERAGE, "timeout": 600000}):
            with self.subTest(tool_input=tool_input):
                self.assertEqual(run_hook(self.payload(agent_id=False, **tool_input))[0], 0)

    def test_a_chain_must_fit_in_total(self):
        fits = "tools/bg_run.py a --timeout 200 -- true && tools/bg_run.py b --timeout 300 -- true"
        over = "tools/bg_run.py a --timeout 300 -- true && tools/bg_run.py b --timeout 300 -- true"
        self.assertEqual(run_hook(self.payload(command=fits, timeout=600000))[0], 0)
        status, message = run_hook(self.payload(command=over, timeout=600000))
        self.assertEqual(status, 2)
        self.assertIn("summed", message)

    def test_every_run_in_a_chain_needs_a_bound(self):
        raw = self.payload(command="tools/bg_run.py a --timeout 100 -- true; tools/bg_run.py b -- true", timeout=600000)
        self.assertEqual(run_hook(raw)[0], 2)

    def test_a_loop_is_denied_with_the_split_advice(self):
        loop = "for i in 1 2 3; do tools/bg_run.py s$i --timeout 100 -- true; done"
        status, message = run_hook(self.payload(command=loop, timeout=600000))
        self.assertEqual(status, 2)
        self.assertIn("one bounded", message)
        self.assertEqual(run_hook(self.payload(agent_id=False, command=loop, timeout=600000))[0], 0)

    def test_a_bg_run_beside_a_bare_full_run_is_denied(self):
        raw = self.payload(command=f"tools/bg_run.py a --timeout 100 -- true && {COVERAGE}", timeout=600000)
        self.assertEqual(run_hook(raw)[0], 2)

    def test_a_path_after_double_dash_is_not_a_run(self):
        for command in ("git diff -- tools/bg_run.py", "git log -- tools/bg_run.py"):
            with self.subTest(command=command):
                self.assertEqual(run_hook(self.payload(command=command, timeout=600000))[0], 0)

    def test_a_name_in_another_command_is_not_a_run(self):
        raw = self.payload(command="grep -n bg_run.py tools/bg_run.py", timeout=600000)
        self.assertEqual(run_hook(raw)[0], 0)


if __name__ == "__main__":
    unittest.main()
