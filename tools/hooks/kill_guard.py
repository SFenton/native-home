#!/usr/bin/env python3
"""PreToolUse hook for Bash: refuse process kills that reach beyond the agent's own work.

This Mac is shared by several agent sessions, the self-hosted Actions runner (``~/actions-runner-hass``), devcap holds
and simulators. On 2026-10-30 a subagent ran ``pkill -f "swift-test|swift-testing|swift-build|xctest"`` and killed the
runner's swift-test job (exit 143). A machine-wide match cannot tell its own processes from anyone else's.

Blocked (exit 2 sends the message back to the model):

- ``pkill`` / ``pgrep`` / ``grep`` (feeding a kill) unless run with ``-f`` and every ``|`` alternative of the pattern
  starts with an absolute path inside the agent's own worktree (the git toplevel of the hook ``cwd``) followed by at
  least one more path character, or inside the scratchpad ``/private/tmp/claude-<uid>/`` (``/tmp/claude-<uid>/``).
  The project root, a sibling lane's worktree, a regex wildcard after the root and a group or alternation around the
  path are never scoped. ``$PWD``, ``${PWD}``, ``$CLAUDE_PROJECT_DIR``, ``$HOME`` and ``~`` are expanded first.
- ``killall`` always (it matches by process name only); ``pkill -P 1`` (launchd's children); ``kill … -1``.
- A pattern naming shared infrastructure (``Runner.Listener``, ``Runner.Worker``, ``actions-runner``, ``devcap``,
  ``Simulator``, ``CoreSimulator``, ``launchd``), even inside a scoped path.
- A kill fed by an unscoped lookup: ``kill $(pgrep …)``, ``kill `pgrep …```, ``pgrep … | xargs kill``,
  ``ps … | grep … | awk … | xargs kill``, and ``kill $p`` in a loop over one. A kill of literal PIDs passes.
- ``xcrun simctl shutdown|erase|delete all`` (devcap owns simulator lifecycle).

Plain ``kill 123`` and ``kill %1`` stay allowed, as does ``pkill -P PID``. The command is split with ``shlex`` into
simple commands on ``; && || | &``, parentheses, backticks and newlines; shell keywords (``then do if {``…), ``sudo``/
``env``/``timeout``/``watch``/``VAR=`` prefixes are stripped, and ``bash -c``/``eval`` strings are scanned too. When
unsure about a broad pattern the hook blocks. A comment ``# kill-ok: reason`` lets a command through.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from typing import List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_parse import (  # noqa: E402
    FEEDERS, SHELLS, XARGS_VALUE, find_override, strip_prefixes, tokenize as _tokenize, unwrap_xargs,
)

MESSAGE = (
    "Blocked: this Mac is shared with other agent sessions, the Actions runner and devcap, so a broad kill can take "
    "down someone else's job. Kill by PID you started (`kill $!`, `kill %1`, `pkill -P PID`), or scope "
    "`pkill -f` to a path under your worktree (`pkill -f \"$PWD/build/...\"`). Never `killall`, never "
    "`simctl shutdown all`. If this really is the intent, add `# kill-ok: reason` to the command. "
    "See .agents/workflow/token-economy.md and .agents/platforms/apple/capacity.md."
)

RELEVANT_LINE = re.compile(r"kill|simctl|grep|eval|\b(?:ba|z|da)?sh\b")
OVERRIDE = re.compile(r"#\s*kill-ok:\s*\S")
ENV_CHDIR = re.compile(r"(?<![\w./-])env\b[^;&|\n]*\s(?:-C|--chdir)\b")
CHDIR = re.compile(r"(?<![\w./-])(?:cd|pushd|popd)(?![\w./-])")
PID_LIKE = re.compile(r"^(?:\d+|%\S*|\$!|\$\$)$")
#: Shared infrastructure. ``Simulator`` is case-sensitive so `Debug-iphonesimulator` build paths stay killable.
INFRA = re.compile(r"(?i:Runner\.?Listener|Runner\.?Worker|actions-runner|devcap|launchd)|Simulator")
SCRATCH = re.compile(r"/(?:private/)?tmp/claude-\d+(?=/[\w@-])")
#: A scoped path must follow one of these (not the tail of a group, class or alternation); ``.*`` is also fine.
PATH_PRECEDERS = {"", " ", "^", "=", '"', "'"}
SIGNAL = re.compile(r"^-(?:\d+|SIG[A-Z0-9]+|[A-Z]{3,}\d*)$")
#: ``pkill``/``pgrep`` options that take a value.
VALUE_OPTS = set("PuUgGtFjcMN")
LONG_VALUE = {"--parent", "--pgroup", "--euid", "--uid", "--group", "--terminal", "--pidfile", "--session"}
GREP_VALUE = {"-e", "-f", "-m", "-A", "-B", "-C"}
AWK_VALUE = {"-F", "-v", "-f"}


# MARK: - Scope

def find_toplevel(cwd: str) -> str:
    """The git toplevel (directory holding ``.git``) at or above ``cwd``, or ``""``."""
    path = os.path.normpath(cwd) if cwd else ""
    while path.startswith("/") and path != "/":
        if os.path.exists(os.path.join(path, ".git")):
            return path
        path = os.path.dirname(path)
    return ""


def roots(cwd: str) -> List[str]:
    """Directories a ``pkill -f`` pattern may point into: the agent's own worktree (the git toplevel of ``cwd``)."""
    top = find_toplevel(cwd)
    if not top and cwd.startswith("/") and len([p for p in cwd.split("/") if p]) >= 3:
        top = os.path.normpath(cwd)
    return [top] if top else []


def expand(command: str, cwd: str, project: str) -> str:
    """Substitute ``$PWD``, ``$CLAUDE_PROJECT_DIR``, ``$HOME``, ``$(pwd)`` and a leading ``~`` so scoping sees paths."""
    home = os.environ.get("HOME", "")
    for name, value in (("PWD", cwd), ("CLAUDE_PROJECT_DIR", project), ("HOME", home)):
        if value:
            command = re.sub(r"\$\{%s\}|\$%s(?!\w)" % (name, name), lambda _m, v=value: v, command)
    if cwd:
        command = command.replace("$(pwd)", cwd).replace("`pwd`", cwd)
    if home:
        command = re.sub(r"(?<![\w$])~(?=/|\s|$)", lambda _m: home, command)
    return command


def alternative_scoped(alt: str, dirs: List[str]) -> bool:
    """Does one regex alternative start with an absolute path inside a scope root, plus a real path component?"""
    for match in SCRATCH.finditer(alt):
        before = alt[:match.start()]
        if before.removesuffix(".*") == "" or before[-1:] in PATH_PRECEDERS:
            return True
    for root in dirs:
        at = alt.find(root)
        while at != -1:
            end = at + len(root)
            before = alt[:at]
            rest = alt[end:]
            leads = before.removesuffix(".*") == "" or before[-1:] in PATH_PRECEDERS
            # `/x` or `/.x` (a hidden directory), not `/.*`, `/(`, `/?` or nothing.
            real = re.match(r"/(?:[\w@-]|\.[\w-])", rest) is not None
            sibling = "/.claude/worktrees" not in root and rest.startswith("/.claude/worktrees")
            if leads and real and not sibling:
                return True
            at = alt.find(root, at + 1)
    return False


def pattern_scoped(pattern: str, dirs: List[str]) -> bool:
    """Is every ``|`` alternative of ``pattern`` anchored to a scope path?"""
    return bool(pattern) and all(alternative_scoped(a, dirs) for a in re.split(r"\\\||\|", pattern))


# MARK: - Parsing

def parse_pattern_cmd(args: List[str]) -> Dict[str, object]:
    """Parse ``pkill``/``pgrep`` arguments.

    Returns ``full`` (-f), ``parent`` (-P/-F given), ``parents`` (the -P values) and ``patterns``.
    """
    full, parent, patterns, parents = False, False, [], []
    i = 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            patterns += args[i:]
            break
        if arg.startswith("--"):
            name = arg.split("=")[0]
            if name == "--full":
                full = True
            elif name in ("--parent", "--pidfile"):
                parent = True
                if name == "--parent":
                    parents.append(arg.split("=", 1)[1] if "=" in arg else (args[i] if i < len(args) else ""))
            if name in LONG_VALUE and "=" not in arg:
                i += 1
            continue
        if arg.startswith("-") and len(arg) > 1:
            if SIGNAL.match(arg):
                continue
            letters = arg[1:].lstrip("0123456789")
            for pos, ch in enumerate(letters):
                if ch == "f":
                    full = True
                if ch in "PF":
                    parent = True
                if ch in VALUE_OPTS:
                    value = letters[pos + 1:]
                    if not value and i < len(args):
                        value = args[i]
                    if ch == "P":
                        parents.append(value)
                    if pos == len(letters) - 1:
                        i += 1
                    break
            continue
        patterns.append(arg)
    return {"full": full, "parent": parent, "parents": parents, "patterns": patterns}


# MARK: - Checks

def is_pid_one(value: str) -> bool:
    """Does a ``-P`` list (``1``, ``01``, ``2,1``) name PID 1?"""
    for part in str(value).split(","):
        if part.strip().isdigit() and int(part) == 1:
            return True
    return False


def check_pattern_cmd(program: str, args: List[str], dirs: List[str]) -> Optional[str]:
    """Why a ``pkill``/``pgrep`` call is too broad, or ``None``."""
    parsed = parse_pattern_cmd(args)
    patterns: List[str] = parsed["patterns"]  # type: ignore[assignment]
    for pattern in patterns:
        if INFRA.search(pattern):
            return f"{program} pattern {pattern!r} names the runner, devcap, a simulator or launchd"
    if any(is_pid_one(v) for v in parsed["parents"]):  # type: ignore[attr-defined]
        return f"{program} -P 1 matches every child of launchd"
    if parsed["parent"]:
        return None
    if not patterns:
        return f"{program} without a pattern, -P or -F"
    if not parsed["full"]:
        return f"{program} matches process names machine-wide (use -f with a path under your worktree)"
    for pattern in patterns:
        if not pattern_scoped(pattern, dirs):
            return f"{program} -f pattern {pattern!r} is not scoped to your worktree or scratchpad"
    return None


def check_filter(program: str, args: List[str], dirs: List[str]) -> Tuple[Optional[str], bool]:
    """``(problem, is_filter)`` for a ``grep``/``awk`` inside a ``ps`` pipeline. ``grep -v`` and an ``awk`` program that
    only prints a column are not filters."""
    pattern: Optional[str] = None
    i = 0
    while i < len(args):
        arg = args[i]
        i += 1
        if program == "grep" and arg.startswith("-") and len(arg) > 1 and not arg.startswith("--"):
            if "v" in arg[1:] and arg not in GREP_VALUE:
                return None, False
            if arg in GREP_VALUE and i < len(args):
                if arg == "-e" and pattern is None:
                    pattern = args[i]
                i += 1
        elif program == "awk" and arg in AWK_VALUE:
            i += 1
        elif arg.startswith("-") and len(arg) > 1:
            continue
        elif pattern is None:
            pattern = arg
    if pattern is None or (program == "awk" and "/" not in pattern and "~" not in pattern):
        return None, False
    if INFRA.search(pattern) or not pattern_scoped(pattern, dirs):
        return f"{program} pattern {pattern!r} feeding a kill is not scoped to your worktree or scratchpad", True
    return None, True


def kill_is_fed(args: List[str], via_xargs: bool) -> bool:
    """Does this ``kill`` take PIDs from somewhere other than literals (substitution, variable, ``xargs``)?"""
    if via_xargs:
        return True
    positional, i = [], 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg in ("-s", "-n") and i < len(args):
            i += 1
        elif arg == "--":
            positional += args[i:]
            break
        elif arg.startswith("-") and len(arg) > 1:
            continue
        else:
            positional.append(arg)
    return not positional or any(not PID_LIKE.match(p) for p in positional)


def scan(command: str, dirs: List[str], depth: int = 0) -> Optional[str]:
    """Why ``command`` is a broad kill, or ``None``."""
    lookup_problem: Optional[str] = None
    fed_kill = False
    ps_chain = ps_piped = filter_ok = unfiltered = False
    for operator, words in _tokenize(command, RELEVANT_LINE):
        piped = operator in ("|", "|&")
        if not piped:
            unfiltered = unfiltered or (ps_piped and not filter_ok)  # close the previous pipeline
            ps_chain = ps_piped = filter_ok = False
        elif ps_chain:
            ps_piped = True
        words = strip_prefixes(words)
        via_xargs = bool(words) and os.path.basename(words[0]) in FEEDERS
        if via_xargs:
            words = unwrap_xargs(words[1:])
        if not words:
            continue
        program, args = os.path.basename(words[0]), words[1:]
        if program in SHELLS and depth < 3:
            for i, arg in enumerate(args[:-1]):
                if re.match(r"^-[A-Za-z]*c[A-Za-z]*$", arg):
                    inner = scan(args[i + 1], dirs, depth + 1)
                    if inner:
                        return inner
        elif program == "eval" and depth < 3:
            inner = scan(" ".join(args), dirs, depth + 1)
            if inner:
                return inner
        elif program == "killall":
            return "killall matches by process name on the whole machine"
        elif program == "pkill":
            why = check_pattern_cmd("pkill", args, dirs)
            if why:
                return why
        elif program == "pgrep":
            lookup_problem = lookup_problem or check_pattern_cmd("pgrep", args, dirs)
        elif program == "ps":
            ps_chain = True
        elif program in ("grep", "awk") and ps_chain:
            problem, is_filter = check_filter(program, args, dirs)
            lookup_problem = lookup_problem or problem
            filter_ok = filter_ok or (is_filter and problem is None)
        elif program == "pidof":
            lookup_problem = lookup_problem or "pidof matches by process name machine-wide"
        elif program == "find" and any(a in ("-exec", "-execdir", "-ok", "-okdir") for a in args) and depth < 3:
            at = min(i for i, a in enumerate(args) if a in ("-exec", "-execdir", "-ok", "-okdir"))
            inner = scan(shlex.join(args[at + 1:]), dirs, depth + 1)
            if inner:
                return inner
        elif program == "kill":
            if args and args[-1] == "-1":
                return "kill -1 signals every process you own"
            fed_kill = fed_kill or kill_is_fed(args, via_xargs)
        elif program == "simctl" or (program == "xcrun" and "simctl" in args):
            for verb in ("shutdown", "erase", "delete"):
                if verb in args and "all" in args[args.index(verb) + 1:]:
                    return f"simctl {verb} all hits every session's simulators (devcap owns their lifecycle)"
    unfiltered = unfiltered or (ps_piped and not filter_ok)
    if fed_kill and (lookup_problem or unfiltered):
        return f"kill fed by a broad lookup: {lookup_problem or 'ps output with no scoped filter'}"
    return None


def reason(command: str, cwd: str = "") -> Optional[str]:
    """Why ``command`` is a broad kill, or ``None``."""
    if find_override(command, OVERRIDE):
        return None
    dirs = roots(cwd)
    project = os.environ.get("CLAUDE_PROJECT_DIR", "")
    # After a cd/pushd/popd, $PWD and $(pwd) no longer name the hook's cwd, so leave them unexpanded (unscoped).
    return scan(expand(command, "" if CHDIR.search(command) or ENV_CHDIR.search(command) else cwd, project), dirs)


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    command = str((payload.get("tool_input") or {}).get("command", ""))
    if not re.search(r"kill|simctl", command):
        return 0
    why = reason(command, str(payload.get("cwd") or os.getcwd()))
    if why:
        print(f"{MESSAGE} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
