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


def lock_child(lock_name: str, state_name: str, connection) -> None:
    with open(lock_name, "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        Path(state_name).write_text("completed-save\n")
        connection.send("ready")
        connection.recv()


class RunnerLockTests(t.Base):
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

    def pause_files(self, sha: str) -> tuple:
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        pause = self.paths.state_dir / "SELF_CHANGE_PAUSED"
        details = self.paths.state_dir / "SELF_CHANGE_PAUSED.json"
        pause.write_text("pending\n")
        details.write_text(json.dumps({"base": "main", "sha": sha, "latest": sha, "moves": []}))
        return pause, details

    def test_shared_writer_admission_reaches_all_six_dispatches(self):
        probes = []
        calls = []

        def probe(site):
            probes.append((site, self.can_acquire(self.paths.lock)))

        class StateSpy:
            def save(self):
                probe("save")

        class RunnerSpy:
            def __init__(spy, cfg, paths, gh, dry_run=False, intake=None, **_kw):
                spy.intake = intake
                spy.state = StateSpy()
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

    def test_tick_manual_both_orders_reload_a_forced_stale_view(self):
        initial = ht.State(self.paths.state)
        initial.data["winner"] = {"value": 1}
        initial.save()
        first = ht.Runner(self.cfg, self.paths, FakeGitHub([]))
        second = ht.Runner(self.cfg, self.paths, FakeGitHub([]))
        attempted = threading.Event()
        continue_lock = threading.Event()
        errors = []
        real_lock = ht.writer_lock

        @contextlib.contextmanager
        def barrier_lock(paths):
            if threading.current_thread().name == "stale-contender":
                attempted.set()
                self.assertTrue(continue_lock.wait(5))
            with real_lock(paths) as admitted:
                yield admitted

        def commit(runner, key):
            def locked(_max_items=None):
                self.assertFalse(self.can_acquire(self.paths.lock))
                runner.state.data.setdefault("winner", {})[key] = key
                runner.state.save()
                return 0
            return locked

        first._tick_locked = commit(first, "first")
        second._tick_locked = commit(second, "second")

        def run_stale():
            try:
                second.tick()
            except BaseException as exc:  # re-raised by the parent assertion
                errors.append(exc)

        with mock.patch.object(ht, "writer_lock", barrier_lock):
            thread = threading.Thread(target=run_stale, name="stale-contender")
            thread.start()
            self.assertTrue(attempted.wait(5))
            self.assertEqual(first.tick(), 0)
            continue_lock.set()
            thread.join(5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        saved = json.loads(self.paths.state.read_text())
        self.assertEqual(saved["winner"], {"value": 1, "first": "first", "second": "second"})

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
                        self.assertTrue(continue_lock.wait(5))
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
                self.assertTrue(attempted.wait(5))
                with ht.writer_lock(self.paths):
                    disk = ht.State(self.paths.state)
                    disk.data["winner"] = "committed"
                    disk.save()
                continue_lock.set()
                thread.join(5)
                self.assertFalse(thread.is_alive())
                self.assertEqual(errors, [0])
                saved = json.loads(self.paths.state.read_text())
                self.assertEqual((saved["winner"], saved["manual"]), ("committed", "committed"))

    def test_tick_manual_preserve_disjoint_updates_after_refusal_retry(self):
        value = {"current": "first"}
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
        with mock.patch.object(ht, "GitHub", return_value=gh), \
                mock.patch.object(ht, "render_prompt", return_value="rendered") as render, \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["run-issue", "13", "--dry-run"], home=self.home), 0)
        render.assert_called_once()

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

    def test_retro_competes_with_archive_refusal_then_fresh_retry(self):
        runner = self.runner(FakeGitHub([]))
        archive = self.paths.root / "archive" / "request-new"
        digest = archive / "retro" / "new.json"
        digest.parent.mkdir(parents=True, exist_ok=True)
        digest.write_text(json.dumps({"triggers": [{"id": "guard"}]}))
        retro = ht.State(runner.retro_paths.state)
        retro.data["queue"] = [{"task": "old", "archive": "/old"},
                               {"task": "sibling", "archive": "/sibling"}]
        retro.save()

        with ht.writer_lock(self.paths):
            held = ht.State(runner.retro_paths.state)
            current = held.data["queue"].pop(0)
            held.data["current"] = current
            held.save()
            with mock.patch.object(ht, "Runner", side_effect=AssertionError("constructed")), \
                    mock.patch("sys.stdout", new=io.StringIO()) as out:
                self.assertEqual(ht.main(["run-issue", "31"], home=self.home), 1)
            self.assertEqual(out.getvalue(), "another runner writer is active; run-issue refused\n")
            held.data["current"] = None
            held.data["done"] = [current]
            held.save()

        def enqueue(owner, _number):
            return "queued" if owner.enqueue_retro(archive, "new") else "not-queued"

        with mock.patch.object(ht.Runner, "refresh_clone", return_value=None), \
                mock.patch.object(ht.Runner, "work", enqueue), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["run-issue", "31"], home=self.home), 0)
        saved = ht.State(runner.retro_paths.state).data
        self.assertEqual([item["task"] for item in saved["queue"]], ["sibling", "new"])
        self.assertEqual([item["task"] for item in saved["done"]], ["old"])
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
            self.assertTrue(finish.wait(5))
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
        self.assertTrue(reached.wait(5))
        with mock.patch.object(ht, "Runner", side_effect=AssertionError("constructed")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(ht.main(["tick"], home=self.home), 0)
        self.assertEqual(out.getvalue(), "another tick is running\n")
        finish.set()
        thread.join(5)
        self.assertFalse(thread.is_alive())
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

    def test_check_base_refuses_failed_merge_read_without_rebaseline(self):
        runner = self.runner(FakeGitHub([]))
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        runner.base_record().write_text("{")
        pause = self.paths.state_dir / "SELF_CHANGE_PAUSED"
        with mock.patch.object(runner, "remote_base_sha", return_value="b" * 40):
            with self.assertRaises(ht.TriageError):
                runner.check_base("test")
        self.assertEqual(runner.base_record().read_text(), "{")
        self.assertFalse(pause.exists())

    def test_process_death_releases_outer_lock_and_fresh_client_sees_save(self):
        state = self.paths.state_dir / "death.json"
        self.paths.state_dir.mkdir(parents=True, exist_ok=True)
        context = multiprocessing.get_context("fork")
        parent, child = context.Pipe()
        process = context.Process(target=lock_child, args=(str(self.paths.lock), str(state), child))
        process.start()
        child.close()
        try:
            self.assertTrue(parent.poll(5))
            self.assertEqual(parent.recv(), "ready")
            self.assertFalse(self.can_acquire(self.paths.lock))
            process.terminate()
            process.join(5)
            self.assertFalse(process.is_alive())
            self.assertTrue(process.exitcode is not None)
            with ht.writer_lock(self.paths) as admitted:
                self.assertTrue(admitted)
                self.assertEqual(state.read_text(), "completed-save\n")
        finally:
            parent.close()
            if process.is_alive():
                process.terminate()
                process.join(5)


if __name__ == "__main__":
    unittest.main()
