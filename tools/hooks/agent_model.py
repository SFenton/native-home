#!/usr/bin/env python3
"""PreToolUse hook for Agent: delegated work must not inherit Opus by accident.

The orchestrator and `designer` run on Fable 5.2 (medium, pinned in their files); the final review (`reviewer`)
stays on Opus; lanes run on `coder`, `researcher`, `verifier` and `steward` (Sonnet) and chores on `menial` (Haiku).
`coder` and `researcher` may be escalated to Fable by an explicit full model id in the spawn; no other type may,
and the reviewer never runs on Fable, even with `opus-ok`. A spawn
passes when it names `coder`, `menial`, `Explore`, `Plan` or a docs/web helper, or sets `model` to Sonnet or
Haiku. A `general-purpose` spawn with no model, or any spawn asking for Opus, is refused with the fix. A spawn
that really needs Opus (the final reviewer) says `opus-ok: reason` in its prompt. Exit 2 sends the message back.
"""

from __future__ import annotations

import json
import sys
from typing import Dict, List, Optional

LANE_TYPES = {"designer", "coder", "menial", "researcher", "verifier", "steward", "Explore", "Plan", "claude-code-guide", "statusline-setup", "web-fetch"}
#: Agents whose files pin Opus: the spawn must say why with `opus-ok:`.
OPUS_TYPES = {"reviewer"}
#: Agents whose files pin Fable (`designer`) or that may be escalated to it by an explicit model in the spawn.
FABLE_TYPES = {"designer", "coder", "researcher"}
CHEAP = ("sonnet", "haiku")

MESSAGE = (
    "Blocked: this subagent would run on Opus. Delegate with subagent_type \"coder\" (Sonnet, implementation, "
    "tests, builds) or \"menial\" (Haiku: re-runs, logs, git chores), or pass model \"sonnet\"/\"haiku\". Opus is "
    "for the final review (`reviewer`); if this spawn is one, put `opus-ok: reason` in its prompt. Fable is for `designer` and, by explicit `model`, `coder`/`researcher`. "
    "See .agents/workflow/token-economy.md."
)


def reason(tool_input: Dict) -> Optional[str]:
    """Why the spawn is refused, or ``None``."""
    kind = tool_input.get("subagent_type")
    if "fable" in str(tool_input.get("model") or "").lower() and kind not in FABLE_TYPES:
        return f"{kind or 'general-purpose'} may not run on Fable"
    if "opus-ok" in str(tool_input.get("prompt", "")):
        return None
    if kind in OPUS_TYPES:
        return f"{kind} runs on Opus"
    model = str(tool_input.get("model") or "").lower()
    if "opus" in model:
        return "model is Opus"
    if any(name in model for name in CHEAP):
        return None
    if kind in LANE_TYPES:
        return None
    return f"subagent_type {kind or 'general-purpose'} with no model inherits Opus"


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") not in ("Agent", "Task"):
        return 0
    why = reason(payload.get("tool_input") or {})
    if why:
        print(f"{MESSAGE} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
