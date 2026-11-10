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

try:
    import json
    import os

    import deny_rules
    import triage_session
except Exception as error:  # noqa: BLE001 - fail closed even if a sibling module cannot be imported
    print(f"Blocked: triage_deny could not import its modules ({type(error).__name__}); refusing (fails closed).", file=sys.stderr)
    sys.exit(2)

#: Always in force for a registered session (see the module docstring).
BASELINE_DENY = (
    "mcp__t3-code__*",
    "!mcp__t3-code__device_list", "!mcp__t3-code__device_open", "!mcp__t3-code__device_screenshot", "!mcp__t3-code__device_close",
    "Bash(*hass-agents/t3*)", "Read(//**/hass-agents/t3/**)", "Write(//**/hass-agents/t3/**)", "Edit(//**/hass-agents/t3/**)",
)


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
        rule = deny_rules.decide([*BASELINE_DENY, *found.deny], tool, tool_input, project, payload.get("cwd") or project)
    except Exception as error:  # noqa: BLE001 - fail closed
        print(message(f"the call could not be checked ({type(error).__name__})"), file=sys.stderr)
        return 2
    if rule:
        print(message(f"{tool} is on the session's deny list (rule: {rule})"), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
