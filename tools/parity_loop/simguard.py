"""Simulator safety for the parity tools: protected devices and a per-device ``devcap`` hold.

Call :func:`guard` before a tool boots a simulator or changes one of its settings, passing the simulators' UDIDs and the process
environment. It refuses, before anything runs, a simulator in :data:`PROTECTED` and any simulator whose ``device-<UDID>`` gate the
process does not hold (``tools/devcap.py run --sim UDID ...`` puts every held gate in ``DEVCAP_HELD``). A hold on some other
simulator, or on the shared ``simulator`` pool alone, is not enough.
"""

from __future__ import annotations

from typing import Dict, FrozenSet, Iterable, Mapping

#: Simulators no parity tool may boot, install on or reconfigure, with the reason. Matched on the whole UDID or its first eight characters.
PROTECTED: Dict[str, str] = {
    "D14299B9-9F37-437D-85CE-208E13B01087": "the iPhone Duo other sessions keep booted for device checks",
    "366D4D0F-8AE1-44F1-988B-E4D2DBDD1672": "the pinned reference simulator; it must stay as pinned",
}
HELD_VARIABLE = "DEVCAP_HELD"


class Refused(Exception):
    """A simulator the tool will not use; the message names the reason and carries no secret."""


def _protected_reason(udid: str) -> str:
    """The reason ``udid`` (whole or its first eight characters, any case) is protected, or ``""``."""
    text = udid.strip().upper()
    if len(text) < 8:
        return ""
    return next((reason for full, reason in PROTECTED.items() if full.startswith(text)), "")


def is_protected(udid: str) -> bool:
    return bool(_protected_reason(udid))


def refuse_protected(udids: Iterable[str]) -> None:
    for udid in udids:
        reason = _protected_reason(udid)
        if reason:
            raise Refused(f"refused: simulator {udid} is protected ({reason})")


def held_gates(env: Mapping[str, str]) -> FrozenSet[str]:
    return frozenset(g for g in env.get(HELD_VARIABLE, "").split(",") if g)


def require_device_holds(udids: Iterable[str], env: Mapping[str, str]) -> None:
    """Each simulator needs its own ``device-<UDID>`` gate in ``DEVCAP_HELD``, and the ``simulator`` pool must be held too."""
    held = held_gates(env)
    if "simulator" not in held:
        raise Refused("refused: take a devcap simulator hold first (tools/devcap.py run --sim UDID ...)")
    for udid in udids:
        if f"device-{udid}" not in held:
            raise Refused(f"refused: this process holds no devcap gate for simulator {udid} (tools/devcap.py run --sim {udid} ...)")


def guard(udids: Iterable[str], env: Mapping[str, str]) -> None:
    """Refuse a protected simulator, then a simulator this process does not hold, before the tool touches either."""
    udids = list(udids)
    refuse_protected(udids)
    require_device_holds(udids, env)
