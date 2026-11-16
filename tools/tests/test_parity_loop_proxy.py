"""Tests for tools/parity_loop/guard_proxy.py: the allow-lists, the strict frame handling, the log templates, and the proxy end to end.

The end-to-end cases put a fake upstream behind the real proxy on loopback and send hostile input (fragments, binary frames,
bad UTF-8, batches, nested types, case and whitespace tricks, encoded and dotted paths, method-override headers, protocol
violations). The fake upstream records what reached it; nothing but judged, re-serialised reads may.
"""

from __future__ import annotations

import asyncio
import base64
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from parity_loop import guard_proxy as gp  # noqa: E402

WRITES = ["call_service", "execute_script", "fire_event", "person/update", "config/entity_registry/update", "schedule/update",
          "frontend/set_user_data", "mobile_app/push_notification_channel", "todo/item/add", "todo/item/update", "todo/item/remove",
          "camera/webrtc/offer-nope", "fenton_home/house_config/save", "fenton_home/ui_publication/publish",
          "fenton_home/ui_publication/rollback", "subscribe_trigger", "unsubscribe_everything", "", None, 5,
          # case, whitespace and control-character variants of names that are allowed or forbidden
          "Call_Service", "CALL_SERVICE", " call_service", "call_service ", "call_service\u0000", "call_service\n", "Get_States",
          "get_states ", " get_states", "get_states​", "get-states", "getstates", "get_states\x00", "fenton_home/house_config/subscribe/",
          "FENTON_HOME/house_config/subscribe"]
READS = sorted(gp.WS_ALLOWED_TYPES)


# MARK: - Filters

class WebSocketFilterTests(unittest.TestCase):
    def test_every_read_type_passes(self) -> None:
        for kind in READS:
            self.assertTrue(gp.ws_decide({"id": 1, "type": kind}).allowed, kind)
            self.assertFalse(gp.is_write_type(kind), kind)

    def test_the_allow_list_is_the_trimmed_set(self) -> None:
        for kind in ("render_template", "get_panels", "supported_features", "person/list", "schedule/list", "todo/item/list",
                     "config/entity_registry/list", "fenton_home/anything/list", "camera/webrtc/offer"):
            self.assertFalse(gp.ws_decide({"id": 1, "type": kind}).allowed, kind)

    def test_writes_variants_and_unknown_types_are_refused(self) -> None:
        for kind in WRITES:
            self.assertFalse(gp.ws_decide({"id": 1, "type": kind}).allowed, repr(kind))

    def test_call_service_is_refused_whatever_the_service(self) -> None:
        for service in ("turn_on", "get_forecasts", "recordVisit"):
            message = {"id": 2, "type": "call_service", "domain": "weather", "service": service, "return_response": True}
            self.assertFalse(gp.ws_decide(message).allowed)
            self.assertFalse(gp.ws_decide(message, extra_types=["call_service"]).allowed)

    def test_malformed_messages_are_refused(self) -> None:
        for value in ("text", 5, None, [], {}, {"type": 7}, {"type": {"type": "get_states"}}, {"type": ["get_states"]}):
            self.assertFalse(gp.ws_decide(value).allowed)

    def test_widening_never_reaches_a_write_type(self) -> None:
        self.assertTrue(gp.ws_decide({"type": "some/new/read"}, extra_types=["some/new/read"]).allowed)
        for kind in ("call_service", "frontend/set_user_data", "todo/item/add", "fire_event", "some/thing/update", "x_delete_y"):
            self.assertTrue(gp.is_write_type(kind), kind)
            self.assertFalse(gp.ws_decide({"type": kind}, extra_types=[kind]).allowed, kind)
            with self.assertRaises(ValueError):
                gp.GuardProxy(gp.Upstream("127.0.0.1", 1, False), gp.RejectionLog(None), extra_types=[kind])
        self.assertEqual(gp.main(["--upstream", "http://127.0.0.1:1", "--allow-type", "call_service"]), 2)

    def test_widening_paths_must_be_specific_and_not_never_prefixes(self) -> None:
        for prefix in ("/", "/a", "/api/webhook", "/api/mobile_app", "/api/services"):
            with self.assertRaises(ValueError):
                gp.GuardProxy(gp.Upstream("127.0.0.1", 1, False), gp.RejectionLog(None), extra_paths=[prefix])
        gp.GuardProxy(gp.Upstream("127.0.0.1", 1, False), gp.RejectionLog(None), extra_paths=["/custom/thing"])

    def test_a_batch_is_judged_element_by_element_and_re_serialised(self) -> None:
        text = json.dumps([{"id": 1, "type": "get_states"}, {"id": 2, "type": "call_service"}, {"id": 3, "type": "ping"}], indent=2)
        forward, refused = gp.filter_ws_payload(text)
        self.assertEqual(forward, '[{"id":1,"type":"get_states"},{"id":3,"type":"ping"}]')
        self.assertEqual([(d.label, i) for d, i in refused], [("call_service", 2)])

    def test_a_refused_single_message_is_not_forwarded(self) -> None:
        forward, refused = gp.filter_ws_payload(json.dumps({"id": 9, "type": "call_service"}))
        self.assertIsNone(forward)
        error = json.loads(gp.refusal_frame_text(refused[0][1]))
        self.assertEqual((error["id"], error["success"], error["error"]["code"]), (9, False, "read_only"))
        self.assertIsNone(gp.filter_ws_payload("not json")[0])
        self.assertIsNone(gp.filter_ws_payload("[" * 100000)[0])

    def test_duplicate_keys_are_resolved_before_the_judgement_and_the_server_sees_the_same(self) -> None:
        forward, refused = gp.filter_ws_payload('{"type":"call_service","type":"get_states"}')
        self.assertEqual((forward, refused), ('{"type":"get_states"}', []))
        forward, refused = gp.filter_ws_payload('{"type":"get_states","type":"call_service"}')
        self.assertIsNone(forward)

    def test_a_nested_type_cannot_change_the_judgement(self) -> None:
        forward, refused = gp.filter_ws_payload('{"id":1,"type":"get_states","x":{"type":"call_service"}}')
        self.assertEqual(json.loads(forward)["type"], "get_states")
        self.assertIsNone(gp.filter_ws_payload('{"id":1,"type":{"type":"get_states"}}')[0])


class HttpFilterTests(unittest.TestCase):
    def test_only_get_to_listed_paths_passes(self) -> None:
        for path in ("/api/", "/api/websocket", "/api/fenton_home/ui_assets/abc", "/api/fenton_home/config",
                     "/api/camera_proxy/camera.demo_x?token=1", "/api/camera_proxy_stream/camera.demo_x?token=1", "/api/camera_proxy",
                     "/api/image/serve/abc123/512x512", "/local/images/a.png"):
            self.assertTrue(gp.http_decide("GET", path).allowed, path)

    def test_the_http_list_is_trimmed(self) -> None:
        for path in ("/api/config", "/api/states", "/api/states/light.demo_x", "/api/history/period/2026-01-01", "/api/image_proxy/a",
                     "/static/a.js", "/frontend_latest/a.js", "/hacsfiles/a", "/api/services", "/manifest.json", "/api/unknown"):
            self.assertFalse(gp.http_decide("GET", path).allowed, path)

    def test_every_other_method_is_refused_even_on_a_listed_path(self) -> None:
        for method in ("POST", "PUT", "DELETE", "PATCH", "post", "get", "Get", "OPTIONS", "HEAD", "GET ", "GE\nT", ""):
            self.assertFalse(gp.http_decide(method, "/api/camera_proxy/camera.demo_x").allowed, repr(method))

    def test_never_paths_are_refused_even_for_get_and_when_widened(self) -> None:
        for path in ("/api/mobile_app/registrations", "/api/webhook/abc", "/api/services/light/turn_on", "/api/fenton_feedback/x",
                     "/api/template", "/api/events/x"):
            self.assertFalse(gp.http_decide("GET", path).allowed, path)
            self.assertFalse(gp.http_decide("GET", path, extra_prefixes=["/api"]).allowed, path)

    def test_encoded_dotted_and_odd_paths_are_refused(self) -> None:
        for path in ("/api/camera_proxy/%2e%2e/%2e%2e/webhook/x", "/api/camera_proxy/%2E%2E/webhook", "/api/camera_proxy/a%2fb",
                     "/api/camera_proxy/../webhook/x", "/api/camera_proxy/./a", "/api/camera_proxy//a", "//api/camera_proxy/a",
                     "/api/camera_proxy/a\\..\\b", "/api/camera_proxy/a;b", "/api/camera_proxy/a\x00b", "/api/camera_proxy/é",
                     "/api/camera_proxy/a b", "api/camera_proxy/a", "http://x/api/camera_proxy/a", "/api/camera_proxy/..",
                     "/api/camera_proxy/%00", "/local/%2e%2e/api/webhook/x", "/api/fenton_home/ui_assets/%2e%2e/x"):
            self.assertFalse(gp.http_decide("GET", path).allowed, repr(path))

    def test_a_query_string_is_ignored_for_the_judgement_even_when_it_holds_odd_characters(self) -> None:
        self.assertTrue(gp.http_decide("GET", "/api/camera_proxy/camera.demo_x?a=%2e%2e&b=//&c=\\").allowed)
        self.assertFalse(gp.http_decide("GET", "/api/webhook/x?/api/camera_proxy/a").allowed)

    def test_unlisted_paths_and_widening(self) -> None:
        for path in ("/", "/apixyz", "/api/statesx", "/api/image/upload", "/api/image"):
            self.assertFalse(gp.http_decide("GET", path).allowed, path)
        self.assertTrue(gp.http_decide("GET", "/custom/thing", extra_prefixes=["/custom"]).allowed)

    def test_forwardable_headers_drop_overrides_and_framing(self) -> None:
        kept = gp.GuardProxy.forwardable_headers({
            "authorization": "Bearer x", "accept": "*/*", "x-http-method-override": "DELETE", "x-method-override": "PUT",
            "x-http-method": "POST", "x-original-method": "POST", "x-forwarded-for": "1.1.1.1", "x-rewrite-url": "/api/webhook",
            "x-original-url": "/api/webhook", "transfer-encoding": "chunked", "content-length": "5", "te": "trailers", "host": "x"})
        self.assertEqual(kept, {"authorization": "Bearer x", "accept": "*/*"})


class PathTemplateTests(unittest.TestCase):
    def test_templates_keep_words_and_drop_everything_else(self) -> None:
        cases = {
            "/api/hls/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/playlist.m3u8?x=1": "/api/hls/*",
            "/api/webhook/some-webhook-id": "/api/webhook/*",
            "/api/webrtc/ws": "/api/webrtc/*",
            "/api/camera_proxy/camera.demo_x?authSig=SIGNED&token=abc": "/api/camera_proxy/*",
            "/api/image/serve/abc123/512x512": "/api/image/serve/*",
            "/api/fenton_home/ui_assets/" + "a" * 64: "/api/fenton_home/ui_assets/*",
            "/api/fenton_home/config": "/api/fenton_home/config",
            "/local/images/a.png": "/local/images/*",
            "/api/websocket": "/api/websocket",
            "/": "/", "": "/", "/Api/Token123/x": "/*",
        }
        for path, expected in cases.items():
            self.assertEqual(gp.path_template(path), expected, path)

    def test_no_secret_survives_a_template(self) -> None:
        for secret in ("TOKEN" + "a1" * 20, "authSig=abc.def.ghi", "webhookid123"):
            self.assertNotIn(secret, gp.path_template(f"/api/hls/{secret}/x?{secret}"))
            self.assertNotIn(secret, gp.path_template(f"/api/webhook/{secret}"))


class LogTests(unittest.TestCase):
    def test_log_has_type_and_template_but_no_query_id_or_body(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = gp.RejectionLog(Path(tmp) / "run" / "rej.jsonl")
            log.record(gp.http_decide("POST", "/api/webhook/WEBHOOKSECRET?access_token=SECRET"), "/api/webhook/WEBHOOKSECRET?access_token=SECRET")
            log.record(gp.http_decide("GET", "/api/hls/" + "ab12" * 16 + "/playlist.m3u8"), "/api/hls/" + "ab12" * 16 + "/playlist.m3u8")
            log.record(gp.ws_decide({"type": "call_service", "data": {"token": "SECRET"}}), "/api/websocket")
            text = (Path(tmp) / "run" / "rej.jsonl").read_text()
        rows = [json.loads(line) for line in text.splitlines()]
        for secret in ("SECRET", "WEBHOOKSECRET", "ab12" * 16):
            self.assertNotIn(secret, text)
        self.assertEqual([(r["kind"], r["label"], r["path"]) for r in rows],
                         [("http", "POST", "/api/webhook/*"), ("http", "GET", "/api/hls/*"), ("ws", "call_service", "/api/websocket")])
        self.assertEqual(log.counts, {"http:POST": 1, "http:GET": 1, "ws:call_service": 1})

    def test_a_refused_call_service_logs_domain_and_service_only(self) -> None:
        message = {"id": 4, "type": "call_service", "domain": "script", "service": "record_visit",
                   "service_data": {"room": "SECRETROOM"}, "target": {"entity_id": "light.demo_SECRETLIGHT"}}
        verdict = gp.ws_decide(message)
        self.assertEqual(verdict.detail, {"domain": "script", "service": "record_visit"})
        with tempfile.TemporaryDirectory() as tmp:
            log = gp.RejectionLog(Path(tmp) / "r.jsonl")
            log.record(verdict, "/api/websocket")
            log.record(gp.ws_decide({"type": "fire_event", "event_type": "x"}), "/api/websocket")
            text = (Path(tmp) / "r.jsonl").read_text()
        rows = [json.loads(line) for line in text.splitlines()]
        self.assertNotIn("SECRET", text)
        self.assertEqual((rows[0]["domain"], rows[0]["service"]), ("script", "record_visit"))
        self.assertNotIn("domain", rows[1])
        self.assertIsNone(gp.ws_decide({"type": "call_service", "domain": 5}).detail)

    def test_allowed_traffic_is_counted_by_type_and_template(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = gp.RejectionLog(Path(tmp) / "run" / "rej.jsonl")
            forward, _ = gp.filter_ws_payload(json.dumps([{"id": 1, "type": "fenton_home/house_config/subscribe", "token": "SECRET"},
                                                          {"id": 2, "type": "get_states"}]))
            for label in gp.allowed_labels(forward):
                log.record_allowed("ws", label)
            log.record_allowed("ws", "get_states")
            log.record_allowed("http", gp.http_bucket("/api/camera_proxy/camera.demo_secret?x=1"))
            text = (Path(tmp) / "run" / "allowed-summary.json").read_text()
        summary = json.loads(text)
        self.assertEqual(summary["ws"], {"fenton_home/house_config/subscribe": 1, "get_states": 2})
        self.assertEqual(summary["http"], {"/api/camera_proxy/*": 1})
        self.assertNotIn("demo_secret", text)

    def test_scrub_rewrites_an_existing_log_in_place_to_the_template_form(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            old = Path(tmp) / "proxy-rejections.jsonl"
            rows = [{"time": "t", "kind": "http", "label": "GET", "path": "/api/hls/" + "cd34" * 16 + "/a.m3u8", "reason": "r",
                     "extra": "dropped"},
                    {"time": "t", "kind": "ws", "label": "call_service", "path": "/api/websocket", "reason": "r",
                     "domain": "weather", "service": "get_forecasts"},
                    {"time": "t", "kind": "http", "label": "POST", "path": "/api/webhook/WEBHOOKSECRET", "reason": "r"}]
            old.write_text("\n".join(json.dumps(r) for r in rows) + "\n\n")
            summary = Path(tmp) / "allowed-summary.json"
            summary.write_text(json.dumps({"http": {"/api/camera_proxy": 8, "/api/image": 4, "/api/fenton_home": 2}, "ws": {"auth": 1}}))
            other = Path(tmp) / "notes.txt"
            other.write_text("x")
            self.assertEqual(gp.main(["scrub", str(old), str(summary)]), 0)
            text = old.read_text()
            self.assertNotIn("cd34", text)
            self.assertNotIn("WEBHOOKSECRET", text)
            self.assertNotIn("dropped", text)
            result = [json.loads(line) for line in text.splitlines()]
            self.assertEqual([r["path"] for r in result], ["/api/hls/*", "/api/websocket", "/api/webhook/*"])
            self.assertEqual((result[1]["domain"], result[1]["service"]), ("weather", "get_forecasts"))
            self.assertEqual(gp.scrub_file(old), 0)  # idempotent
            self.assertEqual(json.loads(summary.read_text())["http"],
                             {"/api/camera_proxy": 8, "/api/image": 4, "/api/fenton_home": 2})
            with self.assertRaises(ValueError):
                gp.scrub_file(other)
            self.assertEqual(gp.main(["scrub", str(other)]), 2)
            self.assertEqual(gp.main(["scrub"]), 2)


# MARK: - Frames

def raw_frame(fin: bool, opcode: int, payload: bytes, *, mask: bool = True, rsv: int = 0) -> bytes:
    """A hand-built client frame, so a test can set bits ``encode_frame`` never would."""
    first = (0x80 if fin else 0) | (rsv << 4) | opcode
    n = len(payload)
    head = bytes([first]) + (bytes([(0x80 if mask else 0) | n]) if n < 126 else bytes([(0x80 if mask else 0) | 126]) + n.to_bytes(2, "big"))
    if not mask:
        return head + payload
    key = b"\x01\x02\x03\x04"
    return head + key + bytes(b ^ key[i % 4] for i, b in enumerate(payload))


class FrameTests(unittest.TestCase):
    @staticmethod
    def read(*chunks: bytes, from_client: bool = False) -> Tuple[bool, int, bytes]:
        async def go() -> Tuple[bool, int, bytes]:
            reader = asyncio.StreamReader()
            for chunk in chunks:
                reader.feed_data(chunk)
            reader.feed_eof()
            return await gp.read_frame(reader, from_client=from_client)
        return asyncio.run(go())

    def test_frames_round_trip_masked_and_unmasked(self) -> None:
        async def go() -> list:
            reader = asyncio.StreamReader()
            for p, m in ((b"hi", True), (b"x" * 300, True), (b"y" * 70000, False)):
                reader.feed_data(gp.encode_frame(1, p, m))
            reader.feed_eof()
            return [(await gp.read_frame(reader))[2] for _ in range(3)]
        out = asyncio.run(go())
        self.assertEqual([len(p) for p in out], [2, 300, 70000])
        self.assertEqual(out[0], b"hi")

    def test_strict_client_frames_refuse_protocol_violations(self) -> None:
        bad = {
            "reserved bit (compression)": raw_frame(True, 1, b"{}", rsv=4),
            "unmasked": raw_frame(True, 1, b"{}", mask=False),
            "reserved opcode 3": raw_frame(True, 3, b"x"),
            "reserved opcode 11": raw_frame(True, 11, b"x"),
            "fragmented ping": raw_frame(False, 9, b"x"),
            "oversized ping": raw_frame(True, 9, b"x" * 126),
        }
        for name, data in bad.items():
            with self.assertRaises(gp.ProtocolError, msg=name):
                self.read(data, from_client=True)
        self.assertEqual(self.read(raw_frame(True, 1, b"{}"), from_client=True), (True, 1, b"{}"))
        self.assertEqual(self.read(raw_frame(False, 1, b"{"), from_client=True)[0], False)


# MARK: - End to end

class FakeUpstream:
    """A loopback Home Assistant stand-in: records every websocket text message and every HTTP request that reaches it."""

    def __init__(self, on_connect: Optional[Callable[[asyncio.StreamWriter], Awaitable[None]]] = None) -> None:
        self.ws_text: List[str] = []
        self.ws_other: List[int] = []
        self.http: List[Tuple[str, Dict[str, str]]] = []
        self.on_connect = on_connect

    async def handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        head = (await reader.readuntil(b"\r\n\r\n")).decode()
        lines = head.split("\r\n")
        headers = {k.lower(): v.strip() for k, v in (h.split(":", 1) for h in lines[1:] if ":" in h)}
        if headers.get("upgrade", "").lower() == "websocket":
            writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                          f"Sec-WebSocket-Accept: {gp.accept_key(headers['sec-websocket-key'])}\r\n\r\n").encode())
            await writer.drain()
            if self.on_connect:
                asyncio.ensure_future(self.on_connect(writer))
            try:
                while True:
                    _, opcode, data = await gp.read_frame(reader)
                    if opcode == 1:
                        self.ws_text.append(data.decode("utf-8", "replace"))
                        writer.write(gp.encode_frame(1, b'{"type":"result","success":true}', False))
                        await writer.drain()
                    elif opcode == 8:
                        break
                    else:
                        self.ws_other.append(opcode)
            except asyncio.IncompleteReadError:
                pass
        else:
            self.http.append((lines[0].rsplit(" ", 1)[0], headers))
            writer.write(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}")
            await writer.drain()
        writer.close()


class Harness:
    """A fake upstream behind a real proxy; ``await harness.start()`` then talk to ``harness.port``."""

    def __init__(self, log_path: Path, on_connect: Optional[Callable[[asyncio.StreamWriter], Awaitable[None]]] = None) -> None:
        self.ha = FakeUpstream(on_connect)
        self.log = gp.RejectionLog(log_path)
        self.writers: List[asyncio.StreamWriter] = []

    async def start(self) -> "Harness":
        self.upstream = await asyncio.start_server(self.ha.handle, "127.0.0.1", 0)
        proxy = gp.GuardProxy(gp.Upstream("127.0.0.1", self.upstream.sockets[0].getsockname()[1], False), self.log)
        self.server = await gp.serve(proxy, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]
        return self

    async def stop(self) -> None:
        await asyncio.sleep(0.05)
        for writer in self.writers:
            writer.close()
        await asyncio.sleep(0.02)
        self.server.close()
        self.upstream.close()

    async def ws(self) -> Tuple[asyncio.StreamReader, asyncio.StreamWriter]:
        reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
        self.writers.append(writer)
        key = base64.b64encode(os.urandom(16)).decode()
        writer.write((f"GET /api/websocket HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        await reader.readuntil(b"\r\n\r\n")
        return reader, writer

    async def http_request(self, request: bytes) -> int:
        reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
        writer.write(request)
        await writer.drain()
        status = int((await reader.readline()).split()[1])
        writer.close()
        return status


async def frames_until_quiet(reader: asyncio.StreamReader, quiet: float = 0.25) -> List[Tuple[bool, int, bytes]]:
    """Every whole frame the client receives until nothing arrives for ``quiet`` seconds or the stream ends."""
    out: List[Tuple[bool, int, bytes]] = []
    while True:
        try:
            out.append(await asyncio.wait_for(gp.read_frame(reader), quiet))
        except (asyncio.TimeoutError, asyncio.IncompleteReadError):
            return out


def text(frames: List[Tuple[bool, int, bytes]]) -> List[Dict[str, Any]]:
    return [json.loads(p) for _, op, p in frames if op == 1]


def run(coro: Awaitable[Any]) -> Any:
    return asyncio.run(coro)


class ProxyEndToEndTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def scenario(self, body: Callable[[Harness], Awaitable[Any]], on_connect=None) -> Harness:
        async def go() -> Harness:
            harness = await Harness(self.dir / "run" / "rej.jsonl", on_connect).start()
            try:
                await body(harness)
            finally:
                await harness.stop()
            return harness
        return run(go())

    def test_reads_pass_and_writes_never_reach_the_upstream(self) -> None:
        async def body(h: Harness) -> None:
            self.assertEqual(await h.http_request(b"GET /api/image/serve/abc/512 HTTP/1.1\r\nHost: x\r\n\r\n"), 200)
            for method, path in (("POST", "/api/webhook/abc"), ("POST", "/api/mobile_app/registrations"), ("GET", "/api/mobile_app/registrations"),
                                 ("DELETE", "/api/camera_proxy/camera.demo_x"), ("PUT", "/api/image/serve/a")):
                self.assertEqual(await h.http_request(f"{method} {path} HTTP/1.1\r\nHost: x\r\n\r\n".encode()), 403, (method, path))
            reader, writer = await h.ws()
            for message in ({"id": 1, "type": "get_states"}, {"id": 2, "type": "call_service", "domain": "light", "service": "turn_on"},
                            {"id": 3, "type": "ping"}):
                writer.write(gp.encode_frame(1, json.dumps(message).encode(), True))
            await writer.drain()
            replies = text(await frames_until_quiet(reader))
            self.assertEqual([r.get("id") for r in replies if not r.get("success", True)], [2])
            writer.write(gp.encode_frame(8, b"", True))
            await writer.drain()
        h = self.scenario(body)
        self.assertEqual([json.loads(t)["type"] for t in h.ha.ws_text], ["get_states", "ping"])
        self.assertEqual([path for path, _ in h.ha.http], ["GET /api/image/serve/abc/512"])
        self.assertEqual(h.log.allowed["ws"], {"get_states": 1, "ping": 1})
        self.assertEqual(h.log.allowed["http"], {"/api/image/serve/*": 1})
        rows = [json.loads(line) for line in (self.dir / "run" / "rej.jsonl").read_text().splitlines()]
        service = [r for r in rows if r["label"] == "call_service"][0]
        self.assertEqual((service["domain"], service["service"]), ("light", "turn_on"))

    def test_fragmented_messages_are_reassembled_judged_and_re_serialised(self) -> None:
        async def body(h: Harness) -> None:
            reader, writer = await h.ws()
            bad = b'{"id":5,"type":"call_service","domain":"light","service":"turn_on"}'
            good = b'{ "id": 6, "type": "get_states" }'
            for data in (bad, good):
                third = len(data) // 3
                writer.write(raw_frame(False, 1, data[:third]) + raw_frame(False, 0, data[third:2 * third]) + raw_frame(True, 0, data[2 * third:]))
            await writer.drain()
            replies = text(await frames_until_quiet(reader))
            self.assertEqual([r.get("id") for r in replies if not r.get("success", True)], [5])
        h = self.scenario(body)
        self.assertEqual(h.ha.ws_text, ['{"id":6,"type":"get_states"}'])  # one whole frame, re-serialised, bad one absent

    def test_binary_frames_are_refused_whole_or_fragmented(self) -> None:
        async def body(h: Harness) -> None:
            reader, writer = await h.ws()
            message = b'{"id":1,"type":"get_states"}'
            writer.write(raw_frame(True, 2, message))
            writer.write(raw_frame(False, 2, message[:5]) + raw_frame(True, 0, message[5:]))
            writer.write(gp.encode_frame(1, b'{"id":2,"type":"ping"}', True))
            await writer.drain()
            await frames_until_quiet(reader)
        h = self.scenario(body)
        self.assertEqual(h.ha.ws_text, ['{"id":2,"type":"ping"}'])
        self.assertEqual(h.ha.ws_other, [])
        self.assertEqual(h.log.counts.get("ws:<binary>"), 2)

    def test_invalid_utf8_is_refused_not_repaired(self) -> None:
        async def body(h: Harness) -> None:
            reader, writer = await h.ws()
            writer.write(raw_frame(True, 1, b'{"id":1,"type":"get_states","x":"\xff\xfe"}'))
            writer.write(raw_frame(True, 1, b'{"id":2,"type":"get_states"}'))
            await writer.drain()
            replies = text(await frames_until_quiet(reader))
            self.assertEqual(len([r for r in replies if not r.get("success", True)]), 1)
        h = self.scenario(body)
        self.assertEqual(h.ha.ws_text, ['{"id":2,"type":"get_states"}'])
        self.assertEqual(h.log.counts.get("ws:<invalid-utf8>"), 1)

    def test_batches_nested_types_and_case_and_whitespace_tricks(self) -> None:
        async def body(h: Harness) -> None:
            reader, writer = await h.ws()
            sent = [
                [{"id": 1, "type": "get_states"}, {"id": 2, "type": "call_service"}],
                {"id": 3, "type": "get_states", "x": {"type": "call_service"}},
                {"id": 4, "type": {"type": "get_states"}},
                {"id": 5, "type": "Call_Service"}, {"id": 6, "type": " call_service"}, {"id": 7, "type": "call_service\u0000"},
                {"id": 8, "type": "GET_STATES"}, {"id": 9, "type": "get_states\n"},
                {"id": 10, "type": "get_states", "type2": "call_service"},
            ]
            for message in sent:
                writer.write(gp.encode_frame(1, json.dumps(message).encode(), True))
            await writer.drain()
            replies = text(await frames_until_quiet(reader))
            self.assertEqual(sorted(r["id"] for r in replies if not r.get("success", True) and "id" in r), [2, 4, 5, 6, 7, 8, 9])
        h = self.scenario(body)
        seen = [json.loads(t) for t in h.ha.ws_text]
        self.assertEqual(seen[0], [{"id": 1, "type": "get_states"}])
        self.assertEqual([m["id"] for m in seen[1:]], [3, 10])
        self.assertTrue(all(m["type"] == "get_states" for m in seen[1:]))

    def test_protocol_violations_close_the_connection_and_forward_nothing(self) -> None:
        cases = {
            "unmasked": raw_frame(True, 1, b'{"id":1,"type":"get_states"}', mask=False),
            "reserved bit": raw_frame(True, 1, b'{"id":1,"type":"get_states"}', rsv=4),
            "reserved opcode": raw_frame(True, 5, b"x"),
            "stray continuation": raw_frame(True, 0, b'{"id":1,"type":"get_states"}'),
            "new message inside a fragmented one": raw_frame(False, 1, b'{"id":1,') + raw_frame(True, 1, b'"type":"get_states"}'),
        }
        for name, data in cases.items():
            async def body(h: Harness, data: bytes = data) -> None:
                reader, writer = await h.ws()
                writer.write(data)
                await writer.drain()
                frames = await frames_until_quiet(reader)
                self.assertIn(8, [op for _, op, _ in frames])
                self.assertEqual(int.from_bytes([p for _, op, p in frames if op == 8][0], "big"), 1002)
            h = self.scenario(body)
            self.assertEqual(h.ha.ws_text, [], name)
            self.assertEqual(h.log.counts.get("ws:<protocol>"), 1, name)

    def test_a_refusal_never_splits_a_server_frame_or_message(self) -> None:
        big = b'{"id":1,"type":"result","payload":"' + b"x" * 200_000 + b'"}'

        async def on_connect(writer: asyncio.StreamWriter) -> None:
            await asyncio.sleep(0.1)
            # one large frame whose bytes arrive in pieces, then a fragmented message with pauses between its fragments
            frame = gp.encode_frame(1, big, False)
            for start in range(0, len(frame), 40_000):
                writer.write(frame[start:start + 40_000])
                await writer.drain()
                await asyncio.sleep(0.05)
            for fin, opcode, part in ((False, 1, b'{"id":2,'), (False, 0, b'"type":"event",'), (True, 0, b'"event":{}}')):
                writer.write(gp.encode_frame(opcode, part, False, fin))
                await writer.drain()
                await asyncio.sleep(0.15)

        async def body(h: Harness) -> None:
            reader, writer = await h.ws()
            await asyncio.sleep(0.15)  # the big frame is part-way: refusals must wait for whole frames
            for i in range(3):
                writer.write(gp.encode_frame(1, json.dumps({"id": 100 + i, "type": "call_service"}).encode(), True))
                await writer.drain()
                await asyncio.sleep(0.12)
            frames = await frames_until_quiet(reader, quiet=0.6)
            self.frames = frames
        self.scenario(body, on_connect)
        frames = self.frames
        # every frame parsed whole; the big payload and the three-fragment message arrive intact
        self.assertIn((True, 1, big), frames)
        data = [(fin, op, p) for fin, op, p in frames if op in (0, 1)]
        refusals = [i for i, (_, op, p) in enumerate(data) if op == 1 and b'"read_only"' in p]
        self.assertEqual(len(refusals), 3)
        start = next(i for i, (fin, op, p) in enumerate(data) if op == 1 and not fin)
        end = next(i for i in range(start, len(data)) if data[i][0])
        self.assertEqual(b"".join(p for _, _, p in data[start:end + 1]), b'{"id":2,"type":"event","event":{}}')
        self.assertFalse([i for i in refusals if start < i < end], "a refusal landed inside a fragmented server message")
        self.assertTrue(all(d[1] == 0 for d in data[start + 1:end + 1]))

    def test_http_hostile_paths_methods_and_override_headers(self) -> None:
        async def body(h: Harness) -> None:
            refused = [
                b"GET /api/camera_proxy/%2e%2e/%2e%2e/webhook/x HTTP/1.1\r\nHost: x\r\n\r\n",
                b"GET /api/camera_proxy/../webhook/x HTTP/1.1\r\nHost: x\r\n\r\n",
                b"get /api/camera_proxy/a HTTP/1.1\r\nHost: x\r\n\r\n",
                b"POST /api/camera_proxy/a HTTP/1.1\r\nHost: x\r\nX-HTTP-Method-Override: GET\r\n\r\n",
                b"GET http://evil.invalid/api/camera_proxy/a HTTP/1.1\r\nHost: x\r\n\r\n",
                b"GET /api/webhook/abc HTTP/1.1\r\nHost: x\r\nX-HTTP-Method-Override: GET\r\n\r\n",
                b"GET /api/hls/" + b"ab12" * 16 + b"/playlist.m3u8 HTTP/1.1\r\nHost: x\r\n\r\n",
            ]
            for request in refused:
                self.assertEqual(await h.http_request(request), 403, request[:60])
            ok = (b"GET /api/camera_proxy/camera.demo_x?t=1 HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer abc\r\n"
                  b"X-HTTP-Method-Override: DELETE\r\nX-Method-Override: PUT\r\nX-Forwarded-For: 9.9.9.9\r\n\r\n")
            self.assertEqual(await h.http_request(ok), 200)
        h = self.scenario(body)
        self.assertEqual(len(h.ha.http), 1)
        request_line, headers = h.ha.http[0]
        self.assertEqual(request_line, "GET /api/camera_proxy/camera.demo_x?t=1")
        self.assertEqual(headers.get("authorization"), "Bearer abc")
        self.assertFalse([k for k in headers if "method" in k or "forwarded" in k], headers)
        log_text = (self.dir / "run" / "rej.jsonl").read_text()
        self.assertNotIn("ab12" * 8, log_text)
        self.assertNotIn("webhook/abc", log_text)


if __name__ == "__main__":
    unittest.main()
