"""``tools/hooks/merge_guard.py``: no session writes the ruleset, branch protection, repository settings or App installations.

The ruleset ``main-checks`` (pr-checks and ai-review, no bypass) is the server-side gate; an agent runs as the owner's ``gh`` login, an admin,
so only this guard keeps it from weakening the gate. The owner's own terminal is unaffected (hooks run in agent sessions only).
"""

import sys
import tempfile
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


MUTATION = "mutation { updateRepositoryRuleset(input: {}) { clientMutationId } }"
QUERY = "query { viewer { login } }"


class GhApiParserTableTests(unittest.TestCase):
    """One parser for ``gh api`` arguments: clustered short flags, ``--flag=value``, value flags, endpoint forms, last method, GraphQL."""

    def rows(self, tmp):
        mut, qry = Path(tmp) / "m.graphql", Path(tmp) / "q.graphql"
        mut.write_text(MUTATION)
        qry.write_text(QUERY)
        R = REPO
        return [
            # (shape, command, blocked)
            ("clustered -iX PUT", f"gh api -iX PUT {R}/rulesets/1 --input r.json", True),
            ("clustered -iXDELETE", f"gh api -iXDELETE {R}/rulesets/1", True),
            ("clustered -iF k=v", f"gh api -iF k=v {R}/rulesets/1", True),
            ("-XPUT", f"gh api -XPUT {R}/rulesets/1 --input r.json", True),
            ("--method=PUT", f"gh api --method=PUT {R}/rulesets/1 --input r.json", True),
            ("--method PUT", f"gh api --method PUT {R}/rulesets/1 --input r.json", True),
            ("last method wins", f"gh api -X GET {R}/rulesets/1 -X PUT --input r.json", True),
            ("implicit POST from -f", f"gh api {R}/rulesets -f name=x", True),
            ("implicit POST from --input", f"gh api {R}/rulesets/1 --input r.json", True),
            ("--hostname before", f"gh api --hostname github.com -X PUT {R}/rulesets/1 --input r.json", True),
            ("--hostname after", f"gh api -X PUT {R}/rulesets/1 --hostname github.com --input r.json", True),
            ("--hostname=", f"gh api --hostname=github.com -X PUT {R}/rulesets/1 --input r.json", True),
            ("leading slash", f"gh api -X PUT /{R}/rulesets/1 --input r.json", True),
            ("full URL", f"gh api -X PUT https://api.github.com/{R}/rulesets/1 --input r.json", True),
            ("GHES URL", f"gh api -X PUT https://ghe.example.com/api/v3/{R}/rulesets/1 --input r.json", True),
            ("query string", f"gh api -X PUT '{R}/rulesets?x=1' --input r.json", True),
            ("trailing slash", f"gh api -X PUT {R}/rulesets/1/ --input r.json", True),
            ("repositories/ID", "gh api -X PUT repositories/123/rulesets/1 --input r.json", True),
            ("repo root PATCH", f"gh api -X PATCH {R} -f allow_auto_merge=false", True),
            ("repo root URL", f"gh api -X PATCH https://api.github.com/{R} -f allow_auto_merge=false", True),
            ("placeholders", "gh api -X PUT repos/{owner}/{repo}/rulesets/1 --input r.json", True),
            ("GH_REPO relative", "GH_REPO=SFenton/native-home gh api -X PUT repos/{owner}/{repo}/rulesets/1 --input r.json", True),
            ("branch protection", f"gh api -X PUT {R}/branches/main/protection --input p.json", True),
            ("App installation", "gh api -X PUT user/installations/5/repositories/9", True),
            ("graphql bare", f"gh api graphql -f query='{MUTATION}'", True),
            ("graphql /graphql", f"gh api /graphql -f query='{MUTATION}'", True),
            ("graphql full URL", f"gh api https://api.github.com/graphql -f query='{MUTATION}'", True),
            ("graphql GHES URL", f"gh api https://ghe.example.com/api/graphql -f query='{MUTATION}'", True),
            ("graphql clustered", f"gh api -iF query='{MUTATION}' graphql", True),
            ("graphql --input mutation file", f"gh api graphql --input {mut}", True),
            ("graphql query=@file mutation", f"gh api graphql -F query=@{mut}", True),
            ("graphql --input unreadable", f"gh api graphql --input {tmp}/missing.json", True),
            ("graphql --input stdin", "gh api graphql --input -", True),
            ("graphql branch protection", "gh api graphql -f query='mutation { deleteBranchProtectionRule(input: {}) { clientMutationId } }'", True),
            ("graphql repository settings", "gh api graphql -f query='mutation { updateRepository(input: {}) { clientMutationId } }'", True),
            ("unknown flag hides the endpoint", f"gh api --frobnicate x -X PUT {R}/rulesets/1 --input r.json", True),
            ("unknown short flag", f"gh api -Z -X PUT {R}/rulesets/1 --input r.json", True),
            ("missing flag value", f"gh api -X PUT {R}/rulesets/1 --input", True),
            ("GET ruleset", f"gh api {R}/rulesets/26774461", False),
            ("GET rulesets list", f"gh api {R}/rulesets", False),
            ("explicit GET with fields", f"gh api -X GET {R}/rulesets -f per_page=5", False),
            ("last method GET", f"gh api -X PUT -X GET {R}/rulesets/1", False),
            ("-iX GET", f"gh api -iX GET {R}/rulesets/1", False),
            ("GET protection", f"gh api {R}/branches/main/protection", False),
            ("GET repo root", f"gh api {R}", False),
            ("GET --paginate", f"gh api --paginate {R}/rulesets", False),
            ("comment body mentions rulesets", f"gh api -X POST {R}/issues/5/comments -f body='see {R}/rulesets/1'", False),
            ("comment body clustered", f"gh api -iF body={R}/rulesets/1 {R}/issues/5/comments", False),
            ("comment body --raw-field=", f"gh api --raw-field=body={R}/rulesets/1 {R}/issues/5/comments", False),
            ("issue patch", f"gh api -X PATCH {R}/issues/5 -f state=closed", False),
            ("graphql query", f"gh api graphql -f query='{QUERY}'", False),
            ("graphql query --input file", f"gh api graphql --input {qry}", False),
            ("graphql query @file", f"gh api graphql -F query=@{qry}", False),
            ("check-runs", f"gh api {R}/commits/abc/check-runs", False),
        ]

    def test_every_shape(self):
        """Fails if: a clustered short flag (`-iX PUT`), a `/graphql` or full-URL graphql endpoint, `--input` graphql, an unclassifiable
        call or a field value is mishandled (the shapes the round 1-2 reviews found slipping past or blocking a comment)."""
        with tempfile.TemporaryDirectory() as tmp:
            for shape, cmd, blocked in self.rows(tmp):
                with self.subTest(shape=shape):
                    why = verdict(cmd)
                    if blocked:
                        self.assertIn("repo admin", why or "", cmd)
                    else:
                        self.assertIsNone(why, cmd)

    def test_the_parser_reads_clusters_and_endpoints(self):
        call = merge_guard.ApiCall(["-iXDELETE", "https://h.example/api/v3/repos/o/n/rulesets/1/?x=1"])
        self.assertEqual((call.methods, call.endpoint, call.writes, call.understood), (["DELETE"], "repos/o/n/rulesets/1", True, True))
        call = merge_guard.ApiCall(["-iF", "k=v", "--hostname=h", "-q", ".x", "repos/o/n"])
        self.assertEqual((call.fields, call.endpoint, call.writes), (["k=v"], "repos/o/n", True))
        self.assertFalse(merge_guard.ApiCall(["--nope", "x"]).understood)


class AdminMergeTests(unittest.TestCase):
    def test_admin_merge_is_refused_with_its_own_reason(self):
        for cmd in ("gh pr merge 12 --admin", "gh pr merge --admin 12 --squash", "gh pr merge 12 -R SFenton/native-home --squash --admin",
                    "gh pr merge 12 --auto --squash --admin"):
            with self.subTest(cmd=cmd):
                self.assertIn("--admin", verdict(cmd))


if __name__ == "__main__":
    unittest.main()
