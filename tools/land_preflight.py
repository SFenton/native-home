#!/usr/bin/env python3
"""Read-only land preflight: can this PR go through the gated path (``tools/pr_land.sh``)?

The lander runs the gate from the *base's* copy of the tools, so a base without them fails closed at land time
(PR 308 found it that way). This reports the problem when the draft PR opens.

    tools/land_preflight.py --pr N
    tools/land_preflight.py --head H [--base main]

It fetches ``origin`` (unless ``--no-fetch``), checks that the base ref carries the gate files (``tools/jev_gate.py``
only when the change touches app-UI paths, by the path rule of ``tools/lane_land.py``), and reports commits ahead,
whether a review is recorded for the head and whether checks have reported. It never merges, edits or pushes.

Exit 0: the gated path can land. Exit 3: ``owner-only: <reason>`` plus the missing files. Exit 2: usage or git error.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

#: Files the gated path needs on the base ref, always.
GATE_FILES: Tuple[str, ...] = ("tools/lane_land.py", "tools/pr_land.py", "tools/pr_land.sh", "tools/triage/config.json")
#: Needed too when the PR touches app-UI paths.
APP_UI_GATE_FILE = "tools/jev_gate.py"
#: Heads further ahead than this get a warning: land gate-file changes in an early separate PR.
AHEAD_WARN = 50


def git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    """Run ``git`` in ``repo`` and capture text output."""
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)


def resolve(repo: Path, name: str) -> str:
    """``origin/<name>`` when it exists, else ``<name>``; empty when neither resolves."""
    for ref in (f"origin/{name}", name):
        if git(repo, "rev-parse", "--verify", "-q", ref + "^{commit}").returncode == 0:
            return ref
    return ""


def missing_on(repo: Path, ref: str, paths: Sequence[str]) -> List[str]:
    """The ``paths`` that ``ref`` does not contain."""
    return [p for p in paths if git(repo, "cat-file", "-e", f"{ref}:{p}").returncode != 0]


def touches_app_ui(rows: Sequence[Tuple[str, str, str, str]]) -> bool:
    """Whether any changed row is app UI, by ``lane_land``'s own rule (imported, never copied).

    If ``lane_land`` cannot be imported the answer is ``True`` so the stricter file set applies."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import lane_land  # type: ignore
        return bool(lane_land.app_ui_paths(rows))
    except Exception:
        return True
    finally:
        sys.path.pop(0)


def changed_rows(repo: Path, base: str, head: str) -> List[Tuple[str, str, str, str]]:
    """``(status, path, old, new)`` rows of ``base...head``, the shape ``lane_land.app_ui_paths`` takes."""
    out = git(repo, "diff", "--name-status", "--no-renames", f"{base}...{head}").stdout
    rows = []
    for line in out.splitlines():
        status, _, path = line.partition("\t")
        if path:
            rows.append((status[:1], path, path, path))
    return rows


def review_name(branch: str) -> str:
    """``build/review/`` file name for a branch, as ``tools/pr_land.py`` names it."""
    return branch.replace("/", "__") + ".json"


def pr_info(number: str) -> Dict[str, Any]:
    """Head ref, base ref and check rollup of a PR from ``gh`` (read-only)."""
    proc = subprocess.run(["gh", "pr", "view", number, "--json", "headRefName,baseRefName,statusCheckRollup"],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"land_preflight: gh pr view {number} failed: {proc.stderr.strip()[:200]}")
    return json.loads(proc.stdout)


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pr", help="PR number (head, base and checks come from gh)")
    ap.add_argument("--head", help="head branch (without --pr)")
    ap.add_argument("--base", help="base branch (default main)")
    ap.add_argument("--repo", default=".", help="checkout to inspect (default: current directory)")
    ap.add_argument("--no-fetch", action="store_true", help="do not fetch origin first")
    args = ap.parse_args(argv)
    repo = Path(args.repo).resolve()
    checks: Optional[List[Dict[str, Any]]] = None
    if args.pr:
        info = pr_info(args.pr)
        head, base, checks = info["headRefName"], info["baseRefName"], info.get("statusCheckRollup") or []
    elif args.head:
        head, base = args.head, args.base or "main"
    else:
        ap.error("give --pr N or --head H")
    if not args.no_fetch and git(repo, "fetch", "-q", "origin").returncode != 0:
        print("land_preflight: warning, git fetch origin failed; using local refs", file=sys.stderr)
    base_ref, head_ref = resolve(repo, base), resolve(repo, head)
    if not base_ref or not head_ref:
        print(f"land_preflight: cannot resolve {'base ' + base if not base_ref else 'head ' + head}", file=sys.stderr)
        return 2

    ahead = int(git(repo, "rev-list", "--count", f"{base_ref}..{head_ref}").stdout.strip() or 0)
    print(f"base {base_ref}, head {head_ref}: {ahead} commit(s) ahead")
    if ahead > AHEAD_WARN:
        print(f"warning: head is {ahead} commits ahead (more than {AHEAD_WARN}); land gate-file changes on {base} "
              "in an early separate PR")
    ui = touches_app_ui(changed_rows(repo, base_ref, head_ref))
    needed = list(GATE_FILES) + ([APP_UI_GATE_FILE] if ui else [])
    print(f"app-UI paths touched: {'yes' if ui else 'no'}")
    review = repo / "build" / "review" / review_name(head)
    print(f"review recorded: {'yes' if review.is_file() else 'no'} ({review.relative_to(repo)})")
    if checks is None:
        print("checks reported: n/a (no --pr)")
    else:
        print(f"checks reported: {'yes' if checks else 'no'} ({len(checks)})")

    missing = missing_on(repo, base_ref, needed)
    if missing:
        print(f"owner-only: {base} lacks gate files the gated path runs from the base")
        for path in missing:
            print(f"  missing on {base_ref}: {path}")
        return 3
    print(f"ok: {base_ref} carries the gate files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
