"""Tests for live candidate staging: tools/parity_loop/stage.py, the candidate launch script, and the proxy reads it needs."""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from parity_loop import guard_proxy as gp  # noqa: E402
from parity_loop import identity, launch, stage, tls  # noqa: E402
from parity_loop.common import Result  # noqa: E402

LIVE = {"DEVCAP_HELD": "simulator", "PARITY_LIVE_GO": "1"}
TOKEN = "FAKE-TOKEN-VALUE-1234"
SERVER = "https://ha.example.invalid"
PARTITION_DIGEST = "061360d23f8d83ab0d03db3dc31451c58c90760ff2436e2c9ebfd956e76ce509"
CERT = Path(__file__)  # any existing file stands in for the certificate where nothing reads it
ASSET_A, ASSET_B = b"asset-a-bytes", b"asset-b-bytes"
SHA_A, SHA_B = hashlib.sha256(ASSET_A).hexdigest(), hashlib.sha256(ASSET_B).hexdigest()


def event(revision=7, assets=(SHA_A, SHA_B, SHA_A), state="published") -> dict:
    envelope = {"envelopeVersion": "1", "revision": revision,
                "document": {"id": "demo", "assets": [{"id": f"a{i}", "sha256": h.upper() if i == 1 else h} for i, h in enumerate(assets)]}}
    return {"state": state, "epoch": "e", "revision": revision, "envelope": envelope}


class FakeHA:
    """A loopback upstream: websocket auth + publication subscription, and the asset route. Records what reached it."""

    def __init__(self, published: dict, assets: dict) -> None:
        self.published, self.assets = published, assets
        self.ws_types, self.http_paths = [], []

    async def handle(self, reader, writer) -> None:
        head = (await reader.readuntil(b"\r\n\r\n")).decode()
        first = head.split("\r\n")[0]
        if "Upgrade: websocket" in head:
            key = [h.split(": ")[1] for h in head.split("\r\n") if h.startswith("Sec-WebSocket-Key")][0]
            writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                          f"Sec-WebSocket-Accept: {gp.accept_key(key)}\r\n\r\n").encode())

            async def say(message) -> None:
                writer.write(gp.encode_frame(1, json.dumps(message).encode(), False))
                await writer.drain()
            await say({"type": "auth_required"})
            try:
                while True:
                    _, opcode, data = await gp.read_frame(reader)
                    if opcode == 8:
                        break
                    message = json.loads(data)
                    self.ws_types.append(message["type"])
                    if message["type"] == "auth":
                        await say({"type": "auth_ok" if message["access_token"] == TOKEN else "auth_invalid"})
                    elif message["type"] == stage.SUBSCRIBE_COMMAND:
                        assert "capabilities" in message
                        await say({"id": message["id"], "type": "result", "success": True, "result": None})
                        await say({"id": message["id"], "type": "event", "event": self.published})
            except asyncio.IncompleteReadError:
                pass
        else:
            path = first.split(" ")[1]
            self.http_paths.append(path)
            body = self.assets.get(path.rsplit("/", 1)[-1])
            if body is None:
                writer.write(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
            else:
                writer.write(b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
        await writer.drain()
        writer.close()


class StageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def run_stage(self, published: dict, assets: dict, token: str = TOKEN, publication=None):
        out = {}
        bundle = tls.make_certificate(self.dir / "tls")

        async def go():
            ha = FakeHA(published, assets)
            upstream = await asyncio.start_server(ha.handle, "127.0.0.1", 0)
            log = gp.RejectionLog(self.dir / "run" / "rej.jsonl")
            proxy = gp.GuardProxy(gp.Upstream("127.0.0.1", upstream.sockets[0].getsockname()[1], False), log)
            server_ = await gp.serve(proxy, "127.0.0.1", 0, str(bundle.chain), str(bundle.key))
            url = f"https://127.0.0.1:{server_.sockets[0].getsockname()[1]}"
            out["ha"], out["log"], out["origin"] = ha, log, url
            try:
                out["summary"] = await stage.stage(url, self.dir / "container", token, "parity-loop", ["sh.page@1"], bundle.chain, publication)
            finally:
                await asyncio.sleep(0.05)
                server_.close()
                upstream.close()
        asyncio.run(go())
        return out

    def test_stages_bootstrap_publication_and_assets_through_the_proxy(self) -> None:
        out = self.run_stage(event(), {SHA_A: ASSET_A, SHA_B: ASSET_B})
        folder = self.dir / "container" / stage.PREVIEW_SUBPATH
        # the candidate is pointed at the guard proxy's origin, never the real server's
        self.assertEqual(json.loads((folder / "bootstrap.json").read_text()),
                         {"live": {"server": out["origin"], "accountID": "parity-loop"}})
        self.assertNotIn(SERVER, (folder / "bootstrap.json").read_text())
        envelope = (folder / "publication.json").read_bytes()
        self.assertEqual(json.loads(envelope)["revision"], 7)
        self.assertLessEqual(len(envelope), stage.MAX_ENVELOPE_BYTES)
        self.assertEqual(sorted(p.name for p in (folder / "assets").iterdir()), sorted([SHA_A, SHA_B]))
        self.assertEqual((folder / "assets" / SHA_B).read_bytes(), ASSET_B)
        self.assertEqual(out["summary"]["assets"], 2)
        self.assertEqual(out["ha"].ws_types, ["auth", stage.SUBSCRIBE_COMMAND, "unsubscribe_events"])
        self.assertEqual(sorted(out["ha"].http_paths), sorted([stage.ASSET_PATH + SHA_A, stage.ASSET_PATH + SHA_B]))
        self.assertEqual(out["log"].counts, {})  # nothing was refused: staging is all reads
        self.assertEqual(out["log"].allowed["ws"], {"auth": 1, stage.SUBSCRIBE_COMMAND: 1, "unsubscribe_events": 1})

    def test_a_local_publication_replaces_the_live_one_but_assets_still_come_through_the_proxy(self) -> None:
        local = self.dir / "draft.json"
        draft = event(revision=9, assets=(SHA_A,))["envelope"]
        draft["document"]["id"] = "demo_draft"
        local.write_text(json.dumps(draft))
        folder = self.dir / "container" / stage.PREVIEW_SUBPATH
        (folder / "publications" / "demo_partition").mkdir(parents=True)
        (folder / "publications" / "demo_partition" / "record.json").write_text("{}")
        out = self.run_stage(event(revision=7), {SHA_A: ASSET_A}, publication=local)
        self.assertFalse((folder / "publications" / "demo_partition").exists())  # the last-good a newer record would shadow is gone
        staged = json.loads((folder / "publication.json").read_text())
        self.assertEqual((staged["revision"], staged["document"]["id"]), (9, "demo_draft"))
        self.assertEqual((folder / "assets" / SHA_A).read_bytes(), ASSET_A)
        self.assertEqual(out["ha"].ws_types, [])  # the live subscription was never opened
        self.assertEqual(out["ha"].http_paths, [stage.ASSET_PATH + SHA_A])
        self.assertEqual(json.loads((folder / "bootstrap.json").read_text())["live"]["server"], out["origin"])

    def test_a_local_publication_that_is_not_an_envelope_fails(self) -> None:
        bad = self.dir / "bad.json"
        for text in ("not json", "[1]", json.dumps({"revision": "1", "document": {}})):
            bad.write_text(text)
            with self.assertRaises(stage.StageError):
                self.run_stage(event(), {}, publication=bad)
        with self.assertRaises(stage.StageError):
            self.run_stage(event(), {}, publication=self.dir / "missing.json")

    def test_no_file_holds_the_token(self) -> None:
        self.run_stage(event(), {SHA_A: ASSET_A, SHA_B: ASSET_B})
        for path in list(self.dir.rglob("*")):
            if path.is_file():
                self.assertNotIn(TOKEN.encode(), path.read_bytes(), str(path))

    def test_a_bad_asset_hash_a_missing_asset_and_a_missing_publication_fail(self) -> None:
        with self.assertRaises(stage.StageError):
            self.run_stage(event(), {SHA_A: b"tampered", SHA_B: ASSET_B})
        with self.assertRaises(stage.StageError):
            self.run_stage(event(), {SHA_A: ASSET_A})
        with self.assertRaises(stage.StageError):
            self.run_stage(event(state="none"), {})
        self.assertFalse((self.dir / "container" / stage.PREVIEW_SUBPATH / "bootstrap.json").exists())

    def test_a_rejected_token_fails(self) -> None:
        with self.assertRaises(stage.StageError):
            self.run_stage(event(), {SHA_A: ASSET_A, SHA_B: ASSET_B}, token="wrong")

    def test_a_plain_http_proxy_is_refused_before_any_traffic(self) -> None:
        with self.assertRaises(stage.StageError):
            asyncio.run(stage.stage("http://127.0.0.1:9", self.dir / "container", TOKEN, "a", ["sh.page@1"]))
        self.assertFalse((self.dir / "container").exists())

    def test_non_https_servers_are_refused_before_any_traffic(self) -> None:
        for server in ("http://ha.example.invalid", "https://user:pw@ha.example.invalid", "ha.example.invalid"):
            with self.assertRaises(stage.StageError):
                stage.origin_of(server)
        self.assertEqual(stage.origin_of("https://ha.example.invalid:8123/some/path?x=1"), "https://ha.example.invalid:8123")

    def test_envelope_checks(self) -> None:
        self.assertEqual(json.loads(stage.envelope_bytes(event()))["revision"], 7)
        for bad in (event(revision="7"), event(revision=True), event(state="rolledBack")):
            with self.assertRaises(stage.StageError):
                stage.envelope_bytes(bad)
        huge = event()
        huge["envelope"]["padding"] = "x" * stage.MAX_ENVELOPE_BYTES
        with self.assertRaises(stage.StageError):
            stage.envelope_bytes(huge)
        with self.assertRaises(stage.StageError):
            stage.asset_hashes({"document": {"assets": [{"sha256": "nothex"}]}})
        self.assertEqual(stage.asset_hashes(event()["envelope"]), [SHA_A, SHA_B])  # lowercased, distinct

    def test_every_stage_clears_the_persisted_last_good(self) -> None:
        folder = self.dir / "c" / stage.PREVIEW_SUBPATH
        record = folder / "publications" / stage.preview_partition_digest() / "record.json"
        for _ in range(2):  # a draft stage, then a live stage at a lower revision: no record is left to shadow it
            record.parent.mkdir(parents=True, exist_ok=True)
            record.write_text("{}")
            stage.write_container(self.dir / "c", SERVER, "a", b"{}", {})
            self.assertFalse(record.exists())
            self.assertTrue((folder / "publication.json").exists())
            # the partition directory is left private, as the asset stager requires, never as another writer's default mode
            partition = folder / "publications" / stage.preview_partition_digest()
            self.assertEqual(partition.stat().st_mode & 0o777, 0o700)

    def test_the_partition_digest_is_the_apps(self) -> None:
        # ServerUIDraftCompileTests asserts the same constant against ServerUIPublicationPartition.digest.
        self.assertEqual(stage.preview_partition_digest(),
                         hashlib.sha256(b"23:https://preview.invalid").hexdigest())
        self.assertEqual(stage.preview_partition_digest(), PARTITION_DIGEST)

    def test_restaging_clears_stale_assets_and_the_receipt(self) -> None:
        folder = self.dir / "c" / stage.PREVIEW_SUBPATH
        (folder / "assets").mkdir(parents=True)
        (folder / "assets" / "stale").write_text("x")
        (folder / "receipt.json").write_text("{}")
        stage.write_container(self.dir / "c", SERVER, "a", b"{}", {SHA_A: ASSET_A})  # any https origin names the bootstrap
        self.assertEqual([p.name for p in (folder / "assets").iterdir()], [SHA_A])
        self.assertFalse((folder / "receipt.json").exists())

    def test_the_default_capability_list_is_the_contract_corpus(self) -> None:
        caps = stage.load_capabilities()
        self.assertIn("sh.page@1", caps)
        self.assertTrue(all(c.startswith("sh.") for c in caps))

    def test_main_needs_the_token_in_its_environment_and_no_server(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(stage.main(["--proxy", "https://127.0.0.1:1", "--container", str(self.dir)]), 2)
        self.assertNotIn("FENTON_HASS_SERVER", [l for l in Path(stage.__file__).read_text().splitlines() if "environ" in l][0])


class ProxyAllowsTheStagingReadsTests(unittest.TestCase):
    def test_publication_subscribe_unsubscribe_and_assets_are_reads(self) -> None:
        for kind in (stage.SUBSCRIBE_COMMAND, "unsubscribe_events", "auth"):
            self.assertTrue(gp.ws_decide({"id": 1, "type": kind}).allowed, kind)
        self.assertTrue(gp.http_decide("GET", stage.ASSET_PATH + SHA_A).allowed)
        for method in ("POST", "PUT", "DELETE", "PATCH"):
            self.assertFalse(gp.http_decide(method, stage.ASSET_PATH + SHA_A).allowed, method)
        for kind in ("fenton_home/ui_publication/publish", "fenton_home/ui_publication/rollback", "fenton_home/ui_assets/upload"):
            self.assertFalse(gp.ws_decide({"id": 1, "type": kind}).allowed, kind)


class CandidateLaunchTests(unittest.TestCase):
    def test_the_script_passes_a_local_publication_only_when_one_is_named(self) -> None:
        self.assertIn('${STAGE_PUBLICATION:+--publication "$STAGE_PUBLICATION"}', launch.candidate_live_script("UDID-1"))

    def test_launch_live_candidate_hands_the_draft_to_the_stage(self) -> None:
        seen = []

        def runner(argv, env=None, timeout=0):
            seen.append(env)
            return Result(0, "/sim/data\n") if argv[:3] == ["xcrun", "simctl", "get_app_container"] else Result(0)
        launch.launch_live("candidate", "UDID-1", "https://127.0.0.1:9", runner, LIVE, proxy_cert=CERT, publication=Path(__file__))
        self.assertEqual(seen[-1]["STAGE_PUBLICATION"], str(Path(__file__)))
        with self.assertRaises(launch.Refused):
            launch.launch_live("candidate", "UDID-1", "https://127.0.0.1:9", runner, LIVE, proxy_cert=CERT, publication=Path("/nope.json"))

    def test_a_draft_is_refused_for_the_reference_and_never_inherited(self) -> None:
        seen = []

        def runner(argv, env=None, timeout=0):
            seen.append(env)
            return Result(0, "/sim/data\n") if argv[:3] == ["xcrun", "simctl", "get_app_container"] else Result(0)
        with self.assertRaises(launch.Refused):
            launch.launch_live("reference", "UDID-1", "https://127.0.0.1:9", runner, LIVE, proxy_cert=CERT, publication=Path(__file__))
        self.assertEqual(seen, [])
        stale = dict(LIVE, STAGE_PUBLICATION="/stale/draft.json")
        launch.launch_live("candidate", "UDID-1", "https://127.0.0.1:9", runner, stale, proxy_cert=CERT)
        self.assertNotIn("STAGE_PUBLICATION", seen[-1])
        launch.launch_live("reference", "UDID-1", "https://127.0.0.1:9", runner, stale, proxy_cert=CERT)
        self.assertNotIn("STAGE_PUBLICATION", seen[-1])

    def test_the_script_stages_then_launches_the_preview_with_the_token_in_env_only(self) -> None:
        script = launch.candidate_live_script("UDID-1")
        self.assertLess(script.index("stage.py"), script.index("simctl launch"))
        self.assertIn("hass_load_creds", script)
        self.assertIn('SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN="$FENTON_HASS_TOKEN"', script)
        self.assertIn("--server-ui-preview", script)
        self.assertNotIn("FENTON_HASS_SERVER", script)  # the real server's address never reaches the stage or the app
        self.assertIn('--chain "$PROXY_CHAIN"', script)  # stage pins the proxy's own leaf certificate
        self.assertNotIn("ha-credential", script)
        self.assertNotIn(">", script.replace(">/dev/null", "").replace(">&2", "").replace("2>&1", ""))  # no redirect writes a file

    def test_launch_live_candidate_stages_into_the_container_through_the_proxy(self) -> None:
        seen = []

        def runner(argv, env=None, timeout=0):
            seen.append((list(argv), env))
            if argv[:3] == ["xcrun", "simctl", "get_app_container"]:
                return Result(0, "/sim/data\n")
            return Result(0)
        launch.launch_live("candidate", "UDID-1", "https://127.0.0.1:9", runner, LIVE, proxy_cert=CERT)
        argv, env = seen[-1]
        self.assertEqual(argv[:2], ["bash", "-c"])
        self.assertEqual((env["PROXY_URL"], env["CONTAINER_DATA"]), ("https://127.0.0.1:9", "/sim/data"))
        self.assertEqual(Path(env["PROXY_CHAIN"]).name, "proxy-chain.crt")
        # the simulator trusts the proxy's certificate before the app is launched
        trust = [a for a, _ in seen if a[:3] == ["xcrun", "simctl", "keychain"]]
        self.assertEqual(trust, [["xcrun", "simctl", "keychain", "UDID-1", "add-root-cert", str(CERT)]])
        self.assertIn("--server-ui-preview", argv[2])

    def test_candidate_launch_refuses_without_the_go_and_runs_nothing(self) -> None:
        calls = []
        runner = lambda argv, env=None, timeout=0: calls.append(argv) or Result(0)  # noqa: E731
        with self.assertRaises(launch.Refused):
            launch.launch_live("candidate", "UDID", "https://127.0.0.1:9", runner, {}, proxy_cert=CERT)
        self.assertEqual(calls, [])

    def test_a_failed_staging_is_a_refusal_without_output(self) -> None:
        def runner(argv, env=None, timeout=0):
            return Result(0, "/sim/data\n") if argv[1:3] == ["simctl", "get_app_container"] else Result(1, "", "boom")
        with self.assertRaises(launch.Refused) as caught:
            launch.launch_live("candidate", "UDID", "https://127.0.0.1:9", runner, LIVE, proxy_cert=CERT)
        self.assertNotIn("boom", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
