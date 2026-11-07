"""Shell-text helpers shared by the Bash guard hooks (``kill_guard``, ``worktree_guard``).

Not a shell parser: just enough to split a command line into simple commands without being fooled by comments,
quotes, heredoc bodies and wrappers.

- ``scan_shell`` walks the text once, quote-aware: it separates ``#`` comments from code and drops heredoc bodies.
  A ``<<EOF`` marker counts only outside quotes and comments; a comment inside backticks ends at the closing
  backtick; a heredoc fed to a shell (``bash <<EOF``) is code and stays.
- ``find_override`` finds an override comment (``# kill-ok: reason``) that is a real comment, not text in a quote or
  a heredoc body.
- ``lex`` / ``tokenize`` split the code into words and simple commands (operators ``; && || | &``, parentheses,
  backticks, ``$(``, process substitution ``<(`` and ``>(``, and newlines).
- ``strip_prefixes`` drops keywords, ``VAR=`` words and wrapper programs (``env``, ``sudo``, ``timeout`` …).
"""

from __future__ import annotations

import os
import re
import shlex
from typing import Dict, List, Optional, Pattern, Set, Tuple

#: A ``#`` starts a comment only when it begins a word.
COMMENT_LEADERS = set(" \t\n;|&(`")
HEREDOC_MARK = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")
SHELL_HEREDOC = re.compile(r"\b(?:ba|z|da)?sh\b")
#: Characters that change the scanner's state outside quotes and comments.
_SPECIAL = re.compile(r"[\\'\"`#<\n()]")
_DOUBLE_QUOTED = re.compile(r"[\\\"`$]")
KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "{", "}", "!", "done", "fi", "esac"}
WRAPPERS: Dict[str, Set[str]] = {
    "env": {"-u", "-C", "-S"}, "command": set(), "exec": {"-a"}, "nohup": set(), "time": {"-f", "-o"},
    "sudo": {"-u", "-g", "-C", "-h", "-p", "-r", "-t", "-U"}, "nice": {"-n"}, "builtin": set(), "caffeinate": set(),
    "watch": {"-n", "--interval", "-d", "--differences"},
    "timeout": {"-s", "--signal", "-k", "--kill-after"}, "gtimeout": {"-s", "--signal", "-k", "--kill-after"},
}
#: Wrappers whose first positional word is a duration, not the program.
DURATION_WRAPPERS = {"timeout", "gtimeout"}
XARGS_VALUE = {"-I", "-n", "-L", "-P", "-d", "-E", "-s", "-j", "-J"}
FEEDERS = {"xargs", "parallel"}
SHELLS = {"bash", "sh", "zsh", "dash"}


# MARK: - Comments and heredocs

def scan_shell(text: str, drop_comments: bool = True) -> Tuple[str, List[str]]:
    """``(code, comments)``: comments split out and heredoc bodies removed, in one quote-aware pass.

    A comment starts at an unquoted ``#`` that begins a word (line start, or after whitespace, ``;|&(`` or a
    backtick) and runs to the end of the line, or to the closing backtick when it started inside backticks.
    ``a#b``, ``$#`` and a quoted ``#`` are not comments. A heredoc marker (``<<EOF``, ``<<-EOF``, ``<<'EOF'``,
    ``<<"EOF"``) outside quotes and comments hides the lines up to its delimiter, except when the line also names a
    shell (the body is then code) or sits in ``$(( ))`` arithmetic. A backslash before a newline joins the lines.
    A ``$(...)`` or backtick substitution inside double quotes starts a new context, as in bash: quotes and heredocs
    inside it are parsed fresh, the quoted text keeps a ``$_SUB`` placeholder, and the substitution's commands are
    appended to ``code`` as ``( ... )`` groups so they are scanned too. With ``drop_comments`` false the comments
    stay in ``code`` (``comments`` is still filled).
    """
    comments: List[str] = []
    subs: List[str] = []
    n = len(text)

    def run(i: int, stop: str) -> Tuple[str, int]:
        code: List[str] = []
        quote = ""
        comment: Optional[List[str]] = None
        backtick = False
        pending: List[str] = []
        line_start = i
        depth = 0

        def close_comment() -> None:
            nonlocal comment
            if comment is not None:
                body = "".join(comment)
                comments.append(body)
                if not drop_comments:
                    code.append(body)
                comment = None

        while i < n:
            if comment is not None:
                stops = "\n`" if (backtick or stop == "`") else "\n"
                j = i
                while j < n and text[j] not in stops:
                    j += 1
                comment.append(text[i:j])
                i = j
                close_comment()
                continue
            if quote:
                if quote == '"':
                    m = _DOUBLE_QUOTED.search(text, i)
                    j = m.start() if m else -1
                else:
                    j = text.find("'", i)
                if j < 0:
                    code.append(text[i:])
                    i = n
                    break
                code.append(text[i:j])
                ch = text[j]
                i = j + 1
                if ch == "\\":
                    if i < n:
                        if text[i] == "\n":
                            i += 1
                        else:
                            code.append(ch)
                            code.append(text[i])
                            i += 1
                elif ch == "`":
                    inner, i = run(i, "`")
                    subs.append(inner)
                    code.append("$_SUB")
                elif ch == "$":
                    if text.startswith("(", i):
                        inner, i = run(i + 1, ")")
                        subs.append(inner)
                        code.append("$_SUB")
                    else:
                        code.append(ch)
                else:
                    code.append(ch)
                    quote = ""
                continue
            m = _SPECIAL.search(text, i)
            if not m:
                code.append(text[i:])
                i = n
                break
            j = m.start()
            code.append(text[i:j])
            ch = text[j]
            i = j + 1
            if ch == "\n":
                code.append(ch)
                if pending:
                    for delimiter in pending:
                        while i < n:
                            end = text.find("\n", i)
                            line = text[i:] if end < 0 else text[i:end]
                            i = n if end < 0 else end + 1
                            if line.strip() == delimiter:
                                break
                    pending = []
                line_start = i
            elif ch == "\\":
                if i < n and text[i] == "\n":
                    i += 1
                else:
                    code.append(ch)
                    if i < n:
                        code.append(text[i])
                        i += 1
            elif ch in "'\"":
                quote = ch
                code.append(ch)
            elif ch == "`":
                if stop == "`":
                    close_comment()
                    return "".join(code), i
                backtick = not backtick
                code.append(ch)
            elif ch == "(":
                depth += 1
                code.append(ch)
            elif ch == ")":
                if stop == ")" and depth == 0:
                    close_comment()
                    return "".join(code), i
                depth = max(depth - 1, 0)
                code.append(ch)
            elif ch == "#" and (j == 0 or text[j - 1] in COMMENT_LEADERS):
                comment = ["#"]
            elif ch == "<" and text.startswith("<<", j) and text[j + 2:j + 3] != "<" and (j == 0 or text[j - 1] != "<"):
                mark = HEREDOC_MARK.match(text, j)
                if not mark:
                    code.append(ch)
                    continue
                code.append(mark.group(0))
                i = mark.end()
                end = text.find("\n", i)
                line = text[line_start:] if end < 0 else text[line_start:end]
                if not SHELL_HEREDOC.search(line) and "((" not in line:
                    pending.append(mark.group(2))
            else:
                code.append(ch)
        close_comment()
        return "".join(code), i

    code, _ = run(0, "")
    if subs:
        code += "".join("\n( %s\n)" % s for s in subs)
    return code, comments


def split_comments(text: str) -> Tuple[str, List[str]]:
    """``(code, comments)`` with comments removed (heredoc bodies are removed too, see ``scan_shell``)."""
    return scan_shell(text)


def strip_heredocs(command: str) -> str:
    """``command`` without heredoc bodies; comments stay."""
    return scan_shell(command, drop_comments=False)[0]


def find_override(command: str, override: Pattern[str]) -> bool:
    """Does a real comment (not quoted text, not a heredoc body) match ``override`` at its start?"""
    return any(override.match(c) for c in scan_shell(command)[1])


# MARK: - Words and prefixes

def env_split_value(option: str, words: List[str]) -> Tuple[str, List[str]]:
    """The ``-S`` string of an ``env`` option cluster (``-S``, ``-iS``, ``--split-string=…``) and the words left."""
    if option.startswith("--split-string="):
        return option.split("=", 1)[1], words
    if option == "--split-string":
        return (words[0], words[1:]) if words else ("", words)
    rest = option[option.index("S") + 1:]
    if rest:
        return rest, words
    return (words[0], words[1:]) if words else ("", words)


def strip_prefixes(words: List[str]) -> List[str]:
    """Drop leading shell keywords, ``VAR=value`` words and wrapper programs with their options."""
    while words:
        head = os.path.basename(words[0])
        if words[0] in KEYWORDS or re.match(r"^\w+=", words[0]):
            words = words[1:]
        elif head in WRAPPERS:
            takes_value = WRAPPERS[head]
            words = words[1:]
            while words and (words[0].startswith("-") or re.match(r"^\w+=", words[0])):
                option = words[0]
                words = words[1:]
                if head == "env" and (option == "--split-string" or option.startswith("--split-string=")
                                      or (option.startswith("-") and not option.startswith("--") and "S" in option)):
                    value, words = env_split_value(option, words)
                    try:
                        words = shlex.split(value) + words
                    except ValueError:
                        pass
                    continue
                if head == "env" and re.match(r"^-[A-Za-z]+$", option):
                    # a cluster such as -iu: a value letter at its very end takes the next word
                    if option[-1] in "uC" and words:
                        words = words[1:]
                    continue
                if option in takes_value and words:
                    words = words[1:]
            if head in DURATION_WRAPPERS and words:
                words = words[1:]
        else:
            break
    return words


def unwrap_xargs(args: List[str]) -> List[str]:
    """The command ``xargs`` runs, as ``[program, *args]`` (empty when none)."""
    skip = 0
    while skip < len(args) and args[skip].startswith("-"):
        skip += 2 if args[skip] in XARGS_VALUE else 1
    return strip_prefixes(args[skip:])


# MARK: - Lexing

def relevant_lines(text: str, pattern: Optional[Pattern[str]]) -> str:
    """For a long command keep only lines matching ``pattern`` (and the lines after a trailing backslash)."""
    lines = text.split("\n")
    if pattern is None or len(lines) <= 40:
        return text
    kept, joined = [], False
    for line in lines:
        if joined or pattern.search(line):
            kept.append(line)
        joined = line.endswith("\\")
    return "\n".join(kept)


def lex(command: str, relevant: Optional[Pattern[str]] = None) -> List[str]:
    """Words and operator tokens (``;``, ``&&``, ``|``, ``(``, ``)``, ``>``, ``>>`` …) of ``command``.

    Comments and heredoc bodies are gone. Backticks become a ``(`` and a ``)`` in turn, ``$(``, ``<(`` and ``>(`` become ``(``, and
    newlines become ``;``. ``relevant`` keeps only matching lines of a command longer than 40 lines.
    """
    code, _ = scan_shell(command)
    code = relevant_lines(code, relevant)
    pieces: List[str] = []
    opened = False
    for part in code.split("`"):
        if pieces:
            pieces.append(" ) " if opened else " ( ")
            opened = not opened
        pieces.append(part)
    text = "".join(pieces).replace("$(", " ( ").replace("<(", " ( ").replace(">(", " ( ").replace("\n", " ; ")
    try:
        lexer = shlex.shlex(text, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        lexer.commenters = ""
        return list(lexer)
    except ValueError:
        return text.split()


def is_operator(token: str) -> bool:
    """Is ``token`` a run of command separators (``; && || | & ( )``)?"""
    return bool(token) and set(token) <= set("&|;()")


def tokenize(command: str, relevant: Optional[Pattern[str]] = None) -> List[Tuple[str, List[str]]]:
    """Split ``command`` into simple commands: ``(operator before it, words)``."""
    segments: List[Tuple[str, List[str]]] = [("", [])]
    for token in lex(command, relevant):
        if is_operator(token):
            segments.append((token, []))
        else:
            segments[-1][1].append(token)
    return [seg for seg in segments if seg[1]]


def expand_vars(text: str, cwd: str, project: str, home: str) -> str:
    """Substitute ``$PWD``, ``$CLAUDE_PROJECT_DIR``, ``$HOME``, ``$(pwd)`` and a leading ``~``."""
    for name, value in (("PWD", cwd), ("CLAUDE_PROJECT_DIR", project), ("HOME", home)):
        if value:
            text = re.sub(r"\$\{%s\}|\$%s(?!\w)" % (name, name), lambda _m, v=value: v, text)
    if cwd:
        text = text.replace("$(pwd)", cwd).replace("`pwd`", cwd)
    if home:
        text = re.sub(r"(?<![\w$])~(?=/|\s|$)", lambda _m: home, text)
    return text
