"""Claude Code permission-rule matching for the deny list of a registered triage session (the hook form of ``--disallowedTools``).

Rule syntax (the same the runner's ``agent.disallowed_tools`` uses):

* ``Tool``: every use of the tool (``Artifact``, ``AskUserQuestion``); ``*`` in a tool name matches any run of characters
  (``mcp__t3-code__*``).
* ``Bash(pattern)``: ``*`` matches any run of characters (newlines included), anchored at both ends. The pattern is tried against the
  whole command line (comments and heredoc bodies removed, so a quoted body that merely mentions a command is not a command) **and**
  against every simple command in it (``shell_parse.tokenize``), plain, without its wrappers and ``VAR=`` words
  (``strip_prefixes``), and with the program's directory dropped. Commands handed to a shell (``bash -c "..."``, ``eval``) and to
  ``xargs`` are checked again from the inside. Over-blocking is the safe error here.
* ``Read(pattern)``, ``Write(pattern)``, ``Edit(pattern)``: a path pattern. ``//abs/path`` is absolute, ``~/x`` is under the home folder,
  ``/x`` and ``x`` are relative to the project directory; ``*`` stays inside one path segment, ``**`` crosses them. The real path of the
  tool's ``file_path``, ``notebook_path`` or ``path`` is matched, case-insensitively. ``Read`` rules cover Read, Grep and Glob; ``Write`` and
  ``Edit`` rules cover Write, Edit, MultiEdit and NotebookEdit. (Known gap: a suffix-only Read rule such as ``*.pem`` has no fixed folder, so a Grep in content mode over a folder outside the home and config roots is not refused; Bash reads those types without a rule anyway.) A Grep or Glob rooted above the fixed part of a rule's pattern (the home
  folder, for a rule under ``~/.config``) is refused too.
* ``!rule`` (a leading ``!``): an exception. A use that a ``!`` rule matches is allowed even when another rule matches.

Standard library only apart from ``shell_parse``.
"""

from __future__ import annotations

import os
import re
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple

import shell_parse

READ_TOOLS = ("Read", "Grep", "Glob", "NotebookRead")
EDIT_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")
#: Which tools a path rule named ``Read``, ``Write`` or ``Edit`` covers.
PATH_RULE_TOOLS: Dict[str, Tuple[str, ...]] = {"Read": READ_TOOLS, "Write": EDIT_TOOLS, "Edit": EDIT_TOOLS}
PATH_KEYS = ("file_path", "notebook_path", "path")
RULE = re.compile(r"(?P<tool>[^()]+?)(?:\((?P<spec>.*)\))?\Z", re.S)
MAX_DEPTH = 3


# MARK: - Parsing

def parse(rule: str) -> Optional[Tuple[bool, str, Optional[str]]]:
    """``(is_exception, tool, specifier)`` for one rule string, or ``None`` when it does not parse (callers treat that as a refusal)."""
    text = rule.strip()
    exception = text.startswith("!")
    if exception:
        text = text[1:].strip()
    match = RULE.match(text)
    if not match:
        return None
    return exception, match.group("tool").strip(), match.group("spec")


def _tool_matches(pattern: str, tool: str) -> bool:
    return re.fullmatch(".*".join(re.escape(part) for part in pattern.split("*")), tool) is not None


# MARK: - Bash

def _bash_regex(pattern: str) -> "re.Pattern[str]":
    return re.compile(".*".join(re.escape(part) for part in pattern.split("*")), re.S)


def command_forms(command: str, depth: int = 0) -> List[str]:
    """Every text a Bash rule is tried against for ``command``: the line and each simple command, in the forms described above."""
    code, _comments = shell_parse.scan_shell(command)
    forms = [code.strip()]
    for _op, words in shell_parse.tokenize(command):
        stripped = shell_parse.strip_prefixes(list(words))
        for variant in dict.fromkeys((tuple(words), tuple(stripped))):
            if not variant:
                continue
            forms.append(" ".join(variant))
            forms.append(" ".join([os.path.basename(variant[0]), *variant[1:]]))
        if depth >= MAX_DEPTH or not stripped:
            continue
        program = os.path.basename(stripped[0])
        flags = [i for i, w in enumerate(stripped[1:], 1) if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", w)]
        if program in shell_parse.SHELLS and flags:
            inner = [w for w in stripped[flags[0] + 1:] if w != "--"]
            if inner:
                forms.extend(command_forms(inner[0], depth + 1))
        elif program == "eval":
            forms.extend(command_forms(" ".join(stripped[1:]), depth + 1))
        elif program in shell_parse.FEEDERS:
            fed = shell_parse.unwrap_xargs(stripped[1:])
            if fed:
                forms.append(" ".join(fed))
    return [form for form in dict.fromkeys(forms) if form]


# MARK: - Paths

def _path_regex(pattern: str) -> "re.Pattern[str]":
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pattern.startswith("**", i):
            out += ".*"
            i += 2
        elif pattern[i] == "*":
            out += "[^/]*"
            i += 1
        elif pattern[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(pattern[i])
            i += 1
    return re.compile(out + r"\Z", re.I | re.S)


def absolute_pattern(spec: str, project: str, home: str) -> str:
    """The absolute glob a path rule's specifier stands for."""
    if spec.startswith("//"):
        return spec[1:]
    if spec == "~" or spec.startswith("~/"):
        return home.rstrip("/") + spec[1:]
    if spec.startswith("/"):
        return project.rstrip("/") + spec
    return project.rstrip("/") + "/" + (spec[2:] if spec.startswith("./") else spec)


def _fixed_prefix(pattern: str) -> str:
    """The directory part of ``pattern`` before its first wildcard segment."""
    fixed: List[str] = []
    for part in pattern.split("/"):
        if any(c in part for c in "*?"):
            break
        fixed.append(part)
    return "/".join(fixed) or "/"


def _within(parent: str, child: str) -> bool:
    parent, child = parent.rstrip("/").casefold(), child.rstrip("/").casefold()
    return child == parent or child.startswith(parent + "/")


def tool_paths(tool: str, tool_input: Mapping[str, Any], cwd: str) -> List[str]:
    """The paths a path tool touches, as written (normalised) and resolved through symlinks (Grep and Glob with no path search ``cwd``)."""
    found = [str(tool_input[k]) for k in PATH_KEYS if isinstance(tool_input.get(k), str) and tool_input[k]]
    if tool == "Glob" and isinstance(tool_input.get("pattern"), str) and tool_input["pattern"].startswith(("/", "~")):
        found.append(tool_input["pattern"])
    if not found and tool in ("Grep", "Glob"):
        found.append(cwd)
    home = os.path.expanduser("~")
    out = []
    for raw in found:
        if raw == "~" or raw.startswith("~/"):
            raw = home + raw[1:]
        if not os.path.isabs(raw):
            raw = os.path.join(cwd, raw)
        # a glob pattern keeps its wildcards; only the part before them is a real location
        fixed = _fixed_prefix(raw)
        rest = raw[len(fixed):] if fixed != "/" else raw[1:]
        tail = "/" + rest.lstrip("/") if rest.strip("/") else ""
        out.extend(dict.fromkeys((os.path.normpath(fixed).rstrip("/") + tail, os.path.realpath(fixed).rstrip("/") + tail)))
    return out


def path_rule_matches(spec: str, tool: str, paths: Sequence[str], project: str) -> bool:
    """Does the path rule ``spec`` cover any of ``paths`` (or, for Grep and Glob, a search root above its fixed part)?"""
    pattern = absolute_pattern(spec, os.path.realpath(project), os.path.realpath(os.path.expanduser("~")))
    regex = _path_regex(pattern)
    fixed = _fixed_prefix(pattern)
    for path in paths:
        if regex.match(path) or regex.match(path.rstrip("/") + "/"):
            return True
        if tool in ("Grep", "Glob") and _within(path, fixed):
            return True
    return False


# MARK: - Decision

def decide(rules: Iterable[str], tool: str, tool_input: Mapping[str, Any], project: str, cwd: Optional[str] = None) -> Optional[str]:
    """The first deny rule that covers this tool call, or ``None`` to allow it. An unparseable rule denies everything (fail closed).

    ``project`` anchors relative rule patterns; ``cwd`` (default ``project``) anchors relative tool paths."""
    denies: List[Tuple[str, str, Optional[str]]] = []
    excepts: List[Tuple[str, str, Optional[str]]] = []
    for rule in rules:
        parsed = parse(rule)
        if parsed is None:
            return f"unparseable rule {rule!r}"
        exception, name, spec = parsed
        (excepts if exception else denies).append((rule, name, spec))

    def covers(name: str, spec: Optional[str]) -> bool:
        if spec is None:
            return _tool_matches(name, tool)
        if name == "Bash":
            if tool != "Bash" or not isinstance(tool_input.get("command"), str):
                return False
            regex = _bash_regex(spec)
            return any(regex.fullmatch(form) for form in command_forms(tool_input["command"]))
        if tool in PATH_RULE_TOOLS.get(name, ()):
            return path_rule_matches(spec, tool, tool_paths(tool, tool_input, cwd or project), project)
        return False

    for rule, name, spec in denies:
        if covers(name, spec) and not any(covers(n, s) for _r, n, s in excepts):
            return rule
    return None
