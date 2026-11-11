#!/usr/bin/env python3
"""PreToolUse hook for Bash: the full journey suite and full coverage are the nightly and release tiers, not a per-change run.

Refuses (exit 2, the message goes back to the model):

* ``tools/ios_uitest.sh`` with no filter: no ``--changed``, no ``-only-testing…`` and no ``--plan Smoke|Capture|Perf|Live``
  (``--plan Gate`` is the whole gate, so it is a full run and is refused too).
* ``tools/apple_coverage.sh`` without ``--changed``.

Allowed anyway when the command carries ``FENTON_TIER=nightly`` or ``FENTON_TIER=release`` (the CI workflows and the release
checklist set it; the hook process's own environment counts too), or ``--full`` together with a ``# full-ok: reason`` comment.
The scripts are found as the program or behind a launcher (``tools/bg_run.py LABEL --``, ``devcap.py run --``, ``env``,
``nohup``, ``time``, ``bash``, ``bash -c '…'``); a ``grep`` or ``cat`` that merely names them is fine.

A heredoc body is skipped only when the whole command is plainly a write to a file (``cat > path <<EOF``, ``cat <<EOF > path``,
``tee path <<EOF``: nothing piped, substituted, continued, chained or run). Any other command is read raw, bodies included, so a
body that could reach a shell (``bash -c "$(cat <<EOF``, ``eval``, ``source /dev/stdin``, ``python3 -``, ``xargs``, a pipe, a
continuation, a file written and then run) is still seen.

``FENTON_HOSTED_FILTER=<literal with a non-space character>`` counts as a filter for ``ios_uitest.sh --hosted`` only as an env
prefix of that same simple command (or after ``env``), or after an earlier ``export`` in the same command. It does not count
when the command has a comment, a heredoc that is not a plain file write, or a value with ``$`` or a backtick.
See .agents/testing/apple/README.md (test tiers) and .agents/workflow/token-economy.md.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from typing import List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_parse import scan_shell, strip_heredocs  # noqa: E402

UITEST = "ios_uitest.sh"
COVERAGE = "apple_coverage.sh"
LAUNCHERS = {"bg_run.py", "devcap.py", "bash", "sh", "zsh", "dash", "nohup", "time", "env", "exec", "command", "nice"}
SPLIT_KEEP = re.compile(r"(&&|\|\||\$\(|[;|&(){}`\n]|\b(?:then|do|else|elif|if|while|until)\b)")
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
TIER = re.compile(r"\bFENTON_TIER=['\"]?(?:nightly|release)\b")
HOSTED_VAR = "FENTON_HOSTED_FILTER"
ASSIGNMENT = re.compile(r"^\w+=")
UNSAFE_WRITE = re.compile(r"[|;&(){}`$\\<]")
HEREDOC_MARK = re.compile(r"<<-?\s*(?:'[^']*'|\"[^\"]*\"|\w+)")
FULL_OK = re.compile(r"#\s*full-ok:\s*\S")
SMALL_PLANS = {"Smoke", "Capture", "Perf", "Live"}


# MARK: - Messages and filters

def message(script: str) -> str:
    if script == UITEST:
        alternative = ("`tools/ios_uitest.sh --changed` (the journeys the diff affects), `-only-testing:FentonHomeUITests/<Class>`, "
                       "or `--plan Smoke|Capture|Perf|Live` for a family a change does not target")
    else:
        alternative = "`tools/apple_coverage.sh --changed` (coverage of the files this change touches)"
    return (f"Blocked: an unfiltered {script} run is the nightly or release tier. Use {alternative}. The full run belongs to "
            "the nightly workflow and the release checklist (FENTON_TIER=nightly|release); if you really need it, add "
            "`--full` and a `# full-ok: <reason>` comment. See .agents/testing/apple/README.md and "
            ".agents/workflow/token-economy.md.")


def valid_filter(word: str) -> bool:
    """Is ``word`` a ``FENTON_HOSTED_FILTER=value`` assignment whose literal value has a non-space character and no expansion?"""
    if not word.startswith(HOSTED_VAR + "="):
        return False
    value = word.split("=", 1)[1]
    return bool(value.strip()) and not re.search(r"[$`]", value)


def prefix_assignments(words: List[str], end: int) -> List[str]:
    """The ``VAR=value`` words that are env prefixes of the command whose program is ``words[end]``: leading ones and those after ``env``."""
    found: List[str] = []
    i = 0
    while i < end and ASSIGNMENT.match(words[i]):
        found.append(words[i])
        i += 1
    for j in range(i, end):
        if os.path.basename(words[j]) == "env":
            k = j + 1
            while k < end and (words[k].startswith("-") or ASSIGNMENT.match(words[k])):
                if ASSIGNMENT.match(words[k]):
                    found.append(words[k])
                k += 1
    return found


def unfiltered(script: str, args: List[str], hosted_filter: bool = False) -> bool:
    """Is this invocation of ``script`` a full run? ``hosted_filter``: a valid ``FENTON_HOSTED_FILTER`` applies to this command."""
    if any(a in ("-h", "--help") for a in args):
        return False
    if hosted_filter and script == UITEST and "--hosted" in args:
        return False
    if script == COVERAGE:
        return "--changed" not in args
    if "--changed" in args or any(a.startswith("-only-testing") for a in args):
        return False
    for i, a in enumerate(args):
        if a == "--plan" and i + 1 < len(args) and args[i + 1] in SMALL_PLANS:
            return False
        if a.startswith("--plan=") and a.split("=", 1)[1] in SMALL_PLANS:
            return False
    return True


# MARK: - Parsing

def words_of(segment: str) -> List[str]:
    """The shell words of ``segment`` (whitespace split when quotes do not balance)."""
    try:
        return shlex.split(segment)
    except ValueError:
        return segment.split()


def segment_script(segment: str) -> Optional[tuple]:
    """``(script, args, nested, assignments)`` when the simple command runs one of the guarded scripts, else ``None``."""
    words = words_of(segment)
    for i, word in enumerate(words):
        if os.path.basename(word) in (UITEST, COVERAGE):
            before = [os.path.basename(w) for w in words[:i]]
            if "-n" in before:  # `bash -n script`: a syntax check, nothing runs
                return None
            core = [w for w in before if not ASSIGNMENT.match(w) and not w.startswith("-")]
            if all(w in LAUNCHERS or w == "" for w in core) or not core:
                return os.path.basename(word), words[i + 1:], None, prefix_assignments(words, i)
            # `bg_run.py LABEL -- script`: a label word sits between the launcher and the script.
            if any(w in LAUNCHERS for w in core) and "--" in words[:i]:
                return os.path.basename(word), words[i + 1:], None, prefix_assignments(words, i)
            return None
    # bash -c '…' carries a command string.
    if words and os.path.basename(words[0]) in ("bash", "sh", "zsh", "dash"):
        for j, w in enumerate(words[1:-1], 1):
            if SHELL_C.match(w):
                return "", [], words[j + 1], []
    return None


def plain_file_write(command: str) -> bool:
    """Is the whole ``command`` only ``cat``/``tee`` writing a heredoc to files, with nothing that could run a body?

    Refuses (returns ``False``) on a pipe, ``;``, ``&``, parentheses, braces, a backtick or ``$`` anywhere in the code, on a
    backslash continuation, on any line that is not ``cat`` or ``tee``, and on a write to ``/dev/…``. A heredoc with no
    file target is not a plain write either.
    """
    if "\\\n" in command or "<<" not in command:
        return False
    lines = [line for line in strip_heredocs(command).split("\n") if line.strip()]
    if not lines:
        return False
    for line in lines:
        text = HEREDOC_MARK.sub("<<H", re.sub(r"\b[12]?>&[12]\b", "", line))
        if text.count("<") != 2 * text.count("<<H") or "<<<" in text:
            return False
        text = text.replace("<<H", "")
        if UNSAFE_WRITE.search(text):
            return False
        try:
            words = shlex.split(text)
        except ValueError:
            return False
        if not words or os.path.basename(words[0]) not in ("cat", "tee"):
            return False
        is_tee = os.path.basename(words[0]) == "tee"
        targets = 0
        i = 1
        while i < len(words):
            word = words[i]
            redirect = re.match(r"^[12]?>>?(.*)$", word)
            if redirect:
                path = redirect.group(1)
                if not path:
                    i += 1
                    path = words[i] if i < len(words) else ""
                if not path or path.startswith(("/dev/", "&")):
                    return False
                targets += 1
            elif word.startswith(("-", "#")):
                pass
            elif is_tee:
                if word.startswith("/dev/"):
                    return False
                targets += 1
            i += 1
        if targets == 0:
            return False
    return True


# MARK: - Decision

def reason(command: str) -> Optional[str]:
    """The refusal text for ``command``, or ``None``."""
    if TIER.search(command) or os.environ.get("FENTON_TIER") in ("nightly", "release"):
        return None
    # Bodies are skipped only for a plain file write; any other heredoc is read raw, as before.
    raw_heredoc = "<<" in command
    if raw_heredoc and plain_file_write(command):
        command = strip_heredocs(command)
        raw_heredoc = False
    # A comment or a raw heredoc body could fake an `export` or an env prefix, so neither lets a filter count.
    trusted = not raw_heredoc and not scan_shell(command)[1]
    exported = False
    parts = SPLIT_KEEP.split(command)
    # parts alternate segment, separator, segment, ...; the separator before a segment says how it was reached.
    for index in range(0, len(parts), 2):
        segment = parts[index]
        opener = parts[index - 1] if index else "\n"
        words = words_of(segment)
        if trusted and words and words[0] == "export" and opener in ("\n", ";", "&&"):
            for word in words[1:]:
                if word.startswith(HOSTED_VAR + "="):
                    exported = valid_filter(word)
        elif words and words[0] == "unset" and HOSTED_VAR in words:
            exported = False
        hit = segment_script(segment)
        if not hit:
            continue
        script, args, nested, assigned = hit
        if nested is not None:
            inner = reason(nested)
            if inner:
                return inner
            continue
        hosted = trusted and (exported or any(valid_filter(a) for a in assigned))
        if unfiltered(script, args, hosted):
            if "--full" in args and FULL_OK.search(command):
                continue
            return message(script)
    return None


def main() -> int:
    """Read the hook payload from stdin; exit 2 with the refusal to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    why = reason(str((payload.get("tool_input") or {}).get("command", "")))
    if why:
        print(why, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
