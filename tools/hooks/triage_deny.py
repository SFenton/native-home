#!/usr/bin/env python3
"""PreToolUse hook: the deny list of a T3-launched triage session, read from its registry record (``triage_session``).

A headless runner session takes its deny list from ``--disallowedTools``; a T3 session cannot, so this hook enforces the record's ``deny``
list (``agent.disallowed_tools`` plus the request-repo rules, resolved by the runner) with the same rule syntax (``deny_rules``). A session
with no record is untouched (exit 0). A record that cannot be trusted is *strict*: every tool call is refused.

Two rules are built in, so a record cannot leave them out: the T3 MCP toolkit (``mcp__t3-code__*``, which can start and message other
threads that would have no record) except the four device tools, and the registry itself (``hass-agents/t3``) for Bash, Read, Write and Edit.

Every failure, an import error included, is exit 2: this hook never lets a call through because it broke.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import fnmatch
    import json
    import os
    import posixpath
    import re

    import deny_rules
    import shell_parse
    import triage_session
except Exception as error:  # noqa: BLE001 - fail closed even if a sibling module cannot be imported
    print(f"Blocked: triage_deny could not import its modules ({type(error).__name__}); refusing (fails closed).", file=sys.stderr)
    sys.exit(2)

#: Always in force for a registered session (see the module docstring).
BASELINE_DENY = (
    "mcp__t3-code__*",
    "!mcp__t3-code__device_list", "!mcp__t3-code__device_open", "!mcp__t3-code__device_screenshot", "!mcp__t3-code__device_close",
)

#: Programs that change or run things; a command using one on ``hass-agents`` (outside the folders sessions work in) is refused.
DESTRUCTIVE = frozenset({
    "rm", "rmdir", "unlink", "mv", "cp", "ln", "install", "rsync", "ditto", "tee", "dd", "truncate", "shred", "chmod", "chown", "touch", "mkdir",
    "sed", "perl", "ruby", "node", "python", "python3", "awk", "gawk", "find", "xargs", "git", "tar", "unzip", "cat", "echo", "printf", "sh",
    "bash", "zsh", "eval", "source", "."})
#: Folders under ``~/hass-agents`` that sessions use in ordinary work.
WORK_FOLDERS = ("worktrees", "work", "status", "logs", "requests", "repos")
TOKEN = re.compile(r"[^\s;&|()<>'\"`=,{}]+")


def registry_dirs() -> list:
    """The registry folder as spelled and as resolved, casefolded."""
    root = triage_session.registry_root()
    return list(dict.fromkeys(str(p).rstrip("/").casefold() for p in (root, Path(os.path.realpath(root)))))


def _normal(token: str, cwd: str, home: str) -> str:
    """A word as an absolute, casefolded, normalised path: ``~`` and ``$HOME`` expanded, ``//``, ``/./`` and ``..`` collapsed."""
    text = re.sub(r"\$\{?HOME\}?", home, token)
    if text == "~" or text.startswith("~/"):
        text = home + text[1:]
    if not text.startswith("/"):
        text = posixpath.join(cwd, text)
    return posixpath.normpath(text).casefold()


def registry_reason(tool: str, tool_input: dict, cwd: str) -> str:
    """Why this call touches the registry (``~/hass-agents/t3``), or ``""``. Best effort and over-blocking: the runner's end-of-session
    ``triage_session.verify`` is what detects a record that was still removed or edited.

    Path tools: the normalised and the resolved path, case-insensitively, inside the registry (a Grep or Glob rooted above it too).
    Bash: any word that, once spelled out, is the registry, is inside it, or is a glob that matches it; and any command that names
    ``hass-agents`` outside the work folders together with a program that changes or runs things, or a redirect or ``-delete``."""
    roots = registry_dirs()
    home = os.path.expanduser("~")
    if tool != "Bash":
        for path in deny_rules.tool_paths(tool, tool_input, cwd):
            low = path.casefold().rstrip("/")
            for root in roots:
                if low == root or low.startswith(root + "/") or (tool in ("Grep", "Glob") and root.startswith(low + "/")):
                    return "the registry of triage sessions (hass-agents/t3)"
        return ""
    command = tool_input.get("command")
    if not isinstance(command, str):
        return ""
    hass, work = [], []
    for token in TOKEN.findall(command):
        low = _normal(token, cwd, home)
        globby = any(c in token for c in "*?[")
        for root in roots:
            if low == root or low.startswith(root + "/") or (globby and (fnmatch.fnmatchcase(root, low) or fnmatch.fnmatchcase(root + "/x.json", low))):
                return "the registry of triage sessions (hass-agents/t3)"
        parts = low.split("/")
        if "hass-agents" in parts or (globby and any(fnmatch.fnmatchcase("hass-agents", seg) for seg in parts if seg)):
            under = parts[parts.index("hass-agents") + 1:2 + parts.index("hass-agents")] if "hass-agents" in parts else []
            (work if under and under[0] in WORK_FOLDERS else hass).append(token)
    if hass:
        programs = {posixpath.basename(words[0]).casefold() for _op, words in shell_parse.tokenize(command)
                    for words in [shell_parse.strip_prefixes(list(words)) or words]}
        if programs & DESTRUCTIVE or re.search(r"(?<![<>=\d])>|-delete|-exec", command):
            return "hass-agents together with a program that changes things, or a redirect"
    return ""


def message(why: str) -> str:
    """The text sent back with a refusal."""
    return (f"Blocked: {why}. This is an unattended triage session started through T3 Code; its deny list is enforced by "
            "tools/hooks/triage_deny.py from the runner's registry record. Do not look for a way around it: pick another approach, "
            "or finish and report the blocker in the status file.")


def main() -> int:
    """Read the hook payload from stdin; exit 2 with the message to block, 0 to allow."""
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            raise ValueError("payload is not an object")
        found = triage_session.resolve(os.environ, payload)
        if found is None:
            return 0
        if found.strict:
            print(message(f"the session's registry record cannot be trusted ({found.reason}); every tool call is refused"), file=sys.stderr)
            return 2
        tool = payload.get("tool_name")
        tool_input = payload.get("tool_input")
        if not isinstance(tool, str) or not isinstance(tool_input, dict):
            raise ValueError("no tool name or input")
        project = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
        cwd = payload.get("cwd") or project
        rule = deny_rules.decide([*BASELINE_DENY, *found.deny], tool, tool_input, project, cwd)
        guarded = registry_reason(tool, tool_input, cwd)
        if guarded:
            rule = guarded
    except Exception as error:  # noqa: BLE001 - fail closed
        print(message(f"the call could not be checked ({type(error).__name__})"), file=sys.stderr)
        return 2
    if rule:
        print(message(f"{tool} is on the session's deny list (rule: {rule})"), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
