#!/usr/bin/env python3
"""PreToolUse hook for Bash, scoped to the orchestrator: it plans and dispatches, it never builds or tests.

Evidence: in the UIKit port the Opus orchestrator made 676 Bash calls of its own. Builds, tests, simulators and
perf runs belong to the Verifier (evidence) or Menial (re-runs and digests).

Scope: registered in project ``.claude/settings.json`` (Bash matcher) and acts only when the payload's
``agent_type`` is ``orchestrator``; a missing, null or other ``agent_type`` is allowed, so normal sessions and other
agents are unaffected. Live evidence (2026-11-01): hooks declared in agent frontmatter did not fire in
``claude -p --agent orchestrator`` (it ran ``xcodebuild -version``), while settings hooks did, and their payload
carried ``agent_type`` null in a plain session, ``"orchestrator"`` (no ``agent_id``) on the main thread and
``"orchestrator"`` plus ``agent_id`` in a subagent.

Wrappers are looked through: ``env``, ``timeout`` and the like, ``xargs``, shells (``bash -c``), and the sanctioned
launcher ``tools/bg_run.py LABEL [--timeout S] -- CMD``, so a wrapped build is still refused.

Blocked: ``xcodebuild``, ``swift build|test``, ``tools/ios_uitest.sh``, ``tools/apple_coverage.sh``,
``tools/devcap.py run``, ``xcrun simctl boot|install|launch``, ``tools/ios_*perf.sh``, ``tools/uikit_build.sh`` and
``tools/uikit_shot.sh``. Override with a real comment, ``# orch-ok: reason``. Exit 2 sends the message back.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_parse import FEEDERS, SHELLS, find_override, strip_prefixes, tokenize, unwrap_xargs  # noqa: E402

MESSAGE = (
    "Blocked: the orchestrator does not build, test or drive simulators. Dispatch the Verifier (evidence pack, "
    "device journeys) or Menial (re-runs, logs, digests) with a brief, and read their status block. If this really "
    "is the intent, add `# orch-ok: reason` to the command. See .agents/workflow/agent-roster.md."
)
OVERRIDE = re.compile(r"#\s*orch-ok:\s*\S")
RELEVANT = re.compile(r"xcodebuild|swift|tools/|simctl|bash|sh\b|eval")
SCRIPTS = {"ios_uitest.sh", "apple_coverage.sh", "uikit_build.sh", "uikit_shot.sh"}
PERF = re.compile(r"^ios_.*perf\.sh$")


def banned(words: List[str]) -> Optional[str]:
    """The banned command ``words`` run, or ``None``."""
    words = strip_prefixes(words)
    if not words:
        return None
    base = os.path.basename(words[0])
    args = words[1:]
    if base in ("python", "python3") and args and os.path.basename(args[0]) == "bg_run.py":
        base, args = "bg_run.py", args[1:]
    if base == "bg_run.py":
        # tools/bg_run.py LABEL [--timeout S] [--dir D] -- CMD: the sanctioned launcher runs CMD, so judge CMD.
        if "--" in args:
            return banned(args[args.index("--") + 1:])
        return None
    if base in FEEDERS:
        return banned(unwrap_xargs(args)) if base == "xargs" else None
    if base == "xcodebuild":
        return "xcodebuild"
    if base == "swift" and args and args[0] in ("build", "test"):
        return f"swift {args[0]}"
    if base in SCRIPTS or PERF.match(base):
        return base
    if base == "devcap.py" and args and args[0] == "run":
        return "devcap.py run"
    if base in ("python", "python3") and args:
        script = os.path.basename(args[0])
        if script == "devcap.py" and len(args) > 1 and args[1] == "run":
            return "devcap.py run"
        if script in SCRIPTS or PERF.match(script):
            return script
    if base == "xcrun" and len(args) >= 2 and args[0] == "simctl" and args[1] in ("boot", "install", "launch"):
        return f"simctl {args[1]}"
    if base in SHELLS and "-c" in args:
        i = args.index("-c")
        if i + 1 < len(args):
            return scan(args[i + 1])
    if base == "eval" and args:
        return scan(" ".join(args))
    if base in SHELLS and args and not args[0].startswith("-"):
        script = os.path.basename(args[0])
        if script in SCRIPTS or PERF.match(script):
            return script
    return None


def scan(command: str) -> Optional[str]:
    """The first banned command in ``command``, or ``None``."""
    for _op, words in tokenize(command, RELEVANT):
        hit = banned(words)
        if hit:
            return hit
    return None


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    if payload.get("agent_type") != "orchestrator":
        return 0
    command = str((payload.get("tool_input") or {}).get("command", ""))
    if find_override(command, OVERRIDE):
        return 0
    hit = scan(command)
    if hit:
        print(f"{MESSAGE} (matched: {hit})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
