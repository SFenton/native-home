#!/usr/bin/env python3
"""retro_phase: the cost of one PR's review-to-merge phase (no LLM; reads ``gh`` and the review archive).

    tools/retro_phase.py --pr N [--since ISO] [--out DIR]

Computes ``base_merges_after_review`` (commits with more than one parent in the PR, from ``gh api pulls/N/commits``;
with only ``--pr`` the first-review time is not derivable, so every base merge counts, and ``--since`` starts the
count), ``review_restamps`` (**not derivable** with ``--pr``: always null), ``ci_red_runs`` (failed workflow runs on
the branch), ``ci_queue_minutes`` (per run, creation to the first job start from ``gh run view --json jobs``; jobs
carry no queued time; null and noted when a run's jobs are unavailable), ``lane_refusals`` (not derivable, always 0) and
``owner_only_wait_minutes`` (how long the PR sat while an open ``Workflow`` / ``On Hold`` issue it references stayed
open; **product-repo issues only**, runner issues in the request repo are not checked). Writes
``build/retro/phase-N.json``, prints ``phase_cost`` when base merges >= 2, red runs >= 3 or any wait >= 30 minutes,
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


def compute(pr: int, since: Optional[str]) -> Dict[str, Any]:
    """The phase metrics for PR ``pr``, with ``notes`` for anything that could not be derived."""
    notes: List[str] = []
    view = gh_json(["pr", "view", str(pr), "--json",
                    "headRefName,comments,createdAt,mergedAt,closedAt,body"])
    if not isinstance(view, dict):
        notes.append("gh pr view unavailable")
        view = {}
    branch = view.get("headRefName") or ""
    floor = parse_ts(since)

    def after(ts: Optional[datetime]) -> bool:
        return floor is None or ts is None or ts >= floor

    notes.append("review_restamps and the first-review time are not derivable with --pr; every base merge counts "
                 "(use --since to start at the first review)")
    merges = 0
    commits = gh_json(["api", "repos/{owner}/{repo}/pulls/%d/commits?per_page=100" % pr])
    if not isinstance(commits, list):
        notes.append("gh api commits unavailable")
    for c in dicts(commits):
        when = parse_ts((c.get("commit") or {}).get("committer", {}).get("date")) if isinstance(c.get("commit"), dict) else None
        if isinstance(c.get("parents"), list) and len(c["parents"]) > 1 and after(when):
            merges += 1

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
    notes.append("owner_only_wait_minutes checks product-repo issues only; runner issues in the request repo are not")

    return {"pr": pr, "branch": branch, "base_merges_after_review": merges, "review_restamps": None,
            "ci_red_runs": red, "ci_queue_minutes": None if queue is None else round(queue, 1), "lane_refusals": 0,
            "owner_only_wait_minutes": round(wait, 1), "notes": notes}


def fires(m: Dict[str, Any]) -> bool:
    """True when the phase was costly enough for a Steward pass."""
    return (m["base_merges_after_review"] >= BASE_MERGES or m["ci_red_runs"] >= RED_RUNS
            or m["owner_only_wait_minutes"] >= WAIT_MINUTES)


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
             "ci_queue_minutes": None, "lane_refusals": 0, "owner_only_wait_minutes": 0, "notes": [f"error: {exc}"]}
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
