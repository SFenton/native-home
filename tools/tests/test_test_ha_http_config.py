"""Tests for tools/test_ha/http_config.py: the settings merge, idempotency, websocket framing against a fake socket, and the flow."""
from __future__ import annotations

import json
import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "test_ha"))
import http_config as hc  # noqa: E402


def _one(fin, op, body):
    n = len(body)
    head = bytes([(0x80 if fin else 0) | op])
    if n < 126:
        head += bytes([n])
    elif n < 65536:
        head += bytes([126]) + struct.pack(">H", n)
    else:
        head += bytes([127]) + struct.pack(">Q", n)
    return head + body


def server_frame(obj, split=False):
    """An unmasked server text frame (optionally fragmented in two)."""
    p = json.dumps(obj).encode()
    if split:
        return _one(False, 1, p[:5]) + _one(True, 0, p[5:])
    return _one(True, 1, p)


def unmask(frame):
    n = frame[1] & 0x7F
    off = 2
    if n == 126:
        n, off = struct.unpack(">H", frame[2:4])[0], 4
    elif n == 127:
        n, off = struct.unpack(">Q", frame[2:10])[0], 10
    mask = frame[off:off + 4]
    body = frame[off + 4:off + 4 + n]
    return json.loads(bytes(c ^ mask[i % 4] for i, c in enumerate(body)))


class FakeSocket:
    def __init__(self, incoming=b"", chunk=3):
        self.incoming, self.sent, self.chunk = incoming, [], chunk

    def recv(self, n):
        k = min(n, self.chunk)
        out, self.incoming = self.incoming[:k], self.incoming[k:]
        return out

    def sendall(self, data):
        self.sent.append(data)


class MergeTests(unittest.TestCase):
    def test_merge_adds_wanted_and_drops_read_only(self):
        stable = {"server_port": 80, "ip_ban_enabled": False, "created_at": "x", "error": None, "error_message": "m"}
        cfg = hc.merge(stable)
        self.assertEqual(cfg["server_port"], 80)
        for k in ("created_at", "error", "error_message"):
            self.assertNotIn(k, cfg)
        for k, v in hc.WANTED.items():
            self.assertEqual(cfg[k], v)

    def test_merge_of_nothing_is_wanted(self):
        self.assertEqual(hc.merge(None), hc.WANTED)

    def test_matches(self):
        self.assertTrue(hc.matches(dict(hc.WANTED, server_port=80)))
        self.assertFalse(hc.matches({}))
        self.assertFalse(hc.matches(None))
        self.assertFalse(hc.matches(dict(hc.WANTED, login_attempts_threshold=10)))


class FramingTests(unittest.TestCase):
    def test_client_frames_are_masked_and_round_trip(self):
        for size in (10, 200, 70000):
            obj = {"id": 1, "pad": "a" * size}
            frame = hc.encode_frame(obj, mask=b"\x01\x02\x03\x04")
            self.assertEqual(frame[0], 0x81)
            self.assertTrue(frame[1] & 0x80)
            self.assertEqual(unmask(frame), obj)

    def test_recv_handles_sizes_and_fragments(self):
        for obj, split in (({"a": 1}, False), ({"a": "b" * 300}, False), ({"a": "b" * 70000}, False), ({"a": 1, "b": 2}, True)):
            self.assertEqual(hc.WS(FakeSocket(server_frame(obj, split))).recv(), obj)

    def test_close_frame_raises_closed(self):
        with self.assertRaises(hc.Closed):
            hc.WS(FakeSocket(_one(True, 8, b"\x03\xe8"))).recv()

    def test_auth_ok_followed_by_close(self):
        sock = FakeSocket(server_frame({"type": "auth_ok"}) + _one(True, 8, b""))
        ws = hc.WS(sock)
        self.assertEqual(ws.recv(), {"type": "auth_ok"})
        with self.assertRaises(hc.Closed):
            ws.recv()

    def test_ping_is_answered_with_pong_and_pong_is_skipped(self):
        sock = FakeSocket(_one(True, 9, b"hi") + _one(True, 10, b"x") + server_frame({"a": 1}))
        self.assertEqual(hc.WS(sock).recv(), {"a": 1})
        self.assertEqual(len(sock.sent), 1)
        self.assertEqual(sock.sent[0][0], 0x8A)
        self.assertEqual(bytes(c ^ sock.sent[0][2 + i % 4] for i, c in enumerate(sock.sent[0][6:])), b"hi")

    def test_continuation_with_interleaved_ping(self):
        p = json.dumps({"k": "v" * 20}).encode()
        data = _one(False, 1, p[:7]) + _one(True, 9, b"") + _one(False, 0, p[7:12]) + _one(True, 0, p[12:])
        sock = FakeSocket(data)
        self.assertEqual(hc.WS(sock).recv(), {"k": "v" * 20})
        self.assertEqual(len(sock.sent), 1)

    def test_recv_uses_leftover_handshake_bytes(self):
        self.assertEqual(hc.WS(FakeSocket(), buf=server_frame({"x": 1})).recv(), {"x": 1})

    def test_closed_socket_raises(self):
        with self.assertRaises(hc.Closed):
            hc.WS(FakeSocket(b"\x81")).recv()

    def test_handshake_sends_token_and_returns_leftover(self):
        sock = FakeSocket(b"HTTP/1.1 101 Switching Protocols\r\nX: y\r\n\r\nrest", chunk=4096)
        _, rest = hc.handshake(sock, "SECRET")
        self.assertEqual(rest, b"rest")
        req = sock.sent[0].decode()
        self.assertIn("GET /core/websocket", req)
        self.assertIn("Authorization: Bearer SECRET", req)

    def test_handshake_refusal_does_not_echo_token(self):
        with self.assertRaises(SystemExit) as cm:
            hc.handshake(FakeSocket(b"HTTP/1.1 401 Unauthorized\r\n\r\n"), "SECRET")
        self.assertNotIn("SECRET", str(cm.exception))

    def test_open_ws_authenticates(self):
        data = b"HTTP/1.1 101 Switching Protocols\r\n\r\n" + server_frame({"type": "auth_required"}) + server_frame({"type": "auth_ok"})
        sock = FakeSocket(data)
        self.assertIsInstance(hc.open_ws("SECRET", connect=lambda: sock), hc.WS)
        self.assertEqual(unmask(sock.sent[1]), {"type": "auth", "access_token": "SECRET"})

    def test_open_ws_rejects_bad_auth(self):
        data = b"HTTP/1.1 101 x\r\n\r\n" + server_frame({"type": "auth_required"}) + server_frame({"type": "auth_invalid"})
        with self.assertRaises(SystemExit):
            hc.open_ws("t", connect=lambda: FakeSocket(data))


class FakeCore:
    """Stands in for ``open_fn``: a Core with stable and pending slots that goes down for a while after configure."""

    def __init__(self, stable, down_for=1):
        self.stable, self.pending, self.sent, self.down, self.down_for = stable, None, [], 0, down_for
        self._last = None
        self.revert_at, self.active = None, "pending"

    def open(self):
        if self.down > 0:
            self.down -= 1
            raise hc.Closed()
        return self

    def send(self, obj):
        self.sent.append(obj)
        self._last = obj

    def recv(self):
        m = self._last
        kind = m["type"]
        if kind == "http/config":
            result = {"stable": self.stable, "pending": self.pending, "revert_at": self.revert_at,
                      "active_config_type": self.active if self.pending else "stable"}
        elif kind == "http/config/configure":
            self.pending, self.down, result = m["config"], self.down_for, None
        else:
            self.stable, self.pending, result = self.pending, None, None
        return {"id": m["id"], "success": True, "result": result}


class EnsureTests(unittest.TestCase):
    def test_does_not_promote_until_pending_is_active(self):
        core = FakeCore({"server_port": 80}, down_for=0)
        core.active = "stable"
        with self.assertRaises(SystemExit):
            hc.ensure(core.open, sleep=lambda s: None, tries=3)
        self.assertNotIn("http/config/promote", [m["type"] for m in core.sent])

    def test_exits_when_revert_at_has_passed(self):
        core = FakeCore({"server_port": 80}, down_for=0)
        core.revert_at = 100.0
        with self.assertRaises(SystemExit) as cm:
            hc.ensure(core.open, sleep=lambda s: None, now=lambda: 200.0)
        self.assertIn("revert_at", str(cm.exception))
        self.assertNotIn("http/config/promote", [m["type"] for m in core.sent])

    def test_promotes_before_revert_at(self):
        core = FakeCore({"server_port": 80}, down_for=0)
        core.revert_at = "2030-01-01T00:00:00+00:00"
        self.assertEqual(hc.ensure(core.open, sleep=lambda s: None, now=lambda: 1.0), "promoted")

    def test_pending_with_error_is_not_a_match_so_a_rerun_configures_again(self):
        core = FakeCore({"server_port": 80}, down_for=0)
        core.pending = dict(hc.merge(core.stable), error="boom")
        self.assertFalse(hc.pending_ok(core.pending))
        hc.ensure(core.open, sleep=lambda s: None)
        self.assertIn("http/config/configure", [m["type"] for m in core.sent])

    def test_pending_error_after_restart_exits(self):
        core = FakeCore({"server_port": 80}, down_for=0)
        core.recv_orig = core.recv

        def recv():
            r = core.recv_orig()
            if core._last["type"] == "http/config" and core.pending:
                r["result"]["pending"] = dict(core.pending, error="bad")
            return r
        core.recv = recv
        with self.assertRaises(SystemExit):
            hc.ensure(core.open, sleep=lambda s: None, tries=2)

    def test_parse_deadline(self):
        self.assertIsNone(hc.parse_deadline(None))
        self.assertIsNone(hc.parse_deadline("garbage"))
        self.assertEqual(hc.parse_deadline(5), 5.0)
        self.assertEqual(hc.parse_deadline("1970-01-01T00:01:00Z"), 60.0)

    def test_unchanged_when_stable_matches(self):
        core = FakeCore(dict(hc.WANTED, server_port=80))
        self.assertEqual(hc.ensure(core.open, sleep=lambda s: None), "unchanged")
        self.assertEqual([m["type"] for m in core.sent], ["http/config"])

    def test_configures_waits_then_promotes(self):
        core = FakeCore({"server_port": 80, "created_at": "z"}, down_for=2)
        self.assertEqual(hc.ensure(core.open, sleep=lambda s: None), "promoted")
        self.assertEqual([m["type"] for m in core.sent],
                         ["http/config", "http/config/configure", "http/config", "http/config/promote"])
        self.assertTrue(hc.matches(core.stable))
        self.assertEqual(core.sent[1]["config"]["server_port"], 80)
        self.assertNotIn("created_at", core.sent[1]["config"])

    def test_pending_already_matching_skips_configure(self):
        core = FakeCore({"server_port": 80})
        core.pending = hc.merge(core.stable)
        hc.ensure(core.open, sleep=lambda s: None)
        self.assertNotIn("http/config/configure", [m["type"] for m in core.sent])

    def test_gives_up_when_core_never_returns(self):
        core = FakeCore({"server_port": 80}, down_for=10**6)
        with self.assertRaises(SystemExit):
            hc.ensure(core.open, sleep=lambda s: None, tries=3)

    def test_call_failure_exits_with_error(self):
        class Bad:
            def send(self, o):
                self.o = o

            def recv(self):
                return {"id": self.o["id"], "success": False, "error": {"code": "nope"}}

        with self.assertRaises(SystemExit):
            hc.call(Bad(), 1, {"type": "http/config"})


class TemplateTests(unittest.TestCase):
    def test_configuration_template_has_no_http_block(self):
        text = (ROOT / "tools/test_ha/configuration.yaml.tmpl").read_text()
        self.assertFalse([l for l in text.splitlines() if l.startswith("http:")])

    def test_default_config_is_its_own_top_level_key(self):
        # PyYAML is not installed and the template uses !include_dir_named, so read the top-level keys line by line.
        keys = [l.split(":", 1)[0] for l in (ROOT / "tools/test_ha/configuration.yaml.tmpl").read_text().splitlines()
                if l and l[0] not in " #"]
        self.assertEqual(keys[0], "default_config")
        self.assertIn("homeassistant", keys)
        self.assertIn("fenton_demo", keys)

    def test_provision_runs_http_config(self):
        self.assertIn("http_config.py", (ROOT / "tools/test_ha/provision.sh").read_text())


if __name__ == "__main__":
    unittest.main()
