#!/usr/bin/env python3
"""Fail when a branch adds a path under ``build/`` (the gitignored local workspace) against its base.

``build/`` is local and never committed (``.agents/workflow/security.md#house-data``). The hooks in ``tools/hooks/commit_guard.py`` refuse
the commit; this is the authoritative backstop in the ``pr-checks`` repo-checks job, since a commit made outside Claude skips the hooks.

    python3 tools/build_path_check.py [--base origin/main]

Lists ``git diff --name-only --diff-filter=A <base>...HEAD``; a deletion or a modification of a ``build/`` file already on the base
passes (the one-time cleanup removes them). Exit 0 clean, 1 with the offending files named, 2 when git cannot answer (never a silent pass).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from typing import List, Optional


def added_build_paths(base: str, cwd: str = ".") -> List[str]:
    """Paths under ``build/`` that ``<base>...HEAD`` adds. Raises ``RuntimeError`` when git fails."""
    done = subprocess.run(["git", "diff", "--name-only", "--no-renames", "--diff-filter=A", "-z", f"{base}...HEAD", "--"],
                          cwd=cwd, capture_output=True, text=True)
    if done.returncode != 0:
        raise RuntimeError(done.stderr.strip() or "git diff failed")
    return [name for name in done.stdout.split("\0") if name == "build" or name.startswith("build/")]


def main(argv: Optional[List[str]] = None) -> int:
    """Run the check; returns the exit code."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default="origin/main")
    args = parser.parse_args(argv)
    try:
        found = added_build_paths(args.base)
    except (RuntimeError, OSError) as error:
        print(f"build_path_check: cannot compare with {args.base}: {error}", file=sys.stderr)
        return 2
    if found:
        print(f"build_path_check: {len(found)} path(s) under build/ added against {args.base}; build/ is local and never committed "
              "(.agents/workflow/security.md#house-data). Remove them with `git rm --cached`:")
        for name in found:
            print(f"  {name}")
        return 1
    print(f"build_path_check: ok (no build/ path added against {args.base})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
