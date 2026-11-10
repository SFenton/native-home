"""``tools/hooks/merge_guard.py``: no raw auto-merge any more (``tools/pr_land.sh N`` arms); the one allowed ``gh pr merge`` is ``--disable-auto``.

``gh`` is stubbed. Lane A made ``pr_land`` the only thing that arms auto-merge (its gates run what GitHub cannot), so the raw form is closed.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import merge_guard  # noqa: E402

HEAD = "a" * 40
RAW = "gh pr merge 7 -R SFenton/native-home --auto --squash --match-head-commit " + HEAD
BARE = "gh pr merge 12 -R SFenton/native-home --auto --squash"
DISARM = "gh pr merge 12 -R SFenton/native-home --disable-auto"

ORIGIN = {"author": {"login": "SFenton"}, "headRepository": {"name": "native-home"}, "headRepositoryOwner": {"login": "SFenton"}}


class RawAutoMergeClosedTests(unittest.TestCase):
    def verdict(self, command, origin=None, headless=""):
        facts = ORIGIN if origin is None else origin

        def view(number):
            if facts == "error":
                raise RuntimeError("gh failed")
            return facts
        with mock.patch.object(merge_guard, "pr_origin", view), mock.patch.dict("os.environ", {"FENTON_HEADLESS": headless}):
            return merge_guard.reason(command)

    def test_the_raw_form_is_refused_and_names_pr_land(self):
        """Fails if: the pinned raw form is allowed again (it was, with a pass, a live ruleset and a matching head)."""
        why = self.verdict(RAW)
        self.assertIsNotNone(why)
        self.assertIn("tools/pr_land.sh 7", why)

    def test_every_raw_variant_is_refused(self):
        for cmd in (BARE, "gh pr merge 12 --squash --auto", "gh pr merge 12 --auto", "gh pr merge 12 -s --auto --match-head-commit=" + HEAD,
                    "gh pr merge 12 -R SFenton/native-home --squash --match-head-commit " + HEAD, "gh pr merge 12 --squash"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.verdict(cmd))

    def test_admin_has_its_own_reason(self):
        for cmd in ("gh pr merge 12 --admin", "gh pr merge 12 --squash --admin -R SFenton/native-home", RAW + " --admin"):
            with self.subTest(cmd=cmd):
                self.assertIn("--admin", self.verdict(cmd))

    def test_the_message_points_at_pr_land_and_names_no_raw_form(self):
        self.assertIn("tools/pr_land.sh", merge_guard.MESSAGE)
        self.assertNotIn("--match-head-commit", merge_guard.MESSAGE)
        self.assertIn("--disable-auto", merge_guard.MESSAGE)

    def test_the_raw_form_machinery_is_gone(self):
        for name in ("automerge_form", "automerge_reason", "AUTOMERGE_FLAGS", "FULL_SHA", "ruleset_gate", "review_verdict"):
            self.assertFalse(hasattr(merge_guard, name), name)

    def test_the_other_routes_stay_closed(self):
        for cmd in ("gh api repos/SFenton/native-home/pulls/12/merge -X PUT",
                    "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'",
                    "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'",
                    "git push origin main"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.verdict(cmd))

    def test_a_headless_session_never_merges(self):
        self.assertIsNotNone(self.verdict(RAW, headless="1"))
        self.assertIsNotNone(self.verdict(DISARM, headless="1"))


class DisarmTests(unittest.TestCase):
    def verdict(self, command, origin=None):
        facts = ORIGIN if origin is None else origin

        def view(number):
            if facts == "error":
                raise RuntimeError("gh failed")
            return facts
        with mock.patch.object(merge_guard, "pr_origin", view), mock.patch.dict("os.environ", {"FENTON_HEADLESS": ""}):
            return merge_guard.reason(command)

    def test_disarming_the_own_pr_is_allowed_in_any_flag_order(self):
        self.assertIsNone(self.verdict(DISARM))
        self.assertIsNone(self.verdict("gh pr merge --disable-auto 12 --repo=https://github.com/sfenton/Native-Home"))

    def test_other_repos_and_missing_repo_refuse(self):
        self.assertIsNotNone(self.verdict("gh pr merge 12 -R SFenton/Fenton-HASS-Native --disable-auto"))
        self.assertIsNotNone(self.verdict("gh pr merge 12 --disable-auto"))

    def test_a_foreign_author_or_a_fork_refuses(self):
        fork = {**ORIGIN, "headRepositoryOwner": {"login": "mallory"}}
        renamed = {**ORIGIN, "headRepository": {"name": "other"}}
        other = {**ORIGIN, "author": {"login": "sh-reviewer"}}
        for origin in (fork, renamed, other, "error", {}, {"author": None}, {**ORIGIN, "headRepository": None}):
            with self.subTest(origin=origin):
                self.assertIn("not authored by SFenton", self.verdict(DISARM, origin=origin))

    def config_with(self, login, env=None):
        """Point ``merge_guard.AGENT_CONFIG`` at a temp config whose ``agent_login`` is ``login`` (``env`` sets the override that must not exist)."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        config = Path(tmp.name) / "config.json"
        config.write_text(json.dumps({"agent_login": login}))
        patches = [mock.patch.object(merge_guard, "AGENT_CONFIG", config)]
        if env is not None:
            patches.append(mock.patch.dict("os.environ", {"FENTON_AGENT_LOGIN": env}))
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def test_with_no_agent_login_an_agent_authored_pr_still_refuses(self):
        """Fails if: an empty agent_login lets --disable-auto through for a PR by any login but SFenton."""
        self.config_with("")
        self.assertIn("not authored by SFenton", self.verdict(DISARM, origin={**ORIGIN, "author": {"login": "sh-agent"}}))

    def test_a_process_setting_cannot_widen_own_pr(self):
        """Fails if: FENTON_AGENT_LOGIN=<stranger> (a command prefix or shell profile) makes a stranger's PR 'own' while the pinned
        config has no agent_login (or another one)."""
        for configured in ("", "sh-agent"):
            self.config_with(configured, env="mallory")
            self.assertIn("not authored by SFenton", self.verdict(DISARM, origin={**ORIGIN, "author": {"login": "mallory"}}))

    def test_the_agent_login_owns_a_pr_but_a_third_login_and_a_fork_do_not(self):
        """Fails if: own_pr rejects the configured agent login, accepts a third login, or accepts the agent's fork."""
        agent = {**ORIGIN, "author": {"login": "sh-agent"}}
        self.config_with("sh-agent")
        self.assertIsNone(self.verdict(DISARM, origin=agent))
        self.assertIsNone(self.verdict(DISARM, origin=ORIGIN))
        self.assertIn("not authored by SFenton", self.verdict(DISARM, origin={**ORIGIN, "author": {"login": "mallory"}}))
        self.assertIn("not authored by SFenton", self.verdict(DISARM, origin={**agent, "headRepositoryOwner": {"login": "sh-agent"}}))
        self.assertIn("not authored by SFenton", self.verdict(DISARM, origin={"author": None}))

    def test_extra_flags_and_shell_tricks_refuse(self):
        for cmd in (DISARM + " --admin", DISARM + " --squash", DISARM + " --auto", DISARM + "; gh pr merge 3 --admin",
                    DISARM + " && gh pr merge 3 -R SFenton/native-home --auto --squash", DISARM + " | cat", DISARM + " $(echo --admin)",
                    DISARM + " `id`", DISARM + " > out", "FOO=1 " + DISARM, "env GH_REPO=x " + DISARM, "command " + DISARM,
                    "bash -c '%s'" % DISARM, "eval \"%s\"" % DISARM, DISARM + "\ngh pr merge 3 --admin", "echo hi; " + DISARM + " --admin",
                    "gh -R x pr merge 12 -R SFenton/native-home --disable-auto " + "--disable-auto",
                    DISARM + " *", DISARM + " ~", DISARM + " #x", DISARM.replace("12", "١٢"), DISARM.replace("12", "1_2")):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.verdict(cmd))

    def test_pr_origin_asks_gh_pr_view_for_the_author_and_head(self):
        run = mock.Mock(return_value=mock.Mock(stdout='{"author": {}}'))
        with mock.patch.object(merge_guard.subprocess, "run", run):
            self.assertEqual(merge_guard.pr_origin("12"), {"author": {}})
        self.assertEqual(run.call_args[0][0], ["gh", "pr", "view", "12", "-R", "SFenton/native-home", "--json",
                                               "author,headRepository,headRepositoryOwner"])

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
