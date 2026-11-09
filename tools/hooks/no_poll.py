#!/usr/bin/env python3
"""PreToolUse hook for Bash: refuse sleep loops that wait on a background job.

A model that polls pays a full-context turn for every wake-up, and past five minutes the prompt cache has
expired too. Background commands already notify on exit, so the right move is to launch with
``run_in_background`` (through ``tools/bg_run.py``) and end the turn. Exit 2 sends the message back to the model.

A command that really must loop can carry ``# poll-ok`` and a reason.
"""

from __future__ import annotations

import json
import re
import sys
from typing import List, Optional

MESSAGE = (
    "Blocked: do not poll or sleep-loop to wait for a job. Launch it with run_in_background and "
    "`tools/bg_run.py LABEL -- COMMAND` (it prints a short digest on exit), then END YOUR TURN: you are "
    "notified when it finishes. Each poll costs a full-context turn. If this really must wait, add "
    "`# poll-ok: reason` to the command. See .agents/workflow/token-economy.md."
)

HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?\n\s*\2\b", re.S)
LOOP_WITH_SLEEP = re.compile(r"\b(?:until|while)\b.{0,400}?\bdo\b.{0,300}?\bsleep\s+[0-9$]", re.S)
FOR_SEQ_SLEEP = re.compile(r"\bfor\s+\w+\s+in\b[^;\n]*\bseq\b.{0,400}?\bdo\b.{0,300}?\bsleep\s+[0-9$]", re.S)
LONG_SLEEP = re.compile(r"(?:^|[;&|(\s])sleep\s+(\d+(?:\.\d+)?)([smh]?)\b")
TAIL_FOLLOW = re.compile(r"\btail\s+(?:-\w*[fF]\w*|--follow)\b")
MAX_SLEEP_SECONDS = 29


def reason(command: str) -> Optional[str]:
    """Why ``command`` is a poll, or ``None``."""
    if "poll-ok" in command:
        return None
    body = HEREDOC.sub("", command)
    if LOOP_WITH_SLEEP.search(body) or FOR_SEQ_SLEEP.search(body):
        return "a loop that sleeps"
    if TAIL_FOLLOW.search(body):
        return "tail -f never returns"
    for match in LONG_SLEEP.finditer(body):
        seconds = float(match.group(1)) * {"": 1, "s": 1, "m": 60, "h": 3600}[match.group(2)]
        if seconds > MAX_SLEEP_SECONDS:
            return f"sleep {match.group(1)}{match.group(2)}"
    return None


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    why = reason(str((payload.get("tool_input") or {}).get("command", "")))
    if why:
        print(f"{MESSAGE} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
