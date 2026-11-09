#!/usr/bin/env python3
"""Mint a GitHub App installation token for one agent role. In memory only; the CLI prints status, never a token.

Each role (see ``ROLES``) can post PR comments as its own GitHub App. Setup lives outside the repo, in
``~/.config/fenton-hass/github-apps/`` (override the folder with ``FENTON_HASS_APPS_DIR`` for tests):

- ``<role>.pem``: the App's private key (mode 600), downloaded once by the owner.
- ``apps.json``: non-secret ids, ``{"repo": "<owner>/<name>", "apps": {"<role>": {"app_id": 1,
  "slug": "s-h-coder", "client_id": "Iv1...", "installation_id": 2}}}``. ``tools/gh_apps_setup.py serve`` writes the key and
  this file (manifest flow); ``slug`` is what ``pr_note`` uses for the author check (``s-h-<role>`` when absent).
- A missing, unknown (404) or foreign installation id is replaced by ``GET /app/installations`` (the SFenton
  installation), cached in memory only.

Flow: RS256 JWT (``iat`` 60 s back, ``exp`` 9 minutes ahead, ``iss`` the app id) signed by ``openssl dgst -sha256
-sign`` (no key bytes in argv, env or logs), exchanged at ``POST /app/installations/{id}/access_tokens`` for a token
narrowed to ``issues: write`` and ``pull_requests: read``. The token is cached in this process until a minute before
it expires and is never written to disk. Research: ``build/research/github-app-identities.md``.

CLI::

    gh_app_token.py check ROLE      # key present? app reachable? Prints status only.
"""

from __future__ import annotations

import argparse
import base64
import http.client
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROLES = ("orchestrator", "researcher", "designer", "coder", "verifier", "reviewer", "steward", "menial", "triage")
API = "https://api.github.com"
PERMISSIONS = {"issues": "write", "pull_requests": "read"}
TIMEOUT = 20
#: Shorter limit for the identity probe, so a dead network falls back to the owner quickly.
PROBE_TIMEOUT = 5

#: ``role -> (token, expiry epoch seconds)``; process memory only.
_CACHE: Dict[str, Tuple[str, float]] = {}


class AppError(Exception):
    """A key, config or API problem. Messages never contain a key or a token.

    ``status`` is the HTTP status when GitHub answered with an error, else ``None``."""

    status: Optional[int] = None


# MARK: - Files

def apps_dir() -> Path:
    """The folder holding keys and ``apps.json`` (``FENTON_HASS_APPS_DIR`` overrides, for tests)."""
    override = os.environ.get("FENTON_HASS_APPS_DIR")
    return Path(override) if override else Path.home() / ".config" / "fenton-hass" / "github-apps"


def check_role(role: str) -> str:
    """``role`` if it is one of ``ROLES``, else ``AppError``."""
    if role not in ROLES:
        raise AppError(f"unknown role {role!r}")
    return role


def key_path(role: str) -> Path:
    """Where the role's private key lives."""
    return apps_dir() / f"{check_role(role)}.pem"


def has_key(role: str) -> bool:
    """Whether the role's key file exists (it is not read)."""
    return key_path(role).is_file()


def config() -> Dict[str, Any]:
    """The non-secret ``apps.json`` (empty when absent or unreadable)."""
    try:
        data = json.loads((apps_dir() / "apps.json").read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def ids(role: str) -> Tuple[int, int]:
    """``(app_id, installation_id)`` for the role from ``apps.json``."""
    entry = (config().get("apps") or {}).get(check_role(role)) or {}
    try:
        return int(entry["app_id"]), int(entry["installation_id"])
    except (KeyError, TypeError, ValueError):
        raise AppError(f"no app_id/installation_id for {role} in apps.json") from None


def app_id(role: str) -> int:
    """The role's ``app_id`` from ``apps.json``."""
    entry = (config().get("apps") or {}).get(check_role(role)) or {}
    try:
        return int(entry["app_id"])
    except (KeyError, TypeError, ValueError):
        raise AppError(f"no app_id for {role} in apps.json") from None


def recorded_slug(role: str) -> str:
    """The slug recorded in ``apps.json`` for the role, or ``s-h-<role>`` when none is recorded."""
    entry = (config().get("apps") or {}).get(check_role(role)) or {}
    value = entry.get("slug")
    return value if isinstance(value, str) and value else f"s-h-{role}"


def has_recorded_slug(role: str) -> bool:
    """Whether ``apps.json`` holds a slug for the role."""
    entry = (config().get("apps") or {}).get(check_role(role)) or {}
    return bool(isinstance(entry.get("slug"), str) and entry.get("slug"))


def default_repo() -> str:
    """``owner/name`` of the repository this checkout belongs to: ``GITHUB_REPOSITORY``, else the ``origin`` remote.

    Raises:
        AppError: Neither names a GitHub repository. No repository name is written in this file.
    """
    named = os.environ.get("GITHUB_REPOSITORY", "").strip()
    if re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", named):
        return named
    try:
        url = subprocess.run(["git", "-C", str(Path(__file__).resolve().parents[1]), "remote", "get-url", "origin"],
                             capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        url = ""
    match = re.search(r"github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?$", url)
    if not match:
        raise AppError('no repository: set GITHUB_REPOSITORY or the "repo" key of apps.json')
    return match.group(1)


def repo() -> str:
    """``owner/name`` of the repository the apps are installed on (``apps.json``, else :func:`default_repo`)."""
    return str(config().get("repo") or default_repo())


def available(role: str) -> bool:
    """Whether the role has a key and an ``app_id``, so ``token`` can be tried (the installation id can be looked up)."""
    try:
        app_id(role)
    except AppError:
        return False
    return has_key(role)


# MARK: - JWT

def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def jwt(role: str, now: Optional[float] = None, timeout: float = TIMEOUT) -> str:
    """An RS256 JWT for the role's app, signed by ``openssl`` from the key file."""
    issuer = app_id(role)
    path = key_path(role)
    if not path.is_file():
        raise AppError(f"no key for {role}")
    at = int(time.time() if now is None else now)
    head = _b64(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
    claims = _b64(json.dumps({"iat": at - 60, "exp": at + 540, "iss": str(issuer)}, separators=(",", ":")).encode())
    signing_input = f"{head}.{claims}".encode()
    try:
        done = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(path)], input=signing_input,
                              capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        raise AppError("openssl unavailable or timed out") from None
    if done.returncode != 0 or not done.stdout:
        raise AppError("openssl could not sign with the key")
    return f"{head}.{claims}.{_b64(done.stdout)}"


# MARK: - HTTP

def api_request(method: str, path: str, bearer: str, payload: Optional[Dict[str, Any]] = None,
                timeout: float = TIMEOUT) -> Any:
    """One JSON call to the GitHub API; returns the decoded body (``None`` for no content).

    Every failure, including a truncated or non-JSON reply, is an ``AppError``."""
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(f"{API}/{path.lstrip('/')}", data=data, method=method, headers={
        "Authorization": f"Bearer {bearer}", "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "sh-agent-identities",
        "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        err = AppError(f"GitHub answered {exc.code} for {method} {path.split('?')[0]}")
        err.status = exc.code
        raise err from None
    except (urllib.error.URLError, OSError, TimeoutError, http.client.HTTPException):
        raise AppError(f"GitHub unreachable for {method} {path.split('?')[0]}") from None
    try:
        return json.loads(raw) if raw else None
    except ValueError:
        raise AppError(f"GitHub sent unreadable JSON for {method} {path.split('?')[0]}") from None


def _expiry(text: Any) -> float:
    try:
        return datetime.strptime(str(text), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
    except ValueError:
        return time.time() + 1800


#: ``role -> installation id`` found with the app JWT; process memory only.
_INSTALLATIONS: Dict[str, int] = {}
#: The account the apps are installed on, when ``apps.json`` has no installation id.
OWNER_ACCOUNT = "SFenton"


def verify_installation(role: str, installation: int, timeout: float = TIMEOUT) -> bool:
    """Whether ``installation`` exists for the role's app and its account is ``SFenton`` (``GET /app/installations/{id}``
    with the app JWT). A 404 or another account is ``False``; any other failure raises ``AppError``."""
    try:
        reply = api_request("GET", f"app/installations/{int(installation)}", jwt(role, timeout=timeout), timeout=timeout)
    except AppError as exc:
        if exc.status in (403, 404):
            return False
        raise
    account = reply.get("account") if isinstance(reply, dict) else None
    return str((account or {}).get("login") or "").lower() == OWNER_ACCOUNT.lower()


def _discover(role: str, timeout: float) -> int:
    reply = api_request("GET", "app/installations", jwt(role, timeout=timeout), timeout=timeout)
    for item in reply if isinstance(reply, list) else []:
        account = item.get("account") if isinstance(item, dict) else None
        login = str((account or {}).get("login") or "")
        if login.lower() == OWNER_ACCOUNT.lower() and isinstance(item.get("id"), int):
            _INSTALLATIONS[role] = item["id"]
            return item["id"]
    raise AppError(f"no installation of {role} on {OWNER_ACCOUNT}")


def installation_id(role: str, timeout: float = TIMEOUT) -> int:
    """The installation id for the role: the in-memory one, else the one in ``apps.json`` once it is confirmed to
    belong to ``SFenton``, else (missing, 404 or another account) ``GET /app/installations`` choosing the SFenton
    installation. A bad recorded id is never used again in this process."""
    if role in _INSTALLATIONS:
        return _INSTALLATIONS[role]
    try:
        recorded = ids(role)[1]
    except AppError:
        return _discover(role, timeout)
    if verify_installation(role, recorded, timeout=timeout):
        _INSTALLATIONS[role] = recorded
        return recorded
    return _discover(role, timeout)


def permissions(role: str) -> Dict[str, str]:
    """The permissions a comment token for the role is narrowed to (the same for every role)."""
    check_role(role)
    return dict(PERMISSIONS)


def token(role: str, timeout: float = TIMEOUT, extra: Optional[Dict[str, str]] = None) -> str:
    """An installation token for the role (comments only unless ``extra``), minted at most once per process until it nears expiry.

    ``extra`` (for example ``{"checks": "write"}``) is merged into the default ``PERMISSIONS`` for this one request and gets its own
    cache entry; ``PERMISSIONS`` itself never changes, because asking for a permission an App lacks is a 422 for the other roles."""
    key = role + (":" + ",".join(f"{k}={v}" for k, v in sorted(extra.items())) if extra else "")
    cached = _CACHE.get(key)
    if cached and cached[1] - 60 > time.time():
        return cached[0]
    installation = installation_id(role, timeout=timeout)
    body: Dict[str, Any] = {"permissions": {**permissions(role), **(extra or {})}}
    reply = api_request("POST", f"app/installations/{installation}/access_tokens", jwt(role, timeout=timeout),
                        body, timeout=timeout)
    value = reply.get("token") if isinstance(reply, dict) else None
    if not value or not isinstance(value, str):
        raise AppError("GitHub returned no installation token")
    _CACHE[key] = (value, _expiry(reply.get("expires_at")))
    return value


def slug(role: str, timeout: float = TIMEOUT) -> str:
    """The app's slug (the timeline shows ``<slug>[bot]``), read with the JWT."""
    reply = api_request("GET", "app", jwt(role, timeout=timeout), timeout=timeout)
    return str(reply.get("slug") or "") if isinstance(reply, dict) else ""


# MARK: - CLI

def check(role: str) -> Tuple[bool, bool]:
    """``(key present, app reachable)``; reachability is the ``GET /app`` call with the JWT."""
    if not has_key(role):
        return False, False
    try:
        return True, bool(slug(role))
    except AppError:
        return True, False


def main(argv: Optional[List[str]] = None) -> int:
    """Entry point: ``check ROLE`` prints two yes/no facts and exits 0 when both are yes."""
    p = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("role", choices=ROLES)
    args = p.parse_args(argv)
    present, reachable = check(args.role)
    print(f"{args.role}: key {'present' if present else 'missing'}, app {'reachable' if reachable else 'not reachable'}")
    return 0 if present and reachable else 1


if __name__ == "__main__":
    sys.exit(main())
