#!/usr/bin/env python3
"""Fail the CI tool-test step only on failures that are new versus the PR's base commit (owner, 2026-11-04).

Runs ``tools/run_tool_tests.sh`` on this checkout. When it fails, the same script runs in a temporary ``git worktree`` of
``--base`` and the failing test ids of the two runs are compared. Failures already present on the base are listed and
ignored; any other failure exits 1. An infrastructure error (the base cannot be checked out, or its run fails without
reporting a single failing id) also exits 1, so a broken comparison is never green. Failing ids are parsed by the lane
lander's ``failing_ids``, the same parser it uses for its own base comparison.

Usage: ``python3 tools/ci_new_failures.py --base <sha> [--part core|triage|release]``  (a part runs one slice of the suite on both sides; the
hosted workflows run one job per part)
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, List, Optional, Sequence, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lane_land import failing_ids  # noqa: E402  (shared unittest-output parser)

ROOT = Path(__file__).resolve().parent.parent
TEST_SCRIPT = "tools/run_tool_tests.sh"

Runner = Callable[[Path], Tuple[int, str]]


def run_script(tree: Path, part: Optional[str] = None) -> Tuple[int, str]:
    """Run the tool tests (one ``part`` of them when given) in ``tree``, echo the output to stdout and return ``(exit code, output)``."""
    proc = subprocess.run(["bash", str(tree / TEST_SCRIPT), *([part] if part else [])], cwd=tree, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, errors="replace")
    sys.stdout.write(proc.stdout)
    sys.stdout.flush()
    return proc.returncode, proc.stdout


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(ROOT), *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def base_failures(base: str, runner: Runner) -> Optional[List[str]]:
    """Failing ids of the tool tests at ``base`` in a temporary worktree, always removed; ``None`` when the base run is unusable."""
    with tempfile.TemporaryDirectory(prefix="ci-base-") as tmp:
        tree = Path(tmp) / "base"
        added = _git("worktree", "add", "--detach", str(tree), base)
        if added.returncode != 0:
            print(f"ci_new_failures: cannot check out base {base}: {added.stdout.strip()}", file=sys.stderr)
            return None
        try:
            code, output = runner(tree)
        finally:
            _git("worktree", "remove", "--force", str(tree))
            _git("worktree", "prune")
    ids = failing_ids(output)
    if code != 0 and not ids:
        print(f"ci_new_failures: the base run failed (exit {code}) without reporting a failing test", file=sys.stderr)
        return None
    return ids


def compare(current: Sequence[str], base: Sequence[str]) -> Tuple[List[str], List[str], List[str]]:
    """``(new, existing, fixed)`` from the failing ids of this checkout and of the base."""
    cur, old = set(current), set(base)
    return sorted(cur - old), sorted(cur & old), sorted(old - cur)


def main(argv: Optional[Sequence[str]] = None, runner: Optional[Runner] = None) -> int:
    """Entry point; ``runner`` is the test runner (stubbed in tests). Returns the process exit code."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", required=True, help="the PR base commit (sha or ref)")
    parser.add_argument("--part", choices=("core", "triage", "release"), help="run one part of tools/run_tool_tests.sh on both sides")
    args = parser.parse_args(argv)
    if runner is None:  # looked up at call time so tests can replace run_script
        runner = lambda tree: run_script(tree, args.part)  # noqa: E731
    code, output = runner(ROOT)
    if code == 0:
        return 0
    current = failing_ids(output)
    if not current:
        print(f"ci_new_failures: the tool tests failed (exit {code}) without reporting a failing test", file=sys.stderr)
        return 1
    base = base_failures(args.base, runner)
    if base is None:
        return 1
    new, existing, fixed = compare(current, base)
    for title, ids in (("new:", new), ("existing (ignored, owner 2026-11-04):", existing), ("fixed:", fixed)):
        print(title)
        for item in ids:
            print(f"  {item}")
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())
