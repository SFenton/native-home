#!/usr/bin/env python3
"""PreToolUse hook (Bash, Read, Grep, Glob, Edit, Write, MultiEdit, NotebookEdit): agents cannot forge the owner's prompt log.

Owner decision 2026-11-04: the landing gate counts an ``Owner's request:`` quote that matches a prompt in
``~/hass-agents/owner-prompts/`` (written by ``tools/hooks/owner_prompt_log.py``). A forged row would make an agent's own text
look like the owner's request, so, in **every** session (the owner's main thread carries ``agent_type`` too, and may not need
the log; there is no way to tell it from an agent's and nothing is lost by refusing):

* **Bash** whose raw text contains ``owner-prompts`` (case-insensitive) is refused. Raw text, no shell lexing: quoting,
  variables and wrappers do not matter, only the literal name.
  So is a glob that can match the folder name (``~/hass-agents/owner*``, ``~/hass-agents/*``).
* **Bash** where one simple command (raw text split at ``;``, ``&&``, ``||``, ``|``, ``&`` and newlines) launches ``claude``,
  ``claude-code`` or ``@anthropic-ai/claude-code`` (also through ``ssh``, ``env``, ``npx`` or ``sudo``) with ``-p`` or
  ``--print`` is refused unless it passes ``--agent <name>`` where ``<name>`` is a role in ``.claude/agents`` (``--agent ""``
  and a missing name do not count). A bare ``claude -p`` is a plain session with no agent identity. The log hook has its own
  check for a ``claude -p --agent orchestrator`` that gets past this one (it reads the session's environment).
* **Read, Grep, Glob, Edit, Write, MultiEdit, NotebookEdit** of a path that resolves (``realpath``, case-folded, ``~``
  expanded) into the folder, or for Grep and Glob rooted at ``/``, ``/Users``, the home folder or ``~/hass-agents`` (a
  recursive search would read it), or whose pattern names ``owner-prompts`` or is a glob that can match it, is refused.

Quoted prose is refused too, on purpose: a commit message, ``grep`` pattern or ``echo`` that merely mentions ``owner-prompts``
is blocked in every session, because a raw scan cannot tell prose from a path. That is the tripwire's price; say "the prompt
log" instead.

Limit (owner, 2026-11-02: agents run as the owner's macOS user): this is a tripwire, not a boundary. A path built from variables,
a script that opens the file, or a ``claude`` renamed to something else gets past it; each is a deliberate act. The runner's deny
list in ``tools/triage/config.json`` carries the same folder. Exit 2 sends the message back. Standard library only.
"""

from __future__ import annotations

import fnmatch
import json
import os
import re
import sys
from pathlib import Path
from typing import List, Optional

NAME = "owner-prompts"
MESSAGE = ("Blocked: the owner's prompt log is written only by the UserPromptSubmit hook, and a plain `claude -p` run would be "
           "logged as the owner. Agents never read, write or name ~/hass-agents/owner-prompts, and launch `claude -p` only "
           "with `--agent <role>`. See .agents/workflow/agent-roster.md (what code enforces today).")
PATH_TOOLS = ("Read", "Grep", "Glob", "Edit", "Write", "MultiEdit", "NotebookEdit")
PATH_KEYS = ("file_path", "path", "notebook_path")
NAME_KEYS = PATH_KEYS + ("pattern", "glob")  # file contents (new_string, content) may mention the name: docs do
#: ``claude`` as a command word: after a start, space, ``/``, quote, ``;``, ``&``, ``|``, ``(`` or backtick; not ``claude-foo``.
CLAUDE_WORD = re.compile(r"""(?:^|[\s/'";&|(`@])claude(?:-code)?(?![\w.-])""")  # also npx @anthropic-ai/claude-code
#: Separators that end one simple command in raw text (no quote handling: a ``;`` inside a prompt only splits it, which at worst
#: misses a ``claude "a; b" -p``: the documented tripwire limit). Each simple command is judged alone, so
#: ``grep -c claude x; mkdir -p out`` is not a ``claude -p``.
SEPARATORS = re.compile(r"&&|\|\||[;|&\n]")
#: ``hass-agents/<first component>`` in raw text; a glob there that can match the folder name is refused.
AGENTS_COMPONENT = re.compile(r"""hass-agents/+([^/\s'"]*)""", re.I)
PRINT_FLAG = re.compile(r"(?<![\w-])(?:--print|-p|-[A-Za-z]*p[A-Za-z]*)(?![\w-])")
AGENT_FLAG = re.compile(r"""--agent(?:\s+|=)(?:["']?)([A-Za-z][\w-]*)""")


def roles() -> set:
    """Role names: the ``.claude/agents/*.md`` stems of the project."""
    base = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[2])
    return {p.stem for p in (base / ".claude" / "agents").glob("*.md")}


def log_root(home: Optional[str] = None) -> str:
    return os.path.realpath(os.path.join(home or os.path.expanduser("~"), "hass-agents", NAME)).casefold()


def bash_reason(command: str, known: Optional[set] = None) -> Optional[str]:
    """Why ``command`` (raw text) is refused, or ``None``."""
    if NAME in command.casefold():
        return f"names {NAME}"
    if glob_reaches(command):
        return f"a glob that reaches {NAME}"
    for simple in SEPARATORS.split(command):
        for match in CLAUDE_WORD.finditer(simple):
            rest = simple[match.end():]
            if PRINT_FLAG.search(rest):
                role = AGENT_FLAG.search(rest)
                if not role or role.group(1) not in (roles() if known is None else known):
                    return "claude -p without --agent <role>"
    return None


def glob_reaches(text: str) -> bool:
    """Does ``text`` name ``hass-agents/<glob>`` where the glob can match the folder name (``owner*``, ``*``, ``o?ner-prompts``)?"""
    for component in AGENTS_COMPONENT.findall(text):
        if re.search(r"[*?\[{]", component) and fnmatch.fnmatchcase(NAME, component.casefold().replace("{", "[").replace("}", "]")):
            return True
    return False


def path_reason(tool_input: dict, home: Optional[str] = None) -> Optional[str]:
    """Why a path tool's input is refused, or ``None``."""
    if any(NAME in str(tool_input.get(k) or "").casefold() for k in NAME_KEYS):
        return f"names {NAME}"
    if glob_reaches(str(tool_input.get("pattern") or "") + " " + str(tool_input.get("glob") or "")):
        return f"a pattern that reaches {NAME}"
    root = log_root(home)
    base = os.path.realpath(home or os.path.expanduser("~")).casefold()
    agents = os.path.realpath(os.path.join(home or os.path.expanduser("~"), "hass-agents")).casefold()
    for key in PATH_KEYS:
        value = tool_input.get(key)
        if not isinstance(value, str) or not value:
            continue
        real = os.path.realpath(os.path.expanduser(value)).casefold()
        if real == root or real.startswith(root + os.sep):
            return f"{key} is inside {NAME}"
        if real in (agents, base, os.path.dirname(base), os.sep, "/users") and key == "path":
            return "a search rooted at /, /Users, the home folder or ~/hass-agents reaches " + NAME
    return None


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    tool = payload.get("tool_name")
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict) or tool not in ("Bash", *PATH_TOOLS):
        return 0
    why = bash_reason(str(tool_input.get("command") or "")) if tool == "Bash" else path_reason(tool_input)
    if why:
        print(f"{MESSAGE} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
