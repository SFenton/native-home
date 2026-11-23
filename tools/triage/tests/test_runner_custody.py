"""Load, admission, durable-save, containment and status tests for runner stores."""
from __future__ import annotations

import contextlib
import io
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import test_hass_triage as t

ht = t.ht
FakeGitHub = t.FakeGitHub


class StoreTestBase(t.Base):
    def write_raw(self, path: Path, value) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value if isinstance(value, str) else json.dumps(value))

    def legacy(self, **extra) -> dict:
        value = ht.State._empty_data()
        value.update(extra)
        return value

    def main_with(self, argv, cfg=None, gh=None):
        with mock.patch.object(ht, "load_config", return_value=cfg or self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh or FakeGitHub([])), \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            result = ht.main(argv, home=self.home)
        return result, out.getvalue(), err.getvalue()

    def logical_path(self, store: str) -> Path:
        return {
            "primary": self.paths.state,
            "nightly": ht.Paths(self.cfg, self.home, "nightly-").state,
            "retro": ht.Paths(self.cfg, self.home, "retro-").state,
        }[store]

    def quiet_tick_patches(self, events):
        return (
            mock.patch.object(ht.Runner, "readable_base_map",
                              side_effect=lambda: events.append("base-map") or {}),
            mock.patch.object(ht.Runner, "refresh_clone",
                              side_effect=lambda: events.append("refresh")),
            mock.patch.object(ht.Runner, "check_base",
                              side_effect=lambda _when: events.append("base") or True),
            mock.patch.object(ht.Runner, "check_ha_changes",
                              side_effect=lambda: events.append("ha")),
            mock.patch.object(ht.Runner, "check_merging",
                              side_effect=lambda: events.append("merging")),
            mock.patch.object(ht.Runner, "check_parked",
                              side_effect=lambda: events.append("parked")),
            mock.patch.object(ht.Runner, "requeue",
                              side_effect=lambda: events.append("requeue")),
            mock.patch.object(ht.Runner, "recover",
                              side_effect=lambda: events.append("recover")),
        )


class LoadAndMissingTests(StoreTestBase):
    def test_legacy_map_and_unknown_top_level_field_survive_a_save(self):
        opaque = {"version": ["not interpreted"], "nested": {"owner": "kept"}}
        self.write_raw(self.paths.state, self.legacy(
            history=[{"issue": 41, "outcome": "done"}],
            opaque_extension=opaque,
        ))

        state = ht.State(self.paths.state)
        self.assertTrue(state.writable)
        state.save()

        reopened = ht.State(self.paths.state)
        self.assertTrue(reopened.writable)
        self.assertEqual(reopened.data["opaque_extension"], opaque)
        self.assertEqual(reopened.data["history"][0]["outcome"], "done")

    def test_fresh_missing_store_is_observed_not_remembered_and_can_be_saved(self):
        path = self.home / "missing" / "state.json"
        state = ht.State(path)
        self.assertTrue(state.writable)
        self.assertEqual(state.read_result, {
            "kind": "not_found",
            "exists": "no",
            "installation": "unknown",
        })
        self.assertFalse(path.exists())

        state.data["opaque_extension"] = {"first": True}
        state.save()
        reopened = ht.State(path)
        self.assertEqual(reopened.read_result, {"kind": "loaded", "exists": "yes"})
        self.assertEqual(reopened.data["opaque_extension"], {"first": True})

    def test_read_parse_root_and_legacy_type_faults_refuse_without_rewriting(self):
        cases = ("read", "parse", "root", "type")
        for store in ("primary", "nightly", "retro"):
            path = self.logical_path(store)
            for kind in cases:
                with self.subTest(store=store, kind=kind):
                    if kind == "read":
                        self.write_raw(path, self.legacy())
                    elif kind == "parse":
                        self.write_raw(path, "{")
                    elif kind == "root":
                        self.write_raw(path, [])
                    else:
                        self.write_raw(path, self.legacy(jobs=[]))
                    before = path.read_bytes()
                    context = (
                        mock.patch.object(Path, "read_text", side_effect=OSError("synthetic"))
                        if kind == "read" else mock.patch.dict(os.environ, {}, clear=False)
                    )
                    with context:
                        state = ht.State(path)
                    self.assertFalse(state.writable)
                    self.assertEqual(state.load_faults[0]["kind"], kind)
                    with self.assertRaises(ht.StateLoadError):
                        state.require_writable()
                    with self.assertRaises(ht.StateLoadError):
                        state.save()
                    self.assertEqual(path.read_bytes(), before)

    def test_duplicate_keys_are_a_parse_fault(self):
        self.write_raw(self.paths.state, '{"history":[],"history":[]}')
        state = ht.State(self.paths.state)
        self.assertEqual(state.load_faults, [{"kind": "parse", "exists": "yes"}])

    def test_retro_queue_and_done_types_are_checked_before_retro_iteration(self):
        path = self.logical_path("retro")
        for invalid in ({"queue": {}}, {"done": ["not-an-item"]}):
            with self.subTest(invalid=invalid):
                self.write_raw(path, self.legacy(**invalid))
                state = ht.State(path)
                self.assertFalse(state.writable)
                self.assertEqual(state.load_faults[0], {
                    "kind": "type",
                    "exists": "yes",
                })


class AdmissionTests(StoreTestBase):
    def test_tick_preserves_primary_fault_and_still_admits_healthy_nightly(self):
        self.write_raw(self.paths.state, "{")
        calls = []
        cfg = dict(self.cfg)
        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.Runner, "_tick_locked",
                          autospec=True,
                                  side_effect=lambda self, _max: calls.append(
                                      "nightly" if self.intake else "primary") or 0), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            code = ht.main(["tick"], home=self.home)
        self.assertEqual(code, 4)
        self.assertEqual(calls, ["nightly"])
        self.assertIn("state store refused: parse for state.json", err.getvalue())

    def test_nightly_fault_refuses_only_nightly_after_primary_admission(self):
        self.write_raw(ht.Paths(self.cfg, self.home, "nightly-").state, "{")
        calls = []
        with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.Runner, "_tick_locked",
                          autospec=True,
                                  side_effect=lambda self, _max: calls.append(
                                      "nightly" if self.intake else "primary") or 0), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            code = ht.main(["tick"], home=self.home)
        self.assertEqual(code, 4)
        self.assertEqual(calls, ["primary"])
        self.assertIn("state-nightly.json", err.getvalue())

    def test_runner_tick_reloads_and_refuses_under_the_real_writer_lock(self):
        runner = self.runner(FakeGitHub([]))
        runner._state_loader = ht.State
        self.write_raw(self.paths.state, "{")
        with mock.patch.object(ht.Runner, "_tick_locked",
                               side_effect=AssertionError("work after refusal")):
            with self.assertRaisesRegex(ht.StateLoadError, "parse"):
                runner.tick()

    def test_manual_run_commands_refuse_after_busy_and_paused_checks(self):
        self.write_raw(self.paths.state, "{")
        with mock.patch.object(ht.Runner, "refresh_clone",
                               side_effect=AssertionError("refresh after refusal")), \
                mock.patch.object(ht.Runner, "work",
                                  side_effect=AssertionError("work after refusal")):
            result, _out, err = self.main_with(["run-issue", "13"])
        self.assertEqual(result, 4)
        self.assertIn("state store refused: parse", err)

        ht._PRINTED.clear()
        with mock.patch.object(ht.Runner, "run_job",
                               side_effect=AssertionError("job after refusal")):
            result, _out, err = self.main_with(["run-job", "steward"])
        self.assertEqual(result, 4)
        self.assertIn("state store refused: parse", err)

        self.paths.paused.parent.mkdir(parents=True, exist_ok=True)
        self.paths.paused.write_text("paused\n")
        with mock.patch.object(ht, "Runner",
                               side_effect=AssertionError("constructed while paused")):
            result, out, err = self.main_with(["run-job", "steward"])
        self.assertEqual((result, out, err), (0, "paused\n", ""))

    def test_manual_preview_does_not_need_state_write_authority(self):
        self.write_raw(self.paths.state, "{")
        gh = FakeGitHub([t.issue(13)])
        with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh), \
                mock.patch.object(ht, "render_prompt", return_value="fixed preview") as render, \
                mock.patch.object(ht.Runner, "refresh_clone",
                                  side_effect=AssertionError("preview refreshed")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(
                ht.main(["run-issue", "13", "--dry-run"], home=self.home),
                0,
            )
        self.assertEqual(out.getvalue(), "fixed preview\n")
        render.assert_called_once()
        self.assertEqual(self.paths.state.read_text(), "{")

    def test_acknowledgements_do_not_require_intake_authority(self):
        self.write_raw(self.paths.state, "{")
        verified = {"ok": True, "reason": "", "head": "a" * 40, "prs": [1]}
        with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.Runner, "ack_base", return_value="a" * 40), \
                mock.patch.object(ht.Runner, "ack_verified", return_value=verified), \
                mock.patch.dict(os.environ, {}, clear=True), \
                mock.patch("sys.stdin.isatty", return_value=True), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["ack-base", "a" * 40], home=self.home), 0)
            self.assertEqual(ht.main(["ack-verified"], home=self.home), 0)


class DurableSaveTests(StoreTestBase):
    def existing_state(self, name: str = "state.json") -> ht.State:
        path = self.paths.state_dir / name
        state = ht.State(path)
        state.data["sentinel"] = "old"
        state.save()
        return ht.State(path)

    def test_save_orders_all_entry_file_replace_and_parent_barriers(self):
        state = ht.State(self.paths.state)
        state.data["sentinel"] = "new"
        opened = {}
        events = []
        real_open, real_fsync, real_replace = os.open, os.fsync, os.replace

        def open_spy(target, flags, *args, **kwargs):
            fd = real_open(target, flags, *args, **kwargs)
            opened[fd] = str(target)
            return fd

        def sync_spy(fd):
            target = opened.get(fd, "")
            events.append("file" if stat.S_ISREG(os.fstat(fd).st_mode) else f"directory:{target}")
            return real_fsync(fd)

        def replace_spy(source, destination):
            events.append("replace")
            return real_replace(source, destination)

        with mock.patch.object(ht.os, "open", side_effect=open_spy), \
                mock.patch.object(ht.os, "fsync", side_effect=sync_spy), \
                mock.patch.object(ht.os, "replace", side_effect=replace_spy):
            state.save()

        file_sync = events.index("file")
        replace = events.index("replace")
        parent = events.index(f"directory:{self.paths.state_dir}", replace + 1)
        self.assertLess(file_sync, replace)
        self.assertLess(replace, parent)
        self.assertTrue(any(event.startswith("directory:") for event in events[:file_sync]))
        self.assertFalse(any(self.paths.state_dir.glob(f".{self.paths.state.name}.*.tmp")))
        self.assertEqual(stat.S_IMODE(self.paths.state.stat().st_mode), 0o600)

    def test_each_save_stage_preserves_old_bytes_except_post_replace_sync(self):
        stages = ("directory", "temp", "write", "flush", "file_sync", "replace", "parent_sync")
        for stage in stages:
            with self.subTest(stage=stage):
                state = self.existing_state(f"{stage}.json")
                old = state.path.read_bytes()
                state.data["sentinel"] = "new"
                real_fdopen, real_fsync, real_open = os.fdopen, os.fsync, os.open
                opened = {}

                def open_spy(target, flags, *args, **kwargs):
                    fd = real_open(target, flags, *args, **kwargs)
                    opened[fd] = str(target)
                    return fd

                if stage == "directory":
                    context = mock.patch.object(ht, "durable_mkdir", side_effect=OSError("directory"))
                elif stage == "temp":
                    context = mock.patch.object(ht.tempfile, "mkstemp", side_effect=OSError("temp"))
                elif stage in {"write", "flush"}:
                    class FailingHandle:
                        def __init__(self, fd, *args, **kwargs):
                            self.handle = real_fdopen(fd, *args, **kwargs)

                        def __enter__(self):
                            self.handle.__enter__()
                            return self

                        def __exit__(self, *args):
                            return self.handle.__exit__(*args)

                        def write(self, value):
                            if stage == "write":
                                raise OSError("write")
                            return self.handle.write(value)

                        def flush(self):
                            if stage == "flush":
                                raise OSError("flush")
                            return self.handle.flush()

                        def fileno(self):
                            return self.handle.fileno()

                    context = mock.patch.object(ht.os, "fdopen", side_effect=FailingHandle)
                elif stage in {"file_sync", "parent_sync"}:
                    def fail_sync(fd):
                        regular = stat.S_ISREG(os.fstat(fd).st_mode)
                        if (stage == "file_sync" and regular) \
                                or (stage == "parent_sync" and not regular
                                    and opened.get(fd) == str(state.path.parent)):
                            raise OSError(stage)
                        return real_fsync(fd)

                    context = contextlib.ExitStack()
                    context.enter_context(mock.patch.object(
                        ht.os, "open", side_effect=open_spy
                    ))
                    context.enter_context(mock.patch.object(
                        ht.os, "fsync", side_effect=fail_sync
                    ))
                else:
                    context = mock.patch.object(ht.os, "replace", side_effect=OSError("replace"))

                with context, self.assertRaisesRegex(ht.StateSaveError, stage):
                    state.save()
                after = state.path.read_bytes()
                if stage == "parent_sync":
                    self.assertEqual(json.loads(after)["sentinel"], "new")
                else:
                    self.assertEqual(after, old)
                self.assertFalse(any(state.path.parent.glob(f".{state.path.name}.*.tmp")))

    def test_existing_mode_survives_and_failed_ancestor_entry_is_retried(self):
        state = self.existing_state()
        os.chmod(state.path, 0o640)
        state.data["sentinel"] = "mode"
        state.save()
        self.assertEqual(stat.S_IMODE(state.path.stat().st_mode), 0o640)

        before = state.path.read_bytes()
        state.data["sentinel"] = "after"
        real_open, real_fsync = os.open, os.fsync
        opened = {}
        failed = {"value": False}

        def open_spy(target, flags, *args, **kwargs):
            fd = real_open(target, flags, *args, **kwargs)
            opened[fd] = str(target)
            return fd

        def fail_once(fd):
            if not failed["value"] and opened.get(fd) == str(self.paths.state_dir.parent):
                failed["value"] = True
                raise OSError("entry")
            return real_fsync(fd)

        with mock.patch.object(ht.os, "open", side_effect=open_spy), \
                mock.patch.object(ht.os, "fsync", side_effect=fail_once), \
                self.assertRaisesRegex(ht.StateSaveError, "directory"):
            state.save()
        self.assertEqual(state.path.read_bytes(), before)
        state.save()
        self.assertEqual(json.loads(state.path.read_text())["sentinel"], "after")

    def test_quiet_one_and_two_intake_ticks_save_exactly_once_each(self):
        for nightly in (None, self.cfg["nightly"]):
            with self.subTest(two_intakes=nightly is not None):
                cfg = dict(self.cfg)
                cfg["nightly"] = nightly
                events, saves = [], []
                original_save = ht.State.save
                real_open, real_fsync = os.open, os.fsync
                opened = {}
                file_syncs = []
                parent_syncs = []

                def counted(state):
                    saves.append(state.path.name)
                    original_save(state)

                def open_spy(target, flags, *args, **kwargs):
                    fd = real_open(target, flags, *args, **kwargs)
                    opened[fd] = str(target)
                    return fd

                def sync_spy(fd):
                    if stat.S_ISREG(os.fstat(fd).st_mode):
                        file_syncs.append(opened.get(fd))
                    elif opened.get(fd) == str(self.paths.state_dir):
                        parent_syncs.append(opened[fd])
                    return real_fsync(fd)

                patches = self.quiet_tick_patches(events)
                with mock.patch.object(ht, "load_config", return_value=cfg), \
                        mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                        mock.patch.object(ht.State, "save", autospec=True,
                                          side_effect=counted), \
                        mock.patch.object(ht.os, "open", side_effect=open_spy), \
                        mock.patch.object(ht.os, "fsync", side_effect=sync_spy), \
                        patches[0], patches[1], patches[2], patches[3], \
                        patches[4], patches[5], patches[6], patches[7], \
                        mock.patch("sys.stdout", new=io.StringIO()):
                    self.assertEqual(
                        ht.main(["tick", "--max-items", "0"], home=self.home),
                        0,
                    )
                expected = ["state.json", "state-nightly.json"] if nightly else ["state.json"]
                self.assertEqual(saves[-len(expected):], expected)
                self.assertEqual(len(file_syncs), len(expected))
                self.assertEqual(len(parent_syncs), len(expected))


class ContainmentTests(StoreTestBase):
    def completed_request(self, retro_path: Path):
        runner = self.runner(FakeGitHub([]))
        log = runner.paths.log(1, 1)
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text("completed\n")
        runner.task_id = mock.Mock(return_value="task-1")
        runner.run_retro_phase = mock.Mock()
        runner.run_retro_digest = mock.Mock()
        dest = runner.paths.root / "archive" / "request-1"
        (dest / "retro").mkdir(parents=True, exist_ok=True)
        (dest / "retro" / "task-1.json").write_text(
            json.dumps({"triggers": [{"id": "sample"}]})
        )

        def completed(_issue):
            runner.state.record(1, "done", "completed")
            runner._ending["log"] = log
            return "done"

        runner._work = completed
        self.write_raw(retro_path, "{")
        with mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(runner.work(1), "done")
        self.assertIn("enqueue not committed", err.getvalue())
        runner.state.save()
        return runner

    def test_completed_request_preserves_outcome_when_retro_load_refuses_enqueue(self):
        runner = self.completed_request(
            ht.Paths(self.cfg, self.home, "retro-").state
        )
        reopened = ht.State(self.paths.state)
        self.assertEqual(reopened.data["history"][-1]["outcome"], "done")

    def test_completed_job_preserves_outcome_and_save_when_retro_load_refuses(self):
        runner = self.runner(
            FakeGitHub([]),
            {"state": "done", "summary": "completed"},
        )
        runner.preflight = mock.Mock(return_value=True)
        self.write_raw(runner.retro_paths.state, "{")

        def digest(_n, dest, attempt=0, task="", **_kwargs):
            (dest / "retro").mkdir(parents=True, exist_ok=True)
            (dest / "retro" / f"{task}.json").write_text(
                json.dumps({"triggers": [{"id": "sample"}]})
            )

        runner.run_retro_digest = mock.Mock(side_effect=digest)
        runner.run_retro_phase = mock.Mock()
        runner.archive_evidence = mock.Mock(
            wraps=lambda *args, **kwargs: runner.__class__.archive_evidence(
                runner, *args, **kwargs
            )
        )
        with mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(runner.run_job("researcher"), "done")
        self.assertIn("enqueue not committed", err.getvalue())
        reopened = ht.State(self.paths.state)
        self.assertEqual(reopened.data["jobs"]["researcher"]["outcome"], "done")

    def test_enqueue_save_failure_reports_commit_uncertainty_without_losing_archive(self):
        runner = self.runner(FakeGitHub([]))
        retro_path = ht.Paths(self.cfg, self.home, "retro-").state
        self.write_raw(retro_path, self.legacy(queue=[]))
        dest = runner.paths.root / "archive" / "request-1"
        (dest / "retro").mkdir(parents=True, exist_ok=True)
        (dest / "retro" / "task-1.json").write_text(
            json.dumps({"triggers": [{"id": "sample"}]})
        )
        log = dest / "worker.log"
        log.write_text("done\n")
        with mock.patch.object(runner, "run_retro_digest"), \
                mock.patch.object(runner, "run_retro_phase"), \
                mock.patch.object(ht.State, "save", autospec=True,
                                  side_effect=ht.StateSaveError(
                                      retro_path.name, "parent_sync"
                                  )), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            result = runner.archive_evidence(
                1, log=log, name="request-1", task="task-1"
            )
        self.assertEqual(result, dest)
        self.assertIn("retro enqueue unconfirmed", err.getvalue())
        self.assertTrue((dest / "worker.log.tail").exists())

    def test_retro_load_refusal_continues_independent_primary_final_save_and_job(self):
        runner = self.runner(FakeGitHub([]))
        self.write_raw(runner.retro_paths.state, "{")
        with mock.patch.object(runner, "readable_base_map", return_value={}), \
                mock.patch.object(runner, "refresh_clone"), \
                mock.patch.object(runner, "check_base"), \
                mock.patch.object(runner, "check_ha_changes"), \
                mock.patch.object(runner, "check_merging"), \
                mock.patch.object(runner, "check_parked"), \
                mock.patch.object(runner, "requeue"), \
                mock.patch.object(runner, "recover"), \
                mock.patch.object(runner, "check_regressions", return_value=False), \
                mock.patch.object(runner, "run_due_job", return_value=None) as job, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(runner._tick_locked(), 4)
        job.assert_called_once_with()
        self.assertIn("retro state refused", err.getvalue())
        self.assertTrue(self.paths.state.exists())

    def test_retro_prelaunch_save_failure_stops_retro_but_saves_primary(self):
        runner = self.runner(FakeGitHub([]))
        queue = [{"task": "sample", "archive": str(self.home / "archive")}]
        self.write_raw(runner.retro_paths.state, self.legacy(queue=queue, done=[]))
        original_save = ht.State.save

        def fail_retro(state):
            if state.path == runner.retro_paths.state:
                raise ht.StateSaveError(state.path.name, "file_sync")
            return original_save(state)

        with mock.patch.object(runner, "readable_base_map", return_value={}), \
                mock.patch.object(runner, "refresh_clone"), \
                mock.patch.object(runner, "check_base"), \
                mock.patch.object(runner, "check_ha_changes"), \
                mock.patch.object(runner, "check_merging"), \
                mock.patch.object(runner, "check_parked"), \
                mock.patch.object(runner, "requeue"), \
                mock.patch.object(runner, "recover"), \
                mock.patch.object(runner, "preflight", return_value=True), \
                mock.patch.object(runner, "run_due_job",
                                  side_effect=AssertionError("job after retro save failure")), \
                mock.patch.object(
                    runner, "_run",
                    side_effect=lambda *args, **kwargs: subprocess.CompletedProcess(
                        args, 0, "", ""
                    )
                ), \
                mock.patch.object(ht.State, "save", autospec=True,
                                  side_effect=fail_retro), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(runner._tick_locked(), 4)
        self.assertIn("retro persistence failure", err.getvalue())
        self.assertTrue(self.paths.state.exists())
        self.assertEqual(json.loads(runner.retro_paths.state.read_text())["queue"], queue)

    def test_job_final_save_failure_is_not_reported_as_a_normal_result(self):
        runner = self.runner(
            FakeGitHub([]),
            {"state": "done", "summary": "completed"},
        )
        runner.preflight = mock.Mock(return_value=True)
        original_save = ht.State.save
        primary_saves = 0

        def fail_final(state):
            nonlocal primary_saves
            if state.path == self.paths.state:
                primary_saves += 1
                if primary_saves == 2:
                    raise ht.StateSaveError(state.path.name, "parent_sync")
            return original_save(state)

        with mock.patch.object(ht.State, "save", autospec=True,
                               side_effect=fail_final):
            with self.assertRaisesRegex(ht.StateSaveError, "parent_sync"):
                runner.run_job("steward")
        self.assertEqual(primary_saves, 2)

    def test_retro_final_save_failure_preserves_primary_progress_and_result(self):
        runner = self.runner(
            FakeGitHub([]),
            {"state": "done", "summary": "completed"},
        )
        self.write_raw(
            runner.retro_paths.state,
            self.legacy(
                queue=[{"task": "sample", "archive": str(self.home / "archive")}],
                done=[],
            ),
        )
        original_save = ht.State.save
        retro_saves = 0

        def fail_final(state):
            nonlocal retro_saves
            if state.path == runner.retro_paths.state:
                retro_saves += 1
                if retro_saves == 2:
                    raise ht.StateSaveError(state.path.name, "parent_sync")
            return original_save(state)

        with mock.patch.object(runner, "readable_base_map", return_value={}), \
                mock.patch.object(runner, "refresh_clone"), \
                mock.patch.object(runner, "check_base"), \
                mock.patch.object(runner, "check_ha_changes"), \
                mock.patch.object(runner, "check_merging"), \
                mock.patch.object(runner, "check_parked"), \
                mock.patch.object(runner, "requeue"), \
                mock.patch.object(runner, "recover"), \
                mock.patch.object(runner, "preflight", return_value=True), \
                mock.patch.object(runner, "check_regressions",
                                  side_effect=AssertionError("after retro failure")), \
                mock.patch.object(runner, "run_due_job",
                                  side_effect=AssertionError("after retro failure")), \
                mock.patch.object(
                    runner, "_run",
                    side_effect=lambda *args, **kwargs: subprocess.CompletedProcess(
                        args, 0, "", ""
                    ),
                ), \
                mock.patch.object(ht.State, "save", autospec=True,
                                  side_effect=fail_final), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(runner._tick_locked(), 4)
        self.assertEqual(retro_saves, 2)
        self.assertIn("retro persistence failure", err.getvalue())
        self.assertEqual(
            ht.State(self.paths.state).data["history"][-1]["outcome"],
            "retro:done",
        )

    def test_primary_save_after_retro_finalizer_is_not_contained_as_retro_error(self):
        runner = self.runner(
            FakeGitHub([]),
            {"state": "done", "summary": "completed"},
        )
        self.write_raw(
            runner.retro_paths.state,
            self.legacy(
                queue=[{"task": "sample", "archive": str(self.home / "archive")}],
                done=[],
            ),
        )
        original_save = ht.State.save
        primary_saves = 0

        def fail_primary(state):
            nonlocal primary_saves
            if state.path == self.paths.state:
                primary_saves += 1
                if primary_saves == 2:
                    raise ht.StateSaveError(state.path.name, "file_sync")
            return original_save(state)

        with mock.patch.object(runner, "readable_base_map", return_value={}), \
                mock.patch.object(runner, "refresh_clone"), \
                mock.patch.object(runner, "check_base"), \
                mock.patch.object(runner, "check_ha_changes"), \
                mock.patch.object(runner, "check_merging"), \
                mock.patch.object(runner, "check_parked"), \
                mock.patch.object(runner, "requeue"), \
                mock.patch.object(runner, "recover"), \
                mock.patch.object(runner, "preflight", return_value=True), \
                mock.patch.object(
                    runner, "_run",
                    side_effect=lambda *args, **kwargs: subprocess.CompletedProcess(
                        args, 0, "", ""
                    ),
                ), \
                mock.patch.object(ht.State, "save", autospec=True,
                                  side_effect=fail_primary):
            with self.assertRaisesRegex(ht.StateSaveError, "file_sync"):
                runner._tick_locked()
        self.assertEqual(primary_saves, 2)

    def test_classic_launcher_reports_cleanup_before_propagating_save_failure(self):
        runner = self.runner(FakeGitHub([]))
        runner.state.data["current"] = {}
        process = mock.Mock(pid=987654, stdin=mock.Mock(), stdout=None)
        with mock.patch.object(ht.subprocess, "Popen", return_value=process), \
                mock.patch.object(runner.state, "save",
                                  side_effect=ht.StateSaveError("state.json", "file_sync")), \
                mock.patch.object(ht.lane_land, "reap_group", return_value=True) as reap, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            with self.assertRaises(ht.StateSaveError):
                runner._launch(1, self.home / "tree", "prompt", self.home / "log")
        process.stdin.close.assert_called_once_with()
        reap.assert_called_once_with(987654)
        self.assertIn("cleanup confirmed", err.getvalue())

    def test_t3_callback_reports_cleanup_before_propagating_save_failure(self):
        runner = self.runner(FakeGitHub([]))
        runner.state.data["current"] = {}

        class Launcher:
            def __init__(self, *_args, **_kwargs):
                pass

            def launch(self, **kwargs):
                try:
                    kwargs["on_thread"]("thread-1")
                except ht.StateSaveError:
                    return ht.t3launch.Outcome(1, "thread-1", False, True)

        with mock.patch.object(ht.t3launch, "Launcher", Launcher), \
                mock.patch.object(runner.state, "save",
                                  side_effect=ht.StateSaveError("state.json", "parent_sync")), \
                mock.patch.object(runner, "trusted_clone", return_value=self.paths.clone), \
                mock.patch.object(ht.shutil, "which", return_value=None), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            with self.assertRaises(ht.StateSaveError):
                runner._t3_launch(
                    "job-sample", self.home / "tree", "prompt", self.home / "log"
                )
        self.assertIn("cleanup confirmed", err.getvalue())

    def test_wrapped_t3_callback_save_failure_is_not_a_normal_lane_error(self):
        runner = self.runner(FakeGitHub([]))
        runner.state.data["current"] = {}

        class Launcher:
            def __init__(self, *_args, **_kwargs):
                pass

            def launch(self, **kwargs):
                try:
                    kwargs["on_thread"]("thread-1")
                except ht.StateSaveError:
                    raise RuntimeError("launcher wrapped callback failure")

        with mock.patch.object(ht.t3launch, "Launcher", Launcher), \
                mock.patch.object(runner.state, "save",
                                  side_effect=ht.StateSaveError("state.json", "file_sync")), \
                mock.patch.object(runner, "trusted_clone", return_value=self.paths.clone), \
                mock.patch.object(ht.shutil, "which", return_value=None), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            with self.assertRaisesRegex(ht.StateSaveError, "file_sync"):
                runner._t3_launch(
                    "job-sample", self.home / "tree", "prompt", self.home / "log"
                )
        self.assertIn("cleanup unconfirmed", err.getvalue())


class StatusAndGoldenTests(StoreTestBase):
    def run_status(self, args, cfg=None, gh=None):
        with mock.patch.object(ht, "load_config", return_value=cfg or self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh or FakeGitHub([])), \
                mock.patch.object(ht, "claude_logged_in", return_value=None), \
                mock.patch.object(ht.t3launch, "ready", return_value=(None, "")), \
                mock.patch.object(ht, "writer_lock",
                                  side_effect=AssertionError("status acquired writer lock")), \
                mock.patch.object(ht.State, "save",
                                  side_effect=AssertionError("status saved state")), \
                mock.patch.object(ht, "durable_mkdir",
                                  side_effect=AssertionError("status created a directory")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            code = ht.main(args, home=self.home)
        self.assertEqual(code, 0)
        return out.getvalue()

    def test_status_faults_are_read_only_bounded_and_match_both_formats(self):
        self.write_raw(self.paths.state, self.legacy(
            current=[],
            jobs={"steward": {"last_run": 42}},
        ))
        nightly = ht.Paths(self.cfg, self.home, "nightly-").state
        self.write_raw(nightly, "{")
        retro = ht.Paths(self.cfg, self.home, "retro-").state
        self.write_raw(retro, self.legacy(queue={"not": "a list"}))
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        with ht.writer_lock(self.paths) as admitted:
            self.assertTrue(admitted)
            before = {
                str(path.relative_to(self.home)): path.read_bytes()
                for path in self.home.rglob("*") if path.is_file()
            }
            text = self.run_status(["status"], cfg=cfg)
            encoded = self.run_status(["status", "--json"], cfg=cfg)
        report = json.loads(encoded)
        self.assertIn("state store request: type (exists yes)", text)
        self.assertIn("state store nightly: parse (exists yes)", text)
        self.assertEqual(
            {(item["store"], item["kind"], item["exists"])
             for item in report["state_loads"]},
            {
                ("request", "type", "yes"),
                ("nightly", "parse", "yes"),
                ("retro", "type", "yes"),
            },
        )
        self.assertIsNone(report["jobs"]["steward"]["last_run"])
        self.assertEqual(report["jobs"]["steward"]["next_due"], "unknown")
        self.assertEqual(report["retro_queue"], [])
        self.assertEqual(
            {str(path.relative_to(self.home)): path.read_bytes()
             for path in self.home.rglob("*") if path.is_file()},
            before,
        )

    def test_status_does_not_refuse_on_missing_optional_and_reports_primary_missing(self):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        encoded = self.run_status(["status", "--json"], cfg=cfg)
        report = json.loads(encoded)
        self.assertEqual(report["state_loads"], [{
            "store": "request",
            "kind": "not_found",
            "exists": "no",
            "installation": "unknown",
        }])

    def test_recordless_quiet_tick_has_fixed_ordered_transcript_and_opaque_bytes(self):
        events = []
        self.write_raw(self.paths.state, self.legacy(
            opaque_extension={"preserve": ["exact", 1]}
        ))
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        patches = self.quiet_tick_patches(events)
        original_save = ht.State.save

        def save(state):
            events.append("save")
            original_save(state)

        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.State, "save", autospec=True, side_effect=save), \
                patches[0], patches[1], patches[2], patches[3], \
                patches[4], patches[5], patches[6], patches[7], \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            code = ht.main(["tick", "--max-items", "0"], home=self.home)
        self.assertEqual((code, out.getvalue(), err.getvalue()), (0, "", ""))
        self.assertEqual(events, [
            "base-map", "refresh", "base", "ha", "merging", "parked",
            "requeue", "recover", "save",
        ])
        reopened = json.loads(self.paths.state.read_text())
        self.assertEqual(reopened["opaque_extension"], {"preserve": ["exact", 1]})


if __name__ == "__main__":
    unittest.main()
