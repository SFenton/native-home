"""``tools/hooks/merge_guard.py``: the one allowed ``gh pr merge`` (auto-merge on SFenton/native-home), with ``gh`` stubbed."""

import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import merge_guard  # noqa: E402

SHA = "a" * 40
OTHER = "b" * 40
GOOD = f"gh pr merge 12 -R SFenton/native-home --squash --auto --match-head-commit {SHA}"


def pr(author="SFenton", base="main", head=SHA):
    return {"user": {"login": author}, "base": {"ref": base}, "head": {"sha": head}}


def passing(sha=SHA, at="2026-11-08T10:00:00Z"):
    return {"body": f"Reviewed.\nVerdict: pass\nHead: {sha}\n", "created_at": at, "submitted_at": at}


def failing(sha=SHA, at="2026-11-08T11:00:00Z"):
    return {"body": f"Verdict: fail\nHead: {sha}", "created_at": at, "submitted_at": at}


def stub(pull=None, comments=(), reviews=(), error=False):
    def fake(path):
        if error:
            raise RuntimeError("gh failed")
        if path.endswith("/comments"):
            return list(comments)
        if path.endswith("/reviews"):
            return list(reviews)
        return pull if pull is not None else pr()
    return fake


class AutoMergeTests(unittest.TestCase):
    def verdict(self, command, **facts):
        with mock.patch.object(merge_guard, "gh_json", stub(**facts)), mock.patch.dict("os.environ", {"FENTON_HEADLESS": ""}):
            return merge_guard.reason(command)

    def test_the_allowed_form_passes(self):
        self.assertIsNone(self.verdict(GOOD, comments=[passing()]))

    def test_a_review_body_counts_and_the_url_and_long_forms_pass(self):
        self.assertIsNone(self.verdict(GOOD, reviews=[passing()]))
        url = f"gh pr merge 12 --repo=https://github.com/sfenton/Native-Home -s --auto --match-head-commit={SHA} --subject 'T' --body-file msg.txt"
        self.assertIsNone(self.verdict(url, comments=[passing()]))

    def test_case_insensitive_keys_and_a_later_pass_after_a_fail(self):
        text = {"body": f"VERDICT: Pass\nhead: {SHA}", "created_at": "2026-11-08T12:00:00Z"}
        self.assertIsNone(self.verdict(GOOD, comments=[failing(), text]))

    def test_wrong_or_missing_repo_refuses(self):
        for cmd in (f"gh pr merge 12 -R SFenton/Fenton-HASS-Native --squash --auto --match-head-commit {SHA}",
                    f"gh pr merge 12 -R other/native-home --squash --auto --match-head-commit {SHA}",
                    f"gh pr merge 12 --squash --auto --match-head-commit {SHA}"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.verdict(cmd, comments=[passing()]))

    def test_another_author_or_base_refuses(self):
        self.assertIsNotNone(self.verdict(GOOD, pull=pr(author="someone"), comments=[passing()]))
        self.assertIsNotNone(self.verdict(GOOD, pull=pr(author="sfenton"), comments=[passing()]))
        self.assertIsNotNone(self.verdict(GOOD, pull=pr(base="release"), comments=[passing()]))

    def test_a_stale_head_refuses(self):
        self.assertIsNotNone(self.verdict(GOOD, pull=pr(head=OTHER), comments=[passing()]))
        stale = GOOD.replace(SHA, OTHER)
        self.assertIsNotNone(self.verdict(stale, comments=[passing(OTHER)]))
        short = GOOD.replace(SHA, SHA[:12])
        self.assertIsNotNone(self.verdict(short, pull=pr(head=SHA[:12]), comments=[passing(SHA[:12])]))

    def test_no_pass_comment_or_a_pass_for_another_head_refuses(self):
        self.assertIsNotNone(self.verdict(GOOD))
        self.assertIsNotNone(self.verdict(GOOD, comments=[passing(OTHER)]))
        self.assertIsNotNone(self.verdict(GOOD, comments=[{"body": f"Verdict: pass\nHead: {SHA} extra", "created_at": "1"}]))
        self.assertIsNotNone(self.verdict(GOOD, comments=[{"body": f"Head: {SHA}", "created_at": "1"}]))

    def test_a_later_fail_refuses_and_a_fail_for_another_head_does_not(self):
        self.assertIsNotNone(self.verdict(GOOD, comments=[passing(), failing()]))
        self.assertIsNotNone(self.verdict(GOOD, comments=[passing()], reviews=[failing()]))
        self.assertIsNone(self.verdict(GOOD, comments=[passing(), failing(OTHER)]))

    def test_gh_failure_or_odd_payload_refuses(self):
        self.assertIsNotNone(self.verdict(GOOD, error=True))
        self.assertIsNotNone(self.verdict(GOOD, pull={"user": {}}, comments=[passing()]))
        with mock.patch.object(merge_guard, "gh_json", side_effect=lambda p: "nope"):
            self.assertIsNotNone(merge_guard.reason(GOOD))

    def test_other_flags_refuse(self):
        for extra in ("--admin", "--merge", "--rebase", "--delete-branch", "-d", "--disable-auto", "--body-file m --body x"):
            with self.subTest(extra=extra):
                self.assertIsNotNone(self.verdict(f"{GOOD} {extra}", comments=[passing()]))
        self.assertIsNotNone(self.verdict(f"gh pr merge 12 -R SFenton/native-home --squash --match-head-commit {SHA}", comments=[passing()]))
        self.assertIsNotNone(self.verdict(f"gh pr merge 12 -R SFenton/native-home --auto --match-head-commit {SHA}", comments=[passing()]))
        self.assertIsNotNone(self.verdict("gh pr merge 12 -R SFenton/native-home --squash --auto", comments=[passing()]))
        self.assertIsNotNone(self.verdict(f"{GOOD} -R SFenton/Fenton-HASS-Native", comments=[passing()]))

    def test_shell_tricks_refuse_even_when_the_facts_are_good(self):
        facts = {"comments": [passing()]}
        for cmd in (f"{GOOD}; gh pr merge 3 --admin",
                    f"{GOOD} && gh pr merge 3 -R SFenton/native-home --squash --auto",
                    f"{GOOD} | cat",
                    f"{GOOD} $(echo --admin)",
                    f"{GOOD} --body \"$(cat x)\"",
                    f"{GOOD} --body `id`",
                    f"{GOOD} --body-file <(echo x)",
                    f"{GOOD} > out",
                    f"FOO=1 {GOOD}",
                    f"env GH_REPO=x {GOOD}",
                    f"command {GOOD}",
                    f"bash -c '{GOOD}; gh pr merge 3'",
                    f"eval \"{GOOD}; gh pr merge 3 --admin\"",
                    f"{GOOD}\ngh pr merge 3 --admin",
                    f"{GOOD} --subject x\\\n --admin",
                    f"echo hi; {GOOD}",
                    f"gh -R x pr merge 12 -R SFenton/native-home --squash --auto --match-head-commit {SHA}",
                    f"gh pr merge 12 -R SFenton/native-home --squash --auto --match-head-commit {SHA} --subject 'a; gh pr merge 4 --admin' ; true"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.verdict(cmd, **facts))

    def test_quoted_prose_in_the_subject_is_allowed(self):
        cmd = f"{GOOD} --subject 'Tidy the guard (native-home)' --body 'Tests; docs & more'"
        self.assertIsNone(self.verdict(cmd, comments=[passing()]))

    def test_the_other_routes_stay_closed(self):
        for cmd in ("gh api repos/SFenton/native-home/pulls/12/merge -X PUT",
                    "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'",
                    "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'",
                    "git push origin main",
                    "gh pr merge 12 --squash --auto"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.verdict(cmd, comments=[passing()]))

    def test_a_headless_session_never_merges(self):
        with mock.patch.object(merge_guard, "gh_json", stub(comments=[passing()])), mock.patch.dict("os.environ", {"FENTON_HEADLESS": "1"}):
            self.assertIsNotNone(merge_guard.reason(GOOD))

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
