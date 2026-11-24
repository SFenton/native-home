"""``tools/bg_run.py``: a refused ``killpg`` still ends in exit 124 and a digest, and the digest's sha and lane come from the command's cwd."""

import importlib.util
import os
import json
import signal
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import bg_run  # noqa: E402
import factory_lease  # noqa: E402


def git(directory, *args):
    return subprocess.run(["git", *args], cwd=directory, capture_output=True, text=True, check=True).stdout.strip()


class FakeKillpg:
    """Stands in for ``os.killpg``: raises ``PermissionError`` for a real signal, answers the liveness probe (signal 0) as gone."""

    def __init__(self):
        self.calls = []

    def __call__(self, pgid, sig):
        self.calls.append((pgid, int(sig)))
        if int(sig) == 0:
            raise ProcessLookupError
        raise PermissionError("operation not permitted")


class KillFallbackTests(unittest.TestCase):
    def test_a_killpg_permission_error_still_gives_exit_124_and_a_digest(self):
        """Fails if: PermissionError escapes kill_group, the hung command survives, or no digest is written."""
        fake = FakeKillpg()
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(bg_run.os, "killpg", fake), redirect_stdout(StringIO()):
            status = bg_run.main(["hang", "--dir", tmp, "--timeout", "1", "--", "sleep", "30"])
            digest = (Path(tmp) / "hang.digest").read_text()
        self.assertEqual(status, 124)
        self.assertTrue(digest.strip())
        self.assertTrue(fake.calls)

    def test_kill_group_falls_back_to_killing_the_leader(self):
        """Fails if: the leader keeps running after killpg is refused."""
        process = subprocess.Popen(["sleep", "30"], start_new_session=True)
        try:
            with mock.patch.object(bg_run.os, "killpg", FakeKillpg()):
                bg_run.kill_group(process, grace=0.2)
            self.assertIsNotNone(process.poll())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


class CwdStampTests(unittest.TestCase):
    def test_a_command_run_in_another_worktree_stamps_that_worktrees_sha_and_lane(self):
        """Fails if: the digest carries the launching checkout's sha or lane, not the command's cwd."""
        with tempfile.TemporaryDirectory() as tmp:
            other = Path(tmp) / "other-lane"
            other.mkdir()
            git(other, "init", "-q")
            git(other, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "x")
            sha = git(other, "rev-parse", "--short=8", "HEAD")
            logs = Path(tmp) / "logs"
            with redirect_stdout(StringIO()):
                status = bg_run.run("stamp", ["true"], logs, None, cwd=str(other))
            digest = (logs / "stamp.digest").read_text()
        self.assertEqual(status, 0)
        self.assertIn(sha, digest)
        self.assertIn("other-lane", digest)

    def test_the_default_cwd_is_the_current_directory(self):
        """Fails if: a run with no cwd stamps the bg_run script's checkout instead of where it was launched."""
        with tempfile.TemporaryDirectory() as tmp:
            here = Path(tmp) / "here-lane"
            here.mkdir()
            git(here, "init", "-q")
            git(here, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "x")
            old = os.getcwd()
            os.chdir(here)
            try:
                with redirect_stdout(StringIO()):
                    bg_run.run("here", ["true"], Path(tmp) / "logs", None)
            finally:
                os.chdir(old)
            digest = (Path(tmp) / "logs" / "here.digest").read_text()
        self.assertIn("here-lane", digest)


class TaskStampTests(unittest.TestCase):
    def test_task_flag_and_environment_stamp_the_digest(self):
        """Fails if: --task or $SH_TASK does not reach the digest's RESULT line, or an unset task stamps one."""
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp) / "logs"
            with redirect_stdout(StringIO()):
                self.assertEqual(bg_run.main(["flag", "--dir", str(logs), "--task", "parity-loop", "--", "true"]), 0)
                self.assertEqual(bg_run.main(["none", "--dir", str(logs), "--task", "", "--", "true"]), 0)
            flag, none = ((logs / f"{n}.digest").read_text().splitlines()[0] for n in ("flag", "none"))
        self.assertIn("task=parity-loop", flag)
        self.assertNotIn("task=", none)

    def test_the_environment_task_is_the_default(self):
        """Fails if: $SH_TASK is not the default for --task."""
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp) / "logs"
            script = ("import sys; sys.path.insert(0, %r); import bg_run; sys.exit(bg_run.main(['env', '--dir', %r, '--', 'true']))"
                      % (str(Path(bg_run.__file__).parent), str(logs)))
            done = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True,
                                  env={"PATH": "/usr/bin:/bin", "SH_TASK": "sdui-review"})
            self.assertEqual(done.returncode, 0, done.stderr)
            head = (logs / "env.digest").read_text().splitlines()[0]
        self.assertIn("task=sdui-review", head)


class MarkerLeaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.origin = self.root / "origin.git"
        self.repo = self.root / "repo"
        self.lane = self.root / "lane"
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_AUTHOR_NAME": "factory-test",
            "GIT_AUTHOR_EMAIL": "factory@example.invalid",
            "GIT_COMMITTER_NAME": "factory-test",
            "GIT_COMMITTER_EMAIL": "factory@example.invalid",
            "LC_ALL": "C",
        }
        self.git(self.root, "init", "-q", "--bare", "-b", "main", str(self.origin))
        self.git(self.root, "clone", "-q", str(self.origin), str(self.repo))
        (self.repo / "tracked.txt").write_text("base\n")
        self.git(self.repo, "add", "-A")
        self.git(self.repo, "commit", "-qm", "base")
        self.git(self.repo, "push", "-q", "-u", "origin", "main")
        self.git(
            self.repo,
            "worktree",
            "add",
            "-q",
            "-b",
            "agents/proof",
            str(self.lane),
            "main",
        )
        self.runs = self.lane / "build" / "runs"
        self.runs.mkdir(parents=True)

    def git(self, cwd, *arguments):
        return subprocess.run(
            ["git", *arguments],
            cwd=cwd,
            env=self.env,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    def create_parent_lease(self):
        store = factory_lease.LeaseStore.for_repo(self.lane)
        worktree_id, _branch_id = store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/proof",
        )
        return store, worktree_id

    def capture_command(self, destination, marker, delay=0):
        code = (
            "import json,pathlib,sys,time; "
            "time.sleep(float(sys.argv[3])); "
            "data=json.loads(pathlib.Path(sys.argv[1]).read_text()); "
            "pathlib.Path(sys.argv[2]).write_text(json.dumps(data))"
        )
        return [
            sys.executable,
            "-c",
            code,
            str(marker),
            str(destination),
            str(delay),
        ]

    def test_marker_is_atomic_and_visible_to_the_first_child_instruction(self):
        marker = self.runs / "visible.running"
        captured = self.root / "captured.json"
        with redirect_stdout(StringIO()):
            status = bg_run.run(
                "visible",
                self.capture_command(captured, marker),
                self.runs,
                None,
                cwd=str(self.lane),
            )
        self.assertEqual(status, 0)
        record = json.loads(captured.read_text())
        self.assertEqual(
            {
                "v",
                "pid",
                "label",
                "started",
                "cwd",
                "lease_id",
                "start",
                "pgid",
            },
            set(record),
        )
        self.assertEqual(record["pid"], os.getpid())
        self.assertEqual(record["label"], "visible")
        self.assertIsNone(record["lease_id"])
        self.assertIsInstance(record["start"], str)
        self.assertFalse(marker.exists())
        self.assertFalse(marker.with_name(marker.name + ".lock").exists())
        self.assertTrue((self.runs / "visible.digest").exists())

    def test_leased_standard_run_is_released_and_keeps_extended_marker_readable(self):
        store, parent_id = self.create_parent_lease()
        parent_before = [
            record
            for record in store.read_records()[0]
            if record["lease_id"] == parent_id
        ][0]
        marker = self.runs / "leased.running"
        captured = self.root / "leased.json"
        with redirect_stdout(StringIO()):
            status = bg_run.run(
                "leased",
                self.capture_command(captured, marker, 0.1),
                self.runs,
                None,
                cwd=str(self.lane),
            )
        self.assertEqual(status, 0)
        record = json.loads(captured.read_text())
        self.assertEqual(record["v"], 1)
        self.assertIsInstance(record["lease_id"], str)
        self.assertIsInstance(record["pgid"], int)
        records = store.read_records()[0]
        run_record = [
            value
            for value in records
            if value["lease_id"] == record["lease_id"]
        ][0]
        self.assertEqual(run_record["state"], "released")
        self.assertEqual(run_record["release"]["reason"], "ended")
        parent_after = [
            value for value in records if value["lease_id"] == parent_id
        ][0]
        self.assertEqual(
            parent_after["generation"], parent_before["generation"] + 1
        )
        self.assertFalse(marker.exists())

    def test_lease_failure_never_suppresses_legacy_marker_or_digest(self):
        marker = self.runs / "unleased.running"
        captured = self.root / "unleased.json"
        with mock.patch.object(
            factory_lease.LeaseStore,
            "for_repo",
            side_effect=factory_lease.LeaseError("synthetic"),
        ), redirect_stdout(StringIO()):
            status = bg_run.run(
                "unleased",
                self.capture_command(captured, marker),
                self.runs,
                None,
                cwd=str(self.lane),
            )
        self.assertEqual(status, 0)
        record = json.loads(captured.read_text())
        self.assertEqual(record["pid"], os.getpid())
        self.assertEqual(record["label"], "unleased")
        self.assertIsNone(record["lease_id"])
        self.assertTrue((self.runs / "unleased.digest").exists())
        self.assertFalse(marker.exists())

    def test_custom_directory_does_not_renew_or_adopt_the_command_worktree(self):
        store, parent_id = self.create_parent_lease()
        before = [
            record
            for record in store.read_records()[0]
            if record["lease_id"] == parent_id
        ][0]
        custom = self.root / "custom-runs"
        custom.mkdir()
        captured = self.root / "custom.json"
        marker = custom / "custom.running"
        with redirect_stdout(StringIO()):
            status = bg_run.run(
                "custom",
                self.capture_command(captured, marker),
                custom,
                None,
                cwd=str(self.lane),
            )
        self.assertEqual(status, 0)
        self.assertIsNone(json.loads(captured.read_text())["lease_id"])
        after = [
            record
            for record in store.read_records()[0]
            if record["lease_id"] == parent_id
        ][0]
        self.assertEqual(after["generation"], before["generation"])

    def test_contested_marker_is_never_enriched_replaced_or_removed(self):
        marker = self.runs / "contested.running"
        original = b'{"pid":1,"label":"contested","sentinel":"owned"}\n'
        marker.write_bytes(original)
        child_code = (
            "import fcntl,os,sys\n"
            "fd=os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)\n"
            "fcntl.flock(fd, fcntl.LOCK_EX)\n"
            "print('locked', flush=True)\n"
            "sys.stdin.readline()\n"
        )
        lock_path = marker.with_name(marker.name + ".lock")
        child = subprocess.Popen(
            [sys.executable, "-c", child_code, str(lock_path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            env=self.env,
        )
        try:
            self.assertEqual(child.stdout.readline().strip(), "locked")
            with redirect_stdout(StringIO()):
                status = bg_run.run(
                    "contested", ["true"], self.runs, None, cwd=str(self.lane)
                )
            self.assertEqual(status, 0)
            self.assertEqual(marker.read_bytes(), original)
            self.assertTrue(lock_path.exists())
        finally:
            child.stdin.write("\n")
            child.stdin.flush()
            child.wait(timeout=10)
            child.stdin.close()
            child.stdout.close()

    def test_stale_marker_is_replaced_and_seen_by_stop_guard(self):
        marker = self.runs / "stale.running"
        marker.write_text(
            json.dumps(
                {
                    "pid": 999999,
                    "label": "stale",
                    "sentinel": "dead",
                }
            )
        )
        captured = self.root / "stale-jobs.json"
        code = (
            "import importlib.util,json,pathlib,sys\n"
            "spec=importlib.util.spec_from_file_location('stop_guard',sys.argv[1])\n"
            "module=importlib.util.module_from_spec(spec)\n"
            "spec.loader.exec_module(module)\n"
            "jobs=module.running_jobs("
            "{'cwd':sys.argv[2]}, b'bg_run.py stale')\n"
            "pathlib.Path(sys.argv[3]).write_text(json.dumps(jobs))\n"
        )
        command = [
            sys.executable,
            "-c",
            code,
            str(TOOLS / "hooks" / "stop_continue_guard.py"),
            str(self.lane),
            str(captured),
        ]
        with mock.patch.dict(
            os.environ, {"BG_RUNS_DIR": str(self.runs)}, clear=False
        ), redirect_stdout(StringIO()):
            status = bg_run.run(
                "stale", command, self.runs, None, cwd=str(self.lane)
            )
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(captured.read_text()), ["stale"])
        self.assertFalse(marker.exists())

    def test_extended_marker_works_with_real_readers_and_triage_copier(self):
        marker = self.runs / "readers.running"
        marker.write_text(
            json.dumps(
                {
                    "v": 1,
                    "pid": os.getpid(),
                    "label": "readers",
                    "started": 1,
                    "cwd": str(self.lane),
                    "lease_id": "a" * 32,
                    "start": factory_lease.process_start(os.getpid()),
                    "pgid": os.getpgrp(),
                }
            )
        )
        guard_spec = importlib.util.spec_from_file_location(
            "stop_guard_reader", TOOLS / "hooks" / "stop_continue_guard.py"
        )
        guard = importlib.util.module_from_spec(guard_spec)
        guard_spec.loader.exec_module(guard)
        with mock.patch.object(guard, "alive", return_value=True), mock.patch.dict(
            os.environ, {"BG_RUNS_DIR": str(self.runs)}, clear=False
        ):
            self.assertEqual(
                guard.running_jobs(
                    {"cwd": str(self.lane)}, b"bg_run.py readers"
                ),
                ["readers"],
            )

        sys.path.insert(0, str(TOOLS))
        try:
            import retro_digest
        finally:
            sys.path.pop(0)
        with mock.patch.object(retro_digest.os, "kill", return_value=None):
            self.assertEqual(
                retro_digest.live_children(self.runs),
                [f"readers pid {os.getpid()} still running"],
            )

        sys.path.insert(0, str(TOOLS / "triage"))
        try:
            import hass_triage
        finally:
            sys.path.pop(0)
        runner = hass_triage.Runner.__new__(hass_triage.Runner)
        runner.paths = SimpleNamespace(root=self.root / "archive-root")
        runner.intake = None
        runner.workflow_touched = mock.Mock(return_value=[])
        runner.archive_evidence(
            "fixture",
            name="fixture",
            tree=self.lane,
            status_file=self.root / "missing-status",
            task="proof",
            digest=False,
        )
        copied = (
            runner.paths.root
            / "archive"
            / "fixture"
            / "runs"
            / "readers.running"
        )
        copied_record = json.loads(copied.read_text())
        self.assertEqual(
            set(copied_record),
            {
                "v",
                "pid",
                "label",
                "started",
                "cwd",
                "lease_id",
                "start",
                "pgid",
            },
        )
        self.assertEqual(copied_record["lease_id"], "a" * 32)

    def test_lease_survives_timeout_and_nonzero_with_released_run(self):
        store, _parent_id = self.create_parent_lease()
        with redirect_stdout(StringIO()):
            timeout_status = bg_run.run(
                "timeout",
                ["sleep", "30"],
                self.runs,
                0.05,
                cwd=str(self.lane),
            )
        with redirect_stdout(StringIO()):
            nonzero_status = bg_run.run(
                "failure",
                ["false"],
                self.runs,
                None,
                cwd=str(self.lane),
            )
        self.assertEqual(timeout_status, 124)
        self.assertNotEqual(nonzero_status, 0)
        released = [
            record
            for record in store.read_records()[0]
            if record["class"] == "run_marker"
        ]
        self.assertEqual(len(released), 2)
        self.assertTrue(
            all(
                record["state"] == "released"
                and record["release"]["reason"] == "ended"
                for record in released
            )
        )
        self.assertFalse(
            list(self.runs.glob("*.running"))
        )

    def test_lease_survives_wrapper_sigterm_and_sighup(self):
        store, _parent_id = self.create_parent_lease()
        for signum in (signal.SIGTERM, signal.SIGHUP):
            label = signal.Signals(signum).name.lower()
            marker = self.runs / f"{label}.running"
            child_code = (
                "import json,os,pathlib,signal,sys,time;"
                "json.loads(pathlib.Path(sys.argv[1]).read_text());"
                "os.kill(os.getppid(), int(sys.argv[2]));"
                "time.sleep(30)"
            )
            completed = subprocess.run(
                [
                    sys.executable,
                    str(TOOLS / "bg_run.py"),
                    label,
                    "--dir",
                    str(self.runs),
                    "--",
                    sys.executable,
                    "-c",
                    child_code,
                    str(marker),
                    str(int(signum)),
                ],
                cwd=self.lane,
                env=self.env,
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(completed.returncode, 128 + int(signum))
            self.assertFalse(marker.exists())
        released = [
            record
            for record in store.read_records()[0]
            if record["class"] == "run_marker"
        ]
        self.assertEqual(len(released), 2)
        self.assertTrue(
            all(record["state"] == "released" for record in released)
        )

    def test_lease_timeout_before_launch_keeps_legacy_marker_and_digest(self):
        marker = self.runs / "helper-timeout.running"
        captured = self.root / "helper-timeout.json"
        timeout = subprocess.TimeoutExpired(["git", "status"], 60)
        with mock.patch.object(
            factory_lease.LeaseStore,
            "for_repo",
            side_effect=timeout,
        ), redirect_stdout(StringIO()):
            status = bg_run.run(
                "helper-timeout",
                self.capture_command(captured, marker),
                self.runs,
                None,
                cwd=str(self.lane),
            )
        self.assertEqual(status, 0)
        self.assertIsNone(json.loads(captured.read_text())["lease_id"])
        self.assertTrue(
            (self.runs / "helper-timeout.digest").exists()
        )

    def test_spawn_failure_removes_only_this_invocation_marker(self):
        marker = self.runs / "spawn.running"
        with redirect_stdout(StringIO()):
            with self.assertRaises(OSError):
                bg_run.run(
                    "spawn",
                    [str(self.root / "missing-command")],
                    self.runs,
                    None,
                    cwd=str(self.lane),
                )
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
