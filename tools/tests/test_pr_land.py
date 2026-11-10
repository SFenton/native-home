"""``tools/pr_land.py`` gating, ``tools/review/record.py``, the ``merge_guard`` hook and ship.sh's review rule."""

import io
import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import time
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
sys.path.insert(0, str(TOOLS / "review"))
import merge_guard  # noqa: E402
import pr_land  # noqa: E402
import record  # noqa: E402
import agent_model  # noqa: E402

ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
       "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}


class KillSwitchTests(unittest.TestCase):
    def test_kill_switch_files(self):
        with TemporaryDirectory() as tmp:
            paused = Path(tmp) / "PAUSED"
            self.assertIsNone(pr_land.kill_switch({"HASS_TRIAGE_PAUSED_FILE": str(paused), "HOME": tmp}))
            paused.write_text("x")
            self.assertEqual(pr_land.kill_switch({"HASS_TRIAGE_PAUSED_FILE": str(paused)}), str(paused))
            with mock.patch.dict(os.environ, {"HOME": tmp}):
                self.assertIsNone(pr_land.kill_switch({}))
                (Path(tmp) / ".config/fenton-hass").mkdir(parents=True)
                (Path(tmp) / ".config/fenton-hass/NO_LAND").write_text("")
                self.assertTrue(pr_land.kill_switch({}).endswith("NO_LAND"))


class ArmTests(unittest.TestCase):
    """``pr_land.land`` against a fake ``gh``, a fake trusted store and a fake ruleset: the gates GitHub cannot run, then the pinned arm."""

    HEAD = "b" * 40

    def info(self, **extra):
        return {"state": "OPEN", "isDraft": False, "headRefName": "agents/x", "headRefOid": self.HEAD, "mergeable": "MERGEABLE",
                "baseRefName": "main", "labels": [], "files": [], "body": "", "title": "t", "author": {"login": "SFenton"},
                "isCrossRepository": False, **extra}

    def land(self, info=None, dry=False, kill=None, passed=True, ruleset=None, gate=None, denylist=None, merges=None, after=None):
        """Run ``land`` and return ``((code, line), gh calls)``. ``merges`` is the list of ``(returncode, text)`` the successive
        ``gh pr merge`` calls answer; ``after`` is the pull request JSON the post-arm ``pr view`` returns."""
        calls = []
        answers = list(merges if merges is not None else [(0, "")])

        def fake_run(args, check=True):
            calls.append(args)
            if args[:3] == ["gh", "pr", "view"]:
                body = after if args[-1] == "state,autoMergeRequest" else (info if info is not None else self.info())
                return mock.Mock(returncode=0, stdout=json.dumps(body), stderr="")
            if args[:3] == ["gh", "pr", "merge"]:
                code, text = answers.pop(0)
                return mock.Mock(returncode=code, stdout="", stderr=text)
            return mock.Mock(returncode=0, stdout="", stderr="")

        def ui(number, info):
            if isinstance(gate, Exception):
                raise gate
            return "app-UI gate passed (0 app-UI file(s))"
        has_pass = passed if callable(passed) else (lambda sha: passed)
        patches = [mock.patch.object(pr_land, "run", fake_run), mock.patch.object(pr_land, "kill_switch", return_value=kill),
                   mock.patch.object(pr_land.review_verdict, "has_pass", side_effect=has_pass),
                   mock.patch.object(pr_land.ruleset_gate, "check", return_value=ruleset or []),
                   mock.patch.object(pr_land, "ui_gate", ui), mock.patch.object(pr_land, "denylist_gate", return_value=denylist)]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        return pr_land.land("7", dry), calls

    @staticmethod
    def merge_calls(calls):
        return [c for c in calls if c[:3] == ["gh", "pr", "merge"]]

    def test_a_pass_in_the_store_arms_with_no_review_file_and_no_check_rollup(self):
        """Fails if: land asks for a build/review file or the statusCheckRollup, so a pass in the trusted store alone no longer arms."""
        (code, line), calls = self.land(after={"state": "OPEN", "autoMergeRequest": {"enabledBy": {"login": "SFenton"}}})
        self.assertEqual((code, line.split(" at ")[0]), (0, "armed #7"), line)
        self.assertEqual(len(self.merge_calls(calls)), 1)
        view = next(c for c in calls if c[:3] == ["gh", "pr", "view"])
        self.assertNotIn("statusCheckRollup", view[-1])

    def with_agent(self, login, env=None):
        """Point ``pr_land.CONFIG`` at a temp config whose ``agent_login`` is ``login``; ``env`` is set as FENTON_AGENT_LOGIN (the override
        that must not exist)."""
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        config = Path(tmp.name) / "config.json"
        config.write_text(json.dumps({"agent_login": login}))
        patches = [mock.patch.object(pr_land, "CONFIG", config)]
        if env is not None:
            patches.append(mock.patch.dict(os.environ, {"FENTON_AGENT_LOGIN": env}))
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def test_a_process_setting_cannot_widen_the_author_gate(self):
        """Fails if: FENTON_AGENT_LOGIN=<stranger> in front of ship.sh or pr_land (or in a shell profile) makes a stranger's PR armable
        while the pinned config has no agent_login (or another one)."""
        for configured in ("", "sh-agent"):
            self.with_agent(configured, env="mallory")
            (code, line), calls = self.land(info=self.info(author={"login": "mallory"}))
            self.assertEqual(code, 1, line)
            self.assertIn("not a pull request by SFenton", line)
            self.assertEqual(self.merge_calls(calls), [])

    def test_with_no_agent_login_only_the_owner_is_armed(self):
        """Fails if: an empty agent_login lets the author gate accept anyone but SFenton (behaviour must equal the pre-agent gate)."""
        self.with_agent("")
        (code, line), calls = self.land(info=self.info(author={"login": "sh-agent"}))
        self.assertEqual(code, 1, line)
        self.assertIn("not a pull request by SFenton", line)
        self.assertEqual(self.merge_calls(calls), [])
        (code, line), _ = self.land(after={"state": "OPEN", "autoMergeRequest": {"x": 1}})
        self.assertEqual(code, 0, line)

    def test_an_agent_login_pull_request_is_armed_and_a_third_login_or_a_fork_is_not(self):
        """Fails if: a PR by the configured agent login is refused, a third login passes, or the agent's fork passes."""
        self.with_agent("sh-agent")
        (code, line), calls = self.land(info=self.info(author={"login": "sh-agent"}), after={"state": "OPEN", "autoMergeRequest": {"x": 1}})
        self.assertEqual(code, 0, line)
        self.assertEqual(len(self.merge_calls(calls)), 1)
        for name, info in (("third login", self.info(author={"login": "mallory"})),
                           ("agent fork", self.info(author={"login": "sh-agent"}, isCrossRepository=True)),
                           ("owner fork", self.info(isCrossRepository=True)), ("no author", self.info(author=None))):
            (code, line), calls = self.land(info=info)
            self.assertEqual(code, 1, name)
            self.assertIn("not a pull request by SFenton", line, name)
            self.assertEqual(self.merge_calls(calls), [], name)

    def test_the_arm_argv_is_exactly_the_pinned_auto_squash(self):
        """Fails if: the arm drops -R, --auto, --squash or --match-head-commit, or pins any commit but the PR head."""
        _, calls = self.land(after={"state": "OPEN", "autoMergeRequest": {"x": 1}})
        self.assertEqual(self.merge_calls(calls),
                         [["gh", "pr", "merge", "7", "-R", "SFenton/native-home", "--auto", "--squash", "--match-head-commit", self.HEAD]])

    def test_a_draft_is_marked_ready_before_the_arm(self):
        """Fails if: a draft PR is armed without gh pr ready first, or ready runs after the merge call."""
        _, calls = self.land(info=self.info(isDraft=True), after={"state": "OPEN", "autoMergeRequest": {"x": 1}})
        names = [" ".join(c[:3]) for c in calls]
        self.assertLess(names.index("gh pr ready"), names.index("gh pr merge"))
        self.assertEqual(next(c for c in calls if c[:3] == ["gh", "pr", "ready"]), ["gh", "pr", "ready", "7", "-R", "SFenton/native-home"])
        _, calls = self.land(after={"state": "OPEN", "autoMergeRequest": {"x": 1}})
        self.assertFalse([c for c in calls if c[:3] == ["gh", "pr", "ready"]])

    def test_no_pass_or_a_pass_for_an_older_head_blocks_with_no_merge_call(self):
        """Fails if: land arms a head the reviewer never passed (no record, or a record for an earlier commit)."""
        for passed in (False, lambda sha: sha == "c" * 40):
            with self.subTest(passed=bool(passed) and "older"):
                (code, line), calls = self.land(passed=passed)
                self.assertEqual(code, 1, line)
                self.assertIn("no independent pass for " + self.HEAD[:12], line)
                self.assertIn("record.py --lane agents/x", line)
                self.assertFalse(self.merge_calls(calls))

    def test_the_pass_is_looked_up_for_the_exact_head(self):
        """Fails if: the store is asked about the branch or a short sha instead of the full headRefOid."""
        self.land(after={"state": "OPEN", "autoMergeRequest": {"x": 1}})
        pr_land.review_verdict.has_pass.assert_called_once_with(self.HEAD)
        pr_land.ruleset_gate.check.assert_called_once_with("SFenton/native-home", "main")

    def test_clean_status_retries_once_without_auto_and_reports_merged(self):
        """Fails if: GitHub's `clean status` refusal (checks already done) is reported as failed, or retried unpinned or with --auto."""
        (code, line), calls = self.land(merges=[(1, "Pull request is in clean status"), (0, "")], after={"state": "MERGED"})
        self.assertEqual((code, line), (0, f"merged #7 at {self.HEAD[:8]}"))
        merges = self.merge_calls(calls)
        self.assertEqual(len(merges), 2)
        self.assertIn("--auto", merges[0])
        self.assertNotIn("--auto", merges[1])
        self.assertEqual(merges[1][-2:], ["--match-head-commit", self.HEAD])

    def test_other_gh_refusals_are_failed_with_the_message_and_no_retry(self):
        """Fails if: any gh refusal other than `clean status` is retried or hidden, or exits 0."""
        (code, line), calls = self.land(merges=[(1, "auto merge is not allowed for this repository")])
        self.assertEqual(code, 2, line)
        self.assertTrue(line.startswith("failed #7: GitHub refused: auto merge is not allowed"), line)
        self.assertEqual(len(self.merge_calls(calls)), 1)

    def test_armed_and_merged_exit_zero_and_a_call_that_did_neither_fails(self):
        """Fails if: armed or merged exit non-zero (ship.sh would print a refusal), or an arm that left nothing is reported as success."""
        for after, word, code in (({"state": "OPEN", "autoMergeRequest": {"x": 1}}, "armed #7", 0), ({"state": "MERGED"}, "merged #7", 0),
                                  ({"state": "OPEN", "autoMergeRequest": None}, "failed #7", 2)):
            with self.subTest(word=word):
                (got, line), _ = self.land(after=after)
                self.assertEqual(got, code, line)
                self.assertTrue(line.startswith(word), line)
        with mock.patch.object(pr_land, "land", return_value=(0, "armed #7")), mock.patch("builtins.print"):
            self.assertEqual(pr_land.main(["7"]), 0)

    def test_every_gate_blocks_and_nothing_is_armed(self):
        """Fails if: any of these (foreign author, fork, ruleset problem, non-main base, Needs Decision, conflicts, kill switch, closed PR,
        denylist hit, refused app-UI gate) reaches gh pr merge or gh pr ready."""
        rows = {
            "foreign author": ({"info": self.info(author={"login": "mallory"})}, "not a pull request by SFenton"),
            "no author": ({"info": self.info(author=None)}, "not a pull request by SFenton"),
            "fork": ({"info": self.info(isCrossRepository=True)}, "not a pull request by SFenton"),
            "fork unknown": ({"info": {k: v for k, v in self.info().items() if k != "isCrossRepository"}}, "not a pull request by SFenton"),
            "ruleset": ({"ruleset": ["the ruleset allows a bypass"]}, "the ruleset allows a bypass"),
            "base": ({"info": self.info(baseRefName="release")}, "the base is release"),
            "needs decision": ({"info": self.info(labels=[{"name": "Needs Decision"}])}, "Needs Decision"),
            "conflicts": ({"info": self.info(mergeable="CONFLICTING")}, "merge conflicts"),
            "kill switch": ({"kill": "/x/NO_LAND"}, "landing paused (/x/NO_LAND)"),
            "closed": ({"info": self.info(state="CLOSED")}, "pull request is closed"),
            "denylist": ({"denylist": "denylist: 1 new hit"}, "denylist: 1 new hit"),
            "ui gate": ({"gate": pr_land.GateRefused("Jev answered design.app_wide=unsure")}, "app-UI gate (gate)"),
            "owner-kept set": ({"gate": pr_land.GateRefused("touches the owner-kept set", "owner-kept")}, "app-UI gate (owner-kept)"),
            "gate crash": ({"gate": OSError("disk")}, "app-UI gate failed closed"),
        }
        for name, (kwargs, text) in rows.items():
            with self.subTest(name):
                (code, line), calls = self.land(**kwargs)
                self.assertEqual(code, 1, line)
                self.assertTrue(line.startswith("blocked #7: "), line)
                self.assertIn(text, line)
                self.assertFalse(self.merge_calls(calls) or [c for c in calls if c[:3] == ["gh", "pr", "ready"]])

    def test_dry_run_says_would_arm_and_touches_nothing(self):
        """Fails if: --dry-run arms, marks ready, or prints anything but `would arm #N`."""
        (code, line), calls = self.land(dry=True, info=self.info(isDraft=True))
        self.assertEqual(code, 0, line)
        self.assertTrue(line.startswith(f"would arm #7 at {self.HEAD[:8]}"), line)
        self.assertEqual([c[:3] for c in calls], [["gh", "pr", "view"]])

    OWNED_FILES = [{"path": "tools/ci_wait.py"}, {"path": ".github/workflows/pr-checks.yml"}]

    def printed(self, **kw):
        """Run ``land`` and return ``(result, text printed, gh calls)``."""
        out = io.StringIO()
        with mock.patch("sys.stdout", out):
            result, calls = self.land(**kw)
        return result, out.getvalue(), calls

    def test_the_owner_recipe_prints_only_for_codeowners_paths(self):
        """Fails if: the three owner commands print for a PR with no CODEOWNERS path, are missing or unpinned for one that has, or an agent run executes them."""
        owned = self.info(files=self.OWNED_FILES, isDraft=True, reviewDecision="REVIEW_REQUIRED")
        recipe = pr_land.owner_recipe("7", owned)
        self.assertEqual(recipe[1:], ["  gh pr ready 7 -R SFenton/native-home", "  gh pr review 7 -R SFenton/native-home --approve",
                                      f"  gh pr merge 7 -R SFenton/native-home --squash --match-head-commit {self.HEAD}"])
        self.assertIn("draft", recipe[0])
        plain = self.info(files=[{"path": "apple/HassCore/EntityStore.swift"}, {"path": "tools/affected_tests.py"}], reviewDecision="REVIEW_REQUIRED")
        self.assertEqual(pr_land.owner_recipe("7", plain), [])
        self.assertEqual(pr_land.owner_recipe("7", self.info()), [])
        _result, text, calls = self.printed(info=owned, dry=True)
        self.assertIn("gh pr review 7", text)
        self.assertEqual(self.merge_calls(calls), [])
        self.assertEqual(self.printed(info=plain, dry=True)[1], "")

    def test_the_recipe_waits_for_our_gates_and_prints_only_for_an_owner_only_block(self):
        """Fails if: the recipe prints before a refusal of another kind (no pass, ruleset, conflict, denylist, a non-owner app-UI refusal), or is
        missing when the block is the owner's alone (code-owner review, draft, the owner-kept set)."""
        owned = self.info(files=self.OWNED_FILES, reviewDecision="REVIEW_REQUIRED")
        for name, kw in (("no pass", {"passed": False}), ("ruleset", {"ruleset": ["no ruleset"]}), ("denylist", {"denylist": "hit"}),
                         ("app-UI", {"gate": pr_land.GateRefused("no design record")})):
            with self.subTest(name):
                result, text, _calls = self.printed(info=owned, **kw)
                self.assertEqual(result[0], 1)
                self.assertEqual(text, "")
        conflicting = self.info(files=self.OWNED_FILES, mergeable="CONFLICTING", reviewDecision="REVIEW_REQUIRED")
        self.assertEqual(self.printed(info=conflicting)[1], "")
        kept = pr_land.GateRefused("the pull request changes the owner-only set: tools/ci_wait.py (protected)")
        result, text, _calls = self.printed(info=owned, gate=kept)
        self.assertEqual(result[0], 1)
        self.assertIn("gh pr review 7", text)
        self.assertIn("gh pr review 7", self.printed(info=owned, dry=True)[1])  # gates passed, code-owner review is what is left
        approved = self.info(files=self.OWNED_FILES, reviewDecision="APPROVED")
        self.assertEqual(self.printed(info=approved, dry=True)[1], "")

    def test_pr_land_loads_only_modules_that_merge_guard_pins(self):
        """Fails if: pr_land.py (or a repo module it imports, transitively, including imports inside functions) loads a tools/ module that
        merge_guard.PINNED_WITH does not hash against the base copy, so an unreviewed edit could change what the landing process runs."""
        import ast
        pinned = {Path(n).stem for n in merge_guard.PINNED_WITH["pr_land.sh"]}
        seen, todo = set(), ["pr_land"]
        while todo:
            name = todo.pop()
            if name in seen:
                continue
            seen.add(name)
            tree = ast.parse((TOOLS / f"{name}.py").read_text())
            for node in ast.walk(tree):
                mods = [a.name for a in node.names] if isinstance(node, ast.Import) else (
                    [node.module] if isinstance(node, ast.ImportFrom) and node.module and not node.level else [])
                todo += [m.split(".")[0] for m in mods if (TOOLS / f"{m.split('.')[0]}.py").is_file()]
        self.assertEqual(sorted(seen - pinned), [], "repo modules pr_land loads that are not pinned")
        self.assertIn("pr_blockers", seen)

    def test_the_shipped_config_no_longer_has_require_checks(self):
        """Fails if: tools/triage/config.json carries `require_checks` again (GitHub is the only judge of checks)."""
        self.assertNotIn("require_checks", json.loads((TOOLS / "triage" / "config.json").read_text()))
        self.assertNotIn("require_checks", (TOOLS / "pr_land.py").read_text())

    def test_the_dead_gate_pieces_are_gone(self):
        """Fails if: the deleted local checks, review file lookup or direct merge and cleanup come back in pr_land."""
        for name in ("checks_state", "latest_runs", "required_checks", "REQUIRED_CHECKS", "review_state", "find_review", "local_gates",
                     "cleanup", "safe_cleanup", "MAX_ROUNDS", "reviewer_identity_problem"):
            self.assertFalse(hasattr(pr_land, name), name)
        self.assertTrue(callable(pr_land.review_file_name))  # jev_miss still imports it


class LaneWorktreeReapTests(unittest.TestCase):
    """The arm no longer cleans up; ``ci_hygiene.py prune-worktrees`` reaps the lane worktree once GitHub squash-merged its branch."""

    def test_a_squash_merged_lane_worktree_is_reaped_by_prune_worktrees(self):
        """Fails if: prune-worktrees leaves a lane worktree whose multi-commit branch was squash-merged into main, so nothing reaps it now that pr_land does not."""
        import ci_hygiene
        env = {k: v for k, v in ENV.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")}

        def git(cwd, *args):
            subprocess.run(["git", *args], cwd=cwd, env=env, check=True, capture_output=True)
        with TemporaryDirectory() as tmp:
            base = Path(os.path.realpath(tmp))
            origin, repo, lane, far = base / "origin.git", base / "primary", base / "lane", base / "far"
            far.mkdir()
            git(base, "init", "-q", "--bare", "-b", "main", str(origin))
            git(base, "clone", "-q", str(origin), str(repo))
            (repo / "f.txt").write_text("1")
            git(repo, "add", ".")
            git(repo, "commit", "-qm", "init")
            git(repo, "push", "-q", "origin", "HEAD:main")
            git(repo, "fetch", "-q", "origin")
            git(repo, "worktree", "add", "-q", "-b", "agents/x", str(lane), "origin/main")
            for n in (1, 2):
                (lane / f"s{n}.txt").write_text(str(n))
                git(lane, "add", ".")
                git(lane, "commit", "-qm", f"c{n}")
            git(repo, "checkout", "-q", "-b", "squasher", "origin/main")
            git(repo, "merge", "-q", "--squash", "agents/x")
            git(repo, "commit", "-qm", "squash")
            git(repo, "push", "-q", "origin", "squasher:refs/heads/main")
            git(repo, "fetch", "-q", "origin")
            with mock.patch.object(ci_hygiene, "devcap_cwds", return_value=[]), mock.patch("builtins.print"):
                self.assertEqual(ci_hygiene.prune_worktrees(0.0, False, repo=repo, current=far), 0)
            self.assertFalse(lane.exists())


open_real = open


class UiGateInLandTests(unittest.TestCase):
    """``pr_land.land`` runs the lander's app-UI gate (``lane_land.pr_gate``) before it merges; ``--owner-ack`` is owner-only."""

    HEAD = "a" * 40

    def info(self, **extra):
        return {"state": "OPEN", "isDraft": False, "headRefName": "feat/ui", "headRefOid": self.HEAD, "mergeable": "MERGEABLE",
                "baseRefName": "main", "isCrossRepository": False, "labels": [],
                "files": [{"path": "apple/Sources/HassUI/Chip.swift"}], "body": "", "title": "t", "author": {"login": "SFenton"}, **extra}

    def land(self, gate=None, ack=False, dry=True, env=None, tty=True, info=None):
        calls = []

        def fake_run(args, check=True):
            calls.append(args)
            return mock.Mock(returncode=0, stdout=json.dumps(info or self.info()), stderr="")
        patches = [mock.patch.object(pr_land, "run", fake_run),
                   mock.patch.object(pr_land, "kill_switch", return_value=None),
                   mock.patch.object(pr_land.review_verdict, "has_pass", return_value=True),
                   mock.patch.object(pr_land.ruleset_gate, "check", return_value=[]),
                   # These tests are about the app-UI gate; the shipped config requires the denylist, which a test host has not loaded.
                   mock.patch.object(pr_land, "denylist_gate", return_value=None),
                   mock.patch.dict(os.environ, {"HOUSE_SCAN_DENYLIST": "/nonexistent/denylist", **(env or {})}),
                   mock.patch.object(sys.stdin, "isatty", return_value=tty)]
        if gate is not None:
            patches.append(mock.patch.object(pr_land, "ui_gate", gate))
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        for key in ("FENTON_HEADLESS", "HASS_TRIAGE_ISSUE"):
            if key not in (env or {}):
                os.environ.pop(key, None)
        return pr_land.land("9", dry, owner_ack=ack), calls

    def test_the_gate_runs_with_the_pr_info_and_a_pass_lets_it_land(self):
        seen = []
        (code, line), calls = self.land(gate=lambda n, info: seen.append((n, info["files"])) or "app-UI gate passed (1 app-UI file(s))")
        self.assertEqual(code, 0, line)
        self.assertIn("app-UI gate passed", line)
        self.assertEqual(seen[0][0], "9")
        view = next(c for c in calls if c[:3] == ["gh", "pr", "view"])
        for field in ("files", "body", "title", "author", "headRefOid", "baseRefName"):
            self.assertIn(field, view[-1])

    def test_a_refusal_an_error_or_a_missing_gate_blocks_and_nothing_merges(self):
        for raised in (pr_land.GateRefused("Jev answered design.app_wide=unsure"), pr_land.GateRefused("no record", "design"),
                       RuntimeError("git fetch failed"), OSError("disk"), KeyError("files")):
            with self.subTest(raised=repr(raised)):
                def boom(n, info, raised=raised):
                    raise raised
                (code, line), calls = self.land(gate=boom, dry=False)
                self.assertEqual(code, 1, line)
                self.assertTrue(line.startswith("blocked #9: app-UI gate"), line)
                self.assertFalse([c for c in calls if c[:3] == ["gh", "pr", "merge"]])

    def test_owner_ack_skips_the_gate_only_with_the_head_sha_typed_at_the_terminal(self):
        def never(n, info):
            raise AssertionError("gate ran")
        with mock.patch.object(pr_land, "confirm_head_on_tty", return_value=True) as confirm:
            (code, line), _ = self.land(gate=never, ack=True, tty=True)
        self.assertEqual(code, 0, line)
        self.assertIn("skipped by --owner-ack", line)
        confirm.assert_called_once_with("9", self.HEAD)
        with mock.patch.object(pr_land, "confirm_head_on_tty", return_value=False):
            (code, line), calls = self.land(gate=never, ack=True, tty=True, dry=False)
        self.assertEqual(code, 1, line)
        self.assertIn("typed at the terminal", line)
        self.assertFalse([c for c in calls if c[:3] == ["gh", "pr", "merge"]])

    def test_confirm_head_on_tty_reads_the_terminal_and_wants_the_full_sha(self):
        with TemporaryDirectory() as tmp:
            tty = Path(tmp) / "tty"
            for typed, ok in ((self.HEAD + "\n", True), (self.HEAD.upper() + "\n", True), (self.HEAD[:12] + "\n", False),
                              ("\n", False), ("yes\n", False), ("", False)):
                tty.write_text(typed)  # a real /dev/tty shows the prompt and returns only what is typed
                with mock.patch.object(pr_land, "open", create=True, side_effect=lambda path, mode="r": (io.StringIO() if mode == "a" else open_real(path))):
                    self.assertEqual(pr_land.confirm_head_on_tty("9", self.HEAD, str(tty)), ok, typed)
            self.assertFalse(pr_land.confirm_head_on_tty("9", self.HEAD, str(Path(tmp) / "missing")))
            self.assertFalse(pr_land.confirm_head_on_tty("9", "", str(tty)))

    def test_an_abbreviated_flag_is_not_owner_ack(self):
        import lane_land
        for abbreviation in ("--owner", "--owner-a", "--ow", "--own"):
            with self.subTest(flag=abbreviation), mock.patch.object(pr_land, "land", return_value=(0, "ok")) as fake, \
                    mock.patch("sys.stderr", io.StringIO()), self.assertRaises(SystemExit) as cm:
                pr_land.main(["9", abbreviation])
            self.assertEqual(cm.exception.code, 2)
            fake.assert_not_called()
        for argv in (["agents/x", "--into", "b", "--dry"], ["gate", "--p", "7"], ["gate", "--pr", "7", "--ro", "/x"]):
            with self.subTest(argv=argv), mock.patch("sys.stderr", io.StringIO()), self.assertRaises(SystemExit):
                lane_land.main(argv)

    PRODUCT = "https://github.com/" + json.loads((TOOLS / "triage" / "config.json").read_text())["product_repo"] + ".git"

    def test_ui_gate_runs_the_trusted_base_copy_in_isolated_mode_from_the_configured_origin(self):
        trusted = Path("/trusted/repo")
        calls = []

        def fake_sub(argv, **kw):
            calls.append((argv, kw))
            return mock.Mock(returncode=0, stdout="app-UI gate passed (1 app-UI file(s))\n", stderr="")
        with TemporaryDirectory() as home, mock.patch.dict(os.environ, {"HOME": home}), \
                mock.patch.object(pr_land, "run", side_effect=AssertionError("the checkout's remote was read")), \
                mock.patch.object(pr_land, "trusted_gate_clone", return_value=trusted) as tg, \
                mock.patch.object(pr_land.subprocess, "run", fake_sub), mock.patch.object(Path, "is_file", return_value=True):
            note = pr_land.ui_gate("9", self.info())
        self.assertIn("passed", note)
        argv = calls[0][0]
        self.assertEqual(argv[1:3], ["-I", str(trusted / "tools" / "lane_land.py")])
        self.assertEqual(argv[3:8], ["gate", "--pr", "9", "--head", self.HEAD])
        self.assertIn("--lock-held", argv)
        self.assertEqual(tg.call_args.args[1:], (self.PRODUCT, "main"))  # product_repo from the config, and the PR's base branch
        self.assertFalse(any(k.startswith("PYTHON") for k in calls[0][1]["env"]))

    def test_pr_land_holds_the_gate_lock_until_the_gate_process_exits(self):
        import fcntl
        seen = []

        def fake_sub(argv, **kw):
            with open(Path(os.path.expanduser("~/hass-agents")) / "gate.lock", "w") as other:
                try:
                    fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    seen.append("free")
                except BlockingIOError:
                    seen.append("held")
            return mock.Mock(returncode=0, stdout="passed\n", stderr="")
        with TemporaryDirectory() as home, mock.patch.dict(os.environ, {"HOME": home}), \
                mock.patch.object(pr_land, "trusted_gate_clone", return_value=Path("/trusted/repo")), \
                mock.patch.object(pr_land.subprocess, "run", fake_sub), mock.patch.object(Path, "is_file", return_value=True):
            pr_land.ui_gate("9", self.info())
            self.assertEqual(seen, ["held"])
            with open(Path(home) / "hass-agents" / "gate.lock", "w") as after:
                fcntl.flock(after, fcntl.LOCK_EX | fcntl.LOCK_NB)  # released afterwards

    def test_expected_origin_is_the_hard_coded_product_repo(self):
        self.assertEqual(pr_land.PRODUCT_REPO, "SFenton/native-home")
        self.assertEqual(pr_land.expected_origin({"product_repo": pr_land.PRODUCT_REPO}), "https://github.com/SFenton/native-home.git")
        # the checked-in config agrees, so a config edit that disagrees is the thing that gets refused
        self.assertEqual(json.loads((TOOLS / "triage" / "config.json").read_text())["product_repo"], pr_land.PRODUCT_REPO)
        for cfg in ({}, {"product_repo": ""}, {"product_repo": "evil/private-app"}, {"product_repo": "o/r.x-y"},
                    {"product_repo": "https://evil.example/x"}):
            with self.subTest(cfg=cfg), self.assertRaises(pr_land.GateRefused):
                pr_land.expected_origin(cfg)

    def test_ui_gate_refuses_a_base_that_is_not_allowed(self):
        self.assertEqual(pr_land.ALLOWED_BASES, ("main",))
        with mock.patch.object(pr_land, "trusted_gate_clone", side_effect=AssertionError("cloned")), self.assertRaises(pr_land.GateRefused):
            pr_land.ui_gate("9", self.info(baseRefName="evil/base"))

    def test_ui_gate_refusal_text_and_a_base_without_the_gate_fail_closed(self):
        trusted = Path("/trusted/repo")
        common = [mock.patch.object(pr_land, "trusted_gate_clone", return_value=trusted),
                  mock.patch.object(pr_land, "gate_lock", mock.MagicMock())]
        for p in common:
            p.start()
            self.addCleanup(p.stop)
        with mock.patch.object(Path, "is_file", return_value=True), mock.patch.object(
                pr_land.subprocess, "run", return_value=mock.Mock(returncode=2, stdout="", stderr="lane_land gate: refused (gate): Jev answered no")):
            with self.assertRaises(pr_land.GateRefused) as cm:
                pr_land.ui_gate("9", self.info())
        self.assertIn("Jev answered no", str(cm.exception))
        with mock.patch.object(Path, "is_file", return_value=False), self.assertRaises(pr_land.GateRefused):
            pr_land.ui_gate("9", self.info())
        with self.assertRaises(pr_land.GateRefused):
            pr_land.ui_gate("9", self.info(baseRefName="../x"))

    def test_the_trusted_clone_is_the_base_branch_and_survives_a_changed_remote_and_a_corrupt_clone(self):
        with TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            bare, other = tmp / "o.git", tmp / "other.git"
            for repo, text in ((bare, "base copy\n"), (other, "other repo\n")):
                seed = tmp / ("seed-" + repo.name)
                subprocess.run(["git", "init", "-q", "--bare", str(repo)], check=True)
                subprocess.run(["git", "init", "-q", "-b", "main", str(seed)], check=True)
                (seed / "f.txt").write_text(text)
                subprocess.run(["git", "add", "-A"], cwd=seed, env=ENV, check=True)
                subprocess.run(["git", "commit", "-qm", "x"], cwd=seed, env=ENV, check=True)
                subprocess.run(["git", "push", "-q", str(repo), "main"], cwd=seed, env=ENV, check=True)
            root = tmp / "root"
            clone = pr_land.trusted_gate_clone(root, str(bare), "main")
            self.assertEqual((clone / "f.txt").read_text(), "base copy\n")
            subprocess.run(["git", "-C", str(clone), "remote", "set-url", "origin", str(other)], check=True)
            (clone / "f.txt").write_text("tampered\n")
            (clone / "extra.py").write_text("x\n")
            clone = pr_land.trusted_gate_clone(root, str(bare), "main")  # origin forced back, tampering cleaned
            self.assertEqual((clone / "f.txt").read_text(), "base copy\n")
            self.assertFalse((clone / "extra.py").exists())
            shutil.rmtree(clone / ".git" / "objects")  # a corrupt clone: one re-clone, then it works
            clone = pr_land.trusted_gate_clone(root, str(bare), "main")
            self.assertEqual((clone / "f.txt").read_text(), "base copy\n")
            with self.assertRaises(pr_land.GateRefused):
                pr_land.trusted_gate_clone(root, str(bare), "no-such-branch")

    def test_owner_ack_is_refused_for_headless_runner_and_non_terminal_sessions(self):
        def never(n, info):
            raise AssertionError("gate ran")
        for env, tty in (({"FENTON_HEADLESS": "1"}, True), ({"HASS_TRIAGE_ISSUE": "4"}, True), ({}, False)):
            with self.subTest(env=env, tty=tty):
                (code, line), calls = self.land(gate=never, ack=True, dry=False, env=env, tty=tty)
                self.assertEqual(code, 2, line)
                self.assertIn("owner-only", line)
                self.assertEqual(calls, [])

    def test_the_cli_flag_reaches_land(self):
        with mock.patch.object(pr_land, "land", return_value=(0, "ok")) as fake, mock.patch("builtins.print"):
            self.assertEqual(pr_land.main(["9", "--owner-ack"]), 0)
        self.assertTrue(fake.call_args.args[4])


class RecordTests(unittest.TestCase):
    def test_validate(self):
        self.assertEqual(record.validate({"verdict": "pass", "findings": []}), [])
        self.assertTrue(record.validate({"verdict": "ok"}))
        self.assertTrue(record.validate({"verdict": "changes", "findings": [{"severity": "huge", "rule": "r", "detail": "d"}]}))
        self.assertTrue(record.validate({"verdict": "pass", "findings": [{"severity": "blocker", "rule": "r", "detail": "d"}]}))

    def test_verdict_must_follow_the_severities(self):
        def f(sev):
            return {"severity": sev, "rule": "r", "detail": "d"}
        self.assertEqual(record.validate({"verdict": "pass", "findings": [f("minor")]}), [])
        self.assertEqual(record.validate({"verdict": "changes", "findings": [f("major"), f("minor")]}), [])
        self.assertEqual(record.validate({"verdict": "blocker", "findings": [f("blocker"), f("major")]}), [])
        self.assertTrue(record.validate({"verdict": "pass", "findings": [f("major")]}))
        self.assertTrue(record.validate({"verdict": "changes", "findings": [f("blocker")]}))
        self.assertTrue(record.validate({"verdict": "blocker", "findings": []}))
        self.assertTrue(record.validate({"verdict": "changes", "findings": []}))

    def test_round_bumps_only_when_head_moved_after_changes(self):
        self.assertEqual(record.next_round({}, "a"), 1)
        self.assertEqual(record.next_round({"round": 1, "head": "a", "verdict": "changes"}, "a"), 1)
        self.assertEqual(record.next_round({"round": 1, "head": "a", "verdict": "changes"}, "b"), 2)
        self.assertEqual(record.next_round({"round": 1, "head": "a", "verdict": "pass"}, "b"), 1)
        self.assertEqual(record.next_round({"round": 2, "head": "a", "verdict": "blocker"}, "b"), 2)

    def test_summary_and_body_merge_replace_section(self):
        data = {"verdict": "changes", "round": 1, "findings": [
            {"severity": "major", "rule": "pattern-reuse", "file": "A.swift", "detail": "dup", "fix": "use Tile"}]}
        section = record.summary(data)
        self.assertIn("**major** [pattern-reuse] `A.swift`: dup Fix: use Tile", section)
        body = record.merge_body("Body", section)
        again = record.merge_body(body, record.summary({"verdict": "pass", "round": 2, "findings": []}))
        self.assertEqual(again.count(record.START), 1)
        self.assertIn("Review: pass (round 2)", again)
        self.assertNotIn("dup", again)

    def test_writes_file_with_head_and_round(self):
        with TemporaryDirectory() as tmp:
            subprocess.run(["git", "init", "-q", "-b", "claude/t"], cwd=tmp, env=ENV, check=True)
            subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "i"], cwd=tmp, env=ENV, check=True)
            verdict = Path(tmp) / "v.json"
            verdict.write_text(json.dumps({"verdict": "changes", "round": 9, "findings": [
                {"severity": "major", "rule": "r", "detail": "d"}]}))
            home = Path(tmp) / "home"
            ident = home / ".cache" / "fenton-hass" / "reviewer-ident.json"
            ident.parent.mkdir(parents=True)
            ident.write_text(json.dumps({"agent_type": "reviewer", "session_id": "s-9", "cwd": os.path.realpath(tmp), "at": time.time()}))
            env = {**ENV, "HOME": str(home)}
            for expected in (1, 1, 2):
                if expected == 2:  # a fix lands, the head moves
                    subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "fix"], cwd=tmp, env=env, check=True)
                proc = subprocess.run(["python3", str(TOOLS / "review/record.py"), str(verdict)], cwd=tmp, env=env,
                                      capture_output=True, text=True)
                self.assertEqual(proc.returncode, 0, proc.stderr)
                saved = json.loads((Path(tmp) / "build/review/claude__t.json").read_text())
                self.assertEqual(saved["round"], expected)
                self.assertEqual(len(saved["head"]), 40)
                self.assertEqual(saved["reviewer"], {"agent_type": "reviewer", "session_id": "s-9", "agent_id": ""})
            subprocess.run(["git", "checkout", "-q", "--detach"], cwd=tmp, env=env, check=True)
            proc = subprocess.run(["python3", str(TOOLS / "review/record.py"), str(verdict)], cwd=tmp, env=env,
                                  capture_output=True, text=True)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("detached", proc.stderr)
            verdict.write_text("{bad")
            proc = subprocess.run(["python3", str(TOOLS / "review/record.py"), str(verdict)], cwd=tmp, env=env,
                                  capture_output=True, text=True)
            self.assertEqual(proc.returncode, 2)


class BaseMatchHashTests(unittest.TestCase):
    """``merge_guard.pr_land_matches_base`` also hashes ``tools/triage/config.json`` (real git, a throwaway repo)."""

    def git(self, *a):
        subprocess.run(["git", "-C", str(self.top), *a], check=True, capture_output=True)

    def setUp(self):
        self._tmp = TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.top = Path(self._tmp.name)
        (self.top / "tools" / "triage").mkdir(parents=True)
        for name, text in (("tools/pr_land.sh", "sh\n"), ("tools/pr_land.py", "py\n"), ("tools/house_scan.py", "hs\n"), ("tools/agent_login.py", "al\n"), ("tools/pr_blockers.py", "pb\n"), ("tools/review_verdict.py", "rv\n"), ("tools/ruleset_gate.py", "rg\n"), ("tools/request_repo.py", "rr\n"), ("tools/triage/config.json", "{}\n")):
            (self.top / name).write_text(text)
        self.git("init", "-q")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "x")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.cmd = f"{self.top}/tools/pr_land.sh 3"

    def test_identical_copies_match(self):
        self.assertTrue(merge_guard.pr_land_matches_base(self.cmd))

    def test_an_edited_config_no_longer_matches(self):
        (self.top / "tools" / "triage" / "config.json").write_text('{"product_repo": "evil/fork"}\n')
        self.assertFalse(merge_guard.pr_land_matches_base(self.cmd))

    def test_an_edited_pr_land_no_longer_matches(self):
        (self.top / "tools" / "pr_land.py").write_text("edited\n")
        self.assertFalse(merge_guard.pr_land_matches_base(self.cmd))


class AckVerifiedPinTests(unittest.TestCase):
    """``merge_guard.pr_land_matches_base`` pins ``hass_triage.py`` and the modules the verifier imports (real git, a throwaway repo)."""

    def git(self, *a):
        subprocess.run(["git", "-C", str(self.top), *a], check=True, capture_output=True)

    def setUp(self):
        self._tmp = TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.top = Path(self._tmp.name)
        (self.top / "tools" / "triage").mkdir(parents=True)
        for name in (*merge_guard.ACK_VERIFIED_PINNED, "tools/triage/config.json"):
            (self.top / name).write_text(name + "\n")
        self.git("init", "-q")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "x")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.script = f"{self.top}/tools/triage/hass_triage.py"
        self.cmd = f"python3 {self.script} ack-verified"

    def test_a_matching_copy_is_allowed(self):
        """Fails if: an identical checkout is refused, so the verb could never run."""
        self.assertTrue(merge_guard.pr_land_matches_base(self.cmd, self.script))

    def test_an_edited_verifier_or_import_no_longer_matches(self):
        """Fails if: editing hass_triage.py, ruleset_gate.py or any other pinned import still passes the pin."""
        for name in (*merge_guard.ACK_VERIFIED_PINNED, "tools/triage/config.json"):
            with self.subTest(name=name):
                path = self.top / name
                original = path.read_text()
                path.write_text("edited\n")
                self.assertFalse(merge_guard.pr_land_matches_base(self.cmd, self.script))
                path.write_text(original)
        self.assertTrue(merge_guard.pr_land_matches_base(self.cmd, self.script))


class MergeGuardTests(unittest.TestCase):
    BLOCKED = [
        "gh pr merge 12 --squash",
        "gh pr merge",
        "git status && gh pr merge 5 --auto",
        "gh api repos/SFenton/x/pulls/5/merge -X PUT",
        "gh api -X PUT repos/o/r/merges",
        "git push origin main",
        "git push origin HEAD:main",
        "git push origin +claude/x:refs/heads/main",
        "git push -u origin master",
        "FOO=1 gh pr merge 3",
        "bash -c 'gh pr merge 3'",
        "tools/pr_land.sh 3; gh pr merge 3",
        "echo hi | gh pr merge 3",
        "git -C /p push origin main",
        "git -c user.name=x push origin HEAD:main",
        "git --git-dir=/p/.git push origin master",
        "env FOO=1 gh pr merge 3",
        "command gh pr merge 3",
        "/usr/bin/env gh pr merge 3",
        "/opt/homebrew/bin/gh pr merge 3",
        "nohup gh pr merge 3",
        "time gh pr merge 3",
        "echo 3 | xargs gh pr merge",
        "(gh pr merge 3)",
        "{ gh pr merge 3; }",
        "if true; then gh pr merge 3; fi",
        "for n in 1 2; do gh pr merge $n; done",
        "gh -R o/r pr merge 3",
        "gh api -X PUT repos/o/r/pulls/$PR/merge",
        "gh api repos/o/r/pulls/5/merge --method PUT",
        "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }'",
        "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'",
        "gh api -X PUT repos/o/r/contents/README.md -f message=x",
        "gh api --method DELETE repos/o/r/contents/x",
        "tools/pr_land.sh 5 & gh pr merge 6",
        "tools/pr_land.sh $(gh pr merge 6)",
        "tools/pr_land.sh 5 `gh pr merge 6`",
        "/tmp/evil/tools/pr_land.sh 5; gh pr merge 5",
        "gh api -X PUT repos/{owner}/{repo}/pulls/5/merge",
        "gh api -X POST repos/{owner}/{repo}/merges -f base=main -f head=x",
        "gh api -X PATCH repos/{owner}/{repo}/git/refs/heads/main -f sha=abc",
        'gh api -X PUT "repos/o/r/pulls/${N}/merge"',
        "env -u X gh pr merge 3",
        "sudo -u bob gh pr merge 3",
        "bash -lc 'gh pr merge 3'",
        "bash -ec 'gh pr merge 3'",
        "printf 'gh pr merge 3' | sh",
        "echo 'gh pr merge 3' | /bin/bash",
        "sh <<<'gh pr merge 3'",
        "bash <<'EOF'\ngh pr merge 3\nEOF",
        "sh -c 'gh pr merge 3'",
        "eval 'gh pr merge 3'",
    ]
    FINE = [
        "tools/pr_land.sh 12",
        "./tools/pr_land.sh 12 --dry-run",
        "bash tools/pr_land.sh 12",
        "git push -u origin claude/pr-lifecycle",
        "git push origin claude/main-menu",
        "git push",
        "gh pr create --draft",
        "gh pr view 3 --json state",
        "gh api repos/o/r/pulls/5/comments",
        "git log main..HEAD",
        "git merge origin/main",
        "echo 'gh pr merge is blocked'",
        "git -C /p status",
        "gh api repos/{owner}/{repo}/pulls/5/comments",
        "gh api repos/{owner}/{repo}/contents/README.md",
        "env -u X git status",
        "bash -lc 'git status'",
        "cat file | grep sh",
        "gh api repos/o/r/contents/README.md",
        "gh api graphql -f query='query { viewer { login } }'",
        "tools/pr_land.sh 5 --keep-worktree",
        "tools/pr_land.sh 5 --dry-run --review /tmp/r.json",
        "tools/pr_land.sh 5",
    ]

    def run_hook(self, payload):
        err = io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), redirect_stderr(err):
            return merge_guard.main(), err.getvalue()

    def test_blocks_bypasses(self):
        for command in self.BLOCKED:
            with self.subTest(command=command):
                status, message = self.run_hook({"tool_name": "Bash", "tool_input": {"command": command}})
                self.assertEqual(status, 2)
                self.assertIn("pr_land.sh", message)

    def test_allows_sanctioned_and_ordinary_commands(self):
        for command in self.FINE:
            with self.subTest(command=command):
                self.assertEqual(self.run_hook({"tool_name": "Bash", "tool_input": {"command": command}})[0], 0)

    def test_only_the_exact_script_is_sanctioned(self):
        self.assertTrue(merge_guard.is_sanctioned("tools/pr_land.sh 5 --keep-worktree"))
        self.assertTrue(merge_guard.is_sanctioned("./tools/pr_land.sh 5"))
        self.assertTrue(merge_guard.is_sanctioned(f"{merge_guard.REPO}/tools/pr_land.sh 5"))
        for command in ("/tmp/evil/tools/pr_land.sh 5", "tools/pr_land.sh 5; true", "FOO=1 tools/pr_land.sh 5",
                        "tools/pr_land.sh $(id)", "tools/pr_land.sh 5 | cat", ""):
            self.assertFalse(merge_guard.is_sanctioned(command), command)

    def test_ignores_other_tools_and_bad_input(self):
        self.assertEqual(self.run_hook({"tool_name": "Read", "tool_input": {"command": "gh pr merge"}})[0], 0)
        with mock.patch.object(sys, "stdin", io.StringIO("nope")):
            self.assertEqual(merge_guard.main(), 0)

    def test_registered_in_settings(self):
        settings = json.loads((TOOLS.parent / ".claude/settings.json").read_text())
        commands = [h["command"] for m in settings["hooks"]["PreToolUse"] for h in m["hooks"]]
        self.assertTrue(any("merge_guard.py" in c for c in commands))
        self.assertIn("Bash(tools/pr_land.sh:*)", settings["permissions"]["allow"])
        self.assertIn("Bash(tools/ship.sh:*)", settings["permissions"]["allow"])


class MergeGuardExemptionTests(unittest.TestCase):
    """The raw scan decides; a block is dropped only when every simple command is a non-executing one (``merge_guard.exempt``)."""

    def verdict(self, command, agent=True):
        return merge_guard.reason(command, str(TOOLS.parent), agent=agent)

    def test_real_false_positives_pass(self):
        self.assertIsNone(self.verdict('grep -rn "owner-ack" tools/ .agents/'))
        brief = ("cat > build/briefs/X.md <<'EOF'\nlane_land refuses an agent; the owner merges; --owner-ack; "
                 "script/expect/unbuffer around pr_land\nEOF\n"
                 "python3 tools/tasks.py new T-x --check 'w1: lane_land refuses, owner merges'")
        self.assertIsNone(self.verdict(brief))
        self.assertIsNone(self.verdict(brief, agent=False))

    def test_exempt_commands_pass_with_guarded_arguments(self):
        for command in ("rg --owner-ack tools", "cat tools/pr_land.sh | head -5", "head -3 owner-ack.txt", "tail -f lane_land.log",
                        "less pr_land.py", "ls tools/lane_land.py", "git log --grep owner-ack", "git show HEAD:tools/pr_land.sh",
                        "git diff -- lane_land.py", "git status", "gh pr view 5 --json body", "gh pr list --search owner-ack",
                        "wc -l pr_land.py", "echo 'script lane_land' ", "mkdir -p owner-ack",
                        "git commit -m 'document gh pr merge and --owner-ack'", "echo hi # --owner-ack lane_land script",
                        "echo 'gh api repos/o/r/pulls/5/merge' > notes.txt", "grep owner-ack f && ls -l",
                        "cat >> notes.md <<EOF\nscript lane_land\nEOF"):
            with self.subTest(command=command):
                self.assertTrue(merge_guard.exempt(command, str(TOOLS.parent)), command)
                self.assertIsNone(self.verdict(command))

    def test_raw_blocks_hold_wherever_one_condition_fails(self):
        for command in (
                "tools/pr_land.sh 5 --owner-ack", "gh pr merge 5", "script -q /dev/null tools/pr_land.sh 5", "unset FENTON_HEADLESS",
                "FENTON_HEADLESS=0 tools/pr_land.sh 5", "bash -c 'tools/pr_land.sh 5 --owner-ack'", "sh -c \"gh pr merge 5\"",
                "eval 'gh pr merge 5'", "echo $(gh pr merge 5)", "ls `gh pr merge 5`", "true; gh pr merge 5", "true && gh pr merge 5",
                "grep x f | xargs gh pr merge", "env gh pr merge 5", "command gh pr merge 5", "exec gh pr merge 5",
                "git push origin main", "cat f | bash", "grep -f <(gh pr merge 5) f", "echo ok\ngh pr merge 5",
                "echo $'\\''; gh pr merge 5; echo '\\'", "echo $\"x\"; gh pr merge 5",
                "cat <<END-1\nhi\nEND-1\ngh pr merge 5", "cat <<E\\OF\nhi\nEOF\ngh pr merge 5",
                ". /dev/stdin <<'EOF'\ngh pr merge 5\nEOF", "source /dev/stdin <<'EOF'\ngh pr merge 5\nEOF",
                "ksh <<EOF\ngh pr merge 5\nEOF", "cat <<'EOF' |\ngh pr merge 5\nEOF\nbash",
                "eval \"$(cat <<'EOF'\ngh pr merge 5\nEOF\n)\"", "$(cat <<'EOF'\ngh pr merge 5\nEOF\n)",
                "cat > /tmp/x <<EOF\ngh pr merge 5\nEOF\nsource /tmp/x", "python3 <<EOF\ngh api repos/o/r/pulls/5/merge -X PUT\nEOF",
                "echo 'gh pr merge 5' | sh",
                "echo 'x\ncat > f <<EOF\n'; gh pr merge 5; echo '\nEOF\n'",
                "cat > f <<EOF\nx\nEOF\ngh pr merge 5 # script lane_land",
                "python3 -c 'import os' ; gh pr merge 5", "python3 /tmp/nowhere.py; gh pr merge 5",
                "git -c core.hooksPath=/dev/null commit -m x; gh pr merge 5"):
            with self.subTest(command=command):
                self.assertIsNotNone(self.verdict(command), command)

    def test_known_gaps_of_the_raw_scan_are_not_widened(self):
        """Not blocked before this change either (output of a printing command run as a command); the exemption must not claim them."""
        for command in ("$(echo gh pr merge 5)", "echo 'gh pr merge 5' | xargs -0 sh -c", "find . -exec gh pr merge 5 ;",
                        "awk 'BEGIN{system(\"gh pr merge 5\")}'", "sed -n '1e gh pr merge 5' f"):
            with self.subTest(command=command):
                self.assertFalse(merge_guard.exempt(command, str(TOOLS.parent)), command)

    def test_each_exemption_condition_is_needed(self):
        for command in ("grep x f; gh pr merge 5", "grep x f | bash", "FOO=1 grep owner-ack f", "env grep owner-ack f",
                        "find . -name owner-ack", "sed -i 1p owner-ack", "sed -n -e 1p owner-ack", "awk 1 owner-ack", "xargs grep owner-ack",
                        "python3 -c 'print(1)' owner-ack", "python3 tools/nowhere.py owner-ack", "cat /dev/stdin owner-ack",
                        "echo $(cat owner-ack)", "git -c alias.x=y log --grep owner-ack", "git commit -c abc -m owner-ack",
                        "rg --pre ./x owner-ack", "python3 tools/bg_run.py x -- gh pr merge 5", "python3 tools/devcap.py run -- gh pr merge 5",
                        "python3 tools/ship.py", "python3 tools/triage/hass_triage.py x", "python3 tools/agent_status.py x",
                        "printf 'x' owner-ack", "printf -v X 'gh pr merge 5'; echo \"${(e)X}\"", "echo ${X}", "print -v X owner-ack",
                        "python3 tools/pr_land.py 5 --owner-ack", "python3 tools/lane_land.py", "python3 tools/triage/hass_triage.py ack-base", "cat <<EOF\nowner-ack\nEOF", "grep 'unclosed owner-ack", "(grep owner-ack f)",
                        "timeout 5 grep owner-ack f", "nohup grep owner-ack f"):
            with self.subTest(command=command):
                self.assertFalse(merge_guard.exempt(command, str(TOOLS.parent)), command)





class ReviewerSpawnTests(unittest.TestCase):
    def test_final_review_prompt_passes_agent_model_hook(self):
        spawn = {"subagent_type": "reviewer", "model": "opus", "prompt": "opus-ok: final review of PR 7"}
        self.assertIsNone(agent_model.reason(spawn))
        self.assertIsNotNone(agent_model.reason({"subagent_type": "reviewer", "model": "opus", "prompt": "review"}))

    def test_reviewer_definition_exists_with_checklist(self):
        text = (TOOLS.parent / ".claude/agents/reviewer.md").read_text()
        self.assertIn("model: opus", text)
        for item in ("swiftui-pro", "apple-hig", "System API", "HassCore", "tools/review/record.py"):
            self.assertIn(item, text)


class ShipDraftTests(unittest.TestCase):
    def make(self, tmp):
        origin = Path(tmp) / "origin.git"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], env=ENV, check=True)
        clone = Path(tmp) / "clone"
        subprocess.run(["git", "clone", "-q", str(origin), str(clone)], env=ENV, check=True, capture_output=True)
        (clone / "tools").mkdir()
        shutil.copy(TOOLS / "ship.sh", clone / "tools/ship.sh")
        shutil.copy(TOOLS / "ship_guard.sh", clone / "tools/ship_guard.sh")
        shutil.copy(TOOLS / "review_verdict.py", clone / "tools/review_verdict.py")
        (clone / ".gitignore").write_text("build/\n")
        (clone / "a").write_text("1\n")
        subprocess.run(["git", "add", "-A"], cwd=clone, env=ENV, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "i"], cwd=clone, env=ENV, check=True)
        subprocess.run(["git", "push", "-q", "-u", "origin", "main"], cwd=clone, env=ENV, check=True, capture_output=True)
        subprocess.run(["git", "checkout", "-q", "-b", "claude/t"], cwd=clone, env=ENV, check=True)
        (clone / "a").write_text("2\n")
        fake = Path(tmp) / "bin"
        fake.mkdir()
        (fake / "gh").write_text("#!/bin/sh\necho gh \"$@\"\n")
        (fake / "gh").chmod(0o755)
        return clone, {**ENV, "PATH": f"{fake}:{os.environ['PATH']}"}

    def test_pr_is_always_a_draft_and_needs_no_review_file(self):
        with TemporaryDirectory() as tmp:
            clone, env = self.make(tmp)
            proc = subprocess.run(["tools/ship.sh", "Do it", "--pr"], cwd=clone, env=env, capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("--draft", proc.stdout)


if __name__ == "__main__":
    unittest.main()
