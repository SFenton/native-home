#!/usr/bin/env python3
"""PreToolUse hook for Bash: deny a long background job that the harness would kill after 30 minutes.

The harness stops a ``run_in_background`` Bash call after 30 minutes unless the call passes ``timeout`` (milliseconds,
at most 7200000). A full UI run takes about 50 minutes, so launched without one the job is killed mid-way and its
children are orphaned. This guard denies a background call whose command runs ``ios_uitest.sh --full`` (also through
``bash``, ``tools/bg_run.py LABEL --`` or ``devcap.py run --``) with no ``timeout`` of at least ``MIN_TIMEOUT_MS`` and says
how to retry. ``apple_coverage.sh`` is not guarded: it is the host-only logic gate, not a long job.

A sub-agent's background job dies when its turn ends, so a ``run_in_background`` Bash call from a payload with ``agent_id``
(the main session never carries one) is denied whatever the command is.

A sub-agent's foreground call that reaches its ``timeout`` moves to the background and dies with the turn. So a sub-agent's
foreground call that runs ``tools/bg_run.py`` or a full UI run must end the job first: every ``bg_run.py`` run carries ``--timeout S``,
the sum of the S values is at most the call's ``timeout`` (capped at ``FOREGROUND_CAP_MS``) minus ``MARGIN_S`` seconds, and the call
passes its ``timeout``. A loop, or a bare full run beside no bound, is denied.

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

SUBAGENT = (
    "Blocked: a sub-agent's background job is killed when its turn ends. Run it as a foreground Bash call with timeout "
    "up to 600000 (milliseconds), splitting it into calls that each fit (for example one device family per call). A job "
    "that cannot fit: report `blocked` with the exact `tools/bg_run.py` command, so the orchestrator runs it unchanged from the main session. "
    "See .agents/workflow/token-economy.md."
)

#: The most a foreground Bash call may run: its ``timeout`` ceiling.
FOREGROUND_CAP_MS = 600_000
#: Seconds a bounded foreground job must finish before the call's ``timeout``.
MARGIN_S = 30

UNBOUNDED = (
    "Blocked: a sub-agent's foreground `{what}` that reaches the Bash `timeout` is moved to the background by the harness and dies "
    "when your turn ends. End the job before the call does: pass timeout (milliseconds, at most {cap}) on the Bash call and "
    "`tools/bg_run.py LABEL --timeout S -- COMMAND` with S (summed over every bg_run in the call) at most the call's timeout in seconds minus {margin}{limit}; a full UI run goes through bg_run. "
    "A job that cannot fit: report `blocked` with the exact command. See .agents/workflow/token-economy.md."
)

LOOP = (
    "Blocked: `{what}` sits in a loop or a pipe-fed list of runs whose total time cannot be bounded, so a sub-agent's foreground "
    "call could pass its Bash `timeout` and be moved to the background, where it dies with the turn. Split the work into one "
    "bounded `tools/bg_run.py LABEL --timeout S -- COMMAND` run per call. See .agents/workflow/token-economy.md."
)

HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?\n\s*\2\b", re.S)
SEPARATORS = re.compile(r"\n|;|&&|\|\||\||&(?!>)")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
#: Tokens that may stand directly before a script path and leave it the program being run.
LOOPS = {"for", "while", "until", "xargs", "parallel"}
LAUNCHERS = {"--", "bash", "sh", "zsh", "time", "env", "nohup", "exec", "command", "then", "do", "-c", "-lc"}


#: ``LAUNCHERS`` without ``--``: before ``bg_run.py`` it is the end of another command's options (``git diff -- tools/bg_run.py``).
RUNNERS = LAUNCHERS - {"--"}


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


def _segments(command: str) -> List[List[str]]:
    """The token list of each simple command in ``command`` (heredoc bodies dropped)."""
    out = []
    for segment in SEPARATORS.split(HEREDOC.sub("", command)):
        try:
            out.append(shlex.split(segment, comments=True))
        except ValueError:
            out.append(segment.split())
    return out


def bg_run_bound(tokens: List[str]) -> Optional[tuple]:
    """``(text, seconds)`` for the ``tools/bg_run.py`` run in one command's ``tokens``; seconds is its ``--timeout`` or ``None``."""
    for index, token in enumerate(tokens):
        if _script(token) != "bg_run.py":
            continue
        before = tokens[index - 1] if index else ""
        if index and not (before in RUNNERS or ASSIGNMENT.match(before) or _script(before) in RUNNERS
                          or _script(before).startswith("python")):
            continue  # a name in `grep bg_run.py` or `git diff -- tools/bg_run.py`, not a run
        options = tokens[index + 1:]
        options = options[:options.index("--")] if "--" in options else options
        seconds = None
        for position, option in enumerate(options):
            value = None
            if option.startswith("--timeout="):
                value = option.split("=", 1)[1]
            elif option == "--timeout" and position + 1 < len(options):
                value = options[position + 1]
            if value is not None:
                try:
                    seconds = float(value)
                except ValueError:
                    seconds = None
        return " ".join([token] + tokens[index + 1:index + 7]), seconds
    return None


def foreground_verdict(tool_input: dict) -> Optional[str]:
    """The denial text for a sub-agent's foreground call whose long jobs could outlive the call's ``timeout``, or ``None`` to allow.

    Every ``bg_run.py`` run and every bare full UI run in the command counts. Each bg_run needs a ``--timeout`` and their sum must
    fit; a loop, or a bare full run, cannot be bounded, so it is denied.
    """
    command = str(tool_input.get("command", ""))
    runs, bare, loop = [], [], False
    for tokens in _segments(command):
        if tokens and tokens[0] in LOOPS:
            loop = True
        run = bg_run_bound(tokens)
        if run:
            runs.append(run)
        elif long_job(" ".join(shlex.quote(t) for t in tokens)):
            bare.append(" ".join(tokens[:7]))
    if not runs and not bare:
        return None
    call_ms = min(timeout_ms(tool_input), FOREGROUND_CAP_MS)
    limit = f" (here at most {call_ms // 1000 - MARGIN_S})" if call_ms > MARGIN_S * 1000 else ""
    what = (runs[0][0] if runs else bare[0])
    if loop:
        return LOOP.format(what=what)
    if bare or not call_ms or any(not seconds or seconds <= 0 for _, seconds in runs):
        return UNBOUNDED.format(what=what, cap=FOREGROUND_CAP_MS, margin=MARGIN_S, limit=limit)
    if sum(seconds for _, seconds in runs) * 1000 > call_ms - MARGIN_S * 1000:
        return UNBOUNDED.format(what=what, cap=FOREGROUND_CAP_MS, margin=MARGIN_S, limit=limit)
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
        tool_input = payload.get("tool_input") or {}
        if payload.get("agent_id") and tool_input.get("run_in_background"):
            why = SUBAGENT
        elif payload.get("agent_id"):
            why = foreground_verdict(tool_input)
        else:
            why = verdict(tool_input)
    except Exception:  # noqa: BLE001 - a hook never traps an agent
        return 0
    if why:
        print(why, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
