#!/usr/bin/env python3
"""Check the pattern registry and enforce its guard rules.

The registry (`contracts/patterns.json`, prose in `.agents/patterns/<id>.md`) names, per behavior pattern, the
canonical component, the files the pattern owns, and regex guards that keep new code from growing a parallel
implementation outside it. Ported from FestivalNativeApps' `tools/pattern_guard.py`, Apple paths only.

Commands::

    python3 tools/pattern_guard.py                 # check (default): registry, ownership and guards; exit 1 on errors
    python3 tools/pattern_guard.py index           # compact Markdown index (for prompts and agents)
    python3 tools/pattern_guard.py index --json    # the same as JSON
    python3 tools/pattern_guard.py which PATH...   # patterns that own each path (or why it is internal)
    python3 tools/pattern_guard.py changed --base origin/main [--head HEAD] [--strict]
                                                   # patterns touched by a diff and whether their
                                                   # doc or contract was updated

Standard library only, so it runs in CI and on every agent host.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable

# MARK: - Configuration

ROOT = Path(__file__).resolve().parents[1]
STATUSES = frozenset({"current", "proposed", "superseded"})
ID = re.compile(r"^[a-z][a-z0-9-]*$")
#: Lines that are only comments are never guard violations (docs may name banned APIs).
COMMENT = re.compile(r"^\s*(//|/\*|\*|#|<!--)")
SKIP_DIRS = frozenset({".git", "build", ".build", "DerivedData", "node_modules", ".swiftpm"})
REGISTRY = "contracts/patterns.json"


# MARK: - Model

@dataclass
class Report:
    """Findings from one check run."""

    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def load(root: Path = ROOT) -> dict[str, Any]:
    """Read the registry.

    Args:
        root: Repository root.

    Returns:
        The parsed `contracts/patterns.json`.
    """
    return json.loads((root / REGISTRY).read_text(encoding="utf-8"))


@lru_cache(maxsize=None)
def glob_regex(pattern: str) -> re.Pattern[str]:
    """Translate a repo glob (`**`, `*`, `?`) to an anchored regex over `/` paths.

    Args:
        pattern: Glob relative to the repository root.

    Returns:
        Compiled regex matching whole relative paths.
    """
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def matches(path: str, patterns: Iterable[str]) -> bool:
    """Whether `path` matches any glob in `patterns`."""
    return any(glob_regex(p).match(path) for p in patterns)


def source_files(root: Path, glob: str) -> list[str]:
    """Repo-relative files matching `glob`, skipping build output.

    Args:
        root: Repository root.
        glob: Repo glob, e.g. `apple/Sources/**/*.swift`.

    Returns:
        Sorted relative paths.
    """
    if not glob:
        return []
    prefix = glob.split("*", 1)[0].rsplit("/", 1)[0] if "*" in glob else glob
    base = root / prefix
    if base.is_file():
        return [prefix] if glob_regex(glob).match(prefix) else []
    found = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            rel = os.path.relpath(os.path.join(dirpath, name), root).replace(os.sep, "/")
            if glob_regex(glob).match(rel):
                found.append(rel)
    return sorted(found)


def scope_files(data: dict[str, Any], root: Path = ROOT) -> list[str]:
    """Every file the component index and the ownership check cover (`componentScopes`)."""
    files: set[str] = set()
    for glob in data.get("componentScopes") or []:
        files.update(source_files(root, glob))
    return sorted(files)


# MARK: - Ownership

def canonical_paths(pattern: dict[str, Any]) -> list[str]:
    """The canonical component files of one pattern."""
    return [ref["path"] for ref in (pattern.get("canonical") or {}).get("apple") or []]


def owners(data: dict[str, Any], path: str) -> list[tuple[str, str]]:
    """Patterns that own (canonical or `owns`) or guard `path`.

    Returns:
        (pattern id, role) pairs; role is `canonical`, `owns` or `guarded`.
    """
    found: list[tuple[str, str]] = []
    for p in data.get("patterns") or []:
        if path in canonical_paths(p):
            found.append((p["id"], "canonical"))
        elif matches(path, p.get("owns") or []):
            found.append((p["id"], "owns"))
        elif any(glob_regex(g.get("glob", "")).match(path) for g in p.get("guards") or []):
            found.append((p["id"], "guarded"))
    return found


def internal_reason(data: dict[str, Any], path: str) -> str | None:
    """The reason `path` is marked internal in the registry, or None."""
    for entry in data.get("internal") or []:
        if glob_regex(entry.get("glob", "")).match(path):
            return str(entry.get("reason", ""))
    return None


def owning_pattern(data: dict[str, Any], path: str) -> str | None:
    """The single pattern that owns `path` (canonical or `owns`), or None."""
    own = [pid for pid, role in owners(data, path) if role in ("canonical", "owns")]
    return own[0] if own else None


# MARK: - Check

def _validate_entry(pattern: dict[str, Any], root: Path, ids: set[str], report: Report) -> None:
    pid = pattern.get("id", "?")
    where = f"pattern {pid}"
    for key in ("id", "title", "status", "doc", "summary", "canonical", "keywords"):
        if not pattern.get(key):
            report.errors.append(f"{where}: missing `{key}`")
    if not ID.match(str(pid)):
        report.errors.append(f"{where}: id must be kebab-case")
    if pattern.get("status") not in STATUSES:
        report.errors.append(f"{where}: status must be one of {sorted(STATUSES)}")
    doc = root / str(pattern.get("doc", ""))
    doc_text = doc.read_text(encoding="utf-8") if doc.is_file() else ""
    if not doc_text:
        report.errors.append(f"{where}: doc `{pattern.get('doc')}` does not exist")
    canonical = pattern.get("canonical") or {}
    for platform in canonical:
        if platform != "apple":
            report.errors.append(f"{where}: unknown platform `{platform}` in canonical (only `apple`)")
    for ref in canonical.get("apple") or []:
        path = root / ref.get("path", "")
        if not path.is_file():
            report.errors.append(f"{where}: canonical path `{ref.get('path')}` does not exist")
        elif ref.get("symbol") and not re.search(rf"\b{re.escape(ref['symbol'])}\b",
                                                  path.read_text(encoding="utf-8", errors="replace")):
            report.errors.append(f"{where}: symbol `{ref['symbol']}` not found in `{ref['path']}`")
    for glob in pattern.get("owns") or []:
        if not source_files(root, glob):
            report.errors.append(f"{where}: owns glob `{glob}` matches no file")
    related = pattern.get("related") or {}
    for other in related.get("patterns") or []:
        if other not in ids:
            report.errors.append(f"{where}: related pattern `{other}` is not in the registry")
    for other in (pattern.get("supersedes") or []) + ([pattern["supersededBy"]] if pattern.get("supersededBy") else []):
        if other not in ids:
            report.errors.append(f"{where}: supersession target `{other}` is not in the registry")
    for guard in pattern.get("guards") or []:
        gid = f"{pid}/{guard.get('id', '?')}"
        if doc_text and gid not in doc_text:
            report.errors.append(f"{where}: doc must name guard `{gid}` under Guards")
        for rel in guard.get("debt") or {}:
            if doc_text and rel not in doc_text:
                report.errors.append(f"{where}: debt `{rel}` of guard `{gid}` must be listed in the doc's Known debt")


def facade_regex(facades: dict[str, list[str]]) -> str:
    """Alternation matching `Type.name` for every facade a guard names.

    Args:
        facades: Type name to the facade names it declares (`{"HomeConfig": ["cameras", ...]}`).

    Returns:
        A regex source string matching any `Type.name` as whole words.
    """
    return "|".join(rf"\b{re.escape(t)}\.(?:{'|'.join(re.escape(n) for n in sorted(set(names)))})\b"
                    for t, names in sorted(facades.items()) if names)


#: A statement that ends a line with an open bracket or continues on the next (`.map`, `??`, `+`) spans lines.
CONTINUATION = re.compile(r"^\s*(\.|\?\?|&&|\|\||\+|\?|:)")
STATEMENT_LINES = 80


def statements(lines: list[str], start: re.Pattern[str]) -> list[tuple[int, str]]:
    """Join each statement that begins with `start` into one line of text.

    A statement runs from its first line until its `(`, `[` and `{` balance and the next line does not continue it
    (a leading `.`, `??`, `&&`, `||`, `+`, `?` or `:`). Trailing `//` comments are dropped, so a facade named in a
    comment never counts. A comment-only line never starts a statement.

    Args:
        lines: The file's lines.
        start: Pattern a statement's first line matches.

    Returns:
        (1-based first line, joined text) for each statement.
    """
    found: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        if COMMENT.match(line) or not start.search(line):
            continue
        text, end = re.sub(r"\s//.*$", "", line), index
        while end + 1 < len(lines) and end - index < STATEMENT_LINES:
            balance = sum(text.count(o) - text.count(c) for o, c in ("()", "[]", "{}"))
            if balance <= 0 and not CONTINUATION.match(lines[end + 1]):
                break
            end += 1
            text += " " + re.sub(r"\s//.*$", "", lines[end]).strip()
        found.append((index + 1, text))
    return found


def run_guards(pattern: dict[str, Any], root: Path, report: Report,
               only: set[str] | None = None) -> list[tuple[str, str, int, str]]:
    """Apply a pattern's guards; violations outside `allow` and `debt` become errors.

    Args:
        pattern: One registry entry.
        root: Repository root.
        report: Findings sink.
        only: When given, scan only these repo-relative paths.

    Returns:
        Every match as (guard id, path, line number, kind) where kind is `error` or `debt`.
    """
    hits: list[tuple[str, str, int, str]] = []
    for guard in pattern.get("guards") or []:
        gid = f"{pattern['id']}/{guard.get('id', '?')}"
        try:
            shared = next((g for g in pattern.get("guards") or [] if g.get("id") == guard.get("facadesFrom")), {})
            facades = guard.get("facades") or shared.get("facades") or {}
            only_facade_files = re.compile(facade_regex(facades)) if guard.get("onlyFilesReadingFacades") else None
            source = "|".join(part for part in (guard.get("regex"), None if only_facade_files else facade_regex(facades)) if part)
            regex = re.compile(source if source else guard["regex"])
            statement = re.compile(guard["statement"]) if guard.get("statement") else None
        except (KeyError, re.error) as exc:
            report.errors.append(f"guard {gid}: invalid regex ({exc})")
            continue
        allow, debt = guard.get("allow") or [], guard.get("debt") or {}
        seen_debt: dict[str, int] = {}
        files = source_files(root, guard.get("glob", ""))
        if only is not None:
            files = [f for f in files if f in only]
        for rel in files:
            if matches(rel, allow):
                continue
            try:
                lines = (root / rel).read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            if only_facade_files is not None and not only_facade_files.search("\n".join(lines)):
                continue
            if statement is not None:
                candidates = [(n, t) for n, t in statements(lines, statement) if regex.search(t)]
            else:
                candidates = [(n, line) for n, line in enumerate(lines, 1) if not COMMENT.match(line) and regex.search(line)]
            for number, _ in candidates:
                if rel in debt and seen_debt.get(rel, 0) < int(debt[rel]):
                    seen_debt[rel] = seen_debt.get(rel, 0) + 1
                    hits.append((gid, rel, number, "debt"))
                else:
                    hits.append((gid, rel, number, "error"))
                    report.errors.append(f"{rel}:{number}: {gid}: {guard.get('message', 'pattern guard')}")
        if only is None:
            for rel, allowed in debt.items():
                if seen_debt.get(rel, 0) < int(allowed):
                    report.errors.append(f"guard {gid}: debt entry `{rel}` allows {allowed} hit(s) but has "
                                         f"{seen_debt.get(rel, 0)}; lower the count (remove the entry at 0) in `debt` "
                                         "and the doc's Known debt table")
        if seen_debt:
            report.warnings.append(f"guard {gid}: known debt in {len(seen_debt)} file(s)")
    return hits


def check(root: Path = ROOT) -> Report:
    """Validate the registry, the ownership of every component file, and run every guard.

    Args:
        root: Repository root.

    Returns:
        The findings.
    """
    report = Report()
    try:
        data = load(root)
    except (OSError, ValueError) as exc:
        report.errors.append(f"{REGISTRY}: {exc}")
        return report
    patterns = data.get("patterns") or []
    ids = [p.get("id") for p in patterns]
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        report.errors.append(f"duplicate pattern id `{dup}`")
    readme = root / ".agents" / "patterns" / "README.md"
    router = readme.read_text(encoding="utf-8") if readme.is_file() else ""
    for pattern in patterns:
        _validate_entry(pattern, root, set(ids), report)
        if router and f"({pattern.get('id')}.md)" not in router:
            report.errors.append(f"pattern {pattern.get('id')}: not listed in .agents/patterns/README.md")
        run_guards(pattern, root, report)
    docs = {p.get("doc") for p in patterns}
    for doc in sorted((root / ".agents" / "patterns").glob("*.md")):
        rel = doc.relative_to(root).as_posix()
        if doc.name != "README.md" and rel not in docs:
            report.errors.append(f"{rel}: pattern doc has no record in {REGISTRY}")
    for entry in data.get("internal") or []:
        if not entry.get("reason") or not source_files(root, entry.get("glob", "")):
            report.errors.append(f"internal entry `{entry.get('glob')}`: needs a reason and at least one file")
    docs_text = {p.get("id"): (root / str(p.get("doc", ""))).read_text(encoding="utf-8")
                 if (root / str(p.get("doc", ""))).is_file() else "" for p in patterns}
    for path in scope_files(data, root):
        owner = owning_pattern(data, path)
        stem = Path(path).stem
        if owner and not re.search(rf"\b{re.escape(stem)}\b", docs_text.get(owner, "")):
            report.errors.append(f"{path}: owned by {owner} but its doc never names `{stem}`; add it to the doc's "
                                 "Owned files line")
        own = {pid for pid, role in owners(data, path) if role in ("canonical", "owns")}
        internal = internal_reason(data, path)
        if len(own) > 1:
            report.errors.append(f"{path}: owned by several patterns ({', '.join(sorted(own))})")
        elif not own and internal is None:
            report.errors.append(f"{path}: owned by no pattern; add it to a pattern's `owns` or mark it `internal`")
        elif own and internal is not None:
            report.errors.append(f"{path}: both owned by {sorted(own)[0]} and internal")
    return report


# MARK: - Index / which / changed

def index(data: dict[str, Any], as_json: bool = False) -> str:
    """Compact index of current patterns for prompts.

    Args:
        data: Registry.
        as_json: Emit JSON instead of Markdown.

    Returns:
        The index text.
    """
    rows = []
    for p in data.get("patterns") or []:
        if p.get("status") == "superseded":
            continue
        canon = [r["path"].rsplit("/", 1)[-1] + (f" `{r['symbol']}`" if r.get("symbol") else "")
                 for r in (p.get("canonical") or {}).get("apple") or []]
        rows.append({"id": p["id"], "title": p.get("title", ""), "summary": p.get("summary", ""),
                     "doc": p.get("doc", ""), "keywords": p.get("keywords", []), "canonical": canon})
    if as_json:
        return json.dumps(rows, indent=2)
    out = ["| Pattern | Summary | Canonical |", "|---|---|---|"]
    for r in rows:
        out.append(f"| [{r['id']}]({r['doc']}) | {r['summary']} | {', '.join(r['canonical']) or '-'} |")
    return "\n".join(out)


def changed_report(data: dict[str, Any], files: list[str]) -> tuple[str, bool]:
    """Which patterns a change touches and whether their doc/contract moved with it.

    Args:
        data: Registry.
        files: Changed repo-relative paths.

    Returns:
        (Markdown summary, True when a pattern's file changed without its doc or the registry).
    """
    touched: dict[str, list[str]] = {}
    for f in files:
        for pid, role in owners(data, f):
            if role in ("canonical", "owns"):
                touched.setdefault(pid, []).append(f)
    changed = set(files)
    lines, missing = [], False
    for p in data.get("patterns") or []:
        if p["id"] not in touched:
            continue
        updated = p.get("doc") in changed or REGISTRY in changed
        missing |= not updated
        lines.append(f"- `{p['id']}` ({p.get('doc')}): files changed: "
                     + ", ".join(f"`{f}`" for f in touched[p["id"]])
                     + ("; pattern doc/contract updated" if updated
                        else "; **pattern doc/contract not updated**: confirm the rules still hold or update them"))
    if not lines:
        return "No pattern components changed.", False
    return "Patterns touched by this change:\n" + "\n".join(lines), missing


def diff_files(base: str, head: str, root: Path = ROOT) -> list[str]:
    """Changed paths between `base` and `head` (merge-base diff)."""
    out = subprocess.run(["git", "diff", "--name-only", f"{base}...{head}"], cwd=root, capture_output=True,
                         text=True, check=True)
    return [line.strip() for line in out.stdout.splitlines() if line.strip()]


# MARK: - CLI

def main(argv: list[str] | None = None) -> int:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", help="check this tree instead of the repository this file sits in (a change under review, judged by trusted code)")
    sub = parser.add_subparsers(dest="cmd")
    sub.add_parser("check", help="validate the registry and run guards (default)")
    p_index = sub.add_parser("index", help="print the pattern index")
    p_index.add_argument("--json", action="store_true")
    p_which = sub.add_parser("which", help="patterns owning or guarding paths")
    p_which.add_argument("paths", nargs="+")
    p_changed = sub.add_parser("changed", help="patterns touched by a diff")
    p_changed.add_argument("--base", default="origin/main")
    p_changed.add_argument("--head", default="HEAD")
    p_changed.add_argument("--files", nargs="*", help="explicit changed paths instead of git diff")
    p_changed.add_argument("--strict", action="store_true", help="exit 1 when a pattern's file changed without its doc")
    args = parser.parse_args(argv)

    if args.cmd in (None, "check"):
        report = check(Path(args.root).resolve() if args.root else ROOT)
        for w in report.warnings:
            print(f"warning: {w}")
        for e in report.errors:
            print(f"error: {e}")
        print(f"pattern_guard: {len(report.errors)} error(s), {len(report.warnings)} warning(s)")
        return 1 if report.errors else 0
    data = load()
    if args.cmd == "index":
        print(index(data, args.json))
        return 0
    if args.cmd == "which":
        for path in args.paths:
            rel = os.path.relpath(Path(path).resolve(), ROOT).replace(os.sep, "/") if Path(path).exists() else path
            found = [(pid, role) for pid, role in owners(data, rel) if role != "guarded"]
            internal = internal_reason(data, rel)
            print(f"{rel}: " + (", ".join(f"{pid} ({role})" for pid, role in found)
                                or (f"internal ({internal})" if internal else "no pattern")))
        return 0
    files = args.files if args.files is not None else diff_files(args.base, args.head)
    text, missing = changed_report(data, files)
    print(text)
    return 1 if (missing and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
