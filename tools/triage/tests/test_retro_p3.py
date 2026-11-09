"""Option A (owner, 2026-11-02): the runner, not the agent, reviews and merges the lanes a session pushed. Real git in temp
repos with a local bare origin; the session and the reviewer are fake launches. No network, gh or claude."""
from __future__ import annotations

import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import test_hass_triage as t  # noqa: E402
import lane_land  # noqa: E402

ht = t.ht
REAL_REAP = lane_land.reap_group  # the base test class replaces it so a fake pid is never killed
FakeGitHub = t.FakeGitHub
BASE = "claude/uikit-port"
GENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}


def g(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True,
                          env={**os.environ, **GENV}).stdout.strip()


class LandBase(t.Base):
    """A bare origin with the base, a dev clone that plays the agent pushing lanes, and the runner's land clone."""

    def setUp(self):
        super().setUp()
        env = mock.patch.dict(os.environ, GENV)
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("FENTON_HEADLESS", None)
        # the reaper after a landing must not read this machine's primary clone, its worktrees or its processes
        import ci_hygiene
        primary = mock.patch.object(ci_hygiene, "resolve_primary_repo", return_value=(None, "no primary clone configured: test"))
        primary.start()
        self.addCleanup(primary.stop)
        self.tmp = Path(tempfile.mkdtemp(prefix="retro-p3-")).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.origin = self.tmp / "origin.git"
        subprocess.run(["git", "init", "-q", "--bare", str(self.origin)], check=True)
        self.dev = self.tmp / "dev"
        subprocess.run(["git", "init", "-q", "-b", BASE, str(self.dev)], check=True)
        (self.dev / "a.txt").write_text("a\n")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "init")
        g(self.dev, "remote", "add", "origin", str(self.origin))
        g(self.dev, "push", "-q", "origin", BASE)
        self.cfg["land_tests"] = "true"
        self.cfg["workflow_base"] = BASE  # the fixture keeps a workflow base apart from the product base; SharedBaseTests joins them
        self.land_dir = lane_land.land_clone(self.paths.root, str(self.origin), self.cfg["product_repo"].split("/")[1])
        self.launches = []

    def runner(self, *args, **kw):
        """Lanes these tests push before the session count as pushed during it (an empty snapshot); `SnapshotTests` takes real ones."""
        runner = super().runner(*args, **kw)
        if not getattr(self, "real_snapshots", False):
            runner.snapshot_lanes = lambda label: runner.lane_snapshots.__setitem__(str(label), {})
        return runner

    def push_lane(self, lane, files):
        g(self.dev, "fetch", "-q", "origin")
        g(self.dev, "checkout", "-q", "-B", lane.replace("/", "_"), f"origin/{BASE}")
        for rel, text in files.items():
            (self.dev / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.dev / rel).write_text(text)
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", f"work on {lane}")
        g(self.dev, "push", "-q", "-f", "origin", f"HEAD:refs/heads/{lane}")
        return g(self.dev, "rev-parse", "HEAD")

    def origin_base(self):
        return g(self.origin, "rev-parse", BASE)

    def session(self, runner, lanes, task="R-70", verdict="pass", on_session=None):
        """Replace the launch: the reviewer (agent override) writes a verdict; the session writes its status."""
        def launch(key, tree, prompt, log):
            self.launches.append((runner.agent_override, key, Path(tree), prompt))
            if runner.agent_override == "reviewer":
                sha = re.search(r"commit `([0-9a-f]{40})`", prompt).group(1)
                if verdict:
                    body = "Looks fine.\n\n```json\n" + json.dumps(
                        {"verdict": verdict, "head": sha, "round": 1, "findings": []}) + "\n```"
                    log.parent.mkdir(parents=True, exist_ok=True)
                    with open(log, "ab") as fh:
                        fh.write((json.dumps({"type": "result", "result": body}) + "\n").encode())
                return 0
            if on_session:
                on_session()
            status = {"state": "done", "summary": "x", "lanes": lanes}
            (Path(tree) / "build" / "retro").mkdir(parents=True, exist_ok=True)
            (Path(tree) / "build" / "retro" / f"{task}.status.json").write_text(json.dumps(status))
            self.paths.status_file(key).parent.mkdir(parents=True, exist_ok=True)
            self.paths.status_file(key).write_text(json.dumps(status))
            return 0

        runner.launch = launch

    def retro_runner(self, gh, lanes, **kw):
        runner = self.runner(gh, None)
        real = runner.run

        def run(args, **k):
            if "ls-remote" in args and "--exit-code" in args and args[-1] == BASE:
                return subprocess.CompletedProcess(args, 0, "", "")
            return real(args, **k)

        runner.run = run
        self.session(runner, lanes, **kw)
        dest = self.paths.root / "archive" / "request-70"
        (dest / "retro").mkdir(parents=True, exist_ok=True)
        (dest / "retro" / "R-70.json").write_text(json.dumps({"task": "R-70", "triggers": [{"id": "blocked"}]}))
        item = {"archive": str(dest), "task": "R-70", "triggers": ["blocked"], "touched": [], "queued": ht.iso()}
        state = ht.State(runner.retro_paths.state)
        state.data["queue"] = [item]
        state.save()
        return runner

    def removed(self):
        return [c for c in self.commands if "worktree" in c and "remove" in c and "retro-R-70" in c[-1]]

    def issues(self, gh):
        return [c for c in gh.calls if c[0] == "issue"]


class RetroLandingTests(LandBase):
    def test_the_runner_reviews_and_merges_a_pushed_lane(self):
        sha = self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        self.assertEqual(runner.run_retro(), "done")
        reviewer = [x for x in self.launches if x[0] == "reviewer"]
        self.assertEqual(len(reviewer), 1)
        _, key, tree, prompt = reviewer[0]
        self.assertEqual(tree, self.paths.root / "trusted" / self.cfg["product_repo"].split("/")[1])
        self.assertNotEqual(tree, self.land_dir)
        for part in ("agents/retro-r-70", sha, f"origin/{BASE}", str(self.paths.root / "reviews" / "diffs"), "```json"):
            self.assertIn(part, prompt)
        record = json.loads((self.paths.root / "reviews" / ("agents__retro-r-70-" + sha[:12] + ".json")).read_text())
        self.assertEqual((record["head"], record["recorded_by"]), (sha, "runner"))
        self.assertEqual(g(self.origin, "log", "-1", "--format=%P", BASE).split()[1], sha)
        self.assertIn("Release-Note: none", g(self.origin, "log", "-1", "--format=%B", BASE))
        self.assertEqual(self.issues(gh), [])
        self.assertEqual(len(self.removed()), 1)  # landed: the worktree goes
        self.assertEqual(runner.state.data["lanes"]["retro-R-70"], {"agents/retro-r-70": "merged"})
        self.assertIsNone(runner.agent_override)

    def test_a_pushed_lane_is_not_merged_by_the_agent_session_itself(self):
        # the session only pushes; the base on origin moves only when the runner lands
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        before = self.origin_base()
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"], on_session=lambda: self.assertEqual(self.origin_base(), before))
        runner.run_retro()
        self.assertNotEqual(self.origin_base(), before)

    def test_a_fixed_set_lane_is_filed_on_hold_and_not_merged(self):
        self.push_lane("agents/retro-r-70", {"tools/hass_creds.sh": "x\n"})
        before = self.origin_base()
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        runner.run_retro()
        self.assertEqual(self.origin_base(), before)
        [issue] = self.issues(gh)
        self.assertEqual(issue[1], self.cfg["request_repo"])
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn("tools/hass_creds.sh", issue[3])
        self.assertEqual([x for x in self.launches if x[0] == "reviewer"], [])  # refused before spending a review
        self.assertEqual(len(self.removed()), 1)  # filed counts as resolved

    def test_a_failed_review_is_filed_as_workflow_only(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        before = self.origin_base()
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"], verdict="major")
        runner.run_retro()
        self.assertEqual(self.origin_base(), before)
        [issue] = self.issues(gh)
        self.assertEqual(issue[4], ("Workflow",))
        self.assertIn("major", issue[3])

    def test_a_reviewer_that_writes_nothing_is_filed(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"], verdict=None)
        runner.run_retro()
        [issue] = self.issues(gh)
        self.assertIn("no fenced json verdict", issue[3])

    def test_failing_tests_and_conflicts_are_filed(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        self.cfg["land_tests"] = "false"
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        runner.run_retro()
        self.assertIn("tests failed", self.issues(gh)[0][3])
        # a conflict: the base moved under the lane in the same file
        self.cfg["land_tests"] = "true"
        self.push_lane("agents/retro-r-71", {"c.txt": "lane\n"})
        g(self.dev, "checkout", "-q", BASE)
        (self.dev / "c.txt").write_text("base\n")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "clash")
        g(self.dev, "push", "-q", "origin", BASE)
        before = self.origin_base()
        gh2 = FakeGitHub([])
        runner2 = self.retro_runner(gh2, ["agents/retro-r-71"])
        runner2.base_record().parent.mkdir(parents=True, exist_ok=True)  # the owner's own push is accepted (else the monitor pauses)
        runner2.base_record().write_text(json.dumps({BASE: self.origin_base()}))
        runner2.run_retro()
        self.assertEqual(self.origin_base(), before)
        self.assertIn("(conflict)", self.issues(gh2)[0][2])

    def test_an_identical_issue_is_not_filed_twice(self):
        self.push_lane("agents/retro-r-70", {"tools/lane_land.py": "x\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        runner.run_retro()
        runner.file_lane_issue("agents/retro-r-70", "retro-R-70", "again", "paths", True)
        self.assertEqual(len(self.issues(gh)), 1)

    def test_a_kill_switch_holds_the_lane_and_keeps_the_worktree(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        before = self.origin_base()
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        switch = self.paths.state_dir / "SELF_CHANGE_PAUSED"

        def pause():
            switch.parent.mkdir(parents=True, exist_ok=True)
            switch.write_text("x")

        self.session(runner, ["agents/retro-r-70"], on_session=pause)
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.run_retro()
        self.assertEqual(self.origin_base(), before)
        self.assertEqual(self.issues(gh), [])
        self.assertEqual(self.removed(), [])
        self.assertEqual([x for x in self.launches if x[0] == "reviewer"], [])

    def test_a_lane_not_on_origin_or_not_an_agents_branch_is_filed(self):
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/never-pushed", "claude/uikit-port", "main", 7])
        runner.run_retro()
        titles = [i[2] for i in self.issues(gh)]
        self.assertEqual(len(titles), 3)
        self.assertTrue(any("agents/never-pushed" in x for x in titles))
        self.assertTrue(all(("lane)" in x) for x in titles))

    def test_no_lanes_means_no_landing_and_the_old_unpushed_check(self):
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, [])
        runner.run_retro()
        self.assertEqual([x for x in self.launches if x[0] == "reviewer"], [])
        self.assertEqual(self.issues(gh), [])

    def test_the_runner_env_never_carries_the_headless_flag(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "1"}):
            runner.run_retro()
        self.assertEqual(self.issues(gh)[0][2].split("(")[1], "headless)")  # landing from a headless env is refused


class TrustedReviewerTests(LandBase):
    def test_the_reviewer_runs_in_a_clean_base_checkout_not_the_lane(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "lane-only\n", "tools/release/versioning.py": "x\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        seen = {}
        inner = runner.launch

        def launch(key, tree, prompt, log):
            if runner.agent_override == "reviewer":
                seen["x"] = 1
            return inner(key, tree, prompt, log)

        runner.launch = launch
        runner.run_retro()
        # a lane that adds a settings file is a fixed-set change and never reaches a review
        self.assertEqual(seen, {})
        self.assertEqual(self.issues(gh)[0][4], ("Workflow", "On Hold"))

    def test_the_reviewer_checkout_is_the_base_with_the_lane_only_as_objects(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "lane-only\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        trusted = runner.trusted_clone(BASE)
        (trusted / ".claude").mkdir(exist_ok=True)
        (trusted / ".claude" / "settings.local.json").write_text('{"hooks": "planted"}')
        (trusted / "planted.sh").write_text("x")
        (trusted / ".git" / "hooks" / "post-checkout").write_text("#!/bin/sh\n")
        seen = {}
        inner = runner.launch

        def launch(key, tree, prompt, log):
            if runner.agent_override == "reviewer":
                seen.update(local=(Path(tree) / ".claude" / "settings.local.json").exists(),
                            planted=(Path(tree) / "planted.sh").exists(), lane=(Path(tree) / "b.txt").exists(),
                            hook=(Path(tree) / ".git" / "hooks" / "post-checkout").exists(),
                            head=g(tree, "rev-parse", "HEAD"), dirs=list(runner.extra_dirs))
            return inner(key, tree, prompt, log)

        runner.launch = launch
        runner.run_retro()
        self.assertEqual((seen["local"], seen["planted"], seen["lane"], seen["hook"]), (False, False, False, False))
        self.assertEqual(seen["head"], g(self.origin, "rev-parse", f"{BASE}~1"))  # the base it reviewed, not the lane
        self.assertEqual(seen["dirs"], [self.paths.root / "reviews" / "diffs"])

    def test_the_verdict_comes_from_the_final_message_only(self):
        sha = self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"], verdict=None)
        inner = runner.launch
        planted = self.paths.root / "reviews" / ("agents__retro-r-70-" + sha[:12] + ".json")

        def launch(key, tree, prompt, log):
            if runner.agent_override == "reviewer":  # a file at the record path is not a verdict
                planted.parent.mkdir(parents=True, exist_ok=True)
                planted.write_text(json.dumps({"verdict": "pass", "head": sha, "round": 1}))
            return inner(key, tree, prompt, log)

        runner.launch = launch
        before = self.origin_base()
        runner.run_retro()
        self.assertEqual(self.origin_base(), before)
        self.assertIn("no fenced json verdict", self.issues(gh)[0][3])


class ProcessGroupTests(LandBase):
    def script(self, body):
        path = self.tmp / "fake-claude"
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)
        return str(path)

    def test_a_grandchild_the_session_leaves_behind_is_killed_before_landing(self):
        pidfile = self.tmp / "grandchild.pid"
        self.cfg["agent"]["command"] = self.script(f"cat > /dev/null\n(nohup sleep 300 >/dev/null 2>&1 & echo $! > {pidfile})\nexit 0\n")
        runner = ht.Runner(self.cfg, self.paths, FakeGitHub([]), run=mock.Mock())
        runner.state.data["current"] = {"issue": 1}
        with mock.patch.object(ht.lane_land, "reap_group", REAL_REAP):
            code = runner._launch(1, self.tmp, "prompt", self.paths.log(1, 1))
        self.assertEqual(code, 0)
        pid = int(pidfile.read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        self.assertFalse(runner.stray)

    def test_survivors_block_landing_and_the_reviewer(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        before = self.origin_base()
        runner = self.retro_runner(FakeGitHub([]), ["agents/retro-r-70"])
        inner = runner.launch

        def launch(key, tree, prompt, log):
            code = inner(key, tree, prompt, log)
            runner.stray = True  # what _launch records when the group would not die
            return code

        runner.launch = launch
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.run_retro()
        self.assertEqual(self.origin_base(), before)
        self.assertEqual([x for x in self.launches if x[0] == "reviewer"], [])
        self.assertEqual(self.removed(), [])  # the lane is unresolved: the worktree stays

    def test_a_reviewer_with_survivors_is_filed_on_hold(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        inner = runner.launch

        def launch(key, tree, prompt, log):
            code = inner(key, tree, prompt, log)
            if runner.agent_override == "reviewer":
                runner.stray = True
            return code

        runner.launch = launch
        runner.run_retro()
        [issue] = self.issues(gh)
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn("(processes)", issue[2])


class BaseIntegrityTests(LandBase):
    def owner_push(self, name="owner.txt"):
        g(self.dev, "checkout", "-q", BASE)
        g(self.dev, "pull", "-q", "origin", BASE)
        (self.dev / name).write_text("o\n")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "owner push")
        g(self.dev, "push", "-q", "origin", BASE)
        return g(self.dev, "rev-parse", "HEAD")

    def runner_with_clone(self, gh):
        runner = self.runner(gh, None)
        return runner

    def test_first_sight_records_and_an_unchanged_base_is_quiet(self):
        gh = FakeGitHub([])
        runner = self.runner_with_clone(gh)
        self.assertTrue(runner.check_base("tick"))
        self.assertEqual(json.loads(runner.base_record().read_text()), {BASE: self.origin_base()})
        self.assertTrue(runner.check_base("tick"))
        self.assertEqual(self.issues(gh), [])

    def test_a_move_the_runner_did_not_make_pauses_and_files_an_issue_once(self):
        gh = FakeGitHub([])
        runner = self.runner_with_clone(gh)
        runner.check_base("tick")
        sha = self.owner_push()
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertFalse(runner.check_base("tick"))
            self.assertFalse(runner.check_base("tick"))
        switch = self.paths.state_dir / "SELF_CHANGE_PAUSED"
        self.assertIn(sha, switch.read_text())
        [issue] = self.issues(gh)
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn(sha[:10], issue[2])
        self.assertIn("committer: t <t@t>", issue[3])
        self.assertIn("owner.txt", issue[3])
        self.assertEqual(self.origin_base(), sha)  # nothing is reset or force-pushed

    def test_a_paused_base_stops_landing_until_the_owner_acks(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        runner.check_base("tick")
        sha = self.owner_push()
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.run_retro()
        self.assertEqual(self.origin_base(), sha)
        self.assertEqual([x for x in self.launches if x[0] == "reviewer"], [])
        self.assertEqual(runner.ack_base(sha), sha)
        self.assertFalse((self.paths.state_dir / "SELF_CHANGE_PAUSED").exists())
        self.assertTrue(runner.check_base("tick"))

    def test_ack_base_needs_a_pending_pause_and_the_exact_sha(self):
        runner = self.runner_with_clone(FakeGitHub([]))
        runner.check_base("tick")
        with self.assertRaises(ht.TriageError):  # nothing pending
            runner.ack_base(self.origin_base())
        sha = self.owner_push()
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.check_base("tick")
        for wrong in ("", sha[:10], "0" * 40):
            with self.assertRaises(ht.TriageError):
                runner.ack_base(wrong)
        self.assertTrue((self.paths.state_dir / "SELF_CHANGE_PAUSED").exists())
        self.assertEqual(runner.ack_base(sha), sha)

    def test_the_pause_text_and_issue_tell_the_owner_not_agents(self):
        gh = FakeGitHub([])
        runner = self.runner_with_clone(gh)
        runner.check_base("tick")
        sha = self.owner_push()
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.check_base("tick")
        text = (self.paths.state_dir / "SELF_CHANGE_PAUSED").read_text()
        self.assertIn(f"ack-base {sha}", text)
        self.assertIn("Owner only", text)
        self.assertIn("agents never run this", text)

    def test_ack_base_cli_refuses_headless_and_non_tty(self):
        argv = ["ack-base", "0" * 40]
        for env, tty in (({"FENTON_HEADLESS": "1"}, True), ({"HASS_TRIAGE_ISSUE": "9"}, True), ({}, False)):
            with self.subTest(env=env, tty=tty), mock.patch.dict(os.environ, env), \
                    mock.patch("sys.stdin") as stdin, mock.patch("sys.stderr", new=io.StringIO()) as err, \
                    mock.patch.object(ht.Runner, "ack_base") as ack:
                stdin.isatty.return_value = tty
                code = ht.main(argv, home=self.home)
                self.assertEqual(code, 2)
                ack.assert_not_called()
                self.assertIn("owner-only", err.getvalue())

    def test_the_base_moving_during_the_review_is_merged_over_once(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        gh = FakeGitHub([])
        moved = {}
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        inner = runner.launch

        def launch(key, tree, prompt, log):
            code = inner(key, tree, prompt, log)
            if runner.agent_override == "reviewer":
                moved["sha"] = self.owner_push("mid.txt")  # a push to the base while the reviewer works
            return code

        runner.launch = launch
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.run_retro()
        # owner decision 2026-11-04: one move is re-fetched, re-checked for a clean merge, retested and landed on
        self.assertEqual(g(self.origin, "rev-parse", f"{BASE}^1"), moved["sha"])
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "1")
        # the lane landed, but the merge sits on a base the runner never recorded (the owner's push): the runner's own guard
        # still pauses further landings and files the Workflow + On Hold issue until the owner runs ack-base
        self.assertTrue((self.paths.state_dir / "SELF_CHANGE_PAUSED").exists())
        [issue] = self.issues(gh)
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn(moved["sha"][:10], issue[2])

    def test_a_second_base_move_lands_nothing_and_pauses(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        script = self.tmp / "moves.sh"
        script.write_text(f"#!/bin/sh\ncd {self.dev} && git checkout -q {BASE} && git pull -q origin {BASE} && echo $$ > t$$.txt "
                          f"&& git add -A && git commit -qm during-tests && git push -q origin {BASE}\nexit 0\n")
        script.chmod(0o755)
        self.cfg["land_tests"] = f"sh {script}"
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, ["agents/retro-r-70"])
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.run_retro()
        self.assertEqual(g(self.origin, "log", "-1", "--format=%s", BASE), "during-tests")
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "0")
        self.assertTrue((self.paths.state_dir / "SELF_CHANGE_PAUSED").exists())
        [issue] = self.issues(gh)
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn(self.origin_base()[:10], issue[2])

    def test_a_landing_updates_the_record(self):
        self.push_lane("agents/retro-r-70", {"b.txt": "b\n"})
        runner = self.retro_runner(FakeGitHub([]), ["agents/retro-r-70"])
        runner.run_retro()
        self.assertEqual(json.loads(runner.base_record().read_text()), {BASE: self.origin_base()})
        self.assertTrue(runner.check_base("tick"))

    def test_a_push_between_the_land_and_the_check_is_caught(self):
        gh = FakeGitHub([])
        runner = self.runner_with_clone(gh)
        runner.check_base("tick")
        sha = self.owner_push()
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertFalse(runner.check_base("after landing", landed="0" * 40))
        self.assertTrue((self.paths.state_dir / "SELF_CHANGE_PAUSED").exists())
        self.assertIn(sha[:10], self.issues(gh)[0][2])

    def test_the_tick_checks_the_base(self):
        runner = self.runner(FakeGitHub([]), None)
        with mock.patch.object(runner, "check_base") as check, mock.patch.object(runner, "refresh_clone"):
            runner.tick()
        check.assert_called_with("tick")


class WorkflowIssueLaneTests(LandBase):
    def test_a_workflow_issue_lane_is_landed_by_the_runner_and_the_issue_closes(self):
        self.push_lane("agents/fix-261102", {"w.txt": "w\n"})
        gh = FakeGitHub([t.issue(9, labels=["Workflow"])])
        status = {"state": "done", "summary": "fixed the loop", "lanes": ["agents/fix-261102"]}
        runner = self.runner(gh, status)
        inner = runner.launch

        def launch(n, tree, prompt, log):
            if runner.agent_override == "reviewer":
                sha = re.search(r"commit `([0-9a-f]{40})`", prompt).group(1)
                body = "```json\n" + json.dumps({"verdict": "pass", "head": sha, "round": 1, "findings": []}) + "\n```"
                log.parent.mkdir(parents=True, exist_ok=True)
                log.write_text(json.dumps({"type": "result", "result": body}) + "\n")
                return 0
            return inner(n, tree, prompt, log)

        runner.launch = launch
        self.assertEqual(runner.work(9), "done")
        self.assertEqual(g(self.origin, "show", f"{BASE}:w.txt"), "w")
        self.assertIn("Done", ht.label_names(gh.issues[9]))
        self.assertEqual(runner.state.data["lanes"]["9"], {"agents/fix-261102": "merged"})

    def lane_issue(self, status, labels=("Workflow",)):
        self.push_lane("agents/fix-261102", {"w.txt": "w\n"})
        gh = FakeGitHub([t.issue(9, labels=list(labels))])
        runner = self.runner(gh, status)
        inner = runner.launch

        def launch(n, tree, prompt, log):
            if runner.agent_override == "reviewer":
                sha = re.search(r"commit `([0-9a-f]{40})`", prompt).group(1)
                body = "```json\n" + json.dumps({"verdict": "pass", "head": sha, "round": 1, "findings": []}) + "\n```"
                log.parent.mkdir(parents=True, exist_ok=True)
                log.write_text(json.dumps({"type": "result", "result": body}) + "\n")
                return 0
            return inner(n, tree, prompt, log)

        runner.launch = launch
        return gh, runner

    def test_needs_decision_with_lanes_lands_them_and_keeps_the_issue_open(self):
        status = {"state": "needs_decision", "summary": "part one is done", "lanes": ["agents/fix-261102"],
                  "decision": {"question": "Which colour?", "options": [{"key": "A", "summary": "red"}], "recommendation": "A"}}
        gh, runner = self.lane_issue(status)
        self.assertEqual(runner.work(9), "needs_decision")
        self.assertEqual(g(self.origin, "show", f"{BASE}:w.txt"), "w")
        labels = ht.label_names(gh.issues[9])
        self.assertIn("Needs Decision", labels)
        self.assertNotIn("Done", labels)
        self.assertFalse([c for c in gh.calls if c[0] == "close"])
        text = json.dumps(gh.calls)
        self.assertIn("Which colour?", text)
        self.assertIn("agents/fix-261102", text)

    def test_blocked_with_lanes_is_labelled_blocked_and_not_closed(self):
        status = {"state": "blocked", "summary": "stuck", "blocked_reason": "needs a key", "lanes": ["agents/fix-261102"]}
        gh, runner = self.lane_issue(status)
        self.assertEqual(runner.work(9), "blocked")
        labels = ht.label_names(gh.issues[9])
        self.assertIn("Blocked", labels)
        self.assertNotIn("Done", labels)
        self.assertIn("agents/fix-261102", json.dumps(gh.calls))
        self.assertFalse([c for c in gh.calls if c[0] == "close"])

    def test_done_with_a_filed_lane_stays_open(self):
        self.push_lane("agents/fix-261102", {"tools/hass_creds.sh": "x\n"})  # fixed set: filed, not merged
        gh = FakeGitHub([t.issue(9, labels=["Workflow"])])
        runner = self.runner(gh, {"state": "done", "summary": "s", "lanes": ["agents/fix-261102"]})
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(runner.work(9), "blocked")
        labels = ht.label_names(gh.issues[9])
        self.assertIn("Blocked", labels)
        self.assertNotIn("Done", labels)
        self.assertIn("filed", json.dumps(gh.calls))

    def test_an_unlanded_lane_blocks_the_issue_and_keeps_the_worktree(self):
        self.push_lane("agents/fix-261102", {"w.txt": "w\n"})
        switch = self.paths.config_dir / "PAUSED"
        switch.parent.mkdir(parents=True, exist_ok=True)
        switch.write_text("x")
        gh = FakeGitHub([t.issue(9, labels=["Workflow"])])
        runner = self.runner(gh, {"state": "done", "summary": "s", "lanes": ["agents/fix-261102"]})
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(runner.work(9), "blocked")
        removes = [c for c in self.commands if "worktree" in c and "remove" in c]
        self.assertEqual(removes, [])
        self.assertIn(9, runner._keep)

    def test_an_ordinary_issue_does_not_land_lanes(self):
        self.push_lane("agents/fix-261102", {"w.txt": "w\n"})
        before = self.origin_base()
        gh = FakeGitHub([t.issue(9, labels=["Bug"])])
        runner = self.runner(gh, {"state": "no_changes", "summary": "s", "lanes": ["agents/fix-261102"]})
        runner.work(9)
        self.assertEqual(self.origin_base(), before)

    def test_lanes_past_the_limit_are_filed(self):
        gh = FakeGitHub([])
        lanes = [f"agents/l{i}" for i in range(ht.LANE_LIMIT + 1)]
        runner = self.runner(gh, None)
        with mock.patch.object(runner, "land_lane", return_value="merged"), \
                mock.patch.object(runner, "session_lanes", side_effect=lambda raw, label: raw):
            runner.land_lanes({"lanes": lanes}, "x")
        [issue] = self.issues(gh)
        self.assertIn("(limit)", issue[2])
        self.assertIn(lanes[-1], issue[3])


class LaunchTests(LandBase):
    def test_the_reviewer_launch_uses_the_reviewer_agent_and_headless_env(self):
        runner = ht.Runner(self.cfg, self.paths, FakeGitHub([]), run=mock.Mock())
        runner.state.data["current"] = {"issue": 0}
        captured = {}

        class Proc:
            pid = 4242
            stdin = io.BytesIO()

            def wait(self, timeout=None):
                return 0

        def popen(argv, **kw):
            captured.update(argv=argv, env=kw["env"], cwd=kw["cwd"])
            proc = Proc()
            proc.stdin = mock.Mock()
            return proc

        runner.agent_override = "reviewer"
        with mock.patch.object(ht.subprocess, "Popen", popen), mock.patch.object(ht.shutil, "which", return_value=None):
            runner._launch("review-abc", self.land_dir, "prompt", self.paths.log("review-abc", 1))
        argv = captured["argv"]
        self.assertEqual(argv[argv.index("--agent") + 1], "reviewer")
        self.assertEqual(captured["env"]["FENTON_HEADLESS"], "1")
        self.assertEqual(captured["cwd"], str(self.land_dir))
        runner.agent_override = None
        with mock.patch.object(ht.subprocess, "Popen", popen), mock.patch.object(ht.shutil, "which", return_value=None):
            runner._launch("x", self.land_dir, "prompt", self.paths.log("x", 1))
        self.assertEqual(captured["argv"][captured["argv"].index("--agent") + 1], self.cfg["agent"]["agent"])

    def test_create_issue_builds_the_gh_call_and_makes_labels(self):
        gh = ht.GitHub(labels=ht.label_table(self.cfg))
        calls = []
        gh._write = lambda args, text=None: calls.append((args, text)) or "{}"
        gh.create_issue("o/r", "T", "body", ["Workflow", "On Hold"])
        self.assertEqual([c[0][:3] for c in calls[:2]], [["label", "create", "Workflow"], ["label", "create", "On Hold"]])
        args, text = calls[-1]
        self.assertEqual(args[:6], ["issue", "create", "-R", "o/r", "--title", "T"])
        self.assertEqual([args[i + 1] for i, a in enumerate(args) if a == "--label"], ["Workflow", "On Hold"])
        self.assertEqual(text, "body")


class JobLandingTests(LandBase):
    def job_runner(self, gh, lanes, workflow_on_origin=True):
        runner = self.runner(gh, None)
        real = runner.run

        def run(args, **k):
            if "ls-remote" in args and "--heads" in args and args[-1] == BASE:
                return subprocess.CompletedProcess(args, 0 if workflow_on_origin else 2, "", "")
            return real(args, **k)

        runner.run = run
        self.session(runner, lanes, task="job-steward")
        orig = runner.launch

        def launch(key, tree, prompt, log):
            code = orig(key, tree, prompt, log)
            if runner.agent_override != "reviewer":
                self.paths.status_file(key).parent.mkdir(parents=True, exist_ok=True)
                self.paths.status_file(key).write_text(json.dumps({"state": "done", "summary": "w", "lanes": lanes}))
            return code

        runner.launch = launch
        return runner

    def test_the_steward_job_branches_from_the_workflow_base_when_it_exists(self):
        runner = self.job_runner(FakeGitHub([]), [])
        runner.run_job("steward")
        add = [c for c in self.commands if "worktree" in c and "add" in c][-1]
        self.assertEqual(add[-1], f"origin/{BASE}")
        self.commands.clear()
        runner = self.job_runner(FakeGitHub([]), [], workflow_on_origin=False)
        runner.run_job("researcher")
        add = [c for c in self.commands if "worktree" in c and "add" in c][-1]
        self.assertEqual(add[-1], f"origin/{self.cfg['product_base']}")

    def test_a_job_lane_is_landed_by_the_runner(self):
        self.push_lane("agents/steward-261102", {"s.txt": "s\n"})
        gh = FakeGitHub([])
        runner = self.job_runner(gh, ["agents/steward-261102"])
        self.assertEqual(runner.run_job("steward"), "done")
        self.assertEqual(g(self.origin, "show", f"{BASE}:s.txt"), "s")
        self.assertEqual(runner.state.data["lanes"]["job-steward"], {"agents/steward-261102": "merged"})

    def test_a_job_worktree_stays_when_the_kill_switch_holds_a_lane(self):
        self.push_lane("agents/steward-261102", {"s.txt": "s\n"})
        switch = self.paths.config_dir / "PAUSED"
        switch.parent.mkdir(parents=True, exist_ok=True)
        switch.write_text("x")
        runner = self.job_runner(FakeGitHub([]), ["agents/steward-261102"])
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.run_job("steward")
        removes = [c for c in self.commands if "worktree" in c and "remove" in c and c[-1].endswith("job-steward")]
        self.assertEqual(removes, [])  # an unlanded lane keeps the worktree
        self.assertEqual(self.origin_base(), g(self.dev, "rev-parse", f"origin/{BASE}"))


if __name__ == "__main__":
    unittest.main()


class SnapshotTests(LandBase):
    """Lanes belong to the session: only an `agents/*` branch new or moved since the snapshot is landed."""

    real_snapshots = True

    def retro(self, lanes, before=None):
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, lanes, on_session=before)
        return gh, runner

    def test_a_lane_that_existed_before_and_did_not_move_is_filed_on_hold(self):
        self.push_lane("agents/old-work", {"b.txt": "b\n"})
        base = self.origin_base()
        gh, runner = self.retro(["agents/old-work"])
        runner.run_retro()
        self.assertEqual(self.origin_base(), base)
        [issue] = self.issues(gh)
        self.assertIn("(lane)", issue[2])
        self.assertIn("not pushed by this session", issue[3])
        self.assertEqual(sorted(issue[4]), ["On Hold", "Workflow"])
        self.assertEqual([x for x in self.launches if x[0] == "reviewer"], [])

    def test_a_lane_the_session_pushed_is_landed(self):
        gh, runner = self.retro(["agents/retro-r-70"],
                                before=lambda: self.push_lane("agents/retro-r-70", {"b.txt": "b\n"}))
        runner.run_retro()
        self.assertEqual(self.issues(gh), [])
        self.assertEqual(g(self.origin, "show", f"{BASE}:b.txt"), "b")

    def test_a_lane_that_moved_during_the_session_is_landed(self):
        self.push_lane("agents/retro-r-70", {"c.txt": "old\n"})
        gh, runner = self.retro(["agents/retro-r-70"],
                                before=lambda: self.push_lane("agents/retro-r-70", {"b.txt": "b\n"}))
        runner.run_retro()
        self.assertEqual(self.issues(gh), [])
        self.assertEqual(g(self.origin, "show", f"{BASE}:b.txt"), "b")

    def test_a_non_agents_branch_is_filed_even_if_new(self):
        gh, runner = self.retro(["claude/other"], before=lambda: self.push_lane("claude/other", {"b.txt": "b\n"}))
        base = self.origin_base()
        runner.run_retro()
        self.assertEqual(self.origin_base(), base)
        self.assertIn("(lane)", self.issues(gh)[0][2])


class PullGitHub(FakeGitHub):
    """``FakeGitHub`` that answers ``commit_pulls`` from a table (sha -> pull requests), counting the lookups; ``fail`` raises."""

    def __init__(self, *args, **kw):
        super().__init__(*args, **kw)
        self.commit_table = {}
        self.lookups = []
        self.fail = False

    def commit_pulls(self, repo, sha):
        self.lookups.append(sha)
        if self.fail:
            raise ht.TriageError("gh api failed")
        return self.commit_table.get(sha, [])


def merged_pr(sha, base="main", merged_at="2026-11-05T10:00:00Z", merge_sha=None):
    return {"number": 9, "merged_at": merged_at, "base": {"ref": base}, "merge_commit_sha": merge_sha or sha}


class SharedBaseTests(LandBase):
    """``workflow_base`` equal to ``product_base`` (``main``, owner 2026-11-05): merged pull requests move it legitimately."""

    def setUp(self):
        super().setUp()
        g(self.dev, "push", "-q", "origin", f"{BASE}:main")
        self.cfg["workflow_base"] = self.cfg["product_base"] = "main"
        self.gh = PullGitHub([])
        self.runner_ = self.runner(self.gh, None)
        self.assertTrue(self.runner_.check_base("tick"))  # first sight records main

    def push_main(self, name):
        g(self.dev, "fetch", "-q", "origin")
        g(self.dev, "checkout", "-q", "-B", "tmp_main", "origin/main")
        (self.dev / name).write_text(name)
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", f"change {name}")
        g(self.dev, "push", "-q", "origin", "HEAD:main")
        return g(self.dev, "rev-parse", "HEAD")

    def check(self):
        with mock.patch("sys.stdout", new=io.StringIO()):
            return self.runner_.check_base("tick")

    def paused(self):
        return (self.paths.state_dir / "SELF_CHANGE_PAUSED").exists()

    def test_a_merged_pull_request_move_is_accepted_without_a_pause(self):
        sha = self.push_main("one")
        self.gh.commit_table[sha] = [merged_pr(sha)]
        self.assertTrue(self.check())
        self.assertFalse(self.paused())
        self.assertEqual(self.issues(self.gh), [])
        self.assertEqual(json.loads(self.runner_.base_record().read_text()), {"main": sha})
        self.assertTrue(self.check())  # recorded: the next tick is quiet and asks nothing
        self.assertEqual(self.gh.lookups, [sha])

    def test_several_merged_pull_requests_between_ticks_are_accepted(self):
        shas = [self.push_main(f"f{n}") for n in range(3)]
        for sha in shas:
            self.gh.commit_table[sha] = [merged_pr(sha)]
        self.assertTrue(self.check())
        self.assertEqual(sorted(self.gh.lookups), sorted(shas))

    def test_a_direct_push_mixed_with_pull_requests_pauses(self):
        first = self.push_main("one")
        direct = self.push_main("two")
        self.gh.commit_table[first] = [merged_pr(first)]
        self.assertFalse(self.check())
        self.assertTrue(self.paused())
        [issue] = self.issues(self.gh)
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn(direct[:10], issue[2])

    def test_a_force_push_that_is_not_a_descendant_pauses_even_with_a_merged_pull_request(self):
        first = self.push_main("one")
        self.gh.commit_table[first] = [merged_pr(first)]
        self.assertTrue(self.check())
        g(self.dev, "checkout", "-q", "-B", "forked", f"{first}~1")
        (self.dev / "forked").write_text("x")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "forked")
        g(self.dev, "push", "-q", "--force", "origin", "HEAD:main")
        forced = g(self.dev, "rev-parse", "HEAD")
        self.gh.commit_table[forced] = [merged_pr(forced)]
        self.assertFalse(self.check())
        self.assertTrue(self.paused())

    def test_a_failed_lookup_is_retried_once_then_pauses(self):
        sha = self.push_main("one")
        self.gh.commit_table[sha] = [merged_pr(sha)]
        self.gh.fail = True
        self.assertFalse(self.check())
        self.assertTrue(self.paused())
        self.assertEqual(self.gh.lookups, [sha, sha])

    def test_a_lookup_that_fails_once_then_answers_is_accepted(self):
        sha = self.push_main("one")
        answers = iter([ht.TriageError("blip"), [merged_pr(sha)]])

        def flaky(repo, s):
            item = next(answers)
            if isinstance(item, Exception):
                raise item
            return item

        self.gh.commit_pulls = flaky
        self.assertTrue(self.check())

    def test_a_pull_request_that_is_not_merged_into_this_base_commit_pauses(self):
        sha = self.push_main("one")
        for pulls in ([merged_pr(sha, merged_at=None)], [merged_pr(sha, base="release")], [merged_pr(sha, merge_sha="0" * 40)], [], [None]):
            self.gh.commit_table[sha] = pulls
            self.assertFalse(self.check(), pulls)
            self.assertTrue(self.paused())

    def test_a_walk_over_the_cap_pauses(self):
        shas = [self.push_main(f"f{n}") for n in range(2)]
        for sha in shas:
            self.gh.commit_table[sha] = [merged_pr(sha)]
        with mock.patch.object(ht, "BASE_WALK_CAP", 1):
            self.assertFalse(self.check())
        self.assertTrue(self.paused())

    def test_the_runners_own_landing_is_unchanged(self):
        sha = self.push_main("one")
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertTrue(self.runner_.check_base("after landing", landed=sha))
        self.assertEqual(self.gh.lookups, [])

    def test_a_separate_workflow_base_never_trusts_pull_requests(self):
        self.cfg["workflow_base"] = BASE
        runner = self.runner(self.gh, None)
        self.assertTrue(runner.check_base("tick"))
        g(self.dev, "checkout", "-q", "-B", "tmp_wf", f"origin/{BASE}")
        (self.dev / "w").write_text("w")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "w")
        g(self.dev, "push", "-q", "origin", f"HEAD:{BASE}")
        sha = g(self.dev, "rev-parse", "HEAD")
        self.gh.commit_table[sha] = [merged_pr(sha, base=BASE)]
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertFalse(runner.check_base("tick"))
        self.assertEqual(self.gh.lookups, [])

    def test_a_pull_request_merged_during_a_lane_review_lands_the_lane_without_a_pause(self):
        parent = []

        def land(lane, base, **kw):
            parent.append(self.push_main("pr-during-review"))
            self.gh.commit_table[parent[0]] = [merged_pr(parent[0])]
            merge = self.push_main("lane-merge")
            return {"merge": merge, "parent": parent[0]}

        with mock.patch.object(ht.lane_land, "land", land), mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(self.runner_.land_lane("agents/x", "main", "lbl"), "merged")
        self.assertFalse(self.paused())
        self.assertEqual(self.issues(self.gh), [])
        self.assertEqual(json.loads(self.runner_.base_record().read_text())["main"], g(self.dev, "rev-parse", "origin/main"))

    def test_a_non_pull_request_parent_after_landing_still_pauses(self):
        def land(lane, base, **kw):
            parent = self.push_main("direct")
            return {"merge": self.push_main("lane-merge"), "parent": parent}

        with mock.patch.object(ht.lane_land, "land", land), mock.patch("sys.stdout", new=io.StringIO()):
            self.runner_.land_lane("agents/x", "main", "lbl")
        self.assertTrue(self.paused())

    def test_a_lane_refused_because_pull_requests_moved_the_base_is_filed_not_forgotten(self):
        def land(lane, base, **kw):
            for n in ("one", "two"):
                sha = self.push_main(n)
                self.gh.commit_table[sha] = [merged_pr(sha)]
            raise ht.lane_land.Refused("origin/main moved during the tests: not landing", "base")

        with mock.patch.object(ht.lane_land, "land", land), mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(self.runner_.land_lane("agents/x", "main", "lbl"), "filed")
        self.assertFalse(self.paused())
        [issue] = self.issues(self.gh)
        self.assertIn("agents/x not landed (base)", str(issue))
        self.assertEqual(issue[4], ("Workflow",))
