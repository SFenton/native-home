#!/usr/bin/env python3
"""Squash-merge a Studio pull request (``tools/studio_land.py N``) after the gates GitHub does not run there.

SFenton/ha-native-home-app has no ruleset, no branch protection and no auto-merge, so GitHub enforces nothing on it: this script checks the
checks itself. It refuses, in order: the kill switch; a pull request that is not open, not from this repository, not by the owner or the
configured agent login (:func:`pr_land.author_ok`), not based on ``main``, in conflict, or labelled ``Needs Decision``; any changed
file in ``studio_owner_paths`` (``.github/``, the release scripts, ``Dockerfile``, ``CHANGELOG.md``, ``config.yaml``, ``package.json`` and its lock: the owner's); no independent ``pass`` for the full head sha
(:func:`review_verdict.has_pass`); and any check run on that head that is not completed ``success``, ``skipped`` or ``neutral``, or a
required check run that is absent (default ``["studio"]``, overridable by an optional ``studio_required_checks`` key in ``tools/triage/config.json``, the ``ci.yml``
aggregate that needs ``checks``, ``e2e`` and ``container``). Then it runs exactly
``gh pr merge N -R SFenton/ha-native-home-app --squash --match-head-commit <head>`` (no ``--auto``, no ``--admin``, no ``--delete-branch``),
re-reads the pull request and prints one line: ``merged``, ``blocked`` or ``failed`` (``would merge`` for ``--dry-run``).

A merge on the Studio tags a release, so the pinned head matters: GitHub refuses the merge when the head moved after the checks and the pass.
This file is a ``.github/CODEOWNERS`` path (owner decision, issue 209); ``tools/hooks/merge_guard.py`` allows exactly ``tools/studio_land.py ARGS``.
Exit 0 merged or would merge, 1 blocked, 2 failed.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, List, Optional, Tuple

import pr_land
import review_verdict
from pr_land import author_ok, kill_switch, run

#: The one repository this tool merges in.
STUDIO_REPO = "SFenton/ha-native-home-app"
ALLOWED_BASE = "main"
#: The aggregate check run the Studio's ``ci.yml`` posts when ``checks``, ``e2e (n/8)`` and ``container`` passed.
DEFAULT_REQUIRED = ["studio"]
#: Conclusions that do not hold a merge.
PASSING = ("success", "skipped", "neutral")
#: What this tool never merges a change to (``studio_owner_paths``): the release pipeline and its inputs. A trailing ``/`` is a directory prefix.
DEFAULT_OWNER_PATHS = [".github/", "Dockerfile", "scripts/release.ts", "scripts/next-version.ts", "CHANGELOG.md", "config.yaml",
                       "package.json", "package-lock.json"]


def required_checks(cfg: Optional[Dict[str, Any]] = None) -> List[str]:
    """``studio_required_checks`` from the pinned triage config, or :data:`DEFAULT_REQUIRED` when absent or malformed."""
    value = (pr_land.load_config() if cfg is None else cfg).get("studio_required_checks")
    if isinstance(value, list) and value and all(isinstance(n, str) and n.strip() for n in value):
        return [n.strip() for n in value]
    return list(DEFAULT_REQUIRED)


def owner_paths(cfg: Optional[Dict[str, Any]] = None) -> List[str]:
    """``studio_owner_paths`` from the pinned triage config, or :data:`DEFAULT_OWNER_PATHS` when absent or malformed."""
    value = (pr_land.load_config() if cfg is None else cfg).get("studio_owner_paths")
    if isinstance(value, list) and value and all(isinstance(n, str) and n.strip() for n in value):
        return [n.strip() for n in value]
    return list(DEFAULT_OWNER_PATHS)


def owner_hits(files: List[str], owned: List[str]) -> List[str]:
    """The ``files`` an ``owned`` entry covers: a directory entry (ends in ``/``) by prefix, any other entry exactly."""
    return [f for f in files if any(f.startswith(o) if o.endswith("/") else f == o for o in owned)]


def changed_files(number: str) -> List[str]:
    """Every path the pull request touches, renames' old paths included, all pages (``gh pr view`` caps its file list)."""
    out = run(["gh", "api", f"repos/{STUDIO_REPO}/pulls/{number}/files?per_page=100", "--paginate", "--jq",
               ".[] | .filename, (.previous_filename // empty)"]).stdout
    return [line.strip() for line in out.splitlines() if line.strip()]


def check_runs(head: str) -> List[Dict[str, Any]]:
    """The latest check run per name on ``head``, as ``{"name", "status", "conclusion"}`` dicts."""
    out = run(["gh", "api", f"repos/{STUDIO_REPO}/commits/{head}/check-runs?per_page=100", "--paginate", "--jq",
               ".check_runs[] | {name, status, conclusion}"]).stdout
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def checks_refusal(runs: List[Dict[str, Any]], required: List[str]) -> Optional[str]:
    """Why the check runs hold the merge, or ``None``: a required name absent, or any run not completed with a passing conclusion."""
    names = {str(r.get("name")) for r in runs}
    missing = [n for n in required if n not in names]
    if missing:
        return "required check run absent on this head: " + ", ".join(missing)
    bad = [f"{r.get('name')} ({r.get('conclusion') if r.get('status') == 'completed' else r.get('status')})" for r in runs
           if r.get("status") != "completed" or r.get("conclusion") not in PASSING]
    return ("checks not passing on this head: " + ", ".join(bad)) if bad else None


def merge_command(number: str, head: str) -> List[str]:
    """The only merge this tool runs: a squash pinned to ``head`` (GitHub refuses it when the head moved)."""
    return ["gh", "pr", "merge", number, "-R", STUDIO_REPO, "--squash", "--match-head-commit", head]


def land(number: str, dry_run: bool) -> Tuple[int, str]:
    """Run the gates, then merge the exact head. Returns ``(exit code, one line)``: 0 for ``merged`` and ``would merge``, 1 for
    ``blocked``, 2 for ``failed``."""
    paused = kill_switch()
    if paused:
        return 1, f"blocked #{number}: landing paused ({paused})"
    info = json.loads(run(["gh", "pr", "view", number, "-R", STUDIO_REPO, "--json",
                           "state,isDraft,headRefName,headRefOid,mergeable,baseRefName,labels,author,isCrossRepository"]).stdout)
    if info.get("state") != "OPEN":
        return 1, f"blocked #{number}: pull request is {str(info.get('state')).lower()}"
    author = info.get("author")
    login = author.get("login") if isinstance(author, dict) else None
    if info.get("isCrossRepository") is not False:
        return 1, f"blocked #{number}: not from {STUDIO_REPO} itself (fork {info.get('isCrossRepository')!r})"
    if not author_ok(login):
        return 1, f"blocked #{number}: author {login!r} is neither {pr_land.AUTHOR} nor the configured agent login"
    base = str(info.get("baseRefName") or "")
    if base != ALLOWED_BASE:
        return 1, f"blocked #{number}: the base is {base or '?'}, not {ALLOWED_BASE}"
    if info.get("mergeable") == "CONFLICTING":
        return 1, f"blocked #{number}: merge conflicts with {base}"
    if any((label.get("name") if isinstance(label, dict) else label) == "Needs Decision" for label in info.get("labels") or []):
        return 1, f"blocked #{number}: labelled Needs Decision"
    owned = owner_hits(changed_files(number), owner_paths())
    if owned:
        return 1, f"blocked #{number}: changes the owner's release files: {', '.join(owned[:3])}"
    head = str(info.get("headRefOid") or "")
    if not review_verdict.has_pass(head):
        return 1, f"blocked #{number}: no independent pass for {head[:12] or '?'} (record.py --lane {info.get('headRefName')} for exactly this head)"
    refusal = checks_refusal(check_runs(head), required_checks())
    if refusal:
        return 1, f"blocked #{number}: {refusal}"
    if dry_run:
        return 0, f"would merge #{number} at {head[:8]}"
    if info.get("isDraft"):
        run(["gh", "pr", "ready", number, "-R", STUDIO_REPO])
    proc = run(merge_command(number, head), check=False)
    if proc.returncode:
        return 2, f"failed #{number}: GitHub refused: {((proc.stderr or proc.stdout or '').strip() or 'no message')[:300]}"
    after = json.loads(run(["gh", "pr", "view", number, "-R", STUDIO_REPO, "--json", "state"]).stdout or "{}")
    if after.get("state") == "MERGED":
        return 0, f"merged #{number} at {head[:8]}"
    return 2, f"failed #{number}: gh pr merge returned but the pull request is not merged"


def main(argv: Optional[List[str]] = None) -> int:
    """CLI: ``studio_land.py N [--dry-run]``; prints one line and returns its exit code."""
    parser = argparse.ArgumentParser(allow_abbrev=False, description="Squash-merge a Studio pull request after the local gates.")
    parser.add_argument("number")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    number = args.number.lstrip("#")
    try:
        if not number.isdigit():
            raise ValueError("the pull request number must be digits")
        code, line = land(number, args.dry_run)
    except (RuntimeError, ValueError, KeyError, OSError) as exc:
        code, line = 2, f"failed #{args.number}: {exc}"
    print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
