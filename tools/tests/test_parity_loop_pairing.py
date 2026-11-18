"""Tests for the pairing round (S5): gallery variables, the corrected pairings, wrong-page, status-bar precedence, the sidecar, iPad reach."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import expo_pair_compare as epc  # noqa: E402
from parity_loop import build_surfaces, capture, launch, run as plrun, sidecar  # noqa: E402
from parity_loop.common import read_json  # noqa: E402
from parity_loop_fakes import FakeWorld, solid  # noqa: E402

SURFACES = read_json(Path(plrun.SURFACES_FILE))
BY_ID = {s["id"]: s for s in SURFACES["surfaces"]}
BIG = ((10, 100, 110, 190), (200, 40, 40))
plrun.DEVICES["test"] = {"scale": 1, "pose": "folded", "size": [120, 200]}


def args(**over: object) -> argparse.Namespace:
    base = dict(tolerance=8, max_diff_percent=1.0, max_block_percent=0.25, status_bar_pt=54.0, home_indicator_pt=34.0,
                require_sidecar=False, drift=False, require_ax=False, status_bar_equal=False, status_bar_max_percent=0.5)
    base.update(over)
    return argparse.Namespace(**base)


def tree(path: Path, title: str, extra: list = ()) -> Path:
    nodes = [{"index": 0, "type": "Application", "rect": {"x": 0, "y": 0, "width": 100, "height": 200}},
             {"index": 1, "type": "NavigationBar", "role": "UINavigationBar", "identifier": title, "parentIndex": 0, "rect": {"x": 0, "y": 20, "width": 100, "height": 50}},
             {"index": 2, "type": "StaticText", "label": title, "parentIndex": 1, "rect": {"x": 5, "y": 30, "width": 60, "height": 20}}, *extra]
    path.write_text(json.dumps({"nodes": nodes, "normalized": []}))
    return path


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def spec(self, cand=(), **extra: object) -> dict:
        spec = {"id": "p", "capture": "p", "state": "", "reference_png": solid(self.dir / "r.png"), "candidate_png": solid(self.dir / "c.png", paint=cand),
                "reference2_png": None, "reference_ax": None, "candidate_ax": None, "density": 1.0, "live_regions": [], "problems": [],
                "sidecars": {}, "ax_files": {}, "mask_files": []}
        spec.update(extra)
        return spec


# MARK: - Change 1: gallery_variables

class GalleryVariableTests(Base):
    def bootstrap(self, world: FakeWorld) -> dict:
        return json.loads((world.root / "reference" / "data" / launch.FIXTURE_SUBPATH / "bootstrap.json").read_text())

    def test_variables_are_written_beside_the_page(self) -> None:
        world = FakeWorld(self.dir)
        data = world.root / "reference" / "data"
        launch.set_gallery_page(data, "rooms", {"FENTON_GALLERY_ROOM": "bedroom-1", "FENTON_GALLERY_CLEAN": "1"})
        self.assertEqual(self.bootstrap(world)["variables"],
                         {"FENTON_GALLERY": "rooms", "FENTON_GALLERY_ROOM": "bedroom-1", "FENTON_GALLERY_CLEAN": "1"})

    def test_a_name_outside_the_prefix_is_refused_and_nothing_is_written(self) -> None:
        world = FakeWorld(self.dir)
        before = self.bootstrap(world)
        for bad in ({"HOME": "x"}, {"PROXY_URL": "x"}, {"fenton_gallery_room": "x"}, {"FENTON_GALLERY_ROOM": 1}):
            with self.assertRaises(launch.Refused):
                launch.set_gallery_page(world.root / "reference" / "data", "rooms", bad)
        self.assertEqual(self.bootstrap(world), before)

    def test_the_next_surface_does_not_inherit_the_last_ones_variables(self) -> None:
        world = FakeWorld(self.dir)
        data = world.root / "reference" / "data"
        launch.set_gallery_page(data, "rooms", {"FENTON_GALLERY_ROOM": "bedroom-1"})
        launch.set_gallery_page(data, "vacation")
        self.assertEqual(self.bootstrap(world)["variables"], {"FENTON_GALLERY": "vacation"})

    def test_launch_gallery_passes_the_surfaces_variables_to_the_reference_only(self) -> None:
        world = FakeWorld(self.dir)
        surface = BY_ID["room-master-bedroom"]
        ctx = plrun.Context(self.dir / "run", "gallery", "duo", {}, runner=world)
        plan = capture.plan_reach(surface, "reference", "gallery")
        plrun.default_launcher(plrun.Half("reference", world.udid["reference"], capture.Agent("fake-agent reference", world)), surface, plan, ctx)
        self.assertEqual(self.bootstrap(world)["variables"]["FENTON_GALLERY_ROOM"], "bedroom-1")

    def test_every_shipped_variable_name_is_allowed(self) -> None:
        for surface in SURFACES["surfaces"]:
            launch.checked_variables(surface.get("gallery_variables"))

    def test_run_all_refuses_a_bad_name_before_any_capture(self) -> None:
        world = FakeWorld(self.dir)
        ctx = plrun.Context(self.dir / "run", "gallery", "duo", {}, runner=world)
        with self.assertRaises(launch.Refused):
            plrun.run_all(ctx, [{"id": "x", "gallery_variables": {"EVIL": "1"}}], env={"DEVCAP_HELD": "simulator"}, inventory=[])
        self.assertEqual(world.calls["reference"], [])

    def test_build_surfaces_keeps_and_checks_the_fields(self) -> None:
        row = {"id": "a", "kind": "page", "title": "A", "area": "x", "presence": "both", "in_scope": True, "capture_class": "static",
               "native_reachable": True, "live_write_risk": False, "gallery_variables": {"FENTON_GALLERY_ROOM": "r"}, "landing_title": {"reference": "A"}}
        kept = build_surfaces.convert({"surfaces": [row]})["surfaces"][0]
        self.assertEqual((kept["gallery_variables"], kept["landing_title"]), ({"FENTON_GALLERY_ROOM": "r"}, {"reference": "A"}))
        with self.assertRaises(ValueError):
            build_surfaces.convert({"surfaces": [{**row, "gallery_variables": {"X": "1"}}]})


# MARK: - Change 2: the pairings

class PairingTests(unittest.TestCase):
    def test_the_five_corrected_pairings(self) -> None:
        expected = {
            "room-master-bedroom": ("rooms", {"FENTON_GALLERY_ROOM": "bedroom-1", "FENTON_GALLERY_CLEAN": "1"}),
            "room-page": ("rooms", {"FENTON_GALLERY_ROOM": "living-room"}),
            "household-guests": ("household-settings", {"FENTON_GALLERY_HOUSEHOLD": "guests"}),
            "inventory-space": ("inventory", {"FENTON_GALLERY_SPACE": "pantry"}),
            "vacation-chooser": ("vacation", None),
        }
        for sid, (page, variables) in expected.items():
            self.assertEqual(BY_ID[sid]["gallery_page"], page, sid)
            self.assertEqual(BY_ID[sid].get("gallery_variables"), variables, sid)
            self.assertTrue(BY_ID[sid]["landing_title"]["reference"], sid)
        self.assertEqual(BY_ID["room-master-bedroom"]["landing_title"], {"reference": "Bedroom 1", "candidate": "Master Bedroom"})
        self.assertEqual(BY_ID["room-master-bedroom"]["reach"]["candidate"][-1], {"press": "Master Bedroom"})

    def test_the_old_bedroom_page_is_its_own_surface_paired_by_identifier(self) -> None:
        tiles = BY_ID["bedroom-tiles"]
        self.assertEqual((tiles["gallery_page"], tiles["landing_title"]), ("bedroom", {"reference": "Bedroom Devices"}))
        self.assertIn("identifier", json.dumps(tiles["routes"]) + "identifier")
        self.assertTrue(tiles["ax_identifier_match"])

    def test_no_house_data_in_the_new_fields(self) -> None:
        text = json.dumps([{k: s.get(k) for k in ("gallery_variables", "landing_title", "ax_identifier_match")} for s in SURFACES["surfaces"]])
        self.assertEqual(build_surfaces.ENTITY_ID.findall(text), [])

    def test_a_reference_gallery_page_beats_writes_on_reach_in_gallery_mode_only(self) -> None:
        """Open question 2: ``writes_on_reach`` forced a deep link before the gallery page was looked at."""
        surface = BY_ID["room-master-bedroom"]
        self.assertTrue(surface["writes_on_reach"])
        plan = capture.plan_reach(surface, "reference", "gallery")
        self.assertEqual((plan.method, plan.page), ("gallery", "rooms"))
        self.assertEqual(capture.plan_reach(surface, "reference", "live").method, "deeplink")
        self.assertEqual(capture.plan_reach(surface, "candidate", "gallery").method, "deeplink")


# MARK: - Change 3: wrong-page

class WrongPageTests(Base):
    def files(self, ref: str, cand: str) -> dict:
        return {"reference": tree(self.dir / "r.ax.json", ref), "candidate": tree(self.dir / "c.ax.json", cand)}

    def test_landing_title_reads_the_navigation_bar_then_the_large_title(self) -> None:
        nodes = json.loads(tree(self.dir / "a.json", "Guest Controls").read_text())["nodes"]
        self.assertEqual(capture.landing_title(nodes), "Guest Controls")
        large = [{"type": "StaticText", "label": "9:41", "rect": {"x": 0, "y": 5, "width": 20, "height": 10}},
                 {"type": "StaticText", "label": "Vacation", "rect": {"x": 0, "y": 120, "width": 80, "height": 30}}]
        self.assertEqual(capture.landing_title(large), "Vacation")
        self.assertIsNone(capture.landing_title([]))
        self.assertTrue(capture.same_title(" guest  controls", "Guest Controls"))
        self.assertFalse(capture.same_title("Settings", None))

    def test_a_mismatched_landing_skips_the_pixel_diff(self) -> None:
        spec = self.spec(cand=(BIG,), landing_title={"reference": "Pantry", "candidate": "Pantry"}, ax_files=self.files("Pantry", "Food & Recipes"))
        record = epc.judge(spec, self.dir, args())
        self.assertEqual(record["verdict"], "wrong-page")
        self.assertNotIn("changedPercent", record)  # no pixel compare ran
        self.assertIn("candidate landed on 'Food & Recipes'", record["failures"][0])
        self.assertEqual(record["landingTitles"], {"reference": "Pantry", "candidate": "Food & Recipes"})

    def test_matching_titles_go_on_to_the_normal_compare(self) -> None:
        spec = self.spec(landing_title={"reference": "Bedroom 1", "candidate": "Master Bedroom"}, ax_files=self.files("Bedroom 1", "Master Bedroom"))
        self.assertEqual(epc.judge(spec, self.dir, args())["verdict"], "pass")

    def test_no_expected_title_or_no_tree_is_not_a_wrong_page(self) -> None:
        self.assertEqual(epc.judge(self.spec(ax_files=self.files("A", "B")), self.dir, args())["verdict"], "pass")
        spec = self.spec(landing_title={"reference": "A", "candidate": "A"}, ax_files={})
        self.assertEqual(epc.judge(spec, self.dir, args())["verdict"], "pass")

    def test_wrong_page_comes_before_the_status_bar_check_and_fails_the_run(self) -> None:
        spec = self.spec(cand=(((0, 0, 100, 20), (255, 255, 255)),), landing_title={"candidate": "Vacation"}, ax_files=self.files("x", "Settings"))
        self.assertEqual(epc.judge(spec, self.dir, args(status_bar_equal=True))["verdict"], "wrong-page")
        manifest = {"pairs": [{"id": "p", "reference_png": "", "candidate_png": "", "skipped": "x"}]}
        self.assertEqual(manifest["pairs"][0]["id"], "p")

    def test_run_surface_hands_the_expected_titles_to_the_manifest(self) -> None:
        world = FakeWorld(self.dir)
        halves = {s: plrun.Half(s, world.udid[s], capture.Agent(f"fake-agent {s}", world)) for s in ("reference", "candidate")}
        ctx = plrun.Context(self.dir / "run", "gallery", "test", halves, runner=world)
        entry = plrun.run_surface({**BY_ID["vacation-chooser"]}, ctx)
        self.assertEqual(entry["landing_title"], {"reference": "Vacation", "candidate": "Vacation"})
        self.assertEqual(plrun.run_surface({**BY_ID["bedroom-tiles"]}, ctx)["ax_identifier_match"], BY_ID["bedroom-tiles"]["ax_identifier_match"])


class IdentifierPairingTests(Base):
    def tiles(self, name: str, rows: list) -> Path:
        nodes = [{"identifier": i, "label": l, "value": v} for i, l, v in rows]
        (self.dir / name).write_text(json.dumps({"nodes": nodes}))
        return self.dir / name

    def test_pairs_by_identifier_regardless_of_order_or_pixels(self) -> None:
        pattern = BY_ID["bedroom-tiles"]["ax_identifier_match"]
        ref = self.tiles("r.json", [("room.card.A.tile", "A", "Heating • +3"), ("room.card.B.tile", "B", "Next Alarm 2:46")])
        cand = self.tiles("c.json", [("room.card.B.tile", "B", "Next Alarm 7:00"), ("room.card.A.tile", "A", "Heating • +5")])
        spec = self.spec(cand=(BIG,), ax_identifier_match=pattern, ax_files={"reference": ref, "candidate": cand})
        record = epc.judge(spec, self.dir, args())
        self.assertEqual((record["verdict"], record["identifierDiff"]["matched"]), ("pass", 2))
        self.assertNotIn("changedPercent", record)

    def test_a_missing_tile_or_a_changed_label_fails(self) -> None:
        pattern = BY_ID["bedroom-tiles"]["ax_identifier_match"]
        ref = self.tiles("r.json", [("room.card.A.tile", "A", "x"), ("room.card.B.tile", "B", "x")])
        cand = self.tiles("c.json", [("room.card.A.tile", "Renamed", "x")])
        record = epc.judge(self.spec(ax_identifier_match=pattern, ax_files={"reference": ref, "candidate": cand}), self.dir, args())
        self.assertEqual(record["verdict"], "fail")
        self.assertEqual(record["identifierDiff"]["onlyFirst"], ["room.card.B.tile"])
        self.assertEqual(record["identifierDiff"]["changed"], ["room.card.A.tile"])


# MARK: - Change 4: the status bar never masks content

class StatusBarPrecedenceTests(Base):
    CLOCK = ((10, 12, 60, 30), (255, 255, 255))

    def sized(self, cand=()) -> dict:
        size = (466, 300)
        spec = self.spec(device="iphone")
        spec.update(reference_png=solid(self.dir / "r.png", size=size), candidate_png=solid(self.dir / "c.png", paint=cand, size=size))
        return spec

    def test_a_clock_difference_alone_is_statusbar(self) -> None:
        record = epc.judge(self.sized((self.CLOCK,)), self.dir, args(status_bar_equal=True))
        self.assertEqual(record["verdict"], "statusbar")

    def test_a_content_difference_with_a_clock_difference_is_fail_and_names_both(self) -> None:
        content = ((100, 120, 300, 260), (200, 40, 40))
        record = epc.judge(self.sized((self.CLOCK, content)), self.dir, args(status_bar_equal=True))
        self.assertEqual(record["verdict"], "fail")
        self.assertTrue(any("status bar differs" in f for f in record["failures"]))
        self.assertGreater(record["changedPercent"], 1.0)

    def test_the_battery_side_of_the_bar_is_not_compared(self) -> None:
        battery = ((400, 12, 440, 30), (255, 255, 255))
        self.assertEqual(epc.judge(self.sized((battery,)), self.dir, args(status_bar_equal=True))["verdict"], "pass")


# MARK: - Change 5: the candidate sidecar

class PublicationSidecarTests(Base):
    def folder(self, gallery) -> Path:
        folder = self.dir / "preview"
        folder.mkdir()
        (folder / "publication.json").write_bytes(b'{"revision":43,"document":{}}')
        (folder / "bootstrap.json").write_text(json.dumps({"gallery": gallery}))
        return folder

    def test_facts_record_hash_revision_and_flags_without_the_user_id(self) -> None:
        facts = sidecar.publication_facts(self.folder({"administrator": True, "bedroomScenario": "default", "viewerUserID": "u-secret"}))
        self.assertEqual(facts["sha256"], hashlib.sha256(b'{"revision":43,"document":{}}').hexdigest())
        self.assertEqual(facts["revision"], 43)
        self.assertEqual((facts["gallery"]["administrator"], facts["gallery"]["bedroomScenario"]), (True, "default"))
        self.assertNotIn("u-secret", json.dumps(facts))
        self.assertEqual(len(facts["gallery"]["viewerUserID"]), 12)

    def test_no_publication_is_none(self) -> None:
        self.assertIsNone(sidecar.publication_facts(self.dir / "missing"))

    def test_only_the_candidate_sidecar_carries_it(self) -> None:
        world = FakeWorld(self.dir / "w")
        preview = world.root / "candidate" / "data" / launch.PREVIEW_SUBPATH
        preview.mkdir(parents=True)
        (preview / "publication.json").write_text('{"revision":7}')
        halves = {s: plrun.Half(s, world.udid[s], capture.Agent(f"fake-agent {s}", world)) for s in ("reference", "candidate")}
        ctx = plrun.Context(self.dir / "run", "gallery", "test", halves, runner=world)
        ctx.publication = plrun.candidate_publication(ctx)
        plrun.run_surface({**BY_ID["vacation-chooser"]}, ctx)
        folder = ctx.run_dir / "vacation-chooser"
        self.assertEqual(json.loads((folder / "candidate.sidecar.json").read_text())["publication"]["revision"], 7)
        self.assertNotIn("publication", json.loads((folder / "reference.sidecar.json").read_text()))


# MARK: - iPad reach

class IPadReachTests(unittest.TestCase):
    def test_a_tab_is_reached_through_the_flyout_on_ipad(self) -> None:
        for sid, tab in (("chores", "Chores"), ("settings", "Settings"), ("household-guests", "Settings"), ("vacation-chooser", "Settings")):
            plan = capture.plan_reach(BY_ID[sid], "candidate", "gallery", frozenset(), "ipad")
            self.assertEqual(plan.method, "steps", sid)
            self.assertEqual(plan.steps[:2], ["Sections", tab], sid)
        self.assertEqual(capture.plan_reach(BY_ID["vacation-chooser"], "candidate", "gallery", frozenset(), "ipad").steps,
                         ["Sections", "Settings", "Vacation"])

    def test_other_families_and_the_reference_press_the_tab_directly(self) -> None:
        for device in ("duo", "iphone", None):
            self.assertEqual(capture.plan_reach(BY_ID["chores"], "candidate", "gallery", frozenset(), device).steps, ["Chores"])
        self.assertEqual(capture.plan_reach(BY_ID["chores"], "reference", "live", frozenset(), "ipad").steps, ["Chores"])

    def test_quick_links_surfaces_start_from_home_through_the_flyout(self) -> None:
        plan = capture.plan_reach(BY_ID["vacuums"], "candidate", "live", frozenset(), "ipad")
        self.assertEqual(plan.steps, ["Sections", "Home", "Quick Links", "Vacuums"])

    def test_the_flyout_button_is_pressed_first_by_perform_reach(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakeWorld(Path(tmp))
            agent = capture.Agent("fake-agent candidate", world)
            plan = capture.plan_reach(BY_ID["chores"], "candidate", "gallery", frozenset(), "ipad")
            capture.perform_reach(agent, plan, BY_ID["chores"])
            self.assertEqual(world.pressed("candidate")[:1], ['label="Sections"'])

    def test_run_surface_plans_with_the_context_device(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakeWorld(Path(tmp))
            halves = {s: plrun.Half(s, world.udid[s], capture.Agent(f"fake-agent {s}", world)) for s in ("reference", "candidate")}
            ctx = plrun.Context(Path(tmp) / "run", "gallery", "ipad", halves, runner=world)
            plrun.run_surface({**BY_ID["chores"]}, ctx)
            pressed = world.pressed("candidate")
            self.assertEqual(pressed[0], 'label="Sections"')
            self.assertGreaterEqual(len(pressed), 2)


if __name__ == "__main__":
    unittest.main()
