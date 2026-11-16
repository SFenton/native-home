#!/usr/bin/env python3
"""studio_publish: the one path for an agent to change the owner's Studio draft and publish it (owner, 2026-11-16: agents may publish).

    tools/studio_publish.py status   [--base URL] [--json]
    tools/studio_publish.py check    CHANGE_DIR [--base URL] [--json]
    tools/studio_publish.py apply    CHANGE_DIR --reason TEXT [--publish] [--rebase-identical]
    tools/studio_publish.py publish  CHANGE_DIR --reason TEXT
    tools/studio_publish.py rollback CHANGE_DIR --reason TEXT [--live-only | --draft-only]

A sibling of ``tools/ha_change.py`` with the same guardrails (log, redact, ``--reason``, security flag, rollback, fail closed). A Studio
publish is a live Home Assistant change by effect: phones follow it at once. The tool speaks only to the Studio server's own API
(``/native/api/draft``, ``validate``, ``ha/open-check``, ``ha/publication``, ``ha/publish``, ``ha/rollback``) on loopback; the Home
Assistant credential stays in the Studio server and never reaches this tool. It never opens a file under the Studio's data directory.

``CHANGE_DIR`` is ``build/studio-publish/<id>/`` (git-ignored) and holds ``change.json`` (``id``, ``task``, ``studio``
{``base``, ``publisherId``, ``documentId``}, ``base`` {``draftRevision``, ``document``, ``liveRevision``, ``liveEnvelopeSha256``},
``document`` (the full candidate), ``scope`` (JSON pointers the change may differ in), ``summary``) and ``evidence.json``
(``candidateSha256``, ``validation``, ``screenshots`` {``before``, ``after``}, ``checks``). After ``apply`` it also holds ``record.json``
and ``prior.json`` (the draft document before the change; mode 600).

Order: ``check`` (read only) -> ``apply`` (record, then ``PUT draft`` with ``expectedRevision``) -> ``publish`` (re-read, ``POST
ha/publish`` with ``expectedRevision``, confirm). State machine ``built -> checked -> applied -> published -> rolled_back``; each step is
idempotent and resumable from ``record.json``.

Refusals: the draft must equal what the app serves (``open-check`` first, then ``draftIsLive``) so the owner's unpublished edits are
never shipped; the draft must be at the revision and document the change was built against; the diff must lie inside ``scope``;
the evidence must be bound to the SHA-256 of the candidate document. A 409 stops with ``stale_base`` (rebuild, never retried).

Auth: the request goes out without credentials; on a 401 the Studio token is read from the process environment variable
``STUDIO_AUTH_TOKEN`` only (no file is read) and sent as a Bearer header. It is never printed, logged or put on a command line.
The base URL is ``http://127.0.0.1:4801`` unless ``--base`` (or the bundle) says another loopback port.

Every attempt is one JSON line in ``~/hass-agents/studio-publish.jsonl`` (time, command, reason, change id, revisions, envelope hash,
security flag, result; never a document or a secret). Stdlib only. Exit code: 0 done, 1 refused or failed, 3 stale base or owner
edits (rebuild; not an error to retry).
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import redact as _shared_redact  # noqa: E402  (tools/redact.py: the one scrubber)

ROOT = Path(__file__).resolve().parents[1]

# MARK: - Constants

DEFAULT_BASE = "http://127.0.0.1:4801"
DEFAULT_LOG = "~/hass-agents/studio-publish.jsonl"
TOKEN_ENV = "STUDIO_AUTH_TOKEN"
#: Studios that are never the target unless the bundle itself names the port (the identity check is the real guard).
PINNED_PORTS = (4800, 4819)
LOOPBACK_HOSTS = ("127.0.0.1", "localhost")
REQUEST_TIMEOUT = 20
#: A change bundle or evidence file larger than this is refused before anything is sent.
MAX_BYTES = 8 * 1024 * 1024
#: ``open-check`` actions the tool accepts: ``start`` (the draft holds no edit the app lacks) and ``keep``; ``ask`` means unpublished edits.
OPEN_OK = ("start", "keep")
#: A change that mentions these is flagged ``security: true`` in the log, as ``ha_change.py apply`` does.
SECURITY_WORDS = ("lock.", "alarm_control_panel.", "garage", "siren.")
EXIT_STALE = 3
#: Reason codes that exit 3 (rebuild; the bundle no longer matches the Studio).
STALE_CODES = ("stale_base", "owner_edits")
MISSING = object()


class Refusal(Exception):
    """A refusal or failure with a reason ``code`` (the log and the output carry it), and an exit code."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message

    @property
    def exit_code(self) -> int:
        """3 for a stale base or owner edits, otherwise 1."""
        return EXIT_STALE if self.code in STALE_CODES else 1


# MARK: - JSON helpers

def _no_duplicates(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    """``object_pairs_hook`` that refuses a duplicate key (the last one would silently win)."""
    out: Dict[str, Any] = {}
    for key, value in pairs:
        if key in out:
            raise ValueError("duplicate key")
        out[key] = value
    return out


def _reject_constant(name: str) -> Any:
    raise ValueError("non-finite number")


def parse_json(text: str) -> Any:
    """Parse JSON text, refusing duplicate keys and NaN or Infinity."""
    return json.loads(text, object_pairs_hook=_no_duplicates, parse_constant=_reject_constant)


def jeq(a: Any, b: Any) -> bool:
    """Equality of two parsed JSON values; a boolean is never equal to a number."""
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(jeq(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(jeq(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) or isinstance(b, dict) or isinstance(a, list) or isinstance(b, list):
        return False
    return type(a) is type(b) and a == b if isinstance(a, str) or isinstance(b, str) else a == b


def doc_sha256(document: Any) -> str:
    """SHA-256 of the canonical text (sorted keys, no spaces) of a document: how evidence is bound to a candidate.

    Computed and compared only inside this tool; it is not the server's own hash."""
    text = json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _escape(segment: str) -> str:
    return segment.replace("~", "~0").replace("/", "~1")


def diff(old: Any, new: Any, pointer: str = "") -> List[Tuple[str, Any, Any]]:
    """The differences between two documents as ``(JSON pointer, old, new)``; a changed list length is one difference at the list."""
    if isinstance(old, dict) and isinstance(new, dict):
        out: List[Tuple[str, Any, Any]] = []
        for key in sorted(set(old) | set(new)):
            child = f"{pointer}/{_escape(key)}"
            out.extend(diff(old.get(key, MISSING), new.get(key, MISSING), child) if key in old and key in new
                       else [(child, old.get(key, MISSING), new.get(key, MISSING))])
        return out
    if isinstance(old, list) and isinstance(new, list) and len(old) == len(new):
        out = []
        for index, (a, b) in enumerate(zip(old, new)):
            out.extend(diff(a, b, f"{pointer}/{index}"))
        return out
    return [] if jeq(old, new) else [(pointer, old, new)]


def in_scope(pointer: str, scope: Sequence[str]) -> bool:
    """Is ``pointer`` equal to, or below, one of the ``scope`` pointers (whole segments, never a string prefix)?"""
    for allowed in scope:
        if allowed and (pointer == allowed or pointer.startswith(allowed.rstrip("/") + "/")):
            return True
    return False


def is_security(changes: Sequence[Tuple[str, Any, Any]]) -> bool:
    """Does a changed pointer or value mention a lock, alarm, garage or siren?"""
    for pointer, old, new in changes:
        text = " ".join([pointer] + [json.dumps(v, ensure_ascii=False) for v in (old, new) if v is not MISSING]).lower()
        if any(word in text for word in SECURITY_WORDS):
            return True
    return False


# MARK: - Base URL

def check_base(base: str, bundle_base: Optional[str]) -> str:
    """The base URL when it is ``http://127.0.0.1:PORT`` or ``http://localhost:PORT``, otherwise a ``Refusal``.

    Ports 4800 and 4819 are refused unless the bundle names that same base."""
    try:
        parts = urllib.parse.urlsplit(base)
        port = parts.port
    except ValueError:
        raise Refusal("bad_base", "the base URL is not valid") from None
    if parts.scheme != "http" or parts.hostname not in LOOPBACK_HOSTS or port is None or parts.username or parts.password:
        raise Refusal("bad_base", "the base URL must be http://127.0.0.1:PORT or http://localhost:PORT")
    if parts.path not in ("", "/") or parts.query or parts.fragment:
        raise Refusal("bad_base", "the base URL carries a path, query or fragment")
    if port in PINNED_PORTS and (bundle_base is None or bundle_base.rstrip("/") != base.rstrip("/")):
        raise Refusal("bad_base", f"port {port} is refused unless the change bundle names it")
    return f"http://{parts.hostname}:{port}"


# MARK: - HTTP

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """A redirect is an error: a loopback Studio never redirects, and a follow could leave loopback."""

    def redirect_request(self, *args: Any, **kwargs: Any) -> None:  # noqa: D401
        return None


class Studio:
    """A client for the Studio's own API on loopback. Auth is tried without credentials, then with ``STUDIO_AUTH_TOKEN`` on a 401."""

    def __init__(self, base: str, env: Dict[str, str], sleep: Callable[[float], None] = time.sleep):
        self.base = base
        self.token = env.get(TOKEN_ENV, "")
        self.use_auth = False
        self.sleep = sleep
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect)

    def request(self, method: str, path: str, body: Any = None) -> Tuple[int, Any]:
        """``(status, parsed JSON or None)``. One retry with back-off on 429 and one on a 401 with the token; never on 409 or 422."""
        retried_429 = False
        while True:
            status, data = self._once(method, path, body)
            if status == 401 and self.token and not self.use_auth:
                self.use_auth = True
                continue
            if status == 401:
                raise Refusal("auth_failed", "the Studio answered 401 and no valid " + TOKEN_ENV + " is set")
            if status == 429 and not retried_429:
                retried_429 = True
                self.sleep(2.0)
                continue
            return status, data

    def _once(self, method: str, path: str, body: Any) -> Tuple[int, Any]:
        payload = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers = {"Accept": "application/json"}
        if payload is not None:
            headers["Content-Type"] = "application/json"
        if self.use_auth:
            headers["Authorization"] = "Bearer " + self.token
        req = urllib.request.Request(self.base + path, data=payload, method=method, headers=headers)
        try:
            with self.opener.open(req, timeout=REQUEST_TIMEOUT) as resp:
                status, raw = resp.status, resp.read()
        except urllib.error.HTTPError as err:
            status, raw = err.code, err.read()
        except (urllib.error.URLError, OSError, ValueError):
            raise Refusal("studio_unreachable", "the Studio did not answer on " + self.base) from None
        try:
            return status, parse_json(raw.decode("utf-8")) if raw else None
        except ValueError:
            return status, None


# MARK: - Files

def _read_json(path: Path, what: str) -> Dict[str, Any]:
    try:
        with open(path, "rb") as handle:
            raw = handle.read(MAX_BYTES + 1)
    except OSError:
        raise Refusal("bad_bundle", f"{what} is missing or unreadable") from None
    if len(raw) > MAX_BYTES:
        raise Refusal("bad_bundle", f"{what} is larger than {MAX_BYTES} bytes")
    try:
        data = parse_json(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as err:
        raise Refusal("bad_bundle", f"{what} is not valid JSON ({err})") from None
    if not isinstance(data, dict):
        raise Refusal("bad_bundle", f"{what} is not a JSON object")
    return data


def _write_private(path: Path, data: Any) -> None:
    """Write JSON at mode 600, atomically (temp file then rename)."""
    text = json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(str(tmp), str(path))


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


# MARK: - The publisher

class Publisher:
    """One run of the tool: the checkout ``root``, the environment, the log path and an HTTP client factory."""

    def __init__(self, root: Path = ROOT, env: Optional[Dict[str, str]] = None, log_path: Optional[str] = None,
                 sleep: Callable[[float], None] = time.sleep, out: Any = None):
        self.root = Path(root).resolve()
        self.env = dict(os.environ if env is None else env)
        self.log_path = Path(os.path.expanduser(str(log_path or DEFAULT_LOG)))
        self.sleep = sleep
        self.out = out or sys.stdout
        self.studio: Optional[Studio] = None

    # MARK: Output

    def scrub(self, text: str) -> str:
        """Redact credentials and the Studio token (if set) from text that leaves the tool."""
        token = self.env.get(TOKEN_ENV, "")
        if token:
            text = text.replace(token, "[redacted]")
        return _shared_redact.redact(text)

    def say(self, text: str) -> None:
        print(self.scrub(text), file=self.out)

    def log(self, command: str, reason: str, change: str, result: str, **fields: Any) -> None:
        """Append one line to the JSONL log. Only revisions, hashes, the reason code and the security flag; never a document or a secret."""
        line = {"time": _now(), "command": command, "reason": reason, "change": change, "result": result}
        line.update({k: v for k, v in fields.items() if v is not None})
        try:
            self.log_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.log_path, "a", encoding="utf-8") as handle:
                handle.write(self.scrub(json.dumps(line, sort_keys=True)) + "\n")
        except OSError:
            self.say("warning: the log could not be written")

    # MARK: Bundle

    def change_dir(self, given: str) -> Path:
        """The resolved ``CHANGE_DIR``, which must be a directory under ``<root>/build/studio-publish``."""
        base = (self.root / "build" / "studio-publish").resolve()
        path = Path(given)
        path = (path if path.is_absolute() else Path.cwd() / path).resolve()
        if path == base or base not in path.parents or not path.is_dir():
            raise Refusal("bad_bundle", "CHANGE_DIR must be an existing directory under build/studio-publish/")
        return path

    def load_change(self, directory: Path) -> Dict[str, Any]:
        """``change.json``, shape-checked."""
        change = _read_json(directory / "change.json", "change.json")
        for key, kind in (("id", str), ("studio", dict), ("base", dict), ("document", dict), ("scope", list)):
            if not isinstance(change.get(key), kind):
                raise Refusal("bad_bundle", f"change.json needs `{key}` as {kind.__name__}")
        studio, base = change["studio"], change["base"]
        if not isinstance(studio.get("publisherId"), str) or not isinstance(studio.get("documentId"), str):
            raise Refusal("bad_bundle", "change.json studio needs publisherId and documentId")
        if not isinstance(base.get("draftRevision"), int) or isinstance(base.get("draftRevision"), bool) or not isinstance(base.get("document"), dict):
            raise Refusal("bad_bundle", "change.json base needs an integer draftRevision and a document")
        if not isinstance(base.get("liveRevision"), int) or isinstance(base.get("liveRevision"), bool):
            raise Refusal("bad_bundle", "change.json base needs an integer liveRevision")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,80}", change["id"]):
            raise Refusal("bad_bundle", "change id must be letters, digits, dot, dash or underscore")
        if not all(isinstance(s, str) and len(s) > 1 and s.startswith("/") for s in change["scope"]):
            raise Refusal("bad_bundle", "scope must hold non-empty JSON pointers (an empty path would allow the whole document)")
        return change

    def scope_check(self, change: Dict[str, Any]) -> Tuple[List[Tuple[str, Any, Any]], bool]:
        """The differences of the candidate against the base, refused unless every one lies inside ``scope``. Returns them and the security flag."""
        changes = diff(change["base"]["document"], change["document"])
        if not changes:
            raise Refusal("no_change", "the candidate document equals the base: nothing to apply")
        if not change["scope"]:
            raise Refusal("scope_violation", "the change declares no scope")
        outside = [p for p, _, _ in changes if not in_scope(p, change["scope"])]
        if outside:
            shown = ", ".join(p[:100] for p in outside[:5])
            raise Refusal("scope_violation", f"{len(outside)} difference(s) outside the declared scope: {shown}")
        return changes, is_security(changes)

    def evidence_check(self, directory: Path, change: Dict[str, Any]) -> Dict[str, Any]:
        """``evidence.json`` must pass every required check and be bound to the hash of the candidate document."""
        evidence = _read_json(directory / "evidence.json", "evidence.json")
        digest = doc_sha256(change["document"])
        if evidence.get("candidateSha256") != digest:
            raise Refusal("evidence_unbound", "evidence.json is not bound to this candidate document (candidateSha256 differs)")
        validation = evidence.get("validation")
        if not isinstance(validation, dict) or validation.get("result") != "pass":
            raise Refusal("evidence_missing", "evidence.json needs validation.result = pass")
        shots = evidence.get("screenshots")
        for side in ("before", "after"):
            paths = shots.get(side) if isinstance(shots, dict) else None
            if not isinstance(paths, list) or not paths or not all(isinstance(p, str) for p in paths):
                raise Refusal("evidence_missing", f"evidence.json needs screenshots.{side} as a list of paths")
            for rel in paths:
                target = Path(rel) if os.path.isabs(rel) else self.root / rel
                if not target.is_file():
                    raise Refusal("evidence_missing", f"a {side} screenshot does not exist: {rel[:120]}")
        checks = evidence.get("checks", [])
        if not isinstance(checks, list) or any(not isinstance(c, dict) or c.get("result") != "pass" for c in checks):
            raise Refusal("evidence_failed", "a required check in evidence.json is not marked pass")
        return evidence

    # MARK: Studio reads

    def client(self, change: Optional[Dict[str, Any]], base: Optional[str]) -> Studio:
        bundle_base = change["studio"].get("base") if change else None
        chosen = base or bundle_base or DEFAULT_BASE
        if bundle_base is not None and not isinstance(bundle_base, str):
            raise Refusal("bad_bundle", "studio.base must be a string")
        self.studio = Studio(check_base(chosen, bundle_base), self.env, self.sleep)
        return self.studio

    def get(self, path: str, code: str) -> Dict[str, Any]:
        assert self.studio is not None
        status, data = self.studio.request("GET", path)
        if status != 200 or not isinstance(data, dict):
            raise Refusal(code, f"GET {path} answered {status}")
        return data

    def read_state(self) -> Tuple[Dict[str, Any], Dict[str, Any], Dict[str, Any]]:
        """``(open-check, publication, draft)``, in that order: ``open-check`` is read first."""
        open_check = self.get("/native/api/ha/open-check", "ha_unreachable")
        publication = self.get("/native/api/ha/publication", "ha_unreachable")
        draft = self.get("/native/api/draft", "studio_unreachable")
        return open_check, publication, draft

    @staticmethod
    def live_of(publication: Dict[str, Any]) -> Tuple[Any, Any]:
        current = publication.get("current")
        current = current if isinstance(current, dict) else {}
        return current.get("revision"), current.get("envelopeSha256")

    def require_serving(self, open_check: Dict[str, Any], publication: Dict[str, Any]) -> None:
        """The scope guard: refuse unless the draft equals what the app serves."""
        action = open_check.get("action")
        if action not in OPEN_OK:
            raise Refusal("owner_edits", "the owner has unpublished edits in the draft (open-check says " + str(action)[:20] + "); wait")
        if publication.get("draftIsLive") is not True:
            raise Refusal("owner_edits", "the draft does not equal what the app serves (draftIsLive is not true); wait")

    # MARK: Commands

    def status(self, base: Optional[str], as_json: bool) -> int:
        """Print revisions and flags only: no document, token or house value."""
        self.client(None, base)
        open_check, publication, draft = self.read_state()
        history = publication.get("history")
        live_revision, _ = self.live_of(publication)
        info = {
            "draftRevision": draft.get("revision"), "liveRevision": live_revision,
            "draftIsLive": publication.get("draftIsLive"), "openCheck": open_check.get("action"),
            "historyRevisions": [h.get("revision") for h in history if isinstance(h, dict)] if isinstance(history, list) else [],
            "lastChange": self.last_logged(), "openChanges": self.open_changes(),
        }
        self.say(json.dumps(info, sort_keys=True) if as_json else "\n".join(f"{k}: {v}" for k, v in info.items()))
        return 0

    def open_changes(self) -> List[Dict[str, Any]]:
        """Every ``build/studio-publish/*/record.json`` that is not final (change id and state only): a write that was never confirmed or rolled back."""
        found = []
        for path in sorted((self.root / "build" / "studio-publish").glob("*/record.json")):
            try:
                record = _read_json(path, "record.json")
            except Refusal:
                found.append({"change": path.parent.name, "state": "unreadable"})
                continue
            state = record.get("state")
            if state in ("recorded", "applied", "rollback_failed") or (state == "refused" and record.get("draftWritten")):
                found.append({"change": record.get("change", path.parent.name), "state": state})
        return found

    def last_logged(self) -> Optional[Dict[str, Any]]:
        """The newest log line (change id, command, result and time only)."""
        try:
            with open(self.log_path, "r", encoding="utf-8") as handle:
                lines = [ln for ln in handle.read().splitlines() if ln.strip()]
            line = json.loads(lines[-1])
        except (OSError, ValueError, IndexError):
            return None
        return {k: line.get(k) for k in ("time", "command", "change", "result")} if isinstance(line, dict) else None

    def check(self, given: str, base: Optional[str], as_json: bool, rebase_identical: bool = False, command: str = "check",
              reason: str = "") -> Tuple[Dict[str, Any], Dict[str, Any]]:
        """The read-only check. Returns the change and a context (draft, revisions, security flag); raises ``Refusal``."""
        directory = self.change_dir(given)
        change = self.load_change(directory)
        changes, security = self.scope_check(change)
        self.evidence_check(directory, change)
        self.client(change, base)
        open_check, publication, draft = self.read_state()
        self.require_serving(open_check, publication)
        studio = change["studio"]
        document = draft.get("document")
        if draft.get("publisherId") != studio["publisherId"] or not isinstance(document, dict) or document.get("id") != studio["documentId"]:
            raise Refusal("wrong_studio", "the Studio's publisherId or document id differs from the bundle's")
        live_revision, live_sha = self.live_of(publication)
        base_info = change["base"]
        if live_revision != base_info["liveRevision"] or (base_info.get("liveEnvelopeSha256") not in (None, live_sha)):
            raise Refusal("ha_moved", "the live publication differs from the one the change was built against; rebuild")
        revision = draft.get("revision")
        if not jeq(document, base_info["document"]):
            raise Refusal("stale_base", "the draft document differs from the base the change was built against; rebuild")
        rebased = False
        if revision != base_info["draftRevision"]:
            if not rebase_identical:
                raise Refusal("stale_base", f"the draft is at revision {revision}, the change was built at {base_info['draftRevision']}; rebuild")
            rebased = True
        assert self.studio is not None
        status, verdict = self.studio.request("POST", "/native/api/validate", {"document": change["document"]})
        if status != 200 or not isinstance(verdict, dict) or verdict.get("valid") is not True:
            raise Refusal("invalid", f"the Studio's validation refused the candidate (HTTP {status})")
        context = {"draft": draft, "revision": revision, "liveRevision": live_revision, "liveSha": live_sha, "security": security,
                   "rebased": rebased, "diffCount": len(changes), "directory": directory, "candidateSha256": doc_sha256(change["document"])}
        if command == "check":
            summary = {"change": change["id"], "state": "checked", "draftRevision": revision, "liveRevision": live_revision,
                       "differences": len(changes), "security": security}
            self.say(json.dumps(summary, sort_keys=True) if as_json else
                     f"checked {change['id']}: draft r{revision}, live r{live_revision}, {len(changes)} difference(s), security={security}")
        return change, context

    def record_path(self, directory: Path) -> Path:
        return directory / "record.json"

    def apply(self, given: str, base: Optional[str], reason: str, publish: bool, rebase_identical: bool, as_json: bool) -> int:
        """Record, ``PUT draft`` with the revision, verify. Resumes from ``record.json``; with ``publish`` goes on to ``publish``."""
        directory = self.change_dir(given)
        existing = self.load_record(directory)
        state = existing.get("state") if existing else None
        if state in ("applied", "published"):
            self.say(f"already {state}: {existing['change']}")  # type: ignore[index]
            return self.publish(given, base, reason, as_json) if publish and state == "applied" else 0
        if existing and (state in ("recorded", "rollback_failed") or (state == "refused" and existing.get("draftWritten"))):
            raise Refusal("unresolved", f"an earlier run left this change {state}: run rollback --draft-only first")
        change, context = self.check(given, base, as_json, rebase_identical, command="apply", reason=reason)
        draft = context["draft"]
        record = {"change": change["id"], "state": "recorded", "base": self.studio.base if self.studio else None, "priorRevision": context["revision"],
                  "liveBefore": {"revision": context["liveRevision"], "envelopeSha256": context["liveSha"]},
                  "candidateSha256": context["candidateSha256"], "security": context["security"], "reason": self.scrub(reason),
                  "rebased": context["rebased"], "recordedAt": _now()}
        _write_private(directory / "prior.json", {"document": draft["document"], "revision": context["revision"]})
        record["pendingDraftRevision"] = context["revision"] + 1
        _write_private(self.record_path(directory), record)
        assert self.studio is not None
        status, data = self.studio.request("PUT", "/native/api/draft", {"document": change["document"], "expectedRevision": context["revision"]})
        if status == 409:
            record["pendingDraftRevision"] = None
            self.finish_record(directory, record, "refused")
            raise Refusal("stale_base", "the draft moved before the write (409): the owner or another tool saved; rebuild, do not retry")
        if status == 422 or status >= 400 or status == 0:
            record["pendingDraftRevision"] = None
            self.finish_record(directory, record, "refused")
            raise Refusal("rejected", f"the Studio refused the draft write (HTTP {status}); the draft is unchanged")
        after = self.get("/native/api/draft", "studio_unreachable")
        stored = after.get("document")
        expected = _read_json(directory / "evidence.json", "evidence.json").get("storedSha256")
        if not (doc_sha256(stored) == expected if expected else jeq(stored, change["document"])):
            record["draftWritten"] = True
            record["afterDraftRevision"] = after.get("revision")
            self.finish_record(directory, record, "refused")
            raise Refusal("store_mismatch", "the draft the Studio stored differs from the candidate; run rollback --draft-only")
        record.update({"afterDraftRevision": after.get("revision"), "state": "applied"})
        self.finish_record(directory, record, "applied")
        self.log("apply", reason, change["id"], "applied", priorRevision=context["revision"], draftRevision=after.get("revision"),
                 liveRevision=context["liveRevision"], security=context["security"])
        self.say(f"applied {change['id']}: draft r{context['revision']} -> r{after.get('revision')}")
        return self.publish(given, base, reason, as_json) if publish else 0

    def load_record(self, directory: Path) -> Optional[Dict[str, Any]]:
        path = self.record_path(directory)
        return _read_json(path, "record.json") if path.exists() else None

    def finish_record(self, directory: Path, record: Dict[str, Any], state: str) -> None:
        record["state"] = state
        _write_private(self.record_path(directory), record)

    def publish(self, given: str, base: Optional[str], reason: str, as_json: bool) -> int:
        """Re-read, ``POST ha/publish`` with ``expectedRevision``, confirm the live revision, hash and ``draftIsLive``."""
        directory = self.change_dir(given)
        record = self.load_record(directory)
        if not record or record.get("state") not in ("applied", "published"):
            raise Refusal("not_applied", "nothing applied for this change; run apply first")
        if record["state"] == "published":
            self.say(f"already published: {record['change']}")
            return 0
        change = self.load_change(directory)
        changes, _ = self.scope_check(change)
        self.evidence_check(directory, change)
        self.client(change, base)
        open_check, publication, draft = self.read_state()
        if draft.get("revision") != record["afterDraftRevision"] or not jeq(draft.get("document"), change["document"]):
            raise Refusal("owner_edits", "the draft moved since the apply (the owner saved); not publishing, the draft is untouched")
        live_revision, live_sha = self.live_of(publication)
        if live_revision != record["liveBefore"]["revision"]:
            raise Refusal("ha_moved", "the live publication moved since the check; not publishing")
        assert self.studio is not None
        record["publishAttempted"] = True
        record["expectedPublishRevision"] = record["afterDraftRevision"]
        self.finish_record(directory, record, "applied")
        status, result = self.studio.request("POST", "/native/api/ha/publish", {"expectedRevision": record["afterDraftRevision"]})
        if status == 409:
            raise Refusal("owner_edits", "the draft moved before the publish (409); not publishing")
        if status != 200 or not isinstance(result, dict):
            raise Refusal("ha_unreachable" if status >= 500 or status == 0 else "rejected",
                          f"the publish answered {status}; the state stays applied, run publish again to resume")
        confirm = self.get("/native/api/ha/publication", "ha_unreachable")
        revision, sha = self.live_of(confirm)
        if revision != result.get("revision") or sha != result.get("envelopeSha256") or confirm.get("draftIsLive") is not True:
            raise Refusal("publish_unconfirmed", "the publication read back does not match the publish answer")
        record.update({"publishedRevision": revision, "publishedEnvelopeSha256": sha, "publishedAt": _now()})
        self.finish_record(directory, record, "published")
        self.log("publish", reason, change["id"], "published", draftRevision=record["afterDraftRevision"], liveRevision=revision,
                 envelopeSha256=sha, security=record.get("security"))
        info = {"change": change["id"], "state": "published", "liveRevision": revision, "envelopeSha256": sha, "security": record.get("security")}
        self.say(json.dumps(info, sort_keys=True) if as_json else f"published {change['id']}: live r{revision}; the owner's open Studio tab needs a reload")
        return 0

    def rollback(self, given: str, base: Optional[str], reason: str, live_only: bool, draft_only: bool, as_json: bool) -> int:
        """Put the live publication and the draft back. The live side first (``ha/rollback``, else republish the prior document), then the draft
        (only while it still sits at the revision this tool left). Works from any record that wrote or tried to write: ``recorded``, ``applied``,
        ``published``, ``refused`` (after a write that was not confirmed), ``rollback_failed`` and ``rolled_back`` (a no-op)."""
        directory = self.change_dir(given)
        record = self.load_record(directory)
        if not record or record.get("state") not in ("recorded", "applied", "published", "refused", "rolled_back", "rollback_failed"):
            raise Refusal("not_applied", "nothing to roll back for this change")
        change = self.load_change(directory)
        prior = _read_json(directory / "prior.json", "prior.json")
        self.client(change, base)
        was_published = bool(record.get("publishedRevision")) or record.get("state") == "published" or bool(record.get("publishAttempted"))
        want_live = was_published and not draft_only and not record.get("liveRolledBack")
        want_draft = not live_only and not record.get("draftRolledBack")
        outcome: Dict[str, Any] = {"change": change["id"]}
        assert self.studio is not None
        fallback = False
        try:
            if want_live:
                fallback = not self.rollback_live(record, outcome)
            if want_draft or fallback:
                self.rollback_draft(record, prior, outcome, publish_after=fallback)
        except Refusal as err:
            self.finish_record(directory, record, "rollback_failed")
            self.log("rollback", reason, change["id"], "rollback_failed:" + err.code)
            raise
        sides_done = (record.get("liveRolledBack") or not was_published) and record.get("draftRolledBack")
        self.finish_record(directory, record, "rolled_back" if sides_done else record.get("state", "applied"))
        self.log("rollback", reason, change["id"], "rolled_back" if sides_done else "partial", draftRevision=outcome.get("draftRevision"),
                 liveRevision=outcome.get("liveRevision"), envelopeSha256=outcome.get("envelopeSha256"), security=record.get("security"))
        self.say(json.dumps(outcome, sort_keys=True) if as_json else
                 "rolled back " + change["id"] + ": " + ", ".join(f"{k}={v}" for k, v in sorted(outcome.items()) if k != "change") + "; reload the open Studio tab")
        return 0

    def rollback_live(self, record: Dict[str, Any], outcome: Dict[str, Any]) -> bool:
        """``POST ha/rollback`` to the revision recorded before the publish. True when done (or when the publish never took effect); False when
        the entry aged out (404): republish instead.

        Refuses ``live_moved`` unless the live revision is still the one this tool published, so the owner's later publish is never undone. A publish that
        was attempted but never confirmed counts as ours only when the live revision is exactly one past the recorded one and the draft equals it."""
        assert self.studio is not None
        before = record["liveBefore"]
        publication = self.get("/native/api/ha/publication", "ha_unreachable")
        current, _ = self.live_of(publication)
        ours = record.get("publishedRevision")
        if ours is None and current == before["revision"]:
            record["liveRolledBack"] = True  # the publish never took effect
            outcome["live"] = "never_published"
            return True
        if ours is not None and current != ours:
            raise Refusal("live_moved", "the live publication is no longer the one this tool published (the owner published since); leaving it")
        if ours is None and not (current == before["revision"] + 1 and publication.get("draftIsLive") is True):
            raise Refusal("live_moved", "the live publication after an unconfirmed publish is not provably this tool's; leaving it")
        status, _ = self.studio.request("POST", "/native/api/ha/rollback", {"revision": before["revision"]})
        if status == 404:
            return False
        if status != 200:
            raise Refusal("rollback_failed", f"ha/rollback answered {status}")
        revision, sha = self.live_of(self.get("/native/api/ha/publication", "ha_unreachable"))
        if before.get("envelopeSha256") and sha != before["envelopeSha256"]:
            raise Refusal("rollback_failed", "the live publication after the rollback is not the one recorded before the publish")
        record["liveRolledBack"] = True
        outcome.update({"liveRevision": revision, "envelopeSha256": sha, "live": "rolled_back"})
        return True

    def rollback_draft(self, record: Dict[str, Any], prior: Dict[str, Any], outcome: Dict[str, Any], publish_after: bool) -> None:
        """``PUT`` the saved prior document while the draft still sits at the revision this tool left; otherwise report ``draft_moved``.

        With ``publish_after`` (the live entry aged out) the restored draft is then published to put the live side back. Before that publish the
        draft must equal the saved prior document and the live revision must still be this tool's, so the owner's edits are never published."""
        assert self.studio is not None
        draft = self.get("/native/api/draft", "studio_unreachable")
        revision = draft.get("revision")
        left = record.get("afterDraftRevision") or record.get("pendingDraftRevision")
        if not record.get("draftRolledBack"):
            if revision == record.get("priorRevision") and jeq(draft.get("document"), prior["document"]):
                record["draftRolledBack"] = True  # the write never landed
                outcome["draft"] = "unchanged"
            elif revision != left:
                outcome["draft"] = "draft_moved"
                if publish_after:
                    raise Refusal("rollback_failed", "the live entry aged out and the draft moved: nothing safe to republish; report to the owner")
                return
            else:
                if publish_after:
                    self.require_serving(self.get("/native/api/ha/open-check", "ha_unreachable"), self.get("/native/api/ha/publication", "ha_unreachable"))
                status, _ = self.studio.request("PUT", "/native/api/draft", {"document": prior["document"], "expectedRevision": revision})
                if status != 200:
                    raise Refusal("rollback_failed", f"restoring the draft answered {status}")
                draft = self.get("/native/api/draft", "studio_unreachable")
                revision = draft.get("revision")
                record["draftRolledBack"] = True
                outcome.update({"draft": "restored", "draftRevision": revision})
        if publish_after:
            publication = self.get("/native/api/ha/publication", "ha_unreachable")
            ours = record.get("publishedRevision")
            current, _ = self.live_of(publication)
            if not jeq(draft.get("document"), prior["document"]):
                raise Refusal("rollback_failed", "the draft no longer equals the saved prior document (the owner edited); not republishing")
            if ours is not None and current != ours:
                raise Refusal("live_moved", "the live publication is no longer the one this tool published; not republishing")
            status, result = self.studio.request("POST", "/native/api/ha/publish", {"expectedRevision": revision})
            if status != 200 or not isinstance(result, dict):
                raise Refusal("rollback_failed", f"republishing the prior document answered {status}")
            sha = result.get("envelopeSha256")
            expected = record["liveBefore"].get("envelopeSha256")
            if expected and sha != expected:
                raise Refusal("rollback_failed", "the republished prior document does not match the pre-publish hash")
            record["liveRolledBack"] = True
            outcome.update({"live": "republished", "liveRevision": result.get("revision"), "envelopeSha256": sha})


# MARK: - Command line

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="studio_publish.py", description="Change the owner's Studio draft and publish it.")
    parser.add_argument("--log", default=None, help="JSONL log path (default ~/hass-agents/studio-publish.jsonl)")
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--base", default=None, help="Studio base URL on loopback (default http://127.0.0.1:4801)")
        p.add_argument("--json", action="store_true", help="print JSON")

    common(sub.add_parser("status"))
    p = sub.add_parser("check")
    p.add_argument("change_dir")
    common(p)
    p = sub.add_parser("apply")
    p.add_argument("change_dir")
    p.add_argument("--reason", required=True)
    p.add_argument("--publish", action="store_true")
    p.add_argument("--rebase-identical", action="store_true", help="accept a moved revision when the draft document is equal")
    common(p)
    p = sub.add_parser("publish")
    p.add_argument("change_dir")
    p.add_argument("--reason", required=True)
    common(p)
    p = sub.add_parser("rollback")
    p.add_argument("change_dir")
    p.add_argument("--reason", required=True)
    group = p.add_mutually_exclusive_group()
    group.add_argument("--live-only", action="store_true")
    group.add_argument("--draft-only", action="store_true")
    common(p)
    return parser


def main(argv: Optional[Sequence[str]] = None, root: Optional[Path] = None, env: Optional[Dict[str, str]] = None,
         sleep: Callable[[float], None] = time.sleep) -> int:
    """Run one command. ``root`` and ``env`` are for tests."""
    args = build_parser().parse_args(argv)
    tool = Publisher(root or ROOT, env, args.log, sleep)
    reason = getattr(args, "reason", "")
    try:
        if args.command == "status":
            return tool.status(args.base, args.json)
        if args.command == "check":
            tool.check(args.change_dir, args.base, args.json)
            return 0
        if args.command == "apply":
            return tool.apply(args.change_dir, args.base, reason, args.publish, args.rebase_identical, args.json)
        if args.command == "publish":
            return tool.publish(args.change_dir, args.base, reason, args.json)
        return tool.rollback(args.change_dir, args.base, reason, args.live_only, args.draft_only, args.json)
    except Refusal as err:
        change = ""
        with contextlib.suppress(Exception):
            change = tool.load_change(tool.change_dir(args.change_dir))["id"] if hasattr(args, "change_dir") else ""
        if args.command != "status":
            tool.log(args.command, reason, change, "refused:" + err.code)
        tool.say(f"REFUSED [{err.code}]: {err.message}" + (" (rebuild the change; do not retry)" if err.exit_code == EXIT_STALE else ""))
        return err.exit_code


if __name__ == "__main__":
    sys.exit(main())
