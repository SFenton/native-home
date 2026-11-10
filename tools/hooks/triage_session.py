#!/usr/bin/env python3
"""The registry of T3-launched triage sessions, and the hook that arms them (SessionStart).

A headless runner session gets its guards from the runner's process: the deny list as ``--disallowedTools``, the headless markers as
environment, the timeout as a process-group kill. A session T3 Code starts from its own server has none of those, so the runner writes a
**record** before the launch and the hooks read it back:

* ``<root>/worktrees/<sha256(realpath worktree)[:16]>.json``: exists before the thread does, so the first tool call is already covered.
  Hooks find it with ``CLAUDE_PROJECT_DIR`` (which does not move when the agent runs ``cd /tmp``) or the payload's ``cwd`` and its parents.
* ``<root>/threads/<thread id>.json``: a copy that also carries ``thread_id``, written once the handover returns; hooks find it with
  ``T3CODE_THREAD_ID``.

``root`` is ``~/hass-agents/t3`` (directory mode 700, files 600, written atomically). A record is never removed when a session ends, only
set to ``ended`` (a woken old thread stays a triage session); the runner's cleanup calls :func:`forget` with the worktree. ``expires`` is
informational: an expired record still guards.

Schema v1 (exactly): ``{v: 1, launch_id, kind: request|nightly|job|retro, issue, role, worktree, branch, thread_id, state:
launching|running|ended, started, expires, env: {name: value}, deny: [rule], hook_sha: {file: sha256}}``. ``env`` is what the runner's
``_launch`` puts in a session's environment (``FENTON_HEADLESS``, ``HASS_TRIAGE_*``, ``FENTON_DEVCAP_MAX_WAIT``; a ``PATH`` entry is
exported to tool shells too) and ``deny`` is the effective deny list (Claude Code permission-rule syntax, see ``deny_rules``).

**Fail closed.** Absence cannot (an owner session in T3 also carries a thread id), so: no record under either key means an ordinary
session and nothing changes; a record that exists but is unreadable, has another version, lacks the ``env`` or ``deny`` lists, or sits
under a key its ``worktree`` does not hash to, is a *strict* triage session: every tool call is denied (``triage_deny``) and every other hook
treats it as headless.

API for the launcher: :func:`build_record`, :func:`write_record`, :func:`set_state`, :func:`forget`, :func:`hash_hooks`.
API for hooks and tools: :func:`resolve`, :func:`apply`, :func:`session_env`, :func:`registered`.
Standard library only; importing it has no side effects.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Mapping, MutableMapping, Optional, Tuple

SCHEMA_VERSION = 1
THREAD_ENV = "T3CODE_THREAD_ID"
KINDS = ("request", "nightly", "job", "retro")
STATES = ("launching", "running", "ended")
#: The hook files whose bytes the launcher records (and compares at launch and at the end of the session).
#: Built from bare module names on purpose: ``release_closure`` follows script names written in string constants, and the review guard
#: (a fixed-set file that loads this module) must stay self-contained.
GUARD_FILES = tuple(f"tools/hooks/{name}.py" for name in ("triage_deny", "triage_session", "deny_rules", "shell_parse"))
#: Removed from the tool shells of a registered session: the runner scrubs these from a headless environment, T3's own is not scrubbed.
SCRUB_ENV = ("GH_TOKEN", "GITHUB_TOKEN", "GH_CONFIG_DIR", "XDG_CONFIG_HOME", "TYPESAFE_API_KEY",
             "FENTON_HASS_TOKEN", "FENTON_HASS_PASSWORD", "FENTON_HASS_USERNAME")
_THREAD_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z")
_ENV_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


# MARK: - Locations

def registry_root(home: Optional[str] = None) -> Path:
    """The registry folder, ``~/hass-agents/t3``. There is deliberately no environment override: a session could set it."""
    return Path(home or os.path.expanduser("~")) / "hass-agents" / "t3"


def worktree_key(worktree: "str | Path") -> str:
    """The path key: the first 16 hex digits of the sha256 of the worktree's real path."""
    return hashlib.sha256(os.path.realpath(str(worktree)).encode("utf-8")).hexdigest()[:16]


def path_record(worktree: "str | Path", root: Optional[Path] = None) -> Path:
    """Where the path-keyed record of ``worktree`` lives."""
    return (root or registry_root()) / "worktrees" / f"{worktree_key(worktree)}.json"


def thread_record(thread_id: str, root: Optional[Path] = None) -> Path:
    """Where the thread-keyed record of ``thread_id`` lives. Raises ``ValueError`` for an id that is not a plain token."""
    if not _THREAD_ID.match(thread_id or ""):
        raise ValueError(f"not a usable thread id: {thread_id!r}")
    return (root or registry_root()) / "threads" / f"{thread_id}.json"


# MARK: - Writing (the launcher)

def build_record(kind: str, issue: "int | str | None", role: str, worktree: "str | Path", branch: str, env: Mapping[str, str],
                 deny: List[str], ttl_hours: float = 12.0, thread_id: Optional[str] = None, state: str = "launching",
                 hook_sha: Optional[Mapping[str, str]] = None, now: Optional[datetime] = None) -> Dict[str, Any]:
    """A schema-v1 record. ``launch_id`` is generated; ``worktree`` is stored as its real path."""
    now = now or datetime.now(timezone.utc)
    return {"v": SCHEMA_VERSION, "launch_id": uuid.uuid4().hex, "kind": kind, "issue": issue, "role": role,
            "worktree": os.path.realpath(str(worktree)), "branch": branch, "thread_id": thread_id, "state": state,
            "started": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "expires": (now + timedelta(hours=ttl_hours)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "env": dict(env), "deny": list(deny), "hook_sha": dict(hook_sha or {})}


def validate(record: Any, strict_fields: bool = True) -> Optional[str]:
    """Why ``record`` is not a usable v1 record, or ``None``. Reading checks only what the guards need (``strict_fields`` false)."""
    if not isinstance(record, dict) or record.get("v") != SCHEMA_VERSION:
        return "wrong or missing schema version"
    env, deny = record.get("env"), record.get("deny")
    if not isinstance(env, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in env.items()):
        return "env is not a string map"
    if not isinstance(deny, list) or not all(isinstance(r, str) for r in deny):
        return "deny is not a list of strings"
    if not isinstance(record.get("worktree"), str) or not record["worktree"]:
        return "worktree is missing"
    if strict_fields:
        if record.get("kind") not in KINDS or record.get("state") not in STATES:
            return "kind or state is not one of the known values"
        for name in ("launch_id", "role", "branch", "started", "expires"):
            if not isinstance(record.get(name), str):
                return f"{name} is not a string"
        if record.get("thread_id") is not None and not isinstance(record["thread_id"], str):
            return "thread_id is not a string"
    return None


def _atomic_write(path: Path, data: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, data.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, path)


def write_record(record: Dict[str, Any], root: Optional[Path] = None) -> Path:
    """Write ``record`` under its path key, and under its thread key too when ``record["thread_id"]`` is set. Returns the path key's file.

    Call it once before the handover (``thread_id`` unset) and again with the thread id once the handover returns. Raises ``ValueError`` for
    a record that does not validate and ``OSError`` when it cannot be written: the launcher must abort the launch on either.
    """
    problem = validate(record)
    if problem:
        raise ValueError(f"invalid triage record: {problem}")
    root = root or registry_root()
    root.mkdir(parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    data = json.dumps(record, indent=1, sort_keys=True) + "\n"
    thread_id = record.get("thread_id")
    if thread_id:
        _atomic_write(thread_record(thread_id, root), data)
    target = path_record(record["worktree"], root)
    _atomic_write(target, data)
    return target


def set_state(worktree: "str | Path", state: str, root: Optional[Path] = None) -> bool:
    """Set ``state`` (usually ``ended``) on the worktree's records. False when there is no valid record to update."""
    if state not in STATES:
        raise ValueError(f"unknown state {state!r}")
    root = root or registry_root()
    try:
        record = json.loads(path_record(worktree, root).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    if validate(record, strict_fields=False):
        return False
    record["state"] = state
    write_record(record, root)
    return True


def forget(worktree: "str | Path", root: Optional[Path] = None) -> List[Path]:
    """Remove the records of ``worktree`` (its path key and every thread key naming it); returns what was removed.

    Only the runner's cleanup calls this, together with ``git worktree remove``."""
    root = root or registry_root()
    wanted = os.path.realpath(str(worktree))
    doomed = [path_record(worktree, root)]
    for file in sorted((root / "threads").glob("*.json")) if (root / "threads").is_dir() else []:
        try:
            if os.path.realpath(str(json.loads(file.read_text(encoding="utf-8")).get("worktree", ""))) == wanted:
                doomed.append(file)
        except (OSError, ValueError, AttributeError):
            continue
    removed = []
    for file in doomed:
        try:
            file.unlink()
            removed.append(file)
        except FileNotFoundError:
            continue
    return removed


def hash_hooks(repo: "str | Path") -> Dict[str, str]:
    """``{relative path: sha256}`` of the :data:`GUARD_FILES` under ``repo`` (a missing file is left out)."""
    out = {}
    for rel in GUARD_FILES:
        try:
            out[rel] = hashlib.sha256((Path(repo) / rel).read_bytes()).hexdigest()
        except OSError:
            continue
    return out


# MARK: - Resolving (the hooks and tools)

@dataclass(frozen=True)
class Resolution:
    """A registered session: ``record`` (``{}`` when strict and unreadable), how it was found (``via``), and what it imposes."""

    record: Dict[str, Any]
    via: str
    strict: bool = False
    reason: str = ""
    env: Dict[str, str] = field(default_factory=dict)
    deny: Tuple[str, ...] = ()


def _load(path: Path, keyed_by: Optional[str] = None) -> "Tuple[Optional[Dict[str, Any]], str]":
    """``(record, "")`` for a good file, ``(None, "")`` when it does not exist, ``(None, why)`` when it exists but cannot be trusted."""
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None, ""
    except OSError as error:
        return None, f"{path.name} is unreadable ({type(error).__name__})"
    try:
        record = json.loads(text)
    except ValueError:
        return None, f"{path.name} is not JSON"
    problem = validate(record, strict_fields=False)
    if problem:
        return None, f"{path.name}: {problem}"
    if keyed_by is not None and worktree_key(record["worktree"]) != keyed_by:
        return None, f"{path.name} does not belong to its key"
    return record, ""


def _path_candidates(project_dir: Optional[str], payload: Mapping[str, Any]) -> List[str]:
    """Real paths to try as a worktree: the project directory, then the payload's ``cwd`` and every parent of it."""
    found: List[str] = []
    if project_dir:
        found.append(os.path.realpath(project_dir))
    cwd = payload.get("cwd") if isinstance(payload, Mapping) else None
    if isinstance(cwd, str) and cwd:
        here = Path(os.path.realpath(cwd))
        found.extend(str(p) for p in (here, *here.parents) if str(p) != "/")
    return list(dict.fromkeys(found))


def resolve(env: Mapping[str, str], payload: Optional[Mapping[str, Any]] = None, root: Optional[Path] = None,
            project_dir: Optional[str] = None) -> Optional[Resolution]:
    """The :class:`Resolution` of the session with environment ``env`` and hook payload ``payload``, or ``None`` for an ordinary session.

    Order: the thread record (``T3CODE_THREAD_ID``), then the path record (``project_dir``, default ``CLAUDE_PROJECT_DIR``; then the payload's
    ``cwd`` and its parents). A record that exists but cannot be trusted makes the session *strict*, whichever key found it.
    """
    root = root or registry_root()
    payload = payload if isinstance(payload, Mapping) else {}
    good: List[Tuple[str, Dict[str, Any]]] = []
    bad: List[str] = []
    thread_id = env.get(THREAD_ENV) or ""
    if thread_id and _THREAD_ID.match(thread_id):
        record, why = _load(root / "threads" / f"{thread_id}.json")
        if record:
            good.append(("thread", record))
        elif why:
            bad.append(why)
    for candidate in _path_candidates(project_dir if project_dir is not None else env.get("CLAUDE_PROJECT_DIR"), payload):
        key = hashlib.sha256(candidate.encode("utf-8")).hexdigest()[:16]
        record, why = _load(root / "worktrees" / f"{key}.json", keyed_by=key)
        if record:
            good.append(("path", record))
        elif why:
            bad.append(why)
    if not bad:
        if not good:
            return None
        via, record = good[0]
        return Resolution(record, via, env=dict(record["env"]), deny=tuple(record["deny"]))
    env_map = dict(good[0][1]["env"]) if good else {}
    env_map["FENTON_HEADLESS"] = "1"
    return Resolution(good[0][1] if good else {}, good[0][0] if good else "path", strict=True, reason="; ".join(bad), env=env_map,
                      deny=tuple(good[0][1]["deny"]) if good else ())


def apply(payload: Optional[Mapping[str, Any]] = None, env: Optional[MutableMapping[str, str]] = None,
          root: Optional[Path] = None) -> Optional[Resolution]:
    """Resolve the session and, when registered, overlay the record's ``env`` on ``env`` (default ``os.environ``). Never raises.

    The hooks call this first so their ``FENTON_HEADLESS`` and ``HASS_TRIAGE_*`` reads see what a headless runner session would have had."""
    target = os.environ if env is None else env
    try:
        found = resolve(target, payload, root)
    except Exception:  # noqa: BLE001 - an unexpected failure must not turn a guard hook into a crash; bad records already resolve as strict
        return None
    if found:
        target.update(found.env)
    return found


def session_env(env: Optional[Mapping[str, str]] = None, cwd: Optional[str] = None, root: Optional[Path] = None) -> Optional[Dict[str, str]]:
    """For scripts that run from a tool shell (``pr_land``, ``lane_land``): the record's ``env`` when this process is inside a registered
    session, else ``None``. Uses ``T3CODE_THREAD_ID`` and ``git rev-parse --show-toplevel`` of ``cwd`` (the process's own by default).

    Fails closed: if the lookup itself raises, the answer is the bare headless marker."""
    env = os.environ if env is None else env
    try:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=cwd, capture_output=True, text=True, timeout=10).stdout.strip()
        found = resolve(env, {}, root, project_dir=top or "")
    except Exception:  # noqa: BLE001
        return {"FENTON_HEADLESS": "1"}
    return dict(found.env) if found else None


def registered(env: Optional[Mapping[str, str]] = None, cwd: Optional[str] = None, root: Optional[Path] = None) -> bool:
    """Is this process inside a registered triage session? See :func:`session_env`."""
    return session_env(env, cwd, root) is not None


# MARK: - SessionStart

def env_file_lines(found: Resolution) -> List[str]:
    """Shell lines for ``$CLAUDE_ENV_FILE``: the record's env exported, the scrubbed variables unset."""
    lines = [f"export {name}={shlex.quote(value)}" for name, value in sorted(found.env.items()) if _ENV_NAME.match(name)]
    lines.append("unset " + " ".join(SCRUB_ENV))
    return lines


def session_start(payload: Mapping[str, Any], env: Optional[Mapping[str, str]] = None, root: Optional[Path] = None) -> int:
    """The ``--session-start`` hook: append :func:`env_file_lines` to ``$CLAUDE_ENV_FILE`` for a registered session. Always exit 0."""
    env = os.environ if env is None else env
    try:
        found = resolve(env, payload, root)
        target = env.get("CLAUDE_ENV_FILE")
        if found and target:
            with open(target, "a", encoding="utf-8") as handle:
                handle.write("\n".join(env_file_lines(found)) + "\n")
    except Exception:  # noqa: BLE001 - the tools and hooks resolve on their own; a failed export must not stop the session
        pass
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    """``triage_session.py --session-start``: read the SessionStart payload from stdin."""
    args = sys.argv[1:] if argv is None else argv
    if "--session-start" not in args:
        print("usage: triage_session.py --session-start", file=sys.stderr)
        return 2
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        payload = {}
    return session_start(payload if isinstance(payload, dict) else {})


if __name__ == "__main__":
    sys.exit(main())
