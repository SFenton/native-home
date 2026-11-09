#!/usr/bin/env python3
"""Run one command (an xcodebuild test run, `swift test`, a simctl probe) under hang watchdogs.

    tools/xc_watch.py [--silence S] [--wall S] [--exit-cap S] [--require-tests] [--expect-tests N] [--tally FILE] [--sim UDID] [--label NAME] -- COMMAND [ARG …]

Output passes through to stdout unchanged, so the caller's log is the log. Three watchdogs, each acting on
the child's own process group (never a pkill by name):

* ``--silence S``: no output for S seconds means the run is hung. The child gets ``sample <pid> 5`` (written
  to stdout), then TERM and KILL, ``--sim`` is shut down, ``INFRA: hung (no output Ns)`` is printed and the
  exit status is 125.
* ``--exit-cap S``: once ``Test Suite 'Selected tests'|'All tests' passed|failed`` has printed, the child gets S
  seconds to exit (xcodebuild sometimes never does). Then it is killed, ``INFRA: slow exit`` is printed and the
  status is the suite's own (0 passed, 1 failed). A test plan with several bundles prints one such line per bundle,
  so a later bundle's ``Test Suite '…' started`` stops the clock (a Gate run was cut after its unit-test bundle and
  reported a pass, 2026-10-30), and a failed bundle keeps the run failed.
  A slow exit also compares the tests executed (the sum of each bundle's own total) with ``--expect-tests N``: a run
  that falls short was cut between bundles, and is reported as ``INFRA: slow exit … only M of N tests ran``, status 1.
* ``--wall S``: a plain time limit (simulator health probes); status 124.
* ``--require-tests``: a run that ends without executing a single test (every ``Executed N tests`` and Swift Testing
  ``Test run with N tests`` line reads 0, and no ``Test Case`` line printed) is an EMPTY run: status 1, with an
  ``EMPTY: no tests ran`` line. A run whose every test skipped passes here with a ``NOTE:`` line: family-gated journeys
  (iPad-only, skips on iPhone) legitimately skip on other families, so "every test skipped" is decided over the whole run by
  the caller (``--tally FILE`` appends ``LABEL ran skipped``; tools/ios_uitest.sh fails EMPTY when no family ran a test). An
  ``-only-testing`` selection the plan skips runs nothing and xcodebuild calls that a pass (Shell, Chrome and AppIcon
  under Gate, 2026-10-31); journeys that skip for lack of credentials also pass (2026-11-03). tools/log_digest.py reads
  the ``EMPTY:`` line into ``RESULT: EMPTY``. Callers that accept an empty run omit the flag.

Otherwise the exit status is the command's.
"""

from __future__ import annotations

import argparse
import os
import re
import signal
import subprocess
import sys
import threading
import time
from typing import List, Optional

HUNG_STATUS = 125
WALL_STATUS = 124
SUITE_DONE = re.compile(rb"Test Suite '(?:Selected tests|All tests)' (passed|failed)")
SUITE_STARTED = re.compile(rb"Test Suite '(?:Selected tests|All tests)' started")
EXECUTED = re.compile(rb"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?")
SWIFT_TESTING_RUN = re.compile(rb"Test run with (\d+) tests?")
CASE_SKIPPED = re.compile(rb"Test Case '[^']*' skipped")
CASE_RAN = re.compile(rb"Test Case '[^']*' (?:passed|failed)")
NO_TESTS_STATUS = 1


def kill_group(process: "subprocess.Popen[bytes]") -> None:
    """TERM the child's process group, KILL it ten seconds later if it is still there."""
    for sig, grace in ((signal.SIGTERM, 10), (signal.SIGKILL, 5)):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=grace)
            return
        except subprocess.TimeoutExpired:
            continue


def emit(text: str) -> None:
    """Write a marker line to stdout in sequence with the child's output."""
    sys.stdout.buffer.write(text.encode() + b"\n")
    sys.stdout.buffer.flush()


def watch(command: List[str], silence: Optional[float], wall: Optional[float], exit_cap: Optional[float],
          sim: str = "", label: str = "", require_tests: bool = False, expect_tests: int = 0,
          tally: str = "") -> int:
    """Run ``command`` and return its status, or 125 (hung) / 124 (wall limit) / the suite's after a slow exit."""
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               stdin=subprocess.DEVNULL, start_new_session=True)
    state = {"last": time.monotonic(), "suite": None, "suite_at": 0.0, "failed": False, "executed": 0,
             "skipped": 0, "skipped_cases": 0, "ran_cases": 0, "total": 0, "after_done": False}
    lock = threading.Lock()

    def pump() -> None:
        assert process.stdout is not None
        for line in iter(process.stdout.readline, b""):
            sys.stdout.buffer.write(line)
            sys.stdout.buffer.flush()
            with lock:
                state["last"] = time.monotonic()
                ran = EXECUTED.search(line)
                if ran:
                    state["executed"] = max(state["executed"], int(ran.group(1)))
                    state["skipped"] = max(state["skipped"], int(ran.group(2) or 0))
                    if state["after_done"]:
                        state["total"] += int(ran.group(1))  # a bundle's own total follows its closing suite line
                swift_testing = SWIFT_TESTING_RUN.search(line)
                if swift_testing:
                    state["executed"] = max(state["executed"], int(swift_testing.group(1)))
                if CASE_SKIPPED.search(line):
                    state["skipped_cases"] += 1
                elif CASE_RAN.search(line):
                    state["ran_cases"] += 1
                state["after_done"] = bool(SUITE_DONE.search(line))
                if SUITE_STARTED.search(line):
                    # The next bundle of the plan: the run is not over.
                    state["suite"] = None
                found = SUITE_DONE.search(line)
                if found and state["suite"] is None:
                    state["failed"] = state["failed"] or found.group(1) == b"failed"
                    state["suite"] = "failed" if state["failed"] else found.group(1).decode()
                    state["suite_at"] = state["last"]

    reader = threading.Thread(target=pump, daemon=True)
    reader.start()
    started = time.monotonic()
    result: Optional[int] = None
    while process.poll() is None:
        time.sleep(0.5)
        now = time.monotonic()
        with lock:
            quiet, suite, suite_at = now - state["last"], state["suite"], state["suite_at"]
            ran_total = state["total"]
        if wall is not None and now - started > wall:
            emit(f"INFRA: {label or 'command'} exceeded {int(wall)}s")
            kill_group(process)
            result = WALL_STATUS
        elif exit_cap is not None and suite and now - suite_at > exit_cap:
            emit(f"INFRA: slow exit (xcodebuild still running {int(exit_cap)}s after the suite {suite})")
            kill_group(process)
            result = 0 if suite == "passed" else 1
            if result == 0 and expect_tests and ran_total < expect_tests:
                emit(f"INFRA: slow exit cut the run short: only {ran_total} of {expect_tests} selected tests ran")
                result = NO_TESTS_STATUS
        elif silence is not None and quiet > silence:
            emit(f"INFRA: hung (no output {int(silence)}s)")
            try:
                subprocess.run(["sample", str(process.pid), "5"], stdout=sys.stdout, stderr=subprocess.STDOUT,
                               timeout=40, check=False)
            except (OSError, subprocess.TimeoutExpired):
                pass
            kill_group(process)
            if sim:
                subprocess.run(["xcrun", "simctl", "shutdown", sim], capture_output=True, check=False)
            result = HUNG_STATUS
        if result is not None:
            break
    reader.join(timeout=5)
    if result is None:
        result = process.returncode if process.returncode >= 0 else 128 - process.returncode
    skipped = max(state["skipped"], state["skipped_cases"])
    ran = max(state["executed"] - skipped, state["ran_cases"])  # floored on the counted passed/failed cases
    is_empty = False
    if result == 0 and require_tests:
        if state["executed"] == 0 and state["ran_cases"] + state["skipped_cases"] == 0:
            emit(f"EMPTY: no tests ran ({label or 'command'}): the selection matched nothing in this plan "
                 "(--allow-empty if intended)")
            result = NO_TESTS_STATUS
            is_empty = True
        elif ran == 0:
            emit(f"NOTE: every selected test skipped ({label or 'command'}): {skipped} skipped, none ran "
                 "(family-gated journeys do this; the run fails EMPTY only if no family ran a test)")
    if tally:
        try:
            with open(tally, "a", encoding="utf-8") as handle:
                handle.write(f"{(label or 'command').replace(' ', '_')} {ran} {skipped}{' empty' if is_empty else ''}\n")
        except OSError:
            pass
    return result


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--" not in argv:
        print(__doc__, file=sys.stderr)
        return 2
    split = argv.index("--")
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--silence", type=float)
    parser.add_argument("--wall", type=float)
    parser.add_argument("--exit-cap", type=float)
    parser.add_argument("--require-tests", action="store_true")
    parser.add_argument("--expect-tests", type=int, default=0)
    parser.add_argument("--tally", default="")
    parser.add_argument("--sim", default="")
    parser.add_argument("--label", default="")
    args = parser.parse_args(argv[:split])
    command = argv[split + 1:]
    if not command:
        print("xc_watch: no command after --", file=sys.stderr)
        return 2
    # A zero or negative limit switches that watchdog off.
    def limit(value: Optional[float]) -> Optional[float]:
        return value if value and value > 0 else None
    return watch(command, limit(args.silence), limit(args.wall), limit(args.exit_cap), args.sim, args.label,
                 args.require_tests, args.expect_tests, args.tally)


if __name__ == "__main__":
    sys.exit(main())
