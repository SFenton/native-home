#!/usr/bin/env python3
"""Decides which compile checks a pull request needs (pr-checks `scope` job).

    ci_scope.py --base SHA [--head HEAD]     prints `app=…`, `release=…` and `scope=docs|tools|app`

Three classes, by an allowlist:

* ``docs``: only documentation-like paths (Markdown anywhere, `.agents/`, `.claude/`, the PR template).
* ``tools``: docs plus Python tooling: `tools/` (except `tools/push_fixtures/`, which Swift tests read), `contracts/test-map*`, `contracts/test-suites*`,
  `docs/`. The Python tool tests and the repo checks run; no Swift compiles (`app=false`).
* ``app``: everything else (`apple/`, other `contracts/`, workflows, the Makefile). `swift test` runs (`app=true`).

`release=true` (the Release build) only when `apple/` changes. An empty or unreadable diff runs everything. No shell
pipe is involved, so a long file list cannot fail on SIGPIPE. Stdlib only (macOS system Python 3.9).
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from typing import Iterable, List, Optional

#: Paths that never reach the build or a test: Markdown anywhere, the agent docs and mockups, the PR template, agent settings.
DOCS_ONLY = re.compile(r"^(?:.*\.md|\.agents/.*|\.claude/.*|\.github/pull_request_template\.md)$")
#: Python tooling and its data: the tool tests cover it, no Swift test reads it (`tools/push_fixtures/` is read by one, so it is out).
TOOLS_ONLY = re.compile(r"^(?:tools/(?!push_fixtures/).*|contracts/test-(?:map|suites)[^/]*|docs/.*)$")
APPLE = re.compile(r"^apple/")


def scope(files: Iterable[str]) -> str:
    """``docs``, ``tools`` or ``app`` for a changed-file list (an empty list is ``app``)."""
    names: List[str] = [f for f in files if f]
    if not names:
        return "app"
    if all(DOCS_ONLY.match(name) for name in names):
        return "docs"
    if all(DOCS_ONLY.match(name) or TOOLS_ONLY.match(name) for name in names):
        return "tools"
    return "app"


def needs_compile(files: Iterable[str]) -> bool:
    """Does `swift test` need to run?"""
    return scope(files) == "app"


def needs_release(files: Iterable[str]) -> bool:
    """Does the Release build need to run? Only when `apple/` changes (or the diff is unknown)."""
    names: List[str] = [f for f in files if f]
    return not names or any(APPLE.match(name) for name in names)


def changed_files(base: str, head: str) -> Optional[List[str]]:
    proc = subprocess.run(["git", "diff", "--name-only", base, head], capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    return proc.stdout.splitlines()


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    args = parser.parse_args(argv)
    files = changed_files(args.base, args.head)
    known = files if files is not None else []
    print("app=%s" % ("true" if needs_compile(known) else "false"))
    print("release=%s" % ("true" if needs_release(known) else "false"))
    print("scope=%s" % scope(known))
    return 0


if __name__ == "__main__":
    sys.exit(main())
