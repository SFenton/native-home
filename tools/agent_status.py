#!/usr/bin/env python3
"""Write an interactive session's status JSON to ``build/status/<task>.json`` instead of pasting it into chat.

The interactive orchestrator uses this in place of printing the fenced ``status`` block (owner, 2026-11-04). Subagents
still end with the block (``tools/hooks/subagent_report.py`` reads it) and a headless session still writes the runner's
``STATUS_FILE``; neither goes through here.

    python3 tools/agent_status.py write --task T-0142 --json '{"status": "done", ...}'
    python3 tools/agent_status.py write --task T-0142 --file status.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import List

ROOT = Path(__file__).resolve().parents[1]
STATES = ("done", "blocked", "needs_research", "needs_decision")
MAX_SUMMARY_WORDS = 250


def validate(data: object) -> List[str]:
    """Problems with a status object: the contract of ``agent-roster`` (state, task, short summary, acceptance values)."""
    if not isinstance(data, dict):
        return ["status must be a JSON object"]
    problems: List[str] = []
    if data.get("status") not in STATES:
        problems.append(f"status must be one of {', '.join(STATES)}")
    if len(str(data.get("summary", "")).split()) > MAX_SUMMARY_WORDS:
        problems.append(f"summary is over {MAX_SUMMARY_WORDS} words")
    acceptance = data.get("acceptance", {})
    if not isinstance(acceptance, dict) or any(v not in ("pass", "fail", "not_run") for v in acceptance.values()):
        problems.append("acceptance values must be pass, fail or not_run")
    if data.get("status") == "done" and isinstance(acceptance, dict) and "fail" in acceptance.values():
        problems.append("status done with a failing check")
    return problems


def write_status(task: str, data: dict, root: Path | None = None) -> Path:
    """Write ``data`` (with ``task`` filled in) to ``<root>/build/status/<task>.json`` and return the path."""
    if not re.fullmatch(r"[A-Za-z0-9._-]+", task):
        raise ValueError(f"bad task id: {task!r}")
    path = (root or ROOT) / "build" / "status" / f"{task}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({**data, "task": task}, indent=2) + "\n")
    return path


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("write", help="validate and write the status file")
    w.add_argument("--task", required=True)
    src = w.add_mutually_exclusive_group(required=True)
    src.add_argument("--json", dest="text")
    src.add_argument("--file")
    args = parser.parse_args(argv)
    try:
        text = args.text if args.text is not None else Path(args.file).read_text()
        data = json.loads(text)
    except (OSError, ValueError) as exc:
        print(f"agent_status: cannot read the status: {exc}", file=sys.stderr)
        return 2
    problems = validate(data)
    if problems:
        print("agent_status: " + "; ".join(problems), file=sys.stderr)
        return 1
    try:
        print(write_status(args.task, data))
    except ValueError as exc:
        print(f"agent_status: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
