#!/usr/bin/env python3
"""The write-guard proxy for the live reference: reads and subscriptions pass, every write is refused.

    guard_proxy.py --listen 127.0.0.1:PORT --log RUN/proxy-rejections.jsonl [--upstream-env FENTON_HASS_SERVER]
                   [--certfile F --keyfile F] [--allow-type TYPE ...] [--allow-path PREFIX ...]
    guard_proxy.py scrub FILE...          rewrite existing logs in place to the path-template form

The reference app is pointed at this proxy instead of the real Home Assistant, so a stray write (a ``call_service``, a
``mobile_app`` registration, a webhook POST) cannot reach production. Both filters are **allow-lists**: a message type or a
path that is not named is refused, and the allow-lists are the reads the apps were observed to need, not everything HA serves.

* WebSocket (``/api/websocket``): the client's frames are parsed (fragments reassembled, UTF-8 and JSON checked strictly), each
  message is judged by :func:`ws_decide`, and what passes is **re-serialised** from the parsed value, so the server sees exactly
  what was judged. A refused message is not forwarded and the client gets a ``result`` error with code ``read_only``. A frame
  that breaks the protocol (reserved bits, an unmasked client frame, a reserved opcode, a stray continuation) closes the
  connection. Server frames are relayed frame by frame; refusal replies are written only between whole server messages, so the
  client always sees well-formed frames.
* HTTP: only ``GET`` (exactly, any case but upper is refused) to a clean allow-listed path is forwarded. A path with ``%``,
  ``//``, ``.``/``..`` segments, backslashes or control characters is refused, and ``*method*`` override headers are dropped.

The logs record the kind, message type or method, a path *template* (the first fixed words, everything after replaced by ``*``,
never a query string, id or token) and the reason; for a refused ``call_service``, its domain and service. Allowed traffic is
only counted by type and template in ``allowed-summary.json``. Rows also pass through ``tools/redact.py``. Nothing here prints
the upstream address. Python 3 standard library only.
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
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from redact import redact_json  # noqa: E402

WS_GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
#: WebSocket client message types that read or subscribe: the apps' observed set plus what the brief names. Anything else is
#: refused (an allow-list, never a deny-list). ``--allow-type`` widens it, but never to a write type.
WS_ALLOWED_TYPES = frozenset({
    "auth", "ping", "pong", "auth/current_user", "auth/sign_path",
    "get_states", "get_config", "get_services",
    "subscribe_events", "subscribe_entities", "unsubscribe_events",
    "camera/stream",
    "fenton_home/house_config/subscribe", "fenton_home/ui_publication/subscribe", "fenton_home/ui_publication/get",
})
#: Words that mark a type as a write. A type holding one of these (split on ``/`` and ``_``) can never be allowed, not even by
#: ``--allow-type``, and ``call_service`` is always refused.
WRITE_WORDS = frozenset({
    "call", "service", "execute", "script", "fire", "event_fire", "update", "create", "delete", "remove", "add", "set", "save",
    "publish", "rollback", "register", "upload", "push", "reload", "restart", "stop", "start", "trigger", "write", "enable",
    "disable", "toggle", "press", "run", "reset", "clear", "import", "mutate", "revoke", "login", "logout",
})
#: HTTP path prefixes (matched on ``/`` boundaries) a ``GET`` may reach: the apps' observed reads plus the brief's.
HTTP_ALLOWED_PREFIXES = (
    "/api/websocket", "/api/fenton_home/ui_assets", "/api/fenton_home/config", "/api/image/serve", "/local",
)
#: ``/api/camera_proxy*``: a raw string prefix, so ``/api/camera_proxy_stream/...`` (a streamed GET) is a read too.
HTTP_STARTSWITH = ("/api/camera_proxy",)
#: The connectivity probe, allowed as an exact path only.
HTTP_EXACT_PATHS = frozenset({"/api/", "/api"})
#: Prefixes that are refused even when a caller widens the allow-list.
HTTP_NEVER_PREFIXES = ("/api/mobile_app", "/api/webhook", "/api/fenton_feedback", "/api/events", "/api/template", "/api/services")
READ_ONLY_CODE = "read_only"
#: A request header whose name holds one of these never reaches the upstream (method-override tricks and forwarding hints).
STRIPPED_HEADER_PARTS = ("method", "x-forwarded", "x-original", "x-rewrite", "x-http")
MAX_CLIENT_MESSAGE = 1 << 20
MAX_FRAME = 64 << 20


# MARK: - Filters

@dataclass(frozen=True)
class Decision:
    """The verdict on one message or request."""
    allowed: bool
    kind: str  # "ws" | "http"
    label: str  # message type, or HTTP method
    reason: str = ""
    #: Non-secret facts worth logging for a refusal: only ``domain`` and ``service`` of a ``call_service``.
    detail: Optional[Dict[str, str]] = None


def is_write_type(kind: str) -> bool:
    """Does a message type name a write? ``call_service`` always does; otherwise any ``/``- or ``_``-separated word of it."""
    if kind == "call_service":
        return True
    return any(word in WRITE_WORDS for part in kind.lower().split("/") for word in part.split("_"))


def ws_decide(message: Any, extra_types: Iterable[str] = ()) -> Decision:
    """Judge one decoded WebSocket client message (a dict). ``call_service`` and every unnamed type are refused.

    The ``type`` must equal an allowed string exactly: case, whitespace and control-character variants are refused, and a
    ``type`` nested deeper in the message is never looked at (the message is re-serialised, so the server reads the same
    top-level ``type`` that was judged).
    """
    if not isinstance(message, dict):
        return Decision(False, "ws", "<non-object>", "message is not a JSON object")
    kind = message.get("type")
    if not isinstance(kind, str) or not kind:
        return Decision(False, "ws", "<untyped>", "message has no type")
    if kind == "call_service":
        # Which service was tried is the one thing worth keeping; service_data and target are never read here.
        names = {k: message[k][:80] for k in ("domain", "service") if isinstance(message.get(k), str)}
        return Decision(False, "ws", kind, "type is not on the read allow-list", names or None)
    if kind in WS_ALLOWED_TYPES:
        return Decision(True, "ws", kind)
    if kind in set(extra_types) and not is_write_type(kind):
        return Decision(True, "ws", kind)
    return Decision(False, "ws", kind[:80] if kind.isprintable() else "<unprintable>", "type is not on the read allow-list")


_BAD_PATH_CHARS = re.compile(r"[^\x21-\x7e]|[\\%;]")


def clean_path(path: str) -> Optional[str]:
    """Why a request path is refused before the allow-list looks at it, or ``None`` when it is plain.

    The query string and fragment are ignored. A path must be absolute, printable ASCII, hold no percent-encoding (it is never
    decoded, so ``%2e%2e`` cannot smuggle a traversal), backslash or ``;`` parameter, no empty segment and no ``.`` or ``..``.
    """
    bare = path.split("?", 1)[0].split("#", 1)[0]
    if not bare.startswith("/"):
        return "path is not absolute"
    if _BAD_PATH_CHARS.search(bare):
        return "path has encoded, control or non-ASCII characters"
    segments = bare.split("/")[1:]
    if any(s in ("", ".", "..") for s in segments[:-1]) or (segments and segments[-1] in (".", "..")):
        return "path has an empty or dot segment"
    return None


def http_decide(method: str, path: str, extra_prefixes: Iterable[str] = ()) -> Decision:
    """Judge one HTTP request line: only ``GET`` (exactly) to a clean, allow-listed path passes. The query string is ignored."""
    if method != "GET":
        return Decision(False, "http", method.upper()[:12] if method.isalpha() else "<method>", "only GET is allowed")
    reason = clean_path(path)
    if reason:
        return Decision(False, "http", "GET", reason)
    bare = path.split("?", 1)[0].split("#", 1)[0]
    if any(_under(bare, p) for p in HTTP_NEVER_PREFIXES):
        return Decision(False, "http", "GET", "path is never allowed")
    if bare in HTTP_EXACT_PATHS or bare.startswith(HTTP_STARTSWITH) or any(
            _under(bare, p) for p in tuple(HTTP_ALLOWED_PREFIXES) + tuple(extra_prefixes)):
        return Decision(True, "http", "GET")
    return Decision(False, "http", "GET", "path is not on the read allow-list")


def _under(path: str, prefix: str) -> bool:
    prefix = prefix.rstrip("/")
    return path == prefix or path.startswith(prefix + "/")


_WORD = re.compile(r"[a-z][a-z_]{0,31}$")
#: Third segments that name a kind of read, never an id: ``(first two segments) -> words``.
_KNOWN_THIRD = {("api", "fenton_home"): {"ui_assets", "config"}, ("api", "image"): {"serve"}}


def path_template(path: str) -> str:
    """A loggable form of a path: the first two lowercase words and a known third, everything after as ``*``.

    ``/api/hls/<stream token>/playlist.m3u8`` becomes ``/api/hls/*`` and ``/api/webhook/<id>`` becomes ``/api/webhook/*``.
    A query string or fragment is dropped. Ids, tokens and signed paths never survive.
    """
    segments = [s for s in path.split("?", 1)[0].split("#", 1)[0].split("/") if s]
    out: List[str] = []
    for index, segment in enumerate(segments):
        if index < 2 and _WORD.match(segment):
            out.append(segment)
        elif index == 2 and tuple(out) in _KNOWN_THIRD and segment in _KNOWN_THIRD[tuple(out)]:
            out.append(segment)
        else:
            out.append("*")
            break
    return "/" + "/".join(out)


#: What counts of allowed reads are keyed by (the same template form as the logs).
http_bucket = path_template


def filter_ws_payload(text: str, extra_types: Iterable[str] = ()) -> Tuple[Optional[str], List[Tuple[Decision, Any]]]:
    """Split one text frame into what to forward and the refused messages with their ids.

    Returns ``(forward_text_or_None, [(decision, message_id), ...for every refused message])``. A JSON array (coalesced
    messages) is judged element by element; unparseable text is refused whole. What is forwarded is re-serialised.
    """
    try:
        value = json.loads(text)
    except (ValueError, RecursionError):
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


def allowed_labels(forward_text: str) -> List[str]:
    """The message types in a forwarded frame, for the allowed-traffic counts (types only)."""
    value = json.loads(forward_text)
    return [str(m.get("type")) for m in (value if isinstance(value, list) else [value]) if isinstance(m, dict)]


def refusal_frame_text(message_id: Any) -> str:
    """The ``result`` error sent to the client in place of a refused message."""
    body: Dict[str, Any] = {"type": "result", "success": False,
                            "error": {"code": READ_ONLY_CODE, "message": "refused by the parity-loop write guard"}}
    if isinstance(message_id, int) and not isinstance(message_id, bool):
        body["id"] = message_id
    return json.dumps(body, separators=(",", ":"))


# MARK: - Logs

_ROW_KEYS = ("time", "kind", "label", "path", "reason", "domain", "service")


class RejectionLog:
    """An append-only JSONL log of refusals plus running counts of what passed.

    A refusal row holds the kind, type or method, a path *template* (never a query string, id or token), the reason and, for a
    refused ``call_service``, its ``domain`` and ``service``; every row also passes through ``tools/redact.py``. Allowed traffic
    is only counted, by type and template (``allowed-summary.json``, written beside the log). No bodies, headers, service data,
    targets or tokens are ever recorded.
    """

    def __init__(self, path: Optional[Path], summary_path: Optional[Path] = None) -> None:
        self.path = Path(path) if path else None
        self.summary_path = Path(summary_path) if summary_path else (self.path.with_name("allowed-summary.json") if self.path else None)
        self.counts: Dict[str, int] = {}
        self.allowed: Dict[str, Dict[str, int]] = {"ws": {}, "http": {}}
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)

    def record(self, decision: Decision, path: str = "") -> None:
        key = f"{decision.kind}:{decision.label}"
        self.counts[key] = self.counts.get(key, 0) + 1
        if self.path is None:
            return
        row: Dict[str, Any] = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "kind": decision.kind,
                               "label": decision.label, "path": path_template(path), "reason": decision.reason}
        if decision.detail:
            row.update(decision.detail)
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(redact_json(row)) + "\n")

    def record_allowed(self, kind: str, label: str) -> None:
        """Count one forwarded message type (``ws``) or one read path template (``http``) and rewrite the summary file."""
        bucket = self.allowed.setdefault(kind, {})
        bucket[label] = bucket.get(label, 0) + 1
        if self.summary_path:
            self.summary_path.parent.mkdir(parents=True, exist_ok=True)
            self.summary_path.write_text(json.dumps(self.allowed, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def scrub_file(path: Path) -> int:
    """Rewrite one proxy log in place to the template form; returns the rows (or summary keys) that changed.

    A ``.jsonl`` rejection log keeps only the known row keys with each ``path`` turned into its template. An
    ``allowed-summary.json`` has its ``http`` keys templated and merged. Anything else is refused with ``ValueError``.
    """
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    changed = 0
    if path.suffix == ".jsonl":
        rows: List[str] = []
        for line in text.splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            clean = {k: row[k] for k in _ROW_KEYS if k in row}
            if "path" in clean:
                clean["path"] = path_template(str(clean["path"]))
            changed += clean != row
            rows.append(json.dumps(redact_json(clean)))
        out = "\n".join(rows) + ("\n" if rows else "")
    elif path.name.endswith("summary.json"):
        data = json.loads(text)
        http: Dict[str, int] = {}
        for key, count in (data.get("http") or {}).items():
            http[path_template(key)] = http.get(path_template(key), 0) + int(count)
        changed = int(http != (data.get("http") or {}))
        data["http"] = http
        out = json.dumps(data, indent=2, sort_keys=True) + "\n"
    else:
        raise ValueError(f"not a proxy log: {path.name}")
    temp = path.with_name(path.name + ".scrubbing")
    temp.write_text(out, encoding="utf-8")
    os.replace(temp, path)
    return changed


# MARK: - WebSocket frames

class ProtocolError(Exception):
    """A frame that breaks RFC 6455 (or our rules); the connection is closed."""


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


async def read_frame(reader: asyncio.StreamReader, *, from_client: bool = False) -> Tuple[bool, int, bytes]:
    """``(fin, opcode, unmasked payload)`` of the next frame; raises ``IncompleteReadError`` at end of stream.

    ``from_client`` applies the strict rules for frames the proxy will judge: reserved bits clear, the frame masked, a known
    opcode, and a control frame short and unfragmented. A violation raises :class:`ProtocolError`.
    """
    first, second = await reader.readexactly(2)
    opcode, n = first & 0x0F, second & 0x7F
    if from_client:
        if first & 0x70:
            raise ProtocolError("reserved bits set")
        if not second & 0x80:
            raise ProtocolError("client frame is not masked")
        if opcode in (3, 4, 5, 6, 7) or opcode > 10:
            raise ProtocolError("reserved opcode")
        if opcode >= 8 and (not first & 0x80 or n > 125):
            raise ProtocolError("bad control frame")
    if n == 126:
        n = int.from_bytes(await reader.readexactly(2), "big")
    elif n == 127:
        n = int.from_bytes(await reader.readexactly(8), "big")
    if n > MAX_FRAME or (from_client and n > MAX_CLIENT_MESSAGE):
        raise ProtocolError("frame too large")
    key = await reader.readexactly(4) if second & 0x80 else b""
    data = await reader.readexactly(n)
    if key:
        data = bytes(b ^ key[i % 4] for i, b in enumerate(data))
    return bool(first & 0x80), opcode, data


def accept_key(client_key: str) -> str:
    return base64.b64encode(hashlib.sha1(client_key.encode() + WS_GUID).digest()).decode()


class ClientWriter:
    """The one writer toward the client: whole frames only, refusals only between whole server messages.

    Server frames come in through :meth:`server_frame`; refusal replies through :meth:`refusal`. A refusal that arrives while a
    fragmented server message is half sent waits until its final fragment, so the client never sees a data frame spliced into
    another message. Every ``write`` is one complete frame, and ``drain`` is serialised, so frames never interleave.
    """

    def __init__(self, writer: asyncio.StreamWriter) -> None:
        self.writer = writer
        self.mid_message = False
        self.pending: List[bytes] = []
        self.lock = asyncio.Lock()

    async def _drain(self) -> None:
        async with self.lock:
            await self.writer.drain()

    async def server_frame(self, fin: bool, opcode: int, payload: bytes) -> None:
        self.writer.write(encode_frame(opcode, payload, False, fin))
        if opcode < 8:
            self.mid_message = not fin
        if not self.mid_message:
            self._flush()
        await self._drain()

    async def refusal(self, text: str) -> None:
        frame = encode_frame(1, text.encode("utf-8"), False)
        if self.mid_message:
            self.pending.append(frame)
            return
        self.writer.write(frame)
        await self._drain()

    async def close(self, code: int) -> None:
        self.pending.clear()
        self.writer.write(encode_frame(8, code.to_bytes(2, "big"), False))
        await self._drain()

    def _flush(self) -> None:
        for frame in self.pending:
            self.writer.write(frame)
        self.pending.clear()


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
        bad = [t for t in extra_types if is_write_type(t)]
        if bad:
            raise ValueError("a write type cannot be allowed")
        if any(len(p.strip("/")) < 3 for p in extra_paths) or any(_under(p.rstrip("/") + "/x", n) for p in extra_paths
                                                                  for n in HTTP_NEVER_PREFIXES):
            raise ValueError("an allowed path must be specific and not a never-allowed prefix")
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
                    self.log.record(Decision(False, "http", "UPGRADE", "websocket upgrade outside /api/websocket"), target)
                    await self._plain(writer, 403, "refused by the parity-loop write guard")
                else:
                    await self._websocket(reader, writer, target, headers)
            else:
                self.log.record_allowed("http", path_template(target))
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

    @staticmethod
    def forwardable_headers(headers: Dict[str, str]) -> Dict[str, str]:
        """The request headers that may reach the upstream: no hop-by-hop, framing, method-override or forwarding headers."""
        skip = {"host", "connection", "upgrade", "accept-encoding", "content-length", "transfer-encoding", "proxy-connection", "te",
                "expect", "keep-alive", "trailer"}
        return {k: v for k, v in headers.items() if k not in skip and not any(part in k for part in STRIPPED_HEADER_PARTS)}

    async def _forward_http(self, writer: asyncio.StreamWriter, target: str, headers: Dict[str, str]) -> None:
        send = self.forwardable_headers(headers)

        def call() -> Tuple[Any, Any]:
            up = self.upstream
            conn = (http.client.HTTPSConnection(up.host, up.port, timeout=60, context=self._ssl()) if up.tls
                    else http.client.HTTPConnection(up.host, up.port, timeout=60))
            conn.request("GET", target, headers=send)
            return conn, conn.getresponse()

        loop = asyncio.get_running_loop()
        try:
            conn, resp = await loop.run_in_executor(None, call)
        except (OSError, http.client.HTTPException):
            await self._plain(writer, 502, "upstream unreachable")
            return
        try:
            drop = {"transfer-encoding", "connection", "content-encoding"}
            out = [f"HTTP/1.1 {resp.status} OK"] + [f"{k}: {v}" for k, v in resp.getheaders() if k.lower() not in drop]
            out += ["Connection: close", "", ""]
            writer.write("\r\n".join(out).encode("latin-1"))
            # Streamed in chunks, so a camera stream (``/api/camera_proxy_stream``) flows instead of waiting for an end.
            while True:
                chunk = await loop.run_in_executor(None, resp.read1, 65536)
                if not chunk:
                    break
                writer.write(chunk)
                await writer.drain()
        except (OSError, http.client.HTTPException):
            pass
        finally:
            conn.close()

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
        client = ClientWriter(writer)

        async def downstream() -> None:  # server -> client, frame by frame
            while True:
                fin, opcode, payload = await read_frame(ureader)
                await client.server_frame(fin, opcode, payload)
                if opcode == 8:
                    return

        async def judge(text_bytes: bytes) -> None:
            try:
                text = text_bytes.decode("utf-8")  # strict: invalid UTF-8 is refused, never repaired
            except UnicodeDecodeError:
                self.log.record(Decision(False, "ws", "<invalid-utf8>", "frame is not UTF-8"), target)
                await client.refusal(refusal_frame_text(None))
                return
            forward, refused = filter_ws_payload(text, self.extra_types)
            for verdict, message_id in refused:
                self.log.record(verdict, target)
                await client.refusal(refusal_frame_text(message_id))
            if forward is not None:
                for label in allowed_labels(forward):
                    self.log.record_allowed("ws", label)
                uwriter.write(encode_frame(1, forward.encode("utf-8"), True))
                await uwriter.drain()

        async def upstream() -> None:  # client -> server, judged message by message
            buffer, mode = b"", None  # mode: None between messages, "text" or "binary" inside a fragmented one
            while True:
                try:
                    fin, opcode, payload = await read_frame(reader, from_client=True)
                    if opcode >= 8:
                        uwriter.write(encode_frame(opcode, payload, True))
                        await uwriter.drain()
                        if opcode == 8:
                            return
                        continue
                    if opcode == 0 and mode is None:
                        raise ProtocolError("continuation without a message")
                    if opcode in (1, 2) and mode is not None:
                        raise ProtocolError("new message inside a fragmented one")
                    if opcode in (1, 2):
                        mode, buffer = ("text" if opcode == 1 else "binary"), b""
                        if opcode == 2:
                            self.log.record(Decision(False, "ws", "<binary>", "binary frames are not allowed"), target)
                    if mode == "text":
                        buffer += payload
                        if len(buffer) > MAX_CLIENT_MESSAGE:
                            raise ProtocolError("message too large")
                    if fin:
                        done, data, mode, buffer = mode, buffer, None, b""
                        if done == "text":
                            await judge(data)
                except ProtocolError as error:
                    self.log.record(Decision(False, "ws", "<protocol>", str(error)), target)
                    await client.close(1002)
                    return

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
    args_in = list(sys.argv[1:] if argv is None else argv)
    if args_in[:1] == ["scrub"]:
        if len(args_in) < 2:
            print("guard_proxy scrub: give at least one log file", file=sys.stderr)
            return 2
        try:
            for name in args_in[1:]:
                print(f"{name}: {scrub_file(Path(name))} row(s) rewritten")
        except (OSError, ValueError) as error:
            print(f"guard_proxy scrub: {error}", file=sys.stderr)
            return 2
        return 0
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--listen", default="127.0.0.1:0", help="HOST:PORT to listen on (port 0 picks one; it is printed)")
    ap.add_argument("--upstream", help="upstream URL (default: the environment variable named by --upstream-env)")
    ap.add_argument("--upstream-env", default="FENTON_HASS_SERVER")
    ap.add_argument("--log", type=Path, help="rejection log (JSONL)")
    ap.add_argument("--certfile")
    ap.add_argument("--keyfile")
    ap.add_argument("--allow-type", action="append", default=[], help="widen the WebSocket allow-list with one read type (never a write)")
    ap.add_argument("--allow-path", action="append", default=[], help="widen the HTTP allow-list with one GET path prefix")
    args = ap.parse_args(args_in)
    url = args.upstream or os.environ.get(args.upstream_env, "")
    if not url:
        print(f"guard_proxy: no upstream (set {args.upstream_env} or pass --upstream)", file=sys.stderr)
        return 2
    host, _, port = args.listen.rpartition(":")
    try:
        proxy = GuardProxy(Upstream.parse(url), RejectionLog(args.log), args.allow_type, args.allow_path)
    except ValueError as error:
        print(f"guard_proxy: {error}", file=sys.stderr)
        return 2

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
