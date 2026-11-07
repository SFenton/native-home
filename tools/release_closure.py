#!/usr/bin/env python3
"""The files the release pipeline runs or loads, derived from the workflow steps (owner kept set, 2026-11-07).

The ``ios-release*`` workflows run with the App Store Connect key in reach, so everything their steps execute or import stays
owner-only on every landing route (:data:`lane_land.DEFAULT_PROTECTED`, enforced by both ``lane_land`` and ``pr_land``). This module
derives that list instead of keeping it by hand:

* **starts**: every path under ``tools/`` or ``.github/actions/`` named on a non-comment line of ``.github/workflows/ios-release*.yml``;
* **closure**: for a shell script, the ``tools/...`` paths on its non-comment lines; for a Python file, the repository modules it
  imports and the script names in its string constants (docstrings excluded), so a launcher such as
  ``subprocess.run(["python3", "tools/devcap.py"])`` or ``HERE.with_name("devcap.py")`` is followed.

``python3 tools/release_closure.py [--root DIR]`` prints the files, one per line. Standard library only.
"""

from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path
from typing import Iterable, List, Optional, Set

#: Where a bare module or script name is looked for, after the file's own folder.
SEARCH = ("tools", "tools/release", "tools/hooks", "tools/review", "tools/triage")
TOOL_PATH = re.compile(r"(?<![\w.-])((?:tools|\.github/actions)/[A-Za-z0-9_./-]*[A-Za-z0-9_])")
SCRIPT_NAME = re.compile(r"[A-Za-z0-9_./-]*[A-Za-z0-9_]\.(?:py|sh)\b")


def _code_lines(text: str) -> str:
    """The text without comment-only lines (a comment names a file without running it)."""
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


def _existing(root: Path, rel: str) -> Optional[Path]:
    """``rel`` under ``root`` when it is a file inside the repository (case exact)."""
    candidate = root / rel
    try:
        resolved = candidate.resolve()
        resolved.relative_to(root.resolve())
    except (OSError, ValueError):
        return None
    if candidate.is_file() and candidate.name in {p.name for p in candidate.parent.iterdir()}:
        return resolved
    return None


def _shell_refs(root: Path, text: str) -> Set[Path]:
    found = set()
    for match in TOOL_PATH.finditer(_code_lines(text)):
        path = _existing(root, match.group(1))
        if path:
            found.add(path)
    return found


def _python_refs(root: Path, path: Path) -> Set[Path]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    docstrings = {id(n.body[0].value) for n in ast.walk(tree)
                  if isinstance(n, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n.body
                  and isinstance(n.body[0], ast.Expr) and isinstance(getattr(n.body[0], "value", None), ast.Constant)}
    names: Set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(a.name.split(".")[0] + ".py" for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            names.add(node.module.split(".")[0] + ".py")
            names.update(a.name + ".py" for a in node.names)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str) and id(node) not in docstrings:
            if len(node.value) < 200:  # a longer string is a message, not a path or a command
                names.update(SCRIPT_NAME.findall(node.value))
                names.update(m for m in TOOL_PATH.findall(node.value) if m.endswith((".py", ".sh")))
    found = set()
    for name in names:
        for base in (path.parent, *(root / d for d in SEARCH), root):
            try:
                rel = (base / name).resolve().relative_to(root.resolve()).as_posix()
            except ValueError:
                continue
            hit = _existing(root, rel)
            if hit:
                found.add(hit)
                break
    return found


def workflow_starts(root: Path) -> Set[Path]:
    """Files named by the code lines of the ``ios-release*`` workflows."""
    found: Set[Path] = set()
    for workflow in sorted((root / ".github" / "workflows").glob("ios-release*.yml")):
        found |= _shell_refs(root, workflow.read_text(encoding="utf-8"))
    return found


def closure(root: Path, starts: Iterable[Path]) -> List[str]:
    """Repo-relative paths of ``starts`` and everything they run or load, sorted."""
    seen: Set[Path] = set()
    todo = [Path(s).resolve() for s in starts]
    while todo:
        path = todo.pop()
        if path in seen or not path.is_file():
            continue
        seen.add(path)
        text = path.read_text(encoding="utf-8", errors="replace")
        if path.suffix == ".py":
            try:
                todo.extend(_python_refs(root, path))
            except (SyntaxError, ValueError):
                pass
        elif path.suffix == ".sh":
            todo.extend(_shell_refs(root, text))
    return sorted(p.relative_to(root.resolve()).as_posix() for p in seen)


def release_files(root: Path) -> List[str]:
    """Everything the ``ios-release*`` jobs execute or import, derived from their workflow steps."""
    return closure(root, workflow_starts(root))


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="List the files the release workflows run or import.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    args = parser.parse_args(argv)
    print("\n".join(release_files(Path(args.root))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
