#!/usr/bin/env python3
"""PreToolUse hook for Bash: deny a long background job that the harness would kill after 30 minutes.

The harness stops a ``run_in_background`` Bash call after 30 minutes unless the call passes ``timeout`` (milliseconds,
at most 7200000). A full UI run takes about 50 minutes, so launched without one the job is killed mid-way and its
children are orphaned. This guard denies a background call whose command runs ``ios_uitest.sh --full`` (also through
``bash``, ``tools/bg_run.py LABEL --`` or ``devcap.py run --``) with no ``timeout`` of at least ``MIN_TIMEOUT_MS`` and says
how to retry. ``apple_coverage.sh`` is not guarded: it is the host-only logic gate, not a long job.

A tripwire for a habit, not a wall: it reads the command text only, and it fails open on any error of its own (bad payload,
unparsable command). Exit 2 sends the message back to the model.
"""

from __future__ import annotations

import json
import re
import shlex
import sys
from typing import List, Optional

#: 70 minutes: a 50-minute full UI run plus slack, under the harness maximum of 7200000.
MIN_TIMEOUT_MS = 4_200_000
MAX_TIMEOUT_MS = 7_200_000

RETRY = (
    "Blocked: `{what}` runs past the harness's 30-minute background limit and would be killed mid-run, leaving its children "
    "behind. Re-issue the same Bash call with run_in_background: true and timeout: {ms} (milliseconds; the maximum is "
    f"{MAX_TIMEOUT_MS}), for example `tools/bg_run.py LABEL --expect-minutes 70 -- {{what}}`. "
    "See .agents/workflow/token-economy.md."
)

HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?\n\s*\2\b", re.S)
SEPARATORS = re.compile(r"\n|;|&&|\|\||\||&(?!>)")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
#: Tokens that may stand directly before a script path and leave it the program being run.
LAUNCHERS = {"--", "bash", "sh", "zsh", "time", "env", "nohup", "exec", "command", "then", "do", "-c", "-lc"}


def _script(token: str) -> str:
    return token.rsplit("/", 1)[-1]


def long_job(command: str) -> Optional[str]:
    """The long job ``command`` starts (``ios_uitest.sh --full``), or ``None``."""
    body = HEREDOC.sub("", command)
    for segment in SEPARATORS.split(body):
        try:
            tokens = shlex.split(segment, comments=True)
        except ValueError:
            tokens = segment.split()
        for index, token in enumerate(tokens):
            name = _script(token)
            if name != "ios_uitest.sh":
                continue
            before = tokens[index - 1] if index else ""
            if index and not (before in LAUNCHERS or ASSIGNMENT.match(before) or _script(before) in LAUNCHERS):
                continue  # `grep ios_uitest.sh`, `git add tools/ios_uitest.sh`: a name, not a run
            rest = tokens[index + 1:]
            if "--full" not in rest:
                continue
            return " ".join([token] + rest[:6]).strip()
    return None


def timeout_ms(tool_input: dict) -> int:
    """The call's ``timeout`` in milliseconds; 0 when absent or not a number."""
    value = tool_input.get("timeout")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    return int(value)


def verdict(tool_input: dict) -> Optional[str]:
    """The denial text for a Bash call's ``tool_input``, or ``None`` to allow."""
    if not tool_input.get("run_in_background"):
        return None
    what = long_job(str(tool_input.get("command", "")))
    if not what or timeout_ms(tool_input) >= MIN_TIMEOUT_MS:
        return None
    return RETRY.format(what=what, ms=MIN_TIMEOUT_MS)


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with the retry text to deny. Any error of its own allows."""
    try:
        payload = json.load(sys.stdin)
        if payload.get("tool_name") != "Bash":
            return 0
        why = verdict(payload.get("tool_input") or {})
    except Exception:  # noqa: BLE001 - a hook never traps an agent
        return 0
    if why:
        print(why, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
