"""Tests for tools/parity_loop/guard_proxy.py: the WebSocket and HTTP allow-lists, and the proxy end to end on loopback."""

from __future__ import annotations

import asyncio
import base64
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from parity_loop import guard_proxy as gp  # noqa: E402

WRITES = ["call_service", "execute_script", "fire_event", "person/update", "config/entity_registry/update", "schedule/update",
          "frontend/set_user_data", "mobile_app/push_notification_channel", "todo/item/add", "todo/item/update", "todo/item/remove",
          "camera/webrtc/offer-nope", "fenton_home/house_config/save", "fenton_home/ui_publication/publish",
          "fenton_home/ui_publication/rollback", "subscribe_trigger", "unsubscribe_everything", "", None, 5]
READS = ["auth", "ping", "get_states", "get_config", "get_services", "subscribe_events", "subscribe_entities", "render_template",
         "fenton_home/house_config/subscribe", "fenton_home/ui_publication/subscribe", "fenton_home/ui_publication/get",
         "fenton_home/anything/list", "person/list"]


class WebSocketFilterTests(unittest.TestCase):
    def test_every_read_type_passes(self) -> None:
        for kind in READS:
            self.assertTrue(gp.ws_decide({"id": 1, "type": kind}).allowed, kind)

    def test_writes_and_unknown_types_are_refused(self) -> None:
        for kind in WRITES:
            self.assertFalse(gp.ws_decide({"id": 1, "type": kind}).allowed, kind)

    def test_call_service_is_refused_whatever_the_service(self) -> None:
        for service in ("turn_on", "get_forecasts", "recordVisit"):
            message = {"id": 2, "type": "call_service", "domain": "weather", "service": service, "return_response": True}
            self.assertFalse(gp.ws_decide(message).allowed)

    def test_malformed_messages_are_refused(self) -> None:
        for value in ("text", 5, None, [], {}, {"type": 7}):
            self.assertFalse(gp.ws_decide(value).allowed)

    def test_the_allow_list_is_an_allow_list(self) -> None:
        self.assertFalse(gp.ws_decide({"type": "some/new/type"}).allowed)
        self.assertTrue(gp.ws_decide({"type": "some/new/type"}, extra_types=["some/new/type"]).allowed)
        self.assertFalse(gp.ws_decide({"type": "fenton_home/x/save"}).allowed)
        self.assertNotIn("call_service", gp.WS_ALLOWED_TYPES)

    def test_a_batch_is_judged_element_by_element(self) -> None:
        text = json.dumps([{"id": 1, "type": "get_states"}, {"id": 2, "type": "call_service"}, {"id": 3, "type": "ping"}])
        forward, refused = gp.filter_ws_payload(text)
        self.assertEqual([m["id"] for m in json.loads(forward)], [1, 3])
        self.assertEqual([(d.label, i) for d, i in refused], [("call_service", 2)])

    def test_a_refused_single_message_is_not_forwarded(self) -> None:
        forward, refused = gp.filter_ws_payload(json.dumps({"id": 9, "type": "call_service"}))
        self.assertIsNone(forward)
        error = json.loads(gp.refusal_frame_text(refused[0][1]))
        self.assertEqual((error["id"], error["success"], error["error"]["code"]), (9, False, "read_only"))
        self.assertIsNone(gp.filter_ws_payload("not json")[0])


class HttpFilterTests(unittest.TestCase):
    def test_only_get_to_listed_paths_passes(self) -> None:
        for path in ("/api/", "/api/config", "/api/states", "/api/states/light.x", "/api/fenton_home/ui_assets/abc",
                     "/api/camera_proxy/camera.x?token=1", "/api/image_proxy/a", "/api/history/period/2026-01-01", "/static/a.js", "/api/websocket"):
            self.assertTrue(gp.http_decide("GET", path).allowed, path)

    def test_every_other_method_is_refused_even_on_a_listed_path(self) -> None:
        for method in ("POST", "PUT", "DELETE", "PATCH", "post", "OPTIONS", "HEAD"):
            self.assertFalse(gp.http_decide(method, "/api/states/light.x").allowed, method)
        for path in ("/api/mobile_app/registrations", "/api/webhook/abc", "/api/services/light/turn_on", "/api/history/period/x",
                     "/api/camera_proxy/camera.x", "/api/events/foo"):
            self.assertFalse(gp.http_decide("POST", path).allowed, path)

    def test_never_paths_are_refused_even_for_get(self) -> None:
        for path in ("/api/mobile_app/registrations", "/api/webhook/abc", "/api/services/light/turn_on", "/api/fenton_feedback/x",
                     "/api/template", "/api/events/x"):
            self.assertFalse(gp.http_decide("GET", path).allowed, path)
            self.assertFalse(gp.http_decide("GET", path, extra_prefixes=["/api"]).allowed, path)

    def test_unlisted_and_traversal_paths_are_refused(self) -> None:
        for path in ("/api/unknown", "/", "/api/states/../mobile_app/x", "/apixyz", "/api/statesx"):
            self.assertFalse(gp.http_decide("GET", path).allowed, path)
        self.assertTrue(gp.http_decide("GET", "/custom/thing", extra_prefixes=["/custom"]).allowed)


class RejectionLogTests(unittest.TestCase):
    def test_log_has_type_and_path_but_no_query_or_body(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = gp.RejectionLog(Path(tmp) / "run" / "rej.jsonl")
            log.record(gp.http_decide("POST", "/api/webhook/x?access_token=SECRET"), "/api/webhook/x?access_token=SECRET")
            log.record(gp.ws_decide({"type": "call_service", "data": {"token": "SECRET"}}), "/api/websocket")
            text = (Path(tmp) / "run" / "rej.jsonl").read_text()
            rows = [json.loads(line) for line in text.splitlines()]
        self.assertNotIn("SECRET", text)
        self.assertEqual([(r["kind"], r["label"], r["path"]) for r in rows],
                         [("http", "POST", "/api/webhook/x"), ("ws", "call_service", "/api/websocket")])
        self.assertEqual(log.counts, {"http:POST": 1, "ws:call_service": 1})


class FrameTests(unittest.TestCase):
    def test_frames_round_trip_masked_and_unmasked(self) -> None:
        async def go() -> list:
            reader = asyncio.StreamReader()
            for payload, masked in ((b"hi", True), (b"x" * 300, True), (b"y" * 70000, False)):
                reader.feed_data(gp.encode_frame(1, payload, masked))
            reader.feed_eof()
            return [(await gp.read_frame(reader))[2] for _ in range(3)]
        out = asyncio.run(go())
        self.assertEqual([len(p) for p in out], [2, 300, 70000])
        self.assertEqual(out[0], b"hi")


class ProxyEndToEndTests(unittest.TestCase):
    """A fake upstream on loopback records what reaches it; the proxy must forward reads and drop writes."""

    def test_reads_pass_and_writes_never_reach_the_upstream(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = asyncio.run(self.scenario(Path(tmp) / "rej.jsonl"))
        seen_ws, seen_http, replies, statuses, log_rows = result
        self.assertEqual(seen_ws, ["get_states", "ping"])
        self.assertEqual(seen_http, ["GET /api/config"])
        self.assertEqual(statuses, [200, 403, 403, 403])
        self.assertEqual(replies[0]["error"]["code"], "read_only")
        self.assertEqual(replies[0]["id"], 2)
        self.assertEqual(sorted(r["label"] for r in log_rows), ["GET", "POST", "POST", "call_service"])

    async def scenario(self, log_path: Path):
        seen_ws, seen_http = [], []

        async def upstream(reader, writer):
            head = (await reader.readuntil(b"\r\n\r\n")).decode()
            first = head.split("\r\n")[0]
            if "Upgrade: websocket" in head:
                key = [h.split(": ")[1] for h in head.split("\r\n") if h.startswith("Sec-WebSocket-Key")][0]
                writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                              f"Sec-WebSocket-Accept: {gp.accept_key(key)}\r\n\r\n").encode())
                await writer.drain()
                writer.write(gp.encode_frame(1, b'{"type":"auth_required"}', False))
                await writer.drain()
                try:
                    while True:
                        _, op, data = await gp.read_frame(reader)
                        if op == 1:
                            seen_ws.append(json.loads(data)["type"])
                            writer.write(gp.encode_frame(1, b'{"type":"result","success":true}', False))
                            await writer.drain()
                        if op == 8:
                            break
                except asyncio.IncompleteReadError:
                    pass
            else:
                seen_http.append(" ".join(first.split(" ")[:2]))
                body = b"{}"
                writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n" + body)
                await writer.drain()
            writer.close()

        up = await asyncio.start_server(upstream, "127.0.0.1", 0)
        up_port = up.sockets[0].getsockname()[1]
        log = gp.RejectionLog(log_path)
        proxy = gp.GuardProxy(gp.Upstream("127.0.0.1", up_port, False), log)
        server = await gp.serve(proxy, "127.0.0.1", 0)
        port = server.sockets[0].getsockname()[1]

        async def http(method: str, path: str) -> int:
            r, w = await asyncio.open_connection("127.0.0.1", port)
            w.write(f"{method} {path} HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n".encode())
            await w.drain()
            status = int((await r.readline()).split()[1])
            w.close()
            return status

        statuses = [await http("GET", "/api/config"), await http("POST", "/api/webhook/abc"),
                    await http("POST", "/api/mobile_app/registrations"), await http("GET", "/api/mobile_app/registrations")]

        r, w = await asyncio.open_connection("127.0.0.1", port)
        key = base64.b64encode(os.urandom(16)).decode()
        w.write((f"GET /api/websocket HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                 f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        await r.readuntil(b"\r\n\r\n")
        await gp.read_frame(r)  # auth_required, passed through from the server
        replies = []
        for message in ({"id": 1, "type": "get_states"}, {"id": 2, "type": "call_service", "domain": "light", "service": "turn_on"},
                        {"id": 3, "type": "ping"}):
            w.write(gp.encode_frame(1, json.dumps(message).encode(), True))
            await w.drain()
            data = json.loads((await gp.read_frame(r))[2])
            if not data.get("success", True):
                replies.append(data)
        w.write(gp.encode_frame(8, b"", True))
        await w.drain()
        w.close()
        await asyncio.sleep(0.1)
        server.close()
        up.close()
        rows = [json.loads(line) for line in log_path.read_text().splitlines()]
        # three http refusals were logged, one websocket refusal; the GET-to-config passed
        return seen_ws, seen_http, replies, statuses, [r for r in rows if r["label"] in ("POST", "call_service", "GET")]


class FixRoundTests(unittest.TestCase):
    def test_camera_and_sign_path_reads_pass_but_writes_stay_refused(self) -> None:
        for kind in ("camera/stream", "auth/sign_path"):
            self.assertTrue(gp.ws_decide({"id": 1, "type": kind, "entity_id": "camera.x"}).allowed, kind)
        for kind in ("call_service", "camera/webrtc/offer", "camera/update", "auth/delete_token"):
            self.assertFalse(gp.ws_decide({"id": 1, "type": kind}).allowed, kind)

    def test_image_serve_and_camera_proxy_paths_are_get_only_reads(self) -> None:
        for path in ("/api/image/serve/abc123/512x512", "/api/camera_proxy/camera.x", "/api/camera_proxy_stream/camera.x?token=1",
                     "/api/camera_proxy"):
            self.assertTrue(gp.http_decide("GET", path).allowed, path)
            for method in ("POST", "PUT", "DELETE", "PATCH"):
                self.assertFalse(gp.http_decide(method, path).allowed, (method, path))
        self.assertFalse(gp.http_decide("GET", "/api/image/upload").allowed)
        self.assertFalse(gp.http_decide("GET", "/api/image").allowed)

    def test_a_refused_call_service_logs_domain_and_service_only(self) -> None:
        message = {"id": 4, "type": "call_service", "domain": "script", "service": "record_visit",
                   "service_data": {"room": "SECRETROOM"}, "target": {"entity_id": "light.SECRETLIGHT"}}
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
        self.assertEqual(gp.ws_decide({"type": "call_service", "domain": 5}).detail, None)

    def test_allowed_traffic_is_counted_by_type_in_the_summary_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = gp.RejectionLog(Path(tmp) / "run" / "rej.jsonl")
            forward, _ = gp.filter_ws_payload(json.dumps([{"id": 1, "type": "fenton_home/house_config/subscribe", "token": "SECRET"},
                                                          {"id": 2, "type": "get_states"}]))
            for label in gp.allowed_labels(forward):
                log.record_allowed("ws", label)
            log.record_allowed("ws", "get_states")
            log.record_allowed("http", gp.http_bucket("/api/states/light.secret?x=1"))
            text = (Path(tmp) / "run" / "allowed-summary.json").read_text()
        summary = json.loads(text)
        self.assertEqual(summary["ws"], {"fenton_home/house_config/subscribe": 1, "get_states": 2})
        self.assertEqual(summary["http"], {"/api/states": 1})
        self.assertNotIn("light.secret", text)

    def test_proxy_end_to_end_writes_the_summary_and_the_service_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            asyncio.run(ProxyEndToEndTests().scenario(Path(tmp) / "rej.jsonl"))
            summary = json.loads((Path(tmp) / "allowed-summary.json").read_text())
            rows = [json.loads(line) for line in (Path(tmp) / "rej.jsonl").read_text().splitlines()]
        self.assertEqual(summary["ws"], {"get_states": 1, "ping": 1})
        self.assertEqual(summary["http"], {"/api/config": 1})
        service = [r for r in rows if r["label"] == "call_service"][0]
        self.assertEqual((service["domain"], service["service"]), ("light", "turn_on"))


if __name__ == "__main__":
    unittest.main()
