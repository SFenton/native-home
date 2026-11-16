#!/usr/bin/env python3
"""PreToolUse hook for Bash, Read, Grep, Glob, Edit, Write, MultiEdit and NotebookEdit: the owner's Studio is reached only through ``tools/studio_publish.py``.

Owner decision 2026-11-16: agents may publish a finished change to the Studio draft, but only by ``tools/studio_publish.py``. Port 4801 runs
local-only with no token (owner choice, 2026-11-16), so any local process could publish to the house with the Studio's own Home Assistant
credential; this guard is what stops another agent process. It is a tripwire, not a wall: it reads command text only.

Acts on **agent sessions** (``FENTON_HEADLESS=1``, or a payload with ``agent_type`` or ``agent_id``); the owner's plain terminal is never blocked.

Blocked, in an agent session:

- **File tools** (Read, Grep, Glob, Edit, Write, MultiEdit, NotebookEdit) on a path with a ``native-v2`` segment, the ``.studio.lock`` file, or
  a ``data`` folder inside a Studio checkout (``ha-native-home-app``, ``studio-releases``): the Studio's data directory holds the draft and
  the house layout, and the server keeps the draft in memory, so a file edit is overwritten or corrupts the next start.
- **Bash**, per simple command (quote-aware; ``bash -c`` and ``eval`` strings, ``xargs`` and wrappers unwrapped), any word that names the Studio's
  write or publish routes (``/native/api/draft``, ``ha/publish``, ``ha/rollback``, ``ha/restore-draft``, ``ha/start-from-published``,
  ``/native/api``), whatever the program; a word naming a Studio port (``:4800``, ``:4801``, ``:4819``) when the program is a network client or an
  interpreter (curl, wget, httpie, nc, python, node, ...); a word that names ``native-v2`` or ``.studio.lock`` (a bare ``native-v2`` is allowed as
  a search pattern); ``$DATA_DIR`` expanded.
- **Exempt:** ``python3 [-I] <this checkout>/tools/studio_publish.py <sub> ...`` as the whole simple command. Of its subcommands ``apply``, ``publish``
  and ``rollback`` run only for ``agent_type`` ``orchestrator`` or ``menial`` (lanes build changes; the dispatched publish step publishes) and never
  in a headless session; ``status`` and ``check`` run for every agent.

Prose in a ``git commit -m`` or ``gh --body`` value, and the text of a heredoc, is not read. Same limits as ``signing_guard``: a path or URL built at run
time, a script file that opens the URL, and a Write whose content runs later are not seen. Exit 2 sends the message back.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_parse import SHELLS, strip_prefixes, tokenize, unwrap_xargs  # noqa: E402

try:  # the registry of T3-launched triage sessions: a registered session gets the runner's markers
    import triage_session
except Exception:  # noqa: BLE001
    triage_session = None

MESSAGE = (
    "Blocked: the owner's Studio draft and publication change only through `python3 tools/studio_publish.py` "
    "(status, check, apply, publish, rollback), run by the dispatched publish step. Do not call the Studio API or touch its data directory "
    "yourself. If the tool cannot do what you need, report `needs_decision`."
)
TOOL = "studio_publish.py"
PATH_TOOLS = ("Read", "Grep", "Glob", "Edit", "Write", "MultiEdit", "NotebookEdit")
#: Subcommands that change the draft or the live publication; roles that may run them.
MUTATING = ("apply", "publish", "rollback")
PUBLISHERS = ("orchestrator", "menial")

ROUTE = re.compile(r"/?native/api(?![A-Za-z0-9_-])|(?<![A-Za-z0-9_])ha/(?:publish|rollback|restore-draft|start-from-published)(?![A-Za-z0-9_-])", re.I)
PORT = re.compile(r":(?:4800|4801|4819)(?![0-9])")
PORT_WORD = re.compile(r"^(?:4800|4801|4819)$")
NATIVE_V2 = re.compile(r"native-v2[/\\]|[/\\]native-v2", re.I)
BARE_NATIVE_V2 = re.compile(r"^native-v2$", re.I)
LOCK = re.compile(r"\.studio\.lock", re.I)
DATA_DIR_VAR = re.compile(r"\$\{?DATA_DIR(?![A-Za-z0-9_])")
#: The data folder at the root of a Studio checkout only (``<checkout>/data``): source folders such as ``src/workspace2/data`` stay open.
STUDIO_DATA = re.compile(r"(?:ha-native-home-app|studio-releases)(?:[/\\][^/\\]+)?[/\\]data(?:[/\\]|$)", re.I)
#: A word that names the tool (``-m tools.studio_publish``, ``import studio_publish``, ``tools/studio_publish.py``) but not ``test_studio_publish``.
TOOL_WORD = re.compile(r"(?<![A-Za-z0-9_])studio_publish(?![A-Za-z0-9_])")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)(?:\n\s*\2\s*(?:\n|$)|\Z)", re.S)
#: Programs that run code or other programs: a word naming the tool is refused for them unless it is the exact exempt form.
RUNNERS = {"uv", "uvx", "pipx", "poetry", "pdm", "hatch", "tox", "pytest", "make", "just", "npm", "pnpm", "yarn"}
#: Searchers and git read text; a route named as their pattern is not a call.
SEARCH_ONLY = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "git"}
NETWORK = {"curl", "wget", "http", "https", "xh", "httpie", "nc", "ncat", "netcat", "telnet", "socat", "ssh", "node", "nodejs", "deno",
           "bun", "ruby", "perl", "php", "npx", "tsx", "ts-node", "pwsh", "osascript", "python", "python2", "python3", "lua", "go"}
SEARCHERS = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "sed", "awk"}
PROSE_OPTIONS = {"-m", "--message", "--body", "-b", "--title", "-t", "--notes", "--note", "--subject"}
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")


def agent_session(payload: dict) -> bool:
    """Is this an agent session (headless, or a payload with ``agent_type`` or ``agent_id``)?"""
    return os.environ.get("FENTON_HEADLESS") == "1" or bool(payload.get("agent_type")) or bool(payload.get("agent_id"))


def program_of(base: str) -> str:
    """The program name with a version suffix dropped (``python3.11`` -> ``python3``)."""
    return re.sub(r"(?<=\D)[0-9.]+$", "", base) if base.startswith("python") else base


def is_tool_call(words: List[str], project: str) -> Optional[List[str]]:
    """The tool's arguments (subcommand first) when ``words`` is exactly ``python3 [-I] <this checkout>/tools/studio_publish.py ...``, else ``None``."""
    if not words or not program_of(os.path.basename(words[0])).startswith("python"):
        return None
    rest = [w for i, w in enumerate(words[1:]) if not (i == 0 and w == "-I")]
    if not rest:
        return None
    given = os.path.expanduser(rest[0])
    script = os.path.realpath(given if os.path.isabs(given) else os.path.join(project or os.getcwd(), given))
    if os.path.basename(script) != TOOL:
        return None
    if project and script != os.path.realpath(os.path.join(project, "tools", TOOL)):
        return None
    return rest[1:]


def tool_reason(args: List[str], payload: dict) -> str:
    """Why a call of the tool is refused: a mutating subcommand outside the publisher roles, or an unknown subcommand."""
    words = [a for a in args if not a.startswith("-")]
    # argparse takes global options (``--log PATH``, and abbreviations of it) before the subcommand: any mutating word is a mutating call.
    sub = next((a for a in words if a in MUTATING), "") or next((a for a in words if a in ("status", "check")), "")
    if sub in MUTATING:
        if os.environ.get("FENTON_HEADLESS") == "1" or payload.get("agent_type") not in PUBLISHERS:
            return f"`{sub}` runs only in the orchestrator's dispatched publish step"
    elif sub not in ("status", "check"):
        return "unknown studio_publish subcommand"
    return ""


def words_reason(words: List[str], payload: dict, project: str, depth: int = 0, interp: bool = False) -> str:
    """Why one simple command is refused (empty when it passes)."""
    words = strip_prefixes(words)
    if not words or depth > 3:
        return ""
    base = os.path.basename(words[0])
    program = program_of(base)
    args = is_tool_call(words, project)
    if args is not None:
        return tool_reason(args, payload)
    if base == TOOL:  # run directly (``./tools/studio_publish.py``): the same exemption, from this checkout only
        given = os.path.expanduser(words[0])
        script = os.path.realpath(given if os.path.isabs(given) else os.path.join(project or os.getcwd(), given))
        if project and script == os.path.realpath(os.path.join(project, "tools", TOOL)):
            return tool_reason(words[1:], payload)
        return "a copy of studio_publish.py outside this checkout"
    if (program in NETWORK or program in RUNNERS or program in SHELLS) and any(TOOL_WORD.search(w) for w in words[1:]):
        return "studio_publish named other than as `python3 [-I] tools/studio_publish.py <sub>`"
    if program == "xargs":
        return words_reason(unwrap_xargs(words[1:]), payload, project, depth + 1)
    if program in SHELLS or program == "eval":
        for i, w in enumerate(words[1:], 1):
            if (program == "eval" and i == 1) or (program in SHELLS and SHELL_C.match(words[i - 1] if i else "")):
                for _op, inner in tokenize(w):
                    why = words_reason(inner, payload, project, depth + 1)
                    if why:
                        return why
        if program == "eval":
            for _op, inner in tokenize(" ".join(words[1:])):
                why = words_reason(inner, payload, project, depth + 1)
                if why:
                    return why
    searcher = program in SEARCHERS
    reads_text = program in SEARCH_ONLY
    prose = False
    network = program in NETWORK
    for i, word in enumerate(words[1:], 1):
        if prose:
            prose = False
            continue
        if word in PROSE_OPTIONS:
            prose = True
            continue
        if ROUTE.search(word) and not reads_text:
            return "a Studio API route"
        if (network or interp) and not reads_text and (PORT.search(word) or PORT_WORD.match(word)):
            return "a Studio port"
        if NATIVE_V2.search(word) or LOCK.search(word):
            return "the Studio's data directory"
        if BARE_NATIVE_V2.match(word) and not searcher:
            return "the Studio's data directory"
        if DATA_DIR_VAR.search(word) or STUDIO_DATA.search(word):
            return "the Studio's data directory"
    return ""


def runs_code(words: List[str]) -> bool:
    """Does this simple command run code (an interpreter, a shell, a network client or a task runner)?"""
    words = strip_prefixes(words)
    if not words:
        return False
    program = program_of(os.path.basename(words[0]))
    return program in NETWORK or program in SHELLS or program in RUNNERS


def command_reason(command: str, payload: dict, project: str) -> str:
    """Why a Bash command is refused (empty when it passes).

    A heredoc body is code when the command runs an interpreter (``python3 - <<EOF``, ``node``): its text is read for routes, ports, the data
    directory and the tool's name. A port named in a command line that also runs code (``echo '...:4801...' | python3 -``) counts too."""
    segments = tokenize(command)
    interp = any(runs_code(words) for _op, words in segments)
    for _op, words in segments:
        why = words_reason(words, payload, project, interp=interp)
        if why:
            return why
    if interp:
        for match in HEREDOC.finditer(command):
            body = match.group(3)
            if ROUTE.search(body) or PORT.search(body) or NATIVE_V2.search(body) or LOCK.search(body) or TOOL_WORD.search(body) or DATA_DIR_VAR.search(body):
                return "a heredoc fed to an interpreter names the Studio"
    return ""


def path_reason(tool_input: dict) -> str:
    """Why a file tool is refused: the path (``~`` and symlinks resolved) is in the Studio's data directory."""
    path = str(tool_input.get("file_path") or tool_input.get("notebook_path") or tool_input.get("path") or "")
    pattern = str(tool_input.get("pattern") or "")
    for text in (path, os.path.realpath(os.path.expanduser(path)) if path else "", pattern):
        if text and (NATIVE_V2.search(text) or LOCK.search(text) or STUDIO_DATA.search(text)):
            return "the Studio's data directory"
    return ""


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if triage_session:
        triage_session.apply(payload)
    tool = payload.get("tool_name")
    if tool not in ("Bash", *PATH_TOOLS) or not agent_session(payload):
        return 0
    tool_input = payload.get("tool_input") or {}
    project = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or str(payload.get("cwd") or os.getcwd()))
    if tool == "Bash":
        why = command_reason(str(tool_input.get("command") or ""), payload, project)
    else:
        why = path_reason(tool_input)
    if why:
        print(f"{MESSAGE} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
