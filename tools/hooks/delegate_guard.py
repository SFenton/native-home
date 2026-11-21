#!/usr/bin/env python3
"""PreToolUse hook for ``mcp__t3-code__delegate_task``: the T3 tool carries Coder lanes only.

A delegated T3 thread runs none of this repository's Claude hooks (review, push, commit, merge, worktree guards), so the only
safe thing to send it is a Coder lane. The call is refused unless its ``role`` is ``implementation`` and its ``task`` prompt names
``.claude/agents/coder.md`` and the ``status block`` contract; research, review, design, test and general work stay on Claude
roles, and a missing ``role`` is refused too. A tripwire for accident and habit, not a wall: it reads the prompt text only.

Source of the input schema: T3 Code (Beta) ``app.asar`` (``Contents/Resources/app.asar``), the ``delegate_task`` input struct:
``task`` (the prompt, ``OrchestratorMcpPrompt``) and ``role`` (optional ``OrchestratorMcpTaskRole``: ``implementation``,
``research``, ``review``, ``design``, ``test``, ``general``), read 2026-11-20. Exit 2 sends the message back; any other tool, and
an unreadable payload, is allowed.
"""

from __future__ import annotations

import json
import sys
from typing import List, Optional

TOOL = "mcp__t3-code__delegate_task"
ROLE = "implementation"
CODER = ".claude/agents/coder.md"
CONTRACT = "status block"


def problem(tool_input: dict) -> Optional[str]:
    """What is wrong with a ``delegate_task`` input, as the refusal text with its fix, or ``None`` when it is a Coder lane."""
    role = tool_input.get("role")
    if role != ROLE:
        return (f"Blocked: delegate_task carries only Coder lanes (role `{ROLE}`), got role `{role}`. Run research, review, design, "
                "test and general work through the Agent tool on the Claude role; see .agents/workflow/agent-roster.md#guards.")
    prompt = str(tool_input.get("task") or "")
    missing = [what for what, ok in ((f"`{CODER}`", CODER in prompt), (f"the {CONTRACT} contract", CONTRACT in prompt.lower())) if not ok]
    if missing:
        return ("Blocked: a delegate_task prompt must name " + " and ".join(missing) + ". Brief it as a Coder: point it at "
                f"`{CODER}` and end with the {CONTRACT} (agent-roster.md#contracts).")
    return None


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with the refusal to block a delegate_task that is not a Coder lane."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if not isinstance(payload, dict) or payload.get("tool_name") != TOOL:
        return 0
    tool_input = payload.get("tool_input")
    message = problem(tool_input if isinstance(tool_input, dict) else {})
    if message:
        print(message, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
