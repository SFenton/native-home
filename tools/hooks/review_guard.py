#!/usr/bin/env python3
"""PreToolUse hook for Bash, Edit, Write, MultiEdit and NotebookEdit: only the reviewer records a review verdict.

``tools/pr_land.sh`` (and the interactive ``tools/lane_land.py``) read a verdict file as the independent review. Without CI the file is
the whole review gate, so nobody but the reviewer may create or change one (owner, 2026-11-07, end-to-end autonomy; round-1 review of
the unlock). Acts on **agent sessions** (``FENTON_HEADLESS=1``, or a payload with ``agent_type`` or ``agent_id``); a plain owner session is
never blocked. Exit 2 sends the message back.

- **File tools** may not write ``build/review/*.json`` or anything under ``~/hass-agents/reviews/``: not for the reviewer either; the only
  writer is ``tools/review/record.py``.
- **Bash** may run ``tools/review/record.py`` only when the payload's ``agent_type`` is ``reviewer`` (hooks key on ``agent_type``). The hook then
  leaves an identity stamp (``agent_type``, ``session_id``, the working directory, the time) that ``record.py`` reads and copies into the verdict
  as ``reviewer``; ``pr_land`` and ``lane_land`` refuse a verdict without it. Any other command that names a review path must be a plain
  reader (``cat``, ``ls``, ``grep``, ``jq`` …, ``pr_land.sh``, ``ship.sh``) with no redirect, ``tee``, ``cp``, ``mv``, interpreter or editor.

A tripwire, not a wall: a script file that writes the verdict, or a path built at run time, is out of scope; the independent review of the
change that adds such a script is the cover. The runner-launched lane review is separate: the runner parses the reviewer's output itself and
writes ``recorded_by: runner`` (``lane_land.land``).
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple

MESSAGE = (
    "Blocked: a review verdict is written only by `tools/review/record.py`, run by the reviewer (agent_type `reviewer`). The verdict file is the "
    "independent review that `tools/pr_land.sh` gates on, so no other session creates or edits `build/review/*.json` or "
    "`~/hass-agents/reviews/`. Spawn the reviewer (`opus-ok: final review`); read a verdict with `cat`. See .agents/workflow/pr-lifecycle.md."
)
#: Where ``record.py`` looks for the stamp (kept equal to ``record.IDENT_PATH`` by a test).
IDENT_PATH = Path.home() / ".cache" / "fenton-hass" / "reviewer-ident.json"
REVIEW_PATH = re.compile(r"build/review(?:/|\b)|hass-agents/reviews|reviewer-ident", re.I)
FILE_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
READERS = {"cat", "ls", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg", "wc", "jq", "stat", "diff", "test", "[", "echo", "printf",
           "true", "cd", "pwd"}
#: Landing scripts that read a verdict (named without their extension so this file loads no other script by name).
READER_SCRIPTS = {"pr_land", "ship"}
READ_GIT = {"log", "show", "diff", "status", "check-ignore", "ls-files", "rev-parse"}
REDIRECT = re.compile(r"^\d*(?:>>?|>\||<>)$|^\d*>&?\d*$")


#: Self-contained on purpose: this hook is in the owner-only set, so everything it imports would have to be too (``shell_parse`` is shared and unlocked).
WRAPPERS = {"env", "command", "exec", "nohup", "time", "sudo", "nice", "timeout", "gtimeout", "xargs", "builtin", "caffeinate"}
KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "{", "}", "!", "done", "fi", "esac"}


def tokenize(command: str) -> List[Tuple[str, List[str]]]:
    """Simple commands of ``command`` as ``(operator before it, words)``: quote-aware, split on ``; && || | & ( )`` and newlines, with ``$(``,
    backticks and process substitution opening a group. A heredoc body is data and dropped (the word after ``<<`` ends it)."""
    lines, kept, marker = command.split("\n"), [], None
    for line in lines:
        if marker is not None:
            marker = None if line.strip() == marker else marker
            continue
        found = re.search(r"<<-?\s*(['\"]?)(\w+)\1", line)
        kept.append(line)
        if found:
            marker = found.group(2)
    text = " ; ".join(kept).replace("$(", " ( ").replace("<(", " ( ").replace(">(", " ( ").replace("`", " ( ")
    try:
        lexer = shlex.shlex(text, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        tokens = text.split()
    segments: List[Tuple[str, List[str]]] = [("", [])]
    for token in tokens:
        if token and set(token) <= set("&|;()"):
            segments.append((token, []))
        else:
            segments[-1][1].append(token)
    return [seg for seg in segments if seg[1]]


def strip_prefixes(words: List[str]) -> List[str]:
    """``words`` without leading keywords, ``VAR=value`` words and wrapper programs (and their options)."""
    while words:
        base = os.path.basename(words[0])
        if words[0] in KEYWORDS or re.match(r"^\w+=", words[0]):
            words = words[1:]
        elif base in WRAPPERS:
            words = words[1:]
            while words and (words[0].startswith("-") or re.match(r"^\w+=", words[0]) or re.fullmatch(r"\d+[smhd]?", words[0])):
                words = words[1:]
        else:
            break
    return words


def agent_session(payload: dict) -> bool:
    """Is this an agent session (runner or headless, a ``--agent`` main thread, or a subagent)?"""
    return os.environ.get("FENTON_HEADLESS") == "1" or bool(payload.get("agent_type")) or bool(payload.get("agent_id"))


def review_file(path: str, cwd: str) -> bool:
    """Is ``path`` a verdict file: ``build/review/*.json`` (below any ``build/review``) or under ``~/hass-agents/reviews``?"""
    full = os.path.realpath(path if os.path.isabs(path) else os.path.join(cwd, path))
    return bool(re.search(r"/build/review/[^/]+\.json$", full) or "/hass-agents/reviews/" in full + "/"
                or full.endswith("/build/review") or full == str(IDENT_PATH))


INTERPRETERS = re.compile(r"^(?:python|pypy|node|deno|bun|ruby|perl|php|lua|osascript|sh|bash|zsh|dash|ksh)[\d.]*$")


def runs_record(command: str) -> bool:
    """Does a simple command execute ``tools/review/record.py``: the script as the program, or an interpreter given it as its script? Naming it
    as data (``cat``, ``grep``, ``git add``, ``git show SHA:path``) is not running it."""
    for _op, words in tokenize(command):
        words = strip_prefixes(list(words))
        if not words:
            continue
        names = lambda w: w.replace("\\", "/").endswith("review/record.py") or os.path.basename(w) == "record.py"
        if names(words[0]):
            return True
        if INTERPRETERS.match(os.path.basename(words[0])):
            script = [w for w in words[1:] if not w.startswith("-")][:1]
            if script and names(script[0]):
                return True
    return False


def heredoc_writes_review_path(command: str) -> bool:
    """Does an interpreter read a heredoc whose body names a review path (a script that writes the verdict inline)? The body is data for
    ``cat``, ``git commit`` and ``gh``, so only a line that runs an interpreter counts."""
    lines, index = command.split("\n"), 0
    while index < len(lines):
        found = re.search(r"<<-?\s*(['\"]?)(\w+)\1", lines[index])
        index += 1
        if not found:
            continue
        body = []
        while index < len(lines) and lines[index].strip() != found.group(2):
            body.append(lines[index])
            index += 1
        if not REVIEW_PATH.search("\n".join(body).replace("\\", "/")):
            continue
        for _op, words in tokenize(lines[index - len(body) - 1]):
            stripped = strip_prefixes(list(words))
            if stripped and INTERPRETERS.match(os.path.basename(stripped[0])):
                return True
    return False


RECORD_LINE = re.compile(r"\s*(?:cd\s+(?P<cd>[\w./~+-]+|\"[^\"$`\\\\]*\")\s*&&\s*)?(?:python3?\s+)?(?:\./)?[\w./~-]*review/record\.py"
                         r"(?:\s+(?:[\w./=-]+|\"[^\"$`\\]*\"|'[^']*'))*"
                         r"(?:\s+<<-?\s*(?P<q>['\"]?)(?P<word>\w+)(?P=q))?\s*")


def record_dir(command: str, cwd: str) -> str:
    """The checkout a plain ``record.py`` command records for: ``--root`` (relative to a leading ``cd``), else the ``cd`` target, else ``cwd``."""
    first = command.partition("\n")[0]
    match = RECORD_LINE.fullmatch(first)
    where = cwd
    if match and match.group("cd"):
        target = os.path.expanduser(match.group("cd").strip('"'))
        where = target if os.path.isabs(target) else os.path.join(cwd, target)
    try:
        words = shlex.split(first.split("record.py", 1)[1])
    except (ValueError, IndexError):
        return os.path.realpath(where)
    for index, word in enumerate(words):
        value = words[index + 1] if word == "--root" and index + 1 < len(words) else word[len("--root="):] if word.startswith("--root=") else None
        if value:
            value = os.path.expanduser(value)
            where = value if os.path.isabs(value) else os.path.join(where, value)
    return os.path.realpath(where)


def plain_record(command: str) -> bool:
    """Is ``command`` exactly ``[cd DIR &&] [python3] tools/review/record.py ARGS`` (plain or quoted arguments, ``--root DIR`` among them),
    optionally reading the verdict from a heredoc whose terminator ends the command? Nothing else may chain, redirect or substitute."""
    first, _sep, body = command.partition("\n")
    match = RECORD_LINE.fullmatch(first)
    if not match:
        return False
    word = match.group("word")
    if not word:
        return not body.strip()
    lines = [line for line in body.split("\n")]
    while lines and not lines[-1].strip():
        lines.pop()
    return bool(lines) and lines[-1].strip() == word and word not in [line.strip() for line in lines[:-1]]


#: git subcommands whose words are paths for git or a message, never content written into a verdict.
DATA_GIT = READ_GIT | {"add", "commit", "push", "pull", "fetch", "stash", "branch", "tag"}


def writes_review_path(command: str, cwd: str) -> bool:
    """Does ``command`` write a review path? A mention is not a write: a commit message, ``git add``, a PR or issue body and a heredoc body
    are data (the #370 class). A redirect into the path, or a program that is not a reader, ``git`` data command or ``gh`` body command and
    names the path, still counts."""
    if not REVIEW_PATH.search(command.replace("\\", "/")):
        return False
    if heredoc_writes_review_path(command):
        return True
    for _op, words in tokenize(command):
        for index, word in enumerate(words[:-1]):
            if REDIRECT.match(word) and REVIEW_PATH.search(words[index + 1].replace("\\", "/")):
                return True
        stripped = strip_prefixes(list(words))
        if not stripped or not any(REVIEW_PATH.search(w.replace("\\", "/")) for w in words):
            continue
        program = os.path.basename(stripped[0])
        sub = [w for w in stripped[1:] if not w.startswith("-")][:2]
        if program in READERS or os.path.splitext(program)[0] in READER_SCRIPTS:
            continue
        if program == "git" and sub[:1] and sub[0] in DATA_GIT:
            continue
        if program == "gh" and len(sub) == 2 and sub[0] in ("pr", "issue") and sub[1] in ("create", "comment", "edit", "view", "review"):
            continue
        return True
    return False


def only_reads(command: str) -> bool:
    """Is every simple command of ``command`` a plain reader, with no redirect, substitution or write option?"""
    if re.search(r"[`]|\$\(|[<>]\(", command):
        return False
    segments = tokenize(command)
    if not segments:
        return False
    for _op, words in segments:
        if any(REDIRECT.match(w) for w in words):
            return False
        stripped = strip_prefixes(list(words))
        if not stripped:
            continue
        program = os.path.basename(stripped[0])
        if program == "git":
            sub = [w for w in stripped[1:] if not w.startswith("-")][:1]
            if not sub or sub[0] not in READ_GIT:
                return False
        elif program not in READERS and os.path.splitext(program)[0] not in READER_SCRIPTS:
            return False
    return True


def stamp(payload: dict, where: Optional[str] = None) -> None:
    """Leave the identity of the reviewer about to run ``record.py`` (read by ``record.py``); ``where`` is the checkout it records for."""
    IDENT_PATH.parent.mkdir(parents=True, exist_ok=True)
    data = {"agent_type": payload.get("agent_type"), "session_id": str(payload.get("session_id") or ""),
            "agent_id": str(payload.get("agent_id") or ""), "cwd": os.path.realpath(where or str(payload.get("cwd") or os.getcwd())),
            "at": time.time()}
    IDENT_PATH.write_text(json.dumps(data))
    os.chmod(IDENT_PATH, 0o600)


def reason(payload: dict) -> Optional[str]:
    """Why this tool call may not touch a verdict, or ``None``."""
    tool = payload.get("tool_name")
    tool_input = payload.get("tool_input") or {}
    cwd = str(payload.get("cwd") or os.getcwd())
    if tool in FILE_TOOLS:
        path = str(tool_input.get("file_path") or tool_input.get("notebook_path") or "")
        return "a file tool writing a review verdict" if path and review_file(path, cwd) else None
    if tool != "Bash":
        return None
    command = str(tool_input.get("command") or "")
    if runs_record(command):
        if payload.get("agent_type") != "reviewer":
            return "tools/review/record.py run by a session that is not the reviewer"
        if not plain_record(command):
            return "tools/review/record.py with anything but plain arguments (no chain, redirect or substitution)"
        stamp(payload, record_dir(command, cwd))
        return None
    if writes_review_path(command, cwd):
        return "a command that is not a plain reader writes a review path"
    return None


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if not agent_session(payload):
        return 0
    why = reason(payload)
    if why:
        print(f"{MESSAGE} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
