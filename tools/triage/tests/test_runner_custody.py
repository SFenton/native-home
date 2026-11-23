"""Custody store, load-fault, durable-save and read-only status proofs."""
from __future__ import annotations

import io
import json
import os
import stat
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


def custody_aggregate(intake: str, producer: str, generation: str, path: Path,
                      number: int = 41, phase: str = "pending") -> dict:
    key = f"{producer}:{generation}"
    outcome = "done" if phase == "release_authorized" else "blocked"
    return {
        "version": 1,
        "records": {
            "example/product": {
                intake: {
                    producer: {
                        generation: {
                            "repository": "example/product",
                            "intake": intake,
                            "producer": producer,
                            "generation": generation,
                            "phase": phase,
                            "original_outcome": {
                                "state": outcome,
                                "trust": True,
                                "exit_code": 0,
                                "archive_disposition": "archived",
                            },
                            "since": "2026-01-01T00:00:00Z",
                            "reason": "owner review is unresolved",
                            "attempts": 2,
                            "path": str(path),
                            "next": {"kind": "human", "value": "review bridge disposition"},
                            "bindings": {
                                "binding-one": {
                                    "lane": "ui",
                                    "branch": f"agents/factory-{number}",
                                    "disposition": "held",
                                    "tip": "a" * 40,
                                    "pull": number,
                                    "reviewed_head": None,
                                    "reason": "review is unreadable",
                                    "since": "2026-01-01T00:00:30Z",
                                    "attempts": 1,
                                    "next": {"kind": "retry", "value": "observe"},
                                    "notice": {
                                        "key": f"example/product/ui/{'a' * 40}/read-fault:{key}",
                                        "state": "uncertain",
                                        "since": "2026-01-01T00:01:00Z",
                                        "remote_identity": {
                                            "repository": "example/private-requests",
                                            "kind": "issue",
                                            "id": 9,
                                            "issuer": "runner",
                                        },
                                    },
                                },
                            },
                            "private_canary": "not for status",
                        },
                    },
                },
            },
        },
    }


class CustodyTestBase(t.Base):
    def write_raw(self, path: Path, data) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data) if not isinstance(data, str) else data)

    def state_data(self, **extra) -> dict:
        data = ht.State(self.paths.state)._empty_data()
        data.update(extra)
        return data

    def seed_custody(self, path: Path, intake: str, producer: str, generation: str,
                     phase: str = "pending") -> Path:
        checkout = self.home / "checkouts" / generation
        checkout.mkdir(parents=True, exist_ok=True)
        self.write_raw(path, self.state_data(
            custody=custody_aggregate(intake, producer, generation, checkout, phase=phase)
        ))
        return checkout

    def queue_error_github(self):
        gh = FakeGitHub([])

        def unreadable(_repo):
            raise ht.TriageError("synthetic queue read failed")

        gh.open_issues = unreadable
        return gh


class LoadFaultTests(CustodyTestBase):
    def logical_path(self, store: str) -> Path:
        return {
            "primary": self.paths.state,
            "nightly": ht.Paths(self.cfg, self.home, "nightly-").state,
            "retro": ht.Paths(self.cfg, self.home, "retro-").state,
        }[store]

    def test_load_fault_read_parse_root_version_type_phase_expected_enoent(self):
        kinds = ("read", "parse", "root", "version", "type", "phase", "expected_enoent")
        for store in ("primary", "nightly", "retro"):
            path = self.logical_path(store)
            for kind in kinds:
                with self.subTest(store=store, kind=kind):
                    if path.exists():
                        path.unlink()
                    path.parent.mkdir(parents=True, exist_ok=True)
                    if kind == "read":
                        path.write_text("{}")
                        with mock.patch.object(Path, "read_text", side_effect=OSError("synthetic read")):
                            state = ht.State(path)
                    elif kind == "parse":
                        path.write_text("{")
                        state = ht.State(path)
                    elif kind == "root":
                        path.write_text("[]")
                        state = ht.State(path)
                    elif kind in {"version", "type", "phase"}:
                        aggregate = custody_aggregate("request", "request:1", "generation-1",
                                                      self.home / "tree")
                        if kind == "version":
                            aggregate["version"] = True
                        elif kind == "type":
                            aggregate["records"] = []
                        else:
                            record = aggregate["records"]["example/product"]["request"]["request:1"][
                                "generation-1"]
                            record["phase"] = "retired"
                        self.write_raw(path, self.state_data(custody=aggregate))
                        state = ht.State(path)
                    else:
                        ht.State._known_paths.discard(str(path))
                        established = ht.State(path)
                        established.data["sentinel"] = "first"
                        established.save()
                        before = path.read_bytes()
                        path.unlink()
                        state = ht.State(path)
                        self.assertFalse(path.exists())
                        self.assertTrue(before)
                    self.assertTrue(state.load_faults, (store, kind))
                    with self.assertRaises(ht.StateLoadError):
                        state.require_writable()
                    with self.assertRaises(ht.StateLoadError):
                        state.save()
                    if kind != "expected_enoent":
                        self.assertTrue(path.exists())

    def test_duplicate_keys_compatible_extras_and_unknown_outcome_are_strict(self):
        path = self.paths.state
        self.write_raw(path, '{"custody":{"version":1,"version":1,"records":{}}}')
        duplicate = ht.State(path)
        self.assertEqual([fault["kind"] for fault in duplicate.load_faults], ["parse"])

        checkout = self.home / "checkout"
        checkout.mkdir()
        aggregate = custody_aggregate("request", "request:41", "generation-1", checkout)
        aggregate["future_projection"] = {"kept": True}
        aggregate["records"]["example/product"]["request"]["request:41"]["generation-1"][
            "future_record_field"] = {"kept": True}
        self.write_raw(path, self.state_data(custody=aggregate))
        compatible = ht.State(path)
        self.assertTrue(compatible.writable)
        compatible.save()
        reopened = json.loads(path.read_text())
        self.assertEqual(reopened["custody"]["future_projection"], {"kept": True})
        self.assertIn("future_record_field", reopened["custody"]["records"]["example/product"][
            "request"]["request:41"]["generation-1"])

        bad = custody_aggregate("request", "request:41", "generation-2", checkout)
        record = bad["records"]["example/product"]["request"]["request:41"]["generation-2"]
        record["original_outcome"] = {"state": "arbitrary", "worker_payload": {"house": "data"}}
        self.write_raw(path, self.state_data(custody=bad))
        rejected = ht.State(path)
        self.assertFalse(rejected.writable)

    def test_affected_writer_refuses_without_refresh_or_mutation(self):
        self.write_raw(self.paths.state, "{")
        before = self.paths.state.read_bytes()
        with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.Runner, "refresh_clone", side_effect=AssertionError("refreshed")) as refresh, \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(ht.main(["tick"], home=self.home), 4)
        refresh.assert_not_called()
        self.assertEqual(self.paths.state.read_bytes(), before)
        self.assertNotIn("another tick is running", out.getvalue())
        self.assertIn("state store refused: parse", err.getvalue())

    def test_genuine_first_use_is_normal_and_fresh_unseen_enoent_is_not_fabricated(self):
        state = ht.State(self.home / "new-state" / "state.json")
        self.assertTrue(state.writable)
        self.assertEqual(state.data["attempts"], {})
        state.data["sentinel"] = "fresh"
        state.save()
        reopened = ht.State(state.path)
        self.assertEqual(reopened.data["sentinel"], "fresh")

    def test_secondary_store_fault_does_not_hide_valid_primary_record(self):
        self.seed_custody(self.paths.state, "request", "request:41", "primary-record")
        nightly = ht.Paths(self.cfg, self.home, "nightly-").state
        self.write_raw(nightly, "{")
        report = ht.status_report(self.cfg, self.paths, self.queue_error_github())
        self.assertEqual([record["namespace"] for record in report["custody"]["records"]], ["request"])
        self.assertIn("nightly", [fault["namespace"] for fault in report["custody"]["faults"]])


class DurableSaveTests(CustodyTestBase):
    def existing_state(self, name: str = "state.json") -> ht.State:
        path = self.paths.state_dir / name
        state = ht.State(path)
        state.data["sentinel"] = "old"
        state.save()
        return ht.State(path)

    def test_storage_order_file_sync_parent_sync_and_new_ancestors(self):
        path = self.home / "new-parent" / "nested" / "state.json"
        state = ht.State(path)
        state.data["sentinel"] = "durable"
        real_open, real_fsync, real_replace = os.open, os.fsync, os.replace
        opened = {}
        events = []

        def open_spy(target, flags, *args, **kwargs):
            fd = real_open(target, flags, *args, **kwargs)
            opened[fd] = str(target)
            return fd

        def sync_spy(fd):
            target = opened.get(fd, "")
            kind = "file" if stat.S_ISREG(os.fstat(fd).st_mode) else f"directory:{target}"
            events.append(kind)
            return real_fsync(fd)

        def replace_spy(source, destination):
            events.append("replace")
            return real_replace(source, destination)

        with mock.patch.object(ht.os, "open", side_effect=open_spy), \
                mock.patch.object(ht.os, "fsync", side_effect=sync_spy), \
                mock.patch.object(ht.os, "replace", side_effect=replace_spy):
            state.save()

        file_sync = next(index for index, event in enumerate(events) if event == "file")
        replace = events.index("replace")
        parent = next(index for index, event in enumerate(events)
                      if event == f"directory:{path.parent}" and index > replace)
        self.assertLess(file_sync, replace)
        self.assertLess(replace, parent)
        self.assertTrue(any(event.startswith("directory:") for event in events[:file_sync]))
        self.assertEqual(json.loads(path.read_text())["sentinel"], "durable")
        self.assertFalse(any(path.parent.glob(f".{path.name}.*.tmp")))

    def test_save_failure_each_stage_preserves_or_explains_visible_bytes(self):
        stages = ("directory", "temp", "write", "flush", "file_sync", "replace", "parent_sync")
        for stage in stages:
            with self.subTest(stage=stage):
                state = self.existing_state(f"stage-{stage}.json")
                old = state.path.read_bytes()
                state.data["sentinel"] = "new"

                if stage == "directory":
                    context = mock.patch.object(ht, "durable_mkdir", side_effect=OSError("directory"))
                elif stage == "temp":
                    context = mock.patch.object(ht.tempfile, "mkstemp", side_effect=OSError("temp"))
                elif stage in {"write", "flush"}:
                    real_fdopen = os.fdopen

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
                    real_fsync = os.fsync

                    def fail_sync(fd):
                        regular = stat.S_ISREG(os.fstat(fd).st_mode)
                        if (stage == "file_sync" and regular) or (stage == "parent_sync" and not regular):
                            raise OSError(stage)
                        return real_fsync(fd)

                    context = mock.patch.object(ht.os, "fsync", side_effect=fail_sync)
                else:
                    context = mock.patch.object(ht.os, "replace", side_effect=OSError("replace"))

                with context:
                    with self.assertRaisesRegex(ht.StateSaveError, stage):
                        state.save()
                after = state.path.read_bytes()
                if stage == "parent_sync":
                    self.assertNotEqual(after, old)
                    self.assertEqual(json.loads(after)["sentinel"], "new")
                else:
                    self.assertEqual(after, old)
                self.assertFalse(any(state.path.parent.glob(f".{state.path.name}.*.tmp")))

    def test_persistence_failure_is_not_a_job_or_retro_terminal_result(self):
        for kind in ("request", "job", "retro"):
            with self.subTest(kind=kind):
                runner = self.runner(
                    FakeGitHub([t.issue(1)] if kind == "request" else []),
                    {"state": "done", "summary": "synthetic"},
                )
                archive = mock.Mock()
                drop = mock.Mock()
                collect = mock.Mock()
                runner.archive_evidence = archive
                runner._drop_worktree = drop
                runner._collect_owner_comments = collect
                if kind == "request":
                    runner.state.save = mock.Mock(side_effect=ht.StateSaveError("state", "file_sync"))
                    with self.assertRaises(ht.StateSaveError):
                        runner.work(1)
                    collect.assert_not_called()
                    archive.assert_not_called()
                    runner.refresh_clone = mock.Mock()
                    runner.work = mock.Mock(return_value="done")
                    with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                            mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                            mock.patch.object(ht, "Runner", return_value=runner), \
                            mock.patch("sys.stdout", new=io.StringIO()) as out, \
                            mock.patch("sys.stderr", new=io.StringIO()):
                        self.assertEqual(ht.main(["run-issue", "1"], home=self.home), 4)
                    self.assertEqual(out.getvalue(), "")
                elif kind == "job":
                    runner.preflight = lambda: True
                    runner.state.save = mock.Mock(side_effect=ht.StateSaveError("state", "file_sync"))
                    with self.assertRaises(ht.StateSaveError):
                        runner.run_job("steward")
                    archive.assert_not_called()
                    drop.assert_not_called()
                else:
                    retro = ht.State(runner.retro_paths.state)
                    retro.data["queue"] = [{"task": "sample", "archive": str(self.home / "archive")}]
                    retro.data["current"] = None
                    retro.data["done"] = []
                    retro.save()
                    runner.preflight = lambda: True
                    runner._run = mock.Mock(return_value=ht.subprocess.CompletedProcess([], 0, "", ""))
                    original_save = ht.State.save

                    def fail_primary(state):
                        if state.path == runner.paths.state:
                            raise ht.StateSaveError(state.path.name, "file_sync")
                        return original_save(state)

                    with mock.patch.object(ht.State, "save", autospec=True, side_effect=fail_primary):
                        with self.assertRaises(ht.StateSaveError):
                            runner.run_retro()
                    archive.assert_not_called()
                    drop.assert_not_called()

    def test_launcher_save_failure_reaps_pid_and_t3_callback_does_not_become_a_result(self):
        runner = self.runner(FakeGitHub([]))
        runner.state.data["current"] = {}
        process = mock.Mock()
        process.pid = 987654
        process.stdin = mock.Mock()
        process.stdout = None
        with mock.patch.object(ht.subprocess, "Popen", return_value=process), \
                mock.patch.object(runner.state, "save",
                                  side_effect=ht.StateSaveError("state", "file_sync")), \
                mock.patch.object(ht.lane_land, "reap_group", return_value=True) as reap:
            with self.assertRaises(ht.StateSaveError):
                runner._launch(1, self.home / "tree", "prompt", self.home / "log")
        process.stdin.close.assert_called_once_with()
        reap.assert_called_once_with(process.pid)

        runner.state.data["current"] = {}

        class Launcher:
            def __init__(self, *_args, **_kwargs):
                pass

            def launch(self, **kwargs):
                try:
                    kwargs["on_thread"]("thread-1")
                except StateError:
                    return ht.t3launch.Outcome(1, "thread-1", False, True)

        StateError = ht.StateSaveError
        with mock.patch.object(ht.t3launch, "Launcher", Launcher), \
                mock.patch.object(runner.state, "save",
                                  side_effect=ht.StateSaveError("state", "parent_sync")), \
                mock.patch.object(ht.shutil, "which", return_value=None), \
                mock.patch.object(runner, "trusted_clone", return_value=self.paths.clone):
            with self.assertRaises(ht.StateSaveError):
                runner._t3_launch("job-sample", self.home / "tree", "prompt", self.home / "log")


class StatusTests(CustodyTestBase):
    def run_status(self, args, gh=None):
        with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh or FakeGitHub([])), \
                mock.patch.object(ht, "claude_logged_in", return_value=None), \
                mock.patch.object(ht.t3launch, "ready", side_effect=AssertionError("not local custody")), \
                mock.patch.object(ht, "writer_lock", side_effect=AssertionError("status acquired writer lock")), \
                mock.patch.object(ht.State, "save", side_effect=AssertionError("status saved state")), \
                mock.patch.object(ht, "durable_mkdir", side_effect=AssertionError("status created a directory")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(ht.main(args, home=self.home), 0)
            return out.getvalue()

    def test_status_local_only_text_record_and_json_record(self):
        self.seed_custody(self.paths.state, "request", "request:41", "request-generation")
        nightly_paths = ht.Paths(self.cfg, self.home, "nightly-")
        self.seed_custody(nightly_paths.state, "nightly", "nightly:41", "nightly-generation")
        before = {
            str(path.relative_to(self.home)): path.read_bytes()
            for path in self.home.rglob("*") if path.is_file()
        }

        with mock.patch.object(ht.time, "time", return_value=1767312061):
            text = self.run_status(["status"])
            encoded = self.run_status(["status", "--json"])
        report = json.loads(encoded)

        self.assertIn("producer request:41 generation request-generation", text)
        self.assertIn("producer nightly:41 generation nightly-generation", text)
        self.assertIn("binding ui", text)
        self.assertIn("delivery ui uncertain", text)
        self.assertNotIn("not for status", text)
        self.assertNotIn("not for status", encoded)
        self.assertEqual({record["namespace"] for record in report["custody"]["records"]},
                         {"request", "nightly"})
        self.assertEqual(report["custody"]["version"], 1)
        self.assertEqual(
            {str(path.relative_to(self.home)): path.read_bytes()
             for path in self.home.rglob("*") if path.is_file()},
            before,
        )

    def test_status_local_only_faults_survive_queue_and_legacy_errors(self):
        self.seed_custody(self.paths.state, "request", "request:41", "request-generation")
        nightly = ht.Paths(self.cfg, self.home, "nightly-").state
        self.write_raw(nightly, "{")
        retro = ht.Paths(self.cfg, self.home, "retro-").state
        self.write_raw(retro, {"queue": {"not": "a list"}})
        gh = self.queue_error_github()
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh), \
                mock.patch.object(ht, "claude_logged_in", return_value=None), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(ht.main(["status", "--json"], home=self.home), 0)
        report = json.loads(out.getvalue())
        self.assertEqual(report["queue"], [{"error": "synthetic queue read failed"}])
        self.assertEqual([record["namespace"] for record in report["custody"]["records"]], ["request"])
        self.assertTrue(any(fault["namespace"] == "nightly" and fault["kind"] == "parse"
                            for fault in report["custody"]["faults"]))
        self.assertEqual(report["retro_queue"], [])

        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh), \
                mock.patch.object(ht, "claude_logged_in", return_value=None), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(ht.main(["status"], home=self.home), 0)
        self.assertIn("custody fault: nightly parse", out.getvalue())

    def test_status_age_increases_without_changing_since_or_disk(self):
        self.seed_custody(self.paths.state, "request", "request:41", "age-generation")
        clock = mock.Mock(side_effect=[1767225600, 1767225660])
        with mock.patch.object(ht.time, "time", clock):
            first = ht.status_report(self.cfg, self.paths, FakeGitHub([]))
            second = ht.status_report(self.cfg, self.paths, FakeGitHub([]))
        one = first["custody"]["records"][0]
        two = second["custody"]["records"][0]
        self.assertEqual(one["since"], two["since"])
        self.assertEqual(one["age_seconds"], 0)
        self.assertEqual(two["age_seconds"], 60)


class ParityAndNoTransitionTests(CustodyTestBase):
    def test_recordless_parity_fresh_legacy_map_has_fixed_transcript(self):
        cases = (
            ("primary", self.paths.state, "done"),
            ("nightly", ht.Paths(self.cfg, self.home, "nightly-").state, "no_changes"),
            ("retro", ht.Paths(self.cfg, self.home, "retro-").state, "blocked"),
        )
        for entry, path, outcome in cases:
            with self.subTest(entry=entry, outcome=outcome):
                legacy = {
                    "attempts": {"41": 1},
                    "merging": {},
                    "parked": {},
                    "jobs": {},
                    "history": [{"issue": 41, "outcome": outcome, "at": "2026-01-01T00:00:00Z"}],
                    "current": None,
                    "archive_sessions": {},
                    "archive_holds": {},
                    "unknown_legacy": {"preserve": True},
                }
                self.write_raw(path, legacy)
                state = ht.State(path)
                self.assertNotIn("custody", state.data)
                self.assertEqual(state.data["unknown_legacy"], {"preserve": True})
                state.save()
                reopened = ht.State(path)
                self.assertNotIn("custody", reopened.data)
                self.assertEqual(reopened.data["history"][0]["outcome"], outcome)

    def test_injected_authorized_record_causes_no_production_transition(self):
        checkout = self.seed_custody(
            self.paths.state, "request", "request:41", "authorized-generation",
            phase="release_authorized",
        )
        runner = self.runner(FakeGitHub([]), state_loader=lambda _path: ht.State(self.paths.state))
        calls = []
        for name in ("refresh_clone", "check_ha_changes", "check_merging", "check_parked",
                     "requeue", "recover"):
            setattr(runner, name, mock.Mock(side_effect=lambda label=name: calls.append(label)))
        runner.check_base = mock.Mock(side_effect=lambda *_a, **_k: calls.append("base") or True)
        with mock.patch.object(runner.state, "save", side_effect=lambda: calls.append("save")):
            self.assertEqual(runner._tick_locked(max_items=0), 0)
        self.assertEqual(calls, ["refresh_clone", "base", "check_ha_changes", "check_merging",
                                 "check_parked", "requeue", "recover", "save"])
        self.assertTrue(checkout.exists())
        self.assertEqual(runner.state.data["custody"]["records"]["example/product"][
            "request"]["request:41"]["authorized-generation"]["phase"], "release_authorized")

    def test_same_number_two_intake_display_trace_has_both_formats(self):
        self.seed_custody(self.paths.state, "request", "request:41", "request-generation")
        nightly = ht.Paths(self.cfg, self.home, "nightly-").state
        self.seed_custody(nightly, "nightly", "nightly:41", "nightly-generation")
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht, "claude_logged_in", return_value=None):
            with mock.patch("sys.stdout", new=io.StringIO()) as out:
                self.assertEqual(ht.main(["status"], home=self.home), 0)
                text = out.getvalue()
            with mock.patch("sys.stdout", new=io.StringIO()) as out:
                self.assertEqual(ht.main(["status", "--json"], home=self.home), 0)
                report = json.loads(out.getvalue())
        self.assertIn("request-generation", text)
        self.assertIn("nightly-generation", text)
        self.assertEqual(
            {(record["key"]["intake"], record["key"]["generation"])
             for record in report["custody"]["records"]},
            {("request", "request-generation"), ("nightly", "nightly-generation")},
        )


if __name__ == "__main__":
    unittest.main()
