#!/usr/bin/env python3
"""Where did the Claude usage go? Reads the session transcripts under ~/.claude/projects.

Usage: tools/token_report.py [--projects GLOB] [--since YYYY-MM-DD] [--top N] [--root DIR]

Reports tokens and a relative weighted cost per day and model, then the habits that burned tokens in
Oct 2026 (`.agents/archive/audit/token-burn-2026-10-22.md`): sessions past 200 turns, context per turn, poll turns
(sleep loops), and turns that re-wrote a whole cached context after a gap. Weighted cost is relative, not the
plan's meter: input 1, cache read 0.1, cache write 1.25 (5 min tier) or 2 (1 h tier), output 5, times a model
multiplier (Opus 5, Sonnet 1, Haiku 0.33).

A healthy week: no session over 200 turns, no poll turns, no rewrite turns.
"""

from __future__ import annotations

import argparse
import datetime
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Optional

def default_project_glob() -> str:
    """The transcript-folder glob for this repository: its name, taken at runtime from the shared git directory.

    Claude Code names a project folder after the working directory, so a primary checkout and its worktrees all contain
    the primary checkout's folder name. Falls back to every project (``*``) outside a git checkout."""
    import subprocess
    try:
        out = subprocess.run(["git", "-C", str(Path(__file__).resolve().parent), "rev-parse", "--path-format=absolute",
                              "--git-common-dir"], capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        out = ""
    name = Path(out).parent.name if out else ""
    return f"*{name}*" if name else "*"


MODEL_WEIGHT = {"opus": 5.0, "sonnet": 1.0, "haiku": 0.33}
POLL = re.compile(r"\b(?:until|while)\b.{0,400}?\bdo\b.{0,300}?\bsleep\s+[0-9$]|\bfor\s+\w+\s+in\b[^;\n]*\bseq\b.{0,400}?\bdo\b.{0,300}?\bsleep\s+[0-9$]|\bsleep\s+(?:[3-9]\d|\d{3,})\b", re.S)
LONG_SESSION_TURNS = 200
REWRITE_GAP_SECONDS = 300


def family(model: str) -> Optional[str]:
    """``opus``, ``sonnet`` or ``haiku`` for a model id, else ``None`` (synthetic turns)."""
    for name in MODEL_WEIGHT:
        if name in (model or ""):
            return name
    return None


def weighted(usage: Dict, model: str) -> float:
    """Relative cost of one turn."""
    fam = family(model)
    if not fam:
        return 0.0
    created = usage.get("cache_creation") or {}
    write = 1.25 * created.get("ephemeral_5m_input_tokens", 0) + 2.0 * created.get("ephemeral_1h_input_tokens", 0)
    if not created:
        write = 1.25 * usage.get("cache_creation_input_tokens", 0)
    return MODEL_WEIGHT[fam] * (usage.get("input_tokens", 0) + 0.1 * usage.get("cache_read_input_tokens", 0)
                                + write + 5 * usage.get("output_tokens", 0))


def parse_time(stamp: str) -> datetime.datetime:
    return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))


class Session:
    """One transcript file (a main session or a subagent)."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.name = path.stem[:12]
        self.subagent = "subagents" in path.parts
        self.turns: List[Dict] = []

    def load(self) -> "Session":
        by_id: Dict[str, Dict] = {}
        with open(self.path, encoding="utf-8", errors="replace") as handle:
            lines = handle.readlines()
        for raw in lines:
            try:
                record = json.loads(raw)
            except ValueError:
                continue
            if record.get("type") != "assistant":
                continue
            message = record.get("message") or {}
            key = message.get("id") or record.get("uuid")
            turn = by_id.setdefault(key, {"model": message.get("model") or "", "usage": message.get("usage") or {},
                                          "time": record.get("timestamp"), "poll": False})
            for block in message.get("content") or []:
                if block.get("type") == "tool_use" and block.get("name") == "Bash":
                    command = str((block.get("input") or {}).get("command", ""))
                    if POLL.search(re.sub(r"<<-?\s*'?(\w+)'?.*?\n\s*\1\b", "", command, flags=re.S)):
                        turn["poll"] = True
        self.turns = sorted((t for t in by_id.values() if t["usage"] and t["time"]), key=lambda t: t["time"])
        return self

    @staticmethod
    def context(turn: Dict) -> int:
        usage = turn["usage"]
        return usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0) + usage.get("cache_creation_input_tokens", 0)

    def rewrites(self) -> int:
        """Turns that wrote most of the context to cache again after a pause longer than the 5-minute TTL."""
        count, previous = 0, None
        for turn in self.turns:
            usage = turn["usage"]
            written, read = usage.get("cache_creation_input_tokens", 0), usage.get("cache_read_input_tokens", 0)
            if previous and written > 50_000 and written > read * 0.5 \
                    and (parse_time(turn["time"]) - parse_time(previous)).total_seconds() >= REWRITE_GAP_SECONDS:
                count += 1
            previous = turn["time"]
        return count


def find_sessions(root: Path, projects: str, since: Optional[str]) -> List[Session]:
    sessions = []
    for directory in sorted(glob.glob(str(root / projects))):
        for path in Path(directory).rglob("*.jsonl"):
            session = Session(path).load()
            if since:
                session.turns = [t for t in session.turns if t["time"][:10] >= since]
            if session.turns:
                sessions.append(session)
    return sessions


def report(sessions: List[Session], top: int = 8) -> str:
    out: List[str] = []
    day: Dict = defaultdict(Counter)
    for session in sessions:
        for turn in session.turns:
            fam = family(turn["model"])
            if not fam:
                continue
            usage = turn["usage"]
            bucket = day[(turn["time"][:10], fam)]
            bucket["turns"] += 1
            bucket["cost"] += weighted(usage, turn["model"])
            bucket["read"] += usage.get("cache_read_input_tokens", 0)
            bucket["write"] += usage.get("cache_creation_input_tokens", 0)
            bucket["out"] += usage.get("output_tokens", 0)
    out.append("DAY         MODEL   TURNS  COST(M)  CACHE-READ(M)  CACHE-WRITE(M)  OUTPUT(k)")
    for (date, fam), b in sorted(day.items()):
        out.append(f"{date}  {fam:6} {b['turns']:6} {b['cost'] / 1e6:8.0f} {b['read'] / 1e6:14.0f} {b['write'] / 1e6:15.1f} {b['out'] / 1e3:10.0f}")
    total = sum(b["cost"] for b in day.values()) or 1.0

    rows = []
    for session in sessions:
        cost = sum(weighted(t["usage"], t["model"]) for t in session.turns)
        contexts = [Session.context(t) for t in session.turns]
        rows.append((cost, session, sum(contexts) // len(contexts), max(contexts)))
    out.append("")
    out.append(f"TOP SESSIONS (of {total / 1e6:.0f}M)   cost%  turns  avg-ctx(k)  max-ctx(k)  polls  rewrites")
    for cost, session, avg, peak in sorted(rows, key=lambda r: -r[0])[:top]:
        polls = sum(1 for t in session.turns if t["poll"])
        out.append(f"  {session.name:12} {'sub ' if session.subagent else 'main'}  {100 * cost / total:5.1f} {len(session.turns):6} {avg // 1000:10} {peak // 1000:11} {polls:6} {session.rewrites():9}")

    long_sessions = [r for r in rows if len(r[1].turns) > LONG_SESSION_TURNS]
    polls = sum(1 for r in rows for t in r[1].turns if t["poll"])
    poll_cost = sum(weighted(t["usage"], t["model"]) for r in rows for t in r[1].turns if t["poll"])
    rewrites = sum(r[1].rewrites() for r in rows)
    out.append("")
    out.append("HABITS")
    out.append(f"  sessions over {LONG_SESSION_TURNS} turns: {len(long_sessions)} of {len(rows)} "
               f"({100 * sum(r[0] for r in long_sessions) / total:.0f}% of cost)")
    out.append(f"  poll turns (sleep loops): {polls} ({100 * poll_cost / total:.0f}% of cost)")
    out.append(f"  turns that re-wrote the whole cached context after a 5+ min gap: {rewrites}")
    out.append("  healthy: 0 sessions over 200 turns, 0 poll turns, 0 rewrites")
    return "\n".join(out)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--projects", default=default_project_glob(), help="glob of project directories under --root")
    parser.add_argument("--since", help="only turns on or after this date (YYYY-MM-DD)")
    parser.add_argument("--top", type=int, default=8)
    parser.add_argument("--root", type=Path, default=Path(os.path.expanduser("~/.claude/projects")))
    args = parser.parse_args(argv)
    sessions = find_sessions(args.root, args.projects, args.since)
    if not sessions:
        print("no transcripts found", file=sys.stderr)
        return 1
    print(report(sessions, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
