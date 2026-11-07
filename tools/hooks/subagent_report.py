#!/usr/bin/env python3
"""SubagentStop hook: every agent ends with a fenced ``status`` JSON block ([agent-roster](../../.agents/workflow/agent-roster.md)).

Blocks the stop (JSON ``decision: block``, whose reason goes back to the agent) when:

- the last assistant message has no parseable ``status`` block with a valid ``status`` value; or
- the status is ``done`` and an ``acceptance`` value is ``fail``; or
- a ``coder`` reports ``blocked`` with more than ``DIRTY_LIMIT`` dirty files in its worktree and a ``blocked_reason``
  that does not start with ``waiting_bg:`` (an unfinished, uncommitted hand-back looks the same as a dead agent).

Each case blocks once: when ``stop_hook_active`` is true (the agent is already continuing because of a stop hook)
the stop is allowed, with a warning on stderr, so a hook never traps an agent. Only the roster agent types in
``ROSTER`` are judged; every other type (built-in helpers, plugin agents, ``claude``, ``general-purpose``) passes
untouched because it is not briefed with the contract.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from typing import Dict, List, Optional

STATUSES = {"done", "blocked", "needs_research", "needs_decision"}
ROSTER = {"orchestrator", "researcher", "designer", "coder", "verifier", "steward", "menial", "reviewer"}
DIRTY_LIMIT = 20
BLOCK = re.compile(r"```[ \t]*status[ \t]*\n(.*?)```", re.DOTALL)

MISSING = (
    "End with the status block: a fenced block tagged `status` holding JSON "
    '{"status": "done|blocked|needs_research|needs_decision", "task": "...", "summary": "...", "artifacts": [], '
    '"acceptance": {"a1": "pass|fail|not_run"}}. See .agents/workflow/agent-roster.md.'
)
FAILING = (
    "Your status is `done` but acceptance has a `fail`. Fix it, or report `blocked`/`needs_decision` with a question. "
    "Then print the status block again."
)
UNCOMMITTED = (
    "commit your work (WIP) before handing back. If your own tools/bg_run.py job is still running, report `blocked` "
    'with "blocked_reason": "waiting_bg: <label>" instead. Then print the status block again.'
)


def parse_status(text: str) -> Optional[Dict]:
    """The last parseable ``status`` block in ``text`` as a dict, or ``None``."""
    for body in reversed(BLOCK.findall(text or "")):
        try:
            data = json.loads(body)
        except ValueError:
            continue
        if isinstance(data, dict) and data.get("status") in STATUSES:
            return data
    return None


def dirty_count(cwd: str) -> int:
    """Number of dirty paths (status --short lines) in ``cwd``; 0 when the check fails or ``cwd`` is empty."""
    if not cwd:
        return 0
    try:
        done = subprocess.run(["git", "status", "--short"], cwd=cwd, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return 0
    return len(done.stdout.splitlines()) if done.returncode == 0 else 0


def problem(text: str, agent_type: str = "", cwd: str = "") -> Optional[str]:
    """What is wrong with ``text`` as a final message, or ``None``."""
    data = parse_status(text)
    if data is None:
        return MISSING
    acceptance = data.get("acceptance")
    if data["status"] == "done" and isinstance(acceptance, dict) and "fail" in acceptance.values():
        return FAILING
    if agent_type == "coder" and data["status"] == "blocked":
        reason = str(data.get("blocked_reason") or "")
        if not reason.startswith("waiting_bg:") and dirty_count(cwd) > DIRTY_LIMIT:
            return UNCOMMITTED
    return None


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; print a block decision when the report is not acceptable."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("agent_type", "") not in ROSTER:
        return 0
    why = problem(str(payload.get("last_assistant_message") or ""), str(payload.get("agent_type") or ""),
                  str(payload.get("cwd") or ""))
    if not why:
        return 0
    if payload.get("stop_hook_active"):
        print(f"subagent_report: allowing the stop anyway. {why}", file=sys.stderr)
        return 0
    print(json.dumps({"decision": "block", "reason": why}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
