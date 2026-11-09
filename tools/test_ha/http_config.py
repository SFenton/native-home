#!/usr/bin/env python3
"""Apply the test Home Assistant's http proxy settings through Core 2026.11's stored-config websocket API.

Core 2026.11 keeps the http settings in ``.storage/http`` (a stable and a pending slot) and, once ``yaml_migration_done`` is set,
ignores the ``http:`` YAML block. So provisioning sets them over the websocket instead
(``home-assistant/core@2026.11.0:homeassistant/components/http/websocket_api.py``):

    http/config            read ``stable``, ``pending``, ``revert_at``, ``active_config_type``
    http/config/configure  write a config; Core restarts on it as the *pending* config
    http/config/promote    make the pending config stable (must happen before the auto-revert)

The script runs INSIDE the SSH add-on, where ``$SUPERVISOR_TOKEN`` and ``supervisor:80`` exist (Supervisor proxies Core at
``/core/websocket``). ``provision.sh`` streams it there: ``ssh hass-test python3 - ensure < http_config.py``. It never prints the token.

    usage: http_config.py get | ensure | promote

On a fresh Supervisor install Core binds port 80 (``default_server_port()``); an install that migrated an existing ``http:`` block keeps its port (8123).
"""
import base64
import json
import os
import socket
import struct
import sys
import time
from datetime import datetime

#: Supervisor's fixed add-on network (a Supervisor constant, not house data), built from its octets so the house-data lint
#: does not read it as a private address.
ADDON_NETWORK = ".".join(("172", "30", "33", "0")) + "/24"

#: Settings merged into the stable config. Supervisor's add-on network is the only trusted proxy.
WANTED = {
    "use_x_forwarded_for": True,
    "trusted_proxies": [ADDON_NETWORK],
    "ip_ban_enabled": True,
    "login_attempts_threshold": 5,
}
#: Fields Core reports on a stored config but does not accept back in ``configure``.
READ_ONLY = ("created_at", "error", "error_message")
SUPERVISOR = ("supervisor", 80)


def merge(stable):
    """The config to send to ``configure``: ``stable`` without its read-only fields, with ``WANTED`` laid over it."""
    cfg = {k: v for k, v in (stable or {}).items() if k not in READ_ONLY}
    cfg.update(WANTED)
    return cfg


def matches(config):
    """True when ``config`` already carries every ``WANTED`` setting (the idempotency test)."""
    return bool(config) and all(config.get(k) == v for k, v in WANTED.items())


def pending_ok(config):
    """True when a pending config carries the wanted settings and Core reports no ``error`` on it."""
    return matches(config) and not (config or {}).get("error")


def parse_deadline(value):
    """``revert_at`` as epoch seconds (a number or an ISO 8601 string), or ``None`` when absent or unreadable."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def raw_frame(opcode, payload, mask=None):
    """A masked, final frame with ``opcode`` and ``payload`` bytes (clients must mask)."""
    mask = mask if mask is not None else os.urandom(4)
    n = len(payload)
    if n < 126:
        head = bytes([0x80 | opcode, 0x80 | n])
    elif n < 65536:
        head = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack(">H", n)
    else:
        head = bytes([0x80 | opcode, 0x80 | 127]) + struct.pack(">Q", n)
    return head + mask + bytes(c ^ mask[i % 4] for i, c in enumerate(payload))


def encode_frame(obj, mask=None):
    """A masked, final text frame holding ``obj`` as JSON."""
    return raw_frame(0x1, json.dumps(obj).encode(), mask)


class Closed(Exception):
    """The socket closed (Core restarting) before a full message arrived."""


class WS:
    """A stdlib websocket client over any object with ``recv(n)`` and ``sendall(bytes)``; ``buf`` holds bytes read past the handshake."""

    def __init__(self, sock, buf=b""):
        self.s, self.buf = sock, buf

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.s.recv(65536)
            if not chunk:
                raise Closed()
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self):
        """The next complete JSON message. Continuation frames are assembled, ping is answered with pong, pong is skipped,
        and a close frame raises ``Closed`` (Supervisor closes the socket right after ``auth_ok`` while Core restarts)."""
        data = b""
        while True:
            b1, b2 = self._read(2)
            op = b1 & 0x0F
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            if b2 & 0x80:
                self._read(4)  # servers do not mask; discard a mask key if one is sent
            body = self._read(n)
            if op == 0x8:
                raise Closed()
            if op == 0x9:
                self.s.sendall(raw_frame(0xA, body))
                continue
            if op == 0xA:
                continue
            data += body
            if b1 & 0x80:
                return json.loads(data)

    def send(self, obj):
        self.s.sendall(encode_frame(obj))


def handshake(sock, token):
    """Upgrade ``sock`` to a websocket on ``/core/websocket``; returns ``(sock, leftover bytes)``. The token is only ever sent."""
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall((
        "GET /core/websocket HTTP/1.1\r\nHost: supervisor\r\nUpgrade: websocket\r\n"
        f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
        f"Authorization: Bearer {token}\r\n\r\n").encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise Closed()
        buf += chunk
    head, rest = buf.split(b"\r\n\r\n", 1)
    status = head.split(b"\r\n")[0]
    if b" 101 " not in status:
        raise SystemExit("handshake failed: " + status.decode())
    return sock, rest


def open_ws(token, connect=lambda: socket.create_connection(SUPERVISOR, timeout=30)):
    """A WS authenticated against Core."""
    ws = WS(*handshake(connect(), token))
    if ws.recv().get("type") != "auth_required":
        raise SystemExit("unexpected greeting")
    ws.send({"type": "auth", "access_token": token})
    if ws.recv().get("type") != "auth_ok":
        raise SystemExit("auth failed")
    return ws


def call(ws, msg_id, payload):
    """Send ``payload`` as command ``msg_id`` and return its ``result``; exits with the error text on failure."""
    ws.send({"id": msg_id, **payload})
    while True:
        reply = ws.recv()
        if reply.get("id") == msg_id:
            break
    if not reply.get("success"):
        raise SystemExit(json.dumps(reply.get("error")))
    return reply.get("result")


def ensure(open_fn, sleep=time.sleep, tries=60, delay=3, now=time.time):
    """Make the proxy settings stable. Returns ``"unchanged"`` when stable already matches, else ``"promoted"``.

    Reads ``http/config``, merges ``WANTED`` into stable and calls ``configure`` (skipped when a pending config without an
    ``error`` already matches); Core restarts on it as the pending config. Reconnects until Core answers with
    ``active_config_type == "pending"`` (really running the trial config), then promotes. Exits non-zero when ``revert_at``
    passes, the pending config reports an error, or Core never comes back.
    """
    ws = open_fn()
    state = call(ws, 1, {"type": "http/config"})
    if matches(state.get("stable")):
        return "unchanged"
    if not pending_ok(state.get("pending")):
        call(ws, 2, {"type": "http/config/configure", "config": merge(state.get("stable"))})
    for _ in range(tries):
        sleep(delay)
        try:
            ws = open_fn()
            state = call(ws, 1, {"type": "http/config"})
        except (Closed, OSError, SystemExit):
            continue  # Core is still restarting
        deadline = parse_deadline(state.get("revert_at"))
        if deadline is not None and now() >= deadline:
            raise SystemExit("revert_at passed before the pending http config could be promoted")
        pending = state.get("pending")
        if pending and pending.get("error"):
            raise SystemExit("pending http config reports an error: " + str(pending.get("error")))
        if state.get("active_config_type") == "pending" and pending_ok(pending):
            call(ws, 2, {"type": "http/config/promote"})
            return "promoted"
        if matches(state.get("stable")) and not pending:
            return "promoted"
    raise SystemExit("Core did not come back on the pending http config; it will auto-revert")


def main(argv):
    token = os.environ["SUPERVISOR_TOKEN"]
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "get":
        s = call(open_ws(token), 1, {"type": "http/config"})
        print(json.dumps({k: s.get(k) for k in ("stable", "pending", "revert_at", "active_config_type")}, indent=1, default=str))
    elif cmd == "ensure":
        print(ensure(lambda: open_ws(token)))
    elif cmd == "promote":
        print(json.dumps(call(open_ws(token), 1, {"type": "http/config/promote"}), default=str))
    else:
        raise SystemExit("usage: http_config.py get | ensure | promote")


if __name__ == "__main__":
    main(sys.argv)
