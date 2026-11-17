#!/usr/bin/env python3
"""Which Home Assistant user the session's token resolves to, as a hash, through the guard proxy.

    identity.py --proxy https://127.0.0.1:PORT [--chain PROXY_CHAIN]     (the token is read from FENTON_HASS_TOKEN)

Runs as a child of ``launch.py`` (see :func:`parity_loop.launch.identity_script`), which loads the token from ``tools/hass_creds.sh``.
It authenticates over the proxy's websocket, sends ``auth/current_user`` (a read the proxy allows) and prints one line: the
sha256 of the user's id. The name, the admin flag and every other field of the reply are dropped here, never printed or written;
the token is never printed. The hash lets a sidecar say whether two shots were taken as the same user (avatar, admin and chores
differences follow the user) without recording who that is.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import json
import os
import ssl
import sys
from pathlib import Path
from typing import Any, Dict, Optional
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from parity_loop import guard_proxy  # noqa: E402
from parity_loop.stage import Pinned, StageError, client_context  # noqa: E402


class IdentityError(Exception):
    """The user could not be resolved; the message names the step and carries no token, name or address."""


def user_id_hash(user_id: str) -> str:
    """The sidecar's form of a user id: the sha256 hex digest of the id text."""
    return hashlib.sha256(user_id.encode("utf-8")).hexdigest()


async def current_user_hash(host: str, port: int, token: str, context: Optional[Pinned] = None, timeout: float = 20.0) -> str:
    """Authenticate through the proxy, ask ``auth/current_user`` and return the hash of the id in the reply."""
    async def go() -> str:
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
                raise IdentityError("the proxy refused the websocket upgrade")

            async def receive() -> Dict[str, Any]:
                while True:
                    _, opcode, payload = await guard_proxy.read_frame(reader)
                    if opcode == 8:
                        raise IdentityError("the connection closed early")
                    if opcode == 1:
                        value = json.loads(payload)
                        return value if isinstance(value, dict) else {}

            async def send(message: Dict[str, Any]) -> None:
                writer.write(guard_proxy.encode_frame(1, json.dumps(message).encode(), True))
                await writer.drain()

            if (await receive()).get("type") != "auth_required":
                raise IdentityError("unexpected greeting from the server")
            await send({"type": "auth", "access_token": token})
            if (await receive()).get("type") != "auth_ok":
                raise IdentityError("the server did not accept the token")
            await send({"id": 1, "type": "auth/current_user"})
            while True:
                message = await receive()
                if message.get("id") == 1 and message.get("type") == "result":
                    result = message.get("result")
                    user = result.get("id") if message.get("success") and isinstance(result, dict) else None
                    if not isinstance(user, str) or not user:
                        raise IdentityError("the server did not name the user")
                    writer.write(guard_proxy.encode_frame(8, b"", True))
                    return user_id_hash(user)
        finally:
            writer.close()

    try:
        return await asyncio.wait_for(go(), timeout)
    except asyncio.TimeoutError:
        raise IdentityError("timed out resolving the user") from None
    except (OSError, asyncio.IncompleteReadError, ValueError) as error:
        raise IdentityError(f"user lookup failed ({type(error).__name__})") from None


def main(argv: Optional[list] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--proxy", required=True, help="guard proxy URL (https://127.0.0.1:PORT)")
    ap.add_argument("--chain", type=Path, help="the proxy's certificate chain file (its leaf is pinned)")
    args = ap.parse_args(argv)
    token = os.environ.get("FENTON_HASS_TOKEN", "")
    if not token:
        print("identity: the token is not set", file=sys.stderr)
        return 2
    parts = urlsplit(args.proxy)
    try:
        digest = asyncio.run(current_user_hash(parts.hostname or "127.0.0.1", parts.port or (443 if parts.scheme == "https" else 80),
                                               token, client_context(parts.scheme, args.chain)))
    except (IdentityError, StageError, OSError, ValueError) as error:
        print(f"identity: {error if isinstance(error, (IdentityError, StageError)) else type(error).__name__}", file=sys.stderr)
        return 1
    print(digest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
