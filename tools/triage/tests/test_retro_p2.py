"""Phase 2 of the self-improving loop in the runner: Workflow routing, scheduled-job archives, owner comments made during a
run, the post-mortem (retro) queue and its headless session. No network, gh or claude: every seam is faked."""
from __future__ import annotations

import io
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_hass_triage as t  # noqa: E402

ht = t.ht
issue = t.issue
FakeGitHub = t.FakeGitHub


class WorkflowRoutingTests(t.Base):
    def test_workflow_label_routes_to_the_steward_at_l1(self):
        wf = issue(1, labels=["Workflow"])
        self.assertEqual(ht.route_rule(wf, False), "steward")
        self.assertEqual(ht.ledger_level(wf, False), "L1")
        self.assertEqual(ht.route_rule(wf, True), "coder")  # nightly issues are machine text
        self.assertEqual(ht.route_rule(issue(1, labels=["Workflow", "Feature"]), False), "steward")
        self.assertIn("steward-first", ht.route_text("steward", None))
        self.assertIn("Entry B", ht.route_text("steward", None))
        self.assertEqual(ht.route_text("coder", None), "Route: rules say coder-first")

    def test_label_description(self):
        self.assertEqual(self.cfg["labels"]["Workflow"][1], "How the agents work: Steward-first, autonomous (owner 2026-11-02)")
        self.assertEqual(self.cfg["workflow_base"], "main")


class JobArchiveTests(t.Base):
    def test_a_scheduled_job_is_archived_and_digested(self):
        runner = self.runner(FakeGitHub([]), {"state": "done", "summary": "weekly"})
        orig = runner.launch

        def launch(key, tree, prompt, log):
            (tree / "build" / "review").mkdir(parents=True, exist_ok=True)
            (tree / "build" / "review" / "r.json").write_text(json.dumps({"verdict": "pass"}))
            return orig(key, tree, prompt, log)

        runner.launch = launch
        runner.run_job("steward")
        dest = self.paths.root / "archive" / f"job-steward-{ht.now().strftime('%Y-%m-%d')}"
        self.assertTrue((dest / "review" / "r.json").is_file())
        self.assertTrue((dest / "status.json").is_file())
        self.assertTrue((dest / "worker.log.tail").is_file())
        calls = [c for c in self.commands if len(c) > 1 and str(c[1]).endswith("retro_digest.py")]
        self.assertEqual(len(calls), 1)
        self.assertIn(f"job-steward-{ht.now().strftime('%Y-%m-%d')}", calls[0])
        self.assertEqual(calls[0][calls[0].index("--outcome") + 1], "done")

    def test_a_failed_job_still_archives(self):
        runner = self.runner(FakeGitHub([]), None, code=-9)
        self.assertEqual(runner.run_job("researcher"), "timeout")
        calls = [c for c in self.commands if len(c) > 1 and str(c[1]).endswith("retro_digest.py")]
        self.assertEqual(calls[0][calls[0].index("--outcome") + 1], "blocked:timeout")


class OwnerCommentsDuringRunTests(t.Base):
    def comment(self, cid, body, created, login="SFenton"):
        return {"id": cid, "body": body, "created_at": created, "user": {"login": login}}

    def test_comments_after_the_start_are_archived_as_owner_replies(self):
        gh = FakeGitHub([issue(40)])
        runner = self.runner(gh, {"state": "no_changes", "summary": "x"})
        gh.comment_store[40] = [
            self.comment(1, "before the run", "2020-01-01T00:00:00Z"),
            self.comment(2, "use the other tile", "2999-01-01T00:00:00Z"),
            self.comment(3, "<!-- hass-triage:40:progress --> runner text", "2999-01-01T00:00:00Z"),
            self.comment(4, "a stranger", "2999-01-01T00:00:00Z", login="someone"),
        ]
        runner.work(40)
        saved = json.loads((self.paths.root / "archive" / "request-40" / "owner_replies.json").read_text())
        self.assertEqual([r["body"] for r in saved], ["use the other tile"])

    def test_a_comment_fetch_failure_never_fails_the_run(self):
        gh = FakeGitHub([issue(41)])
        calls = []

        def comments(*a):
            calls.append(a)
            if len(calls) > 2:  # the pickup and result updates read comments; the end-of-run fetch fails
                raise ht.TriageError("gh down")
            return []

        gh.comments = comments
        runner = self.runner(gh, {"state": "no_changes", "summary": "x"})
        with mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(runner.work(41), "no_changes")
        self.assertIn("could not read owner comments", out.getvalue())

    def test_the_existing_reply_and_new_comments_merge_without_duplicates(self):
        gh = FakeGitHub([issue(42, labels=["Blocked"])])
        gh.comment_store[42] = [self.comment(7, "pick b", "2999-01-01T00:00:00Z")]
        runner = self.runner(gh, {"state": "blocked", "blocked_reason": "x"})
        runner.state.data["replies"] = {"42": 7}
        runner.work(42)
        saved = json.loads((self.paths.root / "archive" / "request-42" / "owner_replies.json").read_text())
        self.assertEqual([r["id"] for r in saved], [7])


class RetroHelpers(t.Base):
    def write_digest(self, dest, task, triggers):
        (dest / "retro").mkdir(parents=True, exist_ok=True)
        (dest / "retro" / f"{task}.json").write_text(json.dumps({"task": task, "triggers": [{"id": i} for i in triggers]}))

    def retro_state(self):
        return json.loads(self.paths.state_dir.joinpath("state-retro.json").read_text())


class RetroQueueTests(RetroHelpers):
    def test_a_trigger_queues_a_retro_and_none_does_not(self):
        runner = self.runner(FakeGitHub([]))
        quiet = self.paths.root / "archive" / "request-1"
        self.write_digest(quiet, "R-1", [])
        self.assertFalse(runner.enqueue_retro(quiet, "R-1"))
        loud = self.paths.root / "archive" / "request-2"
        self.write_digest(loud, "R-2", ["owner_correction", "blocked"])
        self.assertTrue(runner.enqueue_retro(loud, "R-2"))
        self.assertTrue(runner.enqueue_retro(loud, "R-2"))  # re-archived: replaced, not duplicated
        queue = self.retro_state()["queue"]
        self.assertEqual([q["task"] for q in queue], ["R-2"])
        self.assertEqual(queue[0]["triggers"], ["owner_correction", "blocked"])

    def test_touched_workflow_paths_queue_a_retro_without_a_trigger(self):
        runner = self.runner(FakeGitHub([]))
        dest = self.paths.root / "archive" / "request-3"
        self.write_digest(dest, "R-3", [])
        (dest / "touched.json").write_text(json.dumps([".claude/agents/coder.md"]))
        self.assertTrue(runner.enqueue_retro(dest, "R-3"))
        self.assertEqual(self.retro_state()["queue"][0]["touched"], [".claude/agents/coder.md"])

    def test_workflow_touched_filters_the_diff(self):
        runner = self.runner(FakeGitHub([]))
        files = "\n".join([".claude/agents/coder.md", "Sources/App.swift", "tools/triage/hass_triage.py",
                           "tools/hooks_extra/x.py", ".agents/workflow/a.md", ".agents/patterns/b.md", "contracts/jev/q.json"])
        real = runner.run
        runner.run = lambda args, **kw: (subprocess.CompletedProcess(args, 0, files, "") if "diff" in args
                                          else real(args, **kw))
        self.assertEqual(runner.workflow_touched(self.paths.home),
                         [".claude/agents/coder.md", "tools/triage/hass_triage.py", ".agents/workflow/a.md",
                          "contracts/jev/q.json"])

    def test_an_issue_ending_with_a_trigger_is_queued_end_to_end(self):
        gh = FakeGitHub([issue(50)])
        runner = self.runner(gh, {"state": "blocked", "blocked_reason": "stuck"})
        real = runner.run

        def run(args, **kw):
            if len(args) > 1 and str(args[1]).endswith("retro_digest.py"):  # the real digest, on the real archive
                import retro_digest
                retro_digest.main(args[2:])
                return subprocess.CompletedProcess(args, 0, "", "")
            return real(args, **kw)

        runner.run = run
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.work(50)
        queue = self.retro_state()["queue"]
        self.assertEqual(queue[0]["task"], "R-50")
        self.assertIn("blocked", queue[0]["triggers"])

    def test_a_flow_that_touched_workflow_files_is_queued(self):
        gh = FakeGitHub([issue(51)])
        runner = self.runner(gh, {"state": "no_changes", "summary": "x"})
        real = runner.run
        runner.run = lambda args, **kw: (subprocess.CompletedProcess(args, 0, "tools/hooks/a.py\n", "") if "diff" in args
                                          else real(args, **kw))
        runner.work(51)
        self.assertEqual(self.retro_state()["queue"][0]["touched"], ["tools/hooks/a.py"])


class RetroRunTests(RetroHelpers):
    def setUp(self):
        super().setUp()
        self.cfg["workflow_base"] = "claude/uikit-port"  # the fixture keeps a workflow base apart from the product base

    def queue(self, runner, task="R-60", triggers=("blocked",), touched=()):
        dest = self.paths.root / "archive" / "request-60"
        self.write_digest(dest, task, list(triggers))
        item = {"archive": str(dest), "task": task, "triggers": list(triggers), "touched": list(touched), "queued": ht.iso()}
        state = ht.State(runner.retro_paths.state)
        state.data["queue"] = [item]
        state.save()
        return dest

    def with_base(self, runner, present=True):
        real = runner.run

        def run(args, **kw):
            if "ls-remote" in args and "--exit-code" in args and "origin" in args and args[-1] == "claude/uikit-port":
                return subprocess.CompletedProcess(args, 0 if present else 2, "", "")
            return real(args, **kw)

        runner.run = run

    def test_the_retro_session_runs_from_the_workflow_base_with_the_retro_prompt(self):
        runner = self.runner(FakeGitHub([]), None)
        self.with_base(runner)
        self.queue(runner, triggers=("owner_correction", "blocked"), touched=("tools/hooks/a.py",))
        orig = runner.launch

        def launch(key, tree, prompt, log):
            result = orig(key, tree, prompt, log)
            (tree / "build" / "retro").mkdir(parents=True, exist_ok=True)
            (tree / "build" / "retro" / "R-60.status.json").write_text(json.dumps({"state": "done", "summary": "merged one"}))
            return result

        runner.launch = launch
        self.assertEqual(runner.run_retro(), "done")
        text = self.prompts[0]
        self.assertNotIn("{{", text)
        for part in ("R-60", "claude/uikit-port", "owner_correction, blocked", "tools/hooks/a.py", str(self.paths.root / "archive"),
                     runner.cfg["request_repo"], '"task": "R-60"'):
            self.assertIn(part, text)
        adds = [c for c in self.commands if "worktree" in c and "add" in c]
        self.assertEqual(adds[-1][-1], "origin/claude/uikit-port")
        self.assertIn("-B", adds[-1])
        state = self.retro_state()
        self.assertEqual(state["queue"], [])
        self.assertEqual(state["done"][0]["outcome"], "done")
        self.assertEqual(state["done"][0]["summary"], "merged one")
        self.assertIsNone(state["current"])

    def test_the_retro_is_archived_and_never_queues_another(self):
        runner = self.runner(FakeGitHub([]), {"state": "no_changes", "summary": "nothing"})
        self.with_base(runner)
        self.queue(runner)
        real = runner.run
        calls = []

        def run(args, **kw):
            if len(args) > 1 and str(args[1]).endswith("retro_digest.py"):
                calls.append(args)
                dest = Path(args[args.index("--archive") + 1])
                self.write_digest(dest, "retro-R-60", ["blocked"])  # even a triggering digest must not re-queue
            return real(args, **kw)

        runner.run = run
        runner.launch = lambda key, tree, prompt, log: (log.parent.mkdir(parents=True, exist_ok=True),
                                                         log.write_text("x\n"),
                                                         self.paths.status_file(key).parent.mkdir(parents=True, exist_ok=True),
                                                         self.paths.status_file(key).write_text(
                                                             json.dumps({"state": "no_changes", "summary": "nothing"})), 0)[-1]
        self.assertEqual(runner.run_retro(), "no_changes")
        self.assertTrue((self.paths.root / "archive" / "retro-request-60" / "status.json").is_file())
        self.assertEqual(calls[0][calls[0].index("--task") + 1], "retro-R-60")
        self.assertEqual(self.retro_state()["queue"], [])

    def test_a_missing_base_skips_with_one_log_line_and_keeps_the_queue(self):
        runner = self.runner(FakeGitHub([]), None)
        self.with_base(runner, present=False)
        self.queue(runner)
        with mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertIsNone(runner.run_retro())
            self.assertIsNone(runner.run_retro())
        self.assertEqual(out.getvalue().count("retro: workflow base claude/uikit-port not on origin"), 1)
        self.assertEqual(self.prompts, [])
        self.assertEqual(len(self.retro_state()["queue"]), 1)

    def test_empty_queue_paused_dry_run_and_signed_out_do_nothing(self):
        runner = self.runner(FakeGitHub([]), None)
        self.with_base(runner)
        self.assertIsNone(runner.run_retro())
        self.queue(runner)
        (self.paths.clone / "build" / "retro").mkdir(parents=True)
        (self.paths.clone / "build" / "retro" / "PAUSED").write_text("x")
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertIsNone(runner.run_retro())
        (self.paths.clone / "build" / "retro" / "PAUSED").unlink()
        self.auth = json.dumps({"loggedIn": False})
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertIsNone(runner.run_retro())
        self.assertEqual(self.prompts, [])
        self.assertEqual(len(self.retro_state()["queue"]), 1)
        dry = self.runner(FakeGitHub([], dry_run=True), dry_run=True)
        self.assertIsNone(dry.run_retro())

    def test_retro_runs_only_on_an_idle_tick_and_before_jobs(self):
        runner = self.runner(FakeGitHub([issue(70)]), {"state": "no_changes", "summary": "x"})
        self.with_base(runner)
        self.queue(runner)
        runner.tick(max_items=1)  # the request queue was not drained
        self.assertEqual(len([p for p in self.prompts if "# Fenton Home post-mortem" in p]), 0)
        runner = self.runner(FakeGitHub([]), None)
        self.with_base(runner)
        for name in ("steward", "researcher"):
            runner.state.data["jobs"].setdefault(name, {})["last_run"] = "2020-01-01T00:00:00Z"
        runner.idle_check = lambda: False  # the nightly queue has work
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.tick()
        self.assertEqual(self.prompts, [])
        runner.idle_check = None
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.tick()
        self.assertEqual(len(self.prompts), 1)
        self.assertIn("# Fenton Home post-mortem", self.prompts[0])  # the retro went first; the job waits for the next tick

    def test_a_crashing_retro_is_recorded_and_the_queue_moves_on(self):
        runner = self.runner(FakeGitHub([]), None)
        self.with_base(runner)
        self.queue(runner)
        runner.launch = lambda *a: (_ for _ in ()).throw(RuntimeError("boom"))
        with mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(runner.run_retro(), "error")
        self.assertIn("retro R-60 failed", out.getvalue())
        self.assertEqual(self.retro_state()["queue"], [])
        self.assertEqual(self.retro_state()["done"][0]["outcome"], "error")

    def test_status_lists_queued_postmortems(self):
        runner = self.runner(FakeGitHub([]))
        self.queue(runner)
        report = ht.status_report(self.cfg, self.paths, FakeGitHub([]), True)
        self.assertEqual(report["retro_queue"], ["R-60"])


if __name__ == "__main__":
    unittest.main()


class SelfChangeFollowUpTests(RetroHelpers):
    """Round-1 fixes: one post-mortem per flow, On Hold stays owner-only, resume replies count, every kill switch."""

    def test_a_flow_with_its_own_post_mortem_is_not_queued_again(self):
        runner = self.runner(FakeGitHub([]))
        dest = self.paths.root / "archive" / "request-80"
        self.write_digest(dest, "R-80", ["blocked"])
        (dest / "retro" / "R-80.status.json").write_text(json.dumps({"state": "done"}))
        self.assertFalse(runner.enqueue_retro(dest, "R-80"))
        (dest / "retro" / "R-80.status.json").unlink()
        self.assertTrue(runner.enqueue_retro(dest, "R-80"))

    def test_the_steward_job_archive_never_queues_a_retro_but_other_jobs_may(self):
        for name, expected in (("steward", False), ("researcher", True)):
            runner = self.runner(FakeGitHub([]), {"state": "done", "summary": "x"})
            seen = []
            runner.enqueue_retro = lambda dest, task, seen=seen: seen.append(task) or True
            real = runner.run

            def run(args, **kw):
                if len(args) > 1 and str(args[1]).endswith("retro_digest.py"):
                    self.write_digest(Path(args[args.index("--archive") + 1]), args[args.index("--task") + 1], ["blocked"])
                return real(args, **kw)

            runner.run = run
            runner.run_job(name)
            self.assertEqual(bool(seen), expected, name)

    def test_on_hold_workflow_issues_are_never_picked(self):
        held = issue(90, labels=["Workflow", "On Hold"])
        free = issue(91, labels=["Workflow"])
        self.assertEqual([i["number"] for i in ht.eligible([held, free], ["SFenton"])], [91])
        gh = FakeGitHub([held])
        runner = self.runner(gh, {"state": "no_changes", "summary": "x"})
        with mock.patch("sys.stdout", new=io.StringIO()):
            runner.tick()
        self.assertEqual(self.prompts, [])
        self.assertEqual([c for c in gh.calls if c[0] in ("labels", "close")], [])

    def test_every_pause_file_holds_the_retro(self):
        runner = self.runner(FakeGitHub([]), None)
        for path in (self.paths.config_dir / "PAUSED", self.paths.state_dir / "PAUSED",
                     self.paths.state_dir / "SELF_CHANGE_PAUSED", self.paths.clone / "build" / "retro" / "PAUSED"):
            self.assertFalse(runner.retro_paused())
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("x")
            self.assertTrue(runner.retro_paused(), str(path))
            path.unlink()

    def resumed_argv(self, label, stop_kind):
        gh = FakeGitHub([issue(95, labels=[label])])
        gh.comment_store[95] = [
            {"id": 1, "body": f"<!-- hass-triage:95:{stop_kind} --> stopped", "created_at": "2026-11-01T09:00:00Z",
             "user": {"login": "SFenton"}},
            {"id": 2, "body": "no, use the other tile", "created_at": "2026-11-01T10:00:00Z", "user": {"login": "SFenton"}}]
        runner = self.runner(gh, {"state": "no_changes", "summary": "x"})
        runner.requeue()
        runner.work(95)
        calls = [c for c in self.commands if len(c) > 1 and str(c[1]).endswith("retro_digest.py")]
        return calls[-1][calls[-1].index("--started") + 1]

    def test_a_blocked_resume_reply_counts_as_a_correction(self):
        self.assertEqual(self.resumed_argv("Blocked", "blocked"), "2026-11-01T09:59:59Z")

    def test_a_needs_decision_pick_stays_input(self):
        self.assertGreater(self.resumed_argv("Needs Decision", "decision-needed"), "2026-11-02")

    def test_retro_digest_counts_the_resume_reply_end_to_end(self):
        import retro_digest
        dest = self.paths.root / "archive" / "x"
        dest.mkdir(parents=True)
        (dest / "owner_replies.json").write_text(json.dumps(
            [{"id": 2, "createdAt": "2026-11-01T10:00:00Z", "body": "redirect"}]))
        retro_digest.main(["--task", "R-95", "--archive", str(dest), "--outcome", "done", "--started", "2026-11-01T09:59:59Z"])
        digest = json.loads((dest / "retro" / "R-95.json").read_text())
        self.assertIn("owner_correction", [t["id"] for t in digest["triggers"]])

    def test_an_unpushed_retro_worktree_is_kept(self):
        runner = self.runner(FakeGitHub([]))
        tree = self.paths.worktrees / "retro-R-1"
        tree.mkdir(parents=True)
        real = runner.run

        def run(args, **kw):
            if "rev-parse" in args:
                return subprocess.CompletedProcess(args, 0, "abc123\n", "")
            if "merge-base" in args:
                return subprocess.CompletedProcess(args, self.ancestor, "", "")
            return real(args, **kw)

        runner.run = run
        self.ancestor = 1
        self.assertTrue(runner.retro_unlanded(str(self.paths.clone), tree, "claude/uikit-port"))
        self.ancestor = 0
        self.assertFalse(runner.retro_unlanded(str(self.paths.clone), tree, "claude/uikit-port"))
