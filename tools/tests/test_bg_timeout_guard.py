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

COVERAGE = "tools/apple_coverage.sh"


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

    def test_an_unbalanced_quote_is_still_read(self):
        self.assertEqual(run_hook(bash(command="echo 'x; " + COVERAGE, run_in_background=True))[0], 2)


if __name__ == "__main__":
    unittest.main()
