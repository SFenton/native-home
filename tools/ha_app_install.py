"""Bounded first installation of an ingress-only local Supervisor app, through HaChange.ssh.

No update, options, remote shell, full restore or Core restart operation is exposed here.
config.yaml must use strict JSON syntax (a YAML subset); arbitrary YAML is deliberately refused.
"""
from __future__ import annotations

import base64
import hashlib
import io
import json
import os
import re
import shlex
import stat
import subprocess
import tarfile
import uuid
from pathlib import Path
from typing import TYPE_CHECKING, Any, Pattern, Sequence

if TYPE_CHECKING:
    from ha_change import HaChange

SLUG = re.compile(r"[a-z][a-z0-9]*(?:_[a-z0-9]+)*")
VERSION = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,63}")
NAME = re.compile(r"[A-Za-z0-9_@+()\[\]-][A-Za-z0-9_.@+()\[\]-]{0,127}")
SECRET = re.compile(r"^(secrets?|credentials?|passwords?|tokens?)([._-]|$)", re.I)
MAX_FILES = 2048
MAX_FILE = 16 * 1024 * 1024
MAX_BYTES = 32 * 1024 * 1024
MAX_ARCHIVE = 40 * 1024 * 1024
OPEN_DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
HELP = """First installation only; --owner-approved is explicit authorization, not ordinary HA autonomy.

Supply a trusted frozen build context inside this checkout/build/ha (not build/ha itself).
The tool does not audit Dockerfile/application behavior. All paths must be regular files/directories:
no dot/secret-looking names, symlinks, hardlinks, special files, traversal or alternate config/build
manifests. Scratch files may be git-ignored. Limits: 2048 entries, 16 MiB/file, 32 MiB source,
40 MiB archive. Dockerfile must be nonempty; config.yaml must use strict JSON syntax (valid YAML),
without duplicate keys. No YAML extensions or dependency installation.

Required manifest: name, description, matching slug, bounded version, unique amd64/aarch64 arch,
ingress=true, ingress_port=4800, panel_admin=true, ports={"4800/tcp":null},
options={"live_actions":false}. Optional schema is exactly {"live_actions":"bool"}.
Other allowed fields: url, panel_icon, panel_title, ports_description, startup="application",
boot="manual"|"auto", boolean init and homeassistant_api. No image, environment, mounts,
privileges, host access, additional options, Supervisor API or Docker API access.

Preflight refuses unhealthy/unsupported Supervisor, installed local_<slug>, any existing source
/addons/<slug> (even dangling symlinks), or cached local store entry. Full backup and Core check
precede exclusive upload. Reload store, require matching local version_latest, install via
ha apps install, start, verify exact installed version/started state, then check Core.
Build CLI timeout: 900s; install SSH envelope: 1200s (other SSH steps: 900s).

Failures report backup/source paths and only projected app status, never raw Supervisor responses.
Only acknowledged new installs authorize exact-slug stop/uninstall without --remove-config.
Cleanup removes only marker-owned, hash-matching source, reloads the store and checks Core.
Uncertain install acknowledgment or ownership refuses automatic rollback (rollback_failed);
the build may still be running: do not blindly retry, uninstall or delete its source.
Clean undo logs install_failed_restored. Never restores the full backup or restarts Core.
No options/secrets, /config, protection toggles, unrelated apps/network or Docker socket mutation.
"""


class InstallError(Exception):
    """A fixed, safe diagnostic; never a remote response or source body."""


def strict_json(text: str) -> Any:
    """Read JSON without duplicate keys, non-finite numbers or YAML interpretation."""
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate key")
            result[key] = value
        return result

    def constant(_: str) -> None:
        raise ValueError("non-finite number")

    return json.loads(text, object_pairs_hook=pairs, parse_constant=constant)


def validate_manifest(body: bytes, slug: str) -> str:
    """Accept only the explicitly constrained, local-build ingress manifest."""
    try:
        config = strict_json(body.decode("utf-8"))
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise InstallError("config.yaml must be strict JSON (valid YAML); no duplicate keys or YAML extensions") from exc
    allowed = {
        "name", "description", "slug", "version", "arch", "url", "startup", "boot", "init",
        "ingress", "ingress_port", "panel_admin", "panel_icon", "panel_title", "ports",
        "ports_description", "options", "schema", "homeassistant_api",
    }
    if not isinstance(config, dict) or set(config) - allowed:
        raise InstallError("manifest has unsupported fields (no image, mounts, privileges, host access or environment)")
    if (config.get("slug") != slug or config.get("ingress") is not True or config.get("panel_admin") is not True
            or type(config.get("ingress_port")) is not int or config["ingress_port"] != 4800
            or config.get("ports") != {"4800/tcp": None} or config.get("options") != {"live_actions": False}
            or type(config["options"].get("live_actions")) is not bool):
        raise InstallError("manifest requires matching slug, admin-only ingress on 4800, no published ports and options.live_actions=false")
    if "schema" in config and config["schema"] != {"live_actions": "bool"}:
        raise InstallError("manifest schema may only expose live_actions as bool")
    if (not isinstance(config.get("version"), str) or not VERSION.fullmatch(config["version"])
            or not isinstance(config.get("arch"), list) or not config["arch"]
            or any(a not in ("amd64", "aarch64") for a in config["arch"])
            or len(config["arch"]) != len(set(config["arch"]))):
        raise InstallError("manifest requires a bounded version and unique amd64/aarch64 architectures")
    for key in ("name", "description"):
        if not isinstance(config.get(key), str) or not config[key].strip() or len(config[key]) > 200:
            raise InstallError("manifest requires a short name and description")
    if (config.get("startup", "application") != "application" or config.get("boot", "manual") not in ("manual", "auto")
            or ("init" in config and type(config["init"]) is not bool)
            or ("homeassistant_api" in config and type(config["homeassistant_api"]) is not bool)):
        raise InstallError("manifest has unsupported startup or API settings")
    return config["version"]


def freeze_source(source: str, roots: Sequence[Path], secret_name: Pattern[str], slug: str) -> dict[str, Any]:
    """Snapshot regular files through no-follow directory descriptors into a bounded canonical archive."""
    raw = os.path.expanduser(source)
    if any(p in (".", "..") for p in raw.split("/")):
        raise InstallError("source traversal is refused")
    local = Path(os.path.abspath(raw))
    root, parts = None, ()
    for candidate in roots:
        for anchor in (Path(os.path.abspath(candidate)), Path(candidate).resolve()):
            if local.is_relative_to(anchor / "build" / "ha"):
                root, parts = Path(candidate).resolve(), local.relative_to(anchor).parts
                break
        if root is not None:
            break
    if root is None or len(parts) <= 2:
        raise InstallError("source must be a dedicated directory inside this checkout/build/ha")
    records: list[dict[str, Any]] = []
    bodies: dict[str, bytes] = {}
    total = 0

    def safe_name(name: str) -> None:
        if (not NAME.fullmatch(name) or name.startswith(".") or secret_name.search(name) or SECRET.search(name)
                or name in ("secrets.yaml", ".storage", ".cloud", "deps", "home-assistant_v2.db", ".git")):
            raise InstallError("source contains a dot, secret-looking or unsafe path")

    def walk(fd: int, prefix: str = "") -> None:
        nonlocal total
        for name in sorted(os.listdir(fd)):
            safe_name(name)
            path = prefix + name
            before = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if len(records) >= MAX_FILES:
                raise InstallError("source exceeds 2048 entries")
            if stat.S_ISDIR(before.st_mode):
                child = os.open(name, OPEN_DIR, dir_fd=fd)
                try:
                    records.append({"name": path, "dir": True})
                    walk(child, path + "/")
                finally:
                    os.close(child)
            elif stat.S_ISREG(before.st_mode) and before.st_nlink == 1:
                if before.st_size > MAX_FILE or total + before.st_size > MAX_BYTES:
                    raise InstallError("source exceeds 16 MiB/file or 32 MiB total")
                file_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                with os.fdopen(file_fd, "rb") as fh:
                    opened = os.fstat(fh.fileno())
                    if not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1:
                        raise InstallError("source changed while being frozen")
                    body = fh.read(MAX_FILE + 1)
                    after = os.fstat(fh.fileno())
                if ((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
                        != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
                        or len(body) != before.st_size):
                    raise InstallError("source changed while being frozen")
                total += len(body)
                records.append({"name": path, "dir": False, "size": len(body),
                                "mode": 0o755 if before.st_mode & stat.S_IXUSR else 0o644,
                                "sha256": hashlib.sha256(body).hexdigest()})
                bodies[path] = body
            else:
                raise InstallError("source symlinks, hardlinks and special files are refused")

    fd = os.open(root, OPEN_DIR)
    try:
        for part in parts:
            safe_name(part)
            child = os.open(part, OPEN_DIR, dir_fd=fd)
            os.close(fd)
            fd = child
        walk(fd)
    finally:
        os.close(fd)
    if (not bodies.get("Dockerfile", b"").strip() or "config.yaml" not in bodies
            or any(n in bodies for n in ("config.yml", "config.json", "build.yaml", "build.yml", "build.json"))):
        raise InstallError("source needs config.yaml and a nonempty Dockerfile; alternate config/build manifests are refused")
    version = validate_manifest(bodies["config.yaml"], slug)
    archive = io.BytesIO()
    with tarfile.open(fileobj=archive, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for record in records:
            info = tarfile.TarInfo(record["name"])
            info.mode = 0o755 if record["dir"] else record["mode"]
            if record["dir"]:
                info.type = tarfile.DIRTYPE
                tar.addfile(info)
            else:
                info.size = record["size"]
                tar.addfile(info, io.BytesIO(bodies[record["name"]]))
    body = archive.getvalue()
    if len(body) > MAX_ARCHIVE:
        raise InstallError("source archive exceeds 40 MiB")
    return {"archive": base64.b64encode(body).decode("ascii"), "digest": hashlib.sha256(body).hexdigest(),
            "tree": hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest(), "version": version}


# Runs remotely, with CLI stdout/stderr kept on that side. Only explicit safe projections cross SSH.
REMOTE = r'''
import base64, hashlib, io, json, os, re, stat, subprocess, tarfile

ADDONS = "/addons"
MARKER = ".ha-change-owner"
DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW

class Refused(Exception):
    pass

def cli(args, timeout=120):
    try:
        p = subprocess.run(["ha"] + args + ["--raw-json"], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise Refused("cli_timeout")
    if p.returncode:
        raise Refused("cli_failed")
    try:
        reply = json.loads(p.stdout)
    except (ValueError, TypeError):
        raise Refused("cli_response")
    if not isinstance(reply, dict) or reply.get("result") != "ok":
        raise Refused("cli_response")
    data = reply.get("data")
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise Refused("cli_response")
    return data

def done(args, timeout=120):
    if cli(args, timeout) != {}:
        raise Refused("cli_response")

def listing(data):
    if not isinstance(data, dict) or ("apps" in data and "addons" in data and data["apps"] != data["addons"]):
        raise Refused("cli_response")
    rows = data.get("apps", data.get("addons"))
    if not isinstance(rows, list) or any(not isinstance(r, dict) or not isinstance(r.get("slug"), str) for r in rows):
        raise Refused("cli_response")
    return rows

def apps(slug):
    rows = listing(cli(["apps"]))
    found = [r for r in rows if r["slug"] == "local_" + slug]
    if len(found) > 1:
        raise Refused("cli_response")
    return found[0] if found else None

def store(slug):
    rows = listing(cli(["store"]))
    found = [r for r in rows if r["slug"] == "local_" + slug]
    if len(found) > 1:
        raise Refused("cli_response")
    return found[0] if found else None

def status(slug):
    row = apps(slug)
    if row is None:
        return {"installed": False, "state": "absent", "version": ""}
    version, state = row.get("version"), row.get("state")
    if not isinstance(version, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,63}", version):
        raise Refused("cli_response")
    if state not in ("started", "stopped", "starting", "error", "unknown"):
        raise Refused("cli_response")
    return {"installed": True, "state": state, "version": version}

def root_fd():
    return os.open(ADDONS, DIR)

def exists(parent, slug):
    try:
        os.stat(slug, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        return False
    return True

def anchored(parent, fd, slug):
    current = os.stat(slug, dir_fd=parent, follow_symlinks=False)
    opened = os.fstat(fd)
    if (current.st_dev, current.st_ino) != (opened.st_dev, opened.st_ino):
        raise Refused("ownership")

def child_fd(parent, path):
    fd = os.dup(parent)
    try:
        for part in path.split("/"):
            new = os.open(part, DIR, dir_fd=fd)
            os.close(fd)
            fd = new
        return fd
    except OSError:
        os.close(fd)
        raise

def read_file(fd, name, limit):
    f = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    with os.fdopen(f, "rb") as stream:
        st = os.fstat(stream.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1 or st.st_size > limit:
            raise Refused("source_changed")
        return stream.read(limit + 1)

def marker(p, fd):
    saved = json.loads(read_file(fd, MARKER, 1024 * 1024))
    entries = saved.get("entries")
    if (saved.get("token") != p["token"] or saved.get("digest") != p["digest"]
            or hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest() != p["tree"]):
        raise Refused("ownership")
    return entries

def inspect(p, fd, partial=False):
    entries = marker(p, fd)
    expected = {r["name"]: r for r in entries}
    seen = set()
    def walk(d, prefix=""):
        for name in os.listdir(d):
            if not prefix and name == MARKER:
                continue
            path = prefix + name
            r = expected.get(path)
            if r is None:
                raise Refused("source_changed")
            st = os.stat(name, dir_fd=d, follow_symlinks=False)
            if r["dir"]:
                sub = os.open(name, DIR, dir_fd=d)
                try:
                    walk(sub, path + "/")
                finally:
                    os.close(sub)
            elif (not stat.S_ISREG(st.st_mode) or st.st_size != r["size"]
                  or stat.S_IMODE(st.st_mode) != r["mode"]
                  or hashlib.sha256(read_file(d, name, 16 * 1024 * 1024)).hexdigest() != r["sha256"]):
                raise Refused("source_changed")
            seen.add(path)
    walk(fd)
    if not partial and seen != set(expected):
        raise Refused("source_changed")
    return [r for r in entries if r["name"] in seen]

def write_file(fd, name, body, mode):
    f = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode, dir_fd=fd)
    with os.fdopen(f, "wb") as stream:
        stream.write(body)
        os.fchmod(stream.fileno(), mode)

def upload(p, parent):
    encoded = p["archive"]
    if len(encoded) > 56 * 1024 * 1024:
        raise Refused("archive")
    body = base64.b64decode(encoded, validate=True)
    if len(body) > 40 * 1024 * 1024 or hashlib.sha256(body).hexdigest() != p["digest"]:
        raise Refused("archive")
    entries, contents, names, total = [], {}, set(), 0
    with tarfile.open(fileobj=io.BytesIO(body), mode="r:") as tar:
        for m in tar:
            parts = m.name.split("/")
            if (not parts or any(not re.fullmatch(r"[A-Za-z0-9_@+()\[\]-][A-Za-z0-9_.@+()\[\]-]{0,127}", n)
                                 or n.startswith(".") for n in parts)
                    or m.name in names or len(names) >= 2048 or not (m.isdir() or m.isreg())
                    or m.mode not in (0o644, 0o755) or m.size > 16 * 1024 * 1024):
                raise Refused("archive")
            names.add(m.name)
            if m.isdir():
                entries.append({"name": m.name, "dir": True})
            else:
                total += m.size
                if total > 32 * 1024 * 1024:
                    raise Refused("archive")
                data = tar.extractfile(m).read()
                contents[m.name] = data
                entries.append({"name": m.name, "dir": False, "size": len(data), "mode": m.mode,
                                "sha256": hashlib.sha256(data).hexdigest()})
    if hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest() != p["tree"]:
        raise Refused("archive")
    if apps(p["slug"]) is not None:
        raise Refused("installed")
    os.mkdir(p["slug"], mode=0o755, dir_fd=parent)
    fd = os.open(p["slug"], DIR, dir_fd=parent)
    try:
        saved = {"token": p["token"], "digest": p["digest"], "entries": entries}
        write_file(fd, MARKER, json.dumps(saved).encode(), 0o600)
        for r in entries:
            directory, _, name = r["name"].rpartition("/")
            dest = child_fd(fd, directory) if directory else os.dup(fd)
            try:
                if r["dir"]:
                    os.mkdir(name, mode=0o755, dir_fd=dest)
                else:
                    write_file(dest, name, contents[r["name"]], r["mode"])
            finally:
                os.close(dest)
        inspect(p, fd)
    finally:
        os.close(fd)

def owned(p, operation):
    parent = root_fd()
    fd = None
    try:
        fd = os.open(p["slug"], DIR, dir_fd=parent)
        entries = inspect(p, fd, partial=operation == "cleanup")
        anchored(parent, fd, p["slug"])
        exact = "local_" + p["slug"]
        if operation == "cleanup":
            if apps(p["slug"]) is not None:
                raise Refused("installed")
            for r in reversed(entries):
                directory, _, name = r["name"].rpartition("/")
                dest = child_fd(fd, directory) if directory else os.dup(fd)
                try:
                    if r["dir"]:
                        os.rmdir(name, dir_fd=dest)
                    else:
                        if hashlib.sha256(read_file(dest, name, 16 * 1024 * 1024)).hexdigest() != r["sha256"]:
                            raise Refused("source_changed")
                        os.unlink(name, dir_fd=dest)
                finally:
                    os.close(dest)
            anchored(parent, fd, p["slug"])
            marker(p, fd)
            os.unlink(MARKER, dir_fd=fd)
            os.rmdir(p["slug"], dir_fd=parent)
        elif operation == "store":
            if apps(p["slug"]) is not None:
                raise Refused("installed")
            done(["store", "reload"])
            row = store(p["slug"])
            if (row is None or row.get("version_latest") != p["version"] or row.get("repository") != "local"
                    or row.get("installed") is not False or row.get("available") is not True):
                raise Refused("store_mismatch")
        elif operation == "install":
            if apps(p["slug"]) is not None:
                raise Refused("installed")
            row = store(p["slug"])
            if (row is None or row.get("version_latest") != p["version"] or row.get("repository") != "local"
                    or row.get("installed") is not False or row.get("available") is not True):
                raise Refused("store_mismatch")
            anchored(parent, fd, p["slug"])
            done(["apps", "install", exact], timeout=900)
        elif operation in ("start", "uninstall"):
            current = status(p["slug"])
            if not current["installed"] or current["version"] != p["version"]:
                raise Refused("ownership")
            anchored(parent, fd, p["slug"])
            if operation == "start":
                done(["apps", "start", exact])
            else:
                if current["state"] != "stopped":
                    done(["apps", "stop", exact])
                stopped = status(p["slug"])
                if stopped["state"] != "stopped" or stopped["version"] != p["version"]:
                    raise Refused("not_stopped")
                anchored(parent, fd, p["slug"])
                done(["apps", "uninstall", exact])
                if apps(p["slug"]) is not None:
                    raise Refused("installed")
        else:
            raise Refused("operation")
    finally:
        if fd is not None:
            os.close(fd)
        os.close(parent)

def execute(action, p):
    try:
        if not re.fullmatch(r"[a-z][a-z0-9]*(?:_[a-z0-9]+)*", p["slug"]) or len(p["slug"]) > 48:
            raise Refused("slug")
        data = {}
        if action == "preflight":
            health = cli(["supervisor", "info"])
            if health.get("healthy") is not True or health.get("supported") is not True:
                raise Refused("unhealthy")
            parent = root_fd()
            try:
                if exists(parent, p["slug"]):
                    raise Refused("source_exists")
            finally:
                os.close(parent)
            if apps(p["slug"]) is not None:
                raise Refused("installed")
            if store(p["slug"]) is not None:
                raise Refused("store_exists")
        elif action == "backup":
            result = cli(["backups", "new", "--name", "agent-app-" + p["slug"]], timeout=880)
            backup = result.get("slug")
            if not isinstance(backup, str) or not re.fullmatch(r"[0-9a-f]{8}", backup):
                raise Refused("backup_response")
            data = {"backup": backup}
        elif action == "check":
            done(["core", "check"])
        elif action == "upload":
            parent = root_fd()
            try:
                upload(p, parent)
            finally:
                os.close(parent)
        elif action in ("store", "install", "start", "uninstall", "cleanup"):
            owned(p, action)
        elif action == "store_reload_after_cleanup":
            parent = root_fd()
            try:
                if exists(parent, p["slug"]) or apps(p["slug"]) is not None:
                    raise Refused("ownership")
                done(["store", "reload"])
                if store(p["slug"]) is not None:
                    raise Refused("store_mismatch")
            finally:
                os.close(parent)
        elif action == "status":
            data = status(p["slug"])
        else:
            raise Refused("operation")
        return {"ok": True, "data": data}
    except Refused as exc:
        return {"ok": False, "code": str(exc)}
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError):
        return {"ok": False, "code": "filesystem_or_response"}

if __name__ == "__main__":
    import sys
    payload = json.loads(sys.stdin.read(58 * 1024 * 1024))
    print(json.dumps(execute(sys.argv[1], payload)))
'''


class Attempt:
    """Track only acknowledged ownership; uncertainty never authorizes an uninstall."""

    def __init__(self, change: HaChange, slug: str):
        self.change = change
        self.payload: dict[str, Any] = {"slug": slug, "token": uuid.uuid4().hex}
        self.backup = ""
        self.preflight_attempted = False
        self.upload_attempted = False
        self.source_removed = False
        self.install_attempted = False
        self.install_confirmed = False

    def call(self, action: str) -> dict[str, Any]:
        payload = self.payload if action == "upload" else {k: v for k, v in self.payload.items() if k != "archive"}
        try:
            proc = self.change.ssh("python3 -c " + shlex.quote(REMOTE) + " " + action, json.dumps(payload),
                                   timeout=1200 if action == "install" else 900)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise InstallError(f"{action}: SSH response unavailable (operation may still be running)") from exc
        if proc.returncode:
            raise InstallError(f"{action}: SSH operation failed (response not trusted)")
        try:
            reply = strict_json(proc.stdout)
        except (ValueError, TypeError, RecursionError) as exc:
            raise InstallError(f"{action}: invalid safe response") from exc
        if not isinstance(reply, dict) or reply.get("ok") is not True:
            code = reply.get("code") if isinstance(reply, dict) else None
            codes = {
                "cli_timeout", "cli_failed", "cli_response", "source_changed", "ownership", "archive", "installed",
                "source_exists", "store_exists", "store_mismatch", "not_stopped", "unhealthy", "backup_response",
                "filesystem_or_response",
            }
            raise InstallError(f"{action}: {code if isinstance(code, str) and code in codes else 'invalid safe response'}")
        data = reply.get("data")
        keys = {"backup"} if action == "backup" else {"installed", "state", "version"} if action == "status" else set()
        if not isinstance(data, dict) or set(data) != keys:
            raise InstallError(f"{action}: invalid safe response")
        return data

    def state(self) -> str:
        """A strictly projected status, including when a mutation's acknowledgment was lost."""
        try:
            data = self.call("status")
            installed, state, version = data.get("installed"), data.get("state"), data.get("version")
            if installed is False and state == "absent" and version == "":
                return "installed=false state=absent"
            if (installed is True and state in ("started", "stopped", "starting", "error", "unknown")
                    and isinstance(version, str) and VERSION.fullmatch(version)):
                return f"installed=true state={state} version={version}"
        except InstallError:
            return "installed=unknown state=unknown"
        return "installed=unknown state=unknown"

    def rollback(self) -> str:
        """Undo only a confirmed new install, then remove only matching, marker-owned source entries."""
        if self.install_attempted and not self.install_confirmed:
            raise InstallError("safe automatic rollback unproven: install acknowledgment unavailable; source retained")
        if self.install_confirmed:
            self.call("uninstall")
        if self.upload_attempted:
            self.call("cleanup")
            self.source_removed = True
            self.call("store_reload_after_cleanup")
            self.call("check")
        return "new app/source removed" if self.upload_attempted else "no app/source changes"


def install(change: HaChange, source: str, slug: str, reason: str, owner_approved: bool,
            secret_name: Pattern[str]) -> str:
    """Preflight, backup, check, exclusively upload, install and start; log one redacted outcome."""
    attempt = Attempt(change, slug)
    remote = "/addons/" + slug if SLUG.fullmatch(slug) and len(slug) <= 48 else ""
    result = "failed"
    try:
        if not owner_approved:
            raise InstallError("--owner-approved is required: app installation is outside ordinary HA autonomy")
        if not reason.strip():
            raise InstallError("--reason is required")
        if not remote:
            raise InstallError("slug: lowercase letters/digits separated by single underscores, leading letter, 48 max")
        try:
            attempt.payload.update(freeze_source(source, change.roots, secret_name, slug))
        except (OSError, ValueError, tarfile.TarError) as exc:
            raise InstallError("source could not be safely frozen (no symlinks, special files or unsafe archive paths)") from exc
        attempt.preflight_attempted = True
        attempt.call("preflight")
        data = attempt.call("backup")
        backup = data.get("backup")
        if not isinstance(backup, str) or not re.fullmatch(r"[0-9a-f]{8}", backup):
            raise InstallError("backup: no verified backup slug; stopping before changes")
        attempt.backup = backup
        attempt.call("check")
        attempt.upload_attempted = True
        attempt.call("upload")
        attempt.call("store")
        attempt.install_attempted = True
        attempt.call("install")
        attempt.install_confirmed = True
        attempt.call("start")
        state = attempt.state()
        if state != f"installed=true state=started version={attempt.payload['version']}":
            raise InstallError("final app verification failed")
        attempt.call("check")
    except InstallError as exc:
        recovery = "no app/source changes"
        if attempt.upload_attempted:
            try:
                recovery = attempt.rollback()
                result = "install_failed_restored"
            except InstallError as bad:
                recovery = (f"safe automatic rollback not completed ({bad}); "
                            + ("source removed" if attempt.source_removed else "source removal unconfirmed"))
                result = "rollback_failed"
        state = attempt.state() if attempt.preflight_attempted else "installed=not_queried state=not_queried"
        detail = f"{exc}; {recovery}; {state}"
        change.log("addon-install", result, reason, [remote] if remote else [], attempt.backup, detail=detail)
        raise InstallError(f"{detail}; backup {attempt.backup or 'not_created_or_unconfirmed'}; source {remote or 'not_created'}; "
                           "no full backup restore or Core restart performed") from None
    change.log("addon-install", "ok", reason, [remote], attempt.backup, detail=state)
    change.out(f"installed local_{slug} {attempt.payload['version']} and started; backup {attempt.backup}; source {remote}; Core not restarted")
    return attempt.backup
