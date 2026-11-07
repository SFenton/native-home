#!/usr/bin/env python3
"""retro_weekly: the weekly metrics roll-up of the self-improving loop (plan §9, §11). Deterministic, stdlib, no network.

    tools/retro_weekly.py [--since 7d] [--archive DIR] [--repo DIR] [--out DIR] [--now ISO]

Reads every flow digest ``retro_digest.py`` wrote, ``ARCHIVE/*/retro/*.json`` (the runner's evidence archive, default
``~/hass-agents/archive``) and ``REPO/build/retro/*.json``, keeps those written inside the window (file modification
time; ``--since`` is ``7d``, ``48h`` or an ISO date) and writes ``OUT/weekly-<date>.json`` and ``.md``
(``OUT`` defaults to ``REPO/build/retro``). The previous window of the same length is computed too, for the trend.

Metrics (the plan's §11 table):

- ``flows``: digests of issue flows (archives ``request-*`` and ``nightly-*``); scheduled jobs (``job-*``) and post-mortems
  (``retro-*``) are counted apart as ``other_runs`` and never in the flow metrics.
- ``flows_without_nudge``: flows with no ``owner_correction`` trigger.
- ``owner_corrections`` and ``corrections_per_task``: the owner's replies behind those triggers.
- ``routing_overrides``: flows with a ``routing_override`` trigger.
- ``tokens_per_task`` and ``minutes_per_task``: means over flows that recorded them.
- ``review_findings_per_pr``: findings in the archived ``review/*.json`` verdicts over the number of verdict files (a
  verdict file is one branch, so one pull request), across all rounds.
- ``self_change_merges`` and ``self_change_reverts``: from post-mortem outputs under ``retro/`` (``merged`` and
  ``reverted`` lists, and ``actions[]`` items whose ``status`` is ``merged`` or ``reverted``).
- ``retirements``: files in any ``retired/`` folder under ``REPO/evals`` (``retirements_in_window`` by modification time).
- ``triggers``: count of each trigger id.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

FLOW_PREFIXES = ("request-", "nightly-")
RETRO_REPO = Path(__file__).resolve().parents[1]


def parse_since(text: str, now: datetime) -> datetime:
    """``7d`` / ``48h`` / ``90m`` before ``now``, or an ISO date or time."""
    match = re.fullmatch(r"(\d+)([dhm])", text.strip())
    if match:
        unit = {"d": "days", "h": "hours", "m": "minutes"}[match.group(2)]
        return now - timedelta(**{unit: int(match.group(1))})
    moment = datetime.fromisoformat(text.strip().replace("Z", "+00:00"))
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError):
        return None


def mtime(path: Path) -> datetime:
    return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)


# MARK: - Collection

def collect(archive: Optional[Path], repo: Optional[Path], retired_root: Optional[Path]) -> Dict[str, Any]:
    """Every record the metrics read, each with its time: digests, review verdicts, retro outputs and retired cases."""
    digests: Dict[str, Dict[str, Any]] = {}
    reviews: List[Dict[str, Any]] = []
    outputs: List[Dict[str, Any]] = []

    def add_digest(path: Path, kind: str, origin: str) -> None:
        data = load(path)
        if not isinstance(data, dict) or "triggers" not in data or not isinstance(data["triggers"], list):
            return
        task = str(data.get("task") or path.stem)
        record = {"task": task, "kind": kind, "origin": origin, "at": mtime(path), "data": data}
        if kind == "flow" and task.startswith(("retro-", "job-")):
            record["kind"] = "other"
        old = digests.get(task)
        if old is None or old["at"] <= record["at"]:
            digests[task] = record

    def add_output(path: Path) -> None:
        data = load(path)
        if isinstance(data, dict) and any(k in data for k in ("merged", "reverted", "actions", "owner_rules_broken")):
            outputs.append({"at": mtime(path), "data": data})

    if archive and archive.is_dir():
        for folder in sorted(p for p in archive.iterdir() if p.is_dir()):
            kind = "flow" if folder.name.startswith(FLOW_PREFIXES) else "other"
            for path in sorted((folder / "retro").glob("*.json")) if (folder / "retro").is_dir() else []:
                if path.name.endswith(".status.json"):
                    add_output(path)
                else:
                    add_digest(path, kind, folder.name)
                    add_output(path)
            for path in sorted((folder / "review").glob("*.json")) if (folder / "review").is_dir() else []:
                data = load(path)
                if isinstance(data, dict):
                    reviews.append({"at": mtime(path), "branch": str(data.get("branch") or path.stem),
                                    "findings": len(data.get("findings") or []) if isinstance(data.get("findings") or [], list) else 0})
    if repo and (repo / "build" / "retro").is_dir():
        for path in sorted((repo / "build" / "retro").glob("*.json")):
            if path.name.endswith(".status.json"):
                add_output(path)
            elif not path.name.startswith("weekly-"):
                add_digest(path, "flow", "")
                add_output(path)
    retired: List[datetime] = []
    root = retired_root or (repo / "evals" if repo else None)
    if root and root.is_dir():
        for folder in sorted(p for p in root.rglob("retired") if p.is_dir()):
            retired += [mtime(f) for f in sorted(folder.rglob("*")) if f.is_file() and f.name.lower() != "readme.md"]
    return {"digests": list(digests.values()), "reviews": reviews, "outputs": outputs, "retired": retired}


# MARK: - Metrics

def corrections_of(data: Dict[str, Any]) -> int:
    """Owner replies behind an ``owner_correction`` trigger (at least the evidence lines shown)."""
    for trigger in data.get("triggers") or []:
        if isinstance(trigger, dict) and trigger.get("id") == "owner_correction":
            counted = int(((data.get("counts") or {}).get("owner_replies")) or 0)
            return max(counted, len(trigger.get("evidence") or []), 1)
    return 0


def mean(values: List[float]) -> float:
    return round(sum(values) / len(values), 1) if values else 0.0


def add_rule(rules: Dict[str, Dict[str, Any]], entry: Any, at: datetime) -> None:
    """Count one ``owner_rules_broken`` entry (``{rule, source_date, quote, run}``, or a bare string) under its rule (plan §10)."""
    item = entry if isinstance(entry, dict) else {"rule": str(entry)}
    text = str(item.get("rule") or "").strip()
    if not text:
        return
    key = re.sub(r"\s+", " ", text).lower()
    row = rules.setdefault(key, {"rule": text, "count": 0, "entries": []})
    row["count"] += 1
    row["entries"].append({"source_date": str(item.get("source_date") or ""), "quote": str(item.get("quote") or ""),
                           "run": str(item.get("run") or ""), "at": at.isoformat()})


def metrics(records: Dict[str, Any], start: datetime, end: datetime) -> Dict[str, Any]:
    """The §11 metrics over ``start <= time < end``."""
    def inside(when: datetime) -> bool:
        return start <= when < end

    flows = [r for r in records["digests"] if r["kind"] == "flow" and inside(r["at"])]
    others = [r for r in records["digests"] if r["kind"] != "flow" and inside(r["at"])]
    triggers: Counter = Counter()
    rows: List[Dict[str, Any]] = []
    tokens: List[float] = []
    minutes: List[float] = []
    corrections = overrides = nudged = 0
    for record in sorted(flows, key=lambda r: r["task"]):
        data = record["data"]
        ids = sorted({t.get("id") for t in data["triggers"] if isinstance(t, dict) and t.get("id")})
        triggers.update(ids)
        count = corrections_of(data)
        corrections += count
        nudged += 1 if "owner_correction" in ids else 0
        overrides += 1 if "routing_override" in ids else 0
        token = float(((data.get("cost") or {}).get("tokens")) or 0)
        minute = float(((data.get("durations") or {}).get("minutes")) or 0)
        if token:
            tokens.append(token)
        if minute:
            minutes.append(minute)
        rows.append({"task": record["task"], "tokens": int(token), "minutes": minute, "corrections": count,
                     "triggers": ids})
    reviews = [r for r in records["reviews"] if inside(r["at"])]
    merges = reverts = rule_repeats = 0
    rules: Dict[str, Dict[str, Any]] = {}
    for output in records["outputs"]:
        if not inside(output["at"]):
            continue
        data = output["data"]
        actions = [a for a in data.get("actions") or [] if isinstance(a, dict)]
        state = lambda a: str(a.get("status") or a.get("state") or a.get("outcome") or "").lower()  # noqa: E731
        merged = data.get("merged") if isinstance(data.get("merged"), list) else []
        reverted = data.get("reverted") if isinstance(data.get("reverted"), list) else []
        broken = data.get("owner_rules_broken")
        rule_repeats += len(broken) if isinstance(broken, list) else 0
        for entry in broken if isinstance(broken, list) else []:
            add_rule(rules, entry, output["at"])
        merges += max(len(merged), sum(1 for a in actions if state(a) == "merged"))
        reverts += len(reverted) + sum(1 for a in actions if state(a) == "reverted")
    n = len(flows)
    return {
        "flows": n,
        "flows_without_nudge": n - nudged,
        "owner_corrections": corrections,
        "corrections_per_task": round(corrections / n, 2) if n else 0.0,
        "routing_overrides": overrides,
        "tokens_per_task": mean(tokens),
        "minutes_per_task": mean(minutes),
        "tokens_total": int(sum(tokens)),
        "minutes_total": round(sum(minutes), 1),
        "review_prs": len(reviews),
        "review_findings": sum(r["findings"] for r in reviews),
        "review_findings_per_pr": round(sum(r["findings"] for r in reviews) / len(reviews), 2) if reviews else 0.0,
        "self_change_merges": merges,
        "self_change_reverts": reverts,
        "owner_rule_repeats": rule_repeats,
        "owner_rules": sorted(rules.values(), key=lambda r: (-r["count"], r["rule"])),
        "retirements_in_window": sum(1 for t in records["retired"] if inside(t)),
        "other_runs": len(others),
        "triggers": dict(sorted(triggers.items())),
        "tasks": rows,
    }


#: (metric, direction that is good: +1 rising, -1 falling), the plan's §11 targets.
TARGETS: Tuple[Tuple[str, int], ...] = (
    ("flows_without_nudge", 1), ("corrections_per_task", -1), ("routing_overrides", -1), ("tokens_per_task", -1),
    ("minutes_per_task", -1), ("review_findings_per_pr", -1), ("self_change_reverts", -1), ("owner_rule_repeats", -1),
)


# MARK: - Regression compare (plan §9: the automatic revert)

#: The metrics the revert compares, all "falling is good", as per-flow rates so a window of 9 and one of 10 flows compare.
REVERT_METRICS: Tuple[str, ...] = ("corrections_per_task", "nudged_flows_rate", "routing_overrides_rate", "tokens_per_task",
                                   "review_findings_per_pr", "owner_rule_repeats_rate")


def revert_view(m: Dict[str, Any]) -> Dict[str, float]:
    """The ``REVERT_METRICS`` of a ``metrics()`` dict."""
    n = m["flows"] or 1
    return {"corrections_per_task": m["corrections_per_task"],
            "nudged_flows_rate": round((m["flows"] - m["flows_without_nudge"]) / n, 3) if m["flows"] else 0.0,
            "routing_overrides_rate": round(m["routing_overrides"] / n, 3) if m["flows"] else 0.0,
            "tokens_per_task": m["tokens_per_task"], "review_findings_per_pr": m["review_findings_per_pr"],
            "owner_rule_repeats_rate": round(m["owner_rule_repeats"] / n, 3) if m["flows"] else 0.0}


def flow_window(records: Dict[str, Any], at: datetime, n: int, after: bool) -> Dict[str, Any]:
    """``metrics()`` over the ``n`` flows just after ``at`` (``after``) or just before it: the compare windows of a landing."""
    flows = sorted((r for r in records["digests"] if r["kind"] == "flow"), key=lambda r: r["at"])
    chosen = [r for r in flows if r["at"] >= at][:n] if after else [r for r in flows if r["at"] < at][-n:]
    if not chosen:
        return metrics(records, at, at)
    if after:
        return metrics(records, at, chosen[-1]["at"] + timedelta(seconds=1))
    return metrics(records, chosen[0]["at"], at)


def regressions(before: Dict[str, Any], after: Dict[str, Any], margin: float) -> List[Dict[str, Any]]:
    """The ``REVERT_METRICS`` that got worse by more than ``margin`` (a fraction: 0.2 is 20%) from ``before`` to ``after``
    (``revert_view`` dicts). From a zero baseline any rise counts."""
    worse = []
    for name in REVERT_METRICS:
        b, a = float(before.get(name) or 0), float(after.get(name) or 0)
        if a > b and a > b * (1 + margin):
            worse.append({"metric": name, "before": b, "after": a,
                          "change_pct": round((a - b) / b * 100, 1) if b else None})
    return worse


def build(records: Dict[str, Any], now: datetime, since: datetime) -> Dict[str, Any]:
    span = now - since
    current = metrics(records, since, now + timedelta(seconds=1))
    previous = metrics(records, since - span, since)
    trend = {}
    for name, good in TARGETS:
        a, b = current[name], previous[name]
        trend[name] = {"now": a, "before": b, "change": round(a - b, 2),
                       "direction": "same" if a == b else ("better" if (a - b) * good > 0 else "worse")}
    return {"date": now.strftime("%Y-%m-%d"), "since": since.isoformat(), "until": now.isoformat(),
            "retirements_total": len(records["retired"]), "metrics": current, "previous": {
                k: v for k, v in previous.items() if k != "tasks"}, "trend": trend}


def render_md(doc: Dict[str, Any]) -> str:
    m = doc["metrics"]
    lines = [f"# Weekly retro metrics, {doc['date']}", "", f"Window: {doc['since']} to {doc['until']}.", ""]
    again = [r for r in m.get("owner_rules", []) if r["count"] >= 2]
    if again:
        lines += ["## Owner rules broken again (first)", ""]
        for r in again:
            lines.append(f"- {r['rule']}: broken {r['count']} times")
            lines += [f"  - {e['source_date'] or 'undated'}: \"{e['quote']}\" (run {e['run'] or '-'})" for e in r["entries"]]
        lines.append("")
    lines += ["| Metric | This window | Before | Trend |", "|---|---|---|---|"]
    for name, info in doc["trend"].items():
        lines.append(f"| {name} | {info['now']} | {info['before']} | {info['direction']} ({info['change']:+g}) |")
    lines += ["", f"- Flows: {m['flows']} ({m['other_runs']} job and post-mortem runs apart)",
              f"- Owner corrections: {m['owner_corrections']}",
              f"- Review findings: {m['review_findings']} across {m['review_prs']} pull requests",
              f"- Self-change merges: {m['self_change_merges']}, reverts: {m['self_change_reverts']}",
              f"- Repeats of a rule the owner already gave: {m['owner_rule_repeats']}",
              f"- Retirements: {m['retirements_in_window']} this window, {doc['retirements_total']} in all"]
    singles = [r for r in m.get("owner_rules", []) if r["count"] < 2]
    if singles:
        lines += ["", "## Owner rules broken once", ""]
        for r in singles:
            e = r["entries"][0]
            lines.append(f"- {r['rule']} ({e['source_date'] or 'undated'}: \"{e['quote']}\", run {e['run'] or '-'})")
    lines += ["", "## Triggers", ""]
    lines += [f"- {k}: {v}" for k, v in m["triggers"].items()] or ["- none"]
    lines += ["", "## Tasks", "", "| Task | Tokens | Minutes | Corrections | Triggers |", "|---|---|---|---|---|"]
    lines += [f"| {r['task']} | {r['tokens']} | {r['minutes']} | {r['corrections']} | {', '.join(r['triggers']) or '-'} |"
              for r in m["tasks"]]
    return "\n".join(lines) + "\n"


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Weekly metrics roll-up of the retro digests.")
    parser.add_argument("--since", default="7d")
    parser.add_argument("--archive", default=str(Path.home() / "hass-agents" / "archive"))
    parser.add_argument("--repo", default=str(RETRO_REPO))
    parser.add_argument("--out")
    parser.add_argument("--now", help="ISO time to treat as now (tests)")
    args = parser.parse_args(argv)
    now = parse_since(args.now, datetime.now(timezone.utc)) if args.now else datetime.now(timezone.utc)
    repo = Path(args.repo)
    out = Path(args.out) if args.out else repo / "build" / "retro"
    document = build(collect(Path(args.archive), repo, None), now, parse_since(args.since, now))
    out.mkdir(parents=True, exist_ok=True)
    stem = out / f"weekly-{document['date']}"
    stem.with_suffix(".json").write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    stem.with_suffix(".md").write_text(render_md(document), encoding="utf-8")
    print(f"{stem}.md ({document['metrics']['flows']} flows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
