#!/usr/bin/env python3
"""ha_change: the one path for an agent to change the live Home Assistant (owner, 2026-11-03: full control, guardrails not approvals).

    tools/ha_change.py backup NAME
    tools/ha_change.py check
    tools/ha_change.py apply --files LOCAL:REMOTE [LOCAL:REMOTE ...] --reason TEXT
    tools/ha_change.py restart --reason TEXT
    tools/ha_change.py hacs-install OWNER/REPO --reason TEXT
    tools/ha_change.py addon-install --source build/ha/APP --slug SLUG --reason TEXT --owner-approved
    tools/ha_change.py revert SLUG [--reason TEXT]

Every command takes ``--host ALIAS`` before the command name (default ``hass``): ``--host hass-test`` targets the test instance
(tools/test_ha/), with the same backup, check, rollback and log, and the log line names the host.

Every change is: full backup first, change, ``ha core check``, then reload the affected domain (restart Core only when a reload
cannot cover it). A failed check restores the previous copies of the files and stops. Every attempt is one line in the JSONL log
``~/hass-agents/ha-changes.jsonl`` (time, command, reason, files, backup slug, result, security flag; never a secret or file body).

Reaches Home Assistant with ``ssh hass`` (the HAOS SSH add-on; see .agents/platforms/apple/ha-operations.md). Reloads and the HACS
call use the add-on's own ``$SUPERVISOR_TOKEN`` on the far side, so no credential is read, printed or sent from this machine.
Local sources must resolve (realpath) inside this checkout, with no dot-directory component; /config/www is never a target (HA
serves it unauthenticated). A failed multi-file apply rolls every target back; a rollback that itself fails is logged as
``rollback_failed`` and exits non-zero. Stdlib only. Exit code: 0 done, 1 refused or failed (the log says why).
"""
from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import redact as _shared_redact  # noqa: E402  (tools/redact.py: the one scrubber)

ROOT = Path(__file__).resolve().parents[1]

CONFIG_DIR = "/config"
#: Never written or restored by an agent (HAOS add-on rules: secrets, storage, cloud, deps, the database).
FORBIDDEN = ("secrets.yaml", ".storage", ".cloud", "deps", "home-assistant_v2.db", ".git")
#: Remote file (relative to /config) -> the service that reloads it. Anything unlisted under packages/ reloads all YAML.
RELOADS: Dict[str, Tuple[str, str]] = {
    "automations.yaml": ("automation", "reload"),
    "scripts.yaml": ("script", "reload"),
    "scenes.yaml": ("scene", "reload"),
    "groups.yaml": ("group", "reload"),
    "template.yaml": ("template", "reload"),
}
RELOAD_ALL = ("homeassistant", "reload_all")
#: The house statics file of the fenton_home integration reloads through its own admin service (no Core restart).
FULL_SHA = re.compile(r"[0-9a-f]{40}")
HOUSE_RELOAD = ("fenton_home", "reload_house_config")
HOUSE_FILES = ("fenton_home/house.yaml", "fenton_home/house.json")
#: The Repairs issue fenton_home raises when the house file it just loaded is invalid.
HOUSE_INVALID_ISSUE = ("fenton_home", "house_config_invalid")
#: A change that mentions one of these touches a security device: same path, flagged in the log for the owner digest.
SECURITY = re.compile(r"\b(lock|alarm_control_panel|garage|siren)\.|device_class:\s*garage|\bcover\.\w*garage", re.I)
#: HACS 2.x registers no ``hacs.*`` services and its update entities cannot refresh themselves, so HACS is driven through its own
#: websocket commands (custom_components/hacs/websocket/repositories.py ``hacs/repositories/list``; repository.py
#: ``hacs/repository/refresh`` and ``hacs/repository/download``), from the add-on with its own ``$SUPERVISOR_TOKEN``.
WS_TIMEOUT = 600
#: Stdlib websocket client that runs on the HA host (``python3 - '<json command>' <timeout>``): authenticates to Core with the
#: add-on's ``$SUPERVISOR_TOKEN`` (never printed), sends one command and prints ``{"success", "result", "error"}`` as JSON.
WS_CLIENT = r'''
import base64, json, os, socket, struct, sys

def exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise RuntimeError("connection closed")
        buf += chunk
    return buf

def send(sock, op, data):
    mask = os.urandom(4)
    n = len(data)
    head = bytes([0x80 | op]) + (bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack(">H", n) if n < 65536
                                 else bytes([0x80 | 127]) + struct.pack(">Q", n))
    sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

def recv_text(sock):
    data, first = b"", None
    while True:
        b1, b2 = exact(sock, 2)
        n = b2 & 0x7F
        if n == 126:
            n = struct.unpack(">H", exact(sock, 2))[0]
        elif n == 127:
            n = struct.unpack(">Q", exact(sock, 8))[0]
        payload = exact(sock, n)
        op = b1 & 0x0F
        if op == 9:
            send(sock, 10, payload)
            continue
        if op == 8:
            raise RuntimeError("server closed the websocket")
        if op in (1, 2):
            first = op
        if op in (0, 1, 2):
            data += payload
            if b1 & 0x80:
                return json.loads(data.decode())

def main():
    msg, timeout = json.loads(sys.argv[1]), float(sys.argv[2])
    sock = socket.create_connection(("supervisor", 80), timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall(("GET /core/websocket HTTP/1.1\r\nHost: supervisor\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % key).encode())
    head = b""
    while not head.endswith(b"\r\n\r\n"):
        head += exact(sock, 1)
    if b" 101 " not in head.split(b"\r\n")[0]:
        raise RuntimeError("websocket upgrade refused: " + head.split(b"\r\n")[0].decode())
    if recv_text(sock).get("type") != "auth_required":
        raise RuntimeError("unexpected greeting")
    send(sock, 1, json.dumps({"type": "auth", "access_token": os.environ["SUPERVISOR_TOKEN"]}).encode())
    if recv_text(sock).get("type") != "auth_ok":
        raise RuntimeError("Core refused the add-on token")
    msg["id"] = 1
    send(sock, 1, json.dumps(msg).encode())
    while True:
        reply = recv_text(sock)
        if reply.get("id") == 1 and reply.get("type") == "result":
            err = reply.get("error") or {}
            print(json.dumps({"success": bool(reply.get("success")), "result": reply.get("result"),
                              "error": (err.get("code", "") + ": " + err.get("message", "")) if err else ""}))
            return

try:
    main()
except Exception as exc:
    print(json.dumps({"success": False, "result": None, "error": "%s: %s" % (type(exc).__name__, exc)}))
'''
DEFAULT_LOG = "~/hass-agents/ha-changes.jsonl"

#: The ssh alias of the live house; ``--host`` swaps it (the test instance is ``hass-test``).
DEFAULT_HOST = "hass"
#: A host is an ssh alias: letters, digits, dot, dash, underscore, never a leading dash (it would read as an ssh option).
HOST_ALIAS = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
#: Where a HACS install keeps the tarball of /config/custom_components on the HA host (never under /config/www).
TAR_DIR = "/root/ha-changes"


class ChangeError(Exception):
    """A refused or failed change; the message is safe to print."""


class _Logged(ChangeError):
    """A failure whose log line was already written (a restored or failed rollback), so the caller does not log it again."""


Runner = Callable[..., "subprocess.CompletedProcess[str]"]


def default_run(args: List[str], input: Optional[str] = None, timeout: int = 900) -> "subprocess.CompletedProcess[str]":
    return subprocess.run(args, input=input, capture_output=True, text=True, timeout=timeout)


def redact(text: str) -> str:
    """Drop anything token-shaped from text before it is printed or logged (the local rules, then ``tools/redact.py``)."""
    text = re.sub(r"(?i)(bearer\s+)\S+", r"\1***", text)
    text = re.sub(r"\b[A-Za-z0-9_\-]{40,}\b", "***", text)
    return _shared_redact.redact(text)


#: File names that are secrets even without a leading dot (AGENTS.md: ``*.env`` is git-ignored).
SECRET_NAME = re.compile(r"(\.env|\.key|\.p8|\.p12|\.pem|\.mobileprovision|\.cer)$|^id_(rsa|ed25519|ecdsa)", re.I)


def git_ignored(root: Path, rel: Path) -> bool:
    """True when git reports ``rel`` (under ``root``) as ignored, and also when git cannot say: only exit code 1 ("not ignored")
    lets a file through; any other code (128 not a repository, a crash) or a timeout refuses the source (fail closed)."""
    try:
        proc = subprocess.run(["git", "-C", str(root), "check-ignore", "-q", "--", str(rel)], capture_output=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return True
    return proc.returncode != 1


def check_source(local: str, roots: Sequence[Path]) -> Path:
    """The resolved local file for ``local`` or ChangeError. Only files inside one of ``roots`` (this checkout) are uploaded,
    after symlinks are resolved, and no component below the root may be a dot-directory or dot-file (``.git``, ``.claude``,
    ``.config``, ``.ssh``): a secret outside the repo can never be pushed to /config."""
    lp = Path(os.path.expanduser(local)).resolve()
    if ".config/fenton-hass" in str(lp):
        raise ChangeError(f"refused {local}: credential folder")
    if not lp.is_file():
        raise ChangeError(f"{local}: no such file")
    for root in roots:
        try:
            rel = lp.relative_to(Path(root).resolve())
        except ValueError:
            continue
        if any(part.startswith(".") for part in rel.parts):
            raise ChangeError(f"refused {local}: no dot-directories or dot-files in the path")
        if SECRET_NAME.search(lp.name):
            raise ChangeError(f"refused {local}: looks like a secret (env, key, certificate or provisioning file)")
        scratch = (Path(root).resolve() / "build" / "ha")
        if scratch not in lp.parents and git_ignored(Path(root).resolve(), rel):
            raise ChangeError(f"refused {local}: git ignores it or git could not say, so it is not known to be part of the repository (build/ha/ is the scratch place)")
        return lp
    raise ChangeError(f"refused {local}: only files inside this checkout (build/ha/ for scratch files) may be uploaded")


def clean_remote(path: str) -> str:
    """The absolute /config path for ``path``, or ChangeError when it is outside /config or a forbidden location."""
    p = path if path.startswith("/") else f"{CONFIG_DIR}/{path}"
    parts = [x for x in p.split("/") if x]
    if ".." in parts or "." in parts:
        raise ChangeError(f"refused {path}: no '.' or '..' segments")
    if p != CONFIG_DIR and not p.startswith(CONFIG_DIR + "/"):
        raise ChangeError(f"refused {path}: only files under {CONFIG_DIR} may change")
    rel = p[len(CONFIG_DIR) + 1:]
    if not rel:
        raise ChangeError("refused: name a file, not /config")
    if rel.split("/")[0] == "www":
        raise ChangeError(f"refused {path}: /config/www is served without authentication")
    if any(part in FORBIDDEN for part in rel.split("/")) or rel.endswith(".bak"):
        raise ChangeError(f"refused {path}: secrets, storage, cloud, deps, the database and backups are never touched")
    return p


def reload_for(remotes: List[str]) -> Optional[List[Tuple[str, str]]]:
    """The reload service calls that cover ``remotes``, or None when only a Core restart will (configuration.yaml, custom_components, unknown)."""
    calls: List[Tuple[str, str]] = []
    for remote in remotes:
        rel = remote[len(CONFIG_DIR) + 1:]
        if rel in HOUSE_FILES:
            call = HOUSE_RELOAD
        elif rel in RELOADS:
            call = RELOADS[rel]
        elif rel.startswith("packages/") and rel.endswith((".yaml", ".yml")):
            call = RELOAD_ALL
        else:
            return None
        if call not in calls:
            calls.append(call)
    return calls


def signature_script(cc: str) -> str:
    """Shell that prints ``<directory> <crc> <size>`` per integration directory under ``cc`` (exit 3 when ``cc`` is missing).
    ``cksum`` runs per file so paths, sizes and empty files all count (a rename or an added empty file changes the signature);
    ``__pycache__`` is ignored; names with spaces or quotes are safe because nothing is word-split."""
    return (f"if [ -d {cc} ]; then cd {cc} && {{ for d in *; do [ -d \"$d\" ] && "
            "echo \"$d $(find \"$d\" -type f ! -path '*/__pycache__/*' -exec cksum {} + | sort | cksum)\"; done; exit 0; }; else exit 3; fi")


class HaChange:
    """The operations, over an ssh seam so tests never reach a real Home Assistant."""

    def __init__(self, run: Runner = default_run, log_path: Optional[Path] = None, host: str = DEFAULT_HOST,
                 now: Callable[[], float] = time.time, out: Callable[[str], None] = print,
                 roots: Optional[Sequence[Path]] = None):
        if not HOST_ALIAS.fullmatch(host):
            raise ChangeError(f"--host {host!r}: expected an ssh alias (letters, digits, . _ -)")
        self.run, self.host, self.now, self.out = run, host, now, out
        self.roots = list(roots) if roots is not None else [ROOT]
        self.log_path = Path(os.path.expanduser(str(log_path or DEFAULT_LOG)))

    # -- plumbing
    def ssh(self, remote: str, input: Optional[str] = None, timeout: int = 900) -> "subprocess.CompletedProcess[str]":
        return self.run(["ssh", "-o", "BatchMode=yes", self.host, remote], input=input, timeout=timeout)

    def must(self, remote: str, what: str, input: Optional[str] = None) -> str:
        proc = self.ssh(remote, input)
        if proc.returncode != 0:
            raise ChangeError(f"{what} failed: {redact((proc.stderr or proc.stdout or '').strip())[:300]}")
        return proc.stdout or ""

    def log(self, command: str, result: str, reason: str = "", files: Optional[List[str]] = None, backup: str = "",
            security: bool = False, detail: str = "") -> None:
        entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(self.now())), "command": command, "reason": redact(reason)[:300],
                 "files": files or [], "backup": backup, "result": result, "security": security, "detail": redact(detail)[:300],
                 "host": self.host}
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        with self.log_path.open("a") as fh:
            fh.write(json.dumps(entry, sort_keys=True) + "\n")

    # -- commands
    def backup(self, name: str) -> str:
        """A full backup named ``name``; returns its slug."""
        if not re.fullmatch(r"[\w .:\-]{1,80}", name):
            raise ChangeError("backup name: letters, digits, space and . : _ - only (80 max)")
        out = self.must(f"ha backups new --name {shlex.quote(name)} --raw-json", "backup")
        slug = ""
        try:
            slug = str((json.loads(out).get("data") or {}).get("slug") or "")
        except ValueError:
            m = re.search(r"slug\W+([0-9a-f]{8})", out)
            slug = m.group(1) if m else ""
        if not slug:
            raise ChangeError("backup finished but no slug was reported: stopping before any change")
        return slug

    def check(self) -> None:
        proc = self.ssh("ha core check")
        text = (proc.stdout or "") + (proc.stderr or "")
        if proc.returncode != 0 or re.search(r"(?i)\b(error|invalid)\b", text):
            raise ChangeError("ha core check failed: " + redact(text.strip())[:400])

    def call_service(self, domain: str, service: str, body: str = "{}") -> None:
        url = f"http://supervisor/core/api/services/{domain}/{service}"
        remote = ('curl -sf -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" -H "Content-Type: application/json" '
                  f"-d {shlex.quote(body)} {shlex.quote(url)}")
        out = self.must(remote.replace("curl -sf ", "curl -s -w '\\n%{http_code}' ", 1), f"{domain}.{service}")
        body_text, _, code = out.rpartition("\n")
        if re.fullmatch(r"[45]\d\d", code.strip()):
            raise ChangeError(f"{domain}.{service} failed (HTTP {code.strip()}): {redact(body_text.strip())[:300]}")

    def reload_house(self, previous: Dict[str, Optional[str]], remotes: List[str], reason: str, slug: str, security: bool) -> None:
        """Reload the fenton_home house config after an ``apply``. The config entry must be loaded first, the service call must
        succeed and Repairs must not list ``house_config_invalid``; any of those failing puts every target back, reloads once more
        (when the entry is loaded) and raises with the backup slug."""
        why = ""
        loaded = self.house_entry_loaded()
        if not loaded:
            why = "the fenton_home config entry is not loaded, so the house config cannot be reloaded"
        else:
            try:
                self.call_service(*HOUSE_RELOAD)
                if self.house_config_invalid():
                    why = "fenton_home raised the Repairs issue house_config_invalid for the new file"
            except ChangeError as exc:
                why = f"reloading the house config failed ({exc})"
        if not why:
            return
        problems = self.rollback(previous)
        again = ""
        if not problems and loaded:
            try:
                self.call_service(*HOUSE_RELOAD)
            except ChangeError as bad:
                again = f"; reloading the restored file failed ({bad})"
        if problems:
            self.log("apply", "rollback_failed", reason, remotes, slug, security, f"{why}; rollback errors: {'; '.join(problems)}")
            raise _Logged(f"{why}; ROLLBACK FAILED for {', '.join(problems)}: restore backup {slug} (ha_change.py revert {slug})")
        self.log("apply", "house_reload_restored", reason, remotes, slug, security, why + again)
        raise _Logged(f"{why}; the previous file is back and the house config was reloaded again{again}; backup {slug}")

    def house_entry_loaded(self) -> bool:
        """True when Home Assistant reports a fenton_home config entry in state ``loaded`` (websocket ``config_entries/get``)."""
        res = self.ws_command({"type": "config_entries/get", "domain": HOUSE_RELOAD[0]}, "read config entries") or []
        return any(isinstance(e, dict) and e.get("state") == "loaded" for e in res)

    def house_config_invalid(self) -> bool:
        """True when Home Assistant's Repairs lists fenton_home's ``house_config_invalid`` issue (read over the websocket)."""
        res = self.ws_command({"type": "repairs/list_issues"}, "read Repairs") or {}
        issues = res.get("issues", []) if isinstance(res, dict) else res
        return any((i.get("domain"), i.get("issue_id")) == HOUSE_INVALID_ISSUE for i in issues if isinstance(i, dict))

    def ws_command(self, msg: Dict[str, Any], what: str) -> Any:
        """Send one HACS websocket command from the add-on and return its result; Home Assistant's error text is surfaced."""
        out = self.must(f"python3 - {shlex.quote(json.dumps(msg))} {WS_TIMEOUT}", what, WS_CLIENT)
        try:
            reply = json.loads(out.strip().splitlines()[-1])
        except (ValueError, IndexError) as exc:
            raise ChangeError(f"{what}: no usable reply from the websocket client") from exc
        if not reply.get("success"):
            raise ChangeError(f"{what} failed: {redact(str(reply.get('error') or 'unknown error'))[:300]}")
        return reply.get("result")

    def hacs_entry(self, repo: str) -> Dict[str, Any]:
        """HACS's own record of ``repo`` (matched on ``full_name``, case-insensitive, among HACS repositories only, then by GitHub repo id for a renamed repository), or ChangeError
        telling the caller to add it in HACS as a custom repository first. Several matches are refused."""
        listing = self.ws_command({"type": "hacs/repositories/list"}, "list HACS repositories") or []
        found = [r for r in listing if str(r.get("full_name", "")).lower() == repo.lower()]
        if not found:  # a repository renamed on GitHub keeps its id: HACS's record may still carry the old full_name
            gid = self.github_id(repo)
            found = [r for r in listing if gid and str(r.get("id", "")) == gid]
        if not found:
            raise ChangeError(f"HACS does not know {repo}: add it as a custom repository in HACS (Integration type) first; "
                              "this command never downloads a repository HACS has not registered")
        if len(found) > 1:
            raise ChangeError(f"HACS lists {repo} {len(found)} times; refusing to guess")
        return found[0]

    def github_id(self, repo: str) -> str:
        """GitHub's numeric repository id for ``repo`` (follows a rename; HACS uses it as its own repository id), or "" if unreadable."""
        proc = self.run(["gh", "api", f"repos/{repo}", "-q", ".id"])
        out = (proc.stdout or "").strip() if proc.returncode == 0 else ""
        return out if out.isdigit() else ""

    def github_default_branch(self, repo: str) -> str:
        """The default branch of ``repo`` on GitHub (what HACS's own UI sends to install a commit-tracked repository)."""
        proc = self.run(["gh", "api", f"repos/{repo}", "-q", ".default_branch"])
        out = (proc.stdout or "").strip() if proc.returncode == 0 else ""
        if not re.fullmatch(r"[\w.\-/]+", out):
            raise ChangeError(f"could not read the default branch of {repo}: {redact((proc.stderr or proc.stdout or '').strip())[:200]}")
        return out

    def github_target(self, repo: str) -> str:
        """The version HACS must install for ``repo``: the latest release tag, or the full 40-character head commit when it has no
        release (read from GitHub with ``gh``, the truth HACS's cached value is compared with). Only a tag or a full sha is a
        version HACS 2.0.5 downloads cleanly (``utils/url.py`` ``GIT_SHA`` builds ``archive/<sha>.zip``); a short sha 404s."""
        rel = self.run(["gh", "api", f"repos/{repo}/releases/latest", "--jq", ".tag_name"])
        tag = (rel.stdout or "").strip() if rel.returncode == 0 else ""
        if tag:
            return tag
        head = self.run(["gh", "api", f"repos/{repo}/commits/HEAD", "--jq", ".sha"])
        sha = (head.stdout or "").strip()
        if head.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40}", sha):
            raise ChangeError(f"could not read the GitHub head of {repo}: {redact((head.stderr or head.stdout or '').strip())[:200]}")
        return sha

    @staticmethod
    def same_version(a: Any, b: Any) -> bool:
        """True when two version strings are equal, ignoring a leading ``v`` and case. Commit shas also match by prefix, but only
        when one side is a full 40-character sha (HACS lists commits short, GitHub gives them full); tags compare exactly."""
        x, y = str(a).lower().lstrip("v"), str(b).lower().lstrip("v")
        if x == y:
            return True
        full, short = (x, y) if FULL_SHA.fullmatch(x) else (y, x)
        return bool(FULL_SHA.fullmatch(full) and re.fullmatch(r"[0-9a-f]{7,40}", short) and full.startswith(short))

    def restart_core(self) -> None:
        self.must("ha core restart", "core restart")

    def snapshot(self, remote: str) -> Optional[str]:
        """The current body of ``remote``, or None when it does not exist. Any other failure aborts (never read as absent)."""
        q = shlex.quote(remote)
        proc = self.ssh(f"if [ -e {q} ]; then cat {q}; else exit 3; fi")
        if proc.returncode == 3:
            return None
        if proc.returncode != 0:
            raise ChangeError(f"could not read {remote} before writing: {redact((proc.stderr or proc.stdout or '').strip())[:200]}")
        return proc.stdout or ""

    def apply(self, pairs: List[str], reason: str) -> str:
        if not reason.strip():
            raise ChangeError("--reason is required")
        plan: List[Tuple[Path, str]] = []
        for pair in pairs:
            local, sep, remote = pair.partition(":")
            if not sep or not local or not remote:
                raise ChangeError(f"{pair}: expected LOCAL:REMOTE")
            plan.append((check_source(local, self.roots), clean_remote(remote)))
        remotes = [r for _, r in plan]
        bodies = {r: lp.read_text() for lp, r in plan}
        security = any(SECURITY.search(b) for b in bodies.values())
        slug = ""
        previous: Dict[str, Optional[str]] = {}
        logged = False
        try:
            slug = self.backup(f"agent-{time.strftime('%Y%m%d-%H%M%S', time.gmtime(self.now()))}")
            for r in remotes:  # every target is read (and told apart from absent) before the first write
                previous[r] = self.snapshot(r)
            try:
                for r in remotes:
                    self.must(f"mkdir -p {shlex.quote(os.path.dirname(r))} && cat > {shlex.quote(r)}", f"write {r}", bodies[r])
                self.check()
            except ChangeError as exc:
                problems = self.rollback(previous)
                logged = True
                if problems:
                    self.log("apply", "rollback_failed", reason, remotes, slug, security,
                             f"{exc}; rollback errors: {'; '.join(problems)}")
                    raise ChangeError(f"{exc}; ROLLBACK FAILED for {', '.join(problems)}: restore backup {slug} "
                                      f"(ha_change.py revert {slug})") from exc
                self.log("apply", "check_failed_restored" if "ha core check" in str(exc) else "write_failed_restored",
                         reason, remotes, slug, security, str(exc))
                raise ChangeError(f"{exc}; the previous files are back, Core was not reloaded") from exc
            calls = reload_for(remotes)
            if calls is None:
                self.restart_core()
                how = "restart"
            else:
                for domain, service in calls:
                    if (domain, service) == HOUSE_RELOAD:
                        self.reload_house(previous, remotes, reason, slug, security)
                    else:
                        self.call_service(domain, service)
                how = "reload " + ",".join(f"{d}.{s}" for d, s in calls)
        except ChangeError as exc:
            if not logged and not isinstance(exc, _Logged):
                self.log("apply", "failed", reason, remotes, slug, security, str(exc))
            raise
        self.log("apply", "ok", reason, remotes, slug, security, how)
        if security:
            self.out("SECURITY DEVICE CHANGE: note it in the owner digest.")
        self.out(f"applied ({how}); backup {slug}")
        return slug

    def rollback(self, previous: Dict[str, Optional[str]]) -> List[str]:
        """Put every target back (an absent one is removed). Returns the targets that could not be restored."""
        failed: List[str] = []
        for remote, body in previous.items():
            try:
                if body is None:
                    self.must(f"rm -f {shlex.quote(remote)}", f"remove {remote}")
                else:
                    self.must(f"cat > {shlex.quote(remote)}", f"restore {remote}", body)
            except ChangeError:
                failed.append(remote)
        return failed

    def restart(self, reason: str) -> None:
        if not reason.strip():
            raise ChangeError("--reason is required")
        slug = ""
        try:
            slug = self.backup(f"agent-restart-{time.strftime('%Y%m%d-%H%M%S', time.gmtime(self.now()))}")
            self.check()
            self.restart_core()
        except ChangeError as exc:
            self.log("restart", "failed", reason, [], slug, False, str(exc))
            raise
        self.log("restart", "ok", reason, [], slug)
        self.out(f"restarting Core; backup {slug}")

    def custom_signatures(self) -> Dict[str, str]:
        """``{integration directory: checksum of its files}`` for /config/custom_components. A missing directory is empty; any
        other failure raises (an error must never read as an empty list: that would make every integration look new)."""
        cc = f"{CONFIG_DIR}/custom_components"
        script = signature_script(cc)
        proc = self.ssh(script)
        if proc.returncode == 3:
            return {}
        if proc.returncode != 0:
            raise ChangeError(f"could not list custom_components: {redact((proc.stderr or proc.stdout or '').strip())[:200]}")
        sigs: Dict[str, str] = {}
        for line in (proc.stdout or "").splitlines():
            name, _, rest = line.strip().partition(" ")
            if re.fullmatch(r"\w[\w.\-]*", name) and rest:
                sigs[name] = rest
        return sigs

    def undo_hacs(self, before: Dict[str, str], tarball: str) -> List[str]:
        """Undo a failed HACS install without a full restore: remove the directories it added, put back from ``tarball`` only the
        pre-existing ones whose files changed, then run the check again. Returns what was done; raises ChangeError if any step fails."""
        cc = f"{CONFIG_DIR}/custom_components"
        after = self.custom_signatures()
        done: List[str] = []
        for name in sorted(n for n in after if n not in before):
            self.must(f"rm -rf {cc}/{shlex.quote(name)}", f"remove {name}")
            done.append(f"removed {name}")
        for name in sorted(n for n in before if after.get(n) != before[n]):
            self.must(f"rm -rf {cc}/{shlex.quote(name)} && tar -C {CONFIG_DIR} -xf {shlex.quote(tarball)} "
                      f"custom_components/{shlex.quote(name)}", f"restore {name}")
            done.append(f"restored {name}")
        self.check()
        return done

    def drop_tarball(self, tarball: str) -> None:
        """Delete the pre-install tarball once it is no longer needed (best effort; never fails the command)."""
        with contextlib.suppress(Exception):
            self.ssh(f"rm -f {shlex.quote(tarball)}")

    def hacs_install(self, repo: str, reason: str) -> None:
        if not re.fullmatch(r"[\w.\-]+/[\w.\-]+", repo):
            raise ChangeError("expected OWNER/REPO")
        if not reason.strip():
            raise ChangeError("--reason is required")
        slug = ""
        logged = False
        stamp = time.strftime("%Y%m%d-%H%M%S", time.gmtime(self.now()))
        tarball = f"{TAR_DIR}/custom_components-{stamp}.tar"
        tar_made = False
        try:
            # read-only steps first: an unknown, stale or current repository changes nothing on the host
            entry = self.hacs_entry(repo)
            repo_id = str(entry.get("id") or "")
            if not repo_id:
                raise ChangeError(f"HACS gave no repository id for {repo}")
            target = self.github_target(repo)
            self.ws_command({"type": "hacs/repository/refresh", "repository": repo_id}, "HACS refresh")
            entry = self.hacs_entry(repo)
            available, installed = str(entry.get("available_version") or ""), str(entry.get("installed_version") or "")
            if not available:
                raise ChangeError(f"HACS reports no available version for {repo}; refusing to guess")
            if not self.same_version(available, target):
                raise ChangeError(f"HACS still offers {available} for {repo} but GitHub is at {target}: refusing to install a stale "
                                  "version (nothing changed)")
            if entry.get("installed") and installed and self.same_version(installed, target):
                self.log("hacs-install", "up_to_date", reason, [repo], "", False, installed)
                self.out(f"{repo} is already at {installed}; nothing to install")
                return
            # a release is pinned by its tag; a commit-tracked repo by its default branch, as HACS's own UI does (a sha stored as
            # installed_version never equals HACS's short available commit and leaves the update entity on); the commit is then
            # verified from HACS's own refreshed data below
            pin = self.github_default_branch(repo) if FULL_SHA.fullmatch(target) else target
            slug = self.backup(f"agent-hacs-{repo.replace('/', '-')}-{stamp}")
            before = self.custom_signatures()  # a failed listing stops here, before anything is downloaded
            self.must(f"mkdir -p {TAR_DIR} && if [ -d {CONFIG_DIR}/custom_components ]; then tar -C {CONFIG_DIR} -cf "
                      f"{shlex.quote(tarball)} --exclude=__pycache__ custom_components; fi", "tar custom_components")
            tar_made = True
            self.ws_command({"type": "hacs/repository/download", "repository": repo_id, "version": pin},
                            "HACS download")
            got = str(self.hacs_entry(repo).get("installed_version") or "")
            if not self.same_version(got, target):
                raise ChangeError(f"after the download HACS reports {got or 'nothing'} installed, expected {target}; nothing was undone "
                                  "or restarted")
            try:
                self.check()
            except ChangeError as exc:
                logged = True
                try:
                    done = self.undo_hacs(before, tarball)
                except ChangeError as bad:
                    self.log("hacs-install", "rollback_failed", reason, [repo], slug, False, f"{exc}; {bad}")
                    raise ChangeError(f"{exc}; ROLLBACK FAILED ({bad}): restore by hand with `ha_change.py revert {slug}` "
                                      f"(a full restore of the backup {slug} taken before this install); tarball {tarball} kept on the "
                                      "HA host") from exc
                self.drop_tarball(tarball)
                self.log("hacs-install", "check_failed_restored", reason, [repo], slug, False, f"{exc}; {', '.join(done) or 'nothing to undo'}")
                raise ChangeError(f"{exc}; the install was undone ({', '.join(done) or 'nothing had changed'}) and the check passes "
                                  f"again; this command did not restart Core; backup {slug} (the tarball {tarball} is deleted after a "
                                  "clean undo)") from exc
            self.restart_core()
            self.drop_tarball(tarball)
        except ChangeError as exc:
            if not logged:
                if slug:
                    exc = ChangeError(f"{exc}; backup {slug}" + (f", tarball {tarball} kept on the HA host" if tar_made else ""))
                self.log("hacs-install", "failed", reason, [repo], slug, False, str(exc))
                raise exc
            raise
        self.log("hacs-install", "ok", reason, [repo], slug)
        self.out(f"installed {repo} from HACS, restarting Core; backup {slug}")

    def revert(self, slug: str, reason: str = "revert") -> None:
        if not re.fullmatch(r"[0-9a-f]{8}", slug):
            raise ChangeError("slug: 8 hex characters, as printed by backup/apply")
        try:
            self.must(f"ha backups restore {shlex.quote(slug)}", "restore")
        except ChangeError as exc:
            self.log("revert", "failed", reason, [], slug, False, str(exc))
            raise
        self.log("revert", "ok", reason, [], slug)
        self.out(f"restored backup {slug}")

    def addon_install(self, source: str, slug: str, reason: str, owner_approved: bool = False) -> str:
        """First-install-only local Supervisor app; explicit owner opt-in, no Core restart or automatic full restore."""
        from ha_app_install import InstallError, install
        try:
            return install(self, source, slug, reason, owner_approved, SECRET_NAME)
        except InstallError as exc:
            raise _Logged(str(exc)) from None


def main(argv: Optional[List[str]] = None, change: Optional[HaChange] = None) -> int:
    ap = argparse.ArgumentParser(prog="ha_change.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("--host", default=None, help=f"ssh alias of the Home Assistant to change (default {DEFAULT_HOST})")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("backup").add_argument("name")
    sub.add_parser("check")
    a = sub.add_parser("apply")
    a.add_argument("--files", nargs="+", required=True)
    a.add_argument("--reason", required=True)
    r = sub.add_parser("restart")
    r.add_argument("--reason", required=True)
    h = sub.add_parser("hacs-install")
    h.add_argument("repo")
    h.add_argument("--reason", required=True)
    from ha_app_install import HELP
    app = sub.add_parser("addon-install", help="first install of an owner-approved, ingress-only local app",
                         description=HELP, formatter_class=argparse.RawDescriptionHelpFormatter)
    app.add_argument("--source", required=True, help="frozen build context below this checkout/build/ha")
    app.add_argument("--slug", required=True)
    app.add_argument("--reason", required=True)
    app.add_argument("--owner-approved", action="store_true", help="explicit owner authorization for this app installation")
    v = sub.add_parser("revert")
    v.add_argument("slug")
    v.add_argument("--reason", default="revert")
    args = ap.parse_args(argv)
    try:
        if change is None:
            change = HaChange(host=args.host or DEFAULT_HOST)
        elif args.host:
            if not HOST_ALIAS.fullmatch(args.host):
                raise ChangeError(f"--host {args.host!r}: expected an ssh alias (letters, digits, . _ -)")
            change.host = args.host
        if args.cmd == "backup":
            print(change.backup(args.name))
        elif args.cmd == "check":
            change.check()
            print("configuration valid")
        elif args.cmd == "apply":
            change.apply(args.files, args.reason)
        elif args.cmd == "restart":
            change.restart(args.reason)
        elif args.cmd == "hacs-install":
            change.hacs_install(args.repo, args.reason)
        elif args.cmd == "addon-install":
            change.addon_install(args.source, args.slug, args.reason, args.owner_approved)
        else:
            change.revert(args.slug, args.reason)
    except (ChangeError, subprocess.TimeoutExpired, OSError) as exc:
        print(f"ha_change: {redact(str(exc))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
