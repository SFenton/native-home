#!/usr/bin/env python3
"""PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit, scoped to the researcher.

The researcher writes only ``build/research/**`` and ``.claude/agent-memory/researcher/**`` (relative to the repo or
worktree root, found from the payload ``cwd``). Registered in project ``.claude/settings.json``
and acting only when the payload's ``agent_type`` is ``researcher``; a missing, null or other ``agent_type`` is
allowed. (Hooks in agent frontmatter did not fire in ``claude -p --agent`` sessions, live 2026-11-01; settings hooks
do, and carry ``agent_type`` on the main thread and in subagents.) Bash stays read-only by prompt only.
Exit 2 sends the message back.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from typing import List, Optional

ALLOWED = ("build/research", ".claude/agent-memory/researcher")
MESSAGE = (
    "Blocked: the researcher writes only build/research/<slug>.md and .claude/agent-memory/researcher/. Put "
    "anything else in the note as a recommendation or in `implementation_specs` and let the orchestrator dispatch it."
)


def root_of(cwd: str) -> str:
    """The git toplevel of ``cwd`` (``cwd`` itself when git cannot say)."""
    try:
        out = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                             timeout=10)
        if out.returncode == 0 and out.stdout.strip():
            return os.path.realpath(out.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.realpath(cwd)


def allowed(path: str, cwd: str) -> bool:
    """Is ``path`` inside an allowed directory of the repo that holds ``cwd``?"""
    root = root_of(cwd)
    full = os.path.realpath(path if os.path.isabs(path) else os.path.join(cwd, path))
    return any(full.startswith(os.path.join(root, a) + os.sep) for a in ALLOWED)


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") not in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        return 0
    if payload.get("agent_type") != "researcher":
        return 0
    tool_input = payload.get("tool_input") or {}
    path = str(tool_input.get("file_path") or tool_input.get("notebook_path") or "")
    if not path:
        return 0
    cwd = str(payload.get("cwd") or os.getcwd())
    if allowed(path, cwd):
        return 0
    print(f"{MESSAGE} (path: {path})", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
