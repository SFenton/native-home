#!/usr/bin/env python3
"""Create the nine agent GitHub Apps with the owner's clicks and file their keys. The owner runs ``serve``; agents never do.

``gh_apps_setup.py serve`` starts a local server on ``127.0.0.1`` only and opens a page that lists the nine roles with
their state from ``apps.json`` (not created, created, installed). Each role's button POSTs its manifest to
``https://github.com/settings/apps/new?state=<per-run token>``. GitHub returns the browser to ``/created`` with a
one-hour ``code``; this server exchanges it at ``POST /app-manifests/{code}/conversions`` (the only moment the private key
is delivered), writes the key to ``<role>.pem`` (atomic, mode 600, folder 700) and merges ``app_id``, ``slug`` and
``client_id`` into ``apps.json``. Then it sends the browser to the app's install page; GitHub returns to ``/installed``
with ``installation_id``, which is recorded too. ``client_secret`` and ``webhook_secret`` are never written, and no key
is printed, logged, echoed or put in a page. Design: ``build/research/github-app-identities.md``.

    gh_apps_setup.py serve [--port 8765] [--no-browser]
"""

from __future__ import annotations

import argparse
import hmac
import html
import http.server
import json
import os
import re
import secrets
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gh_app_token  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
HOST = "127.0.0.1"
DEFAULT_PORT = 8765
NEW_APP_URL = "https://github.com/settings/apps/new"
#: Base of the manifest conversion endpoint; tests point it at a local stub.
CONVERT_BASE = "https://api.github.com"
INSTALL_URL = "https://github.com/apps/{slug}/installations/new"


def repo_url() -> str:
    """The App homepage: this checkout's GitHub repository (``gh_app_token.default_repo``), else the GitHub root."""
    try:
        return "https://github.com/" + gh_app_token.default_repo()
    except gh_app_token.AppError:
        return "https://github.com"


PERMISSIONS = {"issues": "write", "pull_requests": "read", "metadata": "read"}
_SLUG = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,99}$")
_PEM = re.compile(r"^-----BEGIN [A-Z ]*PRIVATE KEY-----")

#: How the pages name the private request repository: its real name is local configuration (``tools/request_repo.py``), never this file.
REQUEST_REPO_LABEL = "the private request repository"

#: ``role -> (display name, description, extra repository the app may also be installed on)``.
ROLE_TABLE: Dict[str, tuple] = {
    "orchestrator": ("S+H Orchestrator", "S+H agent comments on pull requests: hand-offs, owner replies and shipped notes.", None),
    "researcher": ("S+H Researcher", "S+H agent comments on pull requests: research conclusions.", None),
    "designer": ("S+H Designer", "S+H agent comments on pull requests: design picks and verdicts.", None),
    "coder": ("S+H Coder", "S+H agent comments on pull requests: implementation notes.", None),
    "verifier": ("S+H Verifier", "S+H agent comments on pull requests: device evidence and pose pictures.", None),
    "reviewer": ("S+H Reviewer", "S+H agent comments on pull requests: review findings tied to a picture.", None),
    "steward": ("S+H Steward", "S+H agent comments: post-mortems and follow-up issues.", REQUEST_REPO_LABEL),
    "menial": ("S+H Menial", "S+H agent comments: mechanical re-runs and status.", None),
    "triage": ("S+H Triage", "S+H triage runner: request updates and results.", REQUEST_REPO_LABEL),
}


def slug(role: str) -> str:
    """The slug the timeline shows (as ``<slug>[bot]``) when none is recorded: ``s-h-<role>``."""
    return f"s-h-{role}"


# MARK: - Manifest

def manifest(role: str, port: int = DEFAULT_PORT) -> Dict[str, Any]:
    """The App manifest for a role: private, no webhook, ``issues: write``, ``pull_requests: read``, ``metadata: read``.

    ``redirect_url`` receives the one-hour ``code``; ``setup_url`` receives ``installation_id`` after an install
    (``setup_on_update`` repeats that after a permission update)."""
    name, description, _extra = ROLE_TABLE[role]
    base = f"http://{HOST}:{port}"
    return {"name": name, "description": description, "url": repo_url(), "public": False,
            "redirect_url": f"{base}/created?role={role}", "setup_url": f"{base}/installed?role={role}",
            "setup_on_update": True, "hook_attributes": {"url": repo_url(), "active": False},
            "default_permissions": dict(PERMISSIONS)}


# MARK: - Files

def _atomic_write(path: Path, data: bytes) -> None:
    """Write ``path`` through a mode-600 temp file in the same folder, then rename it over the target."""
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def ensure_folder() -> Path:
    """The apps folder, created with mode 700."""
    folder = gh_app_token.apps_dir()
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    folder.chmod(0o700)
    return folder


def load_strict() -> Dict[str, Any]:
    """``apps.json`` as a dict; ``{}`` when absent. A file that exists but cannot be parsed raises ``SetupError`` so
    nothing is ever written over it."""
    path = gh_app_token.apps_dir() / "apps.json"
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        data = None
    if not isinstance(data, dict):
        raise SetupError(f"apps.json exists but cannot be read as JSON; fix or move {path} and reload. Nothing was written")
    return data


def record(role: str, **fields: Any) -> None:
    """Merge ``fields`` into ``apps.json`` under the role (other roles and keys are kept) and set the repo.

    Raises ``SetupError`` without writing when the existing file cannot be parsed."""
    data = load_strict()
    folder = ensure_folder()
    apps = data.get("apps") if isinstance(data.get("apps"), dict) else {}
    entry = dict(apps.get(role) or {})
    entry.update(fields)
    apps[role] = entry
    data["apps"] = apps
    try:
        data.setdefault("repo", gh_app_token.default_repo())
    except gh_app_token.AppError:
        pass
    _atomic_write(folder / "apps.json", (json.dumps(data, indent=2, sort_keys=True) + "\n").encode())


def role_state(role: str) -> str:
    """``installed``, ``created`` or ``not created``, from ``apps.json``."""
    entry = (gh_app_token.config().get("apps") or {}).get(role) or {}
    if entry.get("installation_id"):
        return "installed"
    return "created" if entry.get("app_id") else "not created"


def all_installed() -> bool:
    """Whether every role has an installation recorded."""
    return all(role_state(r) == "installed" for r in gh_app_token.ROLES)


def summary() -> List[str]:
    """One line per role with ids only, never key material."""
    lines = []
    for role in gh_app_token.ROLES:
        entry = (gh_app_token.config().get("apps") or {}).get(role) or {}
        ids = ", ".join(f"{k} {entry[k]}" for k in ("app_id", "installation_id") if entry.get(k))
        lines.append(f"{role}: {role_state(role)}" + (f" ({ids})" if ids else ""))
    return lines


# MARK: - GitHub

class SetupError(Exception):
    """A refused or failed step. Messages are safe to show: no code, key or response body."""


def convert(code: str) -> Dict[str, Any]:
    """Exchange the manifest ``code`` for the app's credentials (unauthenticated, one use).

    Returns only ``app_id``, ``slug``, ``client_id`` and the key text; the secrets in the reply are dropped here."""
    req = urllib.request.Request(f"{CONVERT_BASE}/app-manifests/{urllib.parse.quote(code, safe='')}/conversions",
                                 data=b"", method="POST",
                                 headers={"Accept": "application/vnd.github+json", "User-Agent": "sh-agent-identities",
                                          "X-GitHub-Api-Version": "2022-11-28"})
    try:
        with urllib.request.urlopen(req, timeout=gh_app_token.TIMEOUT) as resp:
            body = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        raise SetupError(f"GitHub refused the code (HTTP {exc.code}); it may have expired or been used") from None
    except Exception:  # noqa: BLE001 - never let a body or key reach a message
        raise SetupError("GitHub could not be reached or sent an unreadable reply") from None
    if not isinstance(body, dict):
        raise SetupError("GitHub sent an unexpected reply")
    material, app_id, app_slug = body.get("pem"), body.get("id"), body.get("slug")
    if not (isinstance(material, str) and _PEM.match(material) and isinstance(app_id, int) and isinstance(app_slug, str)
            and _SLUG.match(app_slug)):
        raise SetupError("GitHub's reply lacked a key, id or slug")
    return {"app_id": app_id, "slug": app_slug, "client_id": str(body.get("client_id") or ""), "key": material}


#: Ids whose key is on disk but whose ``apps.json`` write failed; retried on the next page load.
PENDING: Dict[str, Dict[str, Any]] = {}


def retry_pending() -> None:
    """Retry recording ids for roles whose key was written but whose ``apps.json`` write failed."""
    for role, fields in list(PENDING.items()):
        try:
            record(role, **fields)
            del PENDING[role]
        except (SetupError, OSError):
            pass


def manual_line(role: str, fields: Dict[str, Any]) -> str:
    """The non-secret ``apps.json`` entry to add by hand."""
    return f'"{role}": {json.dumps(fields, sort_keys=True)}'


def handle_created(role: str, code: str) -> str:
    """Convert the code, store the key and ids, and return the slug. Raises ``SetupError``.

    ``apps.json`` is checked before the one-use code is spent."""
    load_strict()
    result = convert(code)
    fields = {"app_id": result["app_id"], "slug": result["slug"], "client_id": result["client_id"]}
    try:
        ensure_folder()
        _atomic_write(gh_app_token.key_path(role), result["key"].encode())
    except OSError:
        raise SetupError(f"the app now exists on GitHub but its key could not be saved. Delete it at "
                         f"https://github.com/settings/apps/{result['slug']}/advanced and create it again") from None
    try:
        record(role, **fields)
    except (SetupError, OSError) as exc:
        PENDING[role] = fields
        raise SetupError(f"the key is saved but apps.json was not updated ({exc}). Reload this page to retry, or add "
                         f"this line under \"apps\" by hand: {manual_line(role, fields)}") from None
    return result["slug"]


# MARK: - Server

CSS = ("body{font:16px system-ui;max-width:44rem;margin:2rem auto;padding:0 1rem}"
       "section{border:1px solid #8886;border-radius:8px;padding:0 1rem 1rem;margin:1rem 0}"
       "button,a.btn{font:inherit;padding:.5rem 1rem}")


def render_page(port: int, state: str, notice: str = "") -> str:
    """The page: a section per role with its state, a create form or the install link, and the next step."""
    sections: List[str] = []
    for role in gh_app_token.ROLES:
        name, description, extra = ROLE_TABLE[role]
        st = role_state(role)
        entry = (gh_app_token.config().get("apps") or {}).get(role) or {}
        where = "the main repository" +(f" (and optionally {extra})" if extra else "")
        if st == "not created":
            data = html.escape(json.dumps(manifest(role, port)), quote=True)
            action = (f'<form method="post" action="{NEW_APP_URL}?state={urllib.parse.quote(state)}" id="{role}">'
                      f'<input type="hidden" name="manifest" value="{data}">'
                      f'<button type="submit">Create {html.escape(name)}</button></form>')
            step = "Next: create it, then confirm on GitHub."
        elif st == "created":
            app_slug = str(entry.get("slug") or slug(role))
            link = html.escape(INSTALL_URL.format(slug=urllib.parse.quote(app_slug)))
            action = f'<a class="btn" href="{link}">Install {html.escape(name)}</a>'
            step = f"Next: install on {html.escape(where)}."
        else:
            action = ""
            step = "Installed on the main repository."
            if extra:
                step += f" A second installation on {html.escape(extra)} is optional."
        sections.append(f'<section><h2>{html.escape(name)} <small>({st})</small></h2><p>{html.escape(description)}</p>'
                        f"<p>{step}</p>{action}</section>")
    banner = f"<p><b>{html.escape(notice)}</b></p>" if notice else ""
    done = "<p><b>All nine are installed. You can close this tab.</b></p>" if all_installed() else ""
    return ('<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><title>S+H agent GitHub Apps</title>'
            f"<style>{CSS}</style></head><body><h1>S+H agent GitHub Apps</h1>{banner}{done}<p>{html.escape(NOTE)}</p>"
            + "\n".join(sections) + "</body></html>\n")


class SetupServer(http.server.HTTPServer):
    """Loopback server holding this run's CSRF ``state`` token."""

    def __init__(self, port: int = DEFAULT_PORT) -> None:
        super().__init__((HOST, port), Handler)
        self.state = secrets.token_urlsafe(24)
        self.port = self.server_address[1]
        self.finished = threading.Event()

    def check_done(self) -> None:
        """Stop serving once every role is installed."""
        if all_installed() and not self.finished.is_set():
            self.finished.set()
            threading.Thread(target=self.shutdown, daemon=True).start()


class Handler(http.server.BaseHTTPRequestHandler):
    """Routes ``/``, ``/created`` and ``/installed``. Request lines carry the one-time code, so nothing is logged."""

    server: SetupServer

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        """Silence the default access log."""

    def _send(self, status: int, body: str) -> None:
        raw = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def _redirect(self, location: str) -> None:
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _page(self, status: int = 200, notice: str = "") -> None:
        self._send(status, render_page(self.server.port, self.server.state, notice))

    def do_GET(self) -> None:  # noqa: N802
        """Check the Host header (DNS rebinding), then dispatch; any failure shows a plain error, no traceback."""
        port = self.server.port
        if self.headers.get("Host", "") not in (f"127.0.0.1:{port}", f"localhost:{port}"):
            self._send(403, "<p>Refused: unexpected Host.</p>")
            return
        try:
            self._route()
        except Exception as exc:  # noqa: BLE001 - never a traceback in the browser
            print(f"gh_apps_setup: request failed ({type(exc).__name__})", file=sys.stderr, flush=True)
            try:
                self._send(500, "<p>Something went wrong. Check the terminal and reload.</p>")
            except OSError:
                pass

    def _route(self) -> None:
        retry_pending()
        parsed = urllib.parse.urlparse(self.path)
        query = {k: v[0] for k, v in urllib.parse.parse_qs(parsed.query).items()}
        role = query.get("role", "")
        if parsed.path == "/":
            self._page()
        elif parsed.path == "/created":
            self._created(role, query)
        elif parsed.path == "/installed":
            self._installed(role, query)
        else:
            self._send(404, "<p>Not found.</p>")

    def _created(self, role: str, query: Dict[str, str]) -> None:
        if not hmac.compare_digest(query.get("state", "").encode(), self.server.state.encode()):
            self._page(403, "Refused: the state token did not match this run.")
            return
        if role not in gh_app_token.ROLES:
            self._page(400, "Refused: unknown role.")
            return
        code = query.get("code", "")
        if not code:
            self._page(400, "Refused: GitHub sent no code.")
            return
        try:
            app_slug = handle_created(role, code)
        except SetupError as exc:
            self._page(502, f"{role}: {exc}.")
            return
        print(f"gh_apps_setup: {role} created", flush=True)
        self._redirect(INSTALL_URL.format(slug=app_slug))

    def _installed(self, role: str, query: Dict[str, str]) -> None:
        if role not in gh_app_token.ROLES:
            self._page(400, "Refused: unknown role.")
            return
        raw = query.get("installation_id", "")
        if not raw.isdigit() or role_state(role) == "not created":
            self._page(400, f"{role}: no installation id, or the app is not created yet.")
            return
        try:
            confirmed = gh_app_token.verify_installation(role, int(raw))
        except gh_app_token.AppError:
            self._page(502, f"{role}: could not confirm the installation with GitHub; nothing was recorded. Try again.")
            return
        if not confirmed:
            self._page(400, f"{role}: that installation is not this app's on SFenton; ignored.")
            return
        try:
            record(role, installation_id=int(raw))
        except SetupError as exc:
            self._page(500, f"{role}: {exc}")
            return
        print(f"gh_apps_setup: {role} installed", flush=True)
        self._page(200, f"{role} installed ({query.get('setup_action', 'install')}).")
        self.server.check_done()


NOTE = ("Do one role end to end first (create it, install it) and confirm the page shows it installed before the other "
        "eight: the role query on GitHub's redirects and the loopback setup_url are not yet verified live.")


def serve(port: int = DEFAULT_PORT, open_browser: bool = True) -> int:
    """Run the helper until all nine are installed or Ctrl-C, then print one line per role."""
    try:
        server = SetupServer(port)
    except OSError:
        print(f"gh_apps_setup: port {port} is busy; try --port", file=sys.stderr)
        return 1
    url = f"http://{HOST}:{server.port}/"
    print(f"gh_apps_setup: open {url} (Ctrl-C to stop)", flush=True)
    print(NOTE, flush=True)
    if open_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    print("\n".join(summary()))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    """Entry point: ``serve`` only. The old static page is gone."""
    p = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    sub = p.add_subparsers(dest="cmd")
    s = sub.add_parser("serve", help="start the local helper and open the page")
    s.add_argument("--port", type=int, default=DEFAULT_PORT)
    s.add_argument("--no-browser", action="store_true")
    args = p.parse_args(argv)
    if args.cmd != "serve":
        print("gh_apps_setup: use `gh_apps_setup.py serve`", file=sys.stderr)
        return 2
    return serve(args.port, not args.no_browser)


if __name__ == "__main__":
    sys.exit(main())
