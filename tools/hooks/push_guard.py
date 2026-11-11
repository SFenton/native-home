#!/usr/bin/env python3
"""PreToolUse hook for Bash: the layer git cannot enforce for itself around git's pre-push hook (the house denylist).

What a push may carry is decided by git's own ``pre-push`` hook (``.githooks/pre-push`` runs ``tools/prepush_denylist.py``; no reviewer pass is needed to push, owner 2026-11-10): git hands it the url
and every ref and sha actually being pushed, after every earlier command of the line has run. This hook only stops a command from going
around that hook, or around git altogether. It is a token scan over the raw command text (no refspec, remote or sha parsing, no quote-aware
lexing: a match anywhere, even inside quotes or a heredoc, is a refusal) and fails closed. A command that mentions neither ``git`` nor ``gh``
passes untouched. Refused:

- ``--no-verify`` (and any abbreviation of it), which skips the hook;
- ``core.hooksPath`` in any form (``git -c``, ``git config``, ``GIT_CONFIG_PARAMETERS``/``GIT_CONFIG_KEY_n`` values, an assignment in a file edit);
  ``--config-env``, ``GIT_CONFIG_GLOBAL``, ``GIT_CONFIG_SYSTEM``, ``GIT_CONFIG_COUNT`` and ``GIT_CONFIG_PARAMETERS`` (they can inject it);
- a config write of ``include.path`` or ``includeIf.*.path`` (``git config``, ``-c``, an assignment: a file they pull in can set ``core.hooksPath``);
  a read-only ``git grep`` or ``git log -S`` for the name passes;
- setting ``SH_OWNER_PUSH`` (``env``, ``export``, a prefix assignment, ``bash -c``, a file edit): a retired escape from the review step the
  hook no longer has (kept refused so it cannot come back unnoticed). A read-only ``grep`` for the name passes. The pre-push hook ignores the escape entirely now; the scan stays as hardening, and
  also refuses unsetting or blanking the agent-session markers (``CLAUDECODE``, ``CLAUDE_CODE_ENTRYPOINT``, ``FENTON_HEADLESS``) (``unset``, ``env -u``, ``env -i``, ``exec -c``, an empty assignment). Both checks run even
  when the command mentions neither ``git`` nor ``gh``;
- ``send-pack`` and ``http-push`` (plumbing that never runs the hook);
- ``GIT_DIR`` or ``--git-dir`` together with ``push`` (a repository without the hook configured);
- ``gh api`` writes to ``/git/refs``, ``/merges`` or ``/contents`` (a write method, or any field flag that makes the call a POST), and
  ``gh repo sync`` (both move refs on GitHub without a push).

Residual risk (documented in ``.agents/workflow/ci.md#merge-gate``): the hook runs from the worktree's own files, so an uncommitted edit to
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

try:  # the registry of T3-launched triage sessions: a registered session gets the runner's markers (tools/hooks/triage_session.py)
    import triage_session
except Exception:  # noqa: BLE001 - triage_deny fails closed when the module is gone
    triage_session = None

#: ``--no-verify`` or an abbreviation of it that git accepts (``--no-v`` upward; shorter and ambiguous ones are refused too).
NO_VERIFY = re.compile(r"--no-v(?:e(?:r(?:i(?:f(?:y)?)?)?)?)?(?![\w-])")
HOOKS_PATH = re.compile(r"core\.hookspath", re.I)
INCLUDE_PATH = re.compile(r"(?<![\w-])include(?:if\.[^\s'\"]*)?\.path", re.I)
#: A config write of an include (``git config``, ``-c`` and so on, or an assignment); a read-only ``git grep`` or ``git log -S`` is not one.
INCLUDE_WRITE = re.compile(r"(?<![\w-])config(?![\w-])|[ \t]-c[ \t]|--config-env|(?<![\w-])include(?:if\.[^\s'\"]*)?\.path['\"\]\s]*=", re.I)
#: Setting or assigning the owner's escape: ``NAME=`` in any quoting, or a setter command that names it. A read-only search for the name is not.
OWNER_ASSIGN = re.compile(r"SH_OWNER_PUSH['\"\]\s]*=", re.I)
OWNER_SETTER = re.compile(r"(?<![\w-])(?:export|declare|typeset|readonly|local|setenv|putenv|setdefault|environ|env|launchctl)(?![\w-])[^\n;&|]*SH_OWNER_PUSH", re.I)
#: The agent-session markers `.githooks/pre-push` checks before honouring the escape.
AGENT_MARKER = r"(?:CLAUDECODE|CLAUDE_CODE_ENTRYPOINT|FENTON_HEADLESS|T3CODE_\w+|CLAUDE_PROJECT_DIR|CLAUDE_ENV_FILE)"
#: Clearing a marker: ``unset``, ``env -u``/``--unset``, ``MARKER=`` (empty, quoted or not), or wiping the whole environment (``env -i``, ``env -``, ``exec -c``).
MARKER_CLEAR = re.compile(
    r"(?<![\w-])unset(?![\w-])[^\n;&|]*" + AGENT_MARKER
    + r"|(?<![\w-])(?:-u|--unset)[ \t=]*['\"]?" + AGENT_MARKER
    + r"|" + AGENT_MARKER + r"['\"\]]*=(?:['\"]{2})?(?=[\s;&|)'\"]|$)"
    + r"|(?<![\w-])env[ \t]+(?:-[a-zA-Z]*i[a-zA-Z]*|--ignore-environment|-)(?![\w-])"
    + r"|(?<![\w-])exec[ \t]+-[a-zA-Z]*c", re.I)
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
    return (f"Blocked: {why}. Nothing an agent pushes to SFenton/native-home may skip git's pre-push hook (.githooks/pre-push), which runs the "
            "house denylist on every push. Run tools/setup.sh once, then push normally (tools/hooks/push_guard.py).")


def command_reason(command: str) -> str:
    """Why a Bash command is refused, or the empty string."""
    if OWNER_ASSIGN.search(command) or OWNER_SETTER.search(command):
        return "setting SH_OWNER_PUSH (a retired escape from the pre-push hook; no agent sets it)"
    if MARKER_CLEAR.search(command):
        return "unsetting or blanking an agent-session marker (CLAUDECODE, CLAUDE_CODE_ENTRYPOINT, FENTON_HEADLESS, T3CODE_*, CLAUDE_PROJECT_DIR, CLAUDE_ENV_FILE) or wiping the environment (env -i)"
    if not MENTIONS.search(command):
        return ""
    if NO_VERIFY.search(command):
        return "--no-verify (it skips the pre-push hook)"
    if HOOKS_PATH.search(command):
        return "core.hooksPath (the repo's hooks must run)"
    if INCLUDE_PATH.search(command) and INCLUDE_WRITE.search(command):
        return "a config write of include.path / includeIf.*.path (an included file can set core.hooksPath)"
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
        if triage_session:
            triage_session.apply(payload)
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
