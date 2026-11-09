#!/usr/bin/env python3
"""UserPromptSubmit hook: a log of the prompts the owner types (owner decision 2026-11-04).

The app-UI landing gate (``tools/lane_land.py``, ``logged_owner_prompt``) counts an ``Owner's request: "<quote>"`` line as the
owner's own request only when the quote is inside a prompt logged here in the last 14 days. The log is
``~/hass-agents/owner-prompts/<YYYY-MM>.jsonl`` (mode 600, folder mode 700, outside every worktree); files older than the previous
month are deleted on append.

**What is enforced, honestly.** Agents run as the owner's macOS user, so no file mode stops them. This is a *tripwire*, not a
boundary: ``tools/hooks/owner_prompt_guard.py`` (PreToolUse) refuses Bash that names the folder, Read, Grep, Glob, Edit or Write
of it, and an agent launching ``claude -p`` without a roster ``--agent``; the runner's deny list has the folder; and this hook
declines to log prompts that did not come from a person at an attended session. Deliberate evasion (a path built from variables,
an interpreter that opens the file) is out of scope; it would be a visible, reviewable act.

**Who is logged.** Claude Code fires ``UserPromptSubmit`` for each prompt a session receives. The owner's main thread carries
``agent_type`` (settings pin ``"agent": "orchestrator"``) but never ``agent_id``; subagents and teammates carry ``agent_id``. So
the test is ``agent_id`` absent, never ``agent_type``. A prompt is written only when all hold:

* ``FENTON_HEADLESS`` is not ``1`` (the runner), the payload has no ``agent_id``, and the event is ``UserPromptSubmit``;
* not an SSH session (``SSH_CONNECTION``, ``SSH_CLIENT`` and ``SSH_TTY`` unset): remote ``claude -p`` runs over the mesh;
* ``CLAUDE_CODE_ENTRYPOINT`` is unset, ``cli`` or ``claude-desktop`` (``sdk-*`` values are print or SDK runs; the desktop app
  reports ``claude-desktop``, probed 2026-11-04), and ``CLAUDE_CODE_SESSION_ATTENDED`` is not ``0``;
* no ``claude`` process sits above this session's own ``claude`` in the process tree (an agent's nested run), and that own
  ``claude``'s exec environment (``ps -E``) has neither ``CLAUDECODE=1`` nor ``CLAUDE_CODE_SESSION_ID``: everything a session
  starts inherits them, including a detached ``(claude -p ... &)`` that the tree walk misses; the owner's desktop ``claude``
  has neither (probed 2026-11-04). Fails closed when the environment cannot be read;
* the prompt is not harness-injected: it does not open with a notice tag found in the Claude Code binary (``<task-notification``,
  ``<system-reminder``, ``<channel``, ``<cross-session-message``, ``<teammate-message``, ``<fork-boilerplate``,
  ``<user-prompt-submit-hook``, ``<local-command-``), the loop marker ``<<autonomous-loop``, or ``[Artifact comment``.
  Scheduled tasks, ``/loop`` turns, background-agent reports and side-session messages arrive in those wrappers. This relies on
  what the binary spells today: a new wrapper would be logged until it is added.

The hook never blocks a prompt: it always exits 0 with no output. Row: ``{"ts", "session", "cwd", "sha256", "prompt"}``.
Standard library only.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

NOTICE_TAGS = ("<task-notification", "<system-reminder", "<channel", "<cross-session-message", "<teammate-message",
               "<fork-boilerplate", "<user-prompt-submit-hook", "<local-command-", "<<autonomous-loop", "[artifact comment")
INTERACTIVE_ENTRYPOINTS = ("", "cli", "claude-desktop")
SSH_VARS = ("SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY")


def log_dir(home: str | None = None) -> Path:
    """``~/hass-agents/owner-prompts`` (the lander reads ``<agent root>/owner-prompts``, the same folder)."""
    return Path(home or os.path.expanduser("~")) / "hass-agents" / "owner-prompts"


def claude_chain(pid: int | None = None) -> list[int]:
    """Pids of the ancestors of ``pid`` (default this process) that run an executable named ``claude``, nearest first (``ps`` walk)."""
    chain, pid = [], pid or os.getpid()
    for _ in range(40):
        try:
            out = subprocess.run(["ps", "-o", "ppid=,comm=", "-p", str(pid)], capture_output=True, text=True, timeout=3).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return chain
        if not out:
            return chain
        ppid, _, comm = out.partition(" ")
        if pid != os.getpid() and os.path.basename(comm.strip()) == "claude":
            chain.append(pid)
        if not ppid.isdigit() or int(ppid) <= 1:
            return chain
        pid = int(ppid)
    return chain


def claude_ancestors(pid: int | None = None) -> int:
    """How many ancestors of ``pid`` run an executable named ``claude``."""
    return len(claude_chain(pid))


#: Markers the harness puts in the environment of everything a Claude Code session starts (its tool shells, so any ``claude`` an
#: agent launches, detached or not). The owner's own desktop ``claude`` is started by the app, so it has neither.
CHILD_MARKERS = re.compile(r"(?:^|\s)(?:CLAUDECODE=1|CLAUDE_CODE_SESSION_ID=)")


def _env_clean(pid: int) -> bool:
    """Is process ``pid`` readable and free of :data:`CHILD_MARKERS` in its exec environment? Unreadable is not clean."""
    try:
        out = subprocess.run(["ps", "-E", "-ww", "-o", "command=", "-p", str(pid)], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return bool(out.strip()) and not CHILD_MARKERS.search(out)


def session_env_clean(pid: int | None = None, parent: int | None = None) -> bool:
    """Are this hook's parent process and its session's ``claude`` free of :data:`CHILD_MARKERS` in their exec environment?

    A ``claude`` started from an agent's tool call inherits ``CLAUDECODE=1`` and the session id even when detached
    (``(claude -p ... &)``), which the ancestor walk cannot see. The parent (``os.getppid()``, whatever it is called: a renamed
    launcher such as ``~/.local/share/claude/versions/<ver>``, or ``node`` under ``npx``) is checked as well as the nearest
    process named ``claude``, because a launcher not named ``claude`` would otherwise send the check to the desktop app's
    ``claude``. Both must be clean. Fails closed: no ``claude`` ancestor, or an environment that cannot be read, is not clean.
    Only presence is tested; the environment is never printed or stored. ``pid`` and ``parent`` override the probes (tests)."""
    chain = claude_chain(pid)
    parent = os.getppid() if parent is None else parent
    return bool(chain) and all(_env_clean(p) for p in dict.fromkeys([parent, chain[0]]))


def interactive(env: dict[str, str], ancestors: int | None = None, clean: bool | None = None) -> bool:
    """Does the environment look like a person at an attended session (no SSH, an interactive entrypoint, no nested claude,
    and a session ``claude`` that no other session started)? ``ancestors`` and ``clean`` override the probes (tests)."""
    if env.get("FENTON_HEADLESS") == "1" or any(env.get(v) for v in SSH_VARS):
        return False
    if env.get("CLAUDE_CODE_ENTRYPOINT", "") not in INTERACTIVE_ENTRYPOINTS or env.get("CLAUDE_CODE_SESSION_ATTENDED") == "0":
        return False
    if (claude_ancestors() if ancestors is None else ancestors) > 1:
        return False
    return (session_env_clean() if ancestors is None else True) if clean is None else clean


def should_log(payload: object, env: dict[str, str] | None = None, ancestors: int | None = None, clean: bool | None = None) -> bool:
    """True for a prompt a person typed: see the module docstring. ``ancestors`` and ``clean`` override the process probes (tests)."""
    env = dict(os.environ) if env is None else env
    if not isinstance(payload, dict) or payload.get("agent_id"):
        return False
    if payload.get("hook_event_name", "UserPromptSubmit") != "UserPromptSubmit":
        return False
    prompt = payload.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        return False
    if prompt.lstrip().lower().startswith(NOTICE_TAGS):
        return False
    return interactive(env, ancestors, clean)


def prune(folder: Path, now: datetime) -> None:
    """Delete monthly files older than the previous month (the gate reads 14 days)."""
    keep = {f"{now:%Y-%m}", f"{(now.replace(day=1) - timedelta(days=1)):%Y-%m}"}
    for file in folder.glob("*.jsonl"):
        if file.stem not in keep:
            try:
                file.unlink()
            except OSError:
                pass


def append(payload: dict, now: datetime | None = None, home: str | None = None) -> Path:
    """Append the row for ``payload`` to this month's file (created mode 600 in a mode 700 folder); returns the file."""
    now = now or datetime.now(timezone.utc)
    prompt = payload["prompt"]
    row = {"ts": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "session": str(payload.get("session_id", "")),
           "cwd": str(payload.get("cwd", "")), "sha256": hashlib.sha256(prompt.encode("utf-8")).hexdigest(), "prompt": prompt}
    folder = log_dir(home)
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    prune(folder, now)
    path = folder / f"{now:%Y-%m}.jsonl"
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, (json.dumps(row, ensure_ascii=False) + "\n").encode("utf-8"))
    finally:
        os.close(fd)
    return path


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        if should_log(payload):
            append(payload)
    except Exception:  # noqa: BLE001 (a log failure must never block the owner's prompt)
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
