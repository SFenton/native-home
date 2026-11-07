#!/usr/bin/env python3
"""Detect local-only commits on the workflow base (post-mortem T-uikit-reconcile).

    base_drift.py [--base B] [--branch NAME ...] [--exclude NAME ...]

Lists commits that exist only locally on: the local base (compared with ``origin/<base>``), each ``--branch``, and every
local non-lane branch whose ``branch.<b>.merge`` is ``refs/heads/<base>`` (lanes ``agents/*`` and ``claude/*`` cut from the
base track it by default, so they are skipped unless named with ``--branch``). For branches other than the base only commits
on no ``origin`` ref count. Read-only git, no fetch. Default base: ``workflow_base`` in ``tools/triage/config.json``.

Exit 0 clean (a missing remote ref or local branch is clean), 3 drift, 1/2 an error. Stdlib only (Python 3.9).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
FALLBACK_BASE = "main"
LANE_PREFIXES = ("agents/", "claude/")
DRIFT_EXIT = 3


def workflow_base(root: Path = ROOT) -> str:
    """``workflow_base`` from ``tools/triage/config.json`` (default ``main``)."""
    try:
        return str(json.loads((root / "tools" / "triage" / "config.json").read_text()).get("workflow_base") or FALLBACK_BASE)
    except (OSError, ValueError):
        return FALLBACK_BASE


def _git(cwd: Path, *args: str) -> Optional[str]:
    """Stdout of a read-only ``git`` command, or None when it fails (missing ref, no repo)."""
    try:
        done = subprocess.run(["git", *args], cwd=str(cwd), capture_output=True, text=True)
    except OSError:
        return None
    return done.stdout if done.returncode == 0 else None


def _exists(cwd: Path, ref: str) -> bool:
    return _git(cwd, "rev-parse", "--verify", "-q", ref) is not None


def drift(base: str, branches: Optional[List[str]] = None, exclude: Optional[List[str]] = None,
          cwd: Optional[Path] = None) -> Dict[str, List[str]]:
    """``{branch: ["<sha> <subject>", ...]}`` for each checked branch holding local-only commits."""
    where = cwd or ROOT
    if not _exists(where, "refs/remotes/origin/%s" % base):
        return {}
    skip = set(exclude or [])
    names = [base] + list(branches or [])
    tracking = _git(where, "config", "--get-regexp", r"^branch\..*\.merge$") or ""
    for line in tracking.splitlines():
        key, _, value = line.partition(" ")
        name = key[len("branch."):-len(".merge")]
        if value.strip() == "refs/heads/%s" % base and not name.startswith(LANE_PREFIXES):
            names.append(name)
    found: Dict[str, List[str]] = {}
    for name in names:
        if name in found or (name in skip and name != base) or not _exists(where, "refs/heads/%s" % name):
            continue
        if name == base:
            args = ["log", "--format=%h %s", "refs/remotes/origin/%s..refs/heads/%s" % (base, name)]
        else:
            args = ["log", "--format=%h %s", "refs/heads/%s" % name, "--not", "--remotes=origin"]
        log = _git(where, *args)
        if log and log.strip():
            found[name] = log.strip().splitlines()
    return found


def report(base: str, branches: Optional[List[str]] = None, exclude: Optional[List[str]] = None,
           cwd: Optional[Path] = None) -> int:
    """Print the drift; ``DRIFT_EXIT`` when there is any, else 0."""
    found = drift(base, branches, exclude, cwd)
    for name, commits in found.items():
        print("%s has %d local-only commit(s) not on origin:" % (name, len(commits)))
        for commit in commits:
            print("  " + commit)
    if found:
        print("Never merge, cherry-pick or commit onto a local copy of the workflow base; land through "
              "pr_land.sh or lane_land.py (pr-lifecycle.md). Rescue these on a lane branch before aligning the base.")
        return DRIFT_EXIT
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--base", default=None, help="workflow base (default: workflow_base in the triage config)")
    parser.add_argument("--branch", action="append", default=[])
    parser.add_argument("--exclude", action="append", default=[])
    args = parser.parse_args(argv)
    return report(args.base or workflow_base(), args.branch, args.exclude)


if __name__ == "__main__":
    sys.exit(main())
