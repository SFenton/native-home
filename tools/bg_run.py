#!/usr/bin/env python3
"""Run a long command and print only its digest when it exits.

Launch it with the Bash tool's ``run_in_background: true`` and end the turn: the harness notifies you when it
exits, and the notification carries the digest, not the log. Never poll the log with ``until … sleep``.

    tools/bg_run.py LABEL [--timeout SECONDS] [--expect-minutes N] [--dir DIR] [--allow-empty] -- COMMAND [ARG …]

The full output goes to ``build/runs/LABEL.log`` (``--dir`` to change it) and the digest, from
``tools/log_digest.py`` (its RESULT line carries the git SHA and the worktree name), to ``LABEL.digest`` next to it. The exit status is the command's, or 124 after
``--timeout`` (the process group is killed). A command that exits 0 but whose log shows a test run that executed nothing, or
whose every test skipped, digests as ``RESULT: EMPTY`` and bg_run exits 1 (``--allow-empty`` keeps the command's 0); the digest
shows ``executed N, skipped N, failed N``.

SIGTERM and SIGHUP to bg_run (the harness killing its Bash call, a closed terminal) kill the command's whole process
group (SIGTERM, SIGKILL after 20 s), write the digest, remove the ``.running`` marker and exit 128+signal, so no child
(a coverage run holding the build-database lock, say) outlives its wrapper.

The harness stops a background Bash call after 30 minutes unless the call passes ``timeout`` (milliseconds, up to 7200000).
``--expect-minutes N`` with N over 25 prints the timeout to pass; ``tools/hooks/bg_timeout_guard.py`` denies a background
coverage run or full UI run that carries none.

While the command runs, ``LABEL.running`` (JSON: pid, label, started, cwd) sits next to the log. The Stop hook
``tools/hooks/stop_continue_guard.py`` reads it to refuse to end a session whose background job has not finished.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import log_digest  # noqa: E402
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
    process.wait()


def run(label: str, command: List[str], directory: Path, timeout: Optional[float], allow_empty: bool = False) -> int:
    """Run ``command`` with output to ``directory/label.log``, print its digest and return its status."""
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / f"{label}.log"
    started = time.monotonic()
    status = 0
    marker = directory / f"{label}.running"
    try:
        marker.write_text(json.dumps({"pid": os.getpid(), "label": label, "started": time.time(), "cwd": os.getcwd()}))
    except OSError:
        pass
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
                                           start_new_session=True)
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
        if status != 0 and "devcap: HOLD TIMEOUT" in text:  # cheap pre-check: a clean run never imports the hook or runs git
            try:  # a hold timeout arms the retry guard (the foreground hook never sees a background job's output)
                sys.path.insert(0, str(Path(__file__).resolve().parent / "hooks"))
                import devcap_retry_guard
                root = devcap_retry_guard.repo_root(os.getcwd())
                if root:
                    devcap_retry_guard.arm_from_log(root, " ".join(command), status, text)
            except Exception:  # noqa: BLE001 - fail open
                pass
        sha, lane = log_digest.git_context(str(ROOT))
        digest = redact(log_digest.digest_text(text, exit_code=status, elapsed=elapsed, label=label, log=str(log),
                                               sha=sha, lane=lane, allow_empty=allow_empty))
        if status == 0 and digest.startswith(("RESULT: EMPTY", "RESULT: MISMATCH")):
            status = 1  # an empty run is not a pass
        (directory / f"{label}.digest").write_text(digest + "\n", encoding="utf-8")
    finally:  # a failing or killed command never leaves the marker behind
        while previous:
            signal.signal(*previous.popitem())
        try:
            marker.unlink()
        except OSError:
            pass
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
