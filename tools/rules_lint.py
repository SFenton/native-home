#!/usr/bin/env python3
"""rules_lint: keeps the rule surface (AGENTS.md, the workflow rules, agent files, prompts, skills, reference docs) clean.

    tools/rules_lint.py [--paths P ...] [--base REF] [--report] [--write-ratchet] [--stdin-path PATH] [--root DIR]

Every number, glob and forbidden pattern is data in ``contracts/rules-surface.json``; this module only applies it. A rule is a
present-tense default: no date, no attribution, no PR or commit reference, no words of change, no status. What is not a rule has
another home (the refusal message names it): a decision record, the PR description, ``PROGRESS.md``, a tool's config or ``--help``.

Checks (each a function with a stable id): ``forbidden``, ``budget``, ``role_load``, ``one_home``, ``links``, ``structure``,
``decisions``, and ``ratchet`` for layers that carry one. There is **no inline ignore comment and no per-line allow-list**;
exemptions exist only by layer, in the contract, and the contract is owner-protected.

Output: ``path:line: [check] message -> home`` per finding and a summary; exit 1 when there is any finding. ``--stdin-path``
lints text from stdin as if it were that file (the write-time hook uses :func:`hit_counts`). ``--report`` prints words per layer and
the per-role spawn load as JSON. ``--base REF`` also checks that existing decision files were not edited (append-only).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, NamedTuple, Optional, Set, Tuple

REPO = Path(__file__).resolve().parents[1]
CONTRACT = "contracts/rules-surface.json"
#: Where the walk looks for markdown (the rule surface lives nowhere else).
SURFACE_ROOTS = ("AGENTS.md", "PROGRESS.md", ".claude/agents", ".agents", "tools/triage/prompts")
PATH_PREFIXES = ("tools/", "contracts/", ".agents/", ".claude/", ".github/", "apple/")
DECISION_NAME = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*\.md$")
FRONT_LINES = ("Decision", "Replaces", "Rule home")


class Finding(NamedTuple):
    """One lint result: file, 1-based line, check id, message and the home for the content."""

    path: str
    line: int
    check: str
    message: str
    home: str = ""

    def render(self) -> str:
        return f"{self.path}:{self.line}: [{self.check}] {self.message}" + (f" -> {self.home}" if self.home else "")


class Surface(NamedTuple):
    """The loaded tree: contract, root and ``{relative path: (layer, text)}`` for every markdown file in a layer."""

    root: Path
    contract: Dict[str, Any]
    files: Dict[str, Tuple[str, str]]


# MARK: - Contract and globs

def load_contract(root: Path) -> Dict[str, Any]:
    """The contract of ``root`` (the repo that owns this module when ``root`` has none)."""
    path = root / CONTRACT
    if not path.is_file():
        path = REPO / CONTRACT
    return json.loads(path.read_text(encoding="utf-8"))


def glob_regex(pattern: str) -> "re.Pattern[str]":
    """``**`` crosses folders, ``*`` and ``?`` do not."""
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif pattern.startswith("**", i):
            out, i = out + ".*", i + 2
        elif pattern[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif pattern[i] == "?":
            out, i = out + "[^/]", i + 1
        else:
            out, i = out + re.escape(pattern[i]), i + 1
    return re.compile(out + r"\Z")


def matches(path: str, globs: Iterable[str]) -> bool:
    return any(glob_regex(g).match(path) for g in globs)


def layer_of(contract: Dict[str, Any], rel: str) -> Optional[str]:
    """The layer a repo-relative path belongs to, or ``None`` (not part of the rule surface)."""
    for name, layer in contract["layers"].items():
        if matches(rel, layer["globs"]) and not matches(rel, layer.get("exclude", [])):
            return name
    return None


def iter_markdown(root: Path) -> Iterable[str]:
    for entry in SURFACE_ROOTS:
        base = root / entry
        if base.is_file():
            yield entry
        elif base.is_dir():
            for dirpath, _dirs, names in os.walk(base):
                for name in sorted(names):
                    if name.endswith(".md"):
                        yield (Path(dirpath) / name).relative_to(root).as_posix()


def load_surface(root: Path) -> Surface:
    contract = load_contract(root)
    files: Dict[str, Tuple[str, str]] = {}
    for rel in sorted(set(iter_markdown(root))):
        layer = layer_of(contract, rel)
        if layer:
            files[rel] = (layer, (root / rel).read_text(encoding="utf-8", errors="replace"))
    return Surface(root, contract, files)


# MARK: - Text helpers

FENCE = re.compile(r"^\s*(```|~~~)")
INLINE_CODE = re.compile(r"(`+)(.+?)\1")
LINK_TARGET = re.compile(r"\]\([^)]*\)")
QUOTED = re.compile(r'"[^"\n]*"|\u201c[^\u201d\n]*\u201d')


def blank(match: "re.Match[str]") -> str:
    return " " * len(match.group(0))


def fenced_flags(lines: List[str]) -> List[bool]:
    """True for each line inside or on the edge of a fenced code block."""
    flags, inside = [], False
    for line in lines:
        if FENCE.match(line):
            flags.append(True)
            inside = not inside
        else:
            flags.append(inside)
    return flags


def mask_code(lines: List[str]) -> List[str]:
    """``lines`` with fenced blocks, inline code spans and link targets replaced by spaces (columns stay)."""
    flags = fenced_flags(lines)
    out = []
    for line, fenced in zip(lines, flags):
        out.append(" " * len(line) if fenced else LINK_TARGET.sub(blank, INLINE_CODE.sub(blank, line)))
    return out


def front_matter_end(lines: List[str]) -> int:
    """Index after a leading ``---`` front-matter block (0 when there is none)."""
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return i + 1
    return 0


def words(text: str) -> int:
    return len(text.split())


# MARK: - Text checks: forbidden, per-line and per-file budgets

def layer_limits(contract: Dict[str, Any], layer: str, rel: str) -> Tuple[Optional[int], Optional[int], Optional[int]]:
    """``(max words per file, max lines per file, max words per line)`` for a file; ``None`` is unlimited."""
    cfg = contract["layers"][layer]
    max_words = cfg.get("file_max_words", {}).get(rel, cfg.get("max_words"))
    per_line = cfg["words_per_line"] if "words_per_line" in cfg else contract.get("words_per_line")
    return max_words, cfg.get("max_lines"), per_line


def forbidden_hits(contract: Dict[str, Any], layer: str, text: str) -> List[Tuple[int, str, str, Dict[str, Any]]]:
    """``(line, pattern id, matched text, pattern)`` for every forbidden hit in ``text`` under the layer's rules."""
    cfg = contract["layers"][layer]
    if not cfg.get("forbidden"):
        return []
    lines = text.split("\n")
    masked = mask_code(lines)
    hits = []
    for pattern in contract["forbidden"]:
        if pattern["id"] == "date" and cfg.get("dates"):
            continue
        flags = re.I if pattern.get("ignorecase") else 0
        regex = re.compile(pattern["regex"], flags)
        source = masked if pattern.get("skip_code") else lines
        if pattern.get("skip_quotes"):
            source = [QUOTED.sub(blank, line) for line in source]
        for number, line in enumerate(source, 1):
            for m in regex.finditer(line):
                hits.append((number, pattern["id"], m.group(0), pattern))
    return sorted(hits, key=lambda h: (h[0], h[1]))


def budget_hits(contract: Dict[str, Any], layer: str, rel: str, text: str) -> List[Tuple[int, str, str]]:
    """``(line, kind, message)``: ``long_line``, ``over_words`` and ``over_lines``."""
    max_words, max_lines, per_line = layer_limits(contract, layer, rel)
    lines = text.split("\n")
    hits: List[Tuple[int, str, str]] = []
    if per_line:
        flags = fenced_flags(lines)
        for number, (line, fenced) in enumerate(zip(lines, flags), 1):
            if not fenced and words(line) > per_line:
                hits.append((number, "long_line", f"{words(line)} words on one line (limit {per_line})"))
    if max_words is not None and words(text) > max_words:
        hits.append((1, "over_words", f"{words(text)} words in the file (budget {max_words})"))
    if max_lines is not None and len(text.rstrip("\n").split("\n")) > max_lines:
        hits.append((1, "over_lines", f"{len(text.rstrip(chr(10)).split(chr(10)))} lines in the file (budget {max_lines})"))
    return hits


def text_findings(contract: Dict[str, Any], layer: str, rel: str, text: str) -> List[Finding]:
    """Forbidden and budget findings for ``text`` as if it were file ``rel`` of ``layer``."""
    found = [Finding(rel, n, "forbidden", f"{p['why']}: `{m.strip()}` ({p['id']})", p["home"])
             for n, _id, m, p in forbidden_hits(contract, layer, text)]
    home = contract["homes"]["over budget"]
    found += [Finding(rel, n, "budget", msg, home) for n, _k, msg in budget_hits(contract, layer, rel, text)]
    return found


def hit_counts(contract: Dict[str, Any], layer: str, rel: str, text: str) -> Dict[str, int]:
    """The per-kind counts the ratchet and the write-time hook compare: ``forbidden``, ``long_lines``, ``over_words``
    (words past the file budget) and ``over_lines``."""
    max_words, max_lines, _pl = layer_limits(contract, layer, rel)
    kinds = [k for _n, k, _m in budget_hits(contract, layer, rel, text)]
    count = len(text.rstrip("\n").split("\n"))
    return {"forbidden": len(forbidden_hits(contract, layer, text)), "long_lines": kinds.count("long_line"),
            "over_words": max(0, words(text) - max_words) if max_words is not None else 0,
            "over_lines": max(0, count - max_lines) if max_lines is not None else 0}


def ratcheted(contract: Dict[str, Any], layer: str) -> bool:
    return bool(contract["layers"][layer].get("ratchet"))


def check_forbidden(s: Surface) -> List[Finding]:
    found: List[Finding] = []
    for rel, (layer, text) in s.files.items():
        if ratcheted(s.contract, layer):
            continue
        found += [f for f in text_findings(s.contract, layer, rel, text) if f.check == "forbidden"]
    return found


def check_budget(s: Surface) -> List[Finding]:
    found: List[Finding] = []
    for rel, (layer, text) in s.files.items():
        if ratcheted(s.contract, layer):
            continue
        found += [f for f in text_findings(s.contract, layer, rel, text) if f.check == "budget"]
    return found


# MARK: - Ratchet

def load_ratchet(s: Surface) -> Dict[str, Dict[str, int]]:
    for cfg in s.contract["layers"].values():
        if cfg.get("ratchet"):
            path = s.root / cfg["ratchet"]
            if path.is_file():
                return json.loads(path.read_text(encoding="utf-8")).get("files", {})
            return {}
    return {}


def measure_ratcheted(s: Surface) -> Dict[str, Dict[str, int]]:
    """Nonzero counts for every file of a ratcheted layer."""
    out = {}
    for rel, (layer, text) in s.files.items():
        if ratcheted(s.contract, layer):
            counts = hit_counts(s.contract, layer, rel, text)
            if any(counts.values()):
                out[rel] = {k: v for k, v in counts.items() if v}
    return out


def check_ratchet(s: Surface) -> List[Finding]:
    """A ratcheted file may not exceed its entry; an unlisted file must be clean; an entry above the measured count must fall."""
    entries = load_ratchet(s)
    measured = measure_ratcheted(s)
    found: List[Finding] = []
    for rel, (layer, text) in s.files.items():
        if not ratcheted(s.contract, layer):
            continue
        now, entry = measured.get(rel, {}), entries.get(rel)
        if entry is None:
            found += text_findings(s.contract, layer, rel, text)
            continue
        for kind in sorted(set(now) | set(entry)):
            have, allowed = now.get(kind, 0), entry.get(kind, 0)
            if have > allowed:
                found.append(Finding(rel, 1, "ratchet", f"{kind} is {have}, the ratchet allows {allowed}", s.contract["homes"]["over budget"]))
            elif have < allowed:
                found.append(Finding(rel, 1, "ratchet", f"{kind} is {have} but the ratchet says {allowed}: lower the ratchet "
                                     "(python3 tools/rules_lint.py --write-ratchet)", "contracts/rules-ratchet.json"))
    for rel in sorted(set(entries) - set(s.files)):
        found.append(Finding(rel, 1, "ratchet", "the ratchet lists a file that no longer exists: lower the ratchet", "contracts/rules-ratchet.json"))
    return found


def write_ratchet(s: Surface) -> Tuple[bool, str]:
    """Write the ratchet file from the measured counts; refuse (False) when any count would rise."""
    target = next((c["ratchet"] for c in s.contract["layers"].values() if c.get("ratchet")), None)
    if not target:
        return False, "no layer carries a ratchet"
    path = s.root / target
    measured = measure_ratcheted(s)
    if path.is_file():
        old = json.loads(path.read_text(encoding="utf-8")).get("files", {})
        for rel, counts in measured.items():
            for kind, value in counts.items():
                if value > old.get(rel, {}).get(kind, 0):
                    return False, f"refused: {rel} {kind} would rise to {value} (ratchet {old.get(rel, {}).get(kind, 0)}); fix the file instead"
    body = {"_about": "Per-file counts of forbidden hits, long lines and words over budget that layers with a ratchet may not exceed. "
                      "Entries only fall (python3 tools/rules_lint.py --write-ratchet refuses a rise). Deleted when the reference layer is clean.",
            "files": {rel: measured[rel] for rel in sorted(measured)}}
    path.write_text(json.dumps(body, indent=1) + "\n", encoding="utf-8")
    return True, f"wrote {target} ({len(measured)} files)"


# MARK: - Links and paths

MD_LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
BACKTICK = re.compile(r"`([^`\n]+)`")


def slug(heading: str) -> str:
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    text = re.sub(r"[`*_~]", "", text).strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors_of(text: str) -> Set[str]:
    seen: Dict[str, int] = {}
    out: Set[str] = set()
    lines = text.split("\n")
    for line, fenced in zip(lines, fenced_flags(lines)):
        m = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
        if m and not fenced:
            base = slug(m.group(1))
            n = seen.get(base, 0)
            out.add(base if n == 0 else f"{base}-{n}")
            seen[base] = n + 1
    return out


def resolve_link(rel: str, target: str) -> str:
    """Repo-relative path a relative link in ``rel`` points at (``..`` normalized; empty when it leaves the repo)."""
    path = os.path.normpath(os.path.join(os.path.dirname(rel), target)).replace(os.sep, "/")
    return "" if path.startswith("..") else path


def markdown_links(text: str) -> List[Tuple[int, str]]:
    """``(line, target)`` for each markdown link outside fenced code."""
    lines = text.split("\n")
    out = []
    for number, (line, fenced) in enumerate(zip(lines, fenced_flags(lines)), 1):
        if not fenced:
            out += [(number, m.group(1)) for m in MD_LINK.finditer(INLINE_CODE.sub(blank, line))]
    return out


def path_tokens(text: str, ignore: Tuple[str, ...] = ()) -> List[Tuple[int, str]]:
    """``(line, path)`` for each backticked word that looks like a repo path under the known prefixes."""
    lines = text.split("\n")
    out = []
    for number, (line, fenced) in enumerate(zip(lines, fenced_flags(lines)), 1):
        if fenced:
            continue
        for m in BACKTICK.finditer(line):
            for word in m.group(1).split():
                word = word.rstrip(",;.)").lstrip("(")
                word = re.sub(r":\d+(?:-\d+)?$", "", word.split("#")[0])
                if word.startswith(PATH_PREFIXES) and not re.search(r"[<>*{}$\[\]|=\u2026]|\.\.\.|\?", word) \
                        and not any(word == i or word.startswith(i + "/") for i in ignore):
                    out.append((number, word.rstrip("/")))
    return out


def check_links(s: Surface) -> List[Finding]:
    found: List[Finding] = []
    anchor_cache: Dict[str, Set[str]] = {}

    def anchors(rel: str) -> Set[str]:
        if rel not in anchor_cache:
            anchor_cache[rel] = anchors_of(s.files[rel][1] if rel in s.files else (s.root / rel).read_text(encoding="utf-8", errors="replace"))
        return anchor_cache[rel]

    for rel, (layer, text) in s.files.items():
        if layer == "record":
            continue
        for number, target in markdown_links(text):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target):
                continue
            dest, _, frag = target.partition("#")
            resolved = rel if not dest else resolve_link(rel, dest)
            full = s.root / resolved if resolved else None
            if not resolved or not full.exists():
                found.append(Finding(rel, number, "links", f"link target `{target}` does not exist", "fix or delete the link"))
            elif frag and full.is_file() and resolved.endswith(".md") and frag not in anchors(resolved):
                found.append(Finding(rel, number, "links", f"`{target}` names no heading `#{frag}` in {resolved}", "fix the anchor"))
        for number, word in path_tokens(text, tuple(s.contract.get("path_ignore", ()))):
            if not (s.root / word).exists():
                found.append(Finding(rel, number, "links", f"`{word}` is not a path in the repo", "fix the path or name the file that exists"))
    return found


# MARK: - Structure

def check_structure(s: Surface) -> List[Finding]:
    found: List[Finding] = []
    contract = s.contract
    for rel, (layer, text) in s.files.items():
        if layer == "record":
            continue
        first = text.split("\n", 1)[0]
        if not (first.startswith("# ") or first.strip() == "---"):
            found.append(Finding(rel, 1, "structure", "line 1 must be `# Title`", "docs-conventions"))
        allowed = contract["layers"][layer].get("files")
        if allowed is not None:
            folder = os.path.dirname(rel)
            for glob in contract["layers"][layer]["globs"]:
                if os.path.dirname(glob) == folder and os.path.basename(rel) not in allowed:
                    found.append(Finding(rel, 1, "structure", f"layer {layer} holds only the files listed in {CONTRACT}",
                                         "merge it into one of them, make it a skill, or delete it"))
                    break
        if layer != "record":
            for number, target in markdown_links(text):
                resolved = resolve_link(rel, target.split("#")[0]) if target.split("#")[0] else ""
                if resolved.startswith((".agents/decisions", ".agents/archive")) and not (
                        rel in contract.get("decision_link_allowed", []) or os.path.basename(rel) == "README.md"):
                    found.append(Finding(rel, number, "structure", f"links into {resolved.split('/')[1]}/, which is never required reading",
                                         "state the rule here; the record stays unlinked"))
            for number, word in path_tokens(text, tuple(s.contract.get("path_ignore", ()))):
                if word.startswith((".agents/decisions", ".agents/archive")) and not (
                        rel in contract.get("decision_link_allowed", []) or os.path.basename(rel) == "README.md"):
                    found.append(Finding(rel, number, "structure", f"names {word}, which is never required reading", "state the rule here"))
    found += router_findings(s)
    return found


def router_findings(s: Surface) -> List[Finding]:
    """A folder README links every sibling markdown file and every child folder; folders of the surface have one."""
    skip = ("archive", "decisions", "mockups")
    exempt_children = re.compile(r"^\.agents/(?:pages|controls)/[^/]+$")
    folders: Dict[str, List[str]] = {}
    for rel in s.files:
        if rel.startswith(".agents/") and not any(part in skip for part in rel.split("/")[:-1]):
            folders.setdefault(os.path.dirname(rel), []).append(rel)
    found: List[Finding] = []
    for folder in sorted(folders):
        readme = f"{folder}/README.md"
        if exempt_children.match(folder) or folder.startswith(".agents/skills/"):
            continue
        if readme not in s.files:
            found.append(Finding(folder, 1, "structure", "folder has markdown but no README.md router", "add README.md linking every child"))
            continue
        linked = set()
        for _n, target in markdown_links(s.files[readme][1]):
            if not re.match(r"^[a-z][a-z0-9+.-]*:", target) and target.split("#")[0]:
                linked.add(resolve_link(readme, target.split("#")[0]).rstrip("/"))
        siblings = {rel for rel in folders[folder] if rel != readme}
        for rel in sorted(siblings):
            if rel not in linked:
                found.append(Finding(readme, 1, "structure", f"does not link {os.path.basename(rel)}", "add it to the router"))
        for name in sorted(os.listdir(s.root / folder)):
            sub = f"{folder}/{name}"
            if (s.root / sub).is_dir() and name not in skip and not name.startswith(".") and any(r.startswith(sub + "/") for r in s.files):
                if not ({sub, sub + "/README.md", sub + "/SKILL.md"} & linked):
                    found.append(Finding(readme, 1, "structure", f"does not link the folder {name}/", "add it to the router"))
    return found


# MARK: - Decisions

def check_decisions(s: Surface, base: Optional[str] = None) -> List[Finding]:
    found: List[Finding] = []
    for rel, (layer, text) in s.files.items():
        if not matches(rel, [".agents/decisions/*.md"]) or rel.endswith("/README.md"):
            continue
        name = os.path.basename(rel)
        if not DECISION_NAME.match(name):
            found.append(Finding(rel, 1, "decisions", "file name must be YYYY-MM-DD-slug.md", "rename it"))
        head = "\n".join(text.split("\n")[:12])
        for key in FRONT_LINES:
            if not re.search(rf"^[*_ ]*{key}[*_]*:", head, re.M):
                found.append(Finding(rel, 1, "decisions", f"missing the front line `{key}:` in the first 12 lines", ".agents/decisions/README.md"))
    if base:
        found += append_only_findings(s.root, base)
    return found


def append_only_findings(root: Path, base: str) -> List[Finding]:
    """Existing decision files may not be edited, renamed or deleted against ``base`` (new files are fine)."""
    def git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=60)

    merge = git("merge-base", base, "HEAD")
    if merge.returncode != 0:
        return [Finding(".agents/decisions", 1, "decisions", f"cannot compare with base `{base}`: {merge.stderr.strip()[:120]}", "fetch the base ref")]
    diff = git("diff", "--name-status", "--no-renames", merge.stdout.strip(), "--", ".agents/decisions")
    found = []
    for line in diff.stdout.splitlines():
        status, _, path = line.partition("\t")
        if status != "A" and not path.endswith("README.md"):
            found.append(Finding(path, 1, "decisions", f"decision files are append-only ({status} against {base})",
                                 "write a new decision that names what it replaces"))
    return found


# MARK: - One home

SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")


def paragraphs(text: str) -> List[Tuple[int, str]]:
    """``(first line, text)`` of each paragraph, list item and table cell outside code and front matter."""
    lines = text.split("\n")
    flags = fenced_flags(lines)
    start = front_matter_end(lines)
    out: List[Tuple[int, str]] = []
    current: List[str] = []
    first = 0

    def flush() -> None:
        nonlocal current
        if current:
            out.append((first, " ".join(current)))
        current = []

    for number, (line, fenced) in enumerate(zip(lines, flags), 1):
        if number <= start or fenced or not line.strip() or line.lstrip().startswith("#"):
            flush()
        elif line.lstrip().startswith("|"):
            flush()
            out += [(number, cell) for cell in line.strip().strip("|").split("|")]
        elif re.match(r"^\s*(?:[-*+]|\d+[.)])\s", line):
            flush()
            current, first = [line], number
        else:
            if not current:
                first = number
            current.append(line)
    flush()
    return out


def normalize(sentence: str) -> str:
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", sentence)
    text = re.sub(r"[^a-z0-9 ]", " ", text.lower())
    return " ".join(text.split())


def check_one_home(s: Surface, min_words: int = 12) -> List[Finding]:
    seen: Dict[str, List[Tuple[str, int]]] = {}
    for rel in sorted(s.files):
        layer, text = s.files[rel]
        if not s.contract["layers"][layer].get("one_home"):
            continue
        for number, para in paragraphs(text):
            for sentence in SENTENCE_SPLIT.split(para):
                norm = normalize(sentence)
                if len(norm.split()) >= min_words:
                    where = seen.setdefault(norm, [])
                    if all(rel != r for r, _n in where):
                        where.append((rel, number))
    found = []
    for norm, where in seen.items():
        for rel, number in where[1:]:
            found.append(Finding(rel, number, "one_home", f"sentence repeats one in {where[0][0]}:{where[0][1]}: \"{norm[:60]}...\"",
                                 "keep it in one file and link to it from the other"))
    return sorted(found)


# MARK: - Per-role load

def read_first_links(rel: str, text: str) -> List[str]:
    """Repo-relative markdown files linked from the ``Read first`` section of ``text`` (one level)."""
    lines = text.split("\n")
    flags = fenced_flags(lines)
    out: List[str] = []
    inside = False
    for line, fenced in zip(lines, flags):
        if re.match(r"^#{1,6}\s*read first\b", line, re.I):
            inside = True
            continue
        if inside and re.match(r"^#{1,6}\s", line) and not fenced:
            break
        if inside and not fenced:
            for m in MD_LINK.finditer(line):
                target = m.group(1).split("#")[0]
                if target and not re.match(r"^[a-z][a-z0-9+.-]*:", target) and target.endswith(".md"):
                    resolved = resolve_link(rel, target)
                    if resolved:
                        out.append(resolved)
    return out


def role_loads(s: Surface) -> Dict[str, int]:
    """Words of each role file plus ``AGENTS.md`` plus every file its ``Read first`` section links."""
    cfg = s.contract["role_load"]
    out: Dict[str, int] = {}
    for rel in sorted(s.files):
        if not matches(rel, cfg["agent_globs"] + cfg["prompt_globs"]):
            continue
        names = [rel] + list(cfg.get("always", [])) + read_first_links(rel, s.files[rel][1])
        total = 0
        for name in dict.fromkeys(names):
            path = s.root / name
            if path.is_file():
                total += words(path.read_text(encoding="utf-8", errors="replace"))
        out[rel] = total
    return out


def check_role_load(s: Surface) -> List[Finding]:
    cfg = s.contract["role_load"]
    found = []
    for rel, total in role_loads(s).items():
        limit = cfg["orchestrator"] if rel in cfg.get("orchestrator_files", []) else cfg["default"]
        if total > limit:
            found.append(Finding(rel, 1, "role_load", f"spawn load is {total} words (budget {limit}): the file, AGENTS.md and its Read first links",
                                 s.contract["homes"]["over budget"]))
    return found


# MARK: - Running

CHECKS = {"forbidden": check_forbidden, "budget": check_budget, "ratchet": check_ratchet, "role_load": check_role_load,
          "one_home": check_one_home, "links": check_links, "structure": check_structure}


def run(root: Path, paths: Optional[List[str]] = None, base: Optional[str] = None) -> List[Finding]:
    """Every finding for the tree at ``root`` (only those in ``paths`` when given)."""
    s = load_surface(root)
    found: List[Finding] = []
    for check in CHECKS.values():
        found += check(s)
    found += check_decisions(s, base)
    if paths:
        wanted = {(os.path.relpath(p, root) if os.path.isabs(p) else os.path.normpath(p)).replace(os.sep, "/") for p in paths}
        found = [f for f in found if f.path in wanted]
    return sorted(set(found), key=lambda f: (f.path, f.line, f.check, f.message))


def report(root: Path) -> Dict[str, Any]:
    """Words per layer and the per-role spawn load, for the weekly roll-up (report only)."""
    s = load_surface(root)
    layers: Dict[str, Dict[str, int]] = {}
    for _rel, (layer, text) in s.files.items():
        entry = layers.setdefault(layer, {"files": 0, "words": 0})
        entry["files"] += 1
        entry["words"] += words(text)
    surface = sum(v["words"] for k, v in layers.items() if k not in ("record",))
    return {"layers": layers, "rule_surface_words": surface, "role_load": role_loads(s)}


def summary(found: List[Finding]) -> str:
    counts: Dict[str, int] = {}
    for f in found:
        counts[f.check] = counts.get(f.check, 0) + 1
    return f"{len(found)} findings in {len({f.path for f in found})} files: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(REPO), help="repository root (default: this repo)")
    ap.add_argument("--paths", nargs="+", help="report only findings in these files")
    ap.add_argument("--base", help="also check that existing decision files are not edited against this ref (append-only)")
    ap.add_argument("--report", action="store_true", help="print words per layer and per-role load as JSON")
    ap.add_argument("--write-ratchet", action="store_true", help="rewrite the ratchet from the tree; refused when any count would rise")
    ap.add_argument("--stdin-path", help="lint text from stdin as if it were this repo-relative file (forbidden and budgets only)")
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    if args.report:
        print(json.dumps(report(root), indent=1))
        return 0
    if args.write_ratchet:
        ok, message = write_ratchet(load_surface(root))
        print(message, file=sys.stdout if ok else sys.stderr)
        return 0 if ok else 1
    if args.stdin_path:
        contract = load_contract(root)
        rel = args.stdin_path
        layer = layer_of(contract, rel)
        found = text_findings(contract, layer, rel, sys.stdin.read()) if layer else []
    else:
        found = run(root, args.paths, args.base)
    for f in found:
        print(f.render())
    if found:
        print(summary(found))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
