"""Writer admission, fresh-state and base-map protocol proofs for the triage runner."""
from __future__ import annotations

import contextlib
import errno
import fcntl
import io
import json
import multiprocessing
import os
import shutil
import sys
import threading
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import test_hass_triage as t  # noqa: E402

ht = t.ht
FakeGitHub = t.FakeGitHub


def lock_child(home: str, connection) -> None:
    cfg = ht.load_config(Path(home))
    paths = ht.Paths(cfg, Path(home))
    with ht.writer_lock(paths) as admitted:
        if not admitted:
            connection.send("busy")
            return
        runner = ht.Runner(cfg, paths, FakeGitHub([]))
        runner.state.data["completed-save"] = "yes"
        runner.state.save()
        connection.send("ready")
        connection.recv()


class RunnerLockTests(t.Base):
    def wait_for(self, event: threading.Event, message: str) -> None:
        self.assertTrue(event.wait(5), message)

    def lock_path(self) -> Path:
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        return self.paths.lock

    @contextlib.contextmanager
    def held_lock(self, text: str = "holder"):
        path = self.lock_path()
        path.write_text(text)
        lock = open(path, "a+")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
            lock.close()

    @staticmethod
    def can_acquire(path: Path) -> bool:
        path.parent.mkdir(parents=True, exist_ok=True)
        lock = open(path, "a+")
        try:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as exc:
                if exc.errno in (errno.EACCES, errno.EAGAIN):
                    return False
                raise
            fcntl.flock(lock, fcntl.LOCK_UN)
            return True
        finally:
            lock.close()

    def snapshot(self) -> dict:
        return {str(path.relative_to(self.home)): path.read_bytes()
                for path in self.home.rglob("*") if path.is_file()}

    def product_snapshot(self) -> dict:
        files = [self.paths.state, self.paths.state_dir / "workflow-base.json"]
        for root in (self.paths.root / "archive", self.paths.work):
            if root.exists():
                files.extend(path for path in root.rglob("*") if path.is_file())
        return {str(path.relative_to(self.home)): path.read_bytes() for path in files if path.is_file()}

    def pause_files(self, sha: str) -> tuple:
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        pause = self.paths.state_dir / "SELF_CHANGE_PAUSED"
        details = self.paths.state_dir / "SELF_CHANGE_PAUSED.json"
        pause.write_text("pending\n")
        details.write_text(json.dumps({"base": "main", "sha": sha, "latest": sha, "moves": []}))
        return pause, details

    def seed_unaccepted_base_move(self, runner):
        accepted = "a" * 40
        current = "b" * 40
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        runner.base_record().write_text(json.dumps({"main": accepted}))
        runner.refresh_clone = lambda: None
        return accepted, current

    def assert_tick_base_move_recorded(self, accepted: str, current: str) -> None:
        details = json.loads((self.paths.state_dir / "SELF_CHANGE_PAUSED.json").read_text())
        self.assertEqual((details["base"], details["sha"], details["expected"], details["when"]),
                         ("main", current, accepted, "tick"))
        self.assertTrue((self.paths.state_dir / "SELF_CHANGE_PAUSED").is_file())

    def test_shared_writer_admission_reaches_all_six_dispatches(self):
        probes = []
        calls = []

        def probe(site):
            probes.append((site, self.can_acquire(self.paths.lock)))

        class StateSpy:
            def require_writable(self):
                pass

            def save(self):
                probe("save")

        class RunnerSpy:
            def __init__(spy, cfg, paths, gh, dry_run=False, intake=None, **_kw):
                spy.intake = intake
                spy.state = mock.Mock()
                calls.append("construct:" + ("nightly" if intake else "primary"))

            def _tick_locked(spy, max_items=None):
                probe("tick:" + ("nightly" if spy.intake else "primary"))
                return 0

            def refresh_clone(spy):
                probe("refresh")

            def work(spy, number):
                probe(("issue", number))
                return "done"

            def run_job(spy, name):
                probe(("job", name))
                return "done"

            def ack_base(spy, sha):
                probe(("base", sha))
                return sha

            def ack_verified(spy, session):
                probe(("verified", session))
                return {"ok": True, "reason": "", "head": "c" * 40, "prs": [9]}

        cases = (
            (["tick"], {}, True),
            (["run-issue", "12"], {}, False),
            (["run-job", "steward"], {}, False),
            (["ack-base", "a" * 40], {}, False),
            (["ack-verified"], {}, False),
        )
        gh = FakeGitHub([t.issue(12)])
        for argv, env, tty in cases:
            with self.subTest(argv=argv):
                probes.clear()
                calls.clear()
                with mock.patch.object(ht, "Runner", RunnerSpy), mock.patch.object(ht, "GitHub", return_value=gh), \
                        mock.patch.dict(os.environ, env), mock.patch("sys.stdin") as stdin, \
                        mock.patch("sys.stdout", new=io.StringIO()), mock.patch("sys.stderr", new=io.StringIO()):
                    stdin.isatty.return_value = tty or argv[0] == "ack-base"
                    code = ht.main(argv, home=self.home)
                self.assertEqual(code, 0)
                self.assertTrue(probes, argv)
                self.assertTrue(all(not acquired for _site, acquired in probes), probes)

        with mock.patch.object(ht, "Runner", RunnerSpy), mock.patch.object(ht, "GitHub", return_value=gh), \
                mock.patch.object(ht, "render_prompt", side_effect=lambda *_a, **_k: "preview"), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["run-issue", "12", "--dry-run"], home=self.home), 0)
        self.assertTrue(probes and any(site == "construct:primary" for site in calls))

    def test_manual_busy_precedence_has_exact_output_and_zero_effects(self):
        commands = (
            (["run-issue", "9"], {}),
            (["run-issue", "9", "--dry-run"], {}),
            (["run-job", "steward"], {}),
            (["ack-base", "a" * 40], {"FENTON_HEADLESS": "1"}),
            (["ack-verified"], {"HASS_TRIAGE_ISSUE": "9"}),
        )
        for argv, env in commands:
            with self.subTest(argv=argv), self.held_lock():
                if argv[0] == "run-job":
                    self.paths.config_dir.mkdir(parents=True, exist_ok=True)
                    self.paths.paused.write_text("paused\n")
                before = self.snapshot()
                with mock.patch.object(ht, "Runner", side_effect=AssertionError("constructed")) as runner, \
                        mock.patch.dict(os.environ, env), mock.patch("sys.stdout", new=io.StringIO()) as out, \
                        mock.patch("sys.stderr", new=io.StringIO()) as err:
                    code = ht.main(argv, home=self.home)
                self.assertEqual(code, 1)
                self.assertEqual(out.getvalue(), f"another runner writer is active; {argv[0]} refused\n")
                self.assertEqual(err.getvalue(), "")
                runner.assert_not_called()
                self.assertEqual(self.snapshot(), before)
                self.assertEqual(self.paths.lock.read_text(), "holder")

    def test_busy_primary_never_falls_through_when_holder_releases(self):
        real_lock = ht.writer_lock
        holder = open(self.lock_path(), "a+")
        fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
        calls = []

        @contextlib.contextmanager
        def release_after_refusal(paths):
            with real_lock(paths) as admitted:
                calls.append(admitted)
                if not admitted:
                    fcntl.flock(holder, fcntl.LOCK_UN)
                    holder.close()
                yield admitted

        try:
            with mock.patch.object(ht, "writer_lock", release_after_refusal), \
                    mock.patch.object(ht, "Runner", side_effect=AssertionError("constructed")), \
                    mock.patch("sys.stdout", new=io.StringIO()) as out:
                self.assertEqual(ht.main(["tick"], home=self.home), 0)
        finally:
            if not holder.closed:
                fcntl.flock(holder, fcntl.LOCK_UN)
                holder.close()
        self.assertEqual(calls, [False])
        self.assertEqual(out.getvalue(), "another tick is running\n")

    def test_cli_nightly_busy_after_primary_returns_without_constructor(self):
        real_lock = ht.writer_lock
        admissions = []
        calls = []

        @contextlib.contextmanager
        def nightly_busy(paths):
            admissions.append(paths.prefix)
            if len(admissions) == 1:
                with real_lock(paths) as admitted:
                    yield admitted
                return
            with open(paths.lock, "a+") as holder:
                fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with real_lock(paths) as admitted:
                    yield admitted
                fcntl.flock(holder, fcntl.LOCK_UN)

        class RunnerSpy:
            def __init__(spy, cfg, paths, gh, dry_run=False, intake=None, **_kw):
                spy.intake = intake
                spy.state = mock.Mock()
                calls.append("construct:" + ("nightly" if intake else "primary"))

            def _tick_locked(spy, _max_items=None):
                calls.append("tick:" + ("nightly" if spy.intake else "primary"))
                return 0

        with mock.patch.object(ht, "writer_lock", nightly_busy), mock.patch.object(ht, "Runner", RunnerSpy), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(ht.main(["tick"], home=self.home), 0)
        self.assertEqual(admissions, ["", "nightly-"])
        self.assertEqual(calls, ["construct:primary", "tick:primary"])
        self.assertEqual(out.getvalue(), "another tick is running\n")

    def test_cli_nightly_winner_loads_its_own_state_while_admitted(self):
        seen = []

        class RunnerSpy:
            def __init__(spy, cfg, paths, gh, dry_run=False, intake=None, **_kw):
                spy.paths = paths
                spy.intake = intake
                spy.state = mock.Mock()
                seen.append(("construct", paths.state.name, RunnerLockTests.can_acquire(paths.lock)))

            def _tick_locked(spy, _max_items=None):
                seen.append(("tick", spy.paths.state.name, self.can_acquire(spy.paths.lock)))
                return 0

        with mock.patch.object(ht, "Runner", RunnerSpy), mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["tick"], home=self.home), 0)
        self.assertEqual([event for event in seen if event[0] == "construct"],
                         [("construct", "state.json", False), ("construct", "state-nightly.json", False)])
        self.assertEqual([event for event in seen if event[0] == "tick"],
                         [("tick", "state.json", False), ("tick", "state-nightly.json", False)])

    def test_tick_loader_runs_after_admission_once_per_entry(self):
        visits = []

        class StateSpy:
            def require_writable(self):
                pass

            def save(self):
                pass

        def loader(path):
            path.parent.mkdir(parents=True, exist_ok=True)
            visits.append((str(path), self.can_acquire(path.parent / "tick.lock")))
            return StateSpy()

        runner = ht.Runner(self.cfg, self.paths, FakeGitHub([]), state_loader=loader)
        visits.clear()
        with mock.patch.object(ht.Runner, "_tick_locked", return_value=0):
            self.assertEqual(runner.tick(), 0)
        self.assertEqual(len(visits), 1)
        self.assertFalse(visits[0][1])

        visits.clear()
        with self.held_lock(), mock.patch.object(ht.Runner, "_tick_locked", return_value=0):
            self.assertEqual(runner.tick(), 0)
        self.assertEqual(visits, [])

    def test_main_constructs_both_ticks_after_the_shared_inode_is_admitted(self):
        visits = []
        original = ht.State

        def load(path):
            visits.append((path.name, self.can_acquire(path.parent / "tick.lock")))
            return original(path)

        with mock.patch.object(ht, "State", side_effect=load), \
                mock.patch.object(ht.Runner, "_tick_locked", return_value=0), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["tick"], home=self.home), 0)
        self.assertEqual([name for name, _held in visits], ["state.json", "state-nightly.json"])
        self.assertTrue(all(not free for _name, free in visits))

    def test_unaccepted_base_move_still_processes_a_queued_request(self):
        gh = FakeGitHub([t.issue(12)])
        runner = self.runner(gh)
        accepted, current = self.seed_unaccepted_base_move(runner)
        runner.preflight = lambda: True
        runner.schedules_idle = lambda: False
        worked = []
        runner.work = lambda number: worked.append(number) or "done"
        with mock.patch.object(runner, "remote_base_sha", return_value=current), \
                mock.patch.object(runner, "pr_moves_ok", return_value=False), \
                mock.patch.object(ht.lane_land, "git",
                                  return_value=mock.Mock(returncode=0, stdout="", stderr="")), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(runner.tick(max_items=1), 0)
        self.assert_tick_base_move_recorded(accepted, current)
        self.assertEqual(worked, [12])

    def test_unaccepted_base_move_still_finishes_a_merging_item(self):
        pr = "https://github.com/SFenton/native-home/pull/77"
        gh = FakeGitHub([t.issue(13, labels=["Merging"])])
        gh.pulls[pr] = {"state": "MERGED", "labels": [], "url": pr}
        runner = self.runner(gh)
        accepted, current = self.seed_unaccepted_base_move(runner)
        runner.schedules_idle = lambda: False
        runner.state.data["merging"]["13"] = {
            "pr": pr, "since": 0, "status": {"summary": "merged", "tests": []},
        }
        with mock.patch.object(runner, "remote_base_sha", return_value=current), \
                mock.patch.object(runner, "pr_moves_ok", return_value=False), \
                mock.patch.object(ht.lane_land, "git",
                                  return_value=mock.Mock(returncode=0, stdout="", stderr="")), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(runner.tick(max_items=0), 0)
        self.assert_tick_base_move_recorded(accepted, current)
        self.assertEqual(gh.issues[13]["state"], "CLOSED")
        self.assertNotIn("13", runner.state.data["merging"])

    def test_unaccepted_base_move_still_runs_a_due_job(self):
        runner = self.runner(FakeGitHub([]))
        accepted, current = self.seed_unaccepted_base_move(runner)
        runner.schedules_idle = lambda: True
        runner.run_retro = lambda: False
        runner.check_regressions = lambda: False
        runner.job_due = lambda name: name == "steward"
        jobs = []
        runner.run_job = lambda name: jobs.append(name) or "done"
        with mock.patch.object(runner, "remote_base_sha", return_value=current), \
                mock.patch.object(runner, "pr_moves_ok", return_value=False), \
                mock.patch.object(ht.lane_land, "git",
                                  return_value=mock.Mock(returncode=0, stdout="", stderr="")), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(runner.tick(), 0)
        self.assert_tick_base_move_recorded(accepted, current)
        self.assertEqual(jobs, ["steward"])

    def test_unaccepted_base_move_still_reaches_a_queued_retro(self):
        runner = self.runner(FakeGitHub([]))
        accepted, current = self.seed_unaccepted_base_move(runner)
        retro = ht.State(runner.retro_paths.state)
        retro.data["queue"] = [{"task": "R-90", "archive": "/archive/R-90"}]
        retro.data["current"] = None
        retro.save()
        runner.schedules_idle = lambda: True
        consumed = []

        def run_retro():
            queued = ht.State(runner.retro_paths.state)
            consumed.append(queued.data["queue"].pop(0)["task"])
            queued.save()
            return "done"

        runner.run_retro = run_retro
        with mock.patch.object(runner, "remote_base_sha", return_value=current), \
                mock.patch.object(runner, "pr_moves_ok", return_value=False), \
                mock.patch.object(ht.lane_land, "git",
                                  return_value=mock.Mock(returncode=0, stdout="", stderr="")), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(runner.tick(), 0)
        self.assert_tick_base_move_recorded(accepted, current)
        self.assertEqual(consumed, ["R-90"])
        self.assertEqual(ht.State(runner.retro_paths.state).data["queue"], [])

    def test_main_tick_reloads_a_forced_stale_view_at_the_real_entry(self):
        initial = ht.State(self.paths.state)
        initial.data["winner"] = {"value": 1}
        initial.save()
        attempted = threading.Event()
        continue_lock = threading.Event()
        errors = []
        seen = []
        real_lock = ht.writer_lock

        @contextlib.contextmanager
        def barrier_lock(paths):
            if threading.current_thread().name == "stale-main-tick" and not paths.prefix:
                attempted.set()
                self.wait_for(continue_lock, "stale main tick did not resume before the deadline")
            with real_lock(paths) as admitted:
                yield admitted

        def refresh(runner):
            seen.append(("refresh", dict(runner.state.data["winner"])))

        def tick_locked(runner, _max_items=None):
            if runner.intake:
                return 0
            runner.refresh_clone()
            runner.state.data.setdefault("winner", {})["tick"] = "tick"
            runner.state.save()
            seen.append(("last-save", dict(json.loads(self.paths.state.read_text())["winner"])))
            return 0

        def commit_job(runner, _name):
            runner.state.data.setdefault("winner", {})["job"] = "job"
            runner.state.save()
            return "done"

        def invoke_tick():
            try:
                with mock.patch.object(ht, "writer_lock", barrier_lock), \
                        mock.patch.object(ht.Runner, "_tick_locked", tick_locked), \
                        mock.patch.object(ht.Runner, "refresh_clone", refresh), \
                        mock.patch.object(ht.Runner, "run_job", commit_job), \
                        mock.patch("sys.stdout", new=io.StringIO()):
                    errors.append(ht.main(["tick"], home=self.home))
            except BaseException as exc:  # re-raised by the parent assertion
                errors.append(exc)

        thread = threading.Thread(target=invoke_tick, name="stale-main-tick")
        thread.start()
        self.wait_for(attempted, "main tick did not pause before admission")
        with mock.patch.object(ht.Runner, "refresh_clone", return_value=None), \
                mock.patch.object(ht.Runner, "run_job", commit_job), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["run-job", "steward"], home=self.home), 0)
        continue_lock.set()
        thread.join(5)
        self.assertFalse(thread.is_alive(), "main tick remained alive after the resume deadline")
        self.assertEqual(errors, [0])
        saved = json.loads(self.paths.state.read_text())
        self.assertEqual(saved["winner"], {"value": 1, "job": "job", "tick": "tick"})
        self.assertEqual(seen, [
            ("refresh", {"value": 1, "job": "job"}),
            ("last-save", {"value": 1, "job": "job", "tick": "tick"}),
        ])

    def test_manual_issue_and_job_reload_after_a_forced_pre_attempt_barrier(self):
        real_lock = ht.writer_lock
        for argv in (["run-issue", "17"], ["run-job", "steward"]):
            with self.subTest(argv=argv):
                initial = ht.State(self.paths.state)
                initial.data = {"attempts": {}, "merging": {}, "parked": {}, "jobs": {}, "history": [],
                                "current": None, "archive_sessions": {}, "archive_holds": {}}
                initial.save()
                attempted = threading.Event()
                continue_lock = threading.Event()
                errors = []

                @contextlib.contextmanager
                def barrier_lock(paths):
                    if threading.current_thread().name == "manual-stale":
                        attempted.set()
                        self.wait_for(continue_lock, "manual stale contender did not resume before the deadline")
                    with real_lock(paths) as admitted:
                        yield admitted

                def action(runner, _arg):
                    seen = runner.state.data["winner"]
                    runner.state.data["manual"] = seen
                    runner.state.save()
                    return "done"

                def invoke():
                    try:
                        with mock.patch.object(ht, "writer_lock", barrier_lock), \
                                mock.patch.object(ht.Runner, "refresh_clone", return_value=None), \
                                mock.patch.object(ht.Runner, "work", action), \
                                mock.patch.object(ht.Runner, "run_job", action), \
                                mock.patch("sys.stdout", new=io.StringIO()):
                            errors.append(ht.main(argv, home=self.home))
                    except BaseException as exc:  # re-raised by the parent assertion
                        errors.append(exc)

                thread = threading.Thread(target=invoke, name="manual-stale")
                thread.start()
                self.wait_for(attempted, "manual contender did not pause before admission")
                with ht.writer_lock(self.paths):
                    disk = ht.State(self.paths.state)
                    disk.data["winner"] = "committed"
                    disk.save()
                continue_lock.set()
                thread.join(5)
                self.assertFalse(thread.is_alive(), "manual contender remained alive after the resume deadline")
                self.assertEqual(errors, [0])
                saved = json.loads(self.paths.state.read_text())
                self.assertEqual((saved["winner"], saved["manual"]), ("committed", "committed"))

    def test_manual_job_refusal_retry_preserves_unchanged_state(self):
        value = ht.State._empty_data()
        value["marker"] = "first"
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        self.paths.state.write_text(json.dumps(value))
        with self.held_lock():
            with mock.patch.object(ht, "Runner", side_effect=AssertionError("constructed")), \
                    mock.patch("sys.stdout", new=io.StringIO()) as out:
                self.assertEqual(ht.main(["run-job", "steward"], home=self.home), 1)
            self.assertEqual(out.getvalue(), "another runner writer is active; run-job refused\n")
        with mock.patch.object(ht.Runner, "refresh_clone", return_value=None), \
                mock.patch.object(ht.Runner, "run_job", return_value="done"), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["run-job", "steward"], home=self.home), 0)
        self.assertEqual(json.loads(self.paths.state.read_text()), value)

    def test_manual_preview_busy_has_no_read_and_free_twin_renders_once(self):
        with self.held_lock():
            before = self.snapshot()
            with mock.patch.object(ht, "GitHub") as github, \
                    mock.patch.object(ht, "render_prompt", side_effect=AssertionError("rendered")), \
                    mock.patch("sys.stdout", new=io.StringIO()):
                self.assertEqual(ht.main(["run-issue", "13", "--dry-run"], home=self.home), 1)
            github.return_value.issue.assert_not_called()
            self.assertEqual(self.snapshot(), before)

        gh = FakeGitHub([t.issue(13)])
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        self.paths.state.write_text(json.dumps({"history": []}))
        (self.paths.state_dir / "workflow-base.json").write_text(json.dumps({"main": "a" * 40}))
        for root, text in ((self.paths.root / "archive", "archive"), (self.paths.work, "work")):
            root.mkdir(parents=True, exist_ok=True)
            (root / "sentinel").write_text(text)
        before = self.product_snapshot()
        remote_calls = list(gh.calls)
        with mock.patch.object(ht, "GitHub", return_value=gh), \
                mock.patch.object(ht, "render_prompt", return_value="rendered") as render, \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["run-issue", "13", "--dry-run"], home=self.home), 0)
        render.assert_called_once()
        self.assertEqual(self.product_snapshot(), before)
        self.assertEqual(gh.calls, remote_calls)

    def test_status_while_held_is_unlocked_and_byte_read_only(self):
        state = ht.State(self.paths.state)
        state.data["history"] = [{"issue": 1, "outcome": "done", "detail": "saved", "at": ht.iso()}]
        state.save()
        gh = FakeGitHub([t.issue(4)])
        for argv in (["status"], ["status", "--json"]):
            with self.subTest(argv=argv), self.held_lock():
                before = self.snapshot()
                with mock.patch.object(ht, "writer_lock", side_effect=AssertionError("acquired")), \
                        mock.patch.object(ht, "GitHub", return_value=gh), \
                        mock.patch.object(ht, "claude_logged_in", return_value=True), \
                        mock.patch("sys.stdout", new=io.StringIO()) as out:
                    self.assertEqual(ht.main(argv, home=self.home), 0)
                self.assertTrue(out.getvalue())
                self.assertEqual(self.snapshot(), before)

    def test_pause_resume_while_held_only_changes_the_emergency_marker(self):
        with self.held_lock():
            self.assertFalse(self.can_acquire(self.paths.lock))
            with mock.patch.object(ht, "writer_lock", side_effect=AssertionError("acquired")), \
                    mock.patch("sys.stdout", new=io.StringIO()):
                self.assertEqual(ht.main(["pause"], home=self.home), 0)
                self.assertTrue(self.paths.paused.is_file())
                self.assertEqual(ht.main(["resume"], home=self.home), 0)
                self.assertFalse(self.paths.paused.exists())
            self.assertFalse(self.can_acquire(self.paths.lock))

    def test_producer_lock_sites_have_scheduled_manual_and_unlocked_twins(self):
        sequence = iter(range(60, 80))

        def run_case(kind, mode, admitted):
            n = next(sequence)
            name = "steward" if mode == "manual" else "researcher"
            gh = FakeGitHub([t.issue(n)] if kind == "request" else [])
            runner = self.runner(gh, {"state": "done", "summary": "probe"})
            runner.refresh_clone = lambda: None
            runner.preflight = lambda: True
            visits = []

            def probe(site, path, args):
                visits.append((site, str(path), tuple(args), self.can_acquire(self.paths.lock)))

            launch = runner.launch
            runner.launch = lambda *args: probe("launch", Path(args[1]), args) or launch(*args)
            archive = runner.archive_evidence
            runner.archive_evidence = lambda *args, **kwargs: (
                probe("archive", Path(kwargs.get("tree") or runner.paths.worktree(args[0])),
                      tuple(args) + tuple(sorted(kwargs.items()))), archive(*args, **kwargs))[1]
            save = runner.state.save

            def save_spy():
                probe("save", runner.paths.state, ("state",))
                return save()

            runner.state.save = save_spy
            real_post = ht.post_update

            def post_spy(gh_arg, repo, issue_number, kind_name, body, media=None):
                if kind_name == "pickup":
                    probe("pickup", runner.paths.worktree(issue_number), (repo, issue_number, kind_name))
                return real_post(gh_arg, repo, issue_number, kind_name, body, media)

            if kind == "request":
                action = lambda: runner.work(n)
            else:
                action = lambda: runner.run_job(name)

            with mock.patch.object(ht, "post_update", side_effect=post_spy), \
                    mock.patch("sys.stdout", new=io.StringIO()):
                if not admitted:
                    action()
                elif kind == "request" and mode == "scheduled":
                    runner.check_base = lambda *_a, **_k: True
                    runner.schedules_idle = lambda: False
                    self.assertEqual(runner.tick(max_items=1), 0)
                elif kind == "job" and mode == "scheduled":
                    runner.check_base = lambda *_a, **_k: True
                    runner.schedules_idle = lambda: True
                    runner.run_retro = lambda: False
                    runner.check_regressions = lambda: False
                    runner.job_due = lambda job: job == name
                    self.assertEqual(runner.tick(max_items=1), 0)
                else:
                    command = ["run-issue", str(n)] if kind == "request" else ["run-job", name]
                    with mock.patch.object(ht, "Runner", return_value=runner), \
                            mock.patch.object(ht, "GitHub", return_value=gh):
                        self.assertEqual(ht.main(command, home=self.home), 0)

            self.assertTrue(visits, (kind, mode, admitted))
            self.assertEqual({free for *_site, free in visits}, {not admitted}, (kind, mode))
            self.assertTrue(any(site == "launch" for site, *_rest in visits), (kind, mode))
            self.assertTrue(any(site == "archive" for site, *_rest in visits), (kind, mode))
            self.assertTrue(any(site == "save" for site, *_rest in visits), (kind, mode))
            if kind == "request":
                self.assertTrue(any(site == "pickup" for site, *_rest in visits), (kind, mode))

        for kind in ("request", "job"):
            for mode in ("scheduled", "manual"):
                for admitted in (False, True):
                    with self.subTest(kind=kind, mode=mode, admitted=admitted):
                        run_case(kind, mode, admitted)

    def test_retro_competes_with_archive_refusal_then_fresh_retry(self):
        archive = self.paths.root / "archive" / "request-new"
        digest = archive / "retro" / "new.json"
        digest.parent.mkdir(parents=True, exist_ok=True)
        digest.write_text(json.dumps({"triggers": [{"id": "guard"}]}))
        for producer in (["run-issue", "31"], ["run-job", "steward"]):
            for ending in ("done", "requeue"):
                with self.subTest(producer=producer, ending=ending):
                    runner = self.runner(FakeGitHub([]))
                    retro = ht.State(runner.retro_paths.state)
                    current = {"task": "old", "archive": "/old"}
                    retro.data["queue"] = [current, {"task": "sibling", "archive": "/sibling"}]
                    retro.data["current"] = None
                    retro.data["done"] = []
                    retro.save()

                    def enqueue(owner, _argument):
                        return "queued" if owner.enqueue_retro(archive, "new") else "not-queued"

                    with ht.writer_lock(self.paths):
                        held = ht.State(runner.retro_paths.state)
                        self.assertEqual(held.data["queue"].pop(0), current)
                        held.data["current"] = current
                        held.save()
                        with mock.patch.object(ht.Runner, "refresh_clone", return_value=None), \
                                mock.patch.object(ht.Runner, "work", enqueue), \
                                mock.patch.object(ht.Runner, "run_job", enqueue), \
                                mock.patch("sys.stdout", new=io.StringIO()) as out:
                            outcome = ht.main(producer, home=self.home)
                            busy_output = out.getvalue()
                        held.data["current"] = None
                        if ending == "done":
                            held.data["done"] = [current]
                        else:
                            held.data["queue"].insert(0, current)
                        held.save()
                    self.assertEqual(outcome, 1)
                    self.assertEqual(busy_output,
                                     f"another runner writer is active; {producer[0]} refused\n")
                    saved_after_contender = ht.State(runner.retro_paths.state).data
                    self.assertEqual([item["task"] for item in saved_after_contender["queue"]],
                                     ["sibling"] if ending == "done" else ["old", "sibling"])
                    self.assertEqual([item["task"] for item in saved_after_contender["done"]],
                                     ["old"] if ending == "done" else [])

                    with mock.patch.object(ht.Runner, "refresh_clone", return_value=None), \
                            mock.patch.object(ht.Runner, "work", enqueue), \
                            mock.patch.object(ht.Runner, "run_job", enqueue), \
                            mock.patch("sys.stdout", new=io.StringIO()):
                        self.assertEqual(ht.main(producer, home=self.home), 0)
                    saved = ht.State(runner.retro_paths.state).data
                    expected = ["old", "sibling", "new"] if ending == "requeue" else ["sibling", "new"]
                    self.assertEqual([item["task"] for item in saved["queue"]], expected)
                    self.assertEqual([item["task"] for item in saved["done"]],
                                     ["old"] if ending == "done" else [])
                    self.assertIsNone(saved["current"])

    def test_manual_busy_job_pause_short_circuit_is_after_admission(self):
        self.paths.config_dir.mkdir(parents=True, exist_ok=True)
        self.paths.paused.write_text("paused\n")
        with mock.patch.object(ht.Runner, "__init__", side_effect=AssertionError("constructed")):
            with mock.patch("sys.stdout", new=io.StringIO()) as out:
                self.assertEqual(ht.main(["run-job", "steward"], home=self.home), 0)
        self.assertEqual(out.getvalue(), "paused\n")
        self.assertEqual(self.paths.paused.read_text(), "paused\n")

    def test_nested_lock_order_outer_then_verified_and_landings(self):
        outer = []
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        accepted = "a" * 40
        head = "b" * 40
        self.paths.state_dir.joinpath("workflow-base.json").write_text(json.dumps({"main": accepted, "other": "keep"}))
        self.pause_files(accepted)

        def verify(_base, _expected, _head):
            outer.append(self.can_acquire(self.paths.lock))
            outer.append(self.can_acquire(self.paths.state_dir / "ack.lock"))
            return True, [{"pr": 7, "contexts": ["pr-checks"]}], ""

        with mock.patch.object(ht.Runner, "remote_base_sha", return_value=head), \
                mock.patch.object(ht.Runner, "verify_pr_range", side_effect=verify), \
                mock.patch("sys.stdin") as stdin, mock.patch("sys.stdout", new=io.StringIO()):
            stdin.isatty.return_value = True
            self.assertEqual(ht.main(["ack-verified"], home=self.home), 0)
        self.assertEqual(outer, [False, False])

        runner = self.runner(FakeGitHub([]))
        inner = []
        with ht.writer_lock(self.paths):
            with runner.landings_guard():
                inner.append(self.can_acquire(self.paths.lock))
                inner.append(self.can_acquire(self.paths.state_dir / "landings.lock"))
        self.assertEqual(inner, [False, False])

    def test_verified_nested_lock_has_unlocked_and_admitted_twins(self):
        for admitted in (False, True):
            with self.subTest(admitted=admitted):
                runner = self.runner(FakeGitHub([]))
                accepted = "a" * 40
                head = "b" * 40
                runner.base_record().parent.mkdir(parents=True, exist_ok=True)
                runner.base_record().write_text(json.dumps({"main": accepted}))
                self.pause_files(accepted)
                visits = []

                def verify(_base, _expected, _head):
                    visits.append((self.can_acquire(self.paths.lock),
                                   self.can_acquire(self.paths.state_dir / "ack.lock")))
                    return True, [{"pr": 4, "contexts": ["pr-checks"]}], ""

                with mock.patch.object(runner, "remote_base_sha", return_value=head), \
                        mock.patch.object(runner, "verify_pr_range", side_effect=verify):
                    if admitted:
                        with ht.writer_lock(self.paths) as outer:
                            self.assertTrue(outer)
                            self.assertTrue(runner.ack_verified()["ok"])
                    else:
                        self.assertTrue(runner.ack_verified()["ok"])
                self.assertEqual(visits, [(not admitted, False)])

    def test_outer_lock_reaches_merging_parked_requeue_and_recover_twins(self):
        for admitted in (False, True):
            with self.subTest(admitted=admitted):
                n = 80 if admitted else 81
                merged = f"https://github.com/SFenton/native-home/pull/{n + 100}"
                parked = f"https://github.com/SFenton/native-home/pull/{n + 200}"
                reply_n, lost_n = n + 2, n + 4
                gh = FakeGitHub([
                    t.issue(n, labels=["Merging"]),
                    t.issue(n + 1, labels=["Needs Decision"]),
                    t.issue(reply_n, labels=["Blocked"]),
                    t.issue(lost_n, labels=["In Progress"]),
                ])
                gh.pulls[merged] = {"state": "MERGED", "labels": [], "url": merged}
                gh.pulls[parked] = {"state": "MERGED", "labels": [], "url": parked}
                gh.comment_store[reply_n] = [
                    {"body": ht.marker(reply_n, "blocked"), "created_at": "2026-10-13T10:00:00Z",
                     "user": {"login": "SFenton"}},
                    {"id": n + 500, "body": "/retry", "created_at": "2026-10-13T11:00:00Z",
                     "user": {"login": "SFenton"}},
                ]
                runner = self.runner(gh)
                runner.state.data["merging"] = {}
                runner.state.data["parked"] = {}
                status = {"state": "done", "summary": "locked transition"}
                runner.state.data["merging"][str(n)] = {"pr": merged, "status": status, "since": 0}
                runner.state.data["parked"][str(n + 1)] = {"pr": parked, "status": status, "since": 0}
                visits = []
                real_pull = gh.pull
                real_labels = gh.edit_labels

                def pull(url):
                    visits.append(("pull", url, self.can_acquire(self.paths.lock)))
                    return real_pull(url)

                def labels(repo, issue_number, add=(), remove=()):
                    visits.append(("labels", issue_number, tuple(add), tuple(remove),
                                   self.can_acquire(self.paths.lock)))
                    return real_labels(repo, issue_number, add, remove)

                gh.pull = pull
                gh.edit_labels = labels

                def run():
                    runner.check_merging()
                    runner.check_parked()
                    runner.requeue()
                    runner.recover()

                with mock.patch("sys.stdout", new=io.StringIO()):
                    if admitted:
                        with ht.writer_lock(self.paths) as outer:
                            self.assertTrue(outer)
                            run()
                    else:
                        run()
                self.assertTrue(visits)
                self.assertEqual({visit[-1] for visit in visits}, {not admitted})
                pulled = [visit[1] for visit in visits if visit[0] == "pull"]
                self.assertEqual(pulled, [merged, parked])
                labelled = [visit[1] for visit in visits if visit[0] == "labels"]
                self.assertIn(reply_n, labelled)
                self.assertIn(lost_n, labelled)

    def test_workflow_finish_initial_and_stored_retry_observe_the_lock_without_relanding(self):
        for admitted in (False, True):
            for stored in (False, True):
                with self.subTest(admitted=admitted, stored=stored):
                    n = 90 + admitted * 2 + stored
                    lane = f"agents/workflow-{n}"
                    gh = FakeGitHub([t.issue(n, labels=["Workflow", "In Progress"])])
                    runner = self.runner(gh)
                    status = {"state": "done", "summary": "workflow complete", "lanes": [lane]}
                    visits = []
                    real_post = ht.post_update

                    def post(gh_arg, repo, issue_number, kind, body, media=None):
                        visits.append(("post", issue_number, kind, self.can_acquire(self.paths.lock)))
                        return real_post(gh_arg, repo, issue_number, kind, body, media)

                    if stored:
                        tree = self.paths.worktree(n)
                        tree.mkdir(parents=True, exist_ok=True)
                        label = runner._archive_label(n)
                        runner.state.data.setdefault("lanes", {})[str(n)] = {lane: "merged"}
                        runner.state.data["archive_sessions"][label] = {
                            "name": label, "session": f"stored-{n}", "path": str(tree),
                        }
                        runner.state.data["archive_holds"][label] = {
                            "name": label, "path": str(tree.relative_to(self.paths.root)),
                            "reason": "sidecar_archive_io", "since": ht.iso(),
                            "finish": {"kind": "workflow", "status": status},
                        }
                        runner.state.save()
                    else:
                        def landing(_lane, _base, clone, **kwargs):
                            visits.append(("landing", _lane, tuple(sorted(kwargs)), self.can_acquire(self.paths.lock)))
                            return {"merge": "d" * 40, "parent": "a" * 40, "lane": _lane}

                        runner.check_base = lambda *_a, **_k: True
                        runner.session_lanes = lambda *_a, **_k: [lane]
                        runner.lane_refs = lambda: {lane: "c" * 40}
                        runner.landings_file().parent.mkdir(parents=True, exist_ok=True)
                        runner.landings_file().write_text("[]")
                        save_landings = runner.save_landings

                        def save_spy(data):
                            visits.append(("landings-write", runner.landings_file(), tuple(data),
                                           self.can_acquire(self.paths.lock),
                                           self.can_acquire(self.paths.state_dir / "landings.lock")))
                            return save_landings(data)

                    def run():
                        if stored:
                            runner.recover()
                        else:
                            runner.finish_workflow(n, status, self.paths.worktree(n))

                    patches = [
                        mock.patch.object(ht, "post_update", side_effect=post),
                        mock.patch("sys.stdout", new=io.StringIO()),
                    ]
                    if stored:
                        patches.append(mock.patch.object(runner, "land_lanes",
                                                         side_effect=AssertionError("stored retry re-landed")))
                    else:
                        patches.extend([mock.patch.object(ht.lane_land, "land", side_effect=landing),
                                        mock.patch.object(runner, "save_landings", side_effect=save_spy)])
                    with contextlib.ExitStack() as stack:
                        for patcher in patches:
                            stack.enter_context(patcher)
                        if admitted:
                            with ht.writer_lock(self.paths) as outer:
                                self.assertTrue(outer)
                                run()
                        else:
                            run()
                    self.assertTrue(visits)
                    self.assertEqual({visit[-1] for visit in visits if visit[0] != "landings-write"},
                                     {not admitted})
                    self.assertEqual(bool([visit for visit in visits if visit[0] == "landing"]), not stored)
                    self.assertTrue(any(visit[0] == "post" and visit[2] == "resolution" for visit in visits))
                    writes = [visit for visit in visits if visit[0] == "landings-write"]
                    self.assertEqual(bool(writes), not stored)
                    if writes:
                        self.assertEqual({visit[-2] for visit in writes}, {not admitted})
                        self.assertEqual({visit[-1] for visit in writes}, {False})

    def test_five_drop_callers_probe_real_removal_and_request_staging(self):
        sidecar = t.ArchiveSidecarTests
        self.seed_sidecar = sidecar.seed_sidecar.__get__(self)
        self.command_run = sidecar.command_run.__get__(self)
        self.launch = sidecar.launch.__get__(self)
        self.retro_item = sidecar.retro_item.__get__(self)
        self.seed_job_identity = sidecar.seed_job_identity.__get__(self)
        self.retro_runner = sidecar.retro_runner.__get__(self)

        def exercise(site, admitted):
            visits = []
            runner = ht.Runner(self.cfg, self.paths, FakeGitHub([]), run=self.command_run(),
                               launch=self.launch(seed=site in ("job_final", "retro_final")))
            runner.preflight = lambda: True
            real_drop = runner._drop_worktree

            def drop(path, clone):
                visits.append(("drop", str(path), clone, self.can_acquire(self.paths.lock)))
                return real_drop(path, clone)

            runner._drop_worktree = drop
            if site == "request":
                self.seed_sidecar(self.paths.worktree(90))
                snapshot = self.paths.request_snapshot(90)
                snapshot.parent.mkdir(parents=True, exist_ok=True)
                snapshot.write_text(json.dumps({"number": 90}))
                staged = self.paths.work / "90"
                staged.mkdir(parents=True, exist_ok=True)
                (staged / "queued").write_text("work")
            elif site == "job_pre":
                self.seed_job_identity(runner, archive_name="job-steward-old")
                self.seed_sidecar(self.paths.worktrees / "job-steward")
            elif site == "retro_pre":
                item = self.retro_item("R-90")
                runner = self.retro_runner([item], [{**item, "archive_name": "retro-request-90",
                                                     "archive_session": "retro-old"}])
                runner._drop_worktree = drop
                runner.launch = self.launch(seed=True)
                self.seed_sidecar(self.paths.worktrees / "retro-R-90")
            elif site == "retro_final":
                item = self.retro_item("R-90")
                runner = self.retro_runner([item])
                runner._drop_worktree = drop
                runner.launch = self.launch(seed=True)

            real_rmtree = shutil.rmtree
            real_unlink = Path.unlink

            def rmtree(path, *args, **kwargs):
                target = Path(path)
                if target == self.paths.work / "90":
                    visits.append(("staging-delete", str(target), tuple(args),
                                   self.can_acquire(self.paths.lock)))
                return real_rmtree(path, *args, **kwargs)

            def unlink(path, *args, **kwargs):
                if site == "request" and path == self.paths.request_snapshot(90):
                    visits.append(("snapshot-delete", str(path), tuple(args),
                                   self.can_acquire(self.paths.lock)))
                return real_unlink(path, *args, **kwargs)

            def run():
                if site == "request":
                    self.assertTrue(runner.cleanup(90))
                elif site.startswith("job_"):
                    runner.run_job("steward")
                else:
                    runner.run_retro()

            with mock.patch.object(shutil, "rmtree", side_effect=rmtree), \
                    mock.patch.object(Path, "unlink", autospec=True, side_effect=unlink), \
                    mock.patch("sys.stdout", new=io.StringIO()):
                if admitted:
                    with ht.writer_lock(self.paths) as outer:
                        self.assertTrue(outer)
                        run()
                else:
                    run()
            drops = [visit for visit in visits if visit[0] == "drop"]
            self.assertTrue(drops, site)
            self.assertEqual({visit[-1] for visit in drops}, {not admitted})
            if site == "request":
                self.assertTrue(any(visit[0] == "staging-delete" for visit in visits))
                self.assertTrue(any(visit[0] == "snapshot-delete" for visit in visits))
                self.assertFalse(snapshot.exists())
                self.assertFalse(staged.exists())

        for site in ("request", "job_pre", "job_final", "retro_pre", "retro_final"):
            for admitted in (False, True):
                with self.subTest(site=site, admitted=admitted):
                    exercise(site, admitted)

    def test_request_undo_probes_tampered_and_stray_effects_with_lock_twins(self):
        for admitted in (False, True):
            for kind in ("tampered", "stray"):
                with self.subTest(admitted=admitted, kind=kind):
                    n = 100 + admitted * 2 + (kind == "stray")
                    pr = f"https://github.com/SFenton/native-home/pull/{n + 500}"
                    gh = FakeGitHub([t.issue(n)])
                    gh.branch_pull_list = [{"url": pr, "state": "OPEN", "labels": []}]
                    runner = self.runner(gh, {"state": "done", "summary": "unsafe", "pr": pr})
                    visits = []
                    launch = runner.launch
                    real_branch_pulls = gh.branch_pulls
                    real_disarm = gh.disarm_pull
                    real_label = gh.label_pull

                    def launch_spy(*args):
                        result = launch(*args)
                        if kind == "tampered":
                            runner.guard_tampered = True
                        else:
                            runner.t3_stray = True
                        return result

                    def branch_pulls(repo, branch):
                        visits.append(("branch-pulls", branch, self.can_acquire(self.paths.lock)))
                        return real_branch_pulls(repo, branch)

                    def disarm(url):
                        visits.append(("disarm", url, self.can_acquire(self.paths.lock)))
                        return real_disarm(url)

                    def label(url, add="", remove=""):
                        visits.append(("label", url, add, remove, self.can_acquire(self.paths.lock)))
                        return real_label(url, add, remove)

                    runner.launch = launch_spy
                    gh.branch_pulls = branch_pulls
                    gh.disarm_pull = disarm
                    gh.label_pull = label
                    with mock.patch("sys.stdout", new=io.StringIO()):
                        if admitted:
                            with ht.writer_lock(self.paths) as outer:
                                self.assertTrue(outer)
                                self.assertEqual(runner.work(n), "blocked")
                        else:
                            self.assertEqual(runner.work(n), "blocked")
                    self.assertTrue([visit for visit in visits if visit[0] == "branch-pulls"])
                    self.assertTrue([visit for visit in visits if visit[0] == "disarm"])
                    self.assertTrue([visit for visit in visits if visit[0] == "label"])
                    self.assertEqual({visit[-1] for visit in visits}, {not admitted})

    def test_real_due_revert_and_landing_keep_outer_then_inner_lock_order(self):
        for admitted in (False, True):
            with self.subTest(admitted=admitted):
                runner = self.runner(FakeGitHub([]))
                accepted = "a" * 40
                merge = "b" * 40
                revert = "c" * 40
                branch = f"agents/revert-{merge[:12]}"
                landing = {
                    "lane": "agents/example", "merge_sha": merge, "base": "main",
                    "landed_at": "2020-01-01T00:00:00Z", "evaluated": None,
                    "metrics_before": {"flows": 1, "metrics": {"tests": 1}},
                }
                runner.save_landings([landing])
                runner.base_record().parent.mkdir(parents=True, exist_ok=True)
                runner.base_record().write_text(json.dumps({"main": accepted}))
                runner.cfg["revert_flows"] = 1
                runner.cfg["revert_days"] = 1
                runner.cfg["revert_min_flows"] = 1
                visits = []
                save_landings = runner.save_landings

                def git(_repo, *args, **kwargs):
                    visits.append(("git", tuple(args), self.can_acquire(self.paths.lock)))
                    stdout = ""
                    if "rev-parse" in args and "HEAD" in args:
                        stdout = revert
                    return ht.subprocess.CompletedProcess(list(args), 0, stdout, "")

                def land(lane_name, base, clone, **kwargs):
                    visits.append(("landing", lane_name, base, self.can_acquire(self.paths.lock)))
                    return {"merge": "d" * 40, "parent": accepted, "lane": lane_name}

                def save_spy(data):
                    visits.append(("inner-write", runner.landings_file(), self.can_acquire(self.paths.lock),
                                   self.can_acquire(self.paths.state_dir / "landings.lock")))
                    return save_landings(data)

                runner.check_base = lambda *_a, **_k: True
                runner.flow_records = lambda: {}
                after = {"flows": 1, "metrics": {"tests": 0, "duration": 2}}
                with mock.patch.object(ht.lane_land, "git", side_effect=git), \
                        mock.patch.object(ht.lane_land, "land", side_effect=land), \
                        mock.patch.object(runner, "save_landings", side_effect=save_spy), \
                        mock.patch.object(ht.retro_weekly, "flow_window", return_value=after), \
                        mock.patch.object(ht.retro_weekly, "revert_view", return_value=after["metrics"]), \
                        mock.patch.object(ht.retro_weekly, "regressions",
                                          return_value=[
                                              {"metric": "tests", "before": 1, "after": 0},
                                              {"metric": "duration", "before": 1, "after": 2},
                                          ]), \
                        mock.patch("sys.stdout", new=io.StringIO()):
                    if admitted:
                        with ht.writer_lock(self.paths) as outer:
                            self.assertTrue(outer)
                            self.assertTrue(runner.check_regressions())
                    else:
                        self.assertTrue(runner.check_regressions())
                self.assertTrue([visit for visit in visits if visit[0] == "git"])
                self.assertTrue([visit for visit in visits if visit[0] == "landing" and visit[1] == branch])
                inner = [visit for visit in visits if visit[0] == "inner-write"]
                self.assertTrue(inner)
                self.assertEqual({visit[-2] for visit in inner}, {not admitted})
                self.assertEqual({visit[-1] for visit in inner}, {False})
                effects = [visit for visit in visits if visit[0] in ("git", "landing")]
                self.assertEqual({visit[-1] for visit in effects}, {not admitted})

    def test_lock_releases_on_body_exception_and_io_error_is_not_busy(self):
        with mock.patch.object(ht.Runner, "_tick_locked", side_effect=RuntimeError("body")):
            with self.assertRaisesRegex(RuntimeError, "body"):
                ht.main(["tick"], home=self.home)
        self.assertTrue(self.can_acquire(self.paths.lock))

        out = io.StringIO()
        with mock.patch.object(ht, "State", side_effect=OSError("load failed")), \
                mock.patch("sys.stdout", new=out):
            with self.assertRaisesRegex(OSError, "load failed"):
                ht.main(["tick"], home=self.home)
        self.assertNotIn("another tick is running", out.getvalue())
        self.assertTrue(self.can_acquire(self.paths.lock))

    def test_job_with_no_lanes_drops_worktree_after_unaccepted_base_move(self):
        runner = self.runner(FakeGitHub([]), {"state": "done", "summary": "ok"})
        accepted, current = self.seed_unaccepted_base_move(runner)
        runner.preflight = lambda: True
        dropped = []
        runner._drop_worktree = lambda path, clone: dropped.append((path, clone))
        with mock.patch.object(runner, "remote_base_sha", return_value=current), \
                mock.patch.object(runner, "pr_moves_ok", return_value=False), \
                mock.patch.object(ht.lane_land, "git",
                                  return_value=mock.Mock(returncode=0, stdout="", stderr="")), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertFalse(runner.check_base("tick"))
            self.assertEqual(runner.run_job("steward"), "done")
        self.assert_tick_base_move_recorded(accepted, current)
        self.assertEqual(dropped, [(self.paths.worktrees / "job-steward", str(self.paths.clone))])

    def test_non_contention_flock_error_is_not_reported_busy(self):
        calls = 0
        real = fcntl.flock

        def fail_once(fd, operation):
            nonlocal calls
            calls += 1
            if calls == 1:
                raise OSError(errno.EPERM, "denied")
            return real(fd, operation)

        with mock.patch.object(fcntl, "flock", side_effect=fail_once), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            with self.assertRaises(OSError):
                ht.main(["tick"], home=self.home)
        self.assertEqual(out.getvalue(), "")

    def test_ack_base_merges_complete_map_and_preserves_unknown_entries(self):
        runner = self.runner(FakeGitHub([]))
        current = "b" * 40
        unknown = {"other": {"nested": ["keep"]}}
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        runner.base_record().write_text(json.dumps({**unknown, "main": "a" * 40}))
        pause, details = self.pause_files(current)
        with mock.patch.object(runner, "remote_base_sha", return_value=current), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(runner.ack_base(current), current)
        self.assertEqual(json.loads(runner.base_record().read_text()), {**unknown, "main": current})
        self.assertFalse(pause.exists())
        self.assertFalse(details.exists())

    def test_ack_verified_merges_complete_map_and_appends_once(self):
        runner = self.runner(FakeGitHub([]))
        accepted = "a" * 40
        head = "c" * 40
        log = self.paths.state_dir / "ack-log.jsonl"
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        log.write_text("old-prefix\n")
        runner.base_record().write_text(json.dumps({"main": accepted, "other": "keep"}))
        pause, details = self.pause_files(accepted)
        with mock.patch.object(runner, "remote_base_sha", side_effect=[head, head]), \
                mock.patch.object(runner, "verify_pr_range",
                                  return_value=(True, [{"pr": 3, "contexts": ["pr-checks"]}], "")):
            result = runner.ack_verified("agent")
        self.assertTrue(result["ok"])
        self.assertEqual(json.loads(runner.base_record().read_text()), {"main": head, "other": "keep"})
        lines = log.read_text().splitlines()
        self.assertEqual(lines[0], "old-prefix")
        self.assertEqual(len(lines), 2)
        self.assertEqual(json.loads(lines[1])["from"], accepted)
        self.assertEqual(json.loads(lines[1])["to"], head)
        self.assertFalse(pause.exists())
        self.assertFalse(details.exists())

    def test_check_vs_owner_ack_ack_first_refuses_tick_until_commit(self):
        accepted = "a" * 40
        head = "b" * 40
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        (self.paths.state_dir / "workflow-base.json").write_text(json.dumps({"main": accepted, "other": "keep"}))
        self.pause_files(accepted)
        details = self.paths.state_dir / "SELF_CHANGE_PAUSED.json"
        details.write_text(json.dumps({"base": "main", "sha": accepted, "latest": head,
                                       "moves": [{"sha": head, "expected": accepted,
                                                  "when": "test", "at": ht.iso()}]}))
        reached = threading.Event()
        finish = threading.Event()
        outcomes = []

        def remote(_runner, _base):
            reached.set()
            self.wait_for(finish, "owner acknowledgement did not resume before the deadline")
            return head

        def acknowledge():
            try:
                with mock.patch.object(ht.Runner, "remote_base_sha", new=remote), \
                        mock.patch("sys.stdin") as stdin, mock.patch("sys.stdout", new=io.StringIO()):
                    stdin.isatty.return_value = True
                    outcomes.append(ht.main(["ack-base", head], home=self.home))
            except BaseException as exc:  # re-raised by the parent assertion
                outcomes.append(exc)

        thread = threading.Thread(target=acknowledge)
        thread.start()
        self.wait_for(reached, "owner acknowledgement did not reach its base read")
        with mock.patch.object(ht, "Runner", side_effect=AssertionError("constructed")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(ht.main(["tick"], home=self.home), 0)
        self.assertEqual(out.getvalue(), "another tick is running\n")
        finish.set()
        thread.join(5)
        self.assertFalse(thread.is_alive(), "owner acknowledgement remained alive after the resume deadline")
        self.assertEqual(outcomes, [0])
        self.assertEqual(json.loads((self.paths.state_dir / "workflow-base.json").read_text()),
                         {"main": head, "other": "keep"})

    def test_check_vs_both_acks_check_first_refuses_ack_until_commit(self):
        for argv in (["ack-base", "b" * 40], ["ack-verified"]):
            with self.subTest(argv=argv):
                accepted = "a" * 40
                head = "b" * 40
                self.paths.state_dir.mkdir(parents=True, exist_ok=True)
                record = self.paths.state_dir / "workflow-base.json"
                record.write_text(json.dumps({"main": accepted, "other": "keep"}))
                self.pause_files(accepted)
                reached = threading.Event()
                finish = threading.Event()
                outcomes = []

                def locked(runner, _max_items=None):
                    if runner.intake:
                        return 0
                    reached.set()
                    self.wait_for(finish, "tick did not resume before the base-commit deadline")
                    self.assertTrue(runner.check_base("test"))
                    return 0

                def tick():
                    try:
                        with mock.patch.object(ht.Runner, "_tick_locked", new=locked), \
                                mock.patch.object(ht.Runner, "remote_base_sha", return_value=head), \
                                mock.patch.object(ht.Runner, "pr_moves_ok", return_value=True), \
                                mock.patch("sys.stdout", new=io.StringIO()):
                            outcomes.append(ht.main(["tick"], home=self.home))
                    except BaseException as exc:  # re-raised by the parent assertion
                        outcomes.append(exc)

                thread = threading.Thread(target=tick)
                thread.start()
                self.wait_for(reached, "tick did not reach its held base check")
                with mock.patch.object(ht, "Runner", side_effect=AssertionError("constructed")), \
                        mock.patch("sys.stdin") as stdin, mock.patch("sys.stdout", new=io.StringIO()) as out, \
                        mock.patch("sys.stderr", new=io.StringIO()):
                    stdin.isatty.return_value = True
                    self.assertEqual(ht.main(argv, home=self.home), 1)
                self.assertEqual(out.getvalue(), f"another runner writer is active; {argv[0]} refused\n")
                finish.set()
                thread.join(5)
                self.assertFalse(thread.is_alive(), "tick remained alive after the resume deadline")
                self.assertEqual(outcomes, [0])
                self.assertEqual(json.loads(record.read_text()), {"main": head, "other": "keep"})

    def test_check_vs_verified_ack_ack_first_refuses_tick_until_commit(self):
        accepted = "a" * 40
        head = "c" * 40
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        (self.paths.state_dir / "workflow-base.json").write_text(json.dumps({"main": accepted, "other": "keep"}))
        self.pause_files(accepted)
        reached = threading.Event()
        finish = threading.Event()
        outcomes = []

        def remote(_runner, _base):
            reached.set()
            self.wait_for(finish, "verified acknowledgement did not resume before the deadline")
            return head

        def acknowledge():
            try:
                with mock.patch.object(ht.Runner, "remote_base_sha", new=remote), \
                        mock.patch.object(ht.Runner, "verify_pr_range",
                                          return_value=(True, [{"pr": 3, "contexts": ["pr-checks"]}], "")), \
                        mock.patch("sys.stdout", new=io.StringIO()), mock.patch("sys.stderr", new=io.StringIO()):
                    outcomes.append(ht.main(["ack-verified"], home=self.home))
            except BaseException as exc:  # re-raised by the parent assertion
                outcomes.append(exc)

        thread = threading.Thread(target=acknowledge)
        thread.start()
        self.wait_for(reached, "verified acknowledgement did not reach its base read")
        with mock.patch.object(ht, "Runner", side_effect=AssertionError("constructed")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(ht.main(["tick"], home=self.home), 0)
        self.assertEqual(out.getvalue(), "another tick is running\n")
        finish.set()
        thread.join(5)
        self.assertFalse(thread.is_alive(), "verified acknowledgement remained alive after the resume deadline")
        self.assertEqual(outcomes, [0])
        self.assertEqual(json.loads((self.paths.state_dir / "workflow-base.json").read_text()),
                         {"main": head, "other": "keep"})

    def test_ack_reads_reject_unreadable_malformed_and_non_map_before_mutation(self):
        runner = self.runner(FakeGitHub([]))
        current = "b" * 40
        pause, details = self.pause_files(current)
        for kind in ("malformed", "list", "directory"):
            with self.subTest(kind=kind):
                if runner.base_record().is_dir():
                    shutil.rmtree(runner.base_record())
                elif runner.base_record().exists():
                    runner.base_record().unlink()
                if kind == "malformed":
                    runner.base_record().write_text("{")
                elif kind == "list":
                    runner.base_record().write_text("[]")
                else:
                    runner.base_record().mkdir(parents=True)
                before_pause = pause.read_bytes()
                before_details = details.read_bytes()
                with mock.patch.object(runner, "remote_base_sha", return_value=current):
                    with self.assertRaises(ht.TriageError):
                        runner.ack_base(current)
                self.assertEqual(pause.read_bytes(), before_pause)
                self.assertEqual(details.read_bytes(), before_details)
                self.assertFalse((self.paths.state_dir / "ack-log.jsonl").exists())

    def test_ack_verified_failed_read_preserves_map_pause_and_audit(self):
        runner = self.runner(FakeGitHub([]))
        accepted = "a" * 40
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        runner.base_record().write_text("{")
        pause, details = self.pause_files(accepted)
        log = self.paths.state_dir / "ack-log.jsonl"
        log.write_text("old\n")
        before = (runner.base_record().read_bytes(), pause.read_bytes(), details.read_bytes(), log.read_bytes())
        with self.assertRaises(ht.TriageError):
            runner.ack_verified("agent")
        after = (runner.base_record().read_bytes(), pause.read_bytes(), details.read_bytes(), log.read_bytes())
        self.assertEqual(after, before)

    def test_main_tick_malformed_base_halts_without_writes_and_next_tick_proceeds(self):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        state = ht.State(self.paths.state)
        state.data["sentinel"] = "keep"
        state.save()
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        record = self.paths.state_dir / "workflow-base.json"
        record.write_text("{")
        before = self.snapshot()
        before.pop(str(self.paths.lock.relative_to(self.home)), None)
        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.Runner, "refresh_clone", side_effect=AssertionError("refreshed")) as refresh, \
                mock.patch.object(ht.Runner, "check_base", side_effect=AssertionError("base move path reached")) as check, \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(ht.main(["tick"], home=self.home), 0)
        after = self.snapshot()
        after.pop(str(self.paths.lock.relative_to(self.home)), None)
        self.assertEqual(after, before)
        refresh.assert_not_called()
        check.assert_not_called()
        self.assertEqual(out.getvalue(),
                         "base record cannot be read; nothing was changed: cannot read workflow-base.json: malformed JSON\n")

        current = "b" * 40
        record.write_text(json.dumps({"main": current}))
        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.Runner, "remote_base_sha", return_value=current), \
                mock.patch.object(ht.Runner, "refresh_clone") as refresh, \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["tick", "--max-items", "0"], home=self.home), 0)
        refresh.assert_called_once_with()

    def test_post_session_and_landing_paths_share_the_malformed_base_refusal(self):
        runner = self.runner(FakeGitHub([]))
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        runner.base_record().write_text("[]")
        before = runner.base_record().read_bytes()
        with mock.patch.object(runner, "remote_base_sha", side_effect=AssertionError("remote read")), \
                mock.patch.object(runner, "session_lanes", side_effect=AssertionError("session lanes")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertFalse(runner.land_lanes({"lanes": ["agents/example"]}, "12"))
        self.assertEqual(out.getvalue(),
                         "base record cannot be read; nothing was changed: cannot read workflow-base.json: expected a map\n")

        with mock.patch.object(runner, "remote_base_sha", side_effect=AssertionError("remote read")), \
                mock.patch.object(ht.lane_land, "land", side_effect=AssertionError("landing")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(runner.land_lane("agents/example", "main", "12"), "paused")
        self.assertEqual(out.getvalue(),
                         "base record cannot be read; nothing was changed: cannot read workflow-base.json: expected a map\n")
        self.assertEqual(runner.base_record().read_bytes(), before)

    def test_ack_commands_refuse_malformed_base_without_mutation_or_busy_output(self):
        current = "b" * 40
        for argv, exit_code in ((["ack-base", current], 4), (["ack-verified"], 1)):
            with self.subTest(argv=argv):
                self.paths.state_dir.mkdir(parents=True, exist_ok=True)
                record = self.paths.state_dir / "workflow-base.json"
                record.write_text("{")
                pause, details = self.pause_files(current)
                before = self.snapshot()
                before.pop(str(self.paths.lock.relative_to(self.home)), None)
                with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                        mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                        mock.patch.object(ht.Runner, "remote_base_sha", return_value=current), \
                        mock.patch("sys.stdin") as stdin, \
                        mock.patch("sys.stdout", new=io.StringIO()) as out, \
                        mock.patch("sys.stderr", new=io.StringIO()) as err:
                    stdin.isatty.return_value = True
                    self.assertEqual(ht.main(argv, home=self.home), exit_code)
                after = self.snapshot()
                after.pop(str(self.paths.lock.relative_to(self.home)), None)
                self.assertEqual(after, before)
                self.assertNotIn("another runner writer is active", out.getvalue() + err.getvalue())
                self.assertNotIn("Traceback", out.getvalue() + err.getvalue())
                self.assertTrue(err.getvalue())
                self.assertTrue(pause.exists())
                self.assertTrue(details.exists())

    def test_check_base_refuses_failed_merge_read_without_rebaseline(self):
        runner = self.runner(FakeGitHub([]))
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        runner.base_record().write_text("{")
        pause = self.paths.state_dir / "SELF_CHANGE_PAUSED"
        with mock.patch.object(runner, "remote_base_sha", return_value="b" * 40), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertFalse(runner.check_base("test"))
        self.assertEqual(runner.base_record().read_text(), "{")
        self.assertFalse(pause.exists())
        self.assertEqual(out.getvalue(),
                         "base record cannot be read; nothing was changed: cannot read workflow-base.json: malformed JSON\n")

    def test_process_death_releases_outer_lock_and_fresh_client_sees_save(self):
        context = multiprocessing.get_context("fork")
        parent, child = context.Pipe()
        process = context.Process(target=lock_child, args=(str(self.home), child))
        process.start()
        child.close()
        try:
            self.assertTrue(parent.poll(5), "child did not enter the shared admission before the deadline")
            self.assertEqual(parent.recv(), "ready")
            self.assertFalse(self.can_acquire(self.paths.lock))
            self.assertEqual(json.loads(self.paths.state.read_text())["completed-save"], "yes")
            process.terminate()
            process.join(5)
            self.assertFalse(process.is_alive(), "process-death fixture did not exit before the deadline")
            self.assertTrue(process.exitcode is not None)
            with ht.writer_lock(self.paths) as admitted:
                self.assertTrue(admitted)
                self.assertEqual(json.loads(self.paths.state.read_text())["completed-save"], "yes")
        finally:
            parent.close()
            if process.is_alive():
                process.terminate()
                process.join(5)


if __name__ == "__main__":
    unittest.main()
