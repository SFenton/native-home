"""tools/ruleset_gate.py: auto-merge is armed only while the live ruleset requires a pull request, the pr-checks check and no bypass."""

import contextlib
import io
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ruleset_gate as gate  # noqa: E402

PULL = {"type": "pull_request", "ruleset_id": 7, "parameters": {"required_approving_review_count": 0, "dismiss_stale_reviews_on_push": False,
                                                                    "require_last_push_approval": False, "allowed_merge_methods": ["squash"]}}
CHECKS = {"type": "required_status_checks", "ruleset_id": 7,
          "parameters": {"required_status_checks": [{"context": "pr-checks", "integration_id": 15368}]}}
NEVER = {"7": {"current_user_can_bypass": "never"}}


def one(repo, ruleset_id):
    return NEVER[str(ruleset_id)]


class RulesetGateTests(unittest.TestCase):
    def test_both_rules_arm(self):
        self.assertEqual(gate.problems([{"type": "deletion"}, PULL, CHECKS], NEVER), [])
        self.assertEqual(gate.check("SFenton/native-home", fetch=lambda repo, branch: [PULL, CHECKS], fetch_one=one), [])

    def test_no_approval_count_is_needed(self):
        """Review happens before the push (tools/review_verdict.py); GitHub keeps only the PR and the check."""
        for count in (0, 1, 2):
            pull = {"type": "pull_request", "ruleset_id": 7, "parameters": {"required_approving_review_count": count}}
            self.assertEqual(gate.problems([pull, CHECKS], NEVER), [], count)
        bare = {"type": "pull_request", "ruleset_id": 7, "parameters": {}}
        self.assertEqual(gate.problems([bare, CHECKS], NEVER), [])

    def test_a_missing_pull_request_rule_or_check_does_not_arm(self):
        self.assertEqual(gate.problems([CHECKS], NEVER), ["the ruleset does not require a pull request"])
        self.assertEqual(len(gate.problems([PULL], NEVER)), 1)
        other = {"type": "required_status_checks", "ruleset_id": 7, "parameters": {"required_status_checks": [{"context": "x"}]}}
        self.assertEqual(len(gate.problems([PULL, other], NEVER)), 1)
        self.assertGreaterEqual(len(gate.problems([], NEVER)), 2)

    def test_squash_must_be_allowed_when_the_rule_lists_merge_methods(self):
        for methods in (["merge"], ["rebase", "merge"], []):
            pull = {"type": "pull_request", "ruleset_id": 7, "parameters": {"allowed_merge_methods": methods}}
            self.assertEqual(gate.problems([pull, CHECKS], NEVER), ["the ruleset does not allow squash merges"], methods)
        pull = {"type": "pull_request", "ruleset_id": 7, "parameters": {"allowed_merge_methods": ["merge", "squash"]}}
        self.assertEqual(gate.problems([pull, CHECKS], NEVER), [])

    def test_the_check_must_come_from_github_actions(self):
        for check in ({"context": "pr-checks"}, {"context": "pr-checks", "integration_id": 1}, {"context": "pr-checks", "integration_id": None}):
            rule = {"type": "required_status_checks", "ruleset_id": 7, "parameters": {"required_status_checks": [check]}}
            found = gate.problems([PULL, rule], NEVER)
            self.assertEqual(len(found), 1, check)
            self.assertIn("15368", found[0])

    def test_the_ruleset_must_allow_no_bypass(self):
        for answer in ("always", "pull_request", None, "", ["never"]):
            found = gate.problems([PULL, CHECKS], {"7": {"current_user_can_bypass": answer}})
            self.assertEqual(len(found), 1, answer)
            self.assertIn("bypassed", found[0])
        self.assertEqual(len(gate.problems([PULL, CHECKS], {"7": "nope"})), 1)
        self.assertEqual(len(gate.problems([PULL, CHECKS], {})), 1)
        self.assertEqual(len(gate.problems([{**PULL, "ruleset_id": None}, {**CHECKS, "ruleset_id": None}], {})), 1)

    def test_check_reads_each_ruleset_and_a_bypassable_one_does_not_arm(self):
        seen = []
        def bypass(repo, ruleset_id):
            seen.append(ruleset_id)
            return {"current_user_can_bypass": "always"}
        found = gate.check("SFenton/native-home", fetch=lambda r, b: [PULL, CHECKS], fetch_one=bypass)
        self.assertEqual(seen, ["7"])
        self.assertEqual(len(found), 1)

    def test_malformed_answers_fail_closed_and_never_raise(self):
        bad = ([{"type": "pull_request", "parameters": []}],
               [{"type": "pull_request", "parameters": {"required_approving_review_count": "many"}}],
               [{"type": "required_status_checks", "parameters": {"required_status_checks": 5}}],
               [{"type": "required_status_checks", "parameters": {"required_status_checks": ["x"]}}],
               [PULL, CHECKS, {"type": "pull_request", "ruleset_id": 7, "parameters": {"allowed_merge_methods": 5}}],
               "nope", None, {"message": "Not Found"})
        for payload in bad:
            with self.subTest(payload=payload):
                self.assertTrue(gate.check("SFenton/native-home", fetch=lambda r, b, p=payload: p, fetch_one=one))
        self.assertTrue(gate.check("SFenton/native-home", fetch=lambda r, b: [PULL, CHECKS], fetch_one=lambda r, i: 5))

    def test_odd_payloads_do_not_arm(self):
        for payload in ("nope", {"message": "Not Found"}, None, [None, "x", {"type": "pull_request"}]):
            with self.subTest(payload=payload):
                self.assertTrue(gate.problems(payload))

    def test_a_failed_fetch_does_not_arm(self):
        def boom(repo, branch):
            raise subprocess.CalledProcessError(1, "gh")
        found = gate.check("SFenton/native-home", fetch=boom)
        self.assertEqual(len(found), 1)
        self.assertIn("could not be read", found[0])

    def test_fetch_rules_asks_gh_for_the_branch_rules_and_raises_on_error(self):
        run = mock.Mock(return_value=mock.Mock(stdout='[{"type": "deletion"}]'))
        with mock.patch.object(gate.subprocess, "run", run):
            self.assertEqual(gate.fetch_rules("SFenton/native-home", "main"), [{"type": "deletion"}])
        self.assertEqual(run.call_args[0][0], ["gh", "api", "repos/SFenton/native-home/rules/branches/main"])
        with mock.patch.object(gate.subprocess, "run", side_effect=OSError):
            with self.assertRaises(OSError):
                gate.fetch_rules("SFenton/native-home")

    def test_fetch_ruleset_asks_gh_for_the_ruleset(self):
        run = mock.Mock(return_value=mock.Mock(stdout='{"current_user_can_bypass": "never"}'))
        with mock.patch.object(gate.subprocess, "run", run):
            self.assertEqual(gate.fetch_ruleset("SFenton/native-home", 7), {"current_user_can_bypass": "never"})
        self.assertEqual(run.call_args[0][0], ["gh", "api", "repos/SFenton/native-home/rulesets/7"])

    def test_main_exits_zero_only_when_the_gate_is_live(self):
        for rules, code in (([PULL, CHECKS], 0), ([PULL], 1), ([CHECKS], 1)):
            out = io.StringIO()
            with mock.patch.object(gate, "fetch_rules", return_value=rules), mock.patch.object(gate, "fetch_ruleset", side_effect=one), \
                    contextlib.redirect_stdout(out):
                self.assertEqual(gate.main([]), code)
        with mock.patch.object(gate, "fetch_rules", side_effect=OSError), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(gate.main(["--repo", "SFenton/native-home"]), 1)


if __name__ == "__main__":
    unittest.main()
