#!/usr/bin/env python3
"""Hook pair for Bash: no blind rebuild after a ``tools/devcap.py`` hold timeout (R-27; owner rule 2026-11-03: one full device run).

* **PostToolUse / PostToolUseFailure** (foreground calls): when a line of the tool output is devcap's real timeout line (see
  ``TIMEOUT_LINE``; source, docs and diffs that merely quote it do not match), or a devcap-held command exited 124, write
  ``build/.devcap_hold_timeout.json`` in the worktree root: ``{time, load1, command}``.
* **``tools/bg_run.py``** (the documented background path, whose output never reaches a hook): writes the same marker through
  ``arm_from_log`` when its command exits non-zero and its log holds the real line (the coverage script exits 1 on a part's hold
  timeout). The guard arms only from a ``bg_run.py`` run or from devcap's line in output a Bash call returns: a heavy script started
  in the background without ``bg_run``, or a foreground run moved to the background, does not arm it.
* **PreToolUse**: refuse a heavy command (``tools/devcap.py run``, ``tools/ios_uitest.sh``, ``tools/apple_coverage.sh``, found as
  the program or behind ``bg_run.py``, ``python3``, ``bash``, ``bash -c '…'`` and the usual wrappers) in that worktree while the
  marker is under two hours old and the load average is still at least 0.8 x the marker's. A command carrying a real
  ``# devcap-retry-ok: <reason>`` comment goes through and the marker is deleted. A stale marker is deleted and ignored.

Commands are read with ``shell_parse``, so a heredoc body or a quoted mention of a script name is not a run. Every error fails open
(exit 0). The vendored ``devcap.py`` is untouched. See .agents/workflow/token-economy.md.
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import subprocess
import sys
import time
from typing import Iterator, List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from redact import redact  # noqa: E402
from shell_parse import SHELLS, find_override, strip_prefixes, tokenize  # noqa: E402

MARKER_REL = os.path.join("build", ".devcap_hold_timeout.json")
#: A marker older than this is deleted and ignored.
MAX_AGE = 2 * 3600
#: The refusal holds while the current load is at least this share of the load at the timeout.
LOAD_SHARE = 0.8
#: devcap's real timeout line, anchored at a line start with the optional ``path:`` / ``lineno:`` prefixes grep -H and -n add.
TIMEOUT_LINE = re.compile(r"(?m)^(?:\S+:)?(?:\d+:)?devcap: HOLD TIMEOUT: held \S+ longer than")
SCRIPTS = {"ios_uitest.sh", "apple_coverage.sh"}
OVERRIDE = re.compile(r"#\s*devcap-retry-ok:\s*\S")
PYTHON_ARG_OPTIONS = frozenset({"-W", "-X", "--check-hash-based-pycs"})
SHELL_ARG_OPTIONS = frozenset({"-o", "+o", "-O", "+O", "--rcfile", "--init-file"})
PYTHONS = re.compile(r"^python[\d.]*$")
EXIT_124 = re.compile(r"\bExit code:? 124\b|\bexit(?:ed with)? (?:code |status )?124\b", re.I)


# MARK: - Environment (mocked in tests)

def now() -> float:
    """The clock, in epoch seconds."""
    return time.time()


def load1() -> float:
    """The one-minute load average."""
    return os.getloadavg()[0]


def repo_root(cwd: str) -> Optional[str]:
    """``git rev-parse --show-toplevel`` of ``cwd``, or ``None``."""
    try:
        out = subprocess.run(["git", "-C", cwd or ".", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() or None if out.returncode == 0 else None


# MARK: - Heavy commands

def skip_options(words: List[str], with_arg: frozenset) -> "tuple[List[str], List[str]]":
    """Split leading option words from the rest; an option in ``with_arg`` swallows the next word, ``--`` ends the options."""
    index = 0
    while index < len(words) and words[index].startswith(("-", "+")) and len(words[index]) > 1:
        if words[index] == "--":
            index += 1
            break
        index += 2 if words[index] in with_arg else 1
    return words[:index], words[index:]


def heavy_words(words: List[str], depth: int = 0) -> bool:
    """Does the simple command ``words`` run a devcap hold, the journey script or the coverage script?"""
    words = strip_prefixes(words)
    if not words or depth > 4:
        return False
    head = os.path.basename(words[0])
    if PYTHONS.match(head) and len(words) > 1:
        rest = skip_options(words[1:], PYTHON_ARG_OPTIONS)[1]
        return not any(w in ("-m", "-c") for w in words[1:len(words) - len(rest)]) and heavy_words(rest, depth + 1)
    if head in SCRIPTS:
        return True
    if head == "devcap.py":
        return len(words) > 1 and words[1] == "run"
    if head == "bg_run.py":
        rest = words[words.index("--") + 1:] if "--" in words else []
        return heavy_words(rest, depth + 1)
    if head in SHELLS:
        flags, rest = skip_options(words[1:], SHELL_ARG_OPTIONS)
        clusters = [f for f in flags if f[0] in "-+" and not f.startswith("--") and f not in SHELL_ARG_OPTIONS]
        if any("c" in f for f in clusters):
            return bool(rest) and is_heavy(rest[0], depth + 1)
        if any("n" in f for f in clusters):
            return False
        return bool(rest) and heavy_words(rest, depth + 1)
    return False


def is_heavy(command: str, depth: int = 0) -> bool:
    """Does any simple command in ``command`` run a heavy script? Heredoc bodies, comments and quoted text do not count."""
    if depth > 4:
        return False
    return any(heavy_words(words, depth) for _, words in tokenize(command))


# MARK: - Marker

def marker_path(root: str) -> str:
    """The marker file of the worktree at ``root``."""
    return os.path.join(root, MARKER_REL)


def read_marker(path: str) -> Optional[dict]:
    """The marker, or ``None`` when absent or malformed."""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        float(data["time"])
        float(data["load1"])
        return data
    except (OSError, ValueError, KeyError, TypeError):
        return None


def remove(path: str) -> None:
    """Delete ``path`` if present."""
    with contextlib.suppress(OSError):
        os.remove(path)


def write_marker(root: str, command: str) -> None:
    """Record a hold timeout now."""
    path = marker_path(root)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump({"time": now(), "load1": load1(), "command": redact(command)[:200]}, handle)


# MARK: - Decisions

def response_text(response: object) -> str:
    """The output text of a tool response: strings as they are, dict values joined by newlines (so line anchors still work)."""
    if isinstance(response, str):
        return response
    if isinstance(response, dict):
        return "\n".join(response_text(value) for value in response.values())
    if isinstance(response, (list, tuple)):
        return "\n".join(response_text(value) for value in response)
    return "" if response is None else str(response)


def timed_out(command: str, response: object) -> bool:
    """Did this tool call end in a devcap hold timeout? Only devcap's real line counts, not text that quotes it."""
    text = response_text(response)
    if TIMEOUT_LINE.search(text):
        return True
    return "124" in text and is_heavy(command) and bool(EXIT_124.search(text))


def arm_from_log(root: str, command: str, status: int, log_text: str) -> bool:
    """Write the marker when a background ``command`` exited non-zero and its log holds devcap's real line. Fails open."""
    try:
        if status != 0 and TIMEOUT_LINE.search(log_text):
            write_marker(root, command)
            return True
    except Exception:  # noqa: BLE001
        pass
    return False


def refusal(command: str, root: str) -> Optional[str]:
    """The refusal text for ``command`` in the worktree ``root``, or ``None``. Deletes a stale marker or one an override spent."""
    path = marker_path(root)
    if not os.path.exists(path):
        return None
    marker = read_marker(path)
    if marker is None:
        return None
    age = now() - float(marker["time"])
    if age > MAX_AGE:
        remove(path)
        return None
    if not is_heavy(command):
        return None
    if find_override(command, OVERRIDE):
        remove(path)
        return None
    current = load1()
    if current < LOAD_SHARE * float(marker["load1"]):
        return None
    return (f"blocked: load (a devcap hold timed out {max(0, int(age // 60))}m ago at load {float(marker['load1']):.1f}, now "
            f"{current:.1f}). Do not retry the build: write status blocked with the cause \"shared-Mac load\", or add "
            "'# devcap-retry-ok: <reason>' if the load has cleared.")


@contextlib.contextmanager
def table_fixture(home: str) -> Iterator[None]:
    """A hermetic world for the bypass table (``test_guard_tables``): a fresh marker at load 10 in a temp worktree, current load 10."""
    import tempfile
    from unittest import mock
    with tempfile.TemporaryDirectory(dir=home) as root:
        os.makedirs(os.path.join(root, "build"))
        with open(marker_path(root), "w", encoding="utf-8") as handle:
            json.dump({"time": now() - 600, "load1": 10.0, "command": "tools/ios_uitest.sh"}, handle)
        with mock.patch.object(sys.modules[__name__], "repo_root", lambda cwd: root), \
                mock.patch.object(sys.modules[__name__], "load1", lambda: 10.0):
            yield


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with the refusal to block. Fails open on any error."""
    try:
        payload = json.load(sys.stdin)
        if payload.get("tool_name") != "Bash":
            return 0
        command = str((payload.get("tool_input") or {}).get("command", ""))
        cwd = str(payload.get("cwd") or os.getcwd())
        if str(payload.get("hook_event_name", "PreToolUse")).startswith("Post"):
            if timed_out(command, payload.get("tool_response", payload.get("error", ""))):
                root = repo_root(cwd)
                if root:
                    write_marker(root, command)
            return 0
        root = repo_root(cwd)
        if not root:
            return 0
        why = refusal(command, root)
        if why:
            print(why, file=sys.stderr)
            return 2
    except Exception:  # noqa: BLE001 - a guard bug must never block work
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
