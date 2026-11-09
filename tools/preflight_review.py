#!/usr/bin/env python3
"""Advisory preflight review `tools/ship.sh` runs before it pushes (.agents/workflow/pr-lifecycle.md, "Preflight review").

Three checks on the diff `BASE...HEAD`, each the cause of a repeated second review round. All only warn; blocking
can be turned on once the false-positive rate on real PRs is zero.

1. **stale-doc-name**: a Swift declaration (type, func, property) of a non-test `apple/Sources` file, or a repo path,
   that the diff deletes or renames and a `.agents/**/*.md` file on the head still names (as `Type.member`, in
   backticks, or as a full path).
2. **facade-guard**: a new or changed non-private `static` member in `apple/Sources` that reads
   `HouseConfigSource.active.read` and is missing from the facade map of the `static-let-reads-house-facade` guard in
   `contracts/patterns.json` (loaded through `pattern_guard`, as `HouseFacadeGuardTests` does).
3. **fails-if**: a new test function with no `Fails if:` line in its doc comment or the PR note.

Usage: ``python3 tools/preflight_review.py [--base main] [--head HEAD] [--note-text TEXT]``.
Exit 0 always, except 2 on a git error.
"""

from __future__ import annotations

import argparse
import ast
import importlib.util
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import NamedTuple

TOOLS = Path(__file__).resolve().parent
GUARD_ID = "static-let-reads-house-facade"
READ_CALL = "HouseConfigSource.active.read"
MIN_SYMBOL = 6
MAX_SYMBOLS = 5000
SOURCES = "apple/Sources/"


@dataclass
class Finding:
    """One advisory preflight hit: which `check`, where, and what is wrong."""

    check: str
    where: str
    message: str

    def __str__(self) -> str:
        return f"warn [{self.check}] {self.where}: {self.message}"


@dataclass
class FileDiff:
    """What the diff does to one file: status, old path (renames), added line numbers, removed (old line, text)."""

    path: str
    status: str
    old_path: str | None = None
    added: set[int] = field(default_factory=set)
    removed: list[tuple[int, str]] = field(default_factory=list)


def git(root: Path, *args: str) -> str:
    """Run git in `root` and return stdout; raises `RuntimeError` on failure."""
    done = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    if done.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {done.stderr.strip()}")
    return done.stdout


def show(root: Path, rev: str, path: str) -> list[str] | None:
    """Lines of `path` at `rev`, or None when it does not exist there."""
    done = subprocess.run(["git", "-C", str(root), "show", f"{rev}:{path}"], capture_output=True, text=True,
                          errors="replace")
    return done.stdout.splitlines() if done.returncode == 0 else None


def parse_diff(name_status: str, patch: str) -> list[FileDiff]:
    """Combine `git diff --name-status -M` and `git diff -U0` output into per-file records.

    Args:
        name_status: Tab separated status lines (`D<TAB>old`, `R087<TAB>old<TAB>new`, `A<TAB>path`).
        patch: Unified zero-context diff of the same range.

    Returns:
        One `FileDiff` per path, keyed by its new path (the old path for a deletion).
    """
    files: dict[str, FileDiff] = {}
    for row in name_status.splitlines():
        cols = row.split("\t")
        if len(cols) < 2:
            continue
        status = cols[0][0]
        if status in "RC" and len(cols) >= 3:
            files[cols[2]] = FileDiff(cols[2], status, old_path=cols[1])
        else:
            files[cols[1]] = FileDiff(cols[1], status)
    current: FileDiff | None = None
    old_name = ""
    new_no = old_no = 0
    in_hunk = False
    for line in patch.splitlines():
        if line.startswith("diff --git"):
            current, old_name, in_hunk = None, "", False
        elif not in_hunk and line.startswith("--- "):
            old_name = line[4:].removeprefix("a/")
        elif not in_hunk and line.startswith("+++ "):
            new = line[4:].removeprefix("b/")
            current = files.get(old_name if new == "/dev/null" else new)
        elif line.startswith("@@"):
            in_hunk = True
            m = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)", line)
            old_no, new_no = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
        elif current is not None and line.startswith("+"):
            current.added.add(new_no)
            new_no += 1
        elif current is not None and line.startswith("-"):
            current.removed.append((old_no, line[1:]))
            old_no += 1
    return list(files.values())


# MARK: - Swift declaration scan

DECL = re.compile(
    r"^(?P<indent>[ \t]*)(?P<mods>(?:(?:public|internal|private|fileprivate|open|static|final|indirect|nonisolated|"
    r"override|mutating|lazy|weak|unowned|class(?=\s+(?:func|var|let)\b)|@\w+(?:\([^)]*\))?)\s+)*)"
    r"(?P<kind>func|var|let|struct|class|enum|protocol|actor|typealias|extension)\s+`?(?P<name>[A-Za-z_]\w*)")
TYPE_KINDS = {"struct", "class", "enum", "protocol", "actor", "extension"}
INDENT_STEP = 4


class Decl(NamedTuple):
    """A Swift declaration: 1-based line, indent width, keyword, name, modifiers, innermost enclosing type, and
    whether it is a type member (not a local variable of a function body)."""

    line: int
    indent: int
    kind: str
    name: str
    mods: str
    owner: str
    member: bool


def scan_decls(lines: list[str]) -> list[Decl]:
    """Every declaration of a Swift file, with its innermost enclosing type.

    The type stack is popped by indentation before each declaration, so a member that follows a nested type at the
    outer indent belongs to the outer type. A `func`/`var`/`let` deeper than one step inside its type (or any
    indent at file scope) is a local, flagged `member=False`.
    """
    out: list[Decl] = []
    stack: list[tuple[int, str]] = []
    for number, line in enumerate(lines, 1):
        m = DECL.match(line)
        if not m or line.lstrip().startswith(("//", "*", "/*")):
            continue
        indent = len(m.group("indent").expandtabs(INDENT_STEP))
        stack = [(i, n) for i, n in stack if i < indent]
        kind, name = m.group("kind"), m.group("name")
        owner = stack[-1][1] if stack else ""
        base = stack[-1][0] if stack else -INDENT_STEP
        member = kind in TYPE_KINDS or indent <= base + INDENT_STEP
        out.append(Decl(number, indent, kind, name, m.group("mods"), owner, member))
        if kind in TYPE_KINDS:
            stack.append((indent, name))
    return out


# MARK: - Check 1: stale doc names

DECLARED_ON_HEAD = r"(func|var|let|struct|class|enum|protocol|actor|typealias)[[:space:]]+`?[A-Za-z_][A-Za-z0-9_]*"


def declared_on_head(root: Path, head: str) -> set[str]:
    """Every name declared by a Swift `func`, `var`, `let` or type in `apple/` at `head` (one `git grep`)."""
    done = subprocess.run(["git", "-C", str(root), "grep", "-hoE", DECLARED_ON_HEAD, head, "--", "apple"],
                          capture_output=True, text=True, errors="replace")
    return {re.split(r"\s+", line.strip(), maxsplit=1)[1].strip("`") for line in done.stdout.splitlines()
            if " " in line.strip()}


def still_declared(name: str, declared: set[str]) -> bool:
    """True when the head still declares `name` somewhere in `apple/` (whole name, not a prefix of another)."""
    return name in declared


def removed_symbols(root: Path, base_rev: str, diffs: list[FileDiff], declared: set[str]) -> list[tuple[str, str]]:
    """Removed type-level declarations of non-test `apple/Sources` files that the head no longer declares.

    A removed line counts when the base file declares a type, or a func/var/let one step inside its type (not a
    local), at that line. Filtering happens before the cap.

    Returns:
        Sorted (owner type, name) pairs, at most `MAX_SYMBOLS`; owner is "" for a top-level name.
    """
    found: set[tuple[str, str]] = set()
    for item in diffs:
        old = item.old_path or item.path
        if not old.startswith(SOURCES) or not old.endswith(".swift") or not item.removed:
            continue
        lines = show(root, base_rev, old)
        if lines is None:
            continue
        at = {d.line: d for d in scan_decls(lines)}
        for number, _ in item.removed:
            decl = at.get(number)
            if not decl or not decl.member or decl.kind in {"extension", "typealias"}:
                continue
            if len(decl.name) < MIN_SYMBOL and not decl.owner:
                continue
            if not still_declared(decl.name, declared):
                found.add((decl.owner if decl.kind not in TYPE_KINDS else "", decl.name))
    return sorted(found)[:MAX_SYMBOLS]


def removed_paths(diffs: list[FileDiff]) -> set[str]:
    """Repo paths the diff deletes, or renames away from."""
    return {item.path if item.status == "D" else item.old_path for item in diffs
            if item.status == "D" or (item.status == "R" and item.old_path)}


def code_like(name: str) -> bool:
    """A bare name specific enough to look for in a code span: `MIN_SYMBOL`+ characters and not a plain lowercase word."""
    return len(name) >= MIN_SYMBOL and name != name.lower()


def doc_needles(symbols: list[tuple[str, str]], paths: set[str]) -> list[tuple[re.Pattern[str], str, bool]]:
    """(pattern, label, code spans only) for a code-like doc mention.

    A full path or `Owner.name` matches anywhere on a line; a bare camelCase or type name matches only inside a
    backtick code span.
    """
    needles = [(re.compile(re.escape(p)), f"path {p}", False) for p in sorted(paths)]
    for owner, name in symbols:
        if owner:
            needles.append((re.compile(rf"(?<!\w){re.escape(owner)}\.{re.escape(name)}\b"), f"symbol {owner}.{name}", False))
        if code_like(name):
            needles.append((re.compile(rf"(?<![\w.]){re.escape(name)}\b"), f"symbol {name}", True))
    return needles


def stale_doc_names(root: Path, head: str, symbols: list[tuple[str, str]], paths: set[str]) -> list[Finding]:
    """`.agents/**/*.md` lines (outside `.agents/archive/`) at `head` that code-mention a removed symbol or path."""
    needles = doc_needles(symbols, paths)
    if not needles:
        return []
    done = subprocess.run(["git", "-C", str(root), "grep", "-In", "", head, "--", ".agents/*.md"],
                          capture_output=True, text=True, errors="replace")
    quick = re.compile(r"(?<!\w)(?:" + "|".join(re.escape(n) for n in sorted({n for _, n in symbols} | set(paths)))
                       + r")(?!\w)")
    found: list[Finding] = []
    for row in done.stdout.splitlines():
        parts = row.split(":", 3)
        if len(parts) < 4 or parts[1].startswith(".agents/archive/") or not quick.search(parts[3]):
            continue
        spans = " ".join(re.findall(r"`([^`\n]+)`", parts[3]))
        for pattern, label, spans_only in needles:
            if pattern.search(spans if spans_only else parts[3]):
                found.append(Finding("stale-doc-name", f"{parts[1]}:{parts[2]}",
                                     f"still names {label}, which this diff deletes or renames"))
    return found


# MARK: - Check 2: facade guard entries

def load_facades(root: Path) -> dict[str, list[str]]:
    """The facade map of the `static-let-reads-house-facade` guard (empty when the repo has none)."""
    spec = importlib.util.spec_from_file_location("pattern_guard", TOOLS / "pattern_guard.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("pattern_guard", module)
    spec.loader.exec_module(module)
    for pattern in module.load(root).get("patterns", []):
        for entry in pattern.get("guards", []):
            if entry.get("id") == GUARD_ID:
                return entry.get("facades", {})
    return {}


def facade_members(lines: list[str]) -> list[tuple[int, str, str, str]]:
    """Non-private `static` members of a Swift file that read the house document.

    A member counts when its span (its line up to the next declaration at its indent or less) calls
    `HouseConfigSource.active.read` directly, or a file-local `read { ... }` helper. The `HouseConfigSource` type
    itself and members named `read` are the mechanism, not facades.

    Returns:
        (first line, enclosing type, member name, span text) per member, lines 1-based.
    """
    if READ_CALL not in "\n".join(lines):
        return []
    decls = scan_decls(lines)
    helper = any(d.kind == "func" and d.name == "read" for d in decls)
    out = []
    for position, decl in enumerate(decls):
        if (decl.kind not in {"func", "var", "let"} or not decl.member or "static" not in decl.mods
                or "private" in decl.mods or decl.owner in {"", "HouseConfigSource"} or decl.name == "read"):
            continue
        if decl.kind == "func" and not re.search(rf"func\s+{decl.name}\s*\(\s*\)", lines[decl.line - 1]):
            continue  # a function with parameters is not a facade value
        end = next((d.line for d in decls[position + 1:] if d.indent <= decl.indent), len(lines) + 1)
        span = "\n".join(lines[decl.line - 1:end - 1])
        if READ_CALL in span or (helper and re.search(r"(?<![\w.:])read\s*\{", span)):
            out.append((decl.line, decl.owner, decl.name, span))
    return out


def missing_facades(path: str, lines: list[str], added: set[int], facades: dict[str, list[str]]) -> list[Finding]:
    """Findings for each changed facade member of `path` that the guard map does not list."""
    found = []
    for first, owner, name, span in facade_members(lines):
        last = first + span.count("\n")
        if any(first <= n <= last for n in added) and name not in facades.get(owner, []):
            found.append(Finding("facade-guard", f"{path}:{first}",
                                 f"{owner}.{name} reads the house document but is not in the {GUARD_ID} "
                                 f"facade map of contracts/patterns.json"))
    return found


# MARK: - Check 3: tests that can fail

SWIFT_TEST = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+)?func\s+(test\w*)\s*\(")
PY_TEST = re.compile(r"^\s*(?:async\s+)?def\s+(test\w*)\s*\(")
FAILS_IF = re.compile(r"Fails if:", re.IGNORECASE)


def is_test_path(path: str) -> bool:
    """Swift tests under `apple/Tests`, Python tests under `tools/tests`."""
    return (path.startswith("apple/Tests/") and path.endswith(".swift")) or \
        (path.startswith("tools/tests/") and path.endswith(".py"))


def comments_above(lines: list[str], index: int) -> str:
    """The contiguous comment and attribute lines (`///`, `//`, `#`, `@`) directly above `lines[index]`."""
    block: list[str] = []
    cursor = index - 1
    while cursor >= 0 and lines[cursor].strip().startswith(("///", "//", "@", "#")):
        block.append(lines[cursor])
        cursor -= 1
    return "\n".join(block)


def test_functions(path: str, lines: list[str]) -> list[tuple[int, str, str]]:
    """(1-based line, name, doc text) for each test function of a file.

    Python is parsed with `ast` (a `def test_x` inside a string literal is not a test), falling back to the regex
    when the file does not parse. Doc text is the comments above plus, for Python, the docstring.
    """
    if path.endswith(".py"):
        try:
            tree = ast.parse("\n".join(lines))
        except SyntaxError:
            tree = None
        if tree is not None:
            return [(n.lineno, n.name, comments_above(lines, n.lineno - 1) + "\n" + (ast.get_docstring(n) or ""))
                    for n in ast.walk(tree)
                    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("test")]
        pattern = PY_TEST
    else:
        pattern = SWIFT_TEST
    return [(i + 1, m.group(1), comments_above(lines, i)) for i, line in enumerate(lines)
            if (m := pattern.match(line))]


def tests_without_fails_if(path: str, lines: list[str], added: set[int], note: str) -> list[Finding]:
    """Each test added in `path` with no `Fails if:` in its doc comment, and not named on a `Fails if` line of `note`."""
    note_lines = [n for n in note.splitlines() if FAILS_IF.search(n)]
    return [Finding("fails-if", f"{path}:{number}", f"{name} has no `Fails if:` line in its doc comment or the PR note")
            for number, name, doc in test_functions(path, lines)
            if number in added and not FAILS_IF.search(doc) and not any(name in n for n in note_lines)]


# MARK: - Driver

def resolve_base(root: Path, base: str) -> str:
    """`origin/<base>` when that ref exists, else `base` itself (a branch, tag or sha)."""
    done = subprocess.run(["git", "-C", str(root), "rev-parse", "-q", "--verify", f"origin/{base}"], capture_output=True)
    return f"origin/{base}" if done.returncode == 0 else base


def run(root: Path, base: str, note: str = "", head: str = "HEAD") -> list[Finding]:
    """All findings for the diff `base...head` in `root` (`base` as `resolve_base` reads it)."""
    ref = resolve_base(root, base)
    merge_base = git(root, "merge-base", ref, head).strip()
    name_status = git(root, "diff", "--name-status", "-M", f"{ref}...{head}")
    patch = git(root, "diff", "-U0", "--no-color", "-M", f"{ref}...{head}")
    diffs = parse_diff(name_status, patch)
    heads: dict[str, list[str]] = {}
    for item in diffs:
        if item.status != "D":
            lines = show(root, head, item.path)
            if lines is not None:
                heads[item.path] = lines
    findings: list[Finding] = []
    if any(item.removed or item.status in "DR" for item in diffs):
        symbols = removed_symbols(root, merge_base, diffs, declared_on_head(root, head))
        findings += stale_doc_names(root, head, symbols, removed_paths(diffs))
    registry = show(root, head, "contracts/patterns.json")
    facades = load_facades(root) if registry is not None else {}
    for item in diffs:
        lines = heads.get(item.path)
        if lines is None:
            continue
        if item.path.startswith(SOURCES) and item.path.endswith(".swift") and facades:
            findings += missing_facades(item.path, lines, item.added, facades)
        if is_test_path(item.path):
            findings += tests_without_fails_if(item.path, lines, item.added, note)
    return findings


def main(argv: list[str] | None = None) -> int:
    """CLI entry; prints one line per finding. Returns 0, or 2 on a git error."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default="main")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--note-text", default="", help="PR note or body; a `Fails if:` line naming a test covers it")
    args = parser.parse_args(argv)
    try:
        root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
        findings = run(root, args.base, args.note_text, args.head)
    except RuntimeError as err:
        print(f"preflight: {err}", file=sys.stderr)
        return 2
    for finding in findings:
        print(finding)
    print(f"preflight: {len(findings)} advisory finding(s)" if findings else "preflight: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
