#!/usr/bin/env python3
"""Stop hook: do not end a session that changed mockups without republishing the hub.

The owner browses the mockup atlas in one hub Artifact in the Claude app (``.agents/skills/mockup-hub/SKILL.md``). A
mockup that is only in the repo cannot be opened there, so every session that touches ``.agents/design/mockups/``
rebuilds the hub (``python3 tools/mockups_hub.py``, which stamps ``build/mockups-hub.built``), publishes it with the
Artifact tool, and runs ``python3 tools/mockups_hub.py --mark-published`` (stamps ``build/mockups-hub.published``).

The hook blocks (exit 2, the message goes back to the model) when a mockup this session changed is newer than either
stamp. With a snapshot for the checkout, "changed in this session" is decided by content: SessionStart stores a SHA-256
of every publishable mockup file outside the worktree (``~/.cache/sh-mockup-hub/<worktree-hash>-<session_id>.json``,
override with ``SH_MOCKUP_HUB_CACHE``), written only when absent so resume and compaction keep the first one, and Stop
compares the current files with it. A fresh worktree, a ``touch`` or a checkout that restores the same bytes never
triggers it. ``--snapshot`` is the same write for any other hook that fires first in a checkout.

A session usually starts in the primary checkout and works in a linked worktree (``EnterWorktree``), where SessionStart
never ran. With no snapshot for the Stop checkout the hook does not pass: it falls back to files that are uncommitted or
untracked and modified after the transcript began, plus files in commits made since then (a checkout's fresh mtimes
on clean files are not in that set). Registering ``--snapshot`` on PreToolUse Edit|Write|MultiEdit|Bash would make the
lazy snapshot exact; that is a ``.claude/settings.json`` change, so it is not wired here.

The candidates also include commits since the merge-base of HEAD and the lane base (the remote default branch, or a
recorded ``branch.<name>.sh-base``); the merge-base only narrows candidates, content decides. A subagent (the Designer)
that writes mockups in this checkout is covered without a SubagentStop registration. A second stop attempt
(``stop_hook_active``) is let through, so a session without the Artifact tool is not trapped: it says in its PR that the
hub republish is pending.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List

MOCKUPS = ".agents/design/mockups/"
HUB_URL = "https://claude.ai/artifact/D566bWMJYibs3HJZSD6Jba"


def _lines(root: Path, *args: str) -> List[str]:
    try:
        out = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return []
    return [line for line in out.stdout.splitlines() if line] if out.returncode == 0 else []


def _publishable(name: str) -> bool:
    """Markdown and the review notes are not published to the hub, so they never need a republish."""
    return not name.endswith(".md") and "/_review/" not in name


def lane_base(root: Path) -> str:
    """The ref this lane branched from: a recorded ``branch.<name>.sh-base`` if lane tooling set one, else the remote default branch, else ``origin/main``."""
    branch = (_lines(root, "rev-parse", "--abbrev-ref", "HEAD") or [""])[0]
    if branch and branch != "HEAD":
        base = (_lines(root, "config", "--get", f"branch.{branch}.sh-base") or [""])[0]
        if base:
            return base
    head = (_lines(root, "symbolic-ref", "--short", "refs/remotes/origin/HEAD") or [""])[0]
    return head or "origin/main"


def file_hashes(root: Path) -> Dict[str, str]:
    """SHA-256 of every publishable mockup file under the worktree, keyed by repo-relative path."""
    found: Dict[str, str] = {}
    base = root / MOCKUPS
    if not base.is_dir():
        return found
    for f in sorted(base.rglob("*")):
        name = f.relative_to(root).as_posix()
        if f.is_file() and _publishable(name):
            found[name] = hashlib.sha256(f.read_bytes()).hexdigest()
    return found


def snapshot_path(root: Path, session_id: str) -> Path:
    """Where this session's start-of-session hashes live: outside the worktree, keyed by worktree and session."""
    cache = Path(os.environ.get("SH_MOCKUP_HUB_CACHE") or Path.home() / ".cache" / "sh-mockup-hub")
    digest = hashlib.sha1(str(root).encode()).hexdigest()[:16]
    safe = "".join(c for c in session_id if c.isalnum() or c in "-_")
    return cache / f"{digest}-{safe}.json"


def session_start(root: Path, event: dict) -> Dict[str, str] | None:
    """The mockup hashes stored for this session in this checkout, or ``None`` (then Stop uses the fallback)."""
    sid = str(event.get("session_id") or "")
    path = snapshot_path(root, sid) if sid else None
    if path is None or not path.exists():
        return None
    try:
        data = json.loads(path.read_text())
    except (ValueError, OSError):
        return None
    return data if isinstance(data, dict) else None


def transcript_start(event: dict) -> float | None:
    """The transcript's birth time (when the session began), or ``None``."""
    transcript = event.get("transcript_path")
    if transcript and os.path.exists(transcript):
        return getattr(os.stat(transcript), "st_birthtime", None)
    return None


def changed_mockups(root: Path, snapshot: Dict[str, str] | None = None, since: float | None = None) -> List[Path]:
    """Mockup files this session changed that still exist.

    With a session-start ``snapshot`` for this checkout, those whose content differs from it. Without one (the session
    started in another checkout), the fallback: uncommitted or untracked files modified at or after ``since``, plus files
    in commits made since then; with ``since`` unknown, every uncommitted or untracked file.
    """
    names = set()
    merge_base = (_lines(root, "merge-base", "HEAD", lane_base(root)) or [""])[0]
    if snapshot is not None and merge_base:
        names |= set(_lines(root, "diff", "--name-only", f"{merge_base}...HEAD", "--", MOCKUPS))
    dirty = set(_lines(root, "diff", "--name-only", "HEAD", "--", MOCKUPS))
    dirty |= set(_lines(root, "ls-files", "--others", "--exclude-standard", "--", MOCKUPS))
    names |= dirty
    now = file_hashes(root)
    if snapshot is not None:
        return [root / n for n in sorted(names) if _publishable(n) and n in now and now[n] != snapshot.get(n)]
    if since is not None:
        names = {n for n in dirty if (root / n).is_file() and (root / n).stat().st_mtime >= since}
        names |= set(_lines(root, "log", f"--since=@{int(since) + 1}", "--name-only", "--format=", "--", MOCKUPS))
    return [root / n for n in sorted(names) if _publishable(n) and n in now]


def stale_reason(root: Path, snapshot: Dict[str, str] | None = None, since: float | None = None) -> str | None:
    """Why the hub is behind the mockups this session changed, or ``None``."""
    files = changed_mockups(root, snapshot, since)
    if not files:
        return None
    newest = max(f.stat().st_mtime for f in files)
    built, published = root / "build" / "mockups-hub.built", root / "build" / "mockups-hub.published"
    if not built.exists() or built.stat().st_mtime < newest:
        return "the hub has not been rebuilt since you changed mockups (python3 tools/mockups_hub.py)"
    if not published.exists() or published.stat().st_mtime < built.stat().st_mtime:
        return "the rebuilt hub has not been published (Artifact tool, then python3 tools/mockups_hub.py --mark-published)"
    return None


def project_root(event: dict) -> Path:
    """The checkout the session works in: the event's cwd first, then CLAUDE_PROJECT_DIR."""
    root = Path(event.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ".").resolve()
    top = _lines(root, "rev-parse", "--show-toplevel")
    return Path(top[0]) if top else root


def main(argv: List[str] | None = None) -> int:
    """``--session-start`` (SessionStart hook) stamps the session; otherwise this is the Stop hook."""
    try:
        event = json.load(sys.stdin)
    except (ValueError, OSError):
        event = {}
    root = project_root(event)
    if argv and ("--session-start" in argv or "--snapshot" in argv):
        sid = str(event.get("session_id") or "")
        if sid:
            stamp = snapshot_path(root, sid)
            if not stamp.exists():  # keep the first snapshot: resume and compaction fire SessionStart again
                stamp.parent.mkdir(parents=True, exist_ok=True)
                stamp.write_text(json.dumps(file_hashes(root)))
        return 0
    if event.get("stop_hook_active"):
        return 0
    reason = stale_reason(root, session_start(root, event), transcript_start(event))
    if reason is None:
        return 0
    print(
        f"Blocked: this session changed .agents/design/mockups/ but {reason}. Mockups are always republished to the hub "
        f"Artifact without being asked, and the owner gets the hub link, never HTML or a file path. Follow "
        f".agents/skills/mockup-hub/SKILL.md, then give the owner {HUB_URL}. "
        "No Artifact tool in this session? Say in the PR that the hub republish is pending and stop again.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
