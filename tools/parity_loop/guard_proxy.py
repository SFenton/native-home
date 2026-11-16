#!/usr/bin/env python3
"""The write-guard proxy for the live reference: reads and subscriptions pass, every write is refused.

    guard_proxy.py --listen 127.0.0.1:PORT --log RUN/proxy-rejections.jsonl [--upstream-env FENTON_HASS_SERVER]
                   [--certfile F --keyfile F] [--allow-type TYPE ...] [--allow-path PREFIX ...]

The reference app is pointed at this proxy instead of the real Home Assistant, so a stray write (a ``call_service``, a
``mobile_app`` registration, a webhook POST) cannot reach production. Both filters are **allow-lists**: a message type or a
path that is not named is refused.

* WebSocket (``/api/websocket``): each client message is parsed and judged by :func:`ws_decide`; a refused message is not
  forwarded and the client gets a ``result`` error with code ``read_only``. Server frames pass through untouched.
* HTTP: only ``GET`` to a path :func:`http_decide` allows is forwarded; every other method and path gets ``403``.

The rejection log records the kind, message type or method, the path without its query string and the reason. It never
records a body, a header or a token, and nothing here prints the upstream address. Python 3 standard library only.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import http.client
import json
import os
import ssl
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.parse import urlsplit

WS_GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
#: WebSocket client message types that read or subscribe. Anything else is refused (an allow-list, never a deny-list).
WS_ALLOWED_TYPES = frozenset({
    "auth", "ping", "pong", "supported_features", "auth/current_user",
    "get_states", "get_config", "get_services", "get_panels",
    "subscribe_events", "subscribe_entities", "unsubscribe_events", "render_template",
    "config/entity_registry/list", "config/entity_registry/list_for_display", "config/device_registry/list",
    "config/area_registry/list", "config/floor_registry/list", "config/label_registry/list",
    "person/list", "schedule/list", "todo/item/list",
    "fenton_home/house_config/subscribe", "fenton_home/ui_publication/subscribe", "fenton_home/ui_publication/get",
})
#: Types under ``fenton_home/`` ending in one of these are reads too (``fenton_home`` reads), whatever their middle part.
FENTON_READ_SUFFIXES = ("/subscribe", "/get", "/list")
#: HTTP paths (prefix match on a ``/``-boundary, plus the exact paths below) a ``GET`` may reach.
HTTP_ALLOWED_PREFIXES = (
    "/api/websocket", "/api/config", "/api/states", "/api/fenton_home/ui_assets", "/api/fenton_home/config",
    "/api/camera_proxy", "/api/image_proxy", "/api/media_player_proxy", "/api/history/period", "/local", "/static",
    "/frontend_latest", "/hacsfiles",
)
#: ``/api/`` alone (the connectivity probe) is allowed as an exact path, not as a prefix of everything under ``/api``.
HTTP_EXACT_PATHS = frozenset({"/api/", "/api", "/manifest.json", "/api/services"})
#: Prefixes that are refused even for ``GET`` or when a caller widens the allow-list.
HTTP_NEVER_PREFIXES = ("/api/mobile_app", "/api/webhook", "/api/fenton_feedback", "/api/events", "/api/template")
READ_ONLY_CODE = "read_only"


# MARK: - Filters

@dataclass(frozen=True)
class Decision:
    """The verdict on one message or request."""
    allowed: bool
    kind: str  # "ws" | "http"
    label: str  # message type, or HTTP method
    reason: str = ""


def ws_decide(message: Any, extra_types: Iterable[str] = ()) -> Decision:
    """Judge one decoded WebSocket client message (a dict). ``call_service`` and every unnamed type are refused."""
    if not isinstance(message, dict):
        return Decision(False, "ws", "<non-object>", "message is not a JSON object")
    kind = message.get("type")
    if not isinstance(kind, str) or not kind:
        return Decision(False, "ws", "<untyped>", "message has no type")
    if kind in WS_ALLOWED_TYPES or kind in set(extra_types):
        return Decision(True, "ws", kind)
    if kind.startswith("fenton_home/") and kind.endswith(FENTON_READ_SUFFIXES):
        return Decision(True, "ws", kind)
    return Decision(False, "ws", kind, "type is not on the read allow-list")


def http_decide(method: str, path: str, extra_prefixes: Iterable[str] = ()) -> Decision:
    """Judge one HTTP request line: only ``GET`` to an allow-listed path passes. The query string is ignored."""
    bare = path.split("?", 1)[0].split("#", 1)[0]
    if method.upper() != "GET":
        return Decision(False, "http", method.upper(), "only GET is allowed")
    if ".." in bare.split("/"):
        return Decision(False, "http", "GET", "path traversal")
    if any(_under(bare, p) for p in HTTP_NEVER_PREFIXES):
        return Decision(False, "http", "GET", "path is never allowed")
    if bare.startswith("/api/services/"):
        return Decision(False, "http", "GET", "service paths are never allowed")
    if bare in HTTP_EXACT_PATHS or any(_under(bare, p) for p in tuple(HTTP_ALLOWED_PREFIXES) + tuple(extra_prefixes)):
        return Decision(True, "http", "GET")
    return Decision(False, "http", "GET", "path is not on the read allow-list")


def _under(path: str, prefix: str) -> bool:
    prefix = prefix.rstrip("/")
    return path == prefix or path.startswith(prefix + "/")


def filter_ws_payload(text: str, extra_types: Iterable[str] = ()) -> Tuple[Optional[str], List[Tuple[Decision, Any]]]:
    """Split one text frame into what to forward and the refused messages with their ids.

    Returns ``(forward_text_or_None, [(decision, message_id), ...for every refused message])``. A JSON array (coalesced
    messages) is judged element by element; unparseable text is refused whole.
    """
    try:
        value = json.loads(text)
    except ValueError:
        return None, [(Decision(False, "ws", "<invalid-json>", "frame is not JSON"), None)]
    items = value if isinstance(value, list) else [value]
    keep: List[Any] = []
    refused: List[Tuple[Decision, Any]] = []
    for item in items:
        verdict = ws_decide(item, extra_types)
        if verdict.allowed:
            keep.append(item)
        else:
            refused.append((verdict, item.get("id") if isinstance(item, dict) else None))
    if not keep:
        return None, refused
    return (json.dumps(keep if isinstance(value, list) else keep[0], separators=(",", ":")), refused)


def refusal_frame_text(message_id: Any) -> str:
    """The ``result`` error sent to the client in place of a refused message."""
    body: Dict[str, Any] = {"type": "result", "success": False,
                            "error": {"code": READ_ONLY_CODE, "message": "refused by the parity-loop write guard"}}
    if isinstance(message_id, int):
        body["id"] = message_id
    return json.dumps(body, separators=(",", ":"))


# MARK: - Rejection log

class RejectionLog:
    """An append-only JSONL log of refusals: kind, type or method, path and reason, plus running counts. No bodies, no tokens."""

    def __init__(self, path: Optional[Path]) -> None:
        self.path = Path(path) if path else None
        self.counts: Dict[str, int] = {}
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)

    def record(self, decision: Decision, path: str = "") -> None:
        key = f"{decision.kind}:{decision.label}"
        self.counts[key] = self.counts.get(key, 0) + 1
        if self.path is None:
            return
        row = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "kind": decision.kind, "label": decision.label,
               "path": path.split("?", 1)[0], "reason": decision.reason}
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row) + "\n")


# MARK: - WebSocket frames

def encode_frame(opcode: int, payload: bytes, mask: bool, fin: bool = True) -> bytes:
    """One RFC 6455 frame; a masking client (the proxy toward the server) sets ``mask``."""
    head = bytes([(0x80 if fin else 0) | opcode])
    n = len(payload)
    flag = 0x80 if mask else 0
    if n < 126:
        head += bytes([flag | n])
    elif n < 1 << 16:
        head += bytes([flag | 126]) + n.to_bytes(2, "big")
    else:
        head += bytes([flag | 127]) + n.to_bytes(8, "big")
    if not mask:
        return head + payload
    key = os.urandom(4)
    return head + key + bytes(b ^ key[i % 4] for i, b in enumerate(payload))


async def read_frame(reader: asyncio.StreamReader) -> Tuple[bool, int, bytes]:
    """``(fin, opcode, unmasked payload)`` of the next frame; raises ``IncompleteReadError`` at end of stream."""
    first, second = await reader.readexactly(2)
    n = second & 0x7F
    if n == 126:
        n = int.from_bytes(await reader.readexactly(2), "big")
    elif n == 127:
        n = int.from_bytes(await reader.readexactly(8), "big")
    key = await reader.readexactly(4) if second & 0x80 else b""
    data = await reader.readexactly(n)
    if key:
        data = bytes(b ^ key[i % 4] for i, b in enumerate(data))
    return bool(first & 0x80), first & 0x0F, data


def accept_key(client_key: str) -> str:
    return base64.b64encode(hashlib.sha1(client_key.encode() + WS_GUID).digest()).decode()


# MARK: - Proxy

@dataclass
class Upstream:
    host: str
    port: int
    tls: bool

    @classmethod
    def parse(cls, url: str) -> "Upstream":
        parts = urlsplit(url if "//" in url else f"//{url}", scheme="http")
        tls = parts.scheme in ("https", "wss")
        return cls(parts.hostname or "", parts.port or (443 if tls else 80), tls)


class GuardProxy:
    """Fronts one upstream; see the module docstring. ``extra_types`` and ``extra_paths`` widen the allow-lists explicitly."""

    def __init__(self, upstream: Upstream, log: RejectionLog, extra_types: Sequence[str] = (), extra_paths: Sequence[str] = ()) -> None:
        self.upstream, self.log = upstream, log
        self.extra_types, self.extra_paths = tuple(extra_types), tuple(extra_paths)

    def _ssl(self) -> Optional[ssl.SSLContext]:
        return ssl.create_default_context() if self.upstream.tls else None

    async def handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            head = await reader.readuntil(b"\r\n\r\n")
            line, *rest = head.decode("latin-1").split("\r\n")
            method, target, _ = line.split(" ", 2)
            headers = {k.strip().lower(): v.strip() for k, v in (h.split(":", 1) for h in rest if ":" in h)}
            decision = http_decide(method, target, self.extra_paths)
            if not decision.allowed:
                self.log.record(decision, target)
                await self._plain(writer, 403, "refused by the parity-loop write guard")
            elif headers.get("upgrade", "").lower() == "websocket":
                if target.split("?", 1)[0].rstrip("/") != "/api/websocket":
                    d = Decision(False, "http", "UPGRADE", "websocket upgrade outside /api/websocket")
                    self.log.record(d, target)
                    await self._plain(writer, 403, "refused by the parity-loop write guard")
                else:
                    await self._websocket(reader, writer, target, headers)
            else:
                await self._forward_http(writer, target, headers)
        except (asyncio.IncompleteReadError, ConnectionError, ValueError, asyncio.LimitOverrunError):
            pass
        finally:
            writer.close()

    @staticmethod
    async def _plain(writer: asyncio.StreamWriter, status: int, text: str) -> None:
        body = text.encode()
        writer.write(f"HTTP/1.1 {status} {'Forbidden' if status == 403 else 'Error'}\r\nContent-Length: {len(body)}\r\n"
                     f"Content-Type: text/plain\r\nConnection: close\r\n\r\n".encode() + body)
        await writer.drain()

    async def _forward_http(self, writer: asyncio.StreamWriter, target: str, headers: Dict[str, str]) -> None:
        skip = {"host", "connection", "upgrade", "accept-encoding", "content-length", "transfer-encoding", "proxy-connection"}
        send = {k: v for k, v in headers.items() if k not in skip}

        def call() -> Tuple[int, List[Tuple[str, str]], bytes]:
            up = self.upstream
            conn = (http.client.HTTPSConnection(up.host, up.port, timeout=60, context=self._ssl()) if up.tls
                    else http.client.HTTPConnection(up.host, up.port, timeout=60))
            try:
                conn.request("GET", target, headers=send)
                resp = conn.getresponse()
                return resp.status, resp.getheaders(), resp.read()
            finally:
                conn.close()

        try:
            status, response_headers, body = await asyncio.get_running_loop().run_in_executor(None, call)
        except (OSError, http.client.HTTPException):
            await self._plain(writer, 502, "upstream unreachable")
            return
        drop = {"transfer-encoding", "connection", "content-length", "content-encoding"}
        out = [f"HTTP/1.1 {status} OK"] + [f"{k}: {v}" for k, v in response_headers if k.lower() not in drop]
        out += [f"Content-Length: {len(body)}", "Connection: close", "", ""]
        writer.write("\r\n".join(out).encode("latin-1") + body)
        await writer.drain()

    async def _websocket(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, target: str,
                         headers: Dict[str, str]) -> None:
        up = self.upstream
        ureader, uwriter = await asyncio.open_connection(up.host, up.port, ssl=self._ssl(), server_hostname=up.host if up.tls else None)
        key = base64.b64encode(os.urandom(16)).decode()
        uwriter.write((f"GET /api/websocket HTTP/1.1\r\nHost: {up.host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                       f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        await uwriter.drain()
        reply = await ureader.readuntil(b"\r\n\r\n")
        if b" 101 " not in reply.split(b"\r\n", 1)[0]:
            await self._plain(writer, 502, "upstream refused the upgrade")
            uwriter.close()
            return
        writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      f"Sec-WebSocket-Accept: {accept_key(headers.get('sec-websocket-key', ''))}\r\n\r\n").encode())
        await writer.drain()

        async def downstream() -> None:  # server -> client, byte for byte
            while data := await ureader.read(65536):
                writer.write(data)
                await writer.drain()

        async def upstream() -> None:  # client -> server, judged message by message
            buffer, first_opcode = b"", 1
            while True:
                fin, opcode, payload = await read_frame(reader)
                if opcode in (8, 9, 10):
                    uwriter.write(encode_frame(opcode, payload, True))
                    await uwriter.drain()
                    if opcode == 8:
                        return
                    continue
                if opcode == 2:
                    self.log.record(Decision(False, "ws", "<binary>", "binary frames are not allowed"), target)
                    continue
                if opcode in (1, 0):
                    if opcode == 1:
                        buffer, first_opcode = b"", 1
                    buffer += payload
                    if not fin:
                        continue
                    forward, refused = filter_ws_payload(buffer.decode("utf-8", "replace"), self.extra_types)
                    for verdict, message_id in refused:
                        self.log.record(verdict, target)
                        writer.write(encode_frame(1, refusal_frame_text(message_id).encode(), False))
                    await writer.drain()
                    if forward is not None:
                        uwriter.write(encode_frame(first_opcode, forward.encode(), True))
                        await uwriter.drain()

        tasks = [asyncio.ensure_future(downstream()), asyncio.ensure_future(upstream())]
        try:
            await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        finally:
            for task in tasks:
                task.cancel()
            uwriter.close()


async def serve(proxy: GuardProxy, host: str, port: int, certfile: Optional[str] = None, keyfile: Optional[str] = None) -> asyncio.AbstractServer:
    context = None
    if certfile:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile, keyfile)
    return await asyncio.start_server(proxy.handle, host, port, ssl=context)


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--listen", default="127.0.0.1:0", help="HOST:PORT to listen on (port 0 picks one; it is printed)")
    ap.add_argument("--upstream", help="upstream URL (default: the environment variable named by --upstream-env)")
    ap.add_argument("--upstream-env", default="FENTON_HASS_SERVER")
    ap.add_argument("--log", type=Path, help="rejection log (JSONL)")
    ap.add_argument("--certfile")
    ap.add_argument("--keyfile")
    ap.add_argument("--allow-type", action="append", default=[], help="widen the WebSocket allow-list with one read type")
    ap.add_argument("--allow-path", action="append", default=[], help="widen the HTTP allow-list with one GET path prefix")
    args = ap.parse_args(argv)
    url = args.upstream or os.environ.get(args.upstream_env, "")
    if not url:
        print(f"guard_proxy: no upstream (set {args.upstream_env} or pass --upstream)", file=sys.stderr)
        return 2
    host, _, port = args.listen.rpartition(":")
    proxy = GuardProxy(Upstream.parse(url), RejectionLog(args.log), args.allow_type, args.allow_path)

    async def main_async() -> None:
        server = await serve(proxy, host or "127.0.0.1", int(port or 0), args.certfile, args.keyfile)
        print(f"guard_proxy listening on port {server.sockets[0].getsockname()[1]}", flush=True)
        async with server:
            await server.serve_forever()

    try:
        asyncio.run(main_async())
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
