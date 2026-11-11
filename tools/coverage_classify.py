#!/usr/bin/env python3
"""Classify the test failures of an instrumented coverage run (post-mortem action A2).

An instrumented coverage run can fail tests that pass without coverage: the profile counters slow the code
and trip a timing assertion. The coverage script therefore reruns only the failed ids without
instrumentation (``tools/coverage_phases.sh``) and calls this tool to say, per id:

* ``coverage-only``: failed instrumented and the rerun log shows that id as **passed** (positive evidence);
* ``real``: everything else, including an id the rerun never reported (an unknown is never a pass).

The digest also prints ``timeout: yes|no``. The exit status is 1 when ``real`` is non-empty, when a
``coverage-only`` id is not in the quarantine file (``apple/coverage-quarantine.json``), when the quarantine is
invalid, or when any phase failed in a way that cannot be classified: it exited 124 (timeout), 125, 126 or above
128, or it was non-zero and named no failing test. Those phase failures fail the run whatever the quarantine says.
Every quarantine entry needs ``id``, ``issue`` and ``date`` and the issue must be an open ``Workflow`` issue.
Quarantine never lowers the 95% bar: ``coverage_gate.py`` is untouched and quarantined tests still count.

    coverage_classify.py failed-ids LOG [LOG ...]
    coverage_classify.py phase-facts LOG
    coverage_classify.py swift-filters ID,ID
    coverage_classify.py classify --failed FILE --phases FILE --rerun-log LOG [LOG ...] [--quarantine FILE] [--offline]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path
from typing import Callable

try:  # imported as tools.coverage_classify (tests) or run as a script (tools/ is then on sys.path)
    from tools import log_digest
except ImportError:  # pragma: no cover
    import log_digest

QUARANTINE_DEFAULT = Path(__file__).resolve().parent.parent / "apple" / "coverage-quarantine.json"

#: Phase exit statuses that fail the run whatever the quarantine says: 124 wall or hold timeout, 125 hung, 126 infra.
FATAL_STATUSES = (124, 125, 126)


def parse_log(text: str) -> tuple[list[str], list[str]]:
    """``(failed, passed)`` test ids in a log, read with ``tools/log_digest.py``'s patterns.

    XCTest ids read ``Class/test``; Swift Testing ids are the bare test name (parameters dropped).
    """
    digest = log_digest.Digest()
    digest.feed(text.splitlines())

    def ident(key: str) -> str:
        return key.replace(".", "/", 1) if "." in key else key

    return sorted({ident(k) for k in digest.failed}), sorted({ident(k) for k in digest.passed})


def phase_facts(text: str) -> tuple[int, int, int]:
    """``(named, crashed, unexplained)`` for one phase log.

    ``named`` is the failing ids it names; ``crashed`` is 1 when the log shows a crash marker (``signal code``,
    ``Restarting after unexpected exit``, ``crashed with signal``, ``Test crashed``: SwiftPM and xcodebuild exit 1
    for these); ``unexplained`` is how many failures the log's own count (XCTest ``Executed N tests, with F
    failures``, or the Swift Testing run line's issues) exceeds what the log itself explains: the named ids and the
    issue or error lines it prints.
    """
    digest = log_digest.Digest()
    digest.feed(text.splitlines())
    named = len({k for k in digest.failed})
    crashed = 1 if digest.infra.get("test host crash") else 0
    explained = max(named, digest.issue_lines)
    unexplained = max(digest.executed_failures - explained, digest.st_issues - explained, 0)
    return named, crashed, unexplained


def extract_failed(text: str) -> list[str]:
    """Failing test ids in a log, sorted and unique."""
    return parse_log(text)[0]


def swift_filters(ids: list[str]) -> list[str]:
    """``swift test --filter`` regexes: ``Class/test$`` for XCTest, ``/name\\(`` for Swift Testing (``Module.Suite/name()``)."""
    return [f"{test_id}$" if "/" in test_id else f"/{re.escape(test_id)}\\(" for test_id in sorted(set(ids))]


def phase_problems(lines: list[str]) -> tuple[list[str], bool]:
    """``(problems, timed_out)`` from ``NAME STATUS NIDS`` lines, one per phase run.

    A phase that exited 124, 125, 126 or above 128, or that is non-zero and named no failing test, fails the run
    whatever the quarantine says: only a phase whose failures were all named can be classified.
    """
    problems: list[str] = []
    timed_out = False
    for line in lines:
        parts = line.split()
        if len(parts) not in (3, 5) or not parts[1].isdigit() or not parts[2].isdigit():
            problems.append(f"unreadable phase line: {line!r}")
            continue
        name, status, named = parts[0], int(parts[1]), int(parts[2])
        crashed = int(parts[3]) if len(parts) > 3 and parts[3].isdigit() else 0
        unexplained = int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else 0
        timed_out = timed_out or status == 124
        if status in FATAL_STATUSES or status > 128:
            problems.append(f"phase {name} exited {status} ({'timeout' if status == 124 else 'hung, infra or killed'})")
        elif status != 0 and named == 0:
            problems.append(f"phase {name} exited {status} and named no failing test")
        if crashed and status not in FATAL_STATUSES and status <= 128:
            problems.append(f"phase {name} shows a crash marker (signal code, restart after unexpected exit): it cannot be classified")
        if unexplained:
            problems.append(f"phase {name} counts {unexplained} more failure(s) than its log explains")
    return problems, timed_out


def gh_issue_state(number: int) -> tuple[str, list[str]]:
    """``(state, labels)`` of a GitHub issue through ``gh``; raises ``RuntimeError`` when it cannot be read."""
    try:
        proc = subprocess.run(["gh", "issue", "view", str(number), "--json", "state,labels"],
                              capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.strip() or f"gh issue view {number} failed")
        data = json.loads(proc.stdout)
        return data["state"], [label["name"] for label in data.get("labels", [])]
    except (OSError, ValueError, KeyError) as error:
        raise RuntimeError(str(error) or type(error).__name__) from error


def validate_quarantine(entries: object, lookup: Callable[[int], tuple[str, list[str]]] | None,
                        needed: set[str] | None = None) -> list[str]:
    """Problems with a quarantine list; empty when valid. ``lookup`` None skips the issue check (offline).

    ``needed`` limits the ``gh`` lookups to those ids (the coverage-only ones): an entry nothing leans on is checked
    for shape only, so a green run never depends on ``gh``.
    """
    if not isinstance(entries, list):
        return ["quarantine must be a JSON list"]
    problems: list[str] = []
    seen: set[str] = set()
    for index, entry in enumerate(entries):
        label = f"entry {index}"
        if not isinstance(entry, dict):
            problems.append(f"{label}: not an object")
            continue
        test_id = entry.get("id")
        if not isinstance(test_id, str) or not test_id:
            problems.append(f"{label}: missing id")
            continue
        label = test_id
        if test_id in seen:
            problems.append(f"{label}: listed twice")
        seen.add(test_id)
        issue = entry.get("issue")
        if not isinstance(issue, int) or isinstance(issue, bool) or issue <= 0:
            problems.append(f"{label}: needs the number of an open Workflow issue")
            continue
        try:
            date.fromisoformat(str(entry.get("date", "")))
        except ValueError:
            problems.append(f"{label}: date must be YYYY-MM-DD")
        if lookup is None or (needed is not None and test_id not in needed):
            continue
        try:
            state, labels = lookup(issue)
        except RuntimeError as error:
            problems.append(f"{label}: issue #{issue} unreadable ({error})")
            continue
        if state.upper() != "OPEN":
            problems.append(f"{label}: issue #{issue} is {state.lower()}; fix the test or file a new issue")
        if "Workflow" not in labels:
            problems.append(f"{label}: issue #{issue} is not labelled Workflow")
    return problems


def load_quarantine(path: Path) -> object:
    """The quarantine list; a missing file is an empty list."""
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8"))


def classify(failed: list[str], rerun_passed: list[str], rerun_failed: list[str] = ()) -> tuple[list[str], list[str]]:
    """``(coverage_only, real)``. coverage-only needs positive evidence: the rerun log shows the id passed.

    An id the rerun did not report (never ran, filter matched nothing, crash) is real: an unknown is never a pass.
    """
    passed, again = set(rerun_passed), set(rerun_failed)
    only = sorted(t for t in set(failed) if t in passed and t not in again)
    return only, sorted(set(failed) - set(only))


def digest(coverage_only: list[str], real: list[str], timed_out: bool, quarantined: set[str],
           problems: list[str], phase_issues: list[str] = (), warn_only: bool = False) -> tuple[list[str], int]:
    """The digest lines and the exit status.

    ``warn_only`` (no coverage-only id leans on the quarantine) makes quarantine problems warnings.
    1 for a real id, an unquarantined coverage-only id, a bad quarantine, a timeout or an unclassifiable phase.
    """
    lines = [f"coverage-only: {' '.join(coverage_only) or 'none'}",
             f"real: {' '.join(real) or 'none'}",
             f"timeout: {'yes' if timed_out else 'no'}"]
    status = 1 if (real or timed_out) else 0
    loose = [test_id for test_id in coverage_only if test_id not in quarantined]
    if loose:
        lines.append(f"unquarantined coverage-only: {' '.join(loose)} (fix the test, or add it to "
                     "apple/coverage-quarantine.json with an open Workflow issue)")
        status = 1
    elif coverage_only:
        lines.append("coverage-only failures are all quarantined; the 95% bar is unchanged")
    for issue in phase_issues:
        lines.append(f"phase: {issue}")
        status = 1
    for problem in problems:
        lines.append(f"{'warning: ' if warn_only else ''}quarantine: {problem}")
        status = status if warn_only else 1
    return lines, status


def _read_ids(path: str) -> list[str]:
    file = Path(path)
    if not file.exists():
        return []
    return [line.split()[-1] for line in file.read_text(encoding="utf-8").splitlines() if line.strip()]


def main(argv: list[str] | None = None) -> int:
    """Command line entry; see the module docstring."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    ids = sub.add_parser("failed-ids", help="print the failing test ids found in logs")
    ids.add_argument("logs", nargs="+")
    facts = sub.add_parser("phase-facts", help="print `NAMED CRASHED UNEXPLAINED` for one phase log")
    facts.add_argument("log")
    flt = sub.add_parser("swift-filters", help="print the swift test --filter regexes for failed ids")
    flt.add_argument("ids", help="comma separated ids")
    cls = sub.add_parser("classify", help="print the digest and exit 1 when the run must fail")
    cls.add_argument("--failed", required=True, help="file: `KIND id` lines, the ids the instrumented run failed")
    cls.add_argument("--phases", required=True, help="file: `NAME STATUS NIDS` lines, one per phase run")
    cls.add_argument("--rerun-log", nargs="*", default=[], help="logs of the plain reruns")
    cls.add_argument("--quarantine", default=str(QUARANTINE_DEFAULT))
    cls.add_argument("--offline", action="store_true", help="skip the open-issue check")
    args = parser.parse_args(argv)
    if args.cmd == "phase-facts":
        print(*phase_facts(Path(args.log).read_text(encoding="utf-8", errors="replace")))
        return 0
    if args.cmd == "swift-filters":
        for flt_ in swift_filters([i for i in args.ids.split(",") if i]):
            print(flt_)
        return 0
    if args.cmd == "failed-ids":
        found: set[str] = set()
        for log in args.logs:
            found.update(extract_failed(Path(log).read_text(encoding="utf-8", errors="replace")))
        if found:
            print("\n".join(sorted(found)))
        return 0
    passed: set[str] = set()
    failed_again: set[str] = set()
    for log in args.rerun_log:
        path = Path(log)
        if path.exists():
            again_failed, again_passed = parse_log(path.read_text(encoding="utf-8", errors="replace"))
            passed.update(again_passed)
            failed_again.update(again_failed)
    entries = load_quarantine(Path(args.quarantine))
    only, real = classify(_read_ids(args.failed), sorted(passed), sorted(failed_again))
    problems = validate_quarantine(entries, None if args.offline else gh_issue_state, set(only))
    quarantined = {entry["id"] for entry in entries if isinstance(entry, dict) and isinstance(entry.get("id"), str)}
    phase_lines = Path(args.phases).read_text(encoding="utf-8").splitlines() if Path(args.phases).exists() else []
    phase_issues, timed_out = phase_problems([line for line in phase_lines if line.strip()])
    lines, status = digest(only, real, timed_out, quarantined, problems, phase_issues, warn_only=not only)
    print("\n".join(lines))
    return status


if __name__ == "__main__":
    sys.exit(main())
