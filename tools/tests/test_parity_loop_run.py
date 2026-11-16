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
HOLD = {"DEVCAP_HELD": "simulator"}  # what a tools/devcap.py hold gives its children
LIVE = {**HOLD, "PARITY_LIVE_GO": "1"}
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
        source = {"surfaces": [{"id": "a", "kind": "page", "title": "light.demo_kitchen_main", "area": "x", "presence": "both", "in_scope": True,
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
        opens = [c for c in world.calls["reference"] if c[0] == "open"]
        self.assertTrue(opens[-1][1].startswith("fentonhome://"))

    def test_plain_surfaces_press_steps_or_open_the_gallery(self) -> None:
        self.assertEqual(capture.plan_reach(BY_ID["chores"], "candidate", "gallery").steps, ["Chores"])
        gallery = capture.plan_reach(BY_ID["chores"], "reference", "gallery")
        self.assertEqual((gallery.method, gallery.page), ("gallery", "chores"))
        self.assertEqual(capture.plan_reach(BY_ID["chores"], "reference", "live").method, "steps")

    def test_live_quick_links_surfaces_press_from_home_not_by_deep_link(self) -> None:
        plan = capture.plan_reach(BY_ID["vacuums"], "reference", "live")
        self.assertEqual((plan.method, plan.steps), ("steps", ["Home", "Quick Links", "Vacuums"]))
        self.assertEqual(capture.plan_reach(BY_ID["room-kitchen"], "reference", "live").method, "deeplink")

    def test_bedroom_sheets_never_reach_by_pressing_a_room_tile(self) -> None:
        guarded = capture.write_opening_labels(SURFACES["surfaces"])
        tile = BY_ID["room-master-bedroom"]["reach"]["candidate"][-1]["press"]
        self.assertIn(tile, guarded)
        sheets = [x for x in SURFACES["surfaces"] if not x.get("writes_on_reach") and any(
            st.get("press") == tile for st in (x.get("reach") or {}).get("candidate", []))]
        self.assertTrue(sheets)
        world = FakeWorld(Path(tempfile.mkdtemp()))
        agent = capture.Agent("fake-agent candidate", world)
        for sheet in sheets:
            plan = capture.plan_reach(sheet, "candidate", "live", guarded)
            self.assertIn(plan.method, ("deeplink", "skip"), sheet["id"])
            self.assertNotEqual(plan.method, "steps")
            capture.perform_reach(agent, capture.ReachPlan("steps", steps=["Rooms", tile]), sheet, guarded)
        self.assertEqual(world.pressed("candidate"), [])
        skipped = capture.plan_reach({"id": "x", "reach": {"candidate": [{"press": tile}]}}, "candidate", "live", guarded)
        self.assertEqual(skipped.method, "skip")

    def test_a_badged_room_tile_is_never_matched_but_a_badged_tab_is(self) -> None:
        def button(label, x):
            return {"type": "Button", "label": label, "rect": {"x": x, "y": 10, "width": 20, "height": 10}}
        nodes = [button("Demo Room, 3 on", 0), button("Chores, 6 overdue", 100)]
        world = FakeWorld(Path(tempfile.mkdtemp()))
        agent = capture.Agent("fake-agent candidate", world)
        world.nodes["candidate"] = nodes
        agent.press("Demo Room")
        self.assertEqual(world.pressed("candidate"), ['label="Demo Room"'])  # the bare selector, never the badged tile's centre
        agent.press("Chores")
        self.assertIn("Chores", capture.NAV_LABELS)
        self.assertEqual(world.pressed("candidate")[-1], "110")  # the badged tab's centre

    def test_several_badged_buttons_fail_instead_of_taking_the_first(self) -> None:
        def button(label, x):
            return {"type": "Button", "label": label, "rect": {"x": x, "y": 10, "width": 20, "height": 10}}
        nodes = [button("Chores, 6 overdue", 0), button("Chores, 2 due", 100)]
        with self.assertRaises(capture.AmbiguousLabel):
            capture.button_centre(nodes, "Chores", badged=True)
        self.assertIsNone(capture.button_centre(nodes, "Chores"))

    def test_button_centre_prefers_exact_labels_then_badged_ones(self) -> None:
        def button(label, x):
            return {"type": "Button", "label": label, "rect": {"x": x, "y": 10, "width": 20, "height": 10}}
        nodes = [button("Security, Armed Home", 0), button("Security", 100), button("Chores, 6 overdue", 200)]
        self.assertEqual(capture.button_centre(nodes, "Security"), (110.0, 15.0))
        self.assertEqual(capture.button_centre(nodes, "Chores", badged=True), (210.0, 15.0))
        self.assertIsNone(capture.button_centre(nodes, "Chores"))
        self.assertIsNone(capture.button_centre(nodes, "Climate"))

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
        kw.setdefault("env", HOLD)
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
        self.assertEqual(self.world.pressed("candidate"), ["30"])  # the centre of the Chores button in the fake tree
        bootstrap = json.loads((self.world.root / "reference" / "data" / "Library" / "Application Support" / "GalleryFixture" / "bootstrap.json").read_text())
        self.assertEqual(bootstrap["variables"]["FENTON_GALLERY"], "chores")
        car = read_json(folder / "candidate.sidecar.json")
        self.assertEqual((car["side"], car["surface"], car["scale"], car["source"]), ("candidate", "chores", 1, "fixture"))

    def test_status_bar_rects_reach_the_compare(self) -> None:
        rects = self.dir / "rects.json"
        rects.write_text(json.dumps({"clock": [0, 0, 10, 10]}))
        ctx = self.context()
        ctx.status_bar_rects = rects
        with mock.patch.object(plrun.expo_pair_compare, "main", return_value=0) as compare:
            plrun.run_all(ctx, plrun.select(SURFACES, ["chores"]), self.pin, pin_path=self.pin_path, env=HOLD)
        flags = compare.call_args[0][0]
        self.assertEqual(flags[flags.index("--status-bar-rects") + 1], str(rects))

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
        ctx, _ = self.run_surfaces(["room-kitchen"], mode="live", env=LIVE)
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
            plrun.run_all(self.context(), plrun.select(SURFACES, ["chores"]), "0" * 64, env=HOLD)

    def test_the_sidecar_measures_the_appearance_so_a_light_half_is_refused(self) -> None:
        self.world.appearance["candidate"] = "light"
        ctx, status = self.run_surfaces(["chores"])
        row = json.loads((ctx.run_dir / "results.json").read_text())[0]
        self.assertEqual((row["verdict"], status), ("refused", 2))
        self.assertTrue(any("appearance differs: 'dark' vs 'light'" in f for f in row["failures"]))
        self.assertEqual(read_json(ctx.run_dir / "chores" / "candidate.sidecar.json")["appearance"], "light")

    def test_a_failed_appearance_change_stops_the_run(self) -> None:
        self.world.appearance_works = False
        with self.assertRaises(launch.Refused) as caught:
            self.run_surfaces(["chores"])
        self.assertIn("appearance", str(caught.exception))
        self.assertFalse((self.dir / "run" / "chores").exists())

    def test_sidecars_record_launch_arguments_and_env_names_for_each_mode_and_side(self) -> None:
        ctx, _ = self.run_surfaces(["chores"])
        reference = read_json(ctx.run_dir / "chores" / "reference.sidecar.json")
        candidate = read_json(ctx.run_dir / "chores" / "candidate.sidecar.json")
        self.assertEqual((reference["launchArguments"], reference["launchEnvNames"]), (["--gallery-fixture"], []))
        self.assertEqual((candidate["launchArguments"], candidate["launchEnvNames"]), (["--server-ui-preview"], []))
        self.assertTrue(reference["statusBarNormalized"])

    def test_live_sidecars_record_names_only(self) -> None:
        ctx, _ = self.run_surfaces(["room-kitchen"], mode="live", env=LIVE)
        reference = read_json(ctx.run_dir / "room-kitchen" / "reference.sidecar.json")
        candidate = read_json(ctx.run_dir / "room-kitchen" / "candidate.sidecar.json")
        self.assertEqual(reference["launchArguments"], [])
        self.assertIn("FENTON_HASS_TOKEN", reference["launchEnvNames"])
        self.assertEqual(candidate["launchArguments"], ["--server-ui-preview"])
        self.assertIn("FENTON_PREVIEW_HA_TOKEN", candidate["launchEnvNames"])
        for car in (reference, candidate):
            self.assertTrue(all(name.isupper() and "=" not in name for name in car["launchEnvNames"]))
        self.assertEqual(launch.launch_record("gallery", "candidate"), (["--server-ui-preview"], []))
        self.assertEqual(launch.launch_record("fixture", "reference"), (["--gallery-fixture"], []))

    def test_runs_and_launches_need_a_devcap_simulator_hold(self) -> None:
        with self.assertRaises(launch.Refused):
            plrun.run_all(self.context(), plrun.select(SURFACES, ["chores"]), self.pin, pin_path=self.pin_path, env={})
        with self.assertRaises(launch.Refused):
            plrun.run_all(self.context(), plrun.select(SURFACES, ["chores"]), self.pin, pin_path=self.pin_path, env={"DEVCAP_HELD": "build"})
        self.assertEqual(self.world.calls, {"reference": [], "candidate": []})
        runner = lambda argv, env=None, timeout=0: Result(0, "/sim/data\n")  # noqa: E731
        for side in ("reference", "candidate"):
            with self.assertRaises(launch.Refused):
                launch.launch_live(side, "UDID", "http://127.0.0.1:9", runner, {"PARITY_LIVE_GO": "1"})
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(launch.main(["gallery", "--side", "reference", "--agent", "x", "--udid", "U"]), 2)

    def test_the_proxy_starts_without_the_token_password_and_username(self) -> None:
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "creds"
            folder.mkdir(mode=0o700)
            creds = folder / "env"
            creds.write_text("FENTON_HASS_TOKEN=tok-fake\nFENTON_HASS_USERNAME=user-fake\nFENTON_HASS_PASSWORD=pw-fake\n"
                             "FENTON_HASS_SERVER=https://ha.example.invalid\n")
            creds.chmod(0o600)
            # the caller's environment holds the secrets too; the script must still start the program without them
            env = {"PATH": "/usr/bin:/bin", "HOME": tmp, "FENTON_HASS_CREDS_FILE": str(creds), "FENTON_HASS_TOKEN": "caller-token"}
            script = launch.proxy_script(Path("/x/log.jsonl"), "127.0.0.1:0", command=["/usr/bin/env"])
            out = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env)
        self.assertEqual(out.returncode, 0, out.stderr)
        variables = {line.split("=", 1)[0] for line in out.stdout.splitlines() if "=" in line}
        self.assertIn("FENTON_HASS_SERVER", variables)
        for name in launch.PROXY_UNNEEDED_SECRETS:
            self.assertNotIn(name, variables)
        self.assertNotIn("-fake", out.stdout)
        self.assertNotIn("caller-token", out.stdout)

    def test_run_proxy_strips_the_secrets_from_the_environment_it_passes_on(self) -> None:
        runner = lambda argv, env=None, timeout=0: Result(0)  # noqa: E731
        env = {**LIVE, "FENTON_HASS_TOKEN": "t", "FENTON_HASS_PASSWORD": "p", "FENTON_HASS_USERNAME": "u", "KEEP": "1"}
        with mock.patch.object(launch.os, "execvpe") as execvpe:
            launch.run_proxy(Path("/repo/build/evidence/parity-loop/r/rej.jsonl"), "127.0.0.1:0", env=env, runner=runner)
        passed = execvpe.call_args[0][2]
        self.assertEqual(sorted(set(env) - set(passed)), sorted(launch.PROXY_UNNEEDED_SECRETS))
        self.assertEqual(passed["KEEP"], "1")
        self.assertIn("unset FENTON_HASS_TOKEN FENTON_HASS_PASSWORD FENTON_HASS_USERNAME;", execvpe.call_args[0][1][2])

    def test_the_proxy_log_must_be_git_ignored(self) -> None:
        calls = []

        def runner(argv, env=None, timeout=0):
            calls.append(argv)
            return Result(1 if "tracked-folder" in argv[-1] else 0)
        with self.assertRaises(launch.Refused):
            launch.run_proxy(Path("/repo/tracked-folder/rej.jsonl"), "127.0.0.1:0", env=LIVE, runner=runner)
        with mock.patch.object(launch.os, "execvpe") as execvpe:
            launch.run_proxy(Path("/repo/build/evidence/parity-loop/r/rej.jsonl"), "127.0.0.1:0", env=LIVE, runner=runner)
        self.assertEqual(execvpe.call_count, 1)
        self.assertEqual(calls[0][:2], ["git", "-C"])

    def test_unknown_surface_ids_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            plrun.select(SURFACES, ["nope"])


class LaunchTests(unittest.TestCase):
    def test_live_refuses_without_the_go_variable(self) -> None:
        calls = []
        runner = lambda argv, env=None, timeout=0: calls.append(argv) or Result(0)  # noqa: E731
        for value in (None, "", "0", "true", "yes"):
            env = dict(HOLD) if value is None else {**HOLD, "PARITY_LIVE_GO": value}
            with self.assertRaises(launch.Refused):
                launch.launch_live("reference", "UDID", "http://127.0.0.1:1", runner, env)
        self.assertEqual(calls, [])

    def test_run_all_in_live_mode_refuses_without_the_go(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakeWorld(Path(tmp) / "w")
            halves = {s: plrun.Half(s, world.udid[s], capture.Agent(f"fake-agent {s}", world)) for s in ("reference", "candidate")}
            ctx = plrun.Context(Path(tmp) / "run", "live", "test", halves, runner=world)
            with self.assertRaises(launch.Refused):
                plrun.run_all(ctx, [], None, env=HOLD)
            self.assertEqual(world.calls, {"reference": [], "candidate": []})
            self.assertFalse((Path(tmp) / "run").exists())

    def test_main_exits_2_without_the_go(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            code = launch.main(["live", "--side", "reference", "--udid", "U", "--proxy-url", "http://127.0.0.1:1"])
        self.assertEqual(code, 2)

    def test_live_launches_need_the_proxy(self) -> None:
        runner = lambda argv, env=None, timeout=0: Result(0)  # noqa: E731
        for side in ("reference", "candidate"):
            with self.assertRaises(launch.Refused):
                launch.launch_live(side, "UDID", None, runner, LIVE)

    def test_live_launch_points_the_reference_at_the_proxy_and_carries_no_secret(self) -> None:
        seen = []

        def runner(argv, env=None, timeout=0):
            seen.append((argv, env))
            return Result(0)
        launch.launch_live("reference", "UDID", "http://127.0.0.1:9", runner, LIVE)
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
