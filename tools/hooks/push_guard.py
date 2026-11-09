#!/usr/bin/env python3
"""PreToolUse hook for Bash: nothing an agent pushes reaches SFenton/native-home without an independent ``pass`` for that exact commit.

The gate is review-before-push (owner, 2026-11-09; .agents/workflow/ci.md#merge-gate). The Reviewer records a verdict for the commit with
``tools/review/record.py --lane BRANCH``; this hook refuses a ``git push`` to native-home unless the trusted store
(``~/hass-agents/reviews``, read by ``tools/review_verdict.py``, never a worktree file) holds a ``pass`` for the sha being pushed.

Per simple command (quote-aware; ``cd`` and ``git -C`` are followed; ``bash -c`` strings are checked, up to three levels):

- the remote is the first operand, else ``branch.<b>.pushRemote``, ``remote.pushDefault``, ``branch.<b>.remote``, else ``origin``; a remote name
  resolves through ``git remote get-url --push`` (so ``pushurl`` and ``insteadOf`` apply);
- ``native-home`` remotes are gated; another GitHub repository is allowed as before; a local path or a URL form it cannot read is refused (fails closed);
- the sha is each refspec's source resolved to a commit (``HEAD`` for a bare ``git push``); every one needs a pass;
- deleting a remote branch (``:branch``, ``--delete``) is allowed; any push to ``main`` or ``master`` is refused (``commit_guard`` and
  ``merge_guard`` say the same); ``--all``, ``--mirror``, ``--tags`` and ``--prune``, glob refspecs, shell expansions, ``git -c`` and ``--git-dir`` on a gated push
  are refused because no single sha can be named;
- ``HOME=... tools/ship.sh`` is refused: ``ship.sh`` reads the same store through ``$HOME``.

Fails closed: an unreadable payload, a parse failure, a missing remote or a missing record all exit 2 with a message; the hook never exits 1.
Commands that are not a ``git push`` pass through untouched.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import Callable, List, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
from commit_guard import git_parts, resolve, run_git  # noqa: E402
from shell_parse import SHELLS, strip_prefixes, tokenize  # noqa: E402
import review_verdict  # noqa: E402

PROTECTED = {"main", "master"}
MAX_DEPTH = 3
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
EXPANSION = re.compile(r"[$`]")
SUBSTITUTION = re.compile(r"\$\(|`|<\(|>\(")
#: ``git push`` options whose next word is a value.
VALUE_OPTIONS = {"-o", "--push-option", "--receive-pack", "--exec", "--repo"}
#: Options that push more than one named sha.
UNBOUNDED = {"--all", "--branches", "--mirror", "--tags", "--prune"}
#: Global git options that change where git looks (cannot be resolved from the command text).
GLOBAL_REDIRECTS = ("-c", "--config-env", "--git-dir", "--work-tree", "--namespace")


def message(why: str) -> str:
    """The text sent back with a refusal."""
    return (f"Blocked: {why}. Nothing an agent pushes to SFenton/native-home may leave this machine without an independent `pass` for that exact "
            "commit: have the reviewer record one (tools/review/record.py --lane BRANCH, from the branch's worktree), then push that commit unchanged. "
            "A push after a new commit needs a new review (tools/hooks/push_guard.py, tools/review_verdict.py).")


def global_redirect(words: List[str]) -> bool:
    """Does the ``git`` command carry a global option that moves its config or repository (before the subcommand)?"""
    for i, word in enumerate(words[1:], 1):
        if word in GLOBAL_REDIRECTS or word.startswith(("--config-env=", "--git-dir=", "--work-tree=", "--namespace=")):
            return True
        if not word.startswith("-") and words[i - 1] not in ("-C",) + GLOBAL_REDIRECTS:
            return False
    return False


def operands(args: List[str]) -> Optional[dict]:
    """Parse the words after ``push``: ``{"positional": [...], "delete": bool, "repo": str|None}``; ``None`` when they name more than one sha."""
    found = {"positional": [], "delete": False, "repo": None}
    skip = False
    after_dashes = False
    for i, word in enumerate(args):
        if skip:
            skip = False
            continue
        if after_dashes or not word.startswith("-") or word == "-":
            found["positional"].append(word)
        elif word == "--":
            after_dashes = True
        elif word in UNBOUNDED:
            return None
        elif word in ("-d", "--delete"):
            found["delete"] = True
        elif word == "--repo" and i + 1 < len(args):
            found["repo"] = args[i + 1]
            skip = True
        elif word.startswith("--repo="):
            found["repo"] = word.split("=", 1)[1]
        elif word in VALUE_OPTIONS:
            skip = True
    return found


def remote_url(cwd: str, remote: str) -> Optional[str]:
    """The push URL for a remote name or URL operand (a URL is returned as is), or ``None`` when it cannot be resolved."""
    if "://" in remote or ":" in remote or remote.startswith(("/", ".", "~")):
        return remote
    return run_git(cwd, "remote", "get-url", "--push", remote)


def default_remote(cwd: str) -> str:
    """The remote a bare ``git push`` uses: the branch's pushRemote, ``remote.pushDefault``, the branch's remote, else ``origin``."""
    branch = run_git(cwd, "rev-parse", "--abbrev-ref", "HEAD") or ""
    for key in (f"branch.{branch}.pushRemote", "remote.pushDefault", f"branch.{branch}.remote"):
        value = run_git(cwd, "config", "--get", key)
        if value:
            return value
    return "origin"


def check_push(words: List[str], args: List[str], cwd: str, verdict: Callable[[str], bool], substituted: bool = False) -> Optional[str]:
    """Why one ``git push`` (``words`` the whole git command, ``args`` after ``push``) is refused in ``cwd``, or ``None``."""
    if any(EXPANSION.search(w) for w in words):
        return "git push with a shell expansion (the pushed commit cannot be named)"
    parsed = operands(args)
    positional = parsed["positional"] if parsed else []
    remote = (parsed or {}).get("repo") or (positional[0] if positional else None)
    url = remote_url(cwd, remote if remote else default_remote(cwd))
    kind = review_verdict.remote_kind(url) if url else "unknown"
    if kind == "other":
        return None
    if kind != "native-home":
        return f"git push to a remote that is not a readable GitHub URL ({'unreadable' if not url else kind}); only other GitHub repositories are exempt"
    if parsed is None:
        return "git push --all/--mirror/--tags/--prune to SFenton/native-home (no single reviewed commit)"
    if substituted:
        return "git push to SFenton/native-home in a command with a substitution (`...` or $(...)); the pushed commit cannot be named"
    if global_redirect(words):
        return "git push to SFenton/native-home with -c, --config-env or --git-dir (the remote cannot be resolved)"
    specs = positional if parsed["repo"] else positional[1:]
    shas: List[str] = []
    if not specs:
        if parsed["delete"]:
            return "git push --delete without a branch"
        specs = ["HEAD"]
        if run_git(cwd, "rev-parse", "--abbrev-ref", "HEAD") in (None, "HEAD"):
            return "git push of a detached or unreadable HEAD to SFenton/native-home"
    for spec in specs:
        spec = spec.lstrip("+")
        src, colon, dest = spec.partition(":")
        if parsed["delete"] and not colon:
            src, dest = "", spec
        target = (dest or src).removeprefix("refs/heads/")
        if target in PROTECTED:
            return f"git push to {target}"
        if colon and not src or (parsed["delete"] and not colon):
            continue  # deleting a remote branch is allowed
        if not src or "*" in spec or "?" in spec:
            return f"git push of the refspec {spec!r} (cannot be resolved to one commit)"
        sha = run_git(cwd, "rev-parse", "--verify", "-q", src + "^{commit}")
        if not sha or not review_verdict.FULL_SHA.match(sha):
            return f"git push of {src!r}, which does not resolve to a commit here"
        shas.append(sha)
    for sha in shas:
        if not verdict(sha):
            return f"git push of {sha[:12]} to SFenton/native-home without an independent pass for that exact commit"
    return None


def command_reason(command: str, cwd: str, depth: int = 0, verdict: Callable[[str], bool] = review_verdict.has_pass) -> Optional[str]:
    """Why a Bash command pushes where it must not, or ``None``."""
    if depth > MAX_DEPTH:
        return "a command nested more than three shells deep (it cannot be checked)"
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
                    why = command_reason(words[i + 1], cwd, depth + 1, verdict)
                    if why:
                        return why
        elif program == "ship.sh" and any(re.match(r"^(?:HOME|XDG_\w+)=", w) for w in raw):
            return "HOME=... on tools/ship.sh (it reads the verdict store through $HOME)"
        elif program == "git":
            parts = git_parts(words, cwd)
            if parts and parts[0] == "push":
                why = check_push(words, parts[1], parts[2], verdict, bool(SUBSTITUTION.search(command)))
                if why:
                    return why
        elif EXPANSION.search(words[0]) and "push" in words[1:]:
            return "a push through a variable or substitution (the command cannot be checked)"
    return None


def main() -> int:
    """Read the hook payload from stdin; exit 2 with the message to block, 0 to allow. Never exits 1."""
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            raise ValueError("payload is not an object")
        if payload.get("tool_name") != "Bash":
            return 0
        tool_input = payload.get("tool_input")
        command = tool_input.get("command") if isinstance(tool_input, dict) else None
        if not isinstance(command, str):
            raise ValueError("no command string")
        if "push" not in command and "ship.sh" not in command:
            return 0
        why = command_reason(command, str(payload.get("cwd") or os.getcwd()))
    except Exception as error:  # noqa: BLE001 - fail closed: anything unreadable is a refusal
        print(message(f"the command could not be checked ({type(error).__name__})"), file=sys.stderr)
        return 2
    if why:
        print(message(why), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
