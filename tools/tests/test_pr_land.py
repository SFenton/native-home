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


def run_check(name, conclusion="SUCCESS", status="COMPLETED"):
    return {"name": name, "status": status, "conclusion": conclusion}


def timed_check(name, conclusion, started, status="COMPLETED", workflow="pr-checks"):
    return {**run_check(name, conclusion, status), "startedAt": started, "workflowName": workflow}


#: The reviewer identity ``tools/review/record.py`` stamps into a verdict (the landers refuse a verdict without it).
ID = {"reviewer": {"agent_type": "reviewer", "session_id": "s-1", "agent_id": ""}}


class ChecksStateTests(unittest.TestCase):
    def test_superseded_runs_do_not_count(self):
        # PR #215: two failed runs on the head SHA, then a green re-run (close and reopen).
        rollup = [timed_check("pr-checks", "FAILURE", "2026-10-30T00:59:28Z"),
                  timed_check("swift-test", "FAILURE", "2026-10-30T00:04:14Z"),
                  timed_check("pr-checks", "SUCCESS", "2026-10-30T03:45:15Z"),
                  timed_check("swift-test", "SUCCESS", "2026-10-30T01:56:04Z"),
                  timed_check("pr-checks", "FAILURE", "2026-10-30T01:12:42Z")]
        self.assertEqual(pr_land.checks_state(rollup, ["pr-checks"]), ("green", "all checks green"))

    def test_newest_failure_still_blocks(self):
        rollup = [timed_check("pr-checks", "SUCCESS", "2026-10-30T01:00:00Z"),
                  timed_check("pr-checks", "FAILURE", "2026-10-30T02:00:00Z")]
        self.assertEqual(pr_land.checks_state(rollup, ["pr-checks"])[0], "failed")

    def test_queued_rerun_is_pending_not_green(self):
        rollup = [timed_check("pr-checks", "SUCCESS", "2026-10-30T01:00:00Z"),
                  timed_check("pr-checks", None, None, "QUEUED")]
        self.assertEqual(pr_land.checks_state(rollup, ["pr-checks"])[0], "pending")

    def test_same_job_name_in_two_workflows_both_count(self):
        rollup = [timed_check("build", "SUCCESS", "2026-10-30T02:00:00Z", workflow="a"),
                  timed_check("build", "FAILURE", "2026-10-30T01:00:00Z", workflow="b")]
        self.assertEqual(pr_land.checks_state(rollup)[0], "failed")

    def test_newer_in_progress_beats_older_success(self):
        rollup = [timed_check("pr-checks", "SUCCESS", "2026-10-30T01:00:00Z"),
                  timed_check("pr-checks", None, "2026-10-30T02:00:00Z", "IN_PROGRESS")]
        self.assertEqual(pr_land.checks_state(rollup, ["pr-checks"])[0], "pending")

    def test_equal_started_at_the_less_green_run_wins_in_either_order(self):
        stamp = "2026-10-30T01:00:00Z"
        ok, bad = timed_check("pr-checks", "SUCCESS", stamp), timed_check("pr-checks", "FAILURE", stamp)
        self.assertEqual(pr_land.checks_state([ok, bad], ["pr-checks"])[0], "failed")
        self.assertEqual(pr_land.checks_state([bad, ok], ["pr-checks"])[0], "failed")

    def test_completed_without_started_at_is_oldest(self):
        undated = timed_check("pr-checks", "SUCCESS", None)
        newer_failure = timed_check("pr-checks", "FAILURE", "2026-10-30T01:00:00Z")
        self.assertEqual(pr_land.checks_state([newer_failure, undated], ["pr-checks"])[0], "failed")
        self.assertEqual(pr_land.checks_state([undated, newer_failure], ["pr-checks"])[0], "failed")

    def test_gh_zero_time_counts_as_missing_started_at(self):
        zero = "0001-01-01T00:00:00Z"
        newer_failure = timed_check("pr-checks", "FAILURE", "2026-10-30T01:00:00Z")
        self.assertEqual(pr_land.checks_state([timed_check("pr-checks", "SUCCESS", zero), newer_failure])[0], "failed")
        queued = timed_check("pr-checks", None, zero, "QUEUED")
        self.assertEqual(pr_land.checks_state([timed_check("pr-checks", "SUCCESS", "2026-10-30T01:00:00Z"), queued])[0],
                         "pending")

    def test_two_apps_with_the_same_check_name_stay_separate(self):
        old_fail = {**run_check("lint", "FAILURE"), "startedAt": "2026-10-30T01:00:00Z",
                    "detailsUrl": "https://ci.one.example/run/1"}
        new_ok = {**run_check("lint", "SUCCESS"), "startedAt": "2026-10-30T02:00:00Z",
                  "detailsUrl": "https://ci.two.example/run/9"}
        self.assertEqual(len(pr_land.latest_runs([old_fail, new_ok])), 2)
        self.assertEqual(pr_land.checks_state([old_fail, new_ok])[0], "failed")
        by_slug = [{**old_fail, "app": {"slug": "one"}, "detailsUrl": ""}, {**new_ok, "app": {"slug": "two"}, "detailsUrl": ""}]
        self.assertEqual(len(pr_land.latest_runs(by_slug)), 2)

    def test_commit_statuses_pass_through(self):
        rollup = [{"context": "ci/x", "state": "FAILURE"}, {"context": "ci/x", "state": "SUCCESS"}]
        self.assertEqual(len(pr_land.latest_runs(rollup)), 2)

    def test_none_configured_passes(self):
        self.assertEqual(pr_land.checks_state([])[0], "none")
        self.assertEqual(pr_land.checks_state(None)[0], "none")

    def test_green_pending_failed(self):
        self.assertEqual(pr_land.checks_state([run_check("a"), run_check("b", "SKIPPED")])[0], "green")
        self.assertEqual(pr_land.checks_state([run_check("a"), run_check("b", None, "IN_PROGRESS")])[0], "pending")
        state, detail = pr_land.checks_state([run_check("a"), run_check("lint", "FAILURE")])
        self.assertEqual(state, "failed")
        self.assertIn("lint", detail)

    def test_commit_statuses(self):
        self.assertEqual(pr_land.checks_state([{"context": "ci", "state": "SUCCESS"}])[0], "green")
        self.assertEqual(pr_land.checks_state([{"context": "ci", "state": "PENDING"}])[0], "pending")
        self.assertEqual(pr_land.checks_state([{"context": "ci", "state": "FAILURE"}])[0], "failed")


class RequiredChecksAndKillSwitchTests(unittest.TestCase):
    def test_missing_required_check_is_pending(self):
        self.assertEqual(pr_land.checks_state([], ["pr-checks"])[0], "pending")
        self.assertEqual(pr_land.checks_state([run_check("other")], ["pr-checks"])[0], "pending")
        self.assertEqual(pr_land.checks_state([run_check("pr-checks")], ["pr-checks"])[0], "green")
        self.assertEqual(pr_land.REQUIRED_CHECKS, ["pr-checks"])

    def test_required_check_must_be_a_successful_check_run(self):
        required = ["pr-checks"]
        # SKIPPED or NEUTRAL do not vouch for the head; a commit status of the same name is not a check run.
        self.assertEqual(pr_land.checks_state([run_check("pr-checks", "SKIPPED")], required)[0], "failed")
        self.assertEqual(pr_land.checks_state([run_check("pr-checks", "NEUTRAL")], required)[0], "failed")
        self.assertEqual(pr_land.checks_state([{"context": "pr-checks", "state": "SUCCESS"}], required)[0], "pending")
        # other checks may still be skipped
        self.assertEqual(pr_land.checks_state([run_check("pr-checks"), run_check("x", "SKIPPED")], required)[0], "green")

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


class ReviewStateTests(unittest.TestCase):
    def test_missing_review_blocks(self):
        self.assertFalse(pr_land.review_state(None, "abc")[0])

    def test_pass_lands(self):
        self.assertTrue(pr_land.review_state({**ID, "verdict": "pass", "round": 1, "head": "abc"}, "abc")[0])

    def test_review_without_head_blocks(self):
        self.assertFalse(pr_land.review_state({**ID, "verdict": "pass", "round": 1}, "abc")[0])
        self.assertFalse(pr_land.review_state({**ID, "verdict": "pass", "round": 1, "head": "abc"}, "")[0])

    def test_stale_head_blocks(self):
        ok, why = pr_land.review_state({**ID, "verdict": "pass", "head": "aaaa1111"}, "bbbb2222")
        self.assertFalse(ok)
        self.assertIn("review again", why)

    def test_changes_round_one_blocks_round_two_lands_unless_blocker(self):
        major = [{"severity": "major", "rule": "pattern", "detail": "x"}]
        self.assertFalse(pr_land.review_state({**ID, "verdict": "changes", "round": 1, "head": "h", "findings": major}, "h")[0])
        self.assertTrue(pr_land.review_state({**ID, "verdict": "changes", "round": 2, "head": "h", "findings": major}, "h")[0])
        blocker = major + [{"severity": "blocker", "rule": "perf", "detail": "main thread"}]
        self.assertFalse(pr_land.review_state({**ID, "verdict": "changes", "round": 3, "head": "h", "findings": blocker}, "h")[0])
        self.assertFalse(pr_land.review_state({**ID, "verdict": "blocker", "round": 1, "head": "h"}, "h")[0])

    def test_pass_with_blocker_finding_blocks(self):
        blocker = [{"severity": "blocker", "rule": "perf", "detail": "d"}]
        self.assertFalse(pr_land.review_state({**ID, "verdict": "pass", "head": "h", "findings": blocker}, "h")[0])

    def test_unknown_verdict_blocks(self):
        self.assertFalse(pr_land.review_state({**ID, "verdict": "maybe", "head": "h"}, "h")[0])

    def test_branch_file_name(self):
        self.assertEqual(pr_land.review_file_name("claude/pr-lifecycle"), "claude__pr-lifecycle.json")


class LandTests(unittest.TestCase):
    """``land`` with a fake ``gh`` and a throwaway repository."""

    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "feat/x"], cwd=self.repo, env=ENV, check=True)
        subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "i"], cwd=self.repo, env=ENV, check=True)
        self.fake = Path(self.tmp.name) / "bin"
        self.fake.mkdir()
        self.log = Path(self.tmp.name) / "gh.log"
        self.origin = self.seed_origin()

    def publish_pr(self, files):
        """Make the pull request head: ``files`` (path to text) on top of ``origin/main``, built with plumbing so this checkout's work tree
        is untouched, published as ``refs/pull/7/head`` of the bare origin (the gate and the local checks fetch it). Sets ``self.head``."""
        index = self.repo / ".git" / "pr-index"
        env = {**ENV, "GIT_INDEX_FILE": str(index)}
        index.unlink(missing_ok=True)
        subprocess.run(["git", "read-tree", "origin/main"], cwd=self.repo, env=env, check=True)
        for path, text in files.items():
            blob = subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=self.repo, env=env, input=text, capture_output=True,
                                  text=True, check=True).stdout.strip()
            subprocess.run(["git", "update-index", "--add", "--cacheinfo", f"100644,{blob},{path}"], cwd=self.repo, env=env, check=True)
        tree = subprocess.run(["git", "write-tree"], cwd=self.repo, env=env, capture_output=True, text=True, check=True).stdout.strip()
        self.head = subprocess.run(["git", "commit-tree", tree, "-p", "origin/main", "-m", "pr"], cwd=self.repo, env=ENV,
                                   capture_output=True, text=True, check=True).stdout.strip()
        subprocess.run(["git", "push", "-q", "-f", str(self.bare), f"{self.head}:refs/pull/7/head"], cwd=self.repo, env=ENV, check=True)

    def seed_origin(self, lane_land_text=None):
        """A bare origin whose ``main`` holds ``tools/lane_land.py`` (the trusted copy the gate runs), added as ``origin``."""
        bare = Path(self.tmp.name) / "origin.git"
        seed = Path(self.tmp.name) / "seed"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], check=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(seed)], cwd=self.tmp.name, env=ENV, check=True)
        (seed / "tools").mkdir()
        (seed / "tools" / "lane_land.py").write_text(lane_land_text or (TOOLS / "lane_land.py").read_text())
        (seed / "tools" / "triage").mkdir()
        (seed / "tools" / "house_scan.py").write_text((TOOLS / "house_scan.py").read_text())  # the trusted copy the local checks run
        (seed / "tools" / "triage" / "config.json").write_text((TOOLS / "triage" / "config.json").read_text())
        (seed / "contracts").mkdir()
        (seed / "contracts" / "house_scan.json").write_text((TOOLS.parent / "contracts" / "house_scan.json").read_text())
        subprocess.run(["git", "add", "-A"], cwd=seed, env=ENV, check=True)
        subprocess.run(["git", "commit", "-qm", "base"], cwd=seed, env=ENV, check=True)
        subprocess.run(["git", "push", "-q", str(bare), "main"], cwd=seed, env=ENV, check=True)
        subprocess.run(["git", "fetch", "-q", str(bare), "main:refs/remotes/origin/main"], cwd=self.repo, env=ENV, check=True)
        self.bare = bare
        self.publish_pr({})
        subprocess.run(["git", "remote", "add", "origin", "https://example.invalid/not/the/product.git"], cwd=self.repo, env=ENV, check=True)
        # The gate clones product_repo's URL from the config (never this checkout's remote); the test maps that URL to the local bare repo.
        self.gitconfig = Path(self.tmp.name) / "gitconfig"
        product = json.loads((TOOLS / "triage" / "config.json").read_text())["product_repo"]
        self.gitconfig.write_text(f'[url "{bare}"]\n\tinsteadOf = https://github.com/{product}.git\n')
        return bare

    def gh(self, info):
        script = self.fake / "gh"
        script.write_text(f"#!/bin/sh\necho \"$@\" >> {self.log}\n"
                          f"if [ \"$2\" = view ]; then cat <<'EOF'\n{json.dumps(info)}\nEOF\nfi\n")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)

    def review(self, **data):
        path = self.repo / "build" / "review"
        path.mkdir(parents=True, exist_ok=True)
        data.setdefault("head", self.head)
        data.setdefault("reviewer", ID["reviewer"])
        (path / "feat__x.json").write_text(json.dumps(data))

    def land(self, dry=False, extra=(), env_extra=None):
        env = {**ENV, "PATH": f"{self.fake}:{os.environ['PATH']}", "HOME": self.tmp.name, "GIT_CONFIG_GLOBAL": str(self.gitconfig),
               **(env_extra or {})}
        args = ["python3", str(TOOLS / "pr_land.py"), "7"] + (["--dry-run"] if dry else []) + list(extra)
        proc = subprocess.run(args, cwd=self.repo, env=env, capture_output=True, text=True)
        return proc.returncode, proc.stdout.strip()

    def info(self, **extra):
        return {"state": "OPEN", "isDraft": False, "headRefName": "feat/x", "headRefOid": self.head, "mergeable": "MERGEABLE",
                "baseRefName": "main", "statusCheckRollup": [run_check("pr-checks")], "files": [{"path": "tools/x.py"}],
                "body": "", "title": "t", "author": {"login": "SFenton"}, **extra}

    def test_a_pr_that_edits_the_gate_is_still_judged_by_the_base_copy(self):
        """The invoking checkout's lane_land.py says everything passes; the base branch's copy is the one that runs."""
        tools = self.repo / "tools"
        tools.mkdir()
        shutil.copy(TOOLS / "pr_land.py", tools / "pr_land.py")
        (tools / "lane_land.py").write_text("import sys\nprint('PWNED app-UI gate passed')\nsys.exit(0)\n")
        (tools / "triage").mkdir()
        shutil.copy(TOOLS / "triage" / "config.json", tools / "triage" / "config.json")
        self.publish_pr({"apple/Sources/HassUI/Chip.swift": "struct Chip {}\n"})
        self.gh(self.info(files=[{"path": "apple/Sources/HassUI/Chip.swift"}]))
        self.review(verdict="pass", round=1, head=self.head)
        env = {**ENV, "PATH": f"{self.fake}:{os.environ['PATH']}", "HOME": self.tmp.name, "GIT_CONFIG_GLOBAL": str(self.gitconfig)}
        env.pop("FENTON_HEADLESS", None)
        proc = subprocess.run(["python3", str(tools / "pr_land.py"), "7"], cwd=self.repo, env=env, capture_output=True, text=True)
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 1, out)
        self.assertNotIn("PWNED", out)
        self.assertIn("blocked #7: app-UI gate", out)  # the base copy of the gate refuses an app view with no design record
        self.assertNotIn("example.invalid", out)  # this checkout's own (wrong) origin remote was never used
        self.assertFalse(self.merged())
        trusted = Path(self.tmp.name) / "hass-agents" / "gate-trusted" / "Fenton-HASS-Native" / "tools" / "lane_land.py"
        self.assertNotIn("PWNED", trusted.read_text())  # what ran is the base copy

    def merged(self):
        return self.log.exists() and "pr merge" in self.log.read_text()

    def land_with_config(self, **overrides):
        """Run a copy of pr_land.py (and house_scan.py) whose triage config is the repo's plus ``overrides``."""
        tools = self.repo / "tools"
        (tools / "triage").mkdir(parents=True, exist_ok=True)
        shutil.copy(TOOLS / "pr_land.py", tools / "pr_land.py")
        shutil.copy(TOOLS / "house_scan.py", tools / "house_scan.py")
        cfg = json.loads((TOOLS / "triage" / "config.json").read_text())
        cfg.update(overrides)
        cfg = {k: v for k, v in cfg.items() if v is not None}
        (tools / "triage" / "config.json").write_text(json.dumps(cfg))
        env = {**ENV, "PATH": f"{self.fake}:{os.environ['PATH']}", "HOME": self.tmp.name, "GIT_CONFIG_GLOBAL": str(self.gitconfig)}
        env.pop("FENTON_HEADLESS", None)
        env.pop("HOUSE_SCAN_DENYLIST", None)
        proc = subprocess.run(["python3", str(tools / "pr_land.py"), "7"], cwd=self.repo, env=env, capture_output=True, text=True)
        return proc.returncode, proc.stdout.strip()

    def test_checks_are_required_when_the_key_is_true_or_missing_and_skipped_when_false(self):
        self.review(verdict="pass", round=1, head=self.head)
        for overrides in ({"require_checks": True}, {"require_checks": None}):
            self.gh(self.info(statusCheckRollup=[]))
            code, line = self.land_with_config(**overrides)
            with self.subTest(overrides=overrides):
                self.assertEqual(code, 1, line)
                self.assertIn("pr-checks", line)
                self.assertFalse(self.merged())
        self.gh(self.info(statusCheckRollup=[]))
        code, line = self.land_with_config(require_checks=False)
        self.assertEqual((code, line.split(" ")[:2]), (0, ["merged", "#7"]), line)
        self.assertIn("checks not required", line)
        self.assertTrue(self.merged())

    def test_review_is_still_required_when_checks_are_not(self):
        self.gh(self.info(statusCheckRollup=[]))
        for review in (dict(verdict="changes", round=1, head=self.head), dict(verdict="pass", round=1, head="stale")):
            self.review(**review)
            code, line = self.land_with_config(require_checks=False)
            with self.subTest(review=review):
                self.assertEqual(code, 1, line)
                self.assertFalse(self.merged())
        (self.repo / "build" / "review" / "feat__x.json").unlink()
        code, line = self.land_with_config(require_checks=False)
        self.assertEqual(code, 1, line)
        self.assertFalse(self.merged())

    def test_green_checks_plus_passing_review_merge(self):
        self.gh(self.info())
        self.review(verdict="pass", round=1, head=self.head)
        code, line = self.land_with_config(require_checks=True)
        self.assertEqual((code, line.split(" ")[:2]), (0, ["merged", "#7"]), line)
        self.assertTrue(self.merged())
        self.assertIn("--squash", self.log.read_text())

    def test_the_shipped_config_is_review_only_and_keeps_the_denylist_optional(self):
        cfg = json.loads((TOOLS / "triage" / "config.json").read_text())
        self.assertIs(cfg["require_checks"], False)
        self.assertIs(cfg["denylist_required"], False)
        self.assertEqual(pr_land.required_checks({}), ["pr-checks"])
        self.assertEqual(pr_land.required_checks({"require_checks": True}), ["pr-checks"])
        self.assertEqual(pr_land.required_checks({"require_checks": False}), [])

    def test_needs_decision_label_blocks_landing(self):
        self.gh(self.info(labels=[{"name": "Needs Decision"}]))
        self.review(verdict="pass", round=1, head=self.head)
        code, line = self.land()
        self.assertEqual(code, 1, line)
        self.assertIn("owner decides first", line)
        self.assertFalse(self.merged())
        self.gh(self.info(labels=[{"name": "Ready to Merge"}]))
        self.assertEqual(self.land()[0], 0)

    def test_dry_run_never_merges(self):
        self.gh(self.info())
        self.review(verdict="pass", round=1)
        code, line = self.land(dry=True)
        self.assertEqual(code, 0, line)
        self.assertTrue(line.startswith("would merge"))
        self.assertFalse(self.merged())

    def test_stale_review_head_blocks(self):
        self.gh(self.info(headRefOid="def"))
        self.review(verdict="pass", round=1, head=self.head)
        code, line = self.land()
        self.assertEqual(code, 1)
        self.assertIn("review again", line)
        self.assertFalse(self.merged())

    def test_kill_switch_pauses_landing(self):
        self.gh(self.info())
        self.review(verdict="pass", round=1)
        paused = Path(self.tmp.name) / "PAUSED"
        paused.write_text("x")
        code, line = self.land(env_extra={"HASS_TRIAGE_PAUSED_FILE": str(paused)})
        self.assertEqual(code, 1)
        self.assertIn("landing paused", line)
        self.assertFalse(self.merged())

    def test_review_flag_is_dry_run_only(self):
        self.gh(self.info())
        self.review(verdict="pass", round=1)
        other = Path(self.tmp.name) / "r.json"
        other.write_text(json.dumps({**ID, "verdict": "pass", "head": self.head}))
        self.assertEqual(self.land(extra=["--review", str(other)])[0], 2)
        self.assertFalse(self.merged())
        self.assertEqual(self.land(dry=True, extra=["--review", str(other)])[0], 0)

    def test_failing_or_pending_checks_block(self):
        self.review(verdict="pass", round=1)
        for rollup, word in (([run_check("pr-checks", "FAILURE")], "failing"), ([run_check("pr-checks", None, "QUEUED")], "running")):
            self.gh(self.info(statusCheckRollup=rollup))
            code, line = self.land_with_config(require_checks=True)
            self.assertEqual(code, 1)
            self.assertIn(word, line)
        self.assertFalse(self.merged())

    def test_missing_review_and_conflicts_block(self):
        self.gh(self.info())
        code, line = self.land()
        self.assertEqual(code, 1)
        self.assertIn("no review", line)
        self.review(verdict="pass", round=1)
        self.gh(self.info(mergeable="CONFLICTING"))
        self.assertEqual(self.land()[0], 1)
        self.gh(self.info(state="MERGED"))
        self.assertEqual(self.land()[0], 1)
        self.assertFalse(self.merged())

    def test_gh_failure_reports_failed(self):
        script = self.fake / "gh"
        script.write_text("#!/bin/sh\necho boom >&2\nexit 1\n")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)
        code, line = self.land()
        self.assertEqual(code, 2)
        self.assertTrue(line.startswith("failed #7"))

    def test_draft_is_marked_ready_before_merge(self):
        self.gh(self.info(isDraft=True))
        self.review(verdict="pass", round=1)
        self.assertEqual(self.land()[0], 0)
        text = self.log.read_text()
        self.assertLess(text.index("pr ready"), text.index("pr merge"))


    IP = ".".join(["10", "9", "8", "20"])

    def test_review_only_runs_house_scan_and_pattern_guard_locally_on_the_exact_head(self):
        """Major 4: ``require_checks: false`` drops CI, so the cheap checks run here with the base's tools; with CI required they are CI's."""
        self.publish_pr({"notes.txt": f"host {self.IP}\n"})
        self.gh(self.info())
        self.review(verdict="pass", round=1)
        code, line = self.land_with_config(require_checks=False)
        self.assertEqual(code, 1, line)
        self.assertIn("blocked #7: house_scan:", line)
        self.assertIn("notes.txt:1", line)
        self.assertFalse(self.merged())
        code, line = self.land_with_config(require_checks=True)  # CI is the gate there (its own run of the same check), the fake rollup is green
        self.assertEqual(code, 0, line)
        self.assertNotIn("run locally", line)

    def test_a_pr_cannot_loosen_its_own_local_check_through_its_config(self):
        self.publish_pr({"notes.txt": f"host {self.IP}\n", "contracts/house_scan.json": json.dumps({"allow": {"skip_prefixes": ["notes"]}})})
        self.gh(self.info())
        self.review(verdict="pass", round=1)
        code, line = self.land_with_config(require_checks=False)
        self.assertEqual(code, 1, line)
        self.assertIn("notes.txt:1", line)

    def test_a_clean_head_lands_and_the_line_says_what_ran(self):
        self.gh(self.info())
        self.review(verdict="pass", round=1)
        code, line = self.land_with_config(require_checks=False)
        self.assertEqual(code, 0, line)
        self.assertIn("house_scan and pattern_guard run locally", line)

    def test_pattern_guard_is_the_bases_copy_run_over_the_head(self):
        for exit_code, expected in ((1, 1), (0, 0)):
            with self.subTest(exit_code=exit_code), TemporaryDirectory() as tmp:
                bare = Path(tmp) / "b.git"
                subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], check=True)
                seed = Path(tmp) / "seed"
                subprocess.run(["git", "init", "-q", "-b", "main", str(seed)], env=ENV, check=True)
                (seed / "tools").mkdir()
                (seed / "tools" / "house_scan.py").write_text((TOOLS / "house_scan.py").read_text())
                (seed / "tools" / "pattern_guard.py").write_text(f"import sys\nprint('error: from the base copy')\nsys.exit({exit_code})\n")
                subprocess.run(["git", "add", "-A"], cwd=seed, env=ENV, check=True)
                subprocess.run(["git", "commit", "-qm", "base"], cwd=seed, env=ENV, check=True)
                subprocess.run(["git", "push", "-q", str(bare), "main"], cwd=seed, env=ENV, check=True)
                repo = Path(tmp) / "repo"
                subprocess.run(["git", "clone", "-q", str(bare), str(repo)], env=ENV, check=True)
                (repo / "tools" / "pattern_guard.py").write_text("import sys\nsys.exit(0)\n")  # the PR rewrites the guard to pass
                subprocess.run(["git", "commit", "-qam", "weaken"], cwd=repo, env=ENV, check=True)
                head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, env=ENV, capture_output=True, text=True).stdout.strip()
                cwd = os.getcwd()
                os.chdir(repo)
                try:
                    refused = pr_land.local_gates("7", head, "main")
                finally:
                    os.chdir(cwd)
                if expected:
                    self.assertIn("pattern_guard: error: from the base copy", refused or "")
                else:
                    self.assertIsNone(refused)

    def test_the_local_checks_fail_closed_without_a_readable_base_or_head(self):
        with TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], env=ENV, check=True)
            subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "i"], cwd=repo, env=ENV, check=True)
            head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, env=ENV, capture_output=True, text=True).stdout.strip()
            cwd = os.getcwd()
            os.chdir(repo)
            try:
                self.assertIn("cannot read origin/main", pr_land.local_gates("7", head, "main") or "")
                self.assertIn("cannot read the head", pr_land.local_gates("7", "0" * 40, "main") or "")
            finally:
                os.chdir(cwd)


open_real = open


class UiGateInLandTests(unittest.TestCase):
    """``pr_land.land`` runs the lander's app-UI gate (``lane_land.pr_gate``) before it merges; ``--owner-ack`` is owner-only."""

    HEAD = "a" * 40

    def info(self, **extra):
        return {"state": "OPEN", "isDraft": False, "headRefName": "feat/ui", "headRefOid": self.HEAD, "mergeable": "MERGEABLE",
                "baseRefName": "main", "statusCheckRollup": [run_check("pr-checks")], "labels": [],
                "files": [{"path": "apple/Sources/HassUI/Chip.swift"}], "body": "", "title": "t", "author": {"login": "SFenton"}, **extra}

    def land(self, gate=None, ack=False, dry=True, env=None, tty=True, info=None):
        calls = []

        def fake_run(args, check=True):
            calls.append(args)
            return mock.Mock(returncode=0, stdout=json.dumps(info or self.info()), stderr="")
        patches = [mock.patch.object(pr_land, "run", fake_run),
                   mock.patch.object(pr_land, "kill_switch", return_value=None),
                   mock.patch.object(pr_land, "find_review", return_value={**ID, "verdict": "pass", "head": self.HEAD, "findings": []}),
                   mock.patch.object(pr_land, "cleanup", return_value=""),
                   mock.patch.object(pr_land, "local_gates", return_value=None),
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
        return pr_land.land("9", dry, None, owner_ack=ack), calls

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
        self.assertEqual(pr_land.PRODUCT_REPO, "SFenton/Fenton-HASS-Native")
        self.assertEqual(pr_land.expected_origin({"product_repo": pr_land.PRODUCT_REPO}), "https://github.com/SFenton/Fenton-HASS-Native.git")
        # the checked-in config agrees, so a config edit that disagrees is the thing that gets refused
        self.assertEqual(json.loads((TOOLS / "triage" / "config.json").read_text())["product_repo"], pr_land.PRODUCT_REPO)
        for cfg in ({}, {"product_repo": ""}, {"product_repo": "evil/Fenton-HASS-Native"}, {"product_repo": "o/r.x-y"},
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


class CleanupTests(unittest.TestCase):
    """Post-merge worktree removal: only when nothing is lost and the caller is not inside it."""

    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.main = Path(self.tmp.name).resolve() / "main"
        self.main.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=self.main, env=ENV, check=True)
        subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "i"], cwd=self.main, env=ENV, check=True)
        self.wt = Path(self.tmp.name).resolve() / "lane"
        subprocess.run(["git", "worktree", "add", "-q", "-b", "feat/x", str(self.wt)], cwd=self.main, env=ENV, check=True)
        self.head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=self.wt, capture_output=True, text=True).stdout.strip()
        old = os.getcwd()
        os.chdir(self.main)
        self.addCleanup(os.chdir, old)
        # cleanup() runs the derived-orphans sweep: point it at a temp folder, never the real DerivedData.
        self.derived = Path(self.tmp.name).resolve() / "DerivedData"
        self.derived.mkdir()
        patcher = mock.patch.dict(os.environ, {**ENV, "HASS_DERIVED_DATA": str(self.derived)})
        patcher.start()
        self.addCleanup(patcher.stop)
        import ci_hygiene  # the reap checks read devcap, which is not under test here
        holds = mock.patch.object(ci_hygiene, "devcap_cwds", return_value=[])
        holds.start()
        self.addCleanup(holds.stop)

    def test_keeps_a_dirty_worktree(self):
        (self.wt / "wip.txt").write_text("x")
        note = pr_land.cleanup("feat/x", self.head, keep=False, cwd=self.main)
        self.assertIn("uncommitted or untracked", note)
        self.assertTrue(self.wt.exists())

    def test_keeps_a_locked_worktree(self):
        subprocess.run(["git", "worktree", "lock", str(self.wt)], cwd=self.main, env=ENV, check=True)
        note = pr_land.cleanup("feat/x", self.head, keep=False, cwd=self.main)
        self.assertIn("locked", note)
        self.assertTrue(self.wt.exists())

    def test_keeps_a_worktree_a_live_process_works_in(self):
        proc = subprocess.Popen(["sleep", "30"], cwd=self.wt)
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        note = pr_land.cleanup("feat/x", self.head, keep=False, cwd=self.main)
        self.assertIn("live process", note)
        self.assertTrue(self.wt.exists())

    def test_safe_cleanup_never_raises(self):
        with mock.patch.object(pr_land, "cleanup", side_effect=RuntimeError("git gone")):
            note = pr_land.safe_cleanup("feat/x", self.head, False)
        self.assertIn("cleanup skipped", note)

    def derived_folder(self, name, workspace):
        folder = self.derived / name
        folder.mkdir()
        (folder / "info.plist").write_bytes(plistlib.dumps({"WorkspacePath": str(workspace)}))
        return folder

    def test_cleanup_removes_an_orphaned_derived_folder_and_keeps_a_live_one(self):
        orphan = self.derived_folder("FentonHome-orphan", Path(self.tmp.name) / "deleted" / "FentonHome.xcodeproj")
        live = self.derived_folder("FentonHome-live", self.main)
        pr_land.cleanup("feat/x", self.head, keep=False, cwd=self.main)
        self.assertFalse(orphan.exists())
        self.assertTrue(live.exists())

    def branches(self):
        return subprocess.run(["git", "branch", "--list", "feat/x"], cwd=self.main, capture_output=True, text=True).stdout

    def test_removes_when_tip_matches_and_cwd_is_elsewhere(self):
        note = pr_land.cleanup("feat/x", self.head, keep=False, cwd=self.main)
        self.assertIn("removed worktree lane", note)
        self.assertFalse(self.wt.exists())
        self.assertEqual(self.branches().strip(), "")

    def test_keeps_when_flagged(self):
        note = pr_land.cleanup("feat/x", self.head, keep=True, cwd=self.main)
        self.assertIn("kept (--keep-worktree)", note)
        self.assertIn("worktree remove", note)
        self.assertTrue(self.wt.exists())

    def test_keeps_when_local_tip_moved_past_the_merged_head(self):
        subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "unpushed"], cwd=self.wt, env=ENV, check=True)
        note = pr_land.cleanup("feat/x", self.head, keep=False, cwd=self.main)
        self.assertIn("is not the merged", note)
        self.assertTrue(self.wt.exists())
        self.assertIn("feat/x", self.branches())

    def test_keeps_when_caller_is_inside_the_worktree(self):
        (self.wt / "sub").mkdir()
        note = pr_land.cleanup("feat/x", self.head, keep=False, cwd=self.wt / "sub")
        self.assertIn("you are inside it", note)
        self.assertTrue(self.wt.exists())

    def test_no_worktree_is_silent(self):
        self.assertEqual(pr_land.cleanup("other", self.head, keep=False, cwd=self.main), "")


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
        for name, text in (("tools/pr_land.sh", "sh\n"), ("tools/pr_land.py", "py\n"), ("tools/house_scan.py", "hs\n"), ("tools/triage/config.json", "{}\n")):
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
                        "find . -name owner-ack", "sed -n 1p owner-ack", "awk 1 owner-ack", "xargs grep owner-ack",
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
