#!/usr/bin/env python3
"""PreToolUse hook for ``mcp__t3-code__delegate_task``: admit Coder lanes and advisory plan reviews.

A delegated T3 thread runs none of this repository's Claude hooks (review, push, commit, merge, worktree guards), so the only
safe things to send it are a Coder lane or a prompt-declared advisory plan review. The call is refused unless an
``implementation`` prompt names ``.claude/agents/coder.md`` and the ``status block`` contract, or a ``review`` prompt ends with
the fixed five-field declaration. A TRIPWIRE, not a wall: it reads prompt text only, so delegated hook coverage is not proved
and the declaration cannot confine what the child reads, writes or executes.

Source of the input schema: T3 Code (Beta) ``app.asar`` (``Contents/Resources/app.asar``), the ``delegate_task`` input struct:
``task`` (the prompt, ``OrchestratorMcpPrompt``) and ``role`` (optional ``OrchestratorMcpTaskRole``: ``implementation``,
``research``, ``review``, ``design``, ``test``, ``general``), read 2026-11-20. Exit 2 sends the message back; any other tool, and
an unreadable payload, is allowed.
"""

from __future__ import annotations

import json
import re
import sys
from typing import List, Optional

TOOL = "mcp__t3-code__delegate_task"
ROLE = "implementation"
REVIEW_ROLE = "review"
CODER = ".claude/agents/coder.md"
CONTRACT = "status block"
REVIEW_FIELDS = ("review-kind", "only-write", "authority", "read-commit", "return")
REVIEW_LINES = (
    r"review-kind: advisory plan review",
    r"only-write: build/plans/[a-z0-9]+(?:-[a-z0-9]+)*-review-[1-9][0-9]*\.md",
    r"authority: advisory-only",
    r"read-commit: [0-9a-f]{40}",
    r"return: status block",
)
REVIEW_DECLARATION = "\n".join((
    "review-kind: advisory plan review",
    "only-write: build/plans/<slug>-review-<n>.md",
    "authority: advisory-only",
    "read-commit: <sha>",
    "return: status block",
))


def review_problem(prompt: str) -> Optional[str]:
    """Return the field-specific refusal for a review that lacks the exact final declaration."""
    lines = prompt.split("\n")
    if len(lines) > 1 and lines[-1] == "":
        lines.pop()

    declarations = {field: [] for field in REVIEW_FIELDS}
    reserved = re.compile(r"^(" + "|".join(REVIEW_FIELDS) + r"):(.*)$")
    for line in lines:
        match = reserved.fullmatch(line)
        if match:
            declarations[match.group(1)].append(match.group(2))

    for field in REVIEW_FIELDS:
        count = len(declarations[field])
        if count == 0:
            return (f"Blocked: delegate_task review declaration field `{field}` is missing. "
                    f"The prompt must end with this declaration:\n{REVIEW_DECLARATION}")
        if count > 1:
            return (f"Blocked: delegate_task review declaration field `{field}` appears {count} times; it must appear once. "
                    f"The prompt must end with this declaration:\n{REVIEW_DECLARATION}")

    final = lines[-len(REVIEW_FIELDS):]
    for index, field in enumerate(REVIEW_FIELDS):
        if len(final) != len(REVIEW_FIELDS) or not final[index].startswith(field + ":"):
            return (f"Blocked: delegate_task review declaration field `{field}` is out of order; the five fields must be the "
                    f"consecutive final lines in this order:\n{REVIEW_DECLARATION}")

    for field, pattern in zip(REVIEW_FIELDS, REVIEW_LINES):
        index = REVIEW_FIELDS.index(field)
        if re.fullmatch(pattern, final[index]) is None:
            return (f"Blocked: delegate_task review declaration field `{field}` is malformed. "
                    f"Expected exactly this form:\n{pattern}")
    return None


def problem(tool_input: dict) -> Optional[str]:
    """Refusal text with a fix, or ``None`` when ``delegate_task`` is an allowed lane."""
    role = tool_input.get("role")
    if role == REVIEW_ROLE:
        return review_problem(str(tool_input.get("task") or ""))
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
    """Read stdin; exit 2 with the refusal for a delegate_task outside the admitted prompt contracts."""
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
