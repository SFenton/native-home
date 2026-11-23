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
from datetime import datetime, timezone
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

    def main_golden(self, argv, cfg, gh, boundaries):
        fixed = datetime(2026, 11, 23, 12, 0, tzinfo=timezone.utc)
        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh), \
                mock.patch.object(
                    ht.Runner, "_run", autospec=True,
                    side_effect=boundaries.run,
                ), \
                mock.patch.object(
                    ht.Runner, "_launch", autospec=True,
                    side_effect=boundaries.launch,
                ), \
                mock.patch.object(
                    ht.lane_land, "git", side_effect=boundaries.land_git,
                ), \
                mock.patch.object(
                    ht.lane_land, "land", side_effect=boundaries.land,
                ), \
                mock.patch.object(ht, "claude_logged_in", return_value=True), \
                mock.patch.object(ht, "iso", return_value="2026-11-23T12:00:00Z"), \
                mock.patch.object(ht, "now", return_value=fixed), \
                mock.patch.object(ht.time, "time", return_value=1795435200.0), \
                mock.patch.object(ht.time, "time_ns", return_value=1795435200000000000), \
                mock.patch.object(ht.os, "getpid", return_value=4242), \
                mock.patch.dict(
                    os.environ,
                    {"FENTON_HEADLESS": "", "HASS_TRIAGE_ISSUE": ""},
                ), \
                mock.patch("sys.stdin.isatty", return_value=True), \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            result = ht.main(argv, home=self.home)
        return result, out.getvalue(), err.getvalue()

    def file_bytes(self):
        return {
            str(path.relative_to(self.home)): path.read_bytes()
            for path in sorted(self.home.rglob("*"))
            if path.is_file()
        }

    @staticmethod
    def saved_bytes(value):
        return json.dumps(value, indent=2, sort_keys=True).encode()


class RecordlessTraceGitHub(FakeGitHub):
    """Argument-aware remote seam with a hard call bound."""

    def __init__(self, by_repo=None, pulls=None, limit=200):
        super().__init__([])
        self.by_repo = {repo: list(items) for repo, items in (by_repo or {}).items()}
        self.pulls = dict(pulls or {})
        self.events = []
        self.limit = limit
        self.issues = {
            item["number"]: item
            for items in self.by_repo.values()
            for item in items
        }

    def _event(self, *event):
        if len(self.events) >= self.limit:
            raise AssertionError(f"remote call limit exceeded: {event!r}")
        self.events.append(event)

    def open_issues(self, repo):
        self._event("open", repo)
        return [
            item for item in self.by_repo.get(repo, [])
            if item.get("state", "OPEN") == "OPEN"
        ]

    def issue(self, repo, n):
        self._event("issue", repo, n)
        return super().issue(repo, n)

    def comments(self, repo, n):
        self._event("comments", repo, n)
        return super().comments(repo, n)

    def edit_labels(self, repo, n, add=(), remove=()):
        self._event("labels", repo, n, tuple(add), tuple(remove))
        return super().edit_labels(repo, n, add, remove)

    def create_comment(self, repo, n, body):
        self._event("comment", repo, n, body)
        return super().create_comment(repo, n, body)

    def edit_comment(self, repo, comment_id, body):
        self._event("edit", repo, comment_id, body)
        return super().edit_comment(repo, comment_id, body)

    def close(self, repo, n, not_planned=False):
        self._event("close", repo, n, not_planned)
        return super().close(repo, n, not_planned)

    def pull(self, url):
        self._event("pull", url)
        return super().pull(url)

    def label_pull(self, url, add="", remove=""):
        self._event("label_pull", url, add, remove)
        return super().label_pull(url, add, remove)

    def ready_pull(self, url):
        self._event("ready", url)
        return super().ready_pull(url)

    def branch_pulls(self, repo, branch):
        self._event("branch_pulls", repo, branch)
        return super().branch_pulls(repo, branch)

    def disarm_pull(self, url):
        self._event("disarm", url)
        return super().disarm_pull(url)


class RecordlessBoundaries:
    """Small Git and launch fakes; no runner branch is replaced."""

    def __init__(self, home: Path, statuses=None, launcher=None, limit=200):
        self.home = home
        self.statuses = dict(statuses or {})
        self.launcher_result = launcher or {}
        self.git_events = []
        self.launch_events = []
        self.limit = limit
        self.land_events = []
        self.launched = False
        self.lane_ref = ""

    def run(self, runner, args, allow_dry=False, cwd=None, check=True):
        if len(self.git_events) >= self.limit:
            raise AssertionError(f"git call limit exceeded: {args!r}")
        self.git_events.append((tuple(str(arg) for arg in args), str(cwd) if cwd else ""))
        if args[:3] == ["git", "-C", str(runner.paths.clone)] and "worktree" in args:
            if "add" in args:
                if "-B" in args:
                    target = Path(args[args.index("-B") + 2])
                elif "-b" in args:
                    target = Path(args[args.index("-b") + 2])
                else:
                    target = Path(args[args.index("add") + 1])
                target.mkdir(parents=True, exist_ok=True)
        if args[:2] == ["gh", "repo"]:
            (runner.paths.clone / ".git").mkdir(parents=True, exist_ok=True)
        return subprocess.CompletedProcess(args, 0, "", "")

    def land_git(self, repo, *args, **kwargs):
        event = (str(repo), tuple(str(arg) for arg in args))
        if len(self.git_events) >= self.limit:
            raise AssertionError(f"git call limit exceeded: {event!r}")
        self.git_events.append(event)
        proc = subprocess.CompletedProcess(list(args), 0, "", "")
        if self.lane_ref and tuple(str(arg) for arg in args)[:4] == (
            "ls-remote", "origin", "refs/heads/agents/*"
        ) and self.launched:
            proc.stdout = f"{'c' * 40}\trefs/heads/{self.lane_ref}\n"
        return proc

    def land(self, lane, base, **kwargs):
        self.land_events.append((lane, base, kwargs.get("expected_sha")))
        return {"parent": "", "merge": "d" * 40}

    def launch(self, runner, label, worktree, prompt, log):
        if len(self.launch_events) >= self.limit:
            raise AssertionError(f"launch call limit exceeded: {label!r}")
        self.launch_events.append((
            label,
            str(worktree.relative_to(self.home)),
            prompt,
        ))
        self.launched = True
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text("recordless launcher fixture\n")
        status = self.statuses.get(label)
        if status is not None:
            status_path = (
                worktree / "build" / "retro" / f"{status[1]}.status.json"
                if isinstance(status, tuple)
                else runner.paths.status_file(label)
            )
            status_path.parent.mkdir(parents=True, exist_ok=True)
            status_path.write_text(json.dumps(
                status[0] if isinstance(status, tuple) else status
            ))
        configured = self.launcher_result.get(label, {})
        seed = configured.get("retro_seed")
        if seed:
            path = worktree / "build" / "retro" / seed["name"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(seed["value"]))
        runner.guard_tampered = configured.get("tampered", False)
        runner.t3_stray = configured.get("stray", False)
        runner.stray = configured.get("stray", False)
        return configured.get("code", 0)


class RecordlessAckGitHub(RecordlessTraceGitHub):
    def __init__(self, by_repo, old, head, pr=17):
        super().__init__(by_repo)
        self.old = old
        self.head = head
        self.pr = pr

    def commit_record(self, repo, sha):
        self._event("commit_record", repo, sha)
        return {
            "committer": {"login": "web-flow"},
            "commit": {
                "message": f"merge ({self.pr})",
                "verification": {"verified": True, "reason": "valid"},
            },
        }

    def commit_pulls(self, repo, sha):
        self._event("commit_pulls", repo, sha)
        return [{
            "number": self.pr,
            "merged_at": "2026-11-22T12:00:00Z",
            "merge_commit_sha": self.head,
            "base": {"ref": "main"},
            "head": {"sha": self.head},
        }]

    def live_requirements(self, repo, branch):
        self._event("requirements", repo, branch)
        return {
            "problems": [],
            "contexts": [("pr-checks", 77)],
            "updated_at": datetime(2026, 11, 21, tzinfo=timezone.utc),
        }

    def check_runs(self, repo, sha):
        self._event("checks", repo, sha)
        return [{
            "name": "pr-checks",
            "id": 1,
            "app": {"id": 77},
            "conclusion": "success",
            "completed_at": "2026-11-22T13:00:00Z",
        }]


class RecordlessQueueErrorGitHub(RecordlessTraceGitHub):
    def open_issues(self, repo):
        self._event("open", repo)
        raise ht.TriageError("synthetic queue failure")


class RecordlessAckBoundaries(RecordlessBoundaries):
    def __init__(self, home, old, head):
        super().__init__(home)
        self.old = old
        self.head = head

    def land_git(self, repo, *args, **kwargs):
        proc = super().land_git(repo, *args, **kwargs)
        values = tuple(str(arg) for arg in args)
        if values[:3] == ("ls-remote", "origin", "refs/heads/main"):
            proc.stdout = f"{self.head}\trefs/heads/main\n"
        elif values[:2] == ("rev-list", "--first-parent"):
            proc.stdout = self.head
        elif values[:3] == ("rev-list", "--parents", "-n1"):
            proc.stdout = f"{self.head} {self.old}\n"
        return proc


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

    def test_recordless_both_admissions_choose_priority_and_keep_fixed_bytes(self):
        self.maxDiff = None
        request_old = t.issue(
            41, created="2026-10-12T00:00:00Z"
        )
        request_priority = t.issue(
            42, labels=["Priority"], created="2026-10-13T00:00:00Z"
        )
        nightly_old = t.issue(
            51,
            labels=["Nightly Fix"],
            author="github-actions",
            created="2026-10-12T00:00:00Z",
        )
        nightly_priority = t.issue(
            52,
            labels=["Nightly Fix", "Priority"],
            author="github-actions",
            created="2026-10-13T00:00:00Z",
        )
        gh = RecordlessTraceGitHub({
            self.cfg["request_repo"]: [request_old, request_priority],
            self.cfg["nightly"]["repo"]: [nightly_old, nightly_priority],
        })
        primary_data = self.legacy(
            opaque_extension={"preserve": ["request", 1]}
        )
        nightly_data = self.legacy(
            opaque_extension={"preserve": ["nightly", 2]}
        )
        self.write_raw(self.paths.state, primary_data)
        nightly_path = ht.Paths(self.cfg, self.home, "nightly-").state
        self.write_raw(nightly_path, nightly_data)
        boundaries = RecordlessBoundaries(self.home)

        result = self.main_golden(
            ["tick", "--dry-run", "--max-items", "2"], self.cfg, gh, boundaries
        )

        self.assertEqual(
            result,
            (
                0,
                "[dry-run] would work #42: [Bug] Thing 42\n"
                "[dry-run] queued #41: [Bug] Thing 41\n"
                "[dry-run] would work #52: [Bug] Thing 52\n"
                "[dry-run] queued #51: [Bug] Thing 51\n",
                "",
            ),
        )
        self.assertEqual(gh.events, [
            ("open", self.cfg["request_repo"]),
            ("open", self.cfg["request_repo"]),
            ("open", self.cfg["request_repo"]),
            ("open", self.cfg["nightly"]["repo"]),
            ("open", self.cfg["nightly"]["repo"]),
            ("open", self.cfg["nightly"]["repo"]),
        ])
        clone = str(self.paths.clone)
        self.assertEqual(boundaries.git_events, [
            (("gh", "repo", "clone", self.cfg["product_repo"], clone), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              self.cfg["product_base"]), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              self.cfg["product_base"]), ""),
        ])
        self.assertEqual(boundaries.launch_events, [])
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state-nightly.json": self.saved_bytes(nightly_data),
            ".local/state/hass-triage/state.json": self.saved_bytes(primary_data),
            ".local/state/hass-triage/tick.lock": b"4242",
        })

    def test_recordless_acknowledgements_ignore_bad_primary_and_keep_base_history(self):
        old = "a" * 40
        head = "b" * 40
        cfg = dict(self.cfg)
        cfg["workflow_base"] = cfg["product_base"]
        cfg["nightly"] = None
        self.write_raw(self.paths.state, "{")
        base = self.paths.state_dir / "workflow-base.json"
        pause = self.paths.state_dir / "SELF_CHANGE_PAUSED"
        pause_info = self.paths.state_dir / "SELF_CHANGE_PAUSED.json"
        gh = RecordlessAckGitHub(
            {cfg["request_repo"]: []}, old, head
        )
        boundaries = RecordlessAckBoundaries(self.home, old, head)
        land = self.paths.root / "land" / cfg["product_repo"].split("/")[-1]
        (land / ".git").mkdir(parents=True)

        def seed_pause():
            base.parent.mkdir(parents=True, exist_ok=True)
            base.write_text(json.dumps({"main": old}, indent=2, sort_keys=True))
            pause.write_text("unexpected workflow base move\n")
            pause_info.write_text(json.dumps({
                "base": "main",
                "sha": head,
                "expected": old,
                "moves": [],
                "when": "tick",
                "at": "2026-11-23T12:00:00Z",
            }))

        seed_pause()
        accepted = self.main_golden(
            ["ack-base", head], cfg, gh, boundaries
        )
        self.assertEqual(accepted, (
            0,
            "Accepted bbbbbbbbbb as the workflow base; SELF_CHANGE_PAUSED cleared.\n",
            "",
        ))

        seed_pause()
        verified = self.main_golden(
            ["ack-verified"], cfg, gh, boundaries
        )
        self.assertEqual(verified, (
            0,
            "Accepted 1 PR merges: #17; head bbbbbbbbbb; "
            "SELF_CHANGE_PAUSED cleared.\n",
            "",
        ))
        self.assertEqual(gh.events, [
            ("requirements", cfg["product_repo"], "main"),
            ("commit_record", cfg["product_repo"], head),
            ("commit_pulls", cfg["product_repo"], head),
            ("checks", cfg["product_repo"], head),
        ])
        self.assertEqual(boundaries.git_events, [
            (str(land), ("ls-remote", "origin", "refs/heads/main")),
            (str(land), ("ls-remote", "origin", "refs/heads/main")),
            (str(land), ("fetch", "-q", "origin",
                         "+refs/heads/main:refs/remotes/origin/main")),
            (str(land), ("merge-base", "--is-ancestor", old, head)),
            (str(land), ("rev-list", "--first-parent",
                         "--max-count=201", f"{old}..{head}")),
            (str(land), ("rev-list", "--parents", "-n1", head)),
            (str(land), ("ls-remote", "origin", "refs/heads/main")),
        ])
        ack_log = {
            "at": "2026-11-23T12:00:00Z",
            "contexts": ["pr-checks"],
            "from": old,
            "mode": "verified",
            "prs": [17],
            "session": "owner",
            "to": head,
        }
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/ack.lock": b"",
            ".local/state/hass-triage/ack-log.jsonl":
                (json.dumps(ack_log, sort_keys=True) + "\n").encode(),
            ".local/state/hass-triage/state.json": b"{",
            ".local/state/hass-triage/tick.lock": b"4242",
            ".local/state/hass-triage/workflow-base.json":
                json.dumps({"main": head}, indent=2, sort_keys=True).encode(),
        })

    def test_recordless_tick_routes_merging_parked_recovery_and_stored_finish(self):
        self.maxDiff = None
        repo = self.cfg["request_repo"]
        product = self.cfg["product_repo"]
        merged_62 = f"https://github.com/{product}/pull/62"
        merged_63 = f"https://github.com/{product}/pull/63"
        parked_67 = f"https://github.com/{product}/pull/67"
        issues = [
            t.issue(62, labels=["Merging"], created="2026-10-01T00:00:00Z"),
            t.issue(63, labels=["Needs Decision"], created="2026-10-02T00:00:00Z"),
            t.issue(64, labels=["In Progress"], created="2026-10-03T00:00:00Z"),
            t.issue(65, labels=["In Progress"], created="2026-10-04T00:00:00Z"),
            t.issue(66, labels=["Blocked"], created="2026-10-05T00:00:00Z"),
            t.issue(67, labels=["Needs Decision"], created="2026-10-06T00:00:00Z"),
        ]
        finish_62 = {"state": "done", "summary": "merged sixty-two"}
        finish_63 = {"state": "done", "summary": "merged sixty-three"}
        finish_64 = {"state": "done", "summary": "stored finish sixty-four"}
        hold_path = self.paths.worktrees / "64"
        hold_path.mkdir(parents=True)
        self.paths.worktrees.joinpath("62").mkdir(parents=True)
        state_data = self.legacy(
            attempts={"65": 1},
            merging={"62": {
                "pr": merged_62, "status": finish_62, "since": 1
            }},
            parked={
                "63": {"pr": merged_63, "status": finish_63, "since": 1},
                "67": {
                    "pr": parked_67,
                    "status": finish_63,
                    "since": 1795435200.0,
                },
            },
            archive_sessions={"request-64": {
                "name": "request-64",
                "session": "request-64-fixed",
                "path": str(hold_path),
            }},
            archive_holds={"request-64": {
                "name": "request-64",
                "path": str(hold_path),
                "reason": "sidecar_archive_io",
                "since": "2026-11-22T00:00:00Z",
                "finish": {
                    "kind": "done", "status": finish_64, "pr": merged_63
                },
            }},
            opaque_extension={"preserve": ["maintenance", 3]},
        )
        self.write_raw(self.paths.state, state_data)
        gh = RecordlessTraceGitHub(
            {repo: issues},
            {
                merged_62: {"state": "MERGED", "url": merged_62, "labels": []},
                merged_63: {"state": "MERGED", "url": merged_63, "labels": []},
                parked_67: {"state": "OPEN", "url": parked_67, "labels": []},
            },
        )
        for number in (66, 67):
            gh.comment_store[number] = [
                {
                    "id": 700 + number,
                    "body": f"<!-- hass-triage:{number}:blocked -->",
                    "user": {"login": "sfenton-agent"},
                    "created_at": "2026-11-22T00:00:00Z",
                },
                {
                    "id": 800 + number,
                    "body": "pick the second option",
                    "user": {"login": "SFenton"},
                    "created_at": "2026-11-23T00:00:00Z",
                },
            ]
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        boundaries = RecordlessBoundaries(self.home)

        result = self.main_golden(
            ["tick", "--dry-run", "--max-items", "1"],
            cfg,
            gh,
            boundaries,
        )

        self.assertEqual(result, (
            0,
            "#66: owner replied; re-queued\n"
            "#67: owner replied; re-queued\n"
            "#65: worker gone; re-queued\n"
            "[dry-run] would work #65: [Bug] Thing 65\n"
            "[dry-run] queued #66: [Bug] Thing 66\n"
            "[dry-run] queued #67: [Bug] Thing 67\n",
            "",
        ))
        self.assertIn(
            ("pull", merged_62), gh.events
        )
        self.assertIn(
            ("pull", merged_63), gh.events
        )
        self.assertIn(
            ("label_pull", parked_67, "", "Needs Decision"), gh.events
        )
        self.assertIn(
            ("close", repo, 62, False), gh.events
        )
        self.assertIn(
            ("close", repo, 63, False), gh.events
        )
        self.assertIn(
            ("close", repo, 64, False), gh.events
        )
        self.assertIn(
            ("labels", repo, 65, (), ("In Progress",)), gh.events
        )
        reopened = json.loads(self.paths.state.read_text())
        expected_history = [
            {
                "at": "2026-11-23T12:00:00Z",
                "detail": merged_62,
                "issue": 62,
                "outcome": "done",
            },
            {
                "at": "2026-11-23T12:00:00Z",
                "detail": merged_63,
                "issue": 63,
                "outcome": "done",
            },
            {
                "at": "2026-11-23T12:00:00Z",
                "detail": merged_63,
                "issue": 64,
                "outcome": "done",
            },
        ]
        self.assertEqual(reopened, self.legacy(
            attempts={"65": 1},
            history=expected_history,
            replies={"66": 866, "67": 867},
            resumed={"66": "2026-11-23T00:00:00Z"},
            picked={"67": parked_67},
            opaque_extension={"preserve": ["maintenance", 3]},
        ))
        self.assertEqual(boundaries.launch_events, [])
        removed = {
            args[-1]
            for args, _cwd in boundaries.git_events
            if "worktree" in args and "remove" in args
        }
        self.assertIn(str(self.paths.worktrees / "62"), removed)
        self.assertIn(str(self.paths.worktrees / "64"), removed)
        self.assertNotIn(str(self.paths.worktrees / "63"), removed)
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state.json": self.saved_bytes(reopened),
            ".local/state/hass-triage/tick.lock": b"4242",
        })

    def test_recordless_scheduled_manual_job_and_retro_reach_both_saves_and_enqueue(self):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        self.write_raw(self.paths.state, self.legacy(
            jobs={"researcher": {
                "last_run": "2026-01-01T00:00:00Z",
                "outcome": "old",
            }},
            opaque_extension={"preserve": ["jobs", 4]},
        ))
        gh = RecordlessTraceGitHub({cfg["request_repo"]: []})
        (self.paths.root / "land" / cfg["product_repo"].split("/")[-1] /
         ".git").mkdir(parents=True)
        landed_at = 1795435200.0
        for offset, after in (
            (-10, False),
            (10, True),
        ):
            for number in range(10):
                digest = (
                    self.paths.root / "archive" /
                    f"request-{after}-{number}" / "retro" /
                    f"flow-{number}.json"
                )
                digest.parent.mkdir(parents=True, exist_ok=True)
                triggers = (
                    [{"id": "owner_correction"}, {"id": "routing_override"}]
                    if after else []
                )
                digest.write_text(json.dumps({
                    "task": f"flow-{after}-{number}",
                    "triggers": triggers,
                    "cost": {"tokens": 2000 if after else 100},
                }))
                os.utime(digest, (landed_at + offset, landed_at + offset))
        statuses = {
            "job-researcher": {
                "state": "done",
                "summary": "job completed",
            },
            "retro-job-researcher-2026-11-23": (
                {
                    "state": "done",
                    "summary": "retro completed",
                },
                "job-researcher-2026-11-23",
            ),
        }
        boundaries = RecordlessBoundaries(self.home, statuses=statuses)

        scheduled = self.main_golden(["tick"], cfg, gh, boundaries)
        self.assertEqual(scheduled, (0, "", ""))

        task = "job-researcher-2026-11-23"
        lane = "agents/researcher-golden"
        boundaries.launched = False
        boundaries.lane_ref = lane
        boundaries.statuses["job-researcher"] = {
            "state": "done",
            "summary": "job completed",
            "lanes": [lane],
        }
        boundaries.launcher_result["job-researcher"] = {
            "retro_seed": {
                "name": f"{task}.json",
                "value": {"triggers": [{"id": "history-volume"}]},
            },
        }
        manual = self.main_golden(
            ["run-job", "researcher"], cfg, gh, boundaries
        )
        self.assertEqual(manual, (
            0,
            "job-researcher: landed agents/researcher-golden "
            "into main (dddddddddd)\ndone\n",
            "",
        ))
        queued = json.loads(ht.Paths(cfg, self.home, "retro-").state.read_text())
        self.assertEqual(
            [item["task"] for item in queued["queue"]],
            [task],
        )
        self.assertEqual(queued["queue"][0]["triggers"], ["history-volume"])

        retro = self.main_golden(["tick"], cfg, gh, boundaries)
        self.assertEqual(retro, (0, "", ""))
        self.assertEqual(
            [(label, tree) for label, tree, _prompt in boundaries.launch_events],
            [
                ("job-researcher", "hass-agents/worktrees/job-researcher"),
                ("job-researcher", "hass-agents/worktrees/job-researcher"),
                (
                    "retro-job-researcher-2026-11-23",
                    "hass-agents/worktrees/retro-job-researcher-2026-11-23",
                ),
            ],
        )
        self.assertEqual(
            boundaries.land_events,
            [(lane, cfg["workflow_base"], "c" * 40)],
        )
        primary = json.loads(self.paths.state.read_text())
        self.assertEqual(primary["opaque_extension"], {"preserve": ["jobs", 4]})
        self.assertEqual(primary["current"], None)
        self.assertEqual(primary["jobs"]["researcher"]["outcome"], "done")
        self.assertEqual(primary["lanes"]["job-researcher"][lane], "merged")
        self.assertEqual(
            [entry["outcome"] for entry in primary["history"]],
            ["job:done", "job:done", "retro:done"],
        )
        reopened_retro = json.loads(
            ht.Paths(cfg, self.home, "retro-").state.read_text()
        )
        self.assertEqual(reopened_retro["queue"], [])
        self.assertIsNone(reopened_retro["current"])
        self.assertEqual(
            reopened_retro["done"][-1]["outcome"],
            "done",
        )
        self.assertEqual(
            reopened_retro["done"][-1]["task"],
            task,
        )

        regression = self.main_golden(["tick"], cfg, gh, boundaries)
        self.assertEqual(regression, (
            0,
            f"revert: landed agents/revert-{'d' * 12} "
            "into main (dddddddddd)\n",
            "",
        ))
        self.assertEqual(boundaries.land_events[-1], (
            f"agents/revert-{'d' * 12}",
            cfg["workflow_base"],
            None,
        ))

    def test_recordless_run_issue_tamper_routes_block_and_disarms_pull(self):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        item = t.issue(71, created="2026-10-01T00:00:00Z")
        pull = f"https://github.com/{cfg['product_repo']}/pull/71"
        gh = RecordlessTraceGitHub({cfg["request_repo"]: [item]})
        gh.branch_pull_list = [
            {"url": pull, "state": "OPEN", "labels": []}
        ]
        self.write_raw(self.paths.state, self.legacy(
            opaque_extension={"preserve": ["tamper", 5]}
        ))
        boundaries = RecordlessBoundaries(
            self.home,
            launcher={71: {"tampered": True}},
        )

        result = self.main_golden(
            ["run-issue", "71"], cfg, gh, boundaries
        )

        self.assertEqual(
            result[0],
            0,
        )
        self.assertRegex(
            result[1],
            r"^#71: retro phase failed: \[Errno 2\] No such file or directory: "
            r"'.*/hass-agents/archive/request-71/status\.json'\nblocked\n$",
        )
        self.assertEqual(result[2], "")
        self.assertEqual(gh.events.count(
            ("branch_pulls", cfg["product_repo"], "report/71")
        ), 1)
        self.assertIn(("disarm", pull), gh.events)
        self.assertIn(
            ("label_pull", pull, "", cfg["merge"]["label"]), gh.events
        )
        self.assertIn(
            ("labels", cfg["request_repo"], 71, ("Blocked",),
             ("In Progress", "Merging", "Needs Decision")),
            gh.events,
        )
        self.assertEqual(boundaries.launch_events[0][0], 71)
        reopened = json.loads(self.paths.state.read_text())
        self.assertEqual(reopened["current"], None)
        self.assertEqual(reopened["opaque_extension"], {
            "preserve": ["tamper", 5]
        })
        self.assertEqual(reopened["history"][-1]["outcome"], "blocked:guard_tampered")
        self.assertEqual(
            reopened["history"][-1]["detail"],
            "The session changed the guard hooks, settings or triage record, "
            "so its result was not used. auto-merge on "
            f"{pull} was turned off.",
        )

    def test_recordless_manual_busy_paused_and_asymmetric_preview_modes(self):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        issue = t.issue(72)
        gh = RecordlessTraceGitHub({cfg["request_repo"]: [issue]})
        self.write_raw(self.paths.state, self.legacy(
            opaque_extension={"preserve": ["manual", 6]}
        ))
        boundaries = RecordlessBoundaries(self.home)

        with ht.writer_lock(self.paths) as admitted:
            self.assertTrue(admitted)
            self.assertEqual(
                self.main_golden(["run-issue", "72"], cfg, gh, boundaries),
                (
                    1,
                    "another runner writer is active; run-issue refused\n",
                    "",
                ),
            )
            self.assertEqual(
                self.main_golden(["run-job", "researcher"], cfg, gh, boundaries),
                (
                    1,
                    "another runner writer is active; run-job refused\n",
                    "",
                ),
            )
        self.assertEqual(
            self.main_golden(["pause"], cfg, gh, boundaries),
            (0, "Paused: no new work starts until `resume`.\n", ""),
        )
        self.assertTrue(self.paths.paused.exists())
        self.assertEqual(
            self.main_golden(["run-job", "researcher"], cfg, gh, boundaries),
            (0, "paused\n", ""),
        )

        preview = self.main_golden(
            ["run-issue", "72", "--dry-run"], cfg, gh, boundaries
        )
        self.assertEqual((preview[0], preview[2]), (0, ""))
        self.assertTrue(
            preview[1].startswith(
                "# Fenton Home triage agent: request #72\n"
            ),
        )
        self.assertIn("report/72", preview[1])
        self.assertIn("## The request", preview[1])
        self.assertEqual(
            json.loads(self.paths.state.read_text())["opaque_extension"],
            {"preserve": ["manual", 6]},
        )
        self.assertEqual(
            self.main_golden(["resume"], cfg, gh, boundaries),
            (0, "Resumed.\n", ""),
        )
        self.assertFalse(self.paths.paused.exists())
        self.assertEqual(boundaries.git_events, [])
        self.assertEqual(boundaries.launch_events, [])

    def test_recordless_status_formats_under_real_lock_with_independent_queue_error(self):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        primary = self.legacy(
            opaque_extension={"preserve": ["status", 7]}
        )
        self.write_raw(self.paths.state, primary)
        retained_nightly = ht.Paths(self.cfg, self.home, "nightly-").state
        self.write_raw(retained_nightly, "{")
        retro = ht.Paths(self.cfg, self.home, "retro-").state
        self.write_raw(retro, self.legacy(queue=[], done=[]))
        gh = RecordlessQueueErrorGitHub({cfg["request_repo"]: []})
        boundaries = RecordlessBoundaries(self.home)

        with ht.writer_lock(self.paths) as admitted:
            self.assertTrue(admitted)
            self.paths.lock.write_text("4242")
            text = self.main_golden(["status"], cfg, gh, boundaries)
            encoded = self.main_golden(["status", "--json"], cfg, gh, boundaries)

        self.assertEqual(text, (
            0,
            "paused: False   installed: False   running: no\n"
            "self-changes: running\n"
            "auth: claude logged in\n"
            "state store nightly: parse (exists yes)\n"
            "queue: #None \n",
            "",
        ))
        self.assertEqual((encoded[0], encoded[2]), (0, ""))
        report = json.loads(encoded[1])
        self.assertEqual(report["queue"], [{
            "error": "synthetic queue failure"
        }])
        self.assertEqual(report["nightly_queue"], [])
        self.assertEqual(report["state_loads"], [{
            "store": "nightly",
            "kind": "parse",
            "exists": "yes",
        }])
        self.assertEqual(report["retro_queue"], [])
        self.assertEqual(gh.events, [
            ("open", cfg["request_repo"]),
            ("open", cfg["request_repo"]),
        ])
        self.assertEqual(boundaries.git_events, [])
        self.assertEqual(boundaries.launch_events, [])
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state-nightly.json": b"{",
            ".local/state/hass-triage/state-retro.json":
                json.dumps(self.legacy(queue=[], done=[])).encode(),
            ".local/state/hass-triage/state.json": json.dumps(primary).encode(),
            ".local/state/hass-triage/tick.lock": b"4242",
        })

    def test_recordless_request_post_launch_save_failure_preserves_disk_authority(self):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        issue = t.issue(81, created="2026-10-01T00:00:00Z")
        gh = RecordlessTraceGitHub({cfg["request_repo"]: [issue]})
        self.write_raw(self.paths.state, self.legacy(
            opaque_extension={"preserve": ["request-save", 8]}
        ))
        boundaries = RecordlessBoundaries(
            self.home,
            statuses={81: {
                "state": "blocked",
                "summary": "worker stopped",
            }},
        )
        original_save = ht.State.save
        primary_saves = 0

        def save(state):
            nonlocal primary_saves
            if state.path == self.paths.state:
                primary_saves += 1
                if primary_saves == 4:
                    raise ht.StateSaveError(state.path.name, "parent_sync")
            return original_save(state)

        with mock.patch.object(
            ht.State, "save", autospec=True, side_effect=save
        ):
            result = self.main_golden(
                ["run-issue", "81"], cfg, gh, boundaries
            )

        self.assertEqual(result, (
            4,
            "",
            "error: state persistence failed during parent_sync "
            "for state.json\n",
        ))
        self.assertEqual(primary_saves, 4)
        self.assertIn(
            (
                "labels",
                cfg["request_repo"],
                81,
                ("Blocked",),
                ("In Progress", "Merging", "Needs Decision"),
            ),
            gh.events,
        )
        reopened = json.loads(self.paths.state.read_text())
        self.assertEqual(reopened["current"]["issue"], 81)
        self.assertEqual(reopened["attempts"], {"81": 1})
        self.assertEqual(reopened["history"], [])
        self.assertEqual(reopened["opaque_extension"], {
            "preserve": ["request-save", 8]
        })
        self.assertTrue(
            (self.paths.root / "archive" / "request-81" / "status.json").is_file()
        )


if __name__ == "__main__":
    unittest.main()
