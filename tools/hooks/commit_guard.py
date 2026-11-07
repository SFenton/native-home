#!/usr/bin/env python3
"""PreToolUse hook for Bash: the ship safety checks also hold for a raw ``git commit`` or ``git push`` (owner, 2026-11-04).

``tools/ship.sh`` is agent-editable; its refusals live in the owner-only ``tools/ship_guard.sh``. This hook runs the same
checks on any Bash call, so going around ``ship.sh`` does not go around the guard. Applies to every session (interactive,
headless, subagent): a commit on ``main`` or a secret in a commit is never wanted.

Refused, per simple command (quote-aware; ``cd``/``git -C`` targets are followed; ``bash -c`` strings are checked too):

- ``git commit`` or ``git push`` when the checkout's branch is ``main`` or ``master``;
- ``git commit`` when staged files (``-a``: also modified tracked files) are env files, ``.p12``, ``.p8`` or ``.mobileprovision``
  (the patterns are ``tools/ship_guard.sh``'s, run as is);
- ``git commit --no-verify`` / ``-n``;
- ``git push --no-verify`` (and abbreviations), ``git config [scope] core.hooksPath ...`` and ``--unset``, ``-c`` / ``--config-env``
  naming ``core.hooksPath``, and ``GIT_CONFIG*`` assignments on a git command (the pre-push denylist hook, ``.githooks/pre-push``,
  must run; owner, 2026-11-07).

Not triggered: read-only git commands, and the words ``git commit`` inside quotes, a ``-m`` message, a comment or a heredoc body
(the command is tokenized with ``shell_parse``, so only a real simple command counts). Limit: files staged by an earlier command
of the same line (``git add -A && git commit``) are not visible yet; ``ship.sh`` re-checks them after its own ``git add``.
Known limits (detection, not prevention): ``git commit <pathspec>``, ``-o`` and ``-i`` naming a modified tracked secret, ``eval``
strings, git aliases and variables are not followed. The hook fails open on an internal error (it must never brick Bash);
``ship.sh`` re-checks. Exit 2 sends the message back.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from typing import List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_parse import SHELLS, strip_prefixes, tokenize  # noqa: E402

GUARD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ship_guard.sh")
PROTECTED_BRANCHES = {"main", "master"}
#: git's global options that take a value (the next word); ``-C`` also moves the working directory.
GIT_VALUE_OPTIONS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix", "--config-env"}
#: ``git commit`` options whose next word is a value, and the short letters that take one (a cluster ends at such a letter).
COMMIT_VALUE_OPTIONS = {"-m", "-F", "-C", "-c", "-t", "--message", "--file", "--reuse-message", "--reedit-message", "--author",
                        "--date", "--template", "--cleanup", "--fixup", "--squash", "--trailer", "--pathspec-from-file"}
COMMIT_VALUE_LETTERS = "mFCct"
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")


def block(why: str) -> str:
    """The message sent back for a refusal."""
    return (f"Blocked: {why}. Commit and push on a lane branch (tools/lane_new.sh), keep env files, keys and provisioning "
            "profiles out of the index, and let the hooks run. These checks are owner-only (tools/ship_guard.sh, "
            "tools/hooks/commit_guard.py); tools/ship.sh applies the same ones.")


def run_git(cwd: str, *args: str) -> Optional[str]:
    """Stdout of ``git <args>`` in ``cwd`` (stripped), or ``None`` when git fails."""
    try:
        done = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.strip() if done.returncode == 0 else None


def resolve(cwd: str, target: str) -> str:
    """``target`` (``cd``/``-C`` argument) against ``cwd``, with ``~`` and the project variables expanded."""
    project = os.environ.get("CLAUDE_PROJECT_DIR", "")
    target = re.sub(r"\$\{?CLAUDE_PROJECT_DIR\}?", lambda _m: project, target)
    return os.path.normpath(os.path.join(cwd, os.path.expanduser(target)))


def git_parts(words: List[str], cwd: str):
    """``(subcommand, args after it, cwd)`` of a ``git`` simple command (global options skipped, ``-C`` followed), or ``None``."""
    i = 1
    while i < len(words):
        word = words[i]
        if word == "-C" and i + 1 < len(words):
            cwd = resolve(cwd, words[i + 1])
            i += 2
        elif word in GIT_VALUE_OPTIONS:
            i += 2
        elif word.startswith("-"):
            i += 1
        else:
            return word, words[i + 1:], cwd
    return None


def commit_flags(args: List[str]) -> dict:
    """Which of ``--no-verify``/``-n`` and ``-a``/``--all`` a ``git commit`` argument list carries (values skipped)."""
    found = {"no_verify": False, "all": False}
    skip = False
    for arg in args:
        if skip:
            skip = False
        elif arg == "--":
            break
        elif arg == "--all":
            found["all"] = True
        elif len(arg) >= len("--no-veri") and "--no-verify".startswith(arg):  # git accepts unique abbreviations
            found["no_verify"] = True
        elif arg in COMMIT_VALUE_OPTIONS:
            skip = True
        elif arg.startswith("--"):
            continue
        elif arg.startswith("-") and len(arg) > 1:
            for letter in arg[1:]:
                if letter == "n":
                    found["no_verify"] = True
                elif letter == "a":
                    found["all"] = True
                elif letter in COMMIT_VALUE_LETTERS:
                    skip = arg.endswith(letter)  # `-m msg` takes the next word; `-mmsg` has it attached
                    break
    return found


def overrides_hooks_path(words: List[str]) -> bool:
    """Does ``git -c core.hooksPath=...`` (before the subcommand) point the hooks elsewhere?"""
    for i, word in enumerate(words[1:-1], 1):
        if word == "-c" and words[i + 1].lower().startswith("core.hookspath"):
            return True
        if not word.startswith("-") and words[i - 1] not in GIT_VALUE_OPTIONS:
            break
    return False


def push_skips_hook(args: List[str]) -> bool:
    """Does a ``git push`` carry ``--no-verify`` (or an abbreviation of it)? Words after ``--`` are refspecs."""
    for arg in args:
        if arg == "--":
            break
        if arg.startswith("--") and len(arg) >= len("--no-veri") and "--no-verify".startswith(arg):
            return True
    return False


#: ``git config`` options that only read.
CONFIG_READ_FLAGS = {"--get", "--get-all", "--get-regexp", "--list", "-l", "--show-origin", "--show-scope"}


def config_changes_hooks_path(args: List[str]) -> bool:
    """Does a ``git config`` (words after ``config``) set, unset or replace ``core.hooksPath`` in any scope?"""
    if not any(a.lower() == "core.hookspath" for a in args):
        return False
    if any(a in CONFIG_READ_FLAGS for a in args):
        return False
    values = [a for a in args if not a.startswith("-")]
    unsets = any(a.startswith(("--unset", "--replace-all", "--add", "-e", "--edit")) for a in args)
    return unsets or len(values) > 1


def config_env_hooks_path(words: List[str]) -> bool:
    """Does the command pass ``core.hooksPath`` through ``--config-env`` or any ``GIT_CONFIG*`` environment assignment?"""
    git_at = next((i for i, w in enumerate(words) if os.path.basename(w) == "git"), None)
    if git_at is None:
        return False
    if any(re.match(r"^GIT_CONFIG\w*=", w) for w in words[:git_at]):
        return True
    for i, word in enumerate(words[git_at + 1:], git_at + 1):
        low = word.lower()
        if low.startswith("--config-env=core.hookspath") or (low == "--config-env" and i + 1 < len(words) and words[i + 1].lower().startswith("core.hookspath")):
            return True
        if not word.startswith("-") and words[i - 1] not in GIT_VALUE_OPTIONS:
            break
    return False


def check_git(sub: str, args: List[str], cwd: str, hooks_path_override: bool = False) -> Optional[str]:
    """Why one ``git <sub>`` is refused in ``cwd``, or ``None``."""
    if sub == "config" and config_changes_hooks_path(args):
        return "git config core.hooksPath (the repo's hooks, including the pre-push denylist hook, must run)"
    if sub not in ("commit", "push"):
        return None
    branch = run_git(cwd, "rev-parse", "--abbrev-ref", "HEAD")
    if branch in PROTECTED_BRANCHES:
        return f"git {sub} on '{branch}'"
    if sub == "push":
        if hooks_path_override:
            return "git -c core.hooksPath=... push (the pre-push denylist hook must run)"
        if push_skips_hook(args):
            return "git push --no-verify (the pre-push denylist hook must run)"
        return None
    if hooks_path_override:
        return "git -c core.hooksPath=... commit (the repo's hooks must run)"
    flags = commit_flags(args)
    if flags["no_verify"]:
        return "git commit --no-verify (the repo's hooks must run)"
    if os.path.isfile(GUARD) and run_git(cwd, "rev-parse", "--git-dir") is not None:
        env = {**os.environ, "SHIP_GUARD_NO_RESET": "1", "SHIP_GUARD_INCLUDE_WORKTREE": "1" if flags["all"] else ""}
        try:
            done = subprocess.run(["bash", GUARD, "staged"], cwd=cwd, env=env, capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.SubprocessError):
            return None
        if done.returncode != 0:
            return "git commit with " + " ".join(done.stderr.split("\n")[1:]).strip()
    return None


def command_reason(command: str, cwd: str, depth: int = 0) -> Optional[str]:
    """Why a Bash command commits or pushes where it must not, or ``None``."""
    if depth > 3:
        return None
    for _op, words in tokenize(command):
        raw = list(words)
        words = strip_prefixes(list(words))
        if not words:
            continue
        program = os.path.basename(words[0])
        if program in ("cd", "pushd"):
            rest = [w for w in words[1:] if not w.startswith("-")]
            if rest:
                cwd = resolve(cwd, rest[0])
        elif program in SHELLS:
            for i, word in enumerate(words[:-1]):
                if SHELL_C.match(word):
                    why = command_reason(words[i + 1], cwd, depth + 1)
                    if why:
                        return why
        elif program == "git":
            parts = git_parts(words, cwd)
            if parts:
                why = check_git(parts[0], parts[1], parts[2], overrides_hooks_path(words) or config_env_hooks_path(raw))
                if why:
                    return why
    return None


def main() -> int:
    """Read the hook payload from stdin; exit 2 with the message to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    command = str((payload.get("tool_input") or {}).get("command") or "")
    if "git" not in command:
        return 0
    why = command_reason(command, str(payload.get("cwd") or os.getcwd()))
    if why:
        print(block(why), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
