#!/usr/bin/env python3
"""PreToolUse hook for Bash: the full journey suite is the nightly and release tier, not a per-change run.

Refuses (exit 2, the message goes back to the model):

* ``tools/ios_uitest.sh`` with no filter: no ``--changed``, no ``-only-testing…`` and no ``--plan Smoke|Capture|Perf|Live``
  (``--plan Gate`` is the whole gate, so it is a full run and is refused too).

``tools/apple_coverage.sh`` is not guarded: it is the host-only logic gate and boots no simulator.

Allowed anyway when the command carries ``FENTON_TIER=nightly`` or ``FENTON_TIER=release`` (the CI workflows and the release
checklist set it; the hook process's own environment counts too), or ``--full`` together with a ``# full-ok: reason`` comment.
The scripts are found as the program or behind a launcher (``tools/bg_run.py LABEL --``, ``devcap.py run --``, ``env``,
``nohup``, ``time``, ``bash``, ``bash -c '…'``); a ``grep`` or ``cat`` that merely names them is fine.
See .agents/testing/apple/README.md (test tiers) and .agents/workflow/token-economy.md.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from typing import List, Optional

UITEST = "ios_uitest.sh"
LAUNCHERS = {"bg_run.py", "devcap.py", "bash", "sh", "zsh", "dash", "nohup", "time", "env", "exec", "command", "nice"}
SPLIT = re.compile(r"&&|\|\||\$\(|[;|&(){}`\n]|\b(?:then|do|else|elif|if|while|until)\b")
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
TIER = re.compile(r"\bFENTON_TIER=['\"]?(?:nightly|release)\b")
FULL_OK = re.compile(r"#\s*full-ok:\s*\S")
SMALL_PLANS = {"Smoke", "Capture", "Perf", "Live"}


def message(script: str) -> str:
    alternative = ("`tools/ios_uitest.sh --changed` (the journeys the diff affects), `-only-testing:FentonHomeUITests/<Class>`, "
                   "or `--plan Smoke|Capture|Perf|Live` for a family a change does not target")
    return (f"Blocked: an unfiltered {script} run is the nightly or release tier. Use {alternative}. The full run belongs to "
            "the nightly workflow and the release checklist (FENTON_TIER=nightly|release); if you really need it, add "
            "`--full` and a `# full-ok: <reason>` comment. See .agents/testing/apple/README.md and "
            ".agents/workflow/token-economy.md.")


def unfiltered(script: str, args: List[str]) -> bool:
    """Is this invocation of ``script`` a full run?"""
    if any(a in ("-h", "--help") for a in args):
        return False
    if "--changed" in args or any(a.startswith("-only-testing") for a in args):
        return False
    for i, a in enumerate(args):
        if a == "--plan" and i + 1 < len(args) and args[i + 1] in SMALL_PLANS:
            return False
        if a.startswith("--plan=") and a.split("=", 1)[1] in SMALL_PLANS:
            return False
    return True


def segment_script(segment: str) -> Optional[tuple]:
    """``(script, args, nested)`` when the simple command runs one of the guarded scripts, else ``None``."""
    try:
        words = shlex.split(segment)
    except ValueError:
        words = segment.split()
    for i, word in enumerate(words):
        if os.path.basename(word) == UITEST:
            before = [os.path.basename(w) for w in words[:i]]
            if "-n" in before:  # `bash -n script`: a syntax check, nothing runs
                return None
            core = [w for w in before if not re.match(r"^\w+=", w) and not w.startswith("-")]
            if all(w in LAUNCHERS or w == "" for w in core) or not core:
                return os.path.basename(word), words[i + 1:], None
            # `bg_run.py LABEL -- script`: a label word sits between the launcher and the script.
            if any(w in LAUNCHERS for w in core) and "--" in words[:i]:
                return os.path.basename(word), words[i + 1:], None
            return None
    # bash -c '…' and eval carry a command string.
    if words and os.path.basename(words[0]) in ("bash", "sh", "zsh", "dash"):
        for j, w in enumerate(words[1:-1], 1):
            if SHELL_C.match(w):
                return "", [], words[j + 1]
    return None


def reason(command: str) -> Optional[str]:
    """The refusal text for ``command``, or ``None``."""
    if TIER.search(command) or os.environ.get("FENTON_TIER") in ("nightly", "release"):
        return None
    for segment in SPLIT.split(command):
        hit = segment_script(segment)
        if not hit:
            continue
        script, args, nested = hit
        if nested is not None:
            inner = reason(nested)
            if inner:
                return inner
            continue
        if unfiltered(script, args):
            if "--full" in args and FULL_OK.search(command):
                continue
            return message(script)
    return None


def main() -> int:
    """Read the hook payload from stdin; exit 2 with the refusal to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    why = reason(str((payload.get("tool_input") or {}).get("command", "")))
    if why:
        print(why, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
