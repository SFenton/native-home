#!/usr/bin/env python3
"""Stop hook: do not end a turn while work this session started is still running, or while waiting out loud.

Blocks the stop (JSON ``decision: block``; the reason goes back to the agent) when either

(a) background work from this session is unfinished: a ``tools/bg_run.py`` job whose ``build/runs/LABEL.running``
    marker names a live pid and whose label appears in this session's transcript, or an ``Agent`` call with
    ``run_in_background`` whose completion notification has not arrived; or
(b) the last assistant message is waiting narration ("I'll wait", "will report back", "once it finishes", ...).

Headless only: the hook is active just when the environment has ``FENTON_HEADLESS=1`` (the triage runner sets it
for every ``claude -p`` it launches, where exiting kills background children). In interactive sessions it allows
immediately, before reading any input: ending the turn while background work runs is correct there, because the
completion notification re-invokes the agent and the repo's token-economy rule is to end the turn, never poll.

Never traps: when ``stop_hook_active`` is true (already continuing because of a stop hook) the stop is allowed, and
any error, missing or malformed input allows it. It reads the transcript as bytes and parses only the tail, so a
50 MB transcript costs milliseconds. Registered for ``Stop``; ``SubagentStop`` is served by ``subagent_report.py``,
whose payload carries no background-job information, so this hook is not registered there.

Assumed transcript format (unverified against future Claude Code versions; the hook fails open if it changes): JSON
lines, each an object with ``message.role`` (or ``type``) and ``message.content`` as a string or a list of blocks
(``text``, ``tool_use`` with ``id``/``name``/``input``, ``tool_result`` with ``tool_use_id``/``content``). A background
``Agent`` call is "finished" when a non-assistant entry (user, queue-operation or attachment) containing ``task-notification`` mentions its ``agentId``; if the
``agentId`` cannot be read from the tool result the hook never blocks on it. A line that is not that shape is
skipped, so the worst case is one missed block or one unneeded block (the second stop is always allowed).
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

try:  # the registry of T3-launched triage sessions: a registered session gets the runner's markers (tools/hooks/triage_session.py)
    import triage_session
except Exception:  # noqa: BLE001 - triage_deny fails closed when the module is gone
    triage_session = None

TAIL_BYTES = 4 * 1024 * 1024
WAITING = re.compile(
    r"\bI(?:'ll| will) (?:wait|hold off|stand by|check back)\b"
    r"|\bwaiting (?:for|on) (?:the |it\b|them\b|that\b|those\b)"
    r"|\bwill report back\b|\bI(?:'ll| will) report back\b"
    r"|\bonce (?:it|they|that|this|the \w+) (?:finish(?:es)?|complete[sd]?|is done|are done)\b"
    r"|\bwhen (?:it|they|that|this) (?:finish(?:es)?|complete[sd]?)\b"
    r"|\bwill (?:be notified|get notified|pick (?:this|it) up)\b"
    r"|\bending (?:the|my) turn (?:here|now) (?:and|to) wait\b",
    re.IGNORECASE,
)

BACKGROUND_REASON = (
    "Background work you started is still running: {what}. Ending the turn in a headless session kills it and no "
    "notification will wake you. Use the time for the rest of the task. If nothing is left, commit a WIP and "
    "finish blocked with blocked_reason \"waiting_bg: <label>\"."
)
WAITING_REASON = (
    "Your last message says you are waiting. A turn that ends waiting finishes nothing. If background work is "
    "running, its notification will wake you: continue the task now with what you can do, then finish. If you are "
    "truly blocked, say why plainly and finish with a blocked status."
)


def read_tail(path: str, limit: int = TAIL_BYTES) -> bytes:
    """The last ``limit`` bytes of ``path``, starting at a line boundary."""
    with open(path, "rb") as handle:
        handle.seek(0, os.SEEK_END)
        size = handle.tell()
        handle.seek(max(0, size - limit))
        data = handle.read()
    if size > limit:
        data = data.split(b"\n", 1)[-1]
    return data


def entries(data: bytes) -> Iterable[Dict[str, Any]]:
    """Parsed JSONL entries in ``data``; unparseable lines are skipped."""
    for line in data.splitlines():
        line = line.strip()
        if not line.startswith(b"{"):
            continue
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict):
            yield item


def blocks(entry: Dict[str, Any]) -> List[Any]:
    """Content blocks of a transcript entry (text entries become one text block)."""
    message = entry.get("message")
    content = message.get("content") if isinstance(message, dict) else entry.get("content")
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return [b for b in content if isinstance(b, dict)] if isinstance(content, list) else []


def role(entry: Dict[str, Any]) -> str:
    message = entry.get("message")
    return str((message or {}).get("role") or entry.get("type") or "")


def last_assistant_text(items: List[Dict[str, Any]]) -> str:
    """Text of the final assistant message, or empty when it was only tool calls."""
    for entry in reversed(items):
        if role(entry) != "assistant":
            continue
        return "\n".join(str(b.get("text", "")) for b in blocks(entry) if b.get("type") == "text")
    return ""


def pending_agents(items: List[Dict[str, Any]]) -> List[str]:
    """Descriptions of ``run_in_background`` Agent calls with no completion notification after them."""
    launched: Dict[str, Dict[str, str]] = {}
    for entry in items:
        for b in blocks(entry):
            if b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task"):
                inp = b.get("input") or {}
                if inp.get("run_in_background") is True:
                    launched[str(b.get("id"))] = {"desc": str(inp.get("description") or "agent"), "agent": ""}
            elif b.get("type") == "tool_result" and str(b.get("tool_use_id")) in launched:
                text = json.dumps(b.get("content"))
                found = re.search(r"agentId[\"':= \\]+([A-Za-z0-9_-]{6,})", text)
                if found:
                    launched[str(b["tool_use_id"])]["agent"] = found.group(1)
    if not launched:
        return []
    # Claude Code stores a completion notice as a user entry, a ``queue-operation`` entry (string ``content`` with
    # ``<task-id>ID</task-id>``) or an ``attachment`` entry: read every non-assistant entry, whole.
    notices = [json.dumps(e) for e in items if role(e) != "assistant"]
    notices = [n for n in notices if "task-notification" in n or "task_notification" in n]
    pending = []
    for info in launched.values():
        agent = info["agent"]
        if not agent:
            continue  # cannot tell whether it finished: never block on a guess
        if not any(agent in n for n in notices):
            pending.append(info["desc"])
    return pending


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def run_dirs(event: Dict[str, Any]) -> List[Path]:
    """Candidate ``build/runs`` directories: the test override, the project dir, the event cwd."""
    override = os.environ.get("BG_RUNS_DIR")
    if override:
        return [Path(override)]
    roots = [os.environ.get("CLAUDE_PROJECT_DIR"), event.get("cwd")]
    return [Path(r) / "build" / "runs" for r in roots if r]


def running_jobs(event: Dict[str, Any], transcript: bytes) -> List[str]:
    """Labels of live ``bg_run.py`` jobs whose launch appears in this session's transcript."""
    labels: List[str] = []
    for directory in run_dirs(event):
        try:
            markers = list(directory.glob("*.running"))
        except OSError:
            continue
        for marker in markers:
            try:
                info = json.loads(marker.read_text())
                label, pid = str(info["label"]), int(info["pid"])
            except (OSError, ValueError, KeyError, TypeError):
                continue
            if label in labels or not alive(pid):
                continue
            if f"bg_run.py {label}".encode() in transcript or f"bg_run.py\\\" {label}".encode() in transcript:
                labels.append(label)
    return labels


def decide(event: Dict[str, Any]) -> Optional[str]:
    """The block reason for ``event``, or ``None`` to allow the stop."""
    if event.get("stop_hook_active"):
        return None
    path = event.get("transcript_path")
    if not path or not os.path.isfile(path):
        return None
    data = read_tail(path)
    items = list(entries(data))
    parts = []
    jobs = running_jobs(event, data)
    if jobs:
        parts.append("bg_run job(s) " + ", ".join(jobs))
    agents = pending_agents(items)
    if agents:
        parts.append("background agent(s) " + ", ".join(agents))
    if parts:
        return BACKGROUND_REASON.format(what="; ".join(parts))
    if WAITING.search(last_assistant_text(items)):
        return WAITING_REASON
    return None


def main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except Exception:  # never trap a session on a hook bug
        event = None
    if triage_session:  # a T3-launched triage session carries the runner's markers through its registry record
        triage_session.apply(event if isinstance(event, dict) else {})
    if os.environ.get("FENTON_HEADLESS") != "1":  # interactive: the completion notification wakes the agent
        return 0
    try:
        reason = decide(event) if isinstance(event, dict) else None
    except Exception:  # never trap a session on a hook bug
        return 0
    if reason:
        print(json.dumps({"decision": "block", "reason": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
