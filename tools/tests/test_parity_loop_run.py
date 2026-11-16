"""Tests for tools/parity_loop: surfaces.json, reach planning (deep-link-only for writes), the triple capture, launch refusals."""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from parity_loop import build_surfaces, capture, launch, run as plrun, sidecar  # noqa: E402
from parity_loop.common import Result, read_json  # noqa: E402
from parity_loop_fakes import FakeWorld  # noqa: E402

SURFACES = read_json(Path(plrun.SURFACES_FILE))
BY_ID = {s["id"]: s for s in SURFACES["surfaces"]}
BIG = ((10, 100, 110, 190), (200, 40, 40))
plrun.DEVICES["test"] = {"scale": 1, "pose": "folded", "size": [120, 200]}


class SurfacesTests(unittest.TestCase):
    def test_file_is_generic_and_complete(self) -> None:
        text = json.dumps(SURFACES)
        self.assertEqual(SURFACES["schema"], build_surfaces.SCHEMA)
        self.assertEqual(len(SURFACES["surfaces"]), 118)
        self.assertEqual(build_surfaces.ENTITY_ID.findall(text), [])
        self.assertNotIn("required_state", text)
        self.assertNotIn("notes", text)
        self.assertTrue(all(set(s["deep_link"]) <= {"reference", "candidate"} for s in SURFACES["surfaces"]))

    def test_writes_on_reach_marks_the_five_write_paths(self) -> None:
        marked = {s["id"] for s in SURFACES["surfaces"] if s["writes_on_reach"]}
        self.assertEqual(len(marked), 5)
        self.assertIn("room-kitchen", marked)

    def test_convert_rejects_an_entity_id(self) -> None:
        source = {"surfaces": [{"id": "a", "kind": "page", "title": "light.kitchen_main", "area": "x", "presence": "both", "in_scope": True,
                                "capture_class": "static", "native_reachable": True, "live_write_risk": False}]}
        with self.assertRaises(ValueError):
            build_surfaces.convert(source)

    def test_reach_step_parsing(self) -> None:
        self.assertEqual(build_surfaces.reach_step("Tab bar: Chores"), {"press": "Chores"})
        self.assertEqual(build_surfaces.reach_step("Tile: <resident> chores"), {"manual": "Tile: <resident> chores"})
        self.assertIn("manual", build_surfaces.reach_step("Header trailing group: Quick Links button (opens the sheet)"))


class ReachTests(unittest.TestCase):
    def test_writes_on_reach_uses_the_deep_link(self) -> None:
        plan = capture.plan_reach(BY_ID["room-kitchen"], "reference", "fixture")
        self.assertEqual(plan.method, "deeplink")
        self.assertTrue(plan.url.startswith("fentonhome://"))

    def test_writes_on_reach_without_a_link_is_skipped(self) -> None:
        for sid in ("feedback-result-alerts", "bed-temperature-scope-sheet"):
            plan = capture.plan_reach(BY_ID[sid], "candidate", "live")
            self.assertEqual((plan.method, plan.reason), ("skip", "writes_on_reach and no deep link"))

    def test_perform_reach_never_presses_for_a_write_surface(self) -> None:
        world = FakeWorld(Path(tempfile.mkdtemp()))
        agent = capture.Agent("fake-agent reference", world)
        surface = dict(BY_ID["room-kitchen"])
        capture.perform_reach(agent, capture.ReachPlan("steps", steps=["Rooms", "Kitchen"]), surface)
        self.assertEqual(world.pressed("reference"), [])
        capture.perform_reach(agent, capture.plan_reach(surface, "reference", "live"), surface)
        self.assertEqual(world.pressed("reference"), [])
        self.assertEqual(world.calls["reference"][-1][0], "open")
        self.assertTrue(world.calls["reference"][-1][1].startswith("fentonhome://"))

    def test_plain_surfaces_press_steps_or_open_the_gallery(self) -> None:
        self.assertEqual(capture.plan_reach(BY_ID["chores"], "candidate", "gallery").steps, ["Chores"])
        gallery = capture.plan_reach(BY_ID["chores"], "reference", "gallery")
        self.assertEqual((gallery.method, gallery.page), ("gallery", "chores"))
        self.assertEqual(capture.plan_reach(BY_ID["chores"], "reference", "live").method, "deeplink")

    def test_ax_normalisation_drops_status_bar_and_masks_dynamic_text(self) -> None:
        rules = [build_surfaces.CLOCK_MASK, build_surfaces.RELATIVE_TIME_MASK]
        rows = capture.normalize_ax([
            {"type": "StaticText", "label": "9:41", "rect": {"x": 1, "y": 5, "width": 20, "height": 10}},
            {"type": "StaticText", "label": "Updated 5 min ago", "value": "12%"},
            {"type": "Button", "label": "Chores", "enabled": False, "selected": True}], rules)
        self.assertEqual([r["label"] for r in rows], [capture.DYNAMIC_TOKEN, "Chores"])
        self.assertEqual((rows[0]["value"], rows[1]["enabled"], rows[1]["selected"]), ("num", False, True))
        regions = capture.resolve_masks([{"label": "9:41", "rect": {"x": 1, "y": 5, "width": 20, "height": 10}}], [build_surfaces.CLOCK_MASK])
        self.assertEqual(regions[0]["label"], "clock")


class RunTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.world = FakeWorld(self.dir / "world")
        self.pin = sidecar.bundle_identity(self.dir / "world" / "reference" / "App.app")
        self.pin_path = self.dir / "pin.json"
        self.pin_path.write_text(json.dumps({"bundleSHA256": self.pin}))

    def context(self, mode: str = "gallery") -> plrun.Context:
        halves = {s: plrun.Half(s, self.world.udid[s], capture.Agent(f"fake-agent {s}", self.world)) for s in ("reference", "candidate")}
        return plrun.Context(self.dir / "run", mode, "test", halves, runner=self.world, tool_sha="abc1234")

    def run_surfaces(self, ids, **kw):
        ctx = self.context(kw.pop("mode", "gallery"))
        status = plrun.run_all(ctx, plrun.select(SURFACES, ids), self.pin, pin_path=self.pin_path, **kw)
        return ctx, status

    def test_a_gallery_pair_is_captured_ref_cand_ref_and_passes(self) -> None:
        ctx, status = self.run_surfaces(["chores"])
        folder = ctx.run_dir / "chores"
        for stem in ("reference", "candidate", "reference2"):
            for suffix in (".png", ".ax.json", ".sidecar.json", ".masks.json"):
                self.assertTrue((folder / f"{stem}{suffix}").is_file(), stem + suffix)
        rows = json.loads((ctx.run_dir / "results.json").read_text())
        self.assertEqual((status, rows[0]["verdict"], rows[0]["class"]), (0, "pass", "unclassified"))
        self.assertTrue((ctx.run_dir / "results.md").is_file())
        self.assertEqual(self.world.calls["reference"][0], ["settings", "appearance", "dark"])
        opens = [c for c in self.world.calls["reference"] if c[0] == "open"]
        self.assertEqual(len(opens), 2)
        self.assertIn("--launch-args=--gallery-fixture", opens[0])
        self.assertEqual(self.world.pressed("candidate"), ['label="Chores"'])
        bootstrap = json.loads((self.world.root / "reference" / "data" / "Library" / "Application Support" / "GalleryFixture" / "bootstrap.json").read_text())
        self.assertEqual(bootstrap["variables"]["FENTON_GALLERY"], "chores")
        car = read_json(folder / "candidate.sidecar.json")
        self.assertEqual((car["side"], car["surface"], car["scale"], car["source"]), ("candidate", "chores", 1, "fixture"))

    def test_reference_drift_is_reported_as_drift(self) -> None:
        self.world.reference2_paint = (BIG,)
        ctx, status = self.run_surfaces(["chores"])
        rows = json.loads((ctx.run_dir / "results.json").read_text())
        self.assertEqual((rows[0]["verdict"], status), ("drift", 1))

    def test_a_candidate_that_differs_fails_the_pair(self) -> None:
        self.world.shot_paint["candidate"] = (BIG,)
        _, status = self.run_surfaces(["chores"])
        self.assertEqual(status, 1)

    def test_a_missing_ax_tree_fails_the_pair(self) -> None:
        self.world.nodes["candidate"] = []
        ctx, status = self.run_surfaces(["chores"])
        row = json.loads((ctx.run_dir / "results.json").read_text())[0]
        self.assertEqual((row["verdict"], status), ("fail", 1))
        self.assertTrue(any("empty AX snapshot" in f for f in row["failures"]))

    def test_ax_difference_fails_the_pair(self) -> None:
        self.world.nodes["candidate"] = self.world.nodes["candidate"] + [{"type": "Button", "label": "Extra"}]
        ctx, status = self.run_surfaces(["chores"])
        row = json.loads((ctx.run_dir / "results.json").read_text())[0]
        self.assertEqual(row["verdict"], "fail")
        self.assertIs(row["allAXNodesEqual"], False)

    def test_a_sidecar_mismatch_is_refused(self) -> None:
        real = sidecar.collect

        def tilted(udid, side, **kw):
            car = real(udid, side, **kw)
            if side == "candidate":
                car["runtimeBuild"] = "OTHER"
            return car
        with mock.patch.object(sidecar, "collect", tilted):
            ctx, status = self.run_surfaces(["chores"])
        row = json.loads((ctx.run_dir / "results.json").read_text())[0]
        self.assertEqual((row["verdict"], status), ("refused", 2))
        self.assertTrue(any("runtimeBuild" in f for f in row["failures"]))

    def test_a_write_surface_is_deep_linked_never_tapped(self) -> None:
        ctx, _ = self.run_surfaces(["room-kitchen"], mode="live", env={"PARITY_LIVE_GO": "1"})
        self.assertEqual(self.world.pressed("reference"), [])
        self.assertEqual(self.world.pressed("candidate"), [])
        opened = [c for c in self.world.calls["candidate"] if c[0] == "open" and c[1].startswith("fentonhome://")]
        self.assertEqual(len(opened), 1)

    def test_a_write_surface_without_a_link_is_skipped_and_recorded(self) -> None:
        ctx, status = self.run_surfaces(["feedback-result-alerts"])
        row = json.loads((ctx.run_dir / "results.json").read_text())[0]
        self.assertEqual((row["verdict"], status), ("skipped", 0))
        self.assertIn("writes_on_reach", row["skipReason"])
        self.assertTrue((ctx.run_dir / "feedback-result-alerts" / "skipped.json").is_file())
        self.assertEqual(self.world.calls["reference"], [["settings", "appearance", "dark"]])

    def test_the_reference_must_match_its_pin(self) -> None:
        with self.assertRaises(launch.Refused):
            plrun.run_all(self.context(), plrun.select(SURFACES, ["chores"]), "0" * 64)

    def test_unknown_surface_ids_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            plrun.select(SURFACES, ["nope"])


class LaunchTests(unittest.TestCase):
    def test_live_refuses_without_the_go_variable(self) -> None:
        calls = []
        runner = lambda argv, env=None, timeout=0: calls.append(argv) or Result(0)  # noqa: E731
        for value in (None, "", "0", "true", "yes"):
            env = {} if value is None else {"PARITY_LIVE_GO": value}
            with self.assertRaises(launch.Refused):
                launch.launch_live("reference", "UDID", "http://127.0.0.1:1", runner, env)
        self.assertEqual(calls, [])

    def test_run_all_in_live_mode_refuses_without_the_go(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakeWorld(Path(tmp) / "w")
            halves = {s: plrun.Half(s, world.udid[s], capture.Agent(f"fake-agent {s}", world)) for s in ("reference", "candidate")}
            ctx = plrun.Context(Path(tmp) / "run", "live", "test", halves, runner=world)
            with self.assertRaises(launch.Refused):
                plrun.run_all(ctx, [], None, env={})
            self.assertEqual(world.calls, {"reference": [], "candidate": []})
            self.assertFalse((Path(tmp) / "run").exists())

    def test_main_exits_2_without_the_go(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            code = launch.main(["live", "--side", "reference", "--udid", "U", "--proxy-url", "http://127.0.0.1:1"])
        self.assertEqual(code, 2)

    def test_live_reference_needs_the_proxy_and_the_candidate_is_refused(self) -> None:
        runner = lambda argv, env=None, timeout=0: Result(0)  # noqa: E731
        with self.assertRaises(launch.Refused):
            launch.launch_live("reference", "UDID", None, runner, {"PARITY_LIVE_GO": "1"})
        with self.assertRaises(launch.Refused):
            launch.launch_live("candidate", "UDID", "http://127.0.0.1:1", runner, {"PARITY_LIVE_GO": "1"})

    def test_live_launch_points_the_reference_at_the_proxy_and_carries_no_secret(self) -> None:
        seen = []

        def runner(argv, env=None, timeout=0):
            seen.append((argv, env))
            return Result(0)
        launch.launch_live("reference", "UDID", "http://127.0.0.1:9", runner, {"PARITY_LIVE_GO": "1"})
        argv, env = seen[0]
        script = argv[2]
        self.assertEqual(env["PROXY_URL"], "http://127.0.0.1:9")
        self.assertIn("hass_load_creds", script)
        self.assertIn('SIMCTL_CHILD_FENTON_HASS_SERVER="$PROXY_URL"', script)
        self.assertNotRegex(script, r"SIMCTL_CHILD_FENTON_HASS_SERVER=\"\$FENTON_HASS_SERVER")
        self.assertNotIn("echo", script.replace('echo "no proxy url"', ""))
        self.assertNotIn("FENTON_HASS_TOKEN=", script.replace('SIMCTL_CHILD_FENTON_HASS_TOKEN="$FENTON_HASS_TOKEN"', ""))

    def test_proxy_script_loads_the_upstream_in_a_child_and_needs_the_go(self) -> None:
        script = launch.proxy_script(Path("/tmp/x.jsonl"), "127.0.0.1:0")
        self.assertIn("hass_load_creds", script)
        self.assertIn("guard_proxy.py", script)
        with self.assertRaises(launch.Refused):
            launch.run_proxy(Path("/tmp/x.jsonl"), "127.0.0.1:0", env={})

    def test_gallery_launch_arguments_follow_the_side(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakeWorld(Path(tmp))
            launch.launch_gallery("candidate", capture.Agent("fake-agent candidate", world), world.udid["candidate"], None, world)
            self.assertEqual(world.calls["candidate"][0], ["open", "com.sfenton.home", "--relaunch", "--launch-args=--server-ui-preview"])

    def test_the_token_is_never_in_the_launch_module_text(self) -> None:
        source = Path(launch.__file__).read_text()
        self.assertFalse(re.search(r"print\(.*TOKEN", source))


if __name__ == "__main__":
    unittest.main()
