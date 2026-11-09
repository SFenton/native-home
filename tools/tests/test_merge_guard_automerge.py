"""``tools/hooks/merge_guard.py``: the one allowed ``gh pr merge`` (auto-merge on SFenton/native-home), with ``gh`` stubbed.

Review before push: the pinned head needs an independent pass, the ruleset must be the gate (a PR and pr-checks), the PR must be the owner's.
"""

import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import merge_guard  # noqa: E402

HEAD = "a" * 40
GOOD = "gh pr merge 12 -R SFenton/native-home --auto --squash --match-head-commit " + HEAD
BARE = "gh pr merge 12 -R SFenton/native-home --auto --squash"
LIVE = []  # ruleset_gate.check: no problems = the gate is live
MISSING = ["the ruleset does not require a pull request"]


ORIGIN = {"author": {"login": "SFenton"}, "headRepository": {"name": "native-home"}, "headRepositoryOwner": {"login": "SFenton"}}


def pr(base="main"):
    return {"user": {"login": "SFenton"}, "base": {"ref": base}, "head": {"sha": "a" * 40}}


class AutoMergeTests(unittest.TestCase):
    def verdict(self, command, rules=LIVE, pull=None, error=False, headless="", origin=None, passed=True):
        def fake(path):
            if error:
                raise RuntimeError("gh failed")
            return pull if pull is not None else pr()
        facts = ORIGIN if origin is None else origin
        def view(number):
            if facts == "error":
                raise RuntimeError("gh failed")
            return facts
        with mock.patch.object(merge_guard, "gh_json", fake), mock.patch.object(merge_guard, "pr_origin", view), mock.patch.object(merge_guard.ruleset_gate, "check", return_value=rules), \
                mock.patch.object(merge_guard.review_verdict, "has_pass", lambda sha: passed and sha == HEAD), \
                mock.patch.dict("os.environ", {"FENTON_HEADLESS": headless}):
            return merge_guard.reason(command)

    def test_the_allowed_form_passes_while_the_ruleset_is_live(self):
        self.assertIsNone(self.verdict(GOOD))

    def test_flag_order_short_flags_and_the_url_form_pass(self):
        self.assertIsNone(self.verdict("gh pr merge 12 --squash --match-head-commit %s --auto -R SFenton/native-home" % HEAD))
        self.assertIsNone(self.verdict("gh pr merge 12 -s --auto --match-head-commit=%s --repo=https://github.com/sfenton/Native-Home" % HEAD))

    def test_a_missing_ruleset_rule_or_a_failed_fetch_refuses(self):
        self.assertIsNotNone(self.verdict(GOOD, rules=MISSING))
        self.assertIn("pull request", self.verdict(GOOD, rules=MISSING))
        self.assertIsNotNone(self.verdict(GOOD, rules=["the rules of SFenton/native-home could not be fetched (OSError)"]))

    def test_no_pass_for_the_pinned_head_refuses(self):
        self.assertIn("independent pass", self.verdict(GOOD, passed=False))
        other = "b" * 40
        self.assertIn("independent pass", self.verdict(GOOD.replace(HEAD, other)))  # a pass for HEAD does not cover another sha

    def test_a_pin_that_is_not_the_prs_head_refuses(self):
        moved = {"user": {"login": "SFenton"}, "base": {"ref": "main"}, "head": {"sha": "c" * 40}}
        self.assertIn("not the PR's head", self.verdict(GOOD, pull=moved))
        self.assertIsNotNone(self.verdict(GOOD, pull={"user": {}, "base": {"ref": "main"}}))

    def test_the_pin_is_required_and_must_be_a_full_sha(self):
        self.assertIsNotNone(self.verdict(BARE))
        for pin in ("abc123", HEAD[:39], HEAD + "a", HEAD.upper(), "HEAD", "$(git rev-parse HEAD)", ""):
            with self.subTest(pin=pin):
                self.assertIsNotNone(self.verdict("%s --match-head-commit %s" % (BARE, pin)))
        self.assertIsNotNone(self.verdict("%s --match-head-commit %s --match-head-commit %s" % (BARE, HEAD, HEAD)))

    def test_wrong_or_missing_repo_refuses(self):
        pin = " --match-head-commit " + HEAD
        for cmd in ("gh pr merge 12 -R SFenton/Fenton-HASS-Native --auto --squash" + pin,
                    "gh pr merge 12 -R other/native-home --auto --squash" + pin,
                    "gh pr merge 12 --auto --squash" + pin):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.verdict(cmd))

    def test_a_pr_not_based_on_main_or_unreadable_refuses(self):
        self.assertIsNotNone(self.verdict(GOOD, pull=pr(base="release")))
        self.assertIsNotNone(self.verdict(GOOD, error=True))
        self.assertIsNotNone(self.verdict(GOOD, pull={"user": {}}))

    def test_a_foreign_author_or_a_fork_refuses(self):
        fork = {**ORIGIN, "headRepositoryOwner": {"login": "mallory"}}
        renamed = {**ORIGIN, "headRepository": {"name": "other"}}
        other = {**ORIGIN, "author": {"login": "sh-reviewer"}}
        for origin in (fork, renamed, other, "error", {}, {"author": None}, {**ORIGIN, "headRepository": None}):
            with self.subTest(origin=origin):
                self.assertIn("not authored by SFenton", self.verdict(GOOD, origin=origin))
                self.assertIsNotNone(self.verdict("gh pr merge 12 -R SFenton/native-home --disable-auto", origin=origin))

    def test_pr_origin_asks_gh_pr_view_for_the_author_and_head(self):
        run = mock.Mock(return_value=mock.Mock(stdout='{"author": {}}'))
        with mock.patch.object(merge_guard.subprocess, "run", run):
            self.assertEqual(merge_guard.pr_origin("12"), {"author": {}})
        self.assertEqual(run.call_args[0][0], ["gh", "pr", "view", "12", "-R", "SFenton/native-home", "--json",
                                               "author,headRepository,headRepositoryOwner"])

    def test_other_flags_refuse(self):
        for extra in ("--admin", "--merge", "--rebase", "--delete-branch", "-d", "--disable-auto",
                      "--subject x", "--body x", "--body-file m"):
            with self.subTest(extra=extra):
                self.assertIsNotNone(self.verdict(f"{GOOD} {extra}"))
        self.assertIsNotNone(self.verdict("gh pr merge 12 -R SFenton/native-home --squash --match-head-commit " + HEAD))
        self.assertIsNotNone(self.verdict("gh pr merge 12 -R SFenton/native-home --auto --match-head-commit " + HEAD))
        self.assertIsNotNone(self.verdict(f"{GOOD} -R SFenton/Fenton-HASS-Native"))

    def test_shell_tricks_refuse_even_when_the_ruleset_is_live(self):
        for cmd in (f"{GOOD}; gh pr merge 3 --admin",
                    f"{GOOD} && gh pr merge 3 -R SFenton/native-home --auto --squash",
                    f"{GOOD} | cat",
                    f"{GOOD} $(echo --admin)",
                    f"{GOOD} `id`",
                    f"{GOOD} > out",
                    f"FOO=1 {GOOD}",
                    f"env GH_REPO=x {GOOD}",
                    f"command {GOOD}",
                    f"bash -c '{GOOD}; gh pr merge 3'",
                    f"eval \"{GOOD}\"",
                    f"bash -c '{GOOD}'",
                    f"sh -c '{GOOD}'",
                    f"{GOOD}\ngh pr merge 3 --admin",
                    f"echo hi; {GOOD}",
                    "gh -R x pr merge 12 -R SFenton/native-home --auto --squash"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.verdict(cmd))

    def test_glob_and_other_expanding_characters_refuse(self):
        for tail in ("*", "?", "[a-z]", "~", "#x", "!x", "{a,b}", "\t12"):
            with self.subTest(tail=tail):
                self.assertIsNotNone(self.verdict(f"{GOOD} {tail}"))

    def test_the_pr_number_is_ascii_digits(self):
        self.assertIsNotNone(self.verdict(GOOD.replace("12", "١٢")))
        self.assertIsNotNone(self.verdict(GOOD.replace("12", "1_2")))

    def test_disarming_is_allowed_on_native_home_only_and_needs_no_ruleset(self):
        ok = "gh pr merge 12 -R SFenton/native-home --disable-auto"
        self.assertIsNone(self.verdict(ok, rules=MISSING, error=True))
        self.assertIsNone(self.verdict(ok, rules=MISSING, error=True, origin=ORIGIN))
        self.assertIsNotNone(self.verdict("gh pr merge 12 -R SFenton/Fenton-HASS-Native --disable-auto"))
        self.assertIsNotNone(self.verdict("gh pr merge 12 --disable-auto"))
        self.assertIsNotNone(self.verdict(ok + " --admin"))
        self.assertIsNotNone(self.verdict(ok + " --squash"))
        self.assertIsNotNone(self.verdict(ok + "; gh pr merge 3 --admin"))

    def test_the_refusal_message_names_the_allowed_form(self):
        self.assertIn("-R SFenton/native-home --auto --squash --match-head-commit SHA", merge_guard.MESSAGE)
        self.assertIn("tools/pr_land.sh", merge_guard.MESSAGE)
        self.assertNotIn("pass comment", merge_guard.MESSAGE)

    def test_the_comment_parsing_is_gone(self):
        self.assertFalse(hasattr(merge_guard, "verdict_events"))
        self.assertFalse(hasattr(merge_guard, "AUTOMERGE_AUTHOR"))

    def test_the_other_routes_stay_closed(self):
        for cmd in ("gh api repos/SFenton/native-home/pulls/12/merge -X PUT",
                    "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'",
                    "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'",
                    "git push origin main",
                    "gh pr merge 12 --squash --auto", BARE):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.verdict(cmd))

    def test_a_headless_session_never_merges(self):
        self.assertIsNotNone(self.verdict(GOOD, headless="1"))

    def test_gh_json_flattens_pages_and_raises_on_error(self):
        run = mock.Mock(return_value=mock.Mock(stdout='[[{"a": 1}], [{"a": 2}]]'))
        with mock.patch.object(merge_guard.subprocess, "run", run):
            self.assertEqual(merge_guard.gh_json("x"), [{"a": 1}, {"a": 2}])
        run = mock.Mock(return_value=mock.Mock(stdout='[{"user": {}}]'))
        with mock.patch.object(merge_guard.subprocess, "run", run):
            self.assertEqual(merge_guard.gh_json("x"), {"user": {}})
        with mock.patch.object(merge_guard.subprocess, "run", side_effect=OSError):
            with self.assertRaises(OSError):
                merge_guard.gh_json("x")


if __name__ == "__main__":
    unittest.main()
