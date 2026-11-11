#!/usr/bin/env python3
"""Is there an independent ``pass`` verdict for this exact commit? One answer for the push guard, ``ship.sh`` and ``merge_guard``.

The gate on SFenton/native-home is review-before-push (owner, 2026-11-09; .agents/workflow/ci.md#the-merge-gate): nothing an agent pushes
reaches the repository without a ``pass`` for the commit it pushes. The verdicts are the records ``tools/review/record.py --lane BRANCH`` writes to the
trusted store ``<account home>/hass-agents/reviews/<branch with / as __>-<sha12>.json`` (the same file ``tools/lane_land.py`` trusts), never a file in a worktree.

A record counts only when it is a JSON object, carries a reviewer identity (``agent_type`` ``reviewer`` and a session id), says ``pass``,
names the full 40-character sha as its ``head`` and holds no ``major`` or ``blocker`` finding. Anything else, an unreadable store
included, is a no (fails closed). ``remote_kind`` classifies a remote URL the same way for every caller.

    review_verdict.py pass SHA        exit 0 when SHA has a pass, 1 when not (prints why), 2 on a usage error
    review_verdict.py remote URL      prints native-home | other | local | unknown

Stdlib only (macOS system Python 3.9 and Linux).
"""
from __future__ import annotations

import json
import os
import pwd
import re
import sys
from pathlib import Path
from typing import List, Optional, Sequence

#: The repository the gate protects, lower case.
GATED_REPO = "sfenton/native-home"
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
#: ``scheme://[user@]host[:port]/owner/repo[.git]``
_URL = re.compile(r"^(?:https?|ssh|git|git\+ssh|ssh\+git)://(?:[^/@\s]+@)?[A-Za-z0-9.-]+(?::[0-9]+)?/(?P<owner>[\w.-]+)/(?P<repo>[\w.-]+?)(?:\.git)?/?$")
#: scp-like ``[user@]host:owner/repo[.git]``
_SCP = re.compile(r"^(?:[^/@\s:]+@)?[A-Za-z0-9.-]+:(?P<owner>[\w.-]+)/(?P<repo>[\w.-]+?)(?:\.git)?/?$")


def reviews_dir() -> Path:
    """The trusted verdict store: ``hass-agents/reviews`` in the account's home from the password database, never ``$HOME``
    (a command line can set ``HOME``; it cannot change who the process runs as)."""
    return Path(pwd.getpwuid(os.getuid()).pw_dir) / "hass-agents" / "reviews"


def remote_kind(url: str) -> str:
    """``native-home`` for SFenton/native-home (https, ssh or scp form, any case), ``other`` for another repository on a URL,
    ``local`` for a filesystem path or ``file://`` URL, ``unknown`` for anything else (fail closed: the caller refuses)."""
    text = url.strip()
    if not text or any(c in text for c in "\n\r\0 \t"):
        return "unknown"
    if text.startswith(("/", "./", "../", "~", "file://")):
        return "local"
    match = _URL.match(text) or _SCP.match(text)
    if not match:
        return "unknown"
    slug = (match.group("owner") + "/" + match.group("repo")).lower()
    return "native-home" if slug == GATED_REPO else "other"


def verdict_files(sha: str, directory: Optional[Path] = None) -> List[Path]:
    """The records in the store whose name ends in ``-<first 12 of sha>.json`` (empty for a malformed sha)."""
    if not isinstance(sha, str) or not FULL_SHA.match(sha):
        return []
    folder = directory if directory is not None else reviews_dir()
    suffix = "-%s.json" % sha[:12]
    try:
        return sorted(folder / name for name in os.listdir(folder) if name.endswith(suffix))
    except OSError:
        return []


def counts(path: Path, sha: str) -> bool:
    """Does the one record at ``path`` pass ``sha``? Any read or shape problem is a no."""
    try:
        data = json.loads(path.read_text())
        who = data.get("reviewer")
        if not isinstance(who, dict) or who.get("agent_type") != "reviewer" or not str(who.get("session_id") or "").strip():
            return False
        if data.get("verdict") != "pass" or str(data.get("head") or "") != sha:
            return False
        findings = data.get("findings") or []
        return not any(not isinstance(f, dict) or f.get("severity") in ("major", "blocker") for f in findings)
    except Exception:  # noqa: BLE001 - a record that cannot be read is no record
        return False


def has_pass(sha: str, directory: Optional[Path] = None) -> bool:
    """True only when a record in the trusted store passes exactly ``sha`` (a full 40-character lower-case hex sha)."""
    return any(counts(path, sha) for path in verdict_files(sha, directory))


def main(argv: Optional[Sequence[str]] = None) -> int:
    """CLI: ``pass SHA`` or ``remote URL`` (see the module docstring)."""
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) == 2 and args[0] == "pass":
        if has_pass(args[1]):
            return 0
        print("review_verdict: no independent pass for %s in %s; the reviewer records one with tools/review/record.py --lane BRANCH "
              "for exactly this commit" % (args[1][:12], reviews_dir()), file=sys.stderr)
        return 1
    if len(args) == 2 and args[0] == "remote":
        print(remote_kind(args[1]))
        return 0
    print(__doc__.split("\n\n")[0], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
