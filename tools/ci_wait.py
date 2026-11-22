#!/usr/bin/env python3
"""Wait for the ``pr-checks`` run of a pull request's current head to appear and finish; print one RESULT line plus the jobs.

    tools/bg_run.py ci-N --timeout 7200 -- python3 tools/ci_wait.py N [--repo OWNER/NAME]

Run it through ``bg_run`` in the background and end the turn (``.claude/agents/orchestrator.md``, "CI waits"). The digest carries the
``RESULT:`` line. Exit 0: merged, or green and CLEAN and not armed. Exit 1: a failed check, or the PR closed unmerged. Exit 2: no run appeared for the head in
``--appear-timeout``, or ``gh`` failed. Exit 3: blocked (see below). Exit 4: the run was cancelled and the PR head is unchanged. With
``--max-wait S``, pending CI exits 5 when the monotonic budget expires.

A rerun resets a completed run to a new attempt, so a completed read is confirmed again after ``--settle`` seconds and discarded when the
attempt or ``updatedAt`` changed. Stdlib and ``gh`` only; nothing is written or merged.

The ruleset also requires ``ai-review`` on the head, so after a green ``pr-checks`` the PR's check rollup and ``mergeStateStatus`` are read
too. Exit 3 is ``blocked``: the head moved, ``ai-review`` is missing or not successful, or the PR stays BLOCKED (armed or not) after
``--merge-wait``. Exit 4 is a cancelled run on a head that did not move: when the head moved (a push cancelled the run), the waiter prints
``superseded: <old> -> <new>`` once, follows the new head's run (waiting up to ``--appear-timeout`` for it) and reports that one. Exit 0 is only ``merged``, or green and CLEAN on a PR that is not armed.

:func:`pr_blockers.blockers` (shared with ``tools/pr_land.py``) reads ``mergeable``, ``isDraft``, ``reviewDecision`` and whether the changed files match
``.github/CODEOWNERS``. A ``CONFLICTING`` PR exits 3 on the first poll (GitHub runs no ``pull_request`` checks on it), and a PR that ends
BLOCKED names its reason (draft, code-owner review).
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from typing import Callable, List, Optional, Sequence

import pr_blockers

REPO = "SFenton/native-home"
WORKFLOW = "pr-checks"


class GhError(RuntimeError):
    """``gh`` failed or printed something that is not JSON."""


class WaitBudgetExpired(RuntimeError):
    """The opt-in monotonic wait budget expired."""


def gh_json(args: Sequence[str], timeout: Optional[float] = None) -> object:
    """Run ``gh`` with ``args`` and return its parsed JSON output; raise :class:`GhError` on a non-zero exit or bad JSON."""
    try:
        proc = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise WaitBudgetExpired from exc
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
    fields = "state,headRefOid,headRefName,autoMergeRequest,mergeStateStatus,statusCheckRollup,mergeable,isDraft,reviewDecision,files"
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
            why = "".join(f"; also {reason}" for reason in pr_blockers.blockers(state))
            if review == "missing":
                return 3, f"blocked: ai-review missing on {short(head)}; run python3 tools/review/record.py --post-check {head} --repo {REPO}{why}"
            if review == "pending":
                return 3, f"blocked: ai-review still pending on {short(head)} ({merge_state}){why}"
            return 3, f"blocked: {'armed' if armed else 'not armed'} but {merge_state} on {short(head)}{why}"
        sleep(poll)
        waited += poll


class WaitBudget:
    """One monotonic deadline shared by every phase and bounded ``gh`` call."""

    def __init__(self, max_wait: Optional[float], clock: Callable, sleep: Callable):
        self.clock = clock
        self.sleep_fn = sleep
        self.deadline = None if max_wait is None else clock() + max_wait

    def remaining(self) -> Optional[float]:
        if self.deadline is None:
            return None
        return max(0.0, self.deadline - self.clock())

    def gh(self, gh: Callable) -> Callable:
        if self.deadline is None:
            return gh

        def bounded(args: Sequence[str]):
            remaining = self.remaining()
            if remaining is None or remaining <= 0:
                raise WaitBudgetExpired
            return gh(args, timeout=remaining)

        return bounded

    def sleep(self, seconds: float) -> float:
        remaining = self.remaining()
        if self.deadline is not None and remaining <= 0:
            raise WaitBudgetExpired
        duration = seconds if remaining is None else min(seconds, remaining)
        self.sleep_fn(duration)
        return duration


def job_lines(run: dict) -> List[str]:
    """The stable one-line table for jobs in ``run``."""
    return [f"job {job.get('name')}: {job.get('conclusion')}" for job in run.get("jobs", [])]


def pending_lines(number: str, lines: List[str], jobs: List[dict], rendered: bool) -> List[str]:
    """Add the current or explicitly empty job table and final pending result."""
    result = list(lines)
    if not rendered:
        result += job_lines({"jobs": jobs}) if jobs else ["jobs: none observed"]
    return result + [f"RESULT: ci pending #{number}"]


def terminal_pr(state: dict, number: str) -> Optional["tuple[int, str]"]:
    """A known PR terminal/blocked result, or ``None`` while the PR still needs a run."""
    if state.get("state") == "MERGED":
        return 0, f"RESULT: merged #{number}"
    if state.get("state") == "CLOSED":
        return 1, f"RESULT: closed #{number} without merging"
    if state.get("mergeable") == "CONFLICTING":
        return 3, f"RESULT: blocked #{number}: {pr_blockers.blockers(state)[0]}"
    return None


def first_red_job(run: dict) -> Optional[dict]:
    """The first completed failure or timeout in an in-progress run."""
    for job in run.get("jobs", []):
        conclusion = str(job.get("conclusion", "")).lower()
        status = str(job.get("status", "")).lower()
        if status in ("", "completed") and conclusion in ("failure", "timed_out"):
            return job
    return None


def wait_opt_in(number: str, repo: str, gh: Callable, sleep: Callable, appear_timeout: float, poll: float,
                settle: float, merge_wait: float, first_red: bool, max_wait: Optional[float],
                clock: Callable) -> "tuple[int, List[str]]":
    """Run an opt-in wait with early-red revalidation and, when requested, one total budget."""
    budget = WaitBudget(max_wait, clock, sleep)
    bounded_gh = budget.gh(gh)
    lines: List[str] = []
    latest_jobs: List[dict] = []
    jobs_rendered = False
    try:
        pr = pr_state(number, repo, bounded_gh)
        head, branch = pr.get("headRefOid", ""), pr.get("headRefName", "")
        lines = [f"PR {number} head {short(head)} branch {branch}"]
        while True:
            terminal = terminal_pr(pr, number)
            if terminal is not None:
                return terminal[0], lines + [terminal[1]]
            waited = 0.0
            while True:
                terminal = terminal_pr(pr, number)
                if terminal is not None:
                    return terminal[0], lines + [terminal[1]]
                run_id = find_run(branch, head, repo, bounded_gh)
                if run_id is not None:
                    break
                if waited >= appear_timeout:
                    return 2, lines + [f"RESULT: no {WORKFLOW} run appeared for {short(head)} within {int(appear_timeout)} s"]
                waited += budget.sleep(poll)
                pr = pr_state(number, repo, bounded_gh)
                if pr.get("headRefOid") != head:
                    return 3, lines + [f"RESULT: blocked: head moved from {short(head)} to {short(pr.get('headRefOid', ''))}; start a new waiter"]

            lines.append(f"run {run_id}")
            latest_jobs = []
            jobs_rendered = False
            restart = False
            while not restart:
                run = read_run(run_id, repo, bounded_gh)
                latest_jobs = list(run.get("jobs", []))
                if run.get("status") == "completed":
                    budget.sleep(settle)
                    again = read_run(run_id, repo, bounded_gh)
                    latest_jobs = list(again.get("jobs", []))
                    if again.get("status") == "completed" and stamp(again) == stamp(run):
                        run = again
                    else:
                        continue
                    lines += job_lines(run)
                    jobs_rendered = True
                    tail = f"{WORKFLOW} {run.get('conclusion')} on {short(head)} (run {run_id}, attempt {run.get('attempt')})"
                    if run.get("conclusion") == "cancelled":
                        pr = pr_state(number, repo, bounded_gh)
                        now = pr.get("headRefOid", "")
                        if now and now != head:
                            lines.append(f"superseded: {short(head)} -> {short(now)}")
                            head, branch = now, pr.get("headRefName", branch)
                            latest_jobs = []
                            jobs_rendered = False
                            restart = True
                            continue
                        return 4, lines + [f"RESULT: cancelled #{number}: {tail}; the head is unchanged, re-run the workflow or push"]
                    if run.get("conclusion") != "success":
                        failed = [str(job.get("name")) for job in run.get("jobs", [])
                                  if job.get("conclusion") not in ("success", "skipped", "neutral")]
                        return 1, lines + [f"RESULT: ci failed #{number}: {', '.join(failed) or tail}; {tail}"]
                    code, text = merge_outcome(number, repo, head, bounded_gh, budget.sleep, merge_wait, poll)
                    return code, lines + [f"RESULT: {tail}; {text}"]

                red_job = first_red_job(run) if first_red else None
                if red_job is not None:
                    pr = pr_state(number, repo, bounded_gh)
                    terminal = terminal_pr(pr, number)
                    if terminal is not None:
                        return terminal[0], lines + [terminal[1]]
                    now = pr.get("headRefOid", "")
                    if now != head:
                        lines.append(f"superseded: {short(head)} -> {short(now)}")
                        head, branch = now, pr.get("headRefName", branch)
                        latest_jobs = []
                        jobs_rendered = False
                        restart = True
                        continue
                    branch = pr.get("headRefName", branch)
                    selected = find_run(branch, head, repo, bounded_gh)
                    if selected is None:
                        latest_jobs = []
                        jobs_rendered = False
                        restart = True
                        continue
                    if selected != run_id:
                        run_id = selected
                        lines.append(f"run {run_id}")
                        latest_jobs = []
                        jobs_rendered = False
                        continue
                    checked = read_run(run_id, repo, bounded_gh)
                    latest_jobs = list(checked.get("jobs", []))
                    same_attempt = checked.get("attempt") == run.get("attempt")
                    if same_attempt and checked.get("status") != "completed":
                        validated = next(
                            (job for job in checked.get("jobs", [])
                             if job.get("name") == red_job.get("name")
                             and str(job.get("status", "")).lower() in ("", "completed")
                             and str(job.get("conclusion", "")).lower() in ("failure", "timed_out")),
                            None,
                        )
                        if validated is not None:
                            lines += job_lines(checked)
                            return 1, lines + [
                                f"RESULT: ci red early #{number}: {red_job.get('name')}; "
                                f"run {run_id} still {checked.get('status')}"
                            ]
                    continue
                budget.sleep(poll)
    except WaitBudgetExpired:
        return 5, pending_lines(number, lines, latest_jobs, jobs_rendered)
    except GhError as exc:
        return 2, [f"RESULT: failed #{number}: {exc}"]


def _wait_legacy(number: str, repo: str = REPO, *, gh: Callable = gh_json, sleep: Callable = time.sleep, appear_timeout: float = 900,
                poll: float = 30, settle: float = 20, merge_wait: float = 300) -> "tuple[int, List[str]]":
    """Run the wait for pull request ``number``. Returns ``(exit code, output lines)``; the last line is the ``RESULT:`` line."""
    try:
        pr = pr_state(number, repo, gh)
        head, branch = pr.get("headRefOid", ""), pr.get("headRefName", "")
        lines = [f"PR {number} head {short(head)} branch {branch}"]
        while True:
            waited = 0.0
            while True:
                if pr.get("state") == "MERGED":
                    return 0, lines + [f"RESULT: merged #{number}"]
                if pr.get("state") == "CLOSED":
                    return 1, lines + [f"RESULT: closed #{number} without merging"]
                if pr.get("mergeable") == "CONFLICTING":
                    return 3, lines + [f"RESULT: blocked #{number}: {pr_blockers.blockers(pr)[0]}"]
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
                pr = pr_state(number, repo, gh)
                now = pr.get("headRefOid", "")
                if now and now != head:  # a push cancelled the run: follow the new head's run
                    lines.append(f"superseded: {short(head)} -> {short(now)}")
                    head, branch = now, pr.get("headRefName", branch)
                    continue
                return 4, lines + [f"RESULT: cancelled #{number}: {tail}; the head is unchanged, re-run the workflow or push"]
            break
        if run.get("conclusion") != "success":
            failed = [str(job.get("name")) for job in run.get("jobs", []) if job.get("conclusion") not in ("success", "skipped", "neutral")]
            return 1, lines + [f"RESULT: ci failed #{number}: {', '.join(failed) or tail}; {tail}"]
        code, text = merge_outcome(number, repo, head, gh, sleep, merge_wait, poll)
        return code, lines + [f"RESULT: {tail}; {text}"]
    except GhError as exc:
        return 2, [f"RESULT: failed #{number}: {exc}"]


def positive_finite(value: str) -> float:
    """Argparse type for a positive finite duration."""
    result = float(value)
    if result <= 0 or not math.isfinite(result):
        raise argparse.ArgumentTypeError("must be a positive finite number")
    return result


def wait(number: str, repo: str = REPO, *, gh: Callable = gh_json, sleep: Callable = time.sleep, appear_timeout: float = 900,
         poll: float = 30, settle: float = 20, merge_wait: float = 300, first_red: bool = False,
         max_wait: Optional[float] = None, clock: Callable = time.monotonic) -> "tuple[int, List[str]]":
    """Run the wait, preserving the legacy path unless either opt-in flag is active."""
    if max_wait is not None and (max_wait <= 0 or not math.isfinite(max_wait)):
        raise ValueError("max_wait must be a positive finite number")
    if not first_red and max_wait is None:
        return _wait_legacy(number, repo, gh=gh, sleep=sleep, appear_timeout=appear_timeout, poll=poll,
                            settle=settle, merge_wait=merge_wait)
    return wait_opt_in(number, repo, gh, sleep, appear_timeout, poll, settle, merge_wait,
                       first_red, max_wait, clock)


def main(argv: Optional[List[str]] = None) -> int:
    """Command-line entry: print the lines from :func:`wait` and return its exit code."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pr")
    parser.add_argument("--repo", default=REPO)
    parser.add_argument("--appear-timeout", type=float, default=900)
    parser.add_argument("--poll", type=float, default=30)
    parser.add_argument("--settle", type=float, default=20)
    parser.add_argument("--merge-wait", type=float, default=300)
    parser.add_argument("--first-red", action="store_true",
                        help="return as soon as a completed failed or timed-out job is revalidated on the current head")
    parser.add_argument("--max-wait", type=positive_finite,
                        help="stop with exit 5 if CI is still pending after this monotonic budget in seconds")
    args = parser.parse_args(argv)
    code, lines = wait(
        args.pr,
        args.repo,
        appear_timeout=args.appear_timeout,
        poll=args.poll,
        settle=args.settle,
        merge_wait=args.merge_wait,
        first_red=args.first_red,
        max_wait=args.max_wait,
    )
    print("\n".join(lines), flush=True)
    return code


if __name__ == "__main__":
    sys.exit(main())
