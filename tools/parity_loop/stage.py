#!/usr/bin/env python3
"""Stage a live publication into the candidate's simulator container, read-only, through the guard proxy.

    stage.py --proxy http://127.0.0.1:PORT --container DATA_DIR [--account NAME] [--capabilities FILE]

Runs as a child of ``launch.py`` (see :func:`parity_loop.launch.stage_script`), which loads ``FENTON_HASS_TOKEN`` and
``FENTON_HASS_SERVER`` into this process's environment from ``tools/hass_creds.sh``. Both live only in this process's memory:
the token is never written, printed or logged, and the server origin is written to exactly one file, the container's
``bootstrap.json`` (server and account only, never a token).

Steps, all reads that the guard proxy allows:

1. websocket ``fenton_home/ui_publication/subscribe`` (with the app's capability list): take the first event, unsubscribe, close;
2. ``GET /api/fenton_home/ui_assets/{sha256}`` for every asset the document lists, each checked against its hash;
3. write ``bootstrap.json``, ``publication.json`` (the raw envelope, integer revision, at most 2162688 bytes) and
   ``assets/<lowercase sha256>`` straight into ``<container>/Library/Application Support/ServerUIPreview/``.

Nothing is written under the repository. The files exist only inside the simulator container.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import http.client
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from parity_loop import guard_proxy  # noqa: E402
from parity_loop.common import REPO  # noqa: E402

PREVIEW_SUBPATH = "Library/Application Support/ServerUIPreview"
SUBSCRIBE_COMMAND = "fenton_home/ui_publication/subscribe"
ASSET_PATH = "/api/fenton_home/ui_assets/"
#: The preview refuses a larger envelope (``UKServerUIPreview.publishedEvent``).
MAX_ENVELOPE_BYTES = 2_162_688
MAX_ASSET_BYTES = 32 * 1024 * 1024
DEFAULT_CAPABILITIES = REPO / "apple" / "Tests" / "HassCoreTests" / "ContractCorpus" / "capabilities.json"
SHA256 = re.compile(r"[0-9a-f]{64}")


class StageError(Exception):
    """Staging failed; the message names the step and never carries a token, server address or payload."""


# MARK: - Pure helpers

def load_capabilities(path: Path = DEFAULT_CAPABILITIES) -> List[str]:
    """The capability ids the app supports (the contract corpus list), sent with the subscription."""
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, list) or not all(isinstance(c, str) for c in value):
        raise StageError("the capabilities file is not a list of ids")
    return value


def origin_of(server: str) -> str:
    """``https://host[:port]`` for the preview's ``bootstrap.json``; the preview accepts only an https origin without a path."""
    parts = urlsplit(server.strip())
    if parts.scheme != "https" or not parts.hostname or parts.username or parts.password:
        raise StageError("the live preview needs an https server origin")
    return f"https://{parts.netloc}"


def envelope_bytes(event: Dict[str, Any]) -> bytes:
    """The envelope of a ``published`` event as the bytes of ``publication.json``; checks state, revision and size."""
    if event.get("state") != "published" or not isinstance(event.get("envelope"), dict):
        raise StageError("the integration has no published layout for this build")
    envelope = event["envelope"]
    if not isinstance(envelope.get("revision"), int) or isinstance(envelope.get("revision"), bool):
        raise StageError("the envelope has no integer revision")
    data = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    if len(data) > MAX_ENVELOPE_BYTES:
        raise StageError("the envelope is larger than the preview accepts")
    return data


def asset_hashes(envelope: Dict[str, Any]) -> List[str]:
    """The distinct lowercase sha256 of every asset the document lists, in document order."""
    seen: List[str] = []
    for asset in (envelope.get("document") or {}).get("assets") or []:
        digest = str(asset.get("sha256", "")).lower() if isinstance(asset, dict) else ""
        if not SHA256.fullmatch(digest):
            raise StageError("an asset has no valid sha256")
        if digest not in seen:
            seen.append(digest)
    return seen


def write_container(data_dir: Path, server: str, account: str, envelope: bytes, assets: Dict[str, bytes]) -> Path:
    """Write the preview inputs into the container. ``bootstrap.json`` holds the server origin and account, never a token."""
    folder = Path(data_dir) / PREVIEW_SUBPATH
    (folder / "assets").mkdir(parents=True, exist_ok=True)
    for stale in (folder / "assets").iterdir():
        stale.unlink()
    bootstrap = {"live": {"server": origin_of(server), "accountID": account}}
    _atomic(folder / "publication.json", envelope)
    for digest, body in assets.items():
        _atomic(folder / "assets" / digest, body)
    _atomic(folder / "bootstrap.json", json.dumps(bootstrap, separators=(",", ":")).encode("utf-8"))
    (folder / "receipt.json").unlink(missing_ok=True)
    return folder


def _atomic(path: Path, data: bytes) -> None:
    temp = path.with_name(path.name + ".partial")
    temp.write_bytes(data)
    os.replace(temp, path)


# MARK: - Reads through the proxy

async def fetch_event(host: str, port: int, token: str, capabilities: Sequence[str], timeout: float = 30.0) -> Dict[str, Any]:
    """Authenticate through the proxy, subscribe, take the first event, then unsubscribe and close."""
    async def go() -> Dict[str, Any]:
        reader, writer = await asyncio.open_connection(host, port)
        try:
            key = base64.b64encode(os.urandom(16)).decode()
            writer.write((f"GET /api/websocket HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                          f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
            await writer.drain()
            if b" 101 " not in (await reader.readuntil(b"\r\n\r\n")).split(b"\r\n", 1)[0]:
                raise StageError("the proxy refused the websocket upgrade")

            async def receive() -> Dict[str, Any]:
                while True:
                    _, opcode, payload = await guard_proxy.read_frame(reader)
                    if opcode == 8:
                        raise StageError("the connection closed early")
                    if opcode == 1:
                        value = json.loads(payload)
                        return value if isinstance(value, dict) else {}

            async def send(message: Dict[str, Any]) -> None:
                writer.write(guard_proxy.encode_frame(1, json.dumps(message).encode(), True))
                await writer.drain()

            if (await receive()).get("type") != "auth_required":
                raise StageError("unexpected greeting from the server")
            await send({"type": "auth", "access_token": token})
            if (await receive()).get("type") != "auth_ok":
                raise StageError("the server did not accept the token")
            await send({"id": 1, "type": SUBSCRIBE_COMMAND, "capabilities": list(capabilities)})
            event: Optional[Dict[str, Any]] = None
            while event is None:
                message = await receive()
                if message.get("id") == 1 and message.get("type") == "result" and not message.get("success", True):
                    raise StageError("the integration refused the publication subscription")
                if message.get("id") == 1 and message.get("type") == "event" and isinstance(message.get("event"), dict):
                    event = message["event"]
            await send({"id": 2, "type": "unsubscribe_events", "subscription": 1})
            writer.write(guard_proxy.encode_frame(8, b"", True))
            await writer.drain()
            return event
        finally:
            writer.close()

    try:
        return await asyncio.wait_for(go(), timeout)
    except asyncio.TimeoutError:
        raise StageError("timed out waiting for the publication") from None
    except (OSError, asyncio.IncompleteReadError, ValueError) as error:
        raise StageError(f"publication fetch failed ({type(error).__name__})") from None


def fetch_asset(host: str, port: int, token: str, digest: str, timeout: float = 60.0) -> bytes:
    """``GET /api/fenton_home/ui_assets/{sha256}`` through the proxy; the body must hash to ``digest``."""
    conn = http.client.HTTPConnection(host, port, timeout=timeout)
    try:
        conn.request("GET", ASSET_PATH + digest, headers={"Authorization": f"Bearer {token}"})
        response = conn.getresponse()
        body = response.read(MAX_ASSET_BYTES + 1)
    except (OSError, http.client.HTTPException) as error:
        raise StageError(f"asset fetch failed ({type(error).__name__})") from None
    finally:
        conn.close()
    if response.status != 200:
        raise StageError(f"asset fetch returned {response.status}")
    if len(body) > MAX_ASSET_BYTES:
        raise StageError("an asset is larger than allowed")
    if hashlib.sha256(body).hexdigest() != digest:
        raise StageError("an asset does not match its sha256")
    return body


async def stage(proxy_url: str, container: Path, token: str, server: str, account: str, capabilities: Sequence[str]) -> Dict[str, Any]:
    """Fetch the publication and its assets through ``proxy_url`` and write them into ``container``; return counts only."""
    origin_of(server)  # refuse before any network traffic
    parts = urlsplit(proxy_url)
    host, port = parts.hostname or "127.0.0.1", parts.port or 80
    event = await fetch_event(host, port, token, capabilities)
    envelope = envelope_bytes(event)
    loop = asyncio.get_running_loop()
    assets: Dict[str, bytes] = {}
    for digest in asset_hashes(event["envelope"]):
        assets[digest] = await loop.run_in_executor(None, fetch_asset, host, port, token, digest)
    write_container(container, server, account, envelope, assets)
    return {"revision": event["envelope"]["revision"], "assets": len(assets), "envelopeBytes": len(envelope)}


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--proxy", required=True, help="guard proxy URL (http://127.0.0.1:PORT)")
    ap.add_argument("--container", type=Path, required=True, help="the candidate's data container")
    ap.add_argument("--account", default="parity-loop")
    ap.add_argument("--capabilities", type=Path, default=DEFAULT_CAPABILITIES)
    args = ap.parse_args(argv)
    token, server = os.environ.get("FENTON_HASS_TOKEN", ""), os.environ.get("FENTON_HASS_SERVER", "")
    if not token or not server:
        print("stage: the token or server is not set", file=sys.stderr)
        return 2
    try:
        summary = asyncio.run(stage(args.proxy, args.container, token, server, args.account, load_capabilities(args.capabilities)))
    except (StageError, OSError, ValueError) as error:
        print(f"stage: {error if isinstance(error, StageError) else type(error).__name__}", file=sys.stderr)
        return 1
    print(f"staged revision {summary['revision']}, {summary['assets']} assets, {summary['envelopeBytes']} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
