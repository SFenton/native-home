#!/usr/bin/env python3
"""Stage a live publication into the candidate's simulator container, read-only, through the guard proxy.

    stage.py --proxy https://127.0.0.1:PORT --container DATA_DIR [--chain PROXY_CHAIN] [--account NAME] [--capabilities FILE]

Runs as a child of ``launch.py`` (see :func:`parity_loop.launch.candidate_live_script`), which loads ``FENTON_HASS_TOKEN`` into
this process's environment from ``tools/hass_creds.sh``. The token lives only in this process's memory: it is never written,
printed or logged. The candidate is pointed at the **guard proxy**, never at the real server: the one origin written, to the
container's ``bootstrap.json`` (origin and account, never a token), is the proxy's, so the candidate passes the same allow-list
as the reference. The real server address is not read here at all. ``--chain`` is the proxy's certificate chain file; its first (leaf) certificate is pinned for
this process's own requests.

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
import ssl
import sys
from dataclasses import dataclass
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
    """``https://host[:port]`` for the preview's ``bootstrap.json``; the preview accepts only an https origin without a path.

    The origin staged is the guard proxy's (served over TLS), so a plain ``http`` proxy URL is refused here.
    """
    parts = urlsplit(server.strip())
    if parts.scheme != "https" or not parts.hostname or parts.username or parts.password:
        raise StageError("the live preview needs an https proxy origin (serve the guard proxy over TLS)")
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


def write_container(data_dir: Path, proxy_url: str, account: str, envelope: bytes, assets: Dict[str, bytes]) -> Path:
    """Write the preview inputs into the container. ``bootstrap.json`` holds the **proxy** origin and account, never a token."""
    folder = Path(data_dir) / PREVIEW_SUBPATH
    (folder / "assets").mkdir(parents=True, exist_ok=True)
    for stale in (folder / "assets").iterdir():
        stale.unlink()
    bootstrap = {"live": {"server": origin_of(proxy_url), "accountID": account}}
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

@dataclass(frozen=True)
class Pinned:
    """A TLS context for the proxy plus the sha256 of the one leaf certificate it may present.

    The proxy's certificate is throwaway and loopback-only, so this process pins it instead of walking a chain: some system
    TLS libraries (the macOS Xcode Python's LibreSSL) cannot evaluate the CA's IP name constraint and would refuse every connection.
    The simulator, which does evaluate it, trusts the constrained CA.
    """
    context: ssl.SSLContext
    sha256: str

    def check(self, der: Optional[bytes]) -> None:
        """Refuse a peer whose certificate is not the pinned leaf."""
        if not der or hashlib.sha256(der).hexdigest() != self.sha256:
            raise StageError("the proxy presented a certificate other than its own")


def client_context(scheme: str, chain: Optional[Path]) -> Optional[Pinned]:
    """The pinned TLS context for an ``https`` proxy whose chain file is ``chain``; ``None`` for plain ``http``.

    An ``https`` proxy without a chain file is refused: nothing is connected without a certificate to hold the peer to.
    """
    if scheme != "https":
        return None
    if not chain or not Path(chain).is_file():
        raise StageError("an https proxy needs its certificate chain file (--chain)")
    first = re.search(r"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", Path(chain).read_text(encoding="utf-8"), re.S)
    if not first:
        raise StageError("the chain file holds no certificate")
    context = ssl.create_default_context()
    context.check_hostname, context.verify_mode = False, ssl.CERT_NONE  # the pin below decides, not a name or a chain
    return Pinned(context, hashlib.sha256(base64.b64decode("".join(first.group(1).split()))).hexdigest())


async def fetch_event(host: str, port: int, token: str, capabilities: Sequence[str], timeout: float = 30.0,
                      context: Optional[Pinned] = None) -> Dict[str, Any]:
    """Authenticate through the proxy, subscribe, take the first event, then unsubscribe and close."""
    async def go() -> Dict[str, Any]:
        reader, writer = await asyncio.open_connection(host, port, ssl=context.context if context else None,
                                                       server_hostname=host if context else None)
        if context:
            context.check(writer.get_extra_info("ssl_object").getpeercert(True))
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


def fetch_asset(host: str, port: int, token: str, digest: str, timeout: float = 60.0,
                context: Optional[Pinned] = None) -> bytes:
    """``GET /api/fenton_home/ui_assets/{sha256}`` through the proxy; the body must hash to ``digest``."""
    conn = (http.client.HTTPSConnection(host, port, timeout=timeout, context=context.context) if context
            else http.client.HTTPConnection(host, port, timeout=timeout))
    if context:
        try:
            conn.connect()
            context.check(conn.sock.getpeercert(True))
        except (OSError, http.client.HTTPException) as error:
            conn.close()
            raise StageError(f"asset fetch failed ({type(error).__name__})") from None
        except StageError:
            conn.close()
            raise
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


async def stage(proxy_url: str, container: Path, token: str, account: str, capabilities: Sequence[str],
                chain: Optional[Path] = None) -> Dict[str, Any]:
    """Fetch the publication and its assets through ``proxy_url`` and write them into ``container``; return counts only.

    The bootstrap names ``proxy_url``'s origin, so the candidate reads through the guard proxy exactly as the reference does.
    """
    origin_of(proxy_url)  # refuse before any network traffic
    parts = urlsplit(proxy_url)
    host, port = parts.hostname or "127.0.0.1", parts.port or 443
    context = client_context(parts.scheme, chain)
    event = await fetch_event(host, port, token, capabilities, context=context)
    envelope = envelope_bytes(event)
    loop = asyncio.get_running_loop()
    assets: Dict[str, bytes] = {}
    for digest in asset_hashes(event["envelope"]):
        assets[digest] = await loop.run_in_executor(None, fetch_asset, host, port, token, digest, 60.0, context)
    write_container(container, proxy_url, account, envelope, assets)
    return {"revision": event["envelope"]["revision"], "assets": len(assets), "envelopeBytes": len(envelope)}


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--proxy", required=True, help="guard proxy URL (https://127.0.0.1:PORT)")
    ap.add_argument("--chain", type=Path, help="the proxy's certificate chain file (its leaf is pinned for this process's requests)")
    ap.add_argument("--container", type=Path, required=True, help="the candidate's data container")
    ap.add_argument("--account", default="parity-loop")
    ap.add_argument("--capabilities", type=Path, default=DEFAULT_CAPABILITIES)
    args = ap.parse_args(argv)
    token = os.environ.get("FENTON_HASS_TOKEN", "")
    if not token:
        print("stage: the token is not set", file=sys.stderr)
        return 2
    try:
        summary = asyncio.run(stage(args.proxy, args.container, token, args.account, load_capabilities(args.capabilities), args.chain))
    except (StageError, OSError, ValueError) as error:
        print(f"stage: {error if isinstance(error, StageError) else type(error).__name__}", file=sys.stderr)
        return 1
    print(f"staged revision {summary['revision']}, {summary['assets']} assets, {summary['envelopeBytes']} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
