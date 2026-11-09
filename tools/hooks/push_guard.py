#!/usr/bin/env python3
"""PreToolUse hook for Bash: the layer git cannot enforce for itself in the review-before-push gate.

What a push may carry is decided by git's own ``pre-push`` hook (``.githooks/pre-push`` runs ``tools/prepush_review.py``): git hands it the url
and every ref and sha actually being pushed, after every earlier command of the line has run. This hook only stops a command from going
around that hook, or around git altogether. It is a token scan over the raw command text (no refspec, remote or sha parsing, no quote-aware
lexing: a match anywhere, even inside quotes or a heredoc, is a refusal) and fails closed. A command that mentions neither ``git`` nor ``gh``
passes untouched. Refused:

- ``--no-verify`` (and any abbreviation of it), which skips the hook;
- ``core.hooksPath`` in any form (``git -c``, ``git config``, ``GIT_CONFIG_PARAMETERS``/``GIT_CONFIG_KEY_n`` values, an assignment in a file edit);
  ``--config-env``, ``GIT_CONFIG_GLOBAL``, ``GIT_CONFIG_SYSTEM``, ``GIT_CONFIG_COUNT`` and ``GIT_CONFIG_PARAMETERS`` (they can inject it);
- ``include.path`` and ``includeIf.*.path`` (a config file they pull in can set ``core.hooksPath``);
- ``SH_OWNER_PUSH`` in any form (``env``, ``export``, a prefix assignment, ``bash -c``, a file edit): the owner's escape from the review step
  in ``.githooks/pre-push`` (the denylist still runs). It is checked even when the command mentions neither ``git`` nor ``gh``;
- ``send-pack`` and ``http-push`` (plumbing that never runs the hook);
- ``GIT_DIR`` or ``--git-dir`` together with ``push`` (a repository without the hook configured);
- ``gh api`` writes to ``/git/refs``, ``/merges`` or ``/contents`` (a write method, or any field flag that makes the call a POST), and
  ``gh repo sync`` (both move refs on GitHub without a push).

Residual risk (documented in ``.agents/workflow/ci.md#the-merge-gate``): the hook runs from the worktree's own files, so an uncommitted edit to
them disables the gate; a push from a clone whose ``core.hooksPath`` was never set
(``tools/setup.sh``), ``curl`` or an interpreter calling the GitHub API, and a hook skipped by editing ``.git/config`` with a tool.
``tools/ship.sh`` checks ``core.hooksPath`` itself. Exit 2 sends the message back; every failure, an import error included, is exit 2,
never 1 and never a silent pass.
"""

from __future__ import annotations

import sys

try:
    import json
    import re
except Exception:  # noqa: BLE001 - fail closed even if the standard library cannot be imported
    print("Blocked: push_guard could not import the standard library; refusing (fails closed).", file=sys.stderr)
    sys.exit(2)

#: ``--no-verify`` or an abbreviation of it that git accepts (``--no-v`` upward; shorter and ambiguous ones are refused too).
NO_VERIFY = re.compile(r"--no-v(?:e(?:r(?:i(?:f(?:y)?)?)?)?)?(?![\w-])")
HOOKS_PATH = re.compile(r"core\.hookspath|(?<![\w-])include(?:if\.[^\s'\"]*)?\.path", re.I)
OWNER_ESCAPE = re.compile(r"SH_OWNER_PUSH", re.I)
CONFIG_INJECTION = re.compile(r"--config-env|GIT_CONFIG_(?:GLOBAL|SYSTEM|COUNT|PARAMETERS|KEY_\d+|VALUE_\d+)\b|GIT_CONFIG_NOSYSTEM", re.I)
SEND_PACK = re.compile(r"(?<![\w-])(?:git[ \t-]+)?(?:send-pack|http-push)(?![\w-])")
GIT_DIR = re.compile(r"(?<![\w])GIT_DIR\b|--git-dir\b")
PUSH_WORD = re.compile(r"(?<![\w-])push(?![\w-])")
GH_API = re.compile(r"(?<![\w-])gh\b[^;|&\n]*?[ \t]api\b")
REF_WRITE_PATH = re.compile(r"/git/refs|/merges\b|/contents\b")
WRITE_METHOD = re.compile(r"(?:-X|--method)[ \t=]*['\"]?(?:POST|PUT|PATCH|DELETE)\b", re.I)
FIELD_FLAG = re.compile(r"(?<![\w-])(?:-f|-F|--field|--raw-field|--input)(?![\w-])")
GH_REPO_SYNC = re.compile(r"(?<![\w-])gh\b[^;|&\n]*?[ \t]repo[ \t]+(?:[^;|&\n]*?[ \t])?sync\b")
MENTIONS = re.compile(r"(?<![\w-])(?:git|gh)(?![\w-])|send-pack|http-push|core\.hookspath", re.I)


def message(why: str) -> str:
    """The text sent back with a refusal."""
    return (f"Blocked: {why}. Nothing an agent pushes to SFenton/native-home may skip git's pre-push hook (.githooks/pre-push), which refuses a "
            "push without an independent `pass` for each pushed commit. Run tools/setup.sh once, have the reviewer record the pass "
            "(tools/review/record.py --lane BRANCH), then push normally (tools/hooks/push_guard.py).")


def command_reason(command: str) -> str:
    """Why a Bash command is refused, or the empty string."""
    if OWNER_ESCAPE.search(command):
        return "SH_OWNER_PUSH (the owner's escape from the review step; only the owner sets it, in their own terminal)"
    if not MENTIONS.search(command):
        return ""
    if NO_VERIFY.search(command):
        return "--no-verify (it skips the pre-push hook)"
    if HOOKS_PATH.search(command):
        return "core.hooksPath or include.path / includeIf.*.path (the repo's hooks must run)"
    if CONFIG_INJECTION.search(command):
        return "a git config injection (--config-env or GIT_CONFIG_*) that could replace the hooks path"
    if SEND_PACK.search(command):
        return "send-pack/http-push (plumbing that never runs the pre-push hook)"
    if GIT_DIR.search(command) and PUSH_WORD.search(command):
        return "GIT_DIR or --git-dir together with push (a repository without the hook)"
    if GH_API.search(command) and REF_WRITE_PATH.search(command) and (WRITE_METHOD.search(command) or FIELD_FLAG.search(command)):
        return "a gh api write to git refs, merges or contents (a ref write the pre-push hook cannot see)"
    if GH_REPO_SYNC.search(command):
        return "gh repo sync (it moves refs without a push)"
    return ""


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
        why = command_reason(command)
    except Exception as error:  # noqa: BLE001 - fail closed: anything unreadable is a refusal
        print(message(f"the command could not be checked ({type(error).__name__})"), file=sys.stderr)
        return 2
    if why:
        print(message(why), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
