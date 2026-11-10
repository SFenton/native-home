#!/usr/bin/env python3
"""The GitHub login agents act as, when it is not the owner's (owner decision 2026-11-09: a machine-user collaborator).

The login is a name, not a secret. ``tools/triage/config.json`` names the machine user in ``agent_login`` (``sfenton-agent``, owner, 2026-11-10); empty would mean only SFenton. It is read from
that file **only**: there is no override from the process settings, because anything an agent session can set in front of a command
(an ``X=y tools/ship.sh`` prefix, a shell profile) would widen the author gates without touching a pinned file. The config file is
hashed against ``origin/<base>`` by the landing-tool pin (``merge_guard.PINNED_WITH``), so changing who counts as the agents' own is a
reviewed change.

With none configured :func:`resolve` returns ``""`` and every consumer behaves exactly as before the second account existed: the owner,
:data:`OWNER`, is the only login that counts as an agent's own. With one, :func:`own_logins` is ``{OWNER, agent}`` for the **author
gates** (``pr_land``, ``merge_guard``). The agent login is never an owner: it is not among the triage ``authors`` that vouch for a
request or issue a reply or command; the runner picks up its issues only when they carry ``Workflow`` (:func:`is_agent`), and
``pr_note`` still addresses ``@SFenton``. Standard library only.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import FrozenSet

#: The owner's login, a constant (``gh api user`` returns the agent once the agent account is ``gh``'s default).
OWNER = "SFenton"
_SHAPE = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})")


def valid(value: object) -> bool:
    """Is ``value`` a GitHub user login (letters, digits, hyphens; at most 39 characters)?"""
    return isinstance(value, str) and _SHAPE.fullmatch(value.strip()) is not None


def configured(config: Path) -> str:
    """``agent_login`` of the config file ``config`` (``tools/triage/config.json``); ``""`` when absent, empty or unreadable."""
    try:
        value = json.loads(Path(config).read_text()).get("agent_login")
    except (OSError, ValueError, AttributeError):
        return ""
    return value if isinstance(value, str) else ""


def resolve(configured_value: object = None) -> str:
    """The agent login, or ``""`` when none is configured: ``configured_value`` (``agent_login`` of ``tools/triage/config.json``) if it
    is a valid login. A malformed value is skipped, never an error. A value equal to the owner's login counts as none (the owner is
    already accepted)."""
    if valid(configured_value) and str(configured_value).strip().lower() != OWNER.lower():
        return str(configured_value).strip()
    return ""


def own_logins(configured_value: object = None) -> FrozenSet[str]:
    """Lower-cased logins whose pull requests are the agents' own: the owner and, when configured, the agent login."""
    agent = resolve(configured_value)
    return frozenset({OWNER.lower(), *([agent.lower()] if agent else [])})


def is_own(login: object, configured_value: object = None) -> bool:
    """Whether ``login`` (as ``gh`` reports it) is the owner or the configured agent login; ``None`` and ``""`` never are."""
    return isinstance(login, str) and bool(login) and login.lower() in own_logins(configured_value)


def is_agent(login: object, configured_value: object = None) -> bool:
    """Whether ``login`` is the configured agent login (never the owner, never true when none is configured)."""
    agent = resolve(configured_value)
    return bool(agent) and isinstance(login, str) and login.lower() == agent.lower()
