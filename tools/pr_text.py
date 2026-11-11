#!/usr/bin/env python3
"""Plain pull request titles and bodies: check them, compose them, label them.

Commands::

    python3 tools/pr_text.py title-check TEXT
    python3 tools/pr_text.py body-check FILE [--strict]
    python3 tools/pr_text.py compose --summary-file F --tests-file F [--evidence-file F]
                                     [--request N] [--request-quote TEXT]
    python3 tools/pr_text.py title-from FILE
    python3 tools/pr_text.py labels --base REF [--head REF] [--type TYPE] [--devices iphone,duo,ipad]

The rules come from the pull-request timeline proposal: a title is one plain sentence of at most 70 characters; a body has a
``## Summary`` and a ``## Tests`` section and nothing a person has to skip. No status text and no review block is shown:
``compose`` writes only the hidden marker pairs other tools find (``sh-timeline``, ``sh-status``, ``review``). An
``## Evidence`` section is for pictures of its own (an image, a gif or a video): one that only links to pictures in the
comments is refused. The banned words, the internal-label patterns and
the path-to-area table live in ``tools/pr_text_words.json``, which the owner can edit. Exit codes: 0 clean, 1 a problem (or a
warning under ``--strict``), 2 bad usage. Standard library only.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable, Optional, Sequence

# MARK: - Configuration

WORDS_PATH = Path(__file__).resolve().with_name("pr_text_words.json")
MAX_TITLE = 70
MAX_PARAGRAPH_SENTENCES = 6
MAX_PROSE_WORDS = 25
MAX_ITEM_WORDS = 20
MAX_AREAS = 3
MIN_SUMMARY_SENTENCES = 2
MAX_SUMMARY_SENTENCES = 4
ALLOWED_SECTIONS = ("summary", "tests", "evidence")
TYPES = ("Bug", "Feature", "Workflow", "Nightly Fix")
#: ``--devices`` token to label. Only the device families the app supports; there is no Mac label.
DEVICE_LABELS = {"iphone": "iPhone", "duo": "iPhone Duo", "ipad": "iPad"}


def load_words(path: Path = WORDS_PATH) -> dict:
    """The owner-editable word data (:file:`pr_text_words.json`)."""
    return json.loads(path.read_text(encoding="utf-8"))


# MARK: - Markdown cleaning

FENCE = re.compile(r"^(```|~~~).*?^\1[ \t]*$", re.S | re.M)
COMMENT = re.compile(r"<!--.*?-->", re.S)
DETAILS = re.compile(r"<details\b.*?</details>", re.S | re.I)
INLINE_CODE = re.compile(r"`[^`\n]*`")
REQUEST_LINE = re.compile(r"^[ \t>*_-]*(?:Owner'?s request\b|Owner-Request:).*$", re.I | re.M)
HEADING = re.compile(r"^##[ \t]+(.+?)[ \t]*#*[ \t]*$", re.M)
ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(.*)$")
BRACKET = re.compile(r"(?<![\w!\\\]])\[(?!!)([^\[\]\n]*)\](?![(\[:])")
SENTENCE_END = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"'(])")
ABBREVIATIONS = ("e.g.", "i.e.", "vs.", "etc.,")
#: A picture of the section's own: a markdown image, an ``<img>`` or ``<video>`` tag, or an uploaded asset on its own line.
OWN_PICTURE = re.compile(
    r"!\[[^\]]*\]\([^)\s]+\)|<img\b[^>]*\bsrc=|<video\b[^>]*\bsrc=|^\s*https://github\.com/user-attachments/assets/\S+\s*$",
    re.I | re.M)


def marker_block(name: str) -> "re.Pattern[str]":
    """The regex for ``<!-- name:start --> ... <!-- name:end -->``, markers included."""
    return re.compile(rf"<!--\s*{re.escape(name)}:start\s*-->.*?<!--\s*{re.escape(name)}:end\s*-->", re.S)


def strip_unlinted(text: str, words: dict) -> str:
    """``text`` without what the style lint skips: code fences, marker blocks, HTML comments, ``<details>`` and request lines."""
    text = FENCE.sub("", text)
    for name in words["marker_blocks"]:
        text = marker_block(name).sub("", text)
    return REQUEST_LINE.sub("", DETAILS.sub("", COMMENT.sub("", text)))


def sections(text: str) -> dict:
    """Level-2 sections by lower-cased heading, each the raw text up to the next ``##`` heading (fences ignored)."""
    text = FENCE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    marks = list(HEADING.finditer(text))
    return {m.group(1).strip().lower(): text[m.end(): marks[i + 1].start() if i + 1 < len(marks) else len(text)]
            for i, m in enumerate(marks)}


def plain(text: str, keep_code: bool = False) -> str:
    """One line of reading text: links reduced to their label, images and emphasis marks removed, code ticks too unless ``keep_code``."""
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"^\[[ xX]\]\s*", "", text)
    text = text if keep_code else text.replace("`", "")
    text = re.sub(r"(\*\*|__|\*|(?<!\w)_|_(?!\w))", "", text)
    return re.sub(r"\s+", " ", text).strip()


def units(text: str, keep_code: bool = False) -> list:
    """``(kind, text)`` for each paragraph (``para``) and list item (``item``) of ``text``; headings, tables and images are skipped.

    Paragraph lines are joined, so a sentence wrapped over lines stays whole."""
    out: list = []
    para: list = []
    item: Optional[list] = None

    def flush() -> None:
        nonlocal para, item
        if para:
            out.append(("para", " ".join(para)))
        if item is not None:
            out.append(("item", " ".join(item)))
        para, item = [], None

    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            flush()
        elif stripped.startswith(("#", "|", "![", "<")):
            flush()
        elif ITEM.match(line):
            flush()
            item = [ITEM.match(line).group(1)]
        elif item is not None and line[:1] in " \t":
            item.append(stripped)
        else:
            if item is not None:
                flush()
            para.append(stripped)
    flush()
    return [(kind, plain(body, keep_code)) for kind, body in out if plain(body, keep_code)]


def sentences(text: str) -> list:
    """The sentences of one unit of reading text."""
    for abbreviation in ABBREVIATIONS:
        text = text.replace(abbreviation, abbreviation.replace(".", "․"))
    return [s.replace("․", ".").strip() for s in SENTENCE_END.split(text) if s.strip()]


def word_count(sentence: str) -> int:
    """Whitespace-separated words in ``sentence``."""
    return len(sentence.split())


# MARK: - Word rules

def banned_hits(text: str, words: dict) -> list:
    """Banned stems and phrases found in ``text`` (lower-cased match, whole-word start)."""
    low = text.lower()
    hits = [m.group(0) for stem in words["banned_stems"] for m in re.finditer(rf"\b{re.escape(stem)}\w*", low)]
    hits += [p for p in words["banned_phrases"] if re.search(rf"\b{re.escape(p)}\b", low)]
    return hits


def label_hits(text: str, words: dict) -> list:
    """Internal labels (``Phase 4``, ``lane P4c``, a ``T-`` task id) found in ``text``."""
    return [m.group(0) for pattern in words["internal_labels"] for m in re.finditer(pattern, text)]


def path_hits(text: str, words: dict) -> list:
    """File paths and file names found in ``text``."""
    roots = "|".join(re.escape(r) for r in words["path_roots"])
    exts = "|".join(re.escape(e) for e in words["path_extensions"])
    pattern = rf"(?<![\w/.-])(?:(?:{roots})/[\w./-]+|[\w-]+(?:/[\w-]+)*\.(?:{exts})\b)"
    return [m.group(0) for m in re.finditer(pattern, text)]


def passive_hits(sentence: str, words: dict) -> list:
    """Passive-voice phrases: a form of *to be* then a past participle."""
    irregular = "|".join(re.escape(w) for w in words["irregular_participles"])
    pattern = rf"\b(?:is|are|was|were|been|being|be)\s+(?:\w{{3,}}ed|{irregular})\b"
    return [m.group(0) for m in re.finditer(pattern, sentence, re.I)]


def progressive_hits(sentence: str, words: dict) -> list:
    """Progressive tense phrases such as *is running*."""
    allowed = {w.lower() for w in words["progressive_allow"]}
    found = []
    for m in re.finditer(r"\b(?:is|are|was|were|am|been|being)\s+(\w{2,}ing)\b", sentence, re.I):
        if m.group(1).lower() not in allowed:
            found.append(m.group(0))
    return found


def placeholder_problems(body: str, words: dict) -> list:
    """Template placeholder text left in ``body``: a bracketed ``[ ... ]`` that is not a link or checkbox, or an old instruction string."""
    problems = []
    raw = marker_block("review").sub("", body)
    prose = INLINE_CODE.sub("", FENCE.sub("", raw))
    for needle in words["placeholder_strings"]:
        hit = re.search(rf"\b{re.escape(needle)}\b", prose) if len(needle) <= 4 else re.search(re.escape(needle), prose, re.I)
        if hit:
            problems.append(f"template placeholder text left in: {needle!r}")
    text = COMMENT.sub("", prose)
    for m in BRACKET.finditer(text):
        inner = m.group(1)
        if inner in (" ", "x", "X") or inner.startswith("^"):
            continue
        problems.append(f"placeholder in square brackets: {m.group(0)!r}")
    return problems


# MARK: - Checks

def title_problems(title: str, words: Optional[dict] = None) -> list:
    """One line per rule a pull request title breaks; empty when it is fine. A trailing ``(#N)`` is allowed."""
    words = words or load_words()
    title = title.strip()
    problems = []
    if not title:
        return ["title is empty"]
    if "\n" in title:
        problems.append("title must be one line")
    if len(title) > MAX_TITLE:
        problems.append(f"title is {len(title)} characters; the limit is {MAX_TITLE}")
    if re.match(r"^[^:]{1,40}:\s", title):
        problems.append("title starts with a 'word:' prefix; say what changes, no area prefix")
    if ";" in title:
        problems.append("title has a semicolon; use one plain sentence")
    if title.count(",") > 1:
        problems.append("title is a comma-joined list of clauses; name the one change")
    for hit in sorted(set(banned_hits(title, words))):
        problems.append(f"title uses a banned word: {hit}")
    for hit in label_hits(title, words):
        problems.append(f"title has an internal label: {hit}")
    if "`" in title:
        problems.append("title has backticks; write plain words")
    for hit in path_hits(title, words):
        problems.append(f"title has a file path or file name: {hit}")
    return problems


def first_summary_sentence(body: str, words: Optional[dict] = None) -> Optional[str]:
    """The first sentence of the ``## Summary`` section, or ``None`` when it has none (inline code ticks kept)."""
    words = words or load_words()
    section = sections(body).get("summary")
    if section is None:
        return None
    for _, unit in units(strip_unlinted(section, words), keep_code=True):
        found = sentences(unit)
        if found:
            return found[0]
    return None


def has_own_picture(text: str) -> bool:
    """Whether ``text`` holds a picture of its own (not a link to one elsewhere); comments and code fences do not count."""
    return bool(OWN_PICTURE.search(COMMENT.sub("", FENCE.sub("", text))))


def body_problems(body: str, words: Optional[dict] = None) -> tuple:
    """``(errors, warnings)`` for a pull request body; see the module notes for which rule is which."""
    words = words or load_words()
    errors: list = []
    warnings: list = []
    found = sections(body)
    visible: dict = {}
    for name in ("summary", "tests"):
        if name not in found:
            errors.append(f"missing section: ## {name.capitalize()}")
        elif not re.search(r"\w", plain(strip_unlinted(found[name], words))):
            errors.append(f"empty section: ## {name.capitalize()}")
        else:
            visible[name] = strip_unlinted(found[name], words)
    for heading in HEADING.finditer(strip_unlinted(body, words)):
        if heading.group(1).strip().lower() not in ALLOWED_SECTIONS:
            errors.append(f"extra section: ## {heading.group(1).strip()}; a body has only Summary, Tests and Evidence")
    if "evidence" in found and not has_own_picture(found["evidence"]):
        errors.append("## Evidence holds no picture of its own; leave the section out when the pictures are in the comments")
    errors += placeholder_problems(body, words)
    first = first_summary_sentence(body, words)
    if first:
        for hit in label_hits(first, words):
            errors.append(f"first Summary sentence has an internal label: {hit}")
        for hit in path_hits(first, words):
            errors.append(f"first Summary sentence has a file path or file name: {hit}")
        if "`" in first:
            errors.append("first Summary sentence has backticks; write plain words")
    for kind, text in units(visible.get("summary", "")):
        if kind == "para" and len(sentences(text)) > MAX_PARAGRAPH_SENTENCES:
            errors.append(f"a Summary paragraph has {len(sentences(text))} sentences; the limit is {MAX_PARAGRAPH_SENTENCES}")
    count = sum(len(sentences(unit)) for _, unit in units(visible.get("summary", "")))
    if "summary" in visible and not MIN_SUMMARY_SENTENCES <= count <= MAX_SUMMARY_SENTENCES:
        warnings.append(f"Summary has {count} sentences; aim for {MIN_SUMMARY_SENTENCES} to {MAX_SUMMARY_SENTENCES}")
    for name, text in visible.items():
        for kind, unit in units(text):
            limit = MAX_ITEM_WORDS if kind == "item" else MAX_PROSE_WORDS
            for sentence in sentences(unit):
                where = f"{name.capitalize()}: {sentence[:60]!r}"
                if word_count(sentence) > limit:
                    warnings.append(f"{where} has {word_count(sentence)} words; the limit is {limit}")
                for hit in passive_hits(sentence, words):
                    warnings.append(f"{where} passive voice: {hit!r}")
                for hit in progressive_hits(sentence, words):
                    warnings.append(f"{where} progressive tense: {hit!r}")
                if " and then " in f" {sentence.lower()} ":
                    warnings.append(f"{where} has two instructions ('and then')")
                for hit in sorted(set(banned_hits(sentence, words))):
                    warnings.append(f"{where} banned word: {hit}")
    return errors, warnings


# MARK: - Composer

def compose(summary: str, tests: str, evidence: str = "", request: str = "", quote: str = "") -> str:
    """The pull request body: Summary, Tests, Evidence when given, then the hidden marker pairs and the request lines.

    Nothing about status or review is shown: the ``sh-timeline``, ``sh-status`` and ``review`` marker pairs are empty HTML
    comments, kept so the tools that write between them still find their place."""
    parts = [f"## Summary\n{summary.strip()}", f"## Tests\n{tests.strip()}"]
    if evidence.strip():
        parts.append(f"## Evidence\n{evidence.strip()}")
    parts.append("<!-- sh-timeline:start -->\n<!-- sh-timeline:end -->")
    parts.append("<!-- sh-status:start -->\n<!-- sh-status:end -->")
    parts.append("<!-- review:start -->\n<!-- review:end -->")
    tail = []
    if quote.strip():
        tail.append(f'Owner\'s request: "{quote.strip()}"')
    if request.strip():
        ref = request.strip()
        tail.append(f"Owner-Request: {ref if ('#' in ref) else '#' + ref}")
    if tail:
        parts.append("\n".join(tail))
    return "\n\n".join(parts) + "\n"


# MARK: - Labels

def area_for(path: str, table: Sequence) -> Optional[str]:
    """The area of ``path`` by the longest matching prefix in ``table``; ``None`` when no prefix matches.

    A prefix matches a whole path, a folder (``prefix/``) or, when it ends in ``_``, a file-name start."""
    def hit(prefix: str) -> bool:
        return path == prefix or path.startswith(prefix + "/") or (prefix.endswith("_") and path.startswith(prefix))

    best = max((row for row in table if hit(row[0])), key=lambda row: len(row[0]), default=None)
    return best[1] if best else None


def area_labels(paths: Iterable, words: Optional[dict] = None) -> list:
    """Up to :data:`MAX_AREAS` ``area:<name>`` labels for the changed ``paths``, most files first (ties by name)."""
    words = words or load_words()
    counts = Counter(a for a in (area_for(p, words["areas"]) for p in paths) if a)
    return [f"area:{name}" for name, _ in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:MAX_AREAS]]


def device_labels(spec: str) -> list:
    """Labels for a comma-separated ``--devices`` value (``iphone``, ``duo``, ``ipad``); raises ``ValueError`` on anything else."""
    out = []
    for token in (t.strip().lower() for t in spec.split(",") if t.strip()):
        if token not in DEVICE_LABELS:
            raise ValueError(f"unknown device {token!r}; use iphone, duo or ipad")
        if DEVICE_LABELS[token] not in out:
            out.append(DEVICE_LABELS[token])
    return out


def changed_paths(base: str, head: str, cwd: Optional[Path] = None) -> list:
    """Files changed on ``head`` since its merge base with ``base``."""
    result = subprocess.run(["git", "diff", "--name-only", f"{base}...{head}"], cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "git diff failed")
    return [line for line in result.stdout.splitlines() if line]


# MARK: - Command line

def read_text(path: str) -> str:
    """The text of ``path``, or of standard input for ``-``."""
    return sys.stdin.read() if path == "-" else Path(path).read_text(encoding="utf-8")


def main(argv: Optional[Sequence] = None) -> int:
    """Run one command; see the module notes."""
    parser = argparse.ArgumentParser(prog="pr_text", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("title-check", help="check a pull request title")
    p.add_argument("text")
    p = sub.add_parser("body-check", help="check a pull request body file")
    p.add_argument("file")
    p.add_argument("--strict", action="store_true", help="warnings fail too")
    p = sub.add_parser("compose", help="print a pull request body")
    p.add_argument("--summary-file", required=True)
    p.add_argument("--tests-file", required=True)
    p.add_argument("--evidence-file")
    p.add_argument("--request")
    p.add_argument("--request-quote")
    p = sub.add_parser("title-from", help="print the first Summary sentence as a title")
    p.add_argument("file")
    p = sub.add_parser("labels", help="print the labels for a change")
    p.add_argument("--base", required=True)
    p.add_argument("--head", default="HEAD")
    p.add_argument("--type", choices=TYPES)
    p.add_argument("--devices", default="")
    args = parser.parse_args(argv)

    if args.command == "title-check":
        problems = title_problems(args.text)
        for line in problems:
            print(f"error: {line}")
        return 1 if problems else 0
    if args.command == "body-check":
        errors, warnings = body_problems(read_text(args.file))
        for line in errors:
            print(f"error: {line}")
        for line in warnings:
            print(f"warning: {line}")
        return 1 if errors or (args.strict and warnings) else 0
    if args.command == "compose":
        summary, tests = read_text(args.summary_file), read_text(args.tests_file)
        evidence = read_text(args.evidence_file) if args.evidence_file else ""
        empty = [n for n, t in (("summary", summary), ("tests", tests)) if not t.strip()]
        if empty:
            print(f"error: empty {' and '.join(empty)} file", file=sys.stderr)
            return 1
        if evidence.strip() and not has_own_picture(evidence):
            print("error: the evidence file holds no picture of its own; leave it out when the pictures are in the comments",
                  file=sys.stderr)
            return 1
        sys.stdout.write(compose(summary, tests, evidence, args.request or "", args.request_quote or ""))
        return 0
    if args.command == "title-from":
        first = first_summary_sentence(read_text(args.file))
        if not first:
            print("error: no Summary sentence", file=sys.stderr)
            return 1
        title = first.rstrip().rstrip(".!?").strip()
        problems = title_problems(title)
        if problems:
            for line in problems:
                print(f"error: {line}", file=sys.stderr)
            return 1
        print(title)
        return 0
    try:
        labels = ([args.type] if args.type else []) + device_labels(args.devices)
        labels += area_labels(changed_paths(args.base, args.head))
    except (ValueError, RuntimeError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    print("\n".join(labels))
    return 0


if __name__ == "__main__":
    sys.exit(main())
