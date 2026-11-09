"""``tools/hooks/merge_guard.py``: no session writes the ruleset, branch protection, repository settings or App installations.

The ruleset ``main-checks`` (pr-checks and ai-review, no bypass) is the server-side gate; an agent runs as the owner's ``gh`` login, an admin,
so only this guard keeps it from weakening the gate. The owner's own terminal is unaffected (hooks run in agent sessions only).
"""

import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import merge_guard  # noqa: E402

REPO = "repos/SFenton/native-home"


def verdict(cmd, headless=""):
    with mock.patch.dict("os.environ", {"FENTON_HEADLESS": headless}):
        return merge_guard.reason(cmd)


class RepoAdminWriteTests(unittest.TestCase):
    def test_ruleset_and_settings_writes_are_blocked(self):
        """Fails if: ``gh api`` writes to rulesets or the repository root pass (they did: exit 0 on both, so an agent could disarm the gate)."""
        for cmd in (f"gh api -X PUT {REPO}/rulesets/1 --input r.json", f"gh api -X PATCH {REPO} -f allow_auto_merge=false",
                    f"gh api -X POST {REPO}/rulesets --input r.json", f"gh api -X DELETE {REPO}/rulesets/26774461",
                    f"gh api --method PUT {REPO}/rulesets/1 --input r.json", f"gh api --method=PUT {REPO}/rulesets/1 --input r.json",
                    f"gh api -XPUT {REPO}/rulesets/1 --input r.json", f"gh api {REPO}/rulesets -f name=x",
                    f"gh api -X PUT {REPO}/branches/main/protection --input p.json", f"gh api -X DELETE {REPO}/branches/main/protection",
                    f"gh api -X PUT {REPO}/branches/release/x/protection/required_status_checks",
                    "gh api -X PATCH repos/{owner}/{repo} -f allow_squash_merge=false", f"gh api -X PATCH /{REPO} -f delete_branch_on_merge=false",
                    f"gh api -X PATCH {REPO} -F allow_merge_commit=true", "gh api -X PUT orgs/SFenton/rulesets/1 --input r.json",
                    "gh api -X PATCH app/hook/config -f url=x", "gh api -X PATCH /app/installations/5 -f x=1", "gh api -X PUT user/installations/5/repositories/9",
                    "gh api -X DELETE app/installations/5", "gh api -X POST app-manifests/CODE/conversions",
                    f"cd x && gh api -X PUT {REPO}/rulesets/1 --input r.json", f"env GH_TOKEN=t gh api -X PUT {REPO}/rulesets/1 --input r.json",
                    f"gh api -X PUT {REPO}/rulesets/1 --input r.json | cat", f"bash -c 'gh api -X PUT {REPO}/rulesets/1 --input r.json'",
                    f"gh api graphql -f query='mutation {{ updateRepositoryRuleset(input: {{}}) {{ clientMutationId }} }}'",
                    f"gh api graphql -f query='mutation {{ deleteBranchProtectionRule(input: {{}}) {{ clientMutationId }} }}'",
                    "gh api graphql -f query='mutation { createRepositoryRuleset(input: {}) { clientMutationId } }'",
                    "gh repo edit SFenton/native-home --enable-auto-merge=false", "gh repo edit --delete-branch-on-merge=false"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(verdict(cmd), cmd)
                self.assertIn("repo admin", verdict(cmd) or "")

    def test_the_last_method_wins(self):
        """Fails if: the first -X/--method is used (gh uses the last), so `-X GET ... -X PUT` slips past as a read."""
        for cmd in (f"gh api -X GET {REPO}/rulesets/1 -X PUT --input r.json", f"gh api --method GET -X PUT {REPO}/rulesets/1 --input r.json",
                    f"gh api -X PUT -X GET {REPO}/rulesets/1 -f a=b -X DELETE"):
            with self.subTest(cmd=cmd):
                self.assertIn("repo admin", verdict(cmd) or "")
        self.assertIsNone(verdict(f"gh api -X PUT -X GET {REPO}/rulesets/1"))

    def test_query_strings_trailing_slashes_and_repository_ids_match(self):
        """Fails if: the path is matched literally, so a query string, a trailing slash or the `repositories/ID` form hides the target."""
        for cmd in (f"gh api -X PUT {REPO}/rulesets?x=1 --input r.json", f"gh api -X PUT {REPO}/rulesets/1/ --input r.json",
                    f"gh api -X PATCH {REPO}?x=1 -f allow_auto_merge=false", f"gh api -X PATCH {REPO}/ -f allow_auto_merge=false",
                    "gh api -X PUT repositories/123/rulesets/1 --input r.json", "gh api -X PATCH repositories/123 -f allow_auto_merge=false",
                    "gh api -X PUT repositories/123/branches/main/protection --input p.json",
                    f"gh api -X PUT '{REPO}/branches/main/protection?x=1' --input p.json",
                    f"gh api -X PUT https://api.github.com/{REPO}/rulesets/1 --input r.json"):
            with self.subTest(cmd=cmd):
                self.assertIn("repo admin", verdict(cmd) or "")

    def test_a_field_value_that_mentions_a_ruleset_path_is_text(self):
        """Fails if: any non-option word counts as a path, so a comment body naming .../rulesets/N is blocked (false positive)."""
        for cmd in (f"gh api -X POST {REPO}/issues/5/comments -f body='see {REPO}/rulesets/1'",
                    f"gh api {REPO}/issues/5/comments -f body={REPO}/rulesets/26774461",
                    f"gh api -X PATCH {REPO}/pulls/5 -f body=x -F note=repos/o/n"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(verdict(cmd), cmd)

    def test_blocked_for_headless_sessions_too(self):
        self.assertIn("repo admin", verdict(f"gh api -X PUT {REPO}/rulesets/1 --input r.json", headless="1"))

    def test_reads_and_other_writes_stay_allowed(self):
        for cmd in (f"gh api {REPO}/rulesets/26774461", f"gh api {REPO}/rulesets", f"gh api {REPO}/rules/branches/main", "gh ruleset list",
                    "gh ruleset view 1", f"gh api {REPO}/commits/abc/check-runs", f"gh api -X GET {REPO}/rulesets/1",
                    f"gh api -X POST {REPO}/issues/5/comments -f body=x", f"gh api {REPO}/branches/main/protection",
                    f"gh api {REPO}", f"gh api {REPO}/pulls/5 -q .title", f"gh api -X PATCH {REPO}/issues/5 -f state=closed",
                    "grep -n rulesets f", "grep -n 'gh api -X PUT repos/o/n/rulesets/1' notes.md", "gh repo view SFenton/native-home",
                    f"gh api {REPO}/rulesets/1 && gh api -X POST {REPO}/issues/5/comments -f body=x",
                    f"gh api {REPO}/rulesets/1 > r.json; gh api -X POST {REPO}/issues/5/comments -f body=x",
                    "gh api -f 'note=rulesets' -X POST repos/o/n/issues/5/comments", "gh repo edit --description x"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(verdict(cmd), cmd)

    def test_the_message_names_the_refusal(self):
        self.assertIn("rulesets", merge_guard.MESSAGE)
        self.assertIn("branch protection", merge_guard.MESSAGE)


class AdminMergeTests(unittest.TestCase):
    def test_admin_merge_is_refused_with_its_own_reason(self):
        for cmd in ("gh pr merge 12 --admin", "gh pr merge --admin 12 --squash", "gh pr merge 12 -R SFenton/native-home --squash --admin",
                    "gh pr merge 12 --auto --squash --admin"):
            with self.subTest(cmd=cmd):
                self.assertIn("--admin", verdict(cmd))


if __name__ == "__main__":
    unittest.main()
