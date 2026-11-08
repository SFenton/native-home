"""tools/ruleset_gate.py: auto-merge is armed only while the live ruleset requires an approval and the pr-checks check."""

import contextlib
import io
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ruleset_gate as gate  # noqa: E402

PULL = {"type": "pull_request", "parameters": {"required_approving_review_count": 1, "dismiss_stale_reviews_on_push": True}}
CHECKS = {"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "pr-checks", "integration_id": 15368}]}}


class RulesetGateTests(unittest.TestCase):
    def test_both_rules_arm(self):
        self.assertEqual(gate.problems([{"type": "deletion"}, PULL, CHECKS]), [])
        self.assertEqual(gate.check("SFenton/native-home", fetch=lambda repo, branch: [PULL, CHECKS]), [])

    def test_zero_approvals_do_not_arm(self):
        zero = {"type": "pull_request", "parameters": {"required_approving_review_count": 0}}
        self.assertEqual(gate.problems([zero, CHECKS]), ["the ruleset does not require an approving review"])

    def test_a_missing_pull_request_rule_or_check_does_not_arm(self):
        self.assertEqual(len(gate.problems([CHECKS])), 1)
        self.assertEqual(gate.problems([PULL]), ["the ruleset does not require the pr-checks check"])
        other = {"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "something-else"}]}}
        self.assertEqual(len(gate.problems([PULL, other])), 1)
        self.assertEqual(len(gate.problems([])), 2)

    def test_odd_payloads_do_not_arm(self):
        for payload in ("nope", {"message": "Not Found"}, None, [None, "x", {"type": "pull_request"}]):
            with self.subTest(payload=payload):
                self.assertTrue(gate.problems(payload))

    def test_a_failed_fetch_does_not_arm(self):
        def boom(repo, branch):
            raise subprocess.CalledProcessError(1, "gh")
        found = gate.check("SFenton/native-home", fetch=boom)
        self.assertEqual(len(found), 1)
        self.assertIn("could not be fetched", found[0])

    def test_fetch_rules_asks_gh_for_the_branch_rules_and_raises_on_error(self):
        run = mock.Mock(return_value=mock.Mock(stdout='[{"type": "deletion"}]'))
        with mock.patch.object(gate.subprocess, "run", run):
            self.assertEqual(gate.fetch_rules("SFenton/native-home", "main"), [{"type": "deletion"}])
        self.assertEqual(run.call_args[0][0], ["gh", "api", "repos/SFenton/native-home/rules/branches/main"])
        with mock.patch.object(gate.subprocess, "run", side_effect=OSError):
            with self.assertRaises(OSError):
                gate.fetch_rules("SFenton/native-home")

    def test_main_exits_zero_only_when_both_rules_are_live(self):
        for rules, code in (([PULL, CHECKS], 0), ([PULL], 1)):
            out = io.StringIO()
            with mock.patch.object(gate, "fetch_rules", return_value=rules), contextlib.redirect_stdout(out):
                self.assertEqual(gate.main([]), code)
        with mock.patch.object(gate, "fetch_rules", side_effect=OSError), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(gate.main(["--repo", "SFenton/native-home"]), 1)


if __name__ == "__main__":
    unittest.main()
