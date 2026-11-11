#!/usr/bin/env python3
"""retro_phase: the cost of one PR's review-to-merge phase (no LLM; reads ``gh`` and the review archive).

    tools/retro_phase.py --pr N [--since ISO] [--out DIR]

Computes ``base_merges_after_review`` (merge commits on the branch's first-parent line, from ``gh api pulls/N/commits``,
counted only after the first review pass: ``--since`` if given, else the earliest successful ``ai-review`` check run
across the PR's commits (``completed_at``), else the first ``sh:review`` comment that says pass; with none of them, every
first-parent merge counts and a note says so). Merges reached only through a second parent were inherited
from a folded branch and are reported as ``base_merges_inherited_skipped``, never counted. The counted merges split into
``base_merges_main`` (the merged ref is ``main``) and ``base_merges_fold`` (any other ref). ``review_restamps`` (**not derivable** with ``--pr``: always null), ``ci_red_runs`` (failed workflow runs on
the branch), ``ci_queue_minutes`` (per run, creation to the first job start from ``gh run view --json jobs``; jobs
carry no queued time; null and noted when a run's jobs are unavailable), ``lane_refusals`` (not derivable, always 0) and
``owner_only_wait_minutes`` (how long the PR sat while an open ``Workflow`` / ``On Hold`` issue it references stayed
open; **product-repo issues only**, runner issues in the request repo are not checked) and ``owner_wait_minutes`` (from the
first ``sh:owner`` comment that carries the owner's merge recipe (``MERGE_RECIPE``) for the head the PR ended on, or names a
blocker, to the merge or close: the wait for the code owner; a note for a superseded head or a plain ping does not start it). Writes
``build/retro/phase-N.json``, prints ``phase_cost`` when base merges >= 2, red runs >= 3 or either wait >= 30 minutes,
and always exits 0. Missing data is skipped and noted, never fatal. ``tools/retro_digest.py`` is not involved.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
BASE_MERGES, RED_RUNS, WAIT_MINUTES = 2, 3, 30
MERGE_RECIPE = "gh pr " + "merge"


def gh_json(args: List[str]) -> Any:
    """Run ``gh`` and parse its JSON; None when it is missing, fails or prints junk."""
    try:
        out = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=60, check=True).stdout
        return json.loads(out)
    except Exception:
        return None


def parse_ts(value: Any) -> Optional[datetime]:
    """An ISO-8601 timestamp (with or without ``Z``) as an aware datetime, else None."""
    if not isinstance(value, str) or not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def minutes(a: Optional[datetime], b: Optional[datetime]) -> float:
    """Minutes from ``a`` to ``b``; 0 when either is missing or the span is negative."""
    if not a or not b:
        return 0.0
    return max(0.0, (b - a).total_seconds() / 60)


def dicts(value: Any) -> List[Dict[str, Any]]:
    """The dict items of ``value`` when it is a list, else nothing."""
    return [x for x in value if isinstance(x, dict)] if isinstance(value, list) else []


def marked_comments(comments: Any, kind: str) -> List[Dict[str, Any]]:
    """The comments carrying the ``<!-- sh:<kind>:`` marker ``pr_note`` writes."""
    return [c for c in dicts(comments) if "<!-- sh:%s:" % kind in str(c.get("body") or "")]


def first_marked_comment(comments: Any, kind: str, pattern: str = "") -> Optional[datetime]:
    """Creation time of the earliest comment carrying the ``<!-- sh:<kind>:`` marker ``pr_note`` writes (and matching
    ``pattern``, case-insensitive, when given), else None."""
    times = [parse_ts(c.get("createdAt")) for c in marked_comments(comments, kind)
             if re.search(pattern, str(c.get("body") or ""), re.I)]
    times = [t for t in times if t]
    return min(times) if times else None


def owner_wait_start(comments: Any, head: str) -> Optional[datetime]:
    """When the code owner was first handed the merge: the earliest ``sh:owner`` note with the merge recipe or a blocker
    (``blocked``), whose ``head=`` meta (when present) is a prefix of ``head``, the head the PR ended on. A plain ping, or a
    recipe pinned to a head the PR later left, does not start the wait."""
    times = []
    for c in marked_comments(comments, "owner"):
        body = str(c.get("body") or "")
        if not (MERGE_RECIPE in body or re.search(r"\bblocked\b|\bblocker\b", body, re.I)):
            continue
        m = re.search(r"sh-meta:[^>]*\bhead=([0-9a-f]+)", body)
        if m and head and not head.startswith(m.group(1)):
            continue
        times.append(parse_ts(c.get("createdAt")))
    times = [t for t in times if t]
    return min(times) if times else None


def review_pass_time(comments: Any) -> Optional[datetime]:
    """Fallback pass time: the earliest ``sh:review`` comment that says ``pass``, else None."""
    return first_marked_comment(comments, "review", r"\bpass\b")


def check_pass_time(commits: List[Dict[str, Any]]) -> Optional[datetime]:
    """When the first review pass completed: the earliest successful ``ai-review`` check run, asking commit by commit in
    push order and stopping at the first commit that has one (so a PR costs few calls). None when none is found."""
    for c in commits:
        sha = c.get("sha")
        if not isinstance(sha, str):
            continue
        found = gh_json(["api", "repos/{owner}/{repo}/commits/%s/check-runs?check_name=ai-review" % sha])
        runs = dicts(found.get("check_runs")) if isinstance(found, dict) else []
        times = [t for t in (parse_ts(r.get("completed_at")) for r in runs
                             if r.get("name") == "ai-review" and r.get("conclusion") == "success") if t]
        if times:
            return min(times)
    return None


def merged_ref(message: str) -> str:
    """The ref a merge headline merges, quoted or not: ``Merge branch 'main' of ...``, ``Merge remote-tracking branch
    'origin/main' into x``, ``Merge origin/main into x``. ``Merge commit 'sha'`` gives ``commit``. Empty when absent."""
    head = message.splitlines()[0] if message else ""
    m = re.match(r"Merge\s+(?:remote-tracking\s+branch\s+|branch\s+)?'?([^\s']+)", head)
    return m.group(1) if m else ""


def is_main(ref: str) -> bool:
    """Is ``ref`` the main branch (``main`` or ``origin/main``)?"""
    return ref in ("main", "origin/main", "refs/remotes/origin/main")


def base_merges(commits: List[Dict[str, Any]], head: str, floor: Optional[datetime]) -> Dict[str, Any]:
    """Merge commits of a PR: ``main`` and ``fold`` after ``floor`` on the first-parent line, and ``inherited`` (merges
    reached only through a second parent). ``chain`` is False when the shas needed to walk the line are missing, in which
    case every merge counts as first-parent."""
    def parents(c: Dict[str, Any]) -> List[Any]:
        return c["parents"] if isinstance(c.get("parents"), list) else []

    merges = [c for c in commits if len(parents(c)) > 1]
    by_sha = {c["sha"]: c for c in commits if isinstance(c.get("sha"), str)}
    if head not in by_sha:
        head = commits[-1].get("sha") if commits else None
    chain: Optional[set] = None
    if by_sha and isinstance(head, str) and head in by_sha:
        chain, cur = set(), head
        while cur in by_sha and cur not in chain:
            chain.add(cur)
            first = parents(by_sha[cur])
            cur = first[0].get("sha") if first and isinstance(first[0], dict) else None
    out: Dict[str, Any] = {"main": 0, "fold": 0, "inherited": 0, "chain": chain is not None}
    for c in merges:
        if chain is not None and c.get("sha") not in chain:
            out["inherited"] += 1
            continue
        info = c.get("commit") if isinstance(c.get("commit"), dict) else {}
        committer = info.get("committer")
        when = parse_ts(committer.get("date")) if isinstance(committer, dict) else None
        if floor is not None and when is not None and when < floor:
            continue
        out["main" if is_main(merged_ref(str(info.get("message") or ""))) else "fold"] += 1
    return out


def compute(pr: int, since: Optional[str]) -> Dict[str, Any]:
    """The phase metrics for PR ``pr``, with ``notes`` for anything that could not be derived."""
    notes: List[str] = []
    view = gh_json(["pr", "view", str(pr), "--json",
                    "headRefName,headRefOid,comments,createdAt,mergedAt,closedAt,body"])
    if not isinstance(view, dict):
        notes.append("gh pr view unavailable")
        view = {}
    branch = view.get("headRefName") or ""
    floor = parse_ts(since)

    def after(ts: Optional[datetime]) -> bool:
        return floor is None or ts is None or ts >= floor

    commits = gh_json(["api", "repos/{owner}/{repo}/pulls/%d/commits?per_page=100" % pr])
    if not isinstance(commits, list):
        notes.append("gh api commits unavailable")
    pass_at = check_pass_time(dicts(commits)) if floor is None else None
    source = "ai-review check run"
    if pass_at is None and floor is None:
        pass_at, source = review_pass_time(view.get("comments")), "sh:review comment"
    merge_floor = floor or pass_at
    if merge_floor is None:
        notes.append("first review pass not findable and no --since; every first-parent base merge counts")
    elif floor is None:
        notes.append(f"base merges counted after the first review pass at {pass_at.isoformat()} ({source})")
    notes.append("review_restamps is not derivable with --pr")
    found = base_merges(dicts(commits), str(view.get("headRefOid") or ""), merge_floor)
    if not found["chain"]:
        notes.append("commit shas unavailable; first-parent line not derivable, every merge counts as first-parent")

    runs = gh_json(["run", "list", "--branch", branch, "--limit", "100", "--json",
                    "databaseId,conclusion,createdAt"]) if branch else None
    if not isinstance(runs, list):
        notes.append("gh run list unavailable")
    red = 0
    queue: Optional[float] = 0.0
    for r in dicts(runs):
        if not after(parse_ts(r.get("createdAt"))):
            continue
        if r.get("conclusion") == "failure":
            red += 1
        detail = gh_json(["run", "view", str(r.get("databaseId")), "--json", "jobs"])
        starts = [t for t in (parse_ts(j.get("startedAt")) for j in dicts((detail or {}).get("jobs") if isinstance(detail, dict) else None)) if t]
        if not starts:
            queue = None
            continue
        if queue is not None:
            queue += minutes(parse_ts(r.get("createdAt")), min(starts))
    if queue is None:
        notes.append("ci_queue_minutes not derivable: a run had no job start times")
    else:
        notes.append("ci_queue_minutes = run created to first job start (jobs carry no queued time)")

    notes.append("lane_refusals not derivable; 0")
    wait = 0.0
    start = parse_ts(view.get("createdAt"))
    end = parse_ts(view.get("mergedAt")) or parse_ts(view.get("closedAt")) or datetime.now(timezone.utc)
    text = " ".join([str(view.get("body") or "")] + [str(c.get("body") or "") for c in dicts(view.get("comments"))])
    refs = {int(n) for n in re.findall(r"#(\d+)", text)} - {pr}
    if refs and start:
        issues = gh_json(["issue", "list", "--state", "all", "--label", "On Hold", "--limit", "200", "--json",
                          "number,labels,createdAt,closedAt"])
        if isinstance(issues, list):
            for i in dicts(issues):
                names = {l.get("name") for l in dicts(i.get("labels"))}
                if i.get("number") not in refs or "Workflow" not in names:
                    continue
                lo = max(start, parse_ts(i.get("createdAt")) or start)
                hi = min(end, parse_ts(i.get("closedAt")) or end)
                wait = max(wait, minutes(lo, hi))
        else:
            notes.append("gh issue list unavailable")
    else:
        notes.append("no referenced Workflow/On Hold issues")
    owner_start = owner_wait_start(view.get("comments"), str(view.get("headRefOid") or ""))
    owner_wait = minutes(owner_start, end)
    if owner_start is None:
        notes.append("no sh:owner note with the merge recipe or a blocker; owner_wait_minutes 0")
    notes.append("owner_only_wait_minutes checks product-repo issues only; runner issues in the request repo are not")

    return {"pr": pr, "branch": branch, "base_merges_after_review": found["main"] + found["fold"],
            "base_merges_main": found["main"], "base_merges_fold": found["fold"],
            "base_merges_inherited_skipped": found["inherited"],
            "review_pass_at": pass_at.isoformat() if pass_at else None, "review_restamps": None,
            "ci_red_runs": red, "ci_queue_minutes": None if queue is None else round(queue, 1), "lane_refusals": 0,
            "owner_only_wait_minutes": round(wait, 1), "owner_wait_minutes": round(owner_wait, 1), "notes": notes}


def fires(m: Dict[str, Any]) -> bool:
    """True when the phase was costly enough for a Steward pass."""
    return (m["base_merges_after_review"] >= BASE_MERGES or m["ci_red_runs"] >= RED_RUNS
            or max(m["owner_only_wait_minutes"], m.get("owner_wait_minutes", 0)) >= WAIT_MINUTES)


def main(argv: Optional[List[str]] = None) -> int:
    """Write ``phase-N.json``, print the metrics (and ``phase_cost`` when it fires); always exit 0."""
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pr", type=int, required=True)
    ap.add_argument("--since")
    ap.add_argument("--out", type=Path, default=ROOT / "build" / "retro")
    a = ap.parse_args(argv)
    try:
        m = compute(a.pr, a.since)
    except Exception as exc:  # never crash the end-of-flow step
        m = {"pr": a.pr, "base_merges_after_review": 0, "review_restamps": None, "ci_red_runs": 0,
             "ci_queue_minutes": None, "lane_refusals": 0, "owner_only_wait_minutes": 0, "owner_wait_minutes": 0, "notes": [f"error: {exc}"]}
    m["phase_cost"] = fires(m)
    try:
        a.out.mkdir(parents=True, exist_ok=True)
        (a.out / f"phase-{a.pr}.json").write_text(json.dumps(m, indent=2) + "\n", encoding="utf-8")
    except OSError as exc:
        print(f"could not write phase-{a.pr}.json: {exc}", file=sys.stderr)
    print(json.dumps({k: v for k, v in m.items() if k != "notes"}))
    if m["phase_cost"]:
        print("phase_cost")
    return 0


if __name__ == "__main__":
    sys.exit(main())
