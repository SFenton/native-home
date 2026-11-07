#!/usr/bin/env python3
"""Which private repository holds the requests: local configuration, never the repository (house-config-runtime, decision 7).

``tools/triage/config.json`` leaves ``request_repo`` empty. The real ``owner/name`` comes from this
machine, first match wins:

1. the ``FENTON_REQUEST_REPO`` environment variable;
2. the first line of ``~/.config/fenton-hass/request_repo`` (a plain file; the folder holds the other local settings and secrets,
   so agents never read it, only this module does, at runtime);
3. the configured value itself, when it is an ``owner/name`` (``tools/triage/config.json`` leaves it empty; the triage runner's own
   ``~/.config/hass-triage/config.json`` override still works and arrives here as ``configured``).

With none of them the repository is **not configured**: :func:`resolve` returns ``None``, :func:`require` raises :class:`NotConfigured`,
the triage runner refuses to start and ``merge_guard`` refuses every guarded ``gh`` write in a headless session. Nothing acts on a
made-up repository name. Standard library only.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Mapping, Optional


class NotConfigured(RuntimeError):
    """No request repository is configured on this machine (see :func:`resolve` for where to set it)."""

#: The environment variable that wins over the local file.
ENV_VAR = "FENTON_REQUEST_REPO"
_SHAPE = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")


def local_file(home: Optional[Path] = None) -> Path:
    """``~/.config/fenton-hass/request_repo`` under ``home`` (default: the ``HOME`` of this process)."""
    return (home or Path(os.path.expanduser("~"))) / ".config" / "fenton-hass" / "request_repo"


def valid(value: object) -> bool:
    """Is ``value`` an ``owner/name`` pair?"""
    return isinstance(value, str) and _SHAPE.fullmatch(value.strip()) is not None


def resolve(configured: object = None, home: Optional[Path] = None, environ: Optional[Mapping[str, str]] = None) -> Optional[str]:
    """The request repository as ``owner/name`` (see the module doc for the order), or ``None`` when none is configured.

    ``configured`` is the ``request_repo`` the config file (or the triage runner's local override) holds. An unreadable or
    malformed source is skipped, never an error."""
    env = os.environ if environ is None else environ
    candidate = env.get(ENV_VAR, "")
    if valid(candidate):
        return candidate.strip()
    try:
        lines = local_file(home).read_text(encoding="utf-8").splitlines()
    except OSError:
        lines = []
    if lines and valid(lines[0]):
        return lines[0].strip()
    if valid(configured):
        return str(configured).strip()
    return None


def require(configured: object = None, home: Optional[Path] = None, environ: Optional[Mapping[str, str]] = None) -> str:
    """:func:`resolve`, raising :class:`NotConfigured` with the setting to create when there is no request repository."""
    value = resolve(configured, home, environ)
    if value is None:
        raise NotConfigured(f"the request repository is not configured: set {ENV_VAR}=owner/name, or write owner/name as the first line of "
                            f"{local_file(home)} (see .agents/workflow/triage-agent.md)")
    return value
