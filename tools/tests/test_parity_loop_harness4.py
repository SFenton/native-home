"""Tests for the parity-loop iter1 harness fixes (H1 to H6): status-bar ring, rail masks, leaf-only masks, AX compare, user identity.

The proxy widening and the staged proxy origin are tested in ``test_parity_loop_proxy.py`` and ``test_parity_loop_stage.py``.
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import expo_pair_compare as epc  # noqa: E402
from parity_loop import capture, guard_proxy as gp, identity, launch, sidecar, tls  # noqa: E402
from parity_loop.common import Result, read_json  # noqa: E402
from parity_loop_fakes import FakeWorld, solid  # noqa: E402

SURFACES = read_json(Path(__file__).resolve().parents[1] / "parity_loop" / "surfaces.json")
BY_ID = {s["id"]: s for s in SURFACES["surfaces"]}
WHITE = (255, 255, 255)
#: A Duo-wide frame at density 1, so the profile rectangles (points) are also pixels.
DUO = (466, 300)
RING = ((400, 110, 430, 140), WHITE)  # inside the rail ring rectangle (x 397-439, y 107-142)
DISC = ((402, 32, 432, 62), WHITE)  # inside the rail disc rectangle (x 398-437, y 28-67)
CLOCK = ((400, 85, 430, 100), WHITE)  # inside the clock rectangle (x 394-440, y 82-102)
PAGE = ((50, 150, 150, 200), WHITE)  # page content, outside every rail rectangle


def args(**over: object) -> argparse.Namespace:
    base = dict(tolerance=8, max_diff_percent=1.0, max_block_percent=0.25, status_bar_pt=54.0, home_indicator_pt=34.0,
                require_sidecar=False, drift=True, require_ax=False, status_bar_equal=True, status_bar_max_percent=0.5)
    base.update(over)
    return argparse.Namespace(**base)


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def duo_spec(self, ref=(), cand=(), ref2=(), **extra: object) -> dict:
        spec = {"id": "p", "capture": "p", "state": "", "reference_png": solid(self.dir / "r.png", paint=ref, size=DUO),
                "candidate_png": solid(self.dir / "c.png", paint=cand, size=DUO), "reference2_png": solid(self.dir / "r2.png", paint=ref2, size=DUO),
                "reference_ax": None, "candidate_ax": None, "density": 1.0, "live_regions": [], "problems": [], "sidecars": {},
                "ax_files": {}, "mask_files": [], "device": "duo"}
        spec.update(extra)
        return spec


# MARK: - H1: the status bar compares the clock only

class StatusBarRingTests(Base):
    def test_a_pair_that_differs_only_inside_the_ring_rectangle_passes(self) -> None:
        record = epc.judge(self.duo_spec(cand=(RING,), ref2=()), self.dir, args())
        self.assertEqual((record["verdict"], record["failures"]), ("pass", []))
        self.assertEqual(record["statusBarDifferencePercent"], 0.0)
        # the second reference shot may sit at another animation phase too
        self.assertEqual(epc.judge(self.duo_spec(ref2=(RING,)), self.dir, args())["verdict"], "pass")

    def test_the_same_ring_difference_fails_where_no_profile_masks_it(self) -> None:
        record = epc.judge(self.duo_spec(cand=(RING,), device=None), self.dir, args(status_bar_equal=False, drift=False))
        self.assertEqual(record["verdict"], "fail")  # the control: the mask, not the image, makes the pair pass

    def test_a_pair_that_differs_in_the_clock_fails(self) -> None:
        record = epc.judge(self.duo_spec(cand=(CLOCK,)), self.dir, args())
        self.assertEqual(record["verdict"], "statusbar")
        self.assertGreater(record["statusBarDifferencePercent"], 0.5)
        self.assertIn("status bar differs between the halves (normalisation failed)", record["failures"])

    def test_every_profile_compares_only_the_clock(self) -> None:
        for profile in ("duo", "iphone", "ipad"):
            self.assertEqual([i[0] for i in epc.STATUS_BAR_ITEMS[profile]], ["clock"])
        self.assertEqual(epc.rail_mask_rects("iphone", DUO, 1.0), [])
        self.assertEqual(epc.rail_mask_rects(None, DUO, 1.0), [])


# MARK: - H2: drift measures page content

class RailMaskTests(Base):
    def test_a_disc_or_ring_between_two_reference_shots_is_not_drift(self) -> None:
        for paint in ((DISC,), (RING,), (DISC, RING)):
            record = epc.judge(self.duo_spec(ref2=paint), self.dir, args())
            self.assertEqual((record["verdict"], record["drift"]["changedPixels"]), ("pass", 0), paint)
            self.assertEqual(record["maskProposals"], [])  # no one-pixel mask proposals for the rail

    def test_page_content_still_drifts(self) -> None:
        record = epc.judge(self.duo_spec(ref2=(PAGE,)), self.dir, args())
        self.assertEqual(record["verdict"], "drift")
        self.assertEqual(record["drift"]["differenceBounds"], [50, 150, 150, 200])

    def test_the_rectangles_cover_the_measured_pixels_at_the_duo_scale(self) -> None:
        # measured on read-only live shots (3x, 1398 x 2034): the union of differing pixels, inclusive-exclusive
        measured = {"rail-ring": (1193, 322, 1316, 424), "rail-disc": (1198, 87, 1311, 200)}
        rects = dict(epc.rail_mask_rects("duo", (1398, 2034), 3.0))
        self.assertEqual(sorted(rects), sorted(measured))
        for name, (x0, y0, x1, y1) in measured.items():
            rx0, ry0, rx1, ry1 = rects[name]
            self.assertTrue(rx0 <= x0 and ry0 <= y0 and rx1 >= x1 and ry1 >= y1, (name, rects[name]))
            self.assertLess(rx0, x0 + 6)  # snug: no more than a few pixels of margin
            self.assertLess(y0 - ry0, 6)
        clock = dict(epc.status_bar_rects("duo", (1398, 2034), 3.0))["clock"]
        for name, rect in rects.items():  # the rail masks never swallow the clock that is compared
            self.assertTrue(rect[3] <= clock[1] or rect[1] >= clock[3], name)

    def test_the_masks_are_reported_in_the_pair_record(self) -> None:
        record = epc.judge(self.duo_spec(), self.dir, args())
        self.assertEqual([m["label"] for m in record["masks"]][-2:], ["rail-disc", "rail-ring"])


# MARK: - H3: masks come from leaf nodes only

def node(depth, label=None, rect=(0, 0, 10, 10), **extra):
    out = {"depth": depth, "rect": dict(zip(("x", "y", "width", "height"), rect)), "type": "Other", **extra}
    if label is not None:
        out["label"] = label
    return out


WEATHER_RULE = {"label": "weather", "ax_match": r"(?i)weather|forecast|°"}


class LeafMaskTests(Base):
    def nested_card(self):
        return [
            node(2, None, (16, 162, 350, 353), identifier="hc-weather-summary"),  # an identifier-only container: never a mask
            node(3, "Weather card", (16, 162, 350, 353)),  # an ancestor whose descendants also match
            node(4, "Open forecast. Sunny, 50°F", (32, 178, 318, 99), type="Button"),
            node(4, "Today Sunny H:52°  L:40°", (32, 256, 207, 21), type="StaticText"),
            node(4, None, (32, 370, 318, 81), identifier="home.weather.carousel"),
            node(5, "Now Partly Cloudy 51°F", (32, 370, 53, 81)),
            node(5, "1 PM Sunny 52°F", (85, 370, 53, 81)),
            node(2, "Chores", (16, 600, 100, 40)),
        ]

    def test_a_nested_weather_card_masks_the_leaves_only(self) -> None:
        regions = capture.resolve_masks(self.nested_card(), [WEATHER_RULE])
        boxes = [(r["x"], r["y"], r["width"], r["height"]) for r in regions]
        self.assertEqual(boxes, [(32, 178, 318, 99), (32, 256, 207, 21), (32, 370, 53, 81), (85, 370, 53, 81)])
        self.assertNotIn((16, 162, 350, 353), boxes)  # not the card

    def test_the_cap_applies_to_the_union_of_the_leaf_boxes(self) -> None:
        regions = capture.resolve_masks(self.nested_card(), [WEATHER_RULE])
        leaf = epc.masked_percent((466, 678), 1.0, regions)
        everything = epc.masked_percent((466, 678), 1.0, regions + [{"x": 16, "y": 162, "width": 350, "height": 353, "unit": "pt"}])
        self.assertAlmostEqual(leaf, 100.0 * (318 * 99 + 2 * 53 * 81) / (466 * 678), places=3)  # a union: "Today" lies inside the first
        self.assertLess(leaf, 15.0)  # under the cap
        self.assertGreater(everything, 15.0)  # the old ancestor-union blew it (27.9% on the baseline Home)

    def test_the_same_box_found_twice_is_kept_once_and_unlabelled_nodes_never_match_by_identifier(self) -> None:
        nodes = [node(1, "Sunny 50°F", (0, 0, 10, 10)), node(1, "Sunny 50°F", (0, 0, 10, 10)), node(1, None, (0, 20, 10, 10), identifier="home.weather")]
        self.assertEqual(len(capture.resolve_masks(nodes, [WEATHER_RULE])), 1)

    def test_without_depths_containment_decides_the_ancestor(self) -> None:
        nodes = [{k: v for k, v in n.items() if k != "depth"} for n in self.nested_card()]
        boxes = [(r["x"], r["y"], r["width"], r["height"]) for r in capture.resolve_masks(nodes, [WEATHER_RULE])]
        self.assertNotIn((16, 162, 350, 353), boxes)
        self.assertEqual(len(boxes), 3)  # conservative: a match that merely lies inside another match is taken for its descendant

    def test_the_camera_rule_matches_the_tiles_not_the_heading(self) -> None:
        nodes = [node(2, None, (16, 531, 350, 147), identifier="hc-home-cameras"),
                 node(3, "Cameras", (16, 531, 350, 24), type="StaticText"),
                 node(3, None, (16, 567, 350, 111), identifier="hc-home-camera-grid"),
                 node(4, None, (16, 567, 169, 111), identifier="hc-camera-0-tile"),
                 node(5, "Front Door", (16, 567, 169, 111), type="Button", identifier="hc-camera-0-tile", value="Live"),
                 node(4, None, (197, 567, 169, 111), identifier="hc-camera-1-tile"),
                 node(5, "Driveway", (197, 567, 169, 111), type="Button", identifier="hc-camera-1-tile", value="Live")]
        for rule in [m for m in BY_ID["home"]["masks"] if m["label"] == "camera-feed"]:
            boxes = [(r["x"], r["y"], r["width"], r["height"]) for r in capture.resolve_masks(nodes, [rule])]
            self.assertEqual(boxes, [(16, 567, 169, 111), (197, 567, 169, 111)])
        self.assertEqual(len([m for m in BY_ID["home"]["masks"] if m["label"] == "camera-feed"]), 1)
        # a tile found by its value alone still counts, wherever the app puts its identifier
        by_value = capture.resolve_masks([node(1, "Garage", (0, 0, 50, 50), value="Live")], [{"label": "camera-feed", "ax_value": "^Live$"}])
        self.assertEqual(len(by_value), 1)

    def test_label_less_dynamic_rules_still_work_and_a_rule_needs_one_criterion(self) -> None:
        clock = [node(1, "9:41", (1, 5, 20, 10))]
        self.assertEqual(capture.resolve_masks(clock, [{"label": "clock", "ax_match": r"^\d{1,2}:\d{2}$"}])[0]["label"], "clock")
        self.assertEqual(capture.resolve_masks(clock, [{"label": "none"}]), [])


# MARK: - H5: the AX compare is about what a person perceives

def row(label="A", role="Button", frame=(10, 20, 100, 40), **extra):
    return {"role": role, "label": label, "value": "", "enabled": True, "selected": False, "traits": [], "frame": list(frame), **extra}


class AxCompareTests(Base):
    def test_identifier_only_nodes_scroll_bars_and_the_status_bar_are_dropped(self) -> None:
        nodes = [node(0, None, (0, 0, 466, 678), identifier="home.scroll"),
                 node(1, "Vertical scroll bar, 2 pages", (349, 82, 30, 596), value="0%"),
                 node(1, "Horizontal scroll bar, 1 page", (0, 600, 30, 10)),
                 node(1, "9:41", (0, 5, 40, 10)),
                 node(1, "Chores", (10, 80, 40, 20), type="Button", identifier="nav.chores"),
                 node(1, None, (10, 120, 40, 20), identifier="slider", value="50%")]
        rows = capture.normalize_ax(nodes)
        self.assertEqual([r["label"] for r in rows], ["Chores", ""])  # a node with a value but no label is a control, kept
        self.assertEqual(rows[0]["frame"], [10, 80, 40, 20])

    def test_identifiers_are_not_recorded_and_do_not_name_a_node(self) -> None:
        a = capture.normalize_ax([node(1, "Chores", (10, 80, 40, 20), type="Button", identifier="nav.chores")])
        b = capture.normalize_ax([node(1, "Chores", (10, 80, 40, 20), type="Button", identifier="tab-chores")])
        self.assertEqual(a, b)
        self.assertNotIn("nav.chores", json.dumps(a))
        weather_id = capture.normalize_ax([node(1, None, (0, 0, 5, 5), identifier="home.weather")], [WEATHER_RULE])
        self.assertEqual(weather_id, [])  # not matched through its identifier, and dropped as identifier-only

    def test_frames_within_the_tolerance_are_equal_and_beyond_it_are_not(self) -> None:
        first = [row("A", frame=(10, 20, 100, 40)), row("B", frame=(10, 70, 100, 40))]
        within = [row("A", frame=(11.5, 18.5, 101.9, 41.9)), row("B", frame=(10, 70, 100, 40))]
        self.assertEqual(epc.compare_ax_sequences(first, within), (True, mock.ANY))
        moved = [row("A", frame=(10, 24, 100, 40)), row("B", frame=(10, 70, 100, 40))]  # the 4 pt top offset
        equal, diff = epc.compare_ax_sequences(first, moved)
        self.assertFalse(equal)
        self.assertEqual((diff["firstDifference"], diff["frameOnly"], diff["onlyFirst"]), (0, 1, 0))
        self.assertTrue(epc.compare_ax_sequences(first, moved, frame_tolerance=4.0)[0])
        wider = [row("A", frame=(10, 20, 100, 43)), row("B")]
        self.assertFalse(epc.compare_ax_sequences(first, wider)[0])  # size counts, not just position
        self.assertEqual(epc.AX_FRAME_TOLERANCE_PT, 2.0)

    def test_labels_roles_traits_values_and_order_still_differ(self) -> None:
        first = [row("A"), row("B", frame=(10, 70, 100, 40))]
        self.assertFalse(epc.compare_ax_sequences(first, [row("A"), row("C", frame=(10, 70, 100, 40))])[0])
        self.assertFalse(epc.compare_ax_sequences(first, [row("A", role="Other"), first[1]])[0])
        self.assertFalse(epc.compare_ax_sequences(first, [row("A", traits=["selected"]), first[1]])[0])
        self.assertFalse(epc.compare_ax_sequences(first, [first[1], first[0]])[0])
        self.assertFalse(epc.compare_ax_sequences(first, first[:1])[0])

    def test_rows_without_frames_compare_on_their_other_fields(self) -> None:
        old = [row("A", frame=(1, 1, 1, 1))]
        bare = [dict(row("A"), frame=None)]
        self.assertTrue(epc.compare_ax_sequences(old, bare)[0])

    def test_the_judge_fails_a_pair_whose_frame_moved_and_names_it(self) -> None:
        def write(name, rows):
            path = self.dir / name
            path.write_text(json.dumps({"normalized": rows}))
            return path
        files = {"reference": write("a.json", [row("A")]), "candidate": write("b.json", [row("A", frame=(10, 25, 100, 40))]),
                 "reference2": write("c.json", [row("A")])}
        record = epc.judge(self.duo_spec(ax_files=files), self.dir, args(require_ax=True, status_bar_equal=False))
        self.assertEqual(record["verdict"], "fail")
        self.assertIn("1 moved more than 2 pt", " ".join(record["failures"]))
        wide = epc.judge(self.duo_spec(ax_files=files), self.dir, args(require_ax=True, status_bar_equal=False, ax_frame_tolerance=6.0))
        self.assertEqual(wide["verdict"], "pass")

    def test_a_real_capture_normalises_to_comparable_rows(self) -> None:
        world = FakeWorld(self.dir / "w")
        world.nodes["reference"] = world.nodes["candidate"] = [
            {"type": "Button", "label": "Chores", "identifier": "nav.chores", "rect": {"x": 10, "y": 80, "width": 40, "height": 20}},
            {"type": "Other", "identifier": "wrapper", "rect": {"x": 0, "y": 0, "width": 120, "height": 200}},
            {"type": "Other", "label": "Vertical scroll bar, 3 pages", "value": "0%", "rect": {"x": 100, "y": 0, "width": 20, "height": 200}}]
        shot = capture.capture_shot(capture.Agent("fake-agent reference", world), self.dir / "out", "reference")
        saved = read_json(shot.ax)
        self.assertEqual([r["label"] for r in saved["normalized"]], ["Chores"])
        self.assertEqual(saved["labels"], ["Chores", "Vertical scroll bar, 3 pages"])
        self.assertNotIn("nav.chores", json.dumps(saved["normalized"]))


# MARK: - H6: the sidecar records which user the token resolves to

class FakeUserHA:
    """An upstream that answers ``auth`` and ``auth/current_user`` and records what it was asked."""

    def __init__(self, token: str, user_id: str, name: str) -> None:
        self.token, self.user_id, self.name, self.types = token, user_id, name, []

    async def handle(self, reader, writer) -> None:
        head = (await reader.readuntil(b"\r\n\r\n")).decode()
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
                self.types.append(message["type"])
                if message["type"] == "auth":
                    await say({"type": "auth_ok" if message["access_token"] == self.token else "auth_invalid"})
                elif message["type"] == "auth/current_user":
                    await say({"id": message["id"], "type": "result", "success": True,
                               "result": {"id": self.user_id, "name": self.name, "is_owner": True, "is_admin": True}})
        except asyncio.IncompleteReadError:
            pass
        writer.close()


class UserIdentityTests(Base):
    TOKEN, USER, NAME = "FAKE-TOKEN-5678", "0123456789abcdef0123456789abcdef", "Pat Example"

    def resolve(self, token: str = TOKEN):
        out = {}
        bundle = tls.make_certificate(self.dir / "tls")

        async def go() -> None:
            ha = FakeUserHA(self.TOKEN, self.USER, self.NAME)
            upstream = await asyncio.start_server(ha.handle, "127.0.0.1", 0)
            log = gp.RejectionLog(self.dir / "run" / "rej.jsonl")
            proxy = gp.GuardProxy(gp.Upstream("127.0.0.1", upstream.sockets[0].getsockname()[1], False), log)
            server = await gp.serve(proxy, "127.0.0.1", 0, str(bundle.chain), str(bundle.key))
            port = server.sockets[0].getsockname()[1]
            out["ha"], out["log"], out["url"] = ha, log, f"https://127.0.0.1:{port}"
            try:
                out["digest"] = await identity.current_user_hash("127.0.0.1", port, token, identity.client_context("https", bundle.chain))
            except identity.IdentityError as error:
                out["error"] = str(error)
            finally:
                await asyncio.sleep(0.05)
                server.close()
                upstream.close()
        asyncio.run(go())
        out["cert"] = bundle.ca
        return out

    def test_the_hash_of_the_user_id_comes_back_through_the_proxy_and_nothing_else(self) -> None:
        out = self.resolve()
        self.assertEqual(out["digest"], hashlib.sha256(self.USER.encode()).hexdigest())
        self.assertNotIn(self.USER, out["digest"])
        self.assertEqual(out["ha"].types, ["auth", "auth/current_user"])
        self.assertEqual(out["log"].counts, {})  # auth/current_user is a read the proxy already allows
        self.assertEqual(out["log"].allowed["ws"], {"auth": 1, "auth/current_user": 1})

    def test_a_rejected_token_names_no_secret(self) -> None:
        out = self.resolve(token="wrong")
        self.assertNotIn("digest", out)
        self.assertNotIn("wrong", out["error"])

    def test_main_prints_one_hash_line_and_never_the_name_or_token(self) -> None:
        async def fake(host, port, token, context=None, timeout=20.0):
            self.assertEqual((host, port, token), ("127.0.0.1", 8443, "TOK"))
            return identity.user_id_hash(self.USER)
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, {"FENTON_HASS_TOKEN": "TOK"}, clear=True), mock.patch.object(identity, "current_user_hash", fake), \
                redirect_stdout(out), redirect_stderr(err):
            self.assertEqual(identity.main(["--proxy", "https://127.0.0.1:8443", "--chain", str(tls.make_certificate(self.dir / "t").chain)]), 0)
        self.assertEqual(out.getvalue(), hashlib.sha256(self.USER.encode()).hexdigest() + "\n")
        self.assertNotIn(self.NAME, out.getvalue() + err.getvalue())
        self.assertNotIn("TOK", out.getvalue() + err.getvalue())
        with mock.patch.dict(os.environ, {}, clear=True), redirect_stderr(err):
            self.assertEqual(identity.main(["--proxy", "https://127.0.0.1:8443"]), 2)

    def test_the_pin_refuses_another_certificate_and_an_https_proxy_without_a_chain(self) -> None:
        mine, other = tls.make_certificate(self.dir / "a"), tls.make_certificate(self.dir / "b")
        pinned = identity.client_context("https", mine.chain)
        with self.assertRaises(identity.StageError):
            identity.client_context("https", other.chain).check(b"not the pinned certificate")
        with self.assertRaises(identity.StageError):
            pinned.check(None)
        with self.assertRaises(identity.StageError):
            identity.client_context("https", None)
        self.assertIsNone(identity.client_context("http", None))
        self.assertNotEqual(pinned.sha256, identity.client_context("https", other.chain).sha256)

    def test_the_sidecar_records_the_hash_and_a_mismatch_refuses_the_pair(self) -> None:
        world = FakeWorld(self.dir / "world")
        cars = {side: sidecar.collect(world.udid[side], side, png=solid(self.dir / f"{side}.png"), scale=1, appearance="dark", runner=world,
                                      extra={"userIdHash": hashlib.sha256(b"u1").hexdigest()}) for side in ("reference", "candidate")}
        self.assertEqual(cars["reference"]["userIdHash"], hashlib.sha256(b"u1").hexdigest())
        self.assertEqual(sorted(k for k in cars["reference"] if "user" in k.lower()), ["userIdHash"])  # no id, no name
        self.assertEqual(sidecar.compare(cars["reference"], cars["candidate"]), [])
        other = dict(cars["candidate"], userIdHash=hashlib.sha256(b"u2").hexdigest())
        self.assertTrue(any("userIdHash differs" in p for p in sidecar.compare(cars["reference"], other)))
        unrecorded = {k: v for k, v in cars["candidate"].items() if k != "userIdHash"}
        self.assertEqual(sidecar.compare(cars["reference"], unrecorded), [])  # fixture runs record none


# MARK: - The throwaway certificate

class CertificateTests(Base):
    def openssl(self, *argv: str) -> str:
        import subprocess
        return subprocess.run(["openssl", *argv], capture_output=True, text=True).stdout

    def test_a_certificate_is_made_at_run_time_with_a_private_key(self) -> None:
        bundle = tls.make_certificate(self.dir / "run")
        self.assertEqual((bundle.ca.name, bundle.chain.name, bundle.key.name), (tls.CA_NAME, tls.CHAIN_NAME, tls.KEY_NAME))
        self.assertTrue(bundle.ca.read_text().startswith("-----BEGIN CERTIFICATE-----"))
        self.assertEqual(bundle.chain.read_text().count("BEGIN CERTIFICATE"), 2)  # the leaf and its CA
        self.assertEqual(stat.S_IMODE(bundle.key.stat().st_mode), 0o600)
        self.assertEqual(sorted(p.name for p in (self.dir / "run").iterdir()), sorted([tls.CA_NAME, tls.CHAIN_NAME, tls.KEY_NAME]))  # no CA key
        self.assertIn("OK", self.openssl("verify", "-CAfile", str(bundle.ca), str(bundle.chain)))

    def test_the_trusted_root_carries_a_critical_name_constraint_for_loopback_only(self) -> None:
        bundle = tls.make_certificate(self.dir / "run")
        text = self.openssl("x509", "-in", str(bundle.ca), "-noout", "-text")
        self.assertIn("X509v3 Name Constraints: critical", text)
        self.assertIn("IP:127.0.0.1/255.255.255.255", text)
        self.assertIn("DNS:localhost", text)
        self.assertIn("CA:TRUE", text)
        leaf = self.openssl("x509", "-in", str(bundle.chain), "-noout", "-text")
        self.assertIn("CA:FALSE", leaf)
        self.assertIn("IP Address:127.0.0.1", leaf)

    def test_the_leaf_key_is_deleted_when_the_proxy_exits(self) -> None:
        bundle = tls.make_certificate(self.dir / "run")
        process = mock.Mock()
        process.wait.return_value = 3
        with mock.patch("parity_loop.launch.subprocess.Popen", return_value=process):
            self.assertEqual(launch.supervise(["true"], {}, bundle), 3)
        self.assertFalse(bundle.key.exists())
        self.assertTrue(bundle.ca.is_file())  # the certificates stay for the run's evidence; only the private key goes
        bundle = tls.make_certificate(self.dir / "run2")
        process.wait.side_effect = KeyboardInterrupt
        with mock.patch("parity_loop.launch.subprocess.Popen", return_value=process), self.assertRaises(KeyboardInterrupt):
            launch.supervise(["true"], {}, bundle)
        self.assertFalse(bundle.key.exists())  # also when it ends abnormally

    def test_a_failed_openssl_leaves_no_key_behind(self) -> None:
        with self.assertRaises(tls.CertificateError):
            tls.make_certificate(self.dir / "run", lambda argv, env=None, timeout=0: Result(1, "", "boom"))
        self.assertFalse((self.dir / "run" / tls.KEY_NAME).exists())

    def test_no_certificate_or_key_is_committed(self) -> None:
        import subprocess
        root = Path(__file__).resolve().parents[2]
        tracked = subprocess.run(["git", "-C", str(root), "ls-files"], capture_output=True, text=True).stdout.split("\n")
        self.assertEqual([p for p in tracked if p.endswith((tls.CA_NAME, tls.CHAIN_NAME, tls.KEY_NAME))], [])


class PerHalfIdentityTests(Base):
    def test_halves_signed_in_as_different_users_are_flagged(self) -> None:
        from parity_loop import run as plrun
        from parity_loop import launch as launch_mod
        world = FakeWorld(self.dir / "world")
        pin = sidecar.bundle_identity(self.dir / "world" / "reference" / "App.app")
        pin_path = self.dir / "pin.json"
        pin_path.write_text(json.dumps({"bundleSHA256": pin}))
        halves = {s: plrun.Half(s, world.udid[s], capture.Agent(f"fake-agent {s}", world)) for s in ("reference", "candidate")}
        plrun.DEVICES["test"] = {"scale": 1, "pose": "folded", "size": [120, 200]}
        asked = []

        def runner(argv, env=None, timeout=0):
            if argv[0] == "bash" and "identity.py" in argv[2]:
                side = "candidate" if "FENTON_PREVIEW_HA_TOKEN" in argv[2] else "reference"
                asked.append(side)
                return Result(0, hashlib.sha256(side.encode()).hexdigest() + "\n")  # each half's session resolves to another user
            return world(argv, env, timeout)
        ctx = plrun.Context(self.dir / "run", "live", "test", halves, runner=runner, proxy_url="https://127.0.0.1:9", proxy_cert=Path(__file__))
        surfaces = plrun.select(read_json(plrun.SURFACES_FILE), ["chores"])
        status = plrun.run_all(ctx, surfaces, pin, env={"DEVCAP_HELD": "simulator", "PARITY_LIVE_GO": "1"}, pin_path=pin_path)
        self.assertEqual(sorted(asked), ["candidate", "reference"])  # one lookup per half, each with its own token variable
        self.assertEqual(status, 2)
        row = read_json(self.dir / "run" / "results.json")[0]
        self.assertEqual(row["verdict"], "refused")
        self.assertTrue(any("userIdHash differs" in f for f in row["failures"]))
        cars = {s: read_json(self.dir / "run" / "chores" / f"{s}.sidecar.json") for s in ("reference", "candidate")}
        self.assertNotEqual(cars["reference"]["userIdHash"], cars["candidate"]["userIdHash"])

    def test_the_candidate_identity_script_uses_the_preview_token_variable(self) -> None:
        from parity_loop import launch as launch_mod
        self.assertIn("FENTON_PREVIEW_HA_TOKEN", launch_mod.identity_script("candidate"))
        self.assertNotIn("FENTON_PREVIEW_HA_TOKEN", launch_mod.identity_script("reference"))


if __name__ == "__main__":
    unittest.main()
