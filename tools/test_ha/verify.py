#!/usr/bin/env python3
"""verify: read back that the test Home Assistant serves every DemoHouse id with a state, and the house document.

    FENTON_TEST_HA_URL=https://... FENTON_TEST_HA_TOKEN=... python3 tools/test_ha/verify.py [--export build/ha/demo-house.json]
    python3 tools/test_ha/verify.py --states states.json      # offline: a saved ``get_states`` result

Live mode signs in over the websocket with the test instance's own token (``FENTON_TEST_HA_TOKEN``, a long-lived token of the
CI or admin user of the *test* instance, never the house's ``FENTON_HASS_*``), sends ``get_states`` and
``fenton_home/house_config``, and checks:

  1. every entity id in the export exists and has a non-empty state (``unavailable`` counts as a failure);
  2. the count of demo ids found equals the export's;
  3. the served house document equals the export's document (live mode only).

The token is read from the environment, never printed or put in an error. Exit code: 0 all present, 1 anything missing. Stdlib only.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import socket
import ssl
import struct
import sys
import urllib.parse
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

ROOT = Path(__file__).resolve().parents[2]


# MARK: - The checks (pure, tested with a fake states list)

def expected_ids(export: Dict[str, Any]) -> List[str]:
    """The entity ids the export names, sorted."""
    return sorted(e["entity_id"] for e in export["entities"])


def check_states(ids: Sequence[str], states: Sequence[Dict[str, Any]]) -> List[str]:
    """Problems found reading ``states`` (the ``get_states`` result) against the expected ids; empty means all present."""
    by_id = {s.get("entity_id"): s for s in states if isinstance(s, dict)}
    problems: List[str] = []
    for entity_id in ids:
        entry = by_id.get(entity_id)
        if entry is None:
            problems.append(f"missing: {entity_id}")
        elif entry.get("state") in (None, "unavailable") or (entry.get("state") == "" and not entity_id.startswith("input_text.")):
            # an input_text with no initial value legitimately reads '' (empty text), so only it may be empty
            problems.append(f"no usable state ({entry.get('state')!r}): {entity_id}")
    found = sum(1 for i in ids if i in by_id)
    if found != len(ids):
        problems.append(f"count: found {found} of {len(ids)} demo ids")
    return problems


def check_house(served: Any, document: Dict[str, Any]) -> List[str]:
    """Problems comparing the document the instance serves with the export's (``[]`` when equal)."""
    if isinstance(served, dict) and isinstance(served.get("config"), dict):
        # the websocket result wraps the document and lifts ``schema`` out of it (Core 2026.11, fenton_home 1.3.0)
        wrapper = served
        served = dict(served["config"])
        if "schema" in document and "schema" not in served and "schema" in wrapper:
            served["schema"] = wrapper["schema"]
    if served != document:
        return ["fenton_home/house_config does not return the export's document"]
    return []


# MARK: - A small websocket client (live mode)

def frame(payload: bytes, opcode: int = 1) -> bytes:
    """A masked client text frame."""
    mask = os.urandom(4)
    head = bytes([0x80 | opcode])
    n = len(payload)
    if n < 126:
        head += bytes([0x80 | n])
    elif n < 65536:
        head += bytes([0x80 | 126]) + struct.pack(">H", n)
    else:
        head += bytes([0x80 | 127]) + struct.pack(">Q", n)
    return head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload))


def read_exact(sock: Any, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("websocket closed")
        buf += chunk
    return buf


def read_message(sock: Any) -> str:
    """The next complete text message (fragments joined; ping answered with pong)."""
    parts = b""
    while True:
        b1, b2 = read_exact(sock, 2)
        opcode, fin, n = b1 & 0x0F, b1 & 0x80, b2 & 0x7F
        if n == 126:
            n = struct.unpack(">H", read_exact(sock, 2))[0]
        elif n == 127:
            n = struct.unpack(">Q", read_exact(sock, 8))[0]
        data = read_exact(sock, n)
        if opcode == 9:
            sock.sendall(frame(data, 10))
        elif opcode == 8:
            raise ConnectionError("websocket closed by the server")
        elif opcode in (0, 1, 2):
            parts += data
            if fin:
                return parts.decode()


def connect(url: str) -> Any:
    """An open websocket to ``<url>/api/websocket`` (http becomes ws, https wss)."""
    u = urllib.parse.urlparse(url)
    tls = u.scheme in ("https", "wss")
    host, port = u.hostname or "", u.port or (443 if tls else 80)
    sock: Any = socket.create_connection((host, port), timeout=30)
    if tls:
        sock = ssl.create_default_context().wrap_socket(sock, server_hostname=host)
    key = base64.b64encode(os.urandom(16)).decode()
    path = (u.path.rstrip("/") or "") + "/api/websocket"
    sock.sendall((f"GET {path} HTTP/1.1\r\nHost: {u.netloc}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += read_exact(sock, 1)
    lines = resp.decode(errors="replace").split("\r\n")
    accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    if " 101 " not in lines[0] or accept not in resp.decode(errors="replace"):
        raise ConnectionError(f"websocket upgrade refused: {lines[0]}")
    return sock


def call(sock: Any, msg_id: int, payload: Dict[str, Any]) -> Any:
    """Send one command and return its result (raises on ``success: false``)."""
    sock.sendall(frame(json.dumps(dict(payload, id=msg_id)).encode()))
    while True:
        reply = json.loads(read_message(sock))
        if reply.get("id") == msg_id:
            if not reply.get("success"):
                raise ConnectionError(f"{payload['type']} failed: {(reply.get('error') or {}).get('code', 'error')}")
            return reply.get("result")


def live(url: str, token: str) -> Dict[str, Any]:
    """``{"states": [...], "house": ...}`` read from the instance."""
    sock = connect(url)
    try:
        if json.loads(read_message(sock)).get("type") != "auth_required":
            raise ConnectionError("unexpected greeting")
        sock.sendall(frame(json.dumps({"type": "auth", "access_token": token}).encode()))
        if json.loads(read_message(sock)).get("type") != "auth_ok":
            raise ConnectionError("sign-in refused (check FENTON_TEST_HA_TOKEN)")
        states = call(sock, 1, {"type": "get_states"})
        try:
            house = call(sock, 2, {"type": "fenton_home/house_config"})
        except ConnectionError:
            house = None
        return {"states": states, "house": house}
    finally:
        sock.close()


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--export", default=str(ROOT / "build/ha/demo-house.json"))
    ap.add_argument("--states", help="a saved get_states JSON list (offline mode: the house document is not checked)")
    args = ap.parse_args(argv)
    try:
        export = json.loads(Path(args.export).read_text())
        ids = expected_ids(export)
        if args.states:
            states, house = json.loads(Path(args.states).read_text()), None
        else:
            url, token = os.environ.get("FENTON_TEST_HA_URL", ""), os.environ.get("FENTON_TEST_HA_TOKEN", "")
            if not url or not token:
                print("verify: set FENTON_TEST_HA_URL and FENTON_TEST_HA_TOKEN (the test instance's, not the house's)", file=sys.stderr)
                return 1
            got = live(url, token)
            states, house = got["states"], got["house"]
    except (OSError, ValueError, KeyError, ConnectionError, ssl.SSLError) as exc:
        print(f"verify: {type(exc).__name__}: {str(exc)[:200]}", file=sys.stderr)
        return 1
    problems = check_states(ids, states)
    if not args.states:
        problems += check_house(house, export["document"]) if house is not None else ["fenton_home/house_config is not available"]
    for line in problems:
        print(line)
    print(f"verify: {len(ids) - sum(1 for p in problems if p.startswith(('missing', 'no usable')))} of {len(ids)} ids present"
          f"{'' if not problems else ', ' + str(len(problems)) + ' problem(s)'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
