"""Phase 4, closing the loop: the automatic revert on regression, the kill switch in `status`, the ack-base hardening and the
missing-base issue. Real git in temp repos with a local bare origin; the sessions and the reviewer are fake launches."""
from __future__ import annotations

import io
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import test_hass_triage as t  # noqa: E402
import test_retro_p3 as p3  # noqa: E402

ht = t.ht
BASE = p3.BASE
g = p3.g
FakeGitHub = t.FakeGitHub
LANE = "agents/retro-r-70"


def view(**kw):
    base = {"corrections_per_task": 0.0, "nudged_flows_rate": 0.0, "routing_overrides_rate": 0.0, "tokens_per_task": 100.0,
            "review_findings_per_pr": 1.0, "owner_rule_repeats_rate": 0.0}
    base.update(kw)
    return base


class RevertBase(p3.LandBase):
    T0 = datetime.now(timezone.utc) - timedelta(days=30)

    def landed_runner(self, gh=None, **cfg):
        """The runner after it landed one lane through the normal path; the landing record is moved to ``T0``."""
        self.cfg.update(cfg)
        self.push_lane(LANE, {"b.txt": "b\n"})
        gh = gh or FakeGitHub([])
        runner = self.retro_runner(gh, [LANE])
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.run_retro()
        (self.paths.root / "archive" / "request-70" / "retro" / "R-70.json").unlink()  # the fixture's own flow is not a metric input
        [landing] = runner.load_landings()
        self.merge_sha = landing["merge_sha"]
        landing["landed_at"] = ht.iso(self.T0)
        landing["metrics_before"] = {"flows": 10, "metrics": view()}
        runner.save_landings([landing])
        self.gh = gh
        return runner

    def flows(self, count, days_after=1, triggers=(), tokens=100, replies=1, start=0):
        for i in range(count):
            task = f"X-{start + i}"
            data = {"task": task, "triggers": [{"id": x, "evidence": ["e"]} for x in triggers],
                    "counts": {"owner_replies": replies if triggers else 0}, "cost": {"tokens": tokens}}
            path = self.paths.root / "archive" / f"request-{task}" / "retro" / f"{task}.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data))
            stamp = (self.T0 + timedelta(days=days_after, minutes=start + i)).timestamp()
            os.utime(path, (stamp, stamp))

    def check(self, runner):
        with mock.patch("sys.stdout", new=io.StringIO()):
            return runner.check_regressions()

    def reviewers(self):
        return [x for x in self.launches if x[0] == "reviewer"]


class RecordTests(RevertBase):
    def test_a_landing_records_lane_sha_time_and_the_metrics_of_the_flows_before(self):
        self.push_lane(LANE, {"b.txt": "b\n"})
        old = self.paths.root / "archive" / "request-1" / "retro" / "R-1.json"
        old.parent.mkdir(parents=True)
        old.write_text(json.dumps({"task": "R-1", "triggers": [{"id": "owner_correction", "evidence": ["e"]}],
                                   "counts": {"owner_replies": 2}, "cost": {"tokens": 500}}))
        stamp = (datetime.now(timezone.utc) - timedelta(days=1)).timestamp()
        os.utime(old, (stamp, stamp))
        runner = self.retro_runner(FakeGitHub([]), [LANE])
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.run_retro()
        [landing] = runner.load_landings()
        self.assertEqual((landing["lane"], landing["merge_sha"], landing["base"]), (LANE, self.origin_base(), BASE))
        self.assertTrue(landing["landed_at"])
        self.assertEqual(landing["metrics_before"]["flows"], 2)  # R-1 and the fixture's own R-70 digest
        self.assertEqual(landing["metrics_before"]["metrics"]["corrections_per_task"], 1.0)  # 2 replies over 2 flows
        self.assertEqual(landing["metrics_before"]["metrics"]["nudged_flows_rate"], 0.5)
        self.assertEqual(landing["metrics_before"]["metrics"]["tokens_per_task"], 500.0)
        self.assertIsNone(landing["evaluated"])

    def test_a_refused_lane_records_nothing(self):
        self.push_lane(LANE, {"b.txt": "b\n"})
        runner = self.retro_runner(FakeGitHub([]), [LANE], verdict="changes")
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.run_retro()
        self.assertEqual(runner.load_landings(), [])


class RevertTests(RevertBase):
    def test_two_worse_metrics_revert_through_the_normal_path_and_file_an_issue(self):
        runner = self.landed_runner()
        self.flows(10, triggers=("owner_correction",), tokens=300)
        before = self.origin_base()
        reviewed = len(self.reviewers())
        self.assertTrue(self.check(runner))
        self.assertEqual(len(self.reviewers()), reviewed + 1)  # independent review, as for any lane
        revert = f"agents/revert-{self.merge_sha[:12]}"
        self.assertEqual(g(self.origin, "branch", "--list", revert), "")  # landed, so the reaper deleted the lane branch
        files = g(self.origin, "ls-tree", "-r", "--name-only", BASE).split()
        self.assertNotIn("b.txt", files)  # reverted
        self.assertEqual(g(self.origin, "merge-base", "--is-ancestor", before, BASE) or "ok", "ok")  # history kept, no force push
        self.assertEqual(g(self.origin, "log", "-1", "--format=%P", BASE).split()[0], before)
        self.assertIn("Revert", g(self.origin, "log", "--format=%s%n%b", "-n", "3", BASE))
        [issue] = [c for c in self.gh.calls if c[0] == "issue"]
        self.assertEqual(issue[4], ("Workflow",))
        for needle in ("corrections_per_task", "tokens_per_task", self.merge_sha[:12], LANE):
            self.assertIn(needle, issue[3])
        landings = runner.load_landings()
        self.assertEqual([x["evaluated"] for x in landings if x["lane"] == LANE], ["reverted"])
        self.assertTrue(any(x.get("reverts") == self.merge_sha for x in landings))  # the revert is itself recorded
        self.assertFalse(self.check(runner))  # nothing left to judge

    def test_one_worse_metric_or_within_the_margin_holds(self):
        runner = self.landed_runner()
        self.flows(10, tokens=105)
        self.assertFalse(self.check(runner))
        self.assertEqual(runner.load_landings()[0]["evaluated"], "held")
        self.assertEqual(self.reviewers(), self.reviewers())
        self.assertEqual([c for c in self.gh.calls if c[0] == "issue"], [])

    def test_the_margin_comes_from_the_config(self):
        for margin, reverted in ((0.5, False), (0.2, True)):
            with self.subTest(margin=margin):
                runner = self.landed_runner(revert_margin=margin)
                [landing] = runner.load_landings()
                landing["metrics_before"] = {"flows": 10, "metrics": view(corrections_per_task=0.8, nudged_flows_rate=0.8)}
                runner.save_landings([landing])
                self.flows(10, triggers=("owner_correction",), tokens=100)  # corrections and nudges 1.0: +25%
                self.assertEqual(self.check(runner), reverted)
                self.assertEqual(runner.load_landings()[0]["evaluated"], "reverted" if reverted else "held")
                self.tearDown()
                self.setUp()

    def test_the_window_waits_for_ten_flows_or_fourteen_days(self):
        runner = self.landed_runner()
        self.flows(4, triggers=("owner_correction",), tokens=300)
        # landed_at is 30 days ago, so the days rule applies: shorten it to 5 days to see the wait
        [landing] = runner.load_landings()
        landing["landed_at"] = ht.iso(datetime.now(timezone.utc) - timedelta(days=5))
        runner.save_landings([landing])
        self.assertFalse(self.check(runner))
        self.assertIsNone(runner.load_landings()[0]["evaluated"])
        landing["landed_at"] = ht.iso(self.T0)
        runner.save_landings([landing])
        self.assertTrue(self.check(runner))  # 14 days passed with 4 flows (>= the minimum)
        self.assertEqual(runner.load_landings()[0]["evaluated"], "reverted")

    def test_too_few_flows_after_fourteen_days_is_not_judged(self):
        runner = self.landed_runner()
        self.flows(2, triggers=("owner_correction",), tokens=300)
        self.assertFalse(self.check(runner))
        self.assertEqual(runner.load_landings()[0]["evaluated"], "too_few_flows")

    def test_no_baseline_is_not_judged(self):
        runner = self.landed_runner()
        [landing] = runner.load_landings()
        landing["metrics_before"] = {"flows": 0, "metrics": view()}
        runner.save_landings([landing])
        self.flows(10, triggers=("owner_correction",), tokens=300)
        self.assertFalse(self.check(runner))
        self.assertEqual(runner.load_landings()[0]["evaluated"], "too_few_flows")

    def test_a_revert_of_a_revert_is_never_automatic(self):
        runner = self.landed_runner()
        self.flows(10, triggers=("owner_correction",), tokens=300)
        self.check(runner)
        revert = [x for x in runner.load_landings() if x.get("reverts")][0]
        revert["landed_at"] = ht.iso(self.T0)
        revert["metrics_before"] = {"flows": 10, "metrics": view()}
        runner.save_landings([x for x in runner.load_landings() if not x.get("reverts")] + [revert])
        self.flows(10, days_after=2, triggers=("owner_correction",), tokens=900, start=100)
        base = self.origin_base()
        reviewed = len(self.reviewers())
        self.assertFalse(self.check(runner))
        self.assertEqual((self.origin_base(), len(self.reviewers())), (base, reviewed))
        issues = [c for c in self.gh.calls if c[0] == "issue"]
        self.assertEqual(issues[-1][4], ("Workflow", "On Hold"))
        self.assertIn("never automatic", issues[-1][3])
        self.assertEqual([x["evaluated"] for x in runner.load_landings() if x.get("reverts")], ["revert_of_revert_held"])

    def test_a_kill_switch_waits_without_judging(self):
        runner = self.landed_runner()
        self.flows(10, triggers=("owner_correction",), tokens=300)
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        (self.paths.state_dir / "PAUSED").write_text("x")
        base = self.origin_base()
        self.assertFalse(self.check(runner))
        self.assertEqual(self.origin_base(), base)
        self.assertIsNone(runner.load_landings()[0]["evaluated"])
        (self.paths.state_dir / "PAUSED").unlink()
        self.assertTrue(self.check(runner))

    def test_a_reviewer_who_refuses_leaves_the_branch_and_the_base(self):
        runner = self.landed_runner()
        self.flows(10, triggers=("owner_correction",), tokens=300)
        self.session(runner, [LANE], verdict="changes")
        base = self.origin_base()
        self.assertTrue(self.check(runner))
        self.assertEqual(self.origin_base(), base)
        self.assertIn(f"agents/revert-{self.merge_sha[:12]}", g(self.origin, "branch", "--list", "agents/revert-*"))
        self.assertEqual(runner.load_landings()[0]["evaluated"], "revert_not_landed")
        titles = [c[2] for c in self.gh.calls if c[0] == "issue"]
        self.assertTrue(any("reverted, metrics regressed" in x for x in titles))
        self.assertTrue(any("not landed (review)" in x for x in titles))

    def test_the_pushed_revert_sha_is_recorded_and_a_retry_lands_only_that_tip(self):
        runner = self.landed_runner()
        self.flows(10, triggers=("owner_correction",), tokens=300)
        self.session(runner, [LANE], verdict="changes")
        self.assertTrue(self.check(runner))  # pushed, then refused by the reviewer
        branch = f"agents/revert-{self.merge_sha[:12]}"
        tip = g(self.origin, "rev-parse", branch)
        [landing] = [x for x in runner.load_landings() if x["lane"] == LANE]
        self.assertEqual(landing["revert_sha"], tip)
        landing["evaluated"] = None  # a retry (e.g. the first attempt was paused)
        runner.save_landings([landing] + [x for x in runner.load_landings() if x["lane"] != LANE])
        self.session(runner, [LANE], verdict="pass")
        self.assertTrue(self.check(runner))
        self.assertNotIn("b.txt", g(self.origin, "ls-tree", "-r", "--name-only", BASE).split())
        self.assertEqual([x["evaluated"] for x in runner.load_landings() if x["lane"] == LANE], ["reverted"])

    def test_the_recorded_revert_sha_is_passed_to_the_lander_and_a_push_in_the_window_is_not_landed(self):
        runner = self.landed_runner()
        self.flows(10, triggers=("owner_correction",), tokens=300)
        seen = []
        import lane_land
        real = lane_land.land

        def racing(*a, **kw):
            seen.append(kw.get("expected_sha"))
            branch = f"agents/revert-{self.merge_sha[:12]}"  # a push after the tip check, before the lander fetches
            g(self.dev, "checkout", "-q", "-b", "racer", BASE)
            (self.dev / "evil.txt").write_text("evil\n")
            g(self.dev, "add", "-A")
            g(self.dev, "commit", "-qm", "swap the revert")
            g(self.dev, "push", "-q", "-f", "origin", f"racer:refs/heads/{branch}")
            g(self.dev, "checkout", "-q", BASE)
            return real(*a, **kw)
        self.session(runner, [LANE], verdict="pass")
        base, reviewed = self.origin_base(), len(self.reviewers())
        with mock.patch.object(lane_land, "land", racing):
            self.check(runner)
        [landing] = [x for x in runner.load_landings() if x["lane"] == LANE]
        self.assertEqual(seen, [landing["revert_sha"]])
        self.assertEqual(self.origin_base(), base)  # refused: nothing merged
        self.assertNotIn("evil.txt", g(self.origin, "ls-tree", "-r", "--name-only", BASE).split())
        self.assertEqual(len(self.reviewers()), reviewed)

    def test_a_pre_existing_revert_branch_the_runner_did_not_push_is_refused_and_filed_on_hold(self):
        runner = self.landed_runner()
        self.flows(10, triggers=("owner_correction",), tokens=300)
        branch = f"agents/revert-{self.merge_sha[:12]}"
        g(self.dev, "checkout", "-q", "-b", branch, BASE)
        (self.dev / "evil.txt").write_text("not a revert\n")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "looks like a revert")
        g(self.dev, "push", "-q", "origin", branch)
        g(self.dev, "checkout", "-q", BASE)
        base, reviewed = self.origin_base(), len(self.reviewers())
        self.assertFalse(self.check(runner))
        self.assertEqual((self.origin_base(), len(self.reviewers())), (base, reviewed))  # nothing reviewed, nothing landed
        self.assertEqual(runner.load_landings()[0]["evaluated"], "revert_branch_foreign")
        [issue] = [c for c in self.gh.calls if c[0] == "issue"]
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn("not the runner's revert", issue[2])

    def test_a_recorded_revert_sha_that_is_not_the_tip_is_refused_too(self):
        runner = self.landed_runner()
        [landing] = runner.load_landings()
        landing["revert_sha"] = "0" * 40
        runner.save_landings([landing])
        branch = f"agents/revert-{self.merge_sha[:12]}"
        g(self.dev, "checkout", "-q", "-b", branch, BASE)
        (self.dev / "evil.txt").write_text("swapped\n")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "swapped tip")
        g(self.dev, "push", "-q", "origin", branch)
        g(self.dev, "checkout", "-q", BASE)
        self.flows(10, triggers=("owner_correction",), tokens=300)
        self.assertFalse(self.check(runner))
        self.assertEqual(runner.load_landings()[0]["evaluated"], "revert_branch_foreign")

    def test_a_failure_while_reverting_files_an_issue_and_never_crashes_the_tick(self):
        runner = self.landed_runner()
        self.flows(10, triggers=("owner_correction",), tokens=300)
        with mock.patch.object(runner, "revert_landing", side_effect=RuntimeError("git exploded")):
            self.assertFalse(self.check(runner))
        self.assertEqual(runner.load_landings()[0]["evaluated"], "revert_error")
        [issue] = [c for c in self.gh.calls if c[0] == "issue"]
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn("git exploded", issue[3])

    def test_landings_are_written_under_a_lock_file(self):
        runner = self.landed_runner()
        with runner.landings_guard():
            with runner.landings_guard():  # re-entrant
                runner.save_landings(runner.load_landings())
        self.assertTrue((self.paths.state_dir / "landings.lock").exists())

    def test_a_revert_that_conflicts_is_filed_on_hold(self):
        runner = self.landed_runner()
        self.push_lane("agents/other", {"b.txt": "changed later\n"})
        g(self.dev, "checkout", "-q", BASE)
        g(self.dev, "pull", "-q", "origin", BASE)
        (self.dev / "b.txt").write_text("changed later\n")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "owner touches b")
        g(self.dev, "push", "-q", "origin", BASE)
        self.flows(10, triggers=("owner_correction",), tokens=300)
        self.assertFalse(self.check(runner))
        self.assertEqual(runner.load_landings()[0]["evaluated"], "revert_failed")
        [issue] = [c for c in self.gh.calls if c[0] == "issue"]
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertEqual(g(self.origin, "branch", "--list", "agents/revert-*"), "")

    def test_the_tick_runs_the_check_before_a_due_job(self):
        runner = self.runner(FakeGitHub([]), None)
        calls = []
        runner.idle_check = lambda: True
        with mock.patch.object(runner, "run_retro", return_value=None), \
                mock.patch.object(runner, "check_regressions", side_effect=lambda: calls.append("c") or True), \
                mock.patch.object(runner, "run_due_job", side_effect=lambda: calls.append("j")), \
                mock.patch.object(runner, "refresh_clone"), mock.patch.object(runner, "check_base"):
            runner.tick()
        self.assertEqual(calls, ["c"])  # a revert used the machine: no job this tick


class DisabledTests(RevertBase):
    def test_dry_run_and_nightly_do_nothing(self):
        runner = self.landed_runner()
        runner.dry_run = True
        self.assertFalse(runner.check_regressions())
        runner.dry_run = False
        runner.intake = {"repo": "x"}
        self.assertFalse(runner.check_regressions())


class KillSwitchStatusTests(t.Base):
    def report(self):
        return ht.status_report(self.cfg, self.paths, FakeGitHub([]), True)["self_changes"]

    def test_running_when_no_switch_exists(self):
        self.assertEqual(self.report()["paused"], False)

    def test_each_switch_is_named_and_the_pending_ack_sha_shown(self):
        sha = "a" * 40
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        (self.paths.state_dir / "SELF_CHANGE_PAUSED").write_text(f"origin moved. Accept with `ack-base {sha}` (agents never run this).\n")
        report = self.report()
        self.assertTrue(report["paused"])
        self.assertEqual(report["switches"], ["SELF_CHANGE_PAUSED"])
        self.assertEqual(report["ack_base"], sha)
        self.assertIn("origin moved", report["reason"])
        (self.paths.state_dir / "SELF_CHANGE_PAUSED.json").write_text(json.dumps({"sha": "b" * 40}))
        self.assertEqual(self.report()["ack_base"], "b" * 40)
        self.paths.config_dir.mkdir(parents=True, exist_ok=True)
        self.paths.paused.write_text("x")
        self.assertEqual(self.report()["switches"], ["runner PAUSED", "SELF_CHANGE_PAUSED"])

    def test_the_status_command_prints_it(self):
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        (self.paths.state_dir / "SELF_CHANGE_PAUSED").write_text(f"moved. ack-base {'c' * 40}\n")
        out = io.StringIO()
        with mock.patch("sys.stdout", new=out), mock.patch.object(ht, "claude_logged_in", return_value=True), \
                mock.patch.object(ht, "GitHub", lambda **k: FakeGitHub([])):
            self.assertEqual(ht.main(["status"], home=self.home), 0)
        text = out.getvalue()
        self.assertIn("self-changes: PAUSED by SELF_CHANGE_PAUSED", text)
        self.assertIn(f"pending ack-base: {'c' * 40}", text)
        self.paths.state_dir.joinpath("SELF_CHANGE_PAUSED").unlink()
        out = io.StringIO()
        with mock.patch("sys.stdout", new=out), mock.patch.object(ht, "claude_logged_in", return_value=True), \
                mock.patch.object(ht, "GitHub", lambda **k: FakeGitHub([])):
            ht.main(["status"], home=self.home)
        self.assertIn("self-changes: running", out.getvalue())


class AckHardeningTests(p3.LandBase):
    def owner_push(self, name):
        g(self.dev, "checkout", "-q", BASE)
        g(self.dev, "pull", "-q", "origin", BASE)
        (self.dev / name).write_text("o\n")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "owner push")
        g(self.dev, "push", "-q", "origin", BASE)
        return g(self.dev, "rev-parse", "HEAD")

    def trip(self):
        runner = self.runner(FakeGitHub([]), None)
        runner.check_base("tick")
        first = self.owner_push("one.txt")
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.check_base("tick")
        return runner, first

    def test_the_trip_stores_the_sha_that_tripped_it(self):
        runner, first = self.trip()
        info = ht.pause_info(self.paths)
        self.assertEqual((info["sha"], info["latest"], info["moves"]), (first, first, []))

    def test_a_second_move_keeps_the_first_sha_and_is_listed(self):
        runner, first = self.trip()
        second = self.owner_push("two.txt")
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.check_base("tick")  # a tick between the two pushes, the loophole the review found
            runner.check_base("tick")
        info = ht.pause_info(self.paths)
        self.assertEqual(info["sha"], first)  # never rewritten to the newest commit
        self.assertEqual(info["latest"], second)
        self.assertEqual([m["sha"] for m in info["moves"]], [second])  # once, however many ticks
        self.assertEqual(ht.pause_moves(info), [first, second])
        text = (self.paths.state_dir / "SELF_CHANGE_PAUSED").read_text()
        for sha in (first, second):
            self.assertIn(sha, text)
        self.assertIn(f"ack-base {second}", text)
        status = ht.self_change_status(self.paths)
        self.assertEqual((status["ack_base"], status["moves"]), (second, [first, second]))

    def test_two_moves_are_acked_by_the_current_sha_and_both_are_printed(self):
        runner, first = self.trip()
        second = self.owner_push("two.txt")
        out = io.StringIO()
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.check_base("tick")
        with self.assertRaises(ht.TriageError):
            runner.ack_base(first)  # not the current SHA
        with mock.patch("sys.stdout", new=out):
            self.assertEqual(runner.ack_base(second), second)
        for sha in (first, second):
            self.assertIn(sha, out.getvalue())
        self.assertFalse((self.paths.state_dir / "SELF_CHANGE_PAUSED").exists())
        self.assertEqual(ht.pause_info(self.paths), {})

    def test_an_ack_after_a_move_the_pause_has_not_listed_is_refused_and_lists_it(self):
        runner, first = self.trip()
        second = self.owner_push("two.txt")  # no tick: the pause does not know it yet
        with self.assertRaises(ht.TriageError) as cm, mock.patch("sys.stdout", new=io.StringIO()):
            runner.ack_base(second)
        self.assertIn("moved again", str(cm.exception))
        self.assertIn(first, str(cm.exception))
        self.assertEqual(ht.pause_info(self.paths)["sha"], first)
        self.assertEqual(ht.pause_moves(ht.pause_info(self.paths)), [first, second])  # now it is listed
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(runner.ack_base(second), second)  # the owner has seen the list: now accepted
        self.assertFalse((self.paths.state_dir / "SELF_CHANGE_PAUSED").exists())

    def test_an_ack_with_no_recorded_trip_sha_still_works(self):
        runner, first = self.trip()
        (self.paths.state_dir / "SELF_CHANGE_PAUSED.json").unlink()
        self.assertEqual(runner.ack_base(first), first)


class MissingBaseTests(p3.LandBase):
    def runner_without_base(self, gh):
        g(self.origin, "update-ref", "-d", f"refs/heads/{BASE}")
        return self.retro_runner(gh, [LANE])

    def test_a_missing_base_files_one_on_hold_issue_per_process(self):
        self.push_lane(LANE, {"b.txt": "b\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, [LANE])
        real = runner.run

        def run(args, **k):  # the clone cannot see the base on origin
            if "ls-remote" in args and "--exit-code" in args and args[-1] == BASE:
                return t.subprocess.CompletedProcess(args, 2, "", "")
            return real(args, **k)

        runner.run = run
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertIsNone(runner.run_retro())
            self.assertIsNone(runner.run_retro())
        [issue] = [c for c in gh.calls if c[0] == "issue"]
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn(BASE, issue[2])
        self.assertIn("not on origin", issue[2])

    def test_a_failed_look_at_origin_is_not_a_missing_base(self):
        self.push_lane(LANE, {"b.txt": "b\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, [LANE])
        real = runner.run

        def run(args, **k):  # ls-remote exit 128: the network or auth failed, the branch may well be there
            if "ls-remote" in args and "--exit-code" in args and args[-1] == BASE:
                return t.subprocess.CompletedProcess(args, 128, "", "fatal: could not read")
            return real(args, **k)

        runner.run = run
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertIsNone(runner.run_retro())
        self.assertEqual([c for c in gh.calls if c[0] == "issue"], [])
        self.assertFalse(runner.base_absent(BASE))  # the branch is there
        g(self.origin, "update-ref", "-d", f"refs/heads/{BASE}")
        g(self.origin, "symbolic-ref", "HEAD", "refs/heads/elsewhere")
        self.assertTrue(runner.base_absent(BASE))

    def test_it_is_not_filed_twice_when_an_open_issue_has_the_title(self):
        gh = FakeGitHub([{"number": 5, "title": f"Workflow: workflow base {BASE} is not on origin", "state": "OPEN", "labels": []}])
        runner = self.runner(gh, None)
        runner.base_missing(BASE, "x")
        self.assertEqual([c for c in gh.calls if c[0] == "issue"], [])

    def test_a_lane_landing_against_a_missing_base_files_it(self):
        self.push_lane(LANE, {"b.txt": "b\n"})
        gh = FakeGitHub([])
        runner = self.retro_runner(gh, [LANE])
        g(self.origin, "symbolic-ref", "HEAD", "refs/heads/elsewhere")  # keep origin valid without the base
        g(self.origin, "update-ref", "-d", f"refs/heads/{BASE}")
        with mock.patch("sys.stdout", new=io.StringIO()):
            outcome = runner.land_lane(LANE, BASE, "x")
        self.assertEqual(outcome, "paused")
        [issue] = [c for c in gh.calls if c[0] == "issue"]
        self.assertEqual(issue[4], ("Workflow", "On Hold"))
        self.assertIn("not on origin", issue[2])
