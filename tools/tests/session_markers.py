"""Pin a tool-test module to a session with no agent markers.

Agent sessions (headless triage, T3 Code threads, Claude Code hooks) export variables that the guards under test read to decide
whether the caller is an agent. A test that expects the plain-owner answer fails wherever one of them is set, and a test that
expects the agent answer passes only by accident of the environment. A module that reads those guards calls :func:`pin` in
``setUpModule`` and :func:`unpin` in ``tearDownModule``::

    from session_markers import pin as setUpModule, unpin as tearDownModule

A test that needs a marker sets it itself with ``mock.patch.dict(os.environ, {...})``; that patch nests inside this one.
"""

import os
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional
from unittest import mock

#: Exact variable names that mark an agent session.
MARKERS = ("FENTON_HEADLESS", "CLAUDE_PROJECT_DIR", "CLAUDE_ENV_FILE")

#: Name prefixes that mark an agent session: the triage runner's and T3 Code's.
MARKER_PREFIXES = ("HASS_TRIAGE_", "T3CODE_")

_PATCHES: List[object] = []
_FOLDERS: List[tempfile.TemporaryDirectory] = []


def marker_names(environ: Optional[Dict[str, str]] = None) -> List[str]:
    """Return the session-marker variables present in ``environ`` (default ``os.environ``)."""
    source = os.environ if environ is None else environ
    return sorted(name for name in source if name in MARKERS or name.startswith(MARKER_PREFIXES))


def pin() -> None:
    """Remove every session marker from ``os.environ`` and point the triage-session lookup at an empty folder, until :func:`unpin`.

    The hooks also find a triage session by looking the current worktree (and the thread id) up in the runner's session records
    (``tools/hooks/triage_session.py``), so a worktree the runner registered is an agent session with no marker set. Idempotent while pinned.
    """
    if _PATCHES:
        return
    env = mock.patch.dict(os.environ)
    env.start()
    _PATCHES.append(env)
    for name in marker_names():
        del os.environ[name]
    hooks = str(Path(__file__).resolve().parents[1] / "hooks")
    if hooks not in sys.path:
        sys.path.insert(0, hooks)
    import triage_session
    folder = tempfile.TemporaryDirectory(prefix="empty-session-records-")
    _FOLDERS.append(folder)
    lookup = mock.patch.object(triage_session, "registry_root", return_value=Path(folder.name))
    lookup.start()
    _PATCHES.append(lookup)


def unpin() -> None:
    """Undo :func:`pin`: restore the environment and the session-record lookup."""
    while _PATCHES:
        _PATCHES.pop().stop()  # type: ignore[attr-defined]
    while _FOLDERS:
        _FOLDERS.pop().cleanup()
