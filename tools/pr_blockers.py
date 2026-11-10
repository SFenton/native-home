#!/usr/bin/env python3
"""Why GitHub will not merge a pull request on its own: the shared reading used by ``tools/ci_wait.py`` and ``tools/pr_land.py``.

:func:`blockers` reads ``mergeable``, ``isDraft``, ``reviewDecision`` and whether the changed files match ``.github/CODEOWNERS``. The
CODEOWNERS matcher here is the only one in the repository (``tools/tests/test_codeowners_cover.py`` imports it). It follows GitHub's
rule: the **last matching pattern wins**, and a match with no owner leaves the file unowned. Supported patterns: a leading ``/`` anchors
to the repository root, a trailing ``/`` is a directory and everything under it, ``*`` and ``?`` do not cross ``/``, ``**`` does, and a
pattern without a slash matches at any depth. Not implemented (the file uses none): ``!`` negation, ``[...]`` classes, escapes, team or
email owners.

``pr_land.py`` loads this module, so it is code-owned and pinned to the base copy by ``merge_guard`` (``PINNED_WITH``); stdlib only.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

#: The ruleset requires code-owner review (``require_code_owner_review``), so a PR touching a CODEOWNERS path waits for the owner.
CODEOWNERS = Path(__file__).resolve().parents[1] / ".github" / "CODEOWNERS"

Rule = Tuple[str, List[str]]


def parse(text: str) -> List[Rule]:
    """``(pattern, owners)`` for each rule line of a CODEOWNERS text, comments and blanks dropped."""
    rules: List[Rule] = []
    for raw in text.splitlines():
        line = raw.split(" #", 1)[0].strip()
        if line and not line.startswith("#"):
            pattern, *owners = line.split()
            rules.append((pattern, owners))
    return rules


def load_rules(path: Optional[Path] = None) -> List[Rule]:
    """The rules of ``.github/CODEOWNERS``; ``[]`` when the file cannot be read."""
    try:
        return parse((path or CODEOWNERS).read_text(encoding="utf-8"))
    except OSError:
        return []


def pattern_regex(pattern: str) -> "re.Pattern[str]":
    """The regex for one gitignore-style CODEOWNERS pattern (see the module docstring for what is supported)."""
    anchored = pattern.startswith("/") or "/" in pattern.rstrip("/")
    body = pattern.strip("/")
    out, i = "", 0
    while i < len(body):
        if body.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif body.startswith("**", i):
            out, i = out + ".*", i + 2
        elif body[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif body[i] == "?":
            out, i = out + "[^/]", i + 1
        else:
            out, i = out + re.escape(body[i]), i + 1
    return re.compile(("" if anchored else "(?:.*/)?") + out + ("/.*" if pattern.endswith("/") else "(?:/.*)?") + r"\Z")


def owners_of(path: str, rules: Sequence[Rule]) -> Optional[List[str]]:
    """The owners of ``path`` from the last matching rule (GitHub's rule), or ``None`` when no rule matches."""
    found: Optional[List[str]] = None
    for pattern, owners in rules:
        if pattern_regex(pattern).match(path):
            found = owners
    return found


def owned_files(state: Dict[str, Any], rules: Optional[Sequence[Rule]] = None) -> List[str]:
    """The changed files of the PR (``files`` of ``gh pr view``) whose last matching CODEOWNERS rule names an owner."""
    rules = load_rules() if rules is None else rules
    paths = [str(f.get("path") if isinstance(f, dict) else f) for f in state.get("files") or []]
    return [p for p in paths if owners_of(p, rules)]


def blockers(state: Dict[str, Any], rules: Optional[Sequence[Rule]] = None) -> List[str]:
    """Why GitHub will not merge the PR on its own, from ``mergeable``, ``isDraft``, ``reviewDecision`` and the CODEOWNERS match.

    ``mergeable`` ``UNKNOWN`` (GitHub still computing it) is not a blocker. A state without those fields has none."""
    found = []
    if state.get("mergeable") == "CONFLICTING":
        found.append("conflicts with main; GitHub runs no pull_request checks; merge main and push")
    if state.get("isDraft"):
        found.append("draft; mark it ready (gh pr ready)")
    owned = owned_files(state, rules)
    if owned and state.get("reviewDecision") != "APPROVED":
        found.append(f"code-owner review required ({state.get('reviewDecision') or 'REVIEW_REQUIRED'}) for {owned[0]}"
                     f"{f' and {len(owned) - 1} more' if len(owned) > 1 else ''}; the owner approves and merges")
    return found


def owner_only(state: Dict[str, Any], rules: Optional[Sequence[Rule]] = None) -> bool:
    """Is what stands between the PR and a merge only the owner's to clear: a draft or a missing code-owner review, with no conflict?"""
    found = blockers(state, rules)
    return bool(found) and state.get("mergeable") != "CONFLICTING"
