#!/usr/bin/env python3
"""Validate a result-note proof manifest using files from one Git commit."""

from __future__ import annotations

import argparse
import ast
import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any, Dict, List, Optional, Sequence, Tuple

SHA = re.compile(r"^[0-9a-fA-F]{40}$")
HEADER_NAMES = {
    "control id",
    "test",
    "one-rule mutant",
    "sites",
    "earlier checks",
    "assertion that must fail",
    "status",
}
PIN = re.compile(r"^\s*manifest-head:\s*(.*?)\s*$", re.MULTILINE)
SEPARATOR = re.compile(r"^:?-{3,}:?$")


class UsageError(Exception):
    """A command-line or environment problem."""


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise UsageError(message)


def git(repo: Path, *arguments: str) -> subprocess.CompletedProcess:
    """Run one read-only Git command."""
    try:
        return subprocess.run(
            ["git", *arguments],
            cwd=str(repo),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise UsageError(f"cannot run git: {error}") from error


def resolve_repo(repo: Path) -> Path:
    result = git(repo, "rev-parse", "--show-toplevel")
    if result.returncode:
        raise UsageError("not a repository")
    try:
        return Path(result.stdout.decode("utf-8").strip()).resolve()
    except UnicodeDecodeError as error:
        raise UsageError("git returned a non-UTF-8 repository path") from error


def resolve_head(repo: Path, value: str) -> str:
    result = git(repo, "rev-parse", "--verify", "--quiet", value + "^{commit}")
    head = result.stdout.decode("utf-8", "replace").strip()
    if result.returncode or not SHA.fullmatch(head):
        raise UsageError(f"--head does not name a commit: {value}")
    return head.lower()


def safe_path(value: str) -> bool:
    if not value or value.startswith("-") or "\x00" in value:
        return False
    if value.startswith(("/", "\\")) or PurePosixPath(value).is_absolute():
        return False
    if PureWindowsPath(value).is_absolute() or PureWindowsPath(value).drive:
        return False
    return ".." not in re.split(r"[\\/]", value)


def read_blob(repo: Path, head: str, path: str) -> Optional[str]:
    """Return the UTF-8 blob at ``head:path``, or ``None`` when it is absent."""
    result = git(repo, "show", f"{head}:{path}")
    if result.returncode:
        return None
    try:
        return result.stdout.decode("utf-8")
    except UnicodeDecodeError:
        return None


def split_row(line: str) -> List[str]:
    """Split a Markdown table row and restore escaped literal pipes."""
    if not line.strip().startswith("|"):
        return []
    cells: List[str] = []
    current: List[str] = []
    text = line.strip()
    index = 1
    while index < len(text):
        if text[index] == "\\" and index + 1 < len(text) and text[index + 1] == "|":
            current.append("|")
            index += 2
            continue
        if text[index] == "|":
            cells.append("".join(current).strip())
            current = []
        else:
            current.append(text[index])
        index += 1
    if current or (text and not text.endswith("|")):
        cells.append("".join(current).strip())
    return cells


def is_separator(cells: Sequence[str]) -> bool:
    return bool(cells) and all(SEPARATOR.fullmatch(cell) for cell in cells)


def manifest_rows(note: str) -> List[Dict[str, str]]:
    lines = note.splitlines()
    rows: List[Dict[str, str]] = []
    index = 0
    while index + 1 < len(lines):
        header = split_row(lines[index])
        lower = [cell.strip().lower() for cell in header]
        if not HEADER_NAMES.issubset(lower) or not is_separator(split_row(lines[index + 1])):
            index += 1
            continue
        positions = {name: lower.index(name) for name in HEADER_NAMES}
        index += 2
        while index < len(lines):
            cells = split_row(lines[index])
            next_header = [cell.strip().lower() for cell in cells]
            if HEADER_NAMES.issubset(next_header):
                break
            if not cells:
                break
            rows.append({name: cells[position] if position < len(cells) else "" for name, position in positions.items()})
            index += 1
    return rows


def code_spans(cell: str) -> List[str]:
    spans: List[str] = []
    index = 0
    while index < len(cell):
        if cell[index] != "`":
            index += 1
            continue
        width = 2 if cell.startswith("``", index) else 1
        end_marker = "`" * width
        end = cell.find(end_marker, index + width)
        if end == -1:
            index += width
            continue
        spans.append(cell[index + width:end])
        index = end + width
    return spans


def pin_matches(note: str, head: str) -> bool:
    pins = PIN.findall(note)
    if len(pins) != 1:
        return False
    spans = code_spans(pins[0])
    value = spans[0] if len(spans) == 1 else pins[0]
    return bool(SHA.fullmatch(value.strip())) and value.strip().lower() == head.lower()


def parse_mutant(cell: str) -> Tuple[str, Optional[Dict[str, str]]]:
    spans = code_spans(cell)
    if len(spans) > 1:
        return "compound", None
    if len(spans) != 1:
        return "malformed one-rule mutant", None
    decoder = json.JSONDecoder()
    try:
        value, end = decoder.raw_decode(spans[0])
    except json.JSONDecodeError:
        return "malformed one-rule mutant", None
    tail = spans[0][end:].strip()
    if isinstance(value, list):
        return "compound", None
    if tail:
        try:
            extra, extra_end = decoder.raw_decode(tail)
            if isinstance(extra, dict) and not tail[extra_end:].strip():
                return "compound", None
        except json.JSONDecodeError:
            pass
        return "malformed one-rule mutant", None
    if not isinstance(value, dict) or set(value) != {"file", "find", "replace"}:
        return "malformed one-rule mutant", None
    if not all(isinstance(value[key], str) for key in ("file", "find", "replace")):
        return "malformed one-rule mutant", None
    if not safe_path(value["file"]):
        return "malformed one-rule mutant", None
    return "", value


def parse_test(cell: str) -> Tuple[Optional[str], Optional[Tuple[str, Optional[str], str]]]:
    spans = code_spans(cell)
    if len(spans) != 1:
        return None, None
    identifier = spans[0].strip()
    if identifier.count("::") != 1:
        return identifier, None
    path, leaf = identifier.split("::", 1)
    pieces = leaf.split(".")
    if len(pieces) == 1:
        class_name, method = None, pieces[0]
    elif len(pieces) == 2:
        class_name, method = pieces
    else:
        return identifier, None
    if not safe_path(path) or not method.isidentifier() or class_name is not None and not class_name.isidentifier():
        return identifier, None
    return identifier, (path, class_name, method)


def parse_assertion(cell: str) -> Optional[Tuple[str, int]]:
    spans = code_spans(cell)
    if len(spans) != 1 or spans[0].count(":") < 1:
        return None
    path, line_text = spans[0].strip().rsplit(":", 1)
    if not line_text.isdigit() or int(line_text) < 1 or not safe_path(path):
        return None
    return path, int(line_text)


def parsed(tree_source: Optional[str], name: str) -> Optional[ast.AST]:
    if tree_source is None:
        return None
    try:
        return ast.parse(tree_source, filename=name)
    except (SyntaxError, ValueError):
        return None


def has_test(tree: Optional[ast.AST], class_name: Optional[str], method: str) -> bool:
    if tree is None or not isinstance(tree, ast.Module):
        return False
    scopes: Sequence[ast.stmt] = tree.body
    if class_name is not None:
        classes = [node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == class_name]
        if not classes:
            return False
        return any(
            isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == method
            for cls in classes
            for node in cls.body
        )
    return any(isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == method for node in scopes)


def assertion_name(node: ast.Call) -> str:
    function = node.func
    if isinstance(function, ast.Name):
        return function.id
    if isinstance(function, ast.Attribute):
        return function.attr
    return ""


def is_assertion(tree: Optional[ast.AST], line: int) -> bool:
    if tree is None:
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Assert):
            if node.lineno <= line <= getattr(node, "end_lineno", node.lineno):
                return True
        elif isinstance(node, ast.Call):
            name = assertion_name(node)
            if (name.startswith("assert") or name == "fail") and node.lineno <= line <= getattr(node, "end_lineno", node.lineno):
                return True
    return False


def cached_blob(cache: Dict[str, Optional[str]], repo: Path, head: str, path: str) -> Optional[str]:
    if path not in cache:
        cache[path] = read_blob(repo, head, path)
    return cache[path]


def check(note: Path, repo: Path, head: str) -> Tuple[int, List[str]]:
    try:
        text = note.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise UsageError(f"cannot read note: {error}") from error
    rows = manifest_rows(text)
    if not rows:
        return 1, ["proof_check: no manifest"]
    head_ok = pin_matches(text, head)
    cache: Dict[str, Optional[str]] = {}
    output: List[str] = []
    failed = 0
    for index, row in enumerate(rows, 1):
        control = "".join(ch for ch in row["control id"].strip(" `") if ch != "\n") or f"row {index}"
        statuses: List[str] = []
        malformed: List[str] = []
        mutant_error, mutant = parse_mutant(row["one-rule mutant"])
        if mutant_error == "compound":
            compound = True
        else:
            compound = False
            if mutant_error:
                malformed.append(mutant_error)
        if mutant is not None:
            source = cached_blob(cache, repo, head, mutant["file"])
            if source is None:
                statuses.append("absent (no such file at head)")
            else:
                occurrences = source.count(mutant["find"])
                if occurrences == 0:
                    statuses.append("absent")
                elif occurrences > 1:
                    statuses.append(f"ambiguous {occurrences}")
                if mutant["replace"] == mutant["find"]:
                    statuses.append("identity")
                if occurrences and mutant["file"].endswith(".py"):
                    replaced = source.replace(mutant["find"], mutant["replace"], 1)
                    if parsed(replaced, mutant["file"]) is None:
                        statuses.append("unparseable")
        assertion = parse_assertion(row["assertion that must fail"])
        if assertion is None:
            malformed.append("malformed assertion")
        else:
            assertion_path, line = assertion
            tree = parsed(cached_blob(cache, repo, head, assertion_path), assertion_path) if assertion_path.endswith(".py") else None
            if not is_assertion(tree, line):
                statuses.append("not_assertion")
        identifier, test_parts = parse_test(row["test"])
        if test_parts is None:
            malformed.append("malformed test")
        else:
            test_path, class_name, method = test_parts
            test_tree = parsed(cached_blob(cache, repo, head, test_path), test_path) if test_path.endswith(".py") else None
            if not has_test(test_tree, class_name, method):
                statuses.append(f"leaf_missing {identifier}")
        if not head_ok:
            statuses.append("head_mismatch")
        if compound:
            statuses.append("compound")
        statuses.extend(malformed)
        if statuses:
            failed += 1
            output.append(f"{control}: {'; '.join(statuses)}")
        else:
            output.append(f"{control}: ok")
    output.append(f"proof_check: {len(rows)} rows, {failed} not ok")
    return (0 if failed == 0 else 1), output


def arguments(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = Parser(description=__doc__)
    parser.add_argument("note", type=Path)
    parser.add_argument("--head", required=True)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    try:
        args = arguments(argv)
        repo = resolve_repo(args.repo)
        head = resolve_head(repo, args.head)
        code, lines = check(args.note, repo, head)
    except UsageError as error:
        print(f"proof_check: {error}", file=sys.stderr)
        return 2
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
