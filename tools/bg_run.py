#!/usr/bin/env python3
"""Run a long command and print only its digest when it exits.

In the main session launch it with the Bash tool's ``run_in_background: true`` and end the turn; a sub-agent runs it in the
foreground (its background jobs die with its turn). The harness notifies the main session when it
exits, and the notification carries the digest, not the log. Never poll the log with ``until … sleep``.

    tools/bg_run.py LABEL [--timeout SECONDS] [--expect-minutes N] [--dir DIR] [--allow-empty] -- COMMAND [ARG …]

The full output goes to ``build/runs/LABEL.log`` (``--dir`` to change it) and the digest, from
``tools/log_digest.py`` (its RESULT line carries the git SHA and the worktree name of the command's working directory, not of the worktree that launched bg_run), to ``LABEL.digest`` next to it. The exit status is the command's, or 124 after
``--timeout`` (the process group is killed; if the group cannot be signalled, ``PermissionError``, the leader is killed instead, and the digest is written either way). A command that exits 0 but whose log shows a test run that executed nothing, or
whose every test skipped, digests as ``RESULT: EMPTY`` and bg_run exits 1 (``--allow-empty`` keeps the command's 0); the digest
shows ``executed N, skipped N, failed N``.

SIGTERM and SIGHUP to bg_run (the harness killing its Bash call, a closed terminal) kill the command's whole process
group (SIGTERM, SIGKILL after 20 s), write the digest, remove the ``.running`` marker and exit 128+signal, so no child
(a coverage run holding the build-database lock, say) outlives its wrapper.

The harness stops a background Bash call after 30 minutes unless the call passes ``timeout`` (milliseconds, up to 7200000).
``--expect-minutes N`` with N over 25 prints the timeout to pass; ``tools/hooks/bg_timeout_guard.py`` denies a background
coverage run or full UI run that carries none.

While the command runs, ``LABEL.running`` sits next to the log with the legacy
``pid``, ``label``, ``started`` and ``cwd`` fields plus private lease and
process-incarnation evidence. The Stop hook
``tools/hooks/stop_continue_guard.py`` reads it to refuse to end a session whose background job has not finished.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import secrets
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import log_digest  # noqa: E402
import factory_lease  # noqa: E402
from redact import redact, redact_lines  # noqa: E402


#: Seconds between SIGTERM and SIGKILL for a command's process group.
KILL_GRACE = 20
#: Signals that mean "the wrapper is going away": the command's group must go with it.
STOP_SIGNALS = (signal.SIGTERM, signal.SIGHUP)


class Terminated(Exception):
    """Raised from the signal handler so ``run`` can kill the command's group and clean up."""

    def __init__(self, signum: int) -> None:
        super().__init__(signum)
        self.signum = signum


def _raise_terminated(signum: int, _frame: object) -> None:
    raise Terminated(signum)


def group_alive(pgid: int) -> bool:
    """True while any process is left in group ``pgid``."""
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def kill_group(process: "subprocess.Popen[bytes]", grace: float = KILL_GRACE) -> None:
    """SIGTERM the command's process group, then SIGKILL whatever is left after ``grace`` seconds."""
    pgid = process.pid
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except PermissionError:  # the group is not ours to signal (a child changed its credentials): kill the leader
        process.kill()
        process.wait()
        return
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        process.poll()  # reap the leader so a zombie does not keep the group "alive"
        if not group_alive(pgid):
            return
        time.sleep(0.05)
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except PermissionError:
        process.kill()
    process.wait()


def _marker_bytes(record: dict) -> bytes:
    return (
        json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode("utf-8")


def _replace_marker(
    marker: Path, record: dict, expected: Optional[bytes] = None
) -> bytes:
    if expected is not None and marker.read_bytes() != expected:
        raise FileExistsError("marker changed")
    data = _marker_bytes(record)
    temporary = marker.parent / (
        "." + marker.name + ".tmp-" + secrets.token_hex(8)
    )
    descriptor = os.open(
        temporary,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        0o600,
    )
    try:
        os.fchmod(descriptor, 0o600)
        view = memoryview(data)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    try:
        os.replace(temporary, marker)
        directory = os.open(marker.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        try:
            temporary.unlink()
        except OSError:
            pass
    return data


def _claim_marker(marker: Path, record: dict):
    lock_path = marker.with_name(marker.name + ".lock")
    lock = os.open(
        lock_path,
        os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
        0o600,
    )
    try:
        os.fchmod(lock, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if marker.exists() or marker.is_symlink():
            try:
                lock_path.unlink()
            except OSError:
                pass
            fcntl.flock(lock, fcntl.LOCK_UN)
            os.close(lock)
            return None
        return lock, _replace_marker(marker, record)
    except Exception:
        os.close(lock)
        raise


def _release_marker(marker: Path, lock: int, expected: bytes) -> None:
    try:
        if marker.read_bytes() == expected:
            marker.unlink()
            directory = os.open(marker.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
    except OSError:
        pass
    lock_path = marker.with_name(marker.name + ".lock")
    try:
        lock_path.unlink()
    except OSError:
        pass
    try:
        fcntl.flock(lock, fcntl.LOCK_UN)
    finally:
        os.close(lock)


def _begin_lease(cwd: str, marker: Path, label: str):
    try:
        store = factory_lease.LeaseStore.for_repo(Path(cwd))
        lease_id = store.begin_run(
            Path(cwd), marker.resolve(), label, os.getpid()
        )
        return store, lease_id
    except (factory_lease.LeaseError, OSError, UnicodeError):
        return None, None


def run(label: str, command: List[str], directory: Path, timeout: Optional[float], allow_empty: bool = False,
        cwd: Optional[str] = None) -> int:
    """Run ``command`` with output to ``directory/label.log``, print its digest and return its status.

    ``cwd`` is where the command runs and where the digest's ``sha`` and ``lane`` are read from (default: the current directory)."""
    cwd = cwd or os.getcwd()
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / f"{label}.log"
    started = time.monotonic()
    status = 0
    marker = directory / f"{label}.running"
    marker_claim = None
    marker_bytes = b""
    lease_store = None
    lease_id = None
    marker_record = {
        "v": 1,
        "pid": os.getpid(),
        "label": label,
        "started": time.time(),
        "cwd": cwd,
        "lease_id": None,
        "start": factory_lease.process_start(os.getpid()) or "",
        "pgid": None,
    }
    try:
        marker_claim = _claim_marker(marker, marker_record)
        if marker_claim is not None:
            marker_claim, marker_bytes = marker_claim
    except (OSError, BlockingIOError):
        pass
    if marker_claim is not None:
        lease_store, lease_id = _begin_lease(cwd, marker, label)
        if lease_id is not None:
            enriched = dict(marker_record)
            enriched["lease_id"] = lease_id
            try:
                marker_bytes = _replace_marker(marker, enriched, marker_bytes)
                marker_record = enriched
            except OSError:
                if lease_store is not None:
                    lease_store.abort_run(lease_id)
                lease_id = None
    previous = {}
    try:
        for sig in STOP_SIGNALS:
            try:
                previous[sig] = signal.signal(sig, _raise_terminated)
            except ValueError:  # not the main thread: no handler, the old behaviour
                break
        with open(log, "wb") as handle:
            process = None
            try:
                process = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                           start_new_session=True, cwd=cwd)
                if marker_claim is not None:
                    child_record = dict(marker_record)
                    child_record["pgid"] = process.pid
                    try:
                        marker_bytes = _replace_marker(
                            marker, child_record, marker_bytes
                        )
                        marker_record = child_record
                    except OSError:
                        pass
                status = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                kill_group(process)
                status = 124
                handle.write(f"\nbg_run: hold timeout, killed after {int(timeout or 0)}s\n".encode())
            except Terminated as stop:
                for sig in previous:  # a second signal must not interrupt the cleanup
                    signal.signal(sig, signal.SIG_IGN)
                if process is not None:
                    kill_group(process)
                status = 128 + stop.signum
                handle.write(f"\nbg_run: {signal.Signals(stop.signum).name} received, killed the command's process group\n".encode())
        while previous:  # the command is gone: a late signal gets the default again, not a half-written digest
            signal.signal(*previous.popitem())
        elapsed = time.monotonic() - started
        text = redact_lines(log.read_text(encoding="utf-8", errors="replace"))
        log.write_text(text, encoding="utf-8")  # the kept log never holds a token
        sha, lane = log_digest.git_context(cwd)
        digest = redact(log_digest.digest_text(text, exit_code=status, elapsed=elapsed, label=label, log=str(log),
                                               sha=sha, lane=lane, allow_empty=allow_empty))
        if status == 0 and digest.startswith(("RESULT: EMPTY", "RESULT: MISMATCH")):
            status = 1  # an empty run is not a pass
        (directory / f"{label}.digest").write_text(digest + "\n", encoding="utf-8")
    finally:  # a failing or killed command never leaves the marker behind
        while previous:
            signal.signal(*previous.popitem())
        if lease_id is not None and lease_store is not None:
            lease_store.end_run(lease_id)
        if marker_claim is not None:
            _release_marker(marker, marker_claim, marker_bytes)
    print(digest)
    return status


def harness_note(expect_minutes: Optional[float]) -> Optional[str]:
    """The warning for a job expected to run past the harness's 30-minute background limit, or ``None``."""
    if expect_minutes is None or expect_minutes <= 25:
        return None
    return f"bg_run: harness limit is 30 min unless the Bash call passes timeout>={int(expect_minutes * 60000)}"


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--" not in argv:
        print(__doc__, file=sys.stderr)
        return 2
    split = argv.index("--")
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("label")
    parser.add_argument("--timeout", type=float)
    parser.add_argument("--expect-minutes", type=float, default=None)
    parser.add_argument("--allow-empty", action="store_true")
    parser.add_argument("--dir", type=Path, default=ROOT / "build" / "runs")
    args = parser.parse_args(argv[:split])
    command = argv[split + 1:]
    if not command:
        print("bg_run: no command after --", file=sys.stderr)
        return 2
    note = harness_note(args.expect_minutes)
    if note:
        print(note, file=sys.stderr, flush=True)
    return run(args.label, command, args.dir, args.timeout, args.allow_empty)


if __name__ == "__main__":
    sys.exit(main())
