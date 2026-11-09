#!/usr/bin/env python3
"""Wait for the ``pr-checks`` run of a pull request's current head to appear and finish; print one RESULT line plus the jobs.

    tools/bg_run.py ci-N --timeout 7200 -- python3 tools/ci_wait.py N [--repo OWNER/NAME]

Run it through ``bg_run`` in the background and end the turn (``.claude/agents/orchestrator.md``, "CI waits"). The digest carries the
``RESULT:`` line. Exit 0: merged, or green and CLEAN and not armed. Exit 1: a failed check, or the PR closed unmerged. Exit 2: no run appeared for the head in
``--appear-timeout``, or ``gh`` failed. Exit 3: blocked (see below). Exit 4: the run was cancelled.

A rerun resets a completed run to a new attempt, so a completed read is confirmed again after ``--settle`` seconds and discarded when the
attempt or ``updatedAt`` changed. Stdlib and ``gh`` only; nothing is written or merged.

The ruleset also requires ``ai-review`` on the head, so after a green ``pr-checks`` the PR's check rollup and ``mergeStateStatus`` are read
too. Exit 3 is ``blocked``: the head moved, ``ai-review`` is missing or not successful, or the PR stays BLOCKED (armed or not) after
``--merge-wait``. Exit 4 is a cancelled run. Exit 0 is only ``merged``, or green and CLEAN on a PR that is not armed.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from typing import Callable, List, Optional, Sequence

REPO = "SFenton/native-home"
WORKFLOW = "pr-checks"


class GhError(RuntimeError):
    """``gh`` failed or printed something that is not JSON."""


def gh_json(args: Sequence[str]) -> object:
    """Run ``gh`` with ``args`` and return its parsed JSON output; raise :class:`GhError` on a non-zero exit or bad JSON."""
    proc = subprocess.run(["gh", *args], capture_output=True, text=True)
    if proc.returncode:
        raise GhError(((proc.stderr or proc.stdout).strip() or f"gh exited {proc.returncode}")[:200])
    try:
        return json.loads(proc.stdout or "null")
    except ValueError as exc:
        raise GhError(f"gh printed no JSON: {exc}") from exc


def short(sha: str) -> str:
    """The first eight characters of ``sha``."""
    return sha[:8]


def pr_state(number: str, repo: str, gh: Callable) -> dict:
    """State, head, branch, auto-merge request, ``mergeStateStatus`` and check rollup of the pull request."""
    fields = "state,headRefOid,headRefName,autoMergeRequest,mergeStateStatus,statusCheckRollup"
    return gh(["pr", "view", number, "-R", repo, "--json", fields]) or {}


GOOD = {"SUCCESS", "NEUTRAL", "SKIPPED"}
PENDING = {"", "NONE", "QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED", "EXPECTED"}


def required_check(state: dict, name: str) -> str:
    """``missing``, ``pending``, ``success`` or ``failure:<conclusion>`` of the check ``name`` in the PR's rollup (the newest entry wins)."""
    found = [e for e in state.get("statusCheckRollup") or [] if name in (e.get("name"), e.get("context"))]
    if not found:
        return "missing"
    entry = found[-1]
    result = str(entry.get("conclusion") or entry.get("state") or "").upper()
    if entry.get("status") not in (None, "COMPLETED") or result in PENDING:
        return "pending"
    return "success" if result in GOOD else f"failure:{result.lower()}"


def find_run(branch: str, sha: str, repo: str, gh: Callable) -> Optional[int]:
    """The id of the newest ``pr-checks`` run for ``sha`` on ``branch``, or ``None`` while GitHub has not created one."""
    runs = gh(["run", "list", "-R", repo, "--branch", branch, "--workflow", WORKFLOW, "--limit", "20", "--json", "databaseId,headSha"]) or []
    match = [r for r in runs if r.get("headSha") == sha]
    return match[0]["databaseId"] if match else None


def read_run(run_id: int, repo: str, gh: Callable) -> dict:
    """``status``, ``conclusion``, ``attempt``, ``updatedAt`` and ``jobs`` of one run."""
    return gh(["run", "view", str(run_id), "-R", repo, "--json", "status,conclusion,attempt,updatedAt,jobs"]) or {}


def stamp(run: dict) -> tuple:
    """What changes when a run is rerun: its attempt and its ``updatedAt``."""
    return run.get("attempt"), run.get("updatedAt")


def wait_finished(run_id: int, repo: str, gh: Callable, sleep: Callable, poll: float, settle: float) -> dict:
    """Poll until the run is completed and still completed (same attempt and ``updatedAt``) ``settle`` seconds later; return that read."""
    while True:
        run = read_run(run_id, repo, gh)
        if run.get("status") == "completed":
            sleep(settle)
            again = read_run(run_id, repo, gh)
            if again.get("status") == "completed" and stamp(again) == stamp(run):
                return again
            continue
        sleep(poll)


def merge_outcome(number: str, repo: str, head: str, gh: Callable, sleep: Callable, merge_wait: float, poll: float) -> "tuple[int, str]":
    """After a green ``pr-checks``: ``(exit code, text)``. 0 only for ``merged`` or ``CI green and CLEAN, not armed``; else 1 (closed) or 3 (blocked).

    Waits up to ``merge_wait`` seconds for ``ai-review`` to appear and finish and for GitHub to merge or report CLEAN."""
    waited = 0.0
    while True:
        state = pr_state(number, repo, gh)
        if state.get("state") == "MERGED":
            return 0, "merged"
        if state.get("state") != "OPEN":
            return 1, f"PR {str(state.get('state', 'unknown')).lower()} without merging"
        now = state.get("headRefOid", "")
        if now != head:
            return 3, f"blocked: head moved from {short(head)} to {short(now)}; the green run is for the old head"
        review = required_check(state, "ai-review")
        if review.startswith("failure"):
            return 3, f"blocked: ai-review {review.split(':')[1]} on {short(head)}; re-run python3 tools/review/record.py --post-check {head} --repo {REPO}"
        merge_state = state.get("mergeStateStatus", "unknown")
        armed = bool(state.get("autoMergeRequest"))
        if review == "success" and merge_state == "CLEAN" and not armed:
            return 0, "CI green and CLEAN, not armed"
        if waited >= merge_wait:
            if review == "missing":
                return 3, f"blocked: ai-review missing on {short(head)}; run python3 tools/review/record.py --post-check {head} --repo {REPO}"
            if review == "pending":
                return 3, f"blocked: ai-review still pending on {short(head)} ({merge_state})"
            return 3, f"blocked: {'armed' if armed else 'not armed'} but {merge_state} on {short(head)}"
        sleep(poll)
        waited += poll


def wait(number: str, repo: str = REPO, *, gh: Callable = gh_json, sleep: Callable = time.sleep, appear_timeout: float = 900,
         poll: float = 30, settle: float = 20, merge_wait: float = 300) -> "tuple[int, List[str]]":
    """Run the wait for pull request ``number``. Returns ``(exit code, output lines)``; the last line is the ``RESULT:`` line."""
    try:
        pr = pr_state(number, repo, gh)
        head, branch = pr.get("headRefOid", ""), pr.get("headRefName", "")
        lines = [f"PR {number} head {short(head)} branch {branch}"]
        waited = 0.0
        run_id = None
        while True:
            if pr.get("state") == "MERGED":
                return 0, lines + [f"RESULT: merged #{number}"]
            if pr.get("state") == "CLOSED":
                return 1, lines + [f"RESULT: closed #{number} without merging"]
            run_id = find_run(branch, head, repo, gh)
            if run_id is not None:
                break
            if waited >= appear_timeout:
                return 2, lines + [f"RESULT: no {WORKFLOW} run appeared for {short(head)} within {int(appear_timeout)} s"]
            sleep(poll)
            waited += poll
            pr = pr_state(number, repo, gh)
            if pr.get("headRefOid") != head:
                return 3, lines + [f"RESULT: blocked: head moved from {short(head)} to {short(pr.get('headRefOid', ''))}; start a new waiter"]
        lines.append(f"run {run_id}")
        run = wait_finished(run_id, repo, gh, sleep, poll, settle)
        lines += [f"job {job.get('name')}: {job.get('conclusion')}" for job in run.get("jobs", [])]
        tail = f"{WORKFLOW} {run.get('conclusion')} on {short(head)} (run {run_id}, attempt {run.get('attempt')})"
        if run.get("conclusion") == "cancelled":
            return 4, lines + [f"RESULT: cancelled #{number}: {tail}; re-run the workflow or push"]
        if run.get("conclusion") != "success":
            failed = [str(job.get("name")) for job in run.get("jobs", []) if job.get("conclusion") not in ("success", "skipped", "neutral")]
            return 1, lines + [f"RESULT: ci failed #{number}: {', '.join(failed) or tail}; {tail}"]
        code, text = merge_outcome(number, repo, head, gh, sleep, merge_wait, poll)
        return code, lines + [f"RESULT: {tail}; {text}"]
    except GhError as exc:
        return 2, [f"RESULT: failed #{number}: {exc}"]


def main(argv: Optional[List[str]] = None) -> int:
    """Command-line entry: print the lines from :func:`wait` and return its exit code."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pr")
    parser.add_argument("--repo", default=REPO)
    parser.add_argument("--appear-timeout", type=float, default=900)
    parser.add_argument("--poll", type=float, default=30)
    parser.add_argument("--settle", type=float, default=20)
    parser.add_argument("--merge-wait", type=float, default=300)
    args = parser.parse_args(argv)
    code, lines = wait(args.pr, args.repo, appear_timeout=args.appear_timeout, poll=args.poll, settle=args.settle, merge_wait=args.merge_wait)
    print("\n".join(lines), flush=True)
    return code


if __name__ == "__main__":
    sys.exit(main())
