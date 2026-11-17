"""Tests for parity_loop.states (the coverage table) and parity_loop.faults (fixture-only state staging and pairing)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import png_raster  # noqa: E402
from parity_loop import capture, faults, launch, run as plrun, sidecar, simguard, states  # noqa: E402
from parity_loop.common import Result, read_json  # noqa: E402
from parity_loop_fakes import FakeWorld, solid  # noqa: E402

SURFACES = read_json(states.SURFACES_FILE)
BY_ID = {s["id"]: s for s in SURFACES["surfaces"]}
HOLD = {"DEVCAP_HELD": "simulator,device-UDID-REF,device-UDID-CAND"}  # a hold on both fake simulators
plrun.DEVICES.setdefault("test", {"scale": 1, "pose": "folded", "size": [120, 200]})


def catalog(*items):
    return {"items": [dict({"devices": ["iphone", "duo", "ipad"], "area": "a"}, **i) for i in items]}


def surface(sid, **kw):
    return dict({"id": sid, "in_scope": True, "presence": "both", "reach": {}, "deep_link": {}}, **kw)


class CoverageTests(unittest.TestCase):
    def test_a_row_per_surface_and_family_the_atlas_lists(self) -> None:
        """Fails if: a row per surface and family the atlas lists no longer holds."""
        doc = states.build(catalog({"id": "home", "kind": "page"}, {"id": "loc", "kind": "modal", "devices": ["iphone", "duo"]}),
                           {"surfaces": [surface("home"), surface("loc")]})
        self.assertEqual(sorted((r["id"], r["family"]) for r in doc["rows"]),
                         [("home", "duo"), ("home", "ipad"), ("home", "iphone"), ("loc", "duo"), ("loc", "iphone")])
        self.assertEqual(doc["counts"]["total"], {"covered": 5, "missing": 0, "skipped": 0, "total": 5})

    def test_proposals_and_watch_are_not_rows(self) -> None:
        """Fails if: proposals and watch are not rows no longer holds."""
        doc = states.build(catalog({"id": "p", "kind": "proposal"}, {"id": "w", "kind": "page", "devices": ["watch"]}), {"surfaces": []})
        self.assertEqual(doc["rows"], [])

    def test_component_without_a_row_is_missing_and_reads_studio(self) -> None:
        """Fails if: component without a row is missing and reads studio no longer holds."""
        doc = states.build(catalog({"id": "tile", "kind": "component", "mockup": "components/tile.html", "presentedFrom": ["home"]}), {"surfaces": []})
        row = doc["rows"][0]
        self.assertEqual((row["status"], row["reference_source"], row["candidate_source"]), ("missing", "studio", "native"))
        self.assertIn("home", row["reach_candidate"])
        self.assertIn("Studio", row["reach_reference"])

    def test_native_only_and_out_of_scope_are_not_covered(self) -> None:
        """Fails if: native only and out of scope are not covered no longer holds."""
        doc = states.build(catalog({"id": "n", "kind": "page"}, {"id": "o", "kind": "page"}, {"id": "e", "kind": "modal"}),
                           {"surfaces": [surface("n", presence="native-only"), surface("o", in_scope=False), surface("e", presence="expo-only")]})
        by = {r["id"]: r for r in doc["rows"] if r["family"] == "duo"}
        self.assertEqual((by["n"]["status"], by["n"]["reference_source"]), ("missing", "studio"))
        self.assertEqual(by["o"]["status"], "skipped")
        self.assertEqual(by["e"]["status"], "skipped")

    def test_reach_text_names_gallery_page_press_path_and_link(self) -> None:
        """Fails if: reach text names gallery page press path and link no longer holds."""
        row = surface("c", gallery_page="chores", reach={"reference": [{"press": "Chores"}], "candidate": [{"press": "A"}, {"press": "B"}]},
                      deep_link={"candidate": "x://y"})
        reach = states.reach_text(row, {"id": "c"})
        self.assertEqual(reach["reference"], "gallery page chores; press Chores")
        self.assertEqual(reach["candidate"], "press A > B; deep link")

    def test_state_classes_come_from_hint_words(self) -> None:
        """Fails if: state classes come from hint words no longer holds."""
        self.assertEqual(states.state_classes(["offline (chip)", "Empty list", "unavailable", "loading"]), ["empty", "loading", "offline", "unavailable"])
        self.assertEqual(states.state_classes(["ax5"]), [])

    def test_the_shipped_atlas_joins_every_page_modal_and_flow(self) -> None:
        """Fails if: the shipped atlas joins every page modal and flow no longer holds."""
        doc = states.build(read_json(states.CATALOG_FILE), SURFACES)
        counts = doc["counts"]["by_kind"]
        for kind in ("page", "modal", "flow"):
            self.assertEqual(counts[kind]["missing"] + counts[kind]["covered"] + counts[kind]["skipped"], counts[kind]["total"])
        self.assertEqual(counts["component"]["covered"], 0)
        self.assertGreater(counts["modal"]["covered"], 100)

    def test_markdown_lists_rows_of_one_status(self) -> None:
        """Fails if: markdown lists rows of one status no longer holds."""
        doc = states.build(catalog({"id": "tile", "kind": "component"}), {"surfaces": []})
        text = states.markdown(doc, "missing")
        self.assertIn("| tile | component | iphone | studio |", text)

    def test_cli_writes_json_and_markdown(self) -> None:
        """Fails if: cli writes json and markdown no longer holds."""
        with tempfile.TemporaryDirectory() as tmp:
            out, md = Path(tmp) / "c.json", Path(tmp) / "c.md"
            self.assertEqual(states.main(["--json", str(out), "--markdown", str(md)]), 0)
            self.assertEqual(read_json(out)["schema"], "parity-states-coverage/1")
            self.assertIn("| all |", md.read_text())

    def test_cli_reports_a_missing_file(self) -> None:
        """Fails if: cli reports a missing file no longer holds."""
        self.assertEqual(states.main(["--catalog", "/nonexistent/c.json"]), 2)


class FaultTableTests(unittest.TestCase):
    def test_every_class_the_brief_names_is_staged(self) -> None:
        """Fails if: every class the brief names is staged no longer holds."""
        self.assertEqual({f.state_class for f in faults.FAULTS.values()}, {"error", "unavailable", "offline", "loading", "empty"})

    def test_native_flag_keys_are_the_preview_flags(self) -> None:
        """Fails if: native flag keys are the preview flags no longer holds."""
        known = {"connection", "failCalls", "empty", "gateDelayMs", "animationsPaused", "reduceMotion"}
        self.assertTrue(faults.MANAGED_FLAGS <= known)

    def test_reference_variables_are_gallery_names_only(self) -> None:
        """Fails if: reference variables are gallery names only no longer holds."""
        for name in faults.MANAGED_VARIABLES:
            self.assertTrue(name.startswith("FENTON_GALLERY_"), name)

    def test_a_delay_must_match_on_both_sides_and_stay_in_range(self) -> None:
        """Fails if: a delay must match on both sides and stay in range no longer holds."""
        loading = faults.FAULTS["loading"]
        faults.check_fault(loading)
        with self.assertRaises(faults.Refused):
            faults.check_fault(faults.Fault("x", "loading", {"FENTON_GALLERY_GATE_DELAY_MS": "10"}, {"gateDelayMs": 20}, frozenset()))
        with self.assertRaises(faults.Refused):
            faults.check_fault(faults.Fault("x", "loading", {}, {"gateDelayMs": 61_000}, frozenset()))

    def test_matrix_pairs_only_where_the_reference_has_a_mechanism(self) -> None:
        """Fails if: matrix pairs only where the reference has a mechanism no longer holds."""
        rows = faults.matrix(SURFACES["surfaces"])
        got = {(r["surface"], r["fault"]) for r in rows if r["status"] == "paired"}
        self.assertIn(("chores", "empty"), got)
        self.assertIn(("security", "unavailable"), got)
        self.assertIn(("performance-screen", "loading"), got)
        self.assertNotIn(("home", "empty"), got)
        self.assertEqual(next(r for r in rows if (r["surface"], r["fault"]) == ("home", "empty"))["status"], "no-reference")

    def test_write_surfaces_are_never_in_the_matrix(self) -> None:
        """Fails if: write surfaces are never in the matrix no longer holds."""
        writes = {s["id"] for s in SURFACES["surfaces"] if s.get("writes_on_reach")}
        self.assertTrue(writes)
        self.assertTrue(writes.isdisjoint({r["surface"] for r in faults.matrix(SURFACES["surfaces"])}))

    def test_matrix_markdown_names_each_fault(self) -> None:
        """Fails if: matrix markdown names each fault no longer holds."""
        text = faults.matrix_markdown(SURFACES["surfaces"])
        for fid in faults.FAULTS:
            self.assertIn(f"| {fid} |", text)


KEY = "_".join(["demo", "entity"])  # a key with no domain dot: not an entity id


class StagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.data = Path(self.tmp.name)
        (self.data / launch.FIXTURE_SUBPATH).mkdir(parents=True)
        (self.data / launch.PREVIEW_SUBPATH).mkdir(parents=True)
        self.ref = self.data / launch.FIXTURE_SUBPATH / "bootstrap.json"
        self.cand = self.data / launch.PREVIEW_SUBPATH / "bootstrap.json"
        self.ref.write_text(json.dumps({"id": "demo", "variables": {"FENTON_GALLERY": "home", "FENTON_GALLERY_SCHEME": "light"}}))
        self.cand.write_text(json.dumps({"entities": {KEY: {"state": "locked"}}, "flags": {"reduceMotion": True}}))

    def test_reference_gets_page_and_variables_and_keeps_unrelated_ones(self) -> None:
        """Fails if: reference gets page and variables and keeps unrelated ones no longer holds."""
        (self.data / launch.FIXTURE_SUBPATH / "receipt.json").write_text("{}")
        faults.stage_reference(self.data, "chores", faults.FAULTS["empty"])
        config = json.loads(self.ref.read_text())
        self.assertEqual(config["variables"], {"FENTON_GALLERY": "chores", "FENTON_GALLERY_SCHEME": "light", "FENTON_GALLERY_EMPTY": "1"})
        self.assertFalse((self.data / launch.FIXTURE_SUBPATH / "receipt.json").exists())

    def test_the_next_fault_replaces_the_last_and_clean_removes_it(self) -> None:
        """Fails if: the next fault replaces the last and clean removes it no longer holds."""
        faults.stage_reference(self.data, "security", faults.FAULTS["error"])
        faults.stage_reference(self.data, "security", faults.FAULTS["unavailable"])
        variables = json.loads(self.ref.read_text())["variables"]
        self.assertNotIn("FENTON_GALLERY_FAIL", variables)
        self.assertEqual(variables["FENTON_GALLERY_SCENARIO"], "unavailable")
        faults.stage_reference(self.data, "security", None)
        self.assertEqual(set(json.loads(self.ref.read_text())["variables"]), {"FENTON_GALLERY", "FENTON_GALLERY_SCHEME"})

    def test_loading_pauses_the_reference_arcs_and_clean_unpauses(self) -> None:
        """Fails if: loading pauses the reference arcs and clean unpauses no longer holds."""
        faults.stage_reference(self.data, "performance", faults.FAULTS["loading"])
        config = json.loads(self.ref.read_text())
        self.assertTrue(config["pauseContinuousAnimations"])
        self.assertEqual(config["variables"]["FENTON_GALLERY_GATE_DELAY_MS"], "20000")
        faults.stage_reference(self.data, "performance", None)
        self.assertNotIn("pauseContinuousAnimations", json.loads(self.ref.read_text()))

    def test_candidate_flags_replace_managed_ones_and_keep_the_rest(self) -> None:
        """Fails if: candidate flags replace managed ones and keep the rest no longer holds."""
        faults.stage_candidate(self.data, faults.FAULTS["offline"])
        self.assertEqual(json.loads(self.cand.read_text())["flags"], {"reduceMotion": True, "connection": "offline"})
        faults.stage_candidate(self.data, faults.FAULTS["empty"])
        self.assertEqual(json.loads(self.cand.read_text())["flags"], {"reduceMotion": True, "empty": True})
        faults.stage_candidate(self.data, None)
        self.assertEqual(json.loads(self.cand.read_text())["flags"], {"reduceMotion": True})

    def test_unavailable_changes_entities_and_a_later_fault_undoes_it(self) -> None:
        """Fails if: unavailable changes entities and a later fault undoes it no longer holds."""
        faults.stage_candidate(self.data, faults.FAULTS["unavailable"])
        self.assertEqual(json.loads(self.cand.read_text())["entities"][KEY]["state"], "unavailable")
        faults.stage_candidate(self.data, None)
        config = json.loads(self.cand.read_text())
        self.assertEqual(config["entities"][KEY]["state"], "locked")
        self.assertNotIn("_pristine_entities", config)

    def test_a_missing_bootstrap_is_refused(self) -> None:
        """Fails if: a missing bootstrap is refused no longer holds."""
        self.cand.unlink()
        with self.assertRaises(faults.Refused):
            faults.stage_candidate(self.data, None)

    def test_staging_touches_no_secret_or_server_key(self) -> None:
        """Fails if: staging touches no secret or server key no longer holds."""
        faults.stage_candidate(self.data, faults.FAULTS["error"])
        text = self.cand.read_text().lower()
        for word in ("token", "server", "password"):
            self.assertNotIn(word, text)


class PairingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.world = FakeWorld(self.dir / "world")
        preview = self.dir / "world" / "candidate" / "data" / launch.PREVIEW_SUBPATH
        preview.mkdir(parents=True)
        (preview / "bootstrap.json").write_text(json.dumps({"entities": {}}))
        pin = sidecar.bundle_identity(self.dir / "world" / "reference" / "App.app")
        self.pin_path = self.dir / "pin.json"
        self.pin_path.write_text(json.dumps({"bundleSHA256": pin}))
        self.pin = pin

    def context(self, mode: str = "gallery") -> plrun.Context:
        halves = {s: plrun.Half(s, self.world.udid[s], capture.Agent(f"fake-agent {s}", self.world)) for s in ("reference", "candidate")}
        return plrun.Context(self.dir / "run", mode, "test", halves, runner=self.world, tool_sha="abc1234")

    def reference_bootstrap(self) -> dict:
        return json.loads((self.world.root / "reference" / "data" / launch.FIXTURE_SUBPATH / "bootstrap.json").read_text())

    def test_a_fault_pair_is_captured_under_the_derived_id_and_judged(self) -> None:
        """Fails if: a fault pair is captured under the derived id and judged no longer holds."""
        ctx = self.context()
        seen = []
        original = faults.stage_reference
        faults.stage_reference = lambda d, p, f: (seen.append((p, f and f.id)), original(d, p, f))[1]
        try:
            status = faults.run_faults(ctx, plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path)
        finally:
            faults.stage_reference = original
        self.assertEqual(status, 0)
        self.assertEqual(seen, [("chores", "empty"), ("chores", "empty"), ("chores", None)])  # reference, reference again, then the clean restore
        for stem in ("reference", "candidate", "reference2"):
            self.assertTrue((ctx.run_dir / "chores.empty" / f"{stem}.png").is_file())
        rows = json.loads((ctx.run_dir / "results.json").read_text())
        self.assertEqual((rows[0]["id"], rows[0]["verdict"]), ("chores.empty", "pass"))
        manifest = read_json(ctx.run_dir / "manifest.json")
        self.assertIn("fault:empty", manifest["pairs"][0]["state"])

    def test_a_page_region_run_masks_both_halves_and_lifts_the_cap(self) -> None:
        """Fails if: a page region run masks both halves and lifts the cap no longer holds."""
        ctx = self.context()
        faults.run_faults(ctx, plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path)
        self.assertEqual(ctx.max_mask_percent, faults.PAGE_REGION_MASK_PERCENT)
        self.assertFalse(ctx.status_bar_equal)
        manifest = read_json(ctx.run_dir / "manifest.json")
        self.assertIn("chores.empty/candidate.masks.json", manifest["pairs"][0]["mask_files"])

    def test_a_full_frame_run_keeps_the_default_cap(self) -> None:
        """Fails if: a full frame run keeps the default cap no longer holds."""
        ctx = self.context()
        faults.run_faults(ctx, plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path, page_region=False)
        self.assertIsNone(ctx.max_mask_percent)
        self.assertTrue(ctx.status_bar_equal)
        self.assertNotIn("chores.empty/candidate.masks.json", read_json(ctx.run_dir / "manifest.json")["pairs"][0]["mask_files"])

    def test_a_text_size_is_set_on_both_halves_tagged_and_restored(self) -> None:
        """Fails if: a text size is set on both halves tagged and restored no longer holds."""
        self.world.content_size = {"reference": "medium", "candidate": "extra-large"}
        ctx = self.context()
        faults.run_faults(ctx, plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path, text_size="accessibility-large")
        sets = [c[5] for c in self.world.simctl_calls if len(c) > 5 and c[4] == "content_size"]
        self.assertEqual(sets, ["accessibility-large", "accessibility-large", "medium", "extra-large"])
        self.assertEqual(self.world.content_size, {"reference": "medium", "candidate": "extra-large"})
        pair = read_json(ctx.run_dir / "manifest.json")["pairs"][0]
        self.assertEqual(pair["id"], "chores.empty.accessibility-large")
        self.assertIn("text:accessibility-large", pair["state"])

    def test_default_text_size_touches_no_setting(self) -> None:
        """Fails if: default text size touches no setting no longer holds."""
        faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path)
        self.assertFalse([c for c in self.world.simctl_calls if "content_size" in c])

    def test_a_text_size_needs_a_hold_and_a_known_name(self) -> None:
        """Fails if: a text size needs a hold and a known name no longer holds."""
        with self.assertRaises(simguard.Refused):
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], env={}, text_size="accessibility-large")
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], env=HOLD, text_size="huge")
        self.assertEqual(self.world.content_size, {"reference": "large", "candidate": "large"})

    def test_a_setting_that_does_not_take_is_refused_and_nothing_runs(self) -> None:
        """Fails if: a setting that does not take is refused and nothing runs no longer holds."""
        original = self.world.__call__
        class Stuck(type(self.world)):
            def __call__(inner, argv, env=None, timeout=150.0):
                if list(argv[:3]) == ["xcrun", "simctl", "ui"] and argv[4:5] == ["content_size"] and len(argv) > 5:
                    return Result(0, "")
                return original(argv, env, timeout)
        self.world.__class__ = Stuck
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path, text_size="accessibility-large")
        self.assertEqual(self.world.calls["reference"], [])

    def test_an_end_stop_scrolls_both_halves_before_each_capture_and_reports_floating(self) -> None:
        """Fails if: an end stop scrolls both halves before each capture and reports floating no longer holds."""
        self.world.nodes["candidate"] = tree(690)
        ctx = self.context()
        faults.run_faults(ctx, plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path, stops=["end"])
        for side in ("reference", "candidate"):
            verbs = [c[0] for c in self.world.calls[side]]
            self.assertIn("scroll", verbs)
            self.assertEqual([c[1] for c in self.world.calls[side] if c[0] == "scroll"], ["bottom"] * verbs.count("scroll"))
            self.assertLess(verbs.index("scroll"), verbs.index("screenshot"))
        pair = read_json(ctx.run_dir / "manifest.json")["pairs"][0]
        self.assertEqual(pair["id"], "chores.empty.stop-end")
        self.assertIn("stop:end", pair["state"])
        self.assertEqual(sorted(pair["floating"]), ["candidate", "reference"])
        results = read_json(ctx.run_dir / "results.json")[0]
        self.assertTrue(results["floatingOverlap"]["candidate"]["intersects"])
        self.assertIn("Floating controls at the end stop", (ctx.run_dir / "results.md").read_text())

    def test_rest_and_end_make_two_pairs_and_an_unknown_stop_is_refused(self) -> None:
        """Fails if: rest and end make two pairs and an unknown stop is refused no longer holds."""
        ctx = self.context()
        faults.run_faults(ctx, plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path, stops=["rest", "end"])
        self.assertEqual([p["id"] for p in read_json(ctx.run_dir / "manifest.json")["pairs"]], ["chores.empty", "chores.empty.stop-end"])
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], env=HOLD, stops=["middle"])

    def test_a_page_that_ignores_scroll_is_dragged_with_swipe_until_it_stops_moving(self) -> None:
        """Fails if: a page that ignores scroll is dragged with swipe until it stops moving no longer holds."""
        self.world.scroll_works = False
        agent = capture.Agent("fake-agent reference", self.world)
        result = agent.scroll_bottom()
        self.assertEqual((result["success"], result["method"]), (True, "swipe"))
        swipes = [c for c in self.world.calls["reference"] if c[0] == "swipe"]
        self.assertEqual(len(swipes), 1)  # the fake page never moves, so the first swipe finds the end
        x, y1, x2, y2 = (float(v) for v in swipes[0][1:5])
        self.assertEqual(x, x2)
        self.assertGreater(y1, y2)

    def test_a_scroll_that_works_uses_no_swipe(self) -> None:
        """Fails if: a scroll that works uses no swipe no longer holds."""
        result = capture.Agent("fake-agent reference", self.world).scroll_bottom()
        self.assertEqual(result["method"], "scroll")
        self.assertFalse([c for c in self.world.calls["reference"] if c[0] == "swipe"])

    def test_a_rest_run_never_scrolls(self) -> None:
        """Fails if: a rest run never scrolls no longer holds."""
        faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path)
        self.assertFalse([c for c in self.world.calls["reference"] if c[0] == "scroll"])

    def test_both_simulators_are_left_clean(self) -> None:
        """Fails if: both simulators are left clean no longer holds."""
        faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path)
        self.assertNotIn("FENTON_GALLERY_EMPTY", self.reference_bootstrap()["variables"])
        cand = json.loads((self.world.root / "candidate" / "data" / launch.PREVIEW_SUBPATH / "bootstrap.json").read_text())
        self.assertNotIn("flags", cand)

    def test_the_candidate_is_staged_before_its_launch(self) -> None:
        """Fails if: the candidate is staged before its launch no longer holds."""
        launches = []
        original = faults.stage_candidate
        faults.stage_candidate = lambda d, f, r=None: (launches.append(f and f.id), original(d, f, r))[1]
        try:
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path)
        finally:
            faults.stage_candidate = original
        self.assertEqual(launches[0], "empty")

    def test_live_mode_is_refused_before_anything_runs(self) -> None:
        """Fails if: live mode is refused before anything runs no longer holds."""
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context("live"), plrun.select(SURFACES, ["chores"]), ["empty"], env={**HOLD, "PARITY_LIVE_GO": "1"})
        self.assertEqual(self.world.calls["reference"], [])

    def test_an_unpaired_surface_and_fault_is_refused(self) -> None:
        """Fails if: an unpaired surface and fault is refused no longer holds."""
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context(), plrun.select(SURFACES, ["home"]), ["empty"], env=HOLD)

    def test_an_unknown_fault_is_refused(self) -> None:
        """Fails if: an unknown fault is refused no longer holds."""
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["melt"], env=HOLD)

    def test_the_launcher_itself_refuses_live(self) -> None:
        """Fails if: the launcher itself refuses live no longer holds."""
        ctx = self.context("live")
        with self.assertRaises(faults.Refused):
            faults.fault_launcher()(ctx.halves["reference"], {"fault": "empty"}, capture.ReachPlan("gallery"), ctx)

    def test_a_failed_run_still_puts_both_text_sizes_back(self) -> None:
        """Fails if: a run that raises after the text size was set leaves either simulator at the large size."""
        self.world.content_size = {"reference": "medium", "candidate": "extra-large"}
        with self.assertRaises(launch.Refused):  # a changed pin makes run_all refuse after the size was set
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], "0" * 64, env=HOLD, pin_path=self.pin_path,
                              text_size="accessibility-large")
        self.assertEqual(self.world.content_size, {"reference": "medium", "candidate": "extra-large"})
        self.assertEqual([c[5] for c in self.world.simctl_calls if len(c) > 5 and c[4] == "content_size"][:2], ["accessibility-large"] * 2)

    def test_an_unreadable_starting_size_refuses_before_anything_is_set(self) -> None:
        """Fails if: a run sets a text size when it could not read the size to restore."""
        original = self.world.__call__

        class Unreadable(type(self.world)):
            def __call__(inner, argv, env=None, timeout=150.0):
                if list(argv[:3]) == ["xcrun", "simctl", "ui"] and argv[4:5] == ["content_size"] and len(argv) == 5:
                    return Result(1, "", "no such option")
                return original(argv, env, timeout)
        self.world.__class__ = Unreadable
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path,
                              text_size="accessibility-large")
        self.assertEqual(self.world.simctl_calls, [])
        self.assertEqual(self.world.calls["reference"], [])

    def test_a_restore_that_does_not_take_fails_loudly(self) -> None:
        """Fails if: the run ends quietly while a simulator is still at the large size."""
        self.world.content_size_set_budget = 2  # the two sets take; the two restores are ignored
        with self.assertRaises(faults.Refused) as caught:
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path,
                              text_size="accessibility-large")
        self.assertIn("restore did not take", str(caught.exception))
        self.assertIn("reference", str(caught.exception))
        self.assertIn("candidate", str(caught.exception))

    def test_a_protected_simulator_is_refused_before_anything_is_touched(self) -> None:
        """Fails if: a protected simulator is booted, launched on or reconfigured by a states run."""
        for udid in ("D14299B9-9F37-437D-85CE-208E13B01087", "366d4d0f", "366D4D0F-8AE1-44F1-988B-E4D2DBDD1672"):
            self.world.udid["reference"] = udid
            env = {"DEVCAP_HELD": f"simulator,device-{udid},device-UDID-CAND"}  # even a hold on it does not make it usable
            with self.assertRaises(simguard.Refused):
                faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=env, pin_path=self.pin_path,
                                  text_size="accessibility-large")
            self.assertEqual(self.world.calls["reference"], [])
            self.assertEqual(self.world.simctl_calls, [])

    def test_each_simulator_needs_its_own_device_hold(self) -> None:
        """Fails if: a run proceeds with a hold on only one of its simulators, or on the simulator pool alone."""
        for held in ("simulator", "simulator,device-UDID-REF", "simulator,device-UDID-CAND", "device-UDID-REF,device-UDID-CAND"):
            with self.assertRaises(simguard.Refused, msg=held):
                faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env={"DEVCAP_HELD": held},
                                  pin_path=self.pin_path)
        self.assertEqual(self.world.calls["reference"], [])

    def test_the_cli_refuses_a_protected_simulator_before_reading_a_container(self) -> None:
        """Fails if: the command line touches a container of a protected simulator."""
        status = faults.main(["run", "--surfaces", "chores", "--faults", "empty", "--reference-udid", "366D4D0F-8AE1-44F1-988B-E4D2DBDD1672",
                              "--reference-agent", "x", "--candidate-udid", "B", "--candidate-agent", "y", "--out", str(self.dir / "o")])
        self.assertEqual(status, 2)

    def test_the_renamed_publication_is_put_back_after_the_run(self) -> None:
        """Fails if: a run leaves the candidate's publication with the aligned names."""
        folder = self.world.root / "candidate" / "data" / launch.PREVIEW_SUBPATH
        (folder / "publication.json").write_text(json.dumps({"title": "Old Name"}))
        faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path,
                          renames={"Old Name": "New Name"})
        self.assertEqual(json.loads((folder / "publication.json").read_text()), {"title": "Old Name"})
        self.assertFalse((folder / faults.PRISTINE_PUBLICATION).exists())

    def test_a_failed_scroll_reports_end_stop_failed_not_no_overlap(self) -> None:
        """Fails if: a capture whose scroll to the end failed reads as "no overlap"."""
        self.world.scroll_works = False
        self.world.swipe_works = False
        ctx = self.context()
        faults.run_faults(ctx, plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path, stops=["end"])
        record = read_json(ctx.run_dir / "results.json")[0]
        self.assertEqual({v["endStop"] for v in record["floatingOverlap"].values()}, {"failed"})
        self.assertIsNone(record["floatingOverlap"]["candidate"]["intersects"])
        self.assertIn("end_stop: failed", (ctx.run_dir / "results.md").read_text())
        out = self.dir / "pub"
        faults.publish(ctx.run_dir, out, "iphone", "abc1234")
        self.assertIn("end_stop: failed", (out / "index.md").read_text())

    def test_the_cli_refuses_without_a_hold(self) -> None:
        """Fails if: the cli refuses without a hold no longer holds."""
        self.assertEqual(faults.main(["run", "--surfaces", "chores", "--faults", "empty", "--reference-udid", "A", "--reference-agent", "x",
                                      "--candidate-udid", "B", "--candidate-agent", "y", "--reference-pin", "none", "--out", str(self.dir / "o")]), 2)


NODES = [
    {"type": "NavigationBar", "label": None, "rect": {"x": 0, "y": 62, "width": 402, "height": 106}},
    {"type": "Button", "label": "Menu", "rect": {"x": 20, "y": 66, "width": 36, "height": 36}},
    {"type": "StaticText", "label": "Chores", "rect": {"x": 16, "y": 120, "width": 114, "height": 40}},
    {"type": "StaticText", "label": "Quick Links", "rect": {"x": 16, "y": 184, "width": 370, "height": 24}},
    {"type": "Button", "label": "Add Task", "rect": {"x": 252, "y": 731, "width": 133, "height": 52}},
    {"type": "TabBar", "label": "Tab Bar", "rect": {"x": 0, "y": 791, "width": 402, "height": 83}},
    {"type": "Button", "label": "Home", "rect": {"x": 25, "y": 795, "width": 77, "height": 54}},
    {"type": "Button", "label": "Close Navigation", "identifier": "nav.flyout.scrim", "rect": {"x": 300, "y": 62, "width": 102, "height": 812}},
]


class PageRegionTests(unittest.TestCase):
    def labels(self, rules):
        return [n["label"] for n in capture.normalize_ax(NODES, rules)]

    def test_shell_chrome_is_dropped_from_the_ax_by_type_and_frame(self) -> None:
        """Fails if: shell chrome is dropped from the ax by type and frame no longer holds."""
        self.assertEqual(self.labels(faults.SHELL_CHROME), ["Quick Links", "Add Task"])

    def test_without_the_rules_the_chrome_stays(self) -> None:
        """Fails if: without the rules the chrome stays no longer holds."""
        self.assertEqual(self.labels([]), ["Menu", "Chores", "Quick Links", "Add Task", "Tab Bar", "Home", "Close Navigation"])

    def test_page_content_is_never_dropped_with_the_chrome(self) -> None:
        """Fails if: page content is never dropped with the chrome no longer holds."""
        self.assertIn("Add Task", self.labels(faults.SHELL_CHROME))

    def test_masks_cover_the_bars_only_and_the_ax_only_rule_makes_none(self) -> None:
        """Fails if: masks cover the bars only and the ax only rule makes none no longer holds."""
        regions = capture.resolve_masks(NODES, faults.SHELL_CHROME)
        self.assertEqual(sorted((r["label"], r["y"], r["height"]) for r in regions), [("shell-nav", 62.0, 106.0), ("shell-tabbar", 791.0, 83.0)])

    def test_derive_adds_the_chrome_rules_only_on_request(self) -> None:
        """Fails if: derive adds the chrome rules only on request no longer holds."""
        row = {"id": "chores", "masks": [{"label": "clock", "ax_match": "x"}]}
        plain = faults.derive(row, faults.FAULTS["empty"])
        paged = faults.derive(row, faults.FAULTS["empty"], page_region=True)
        self.assertNotIn("mask_both_sides", plain)
        self.assertTrue(paged["mask_both_sides"])
        self.assertEqual([m["label"] for m in paged["masks"]], ["clock", "shell-nav", "shell-tabbar", "shell-flyout"])
        self.assertEqual(len(row["masks"]), 1)


def tree(fab_y, last_y=700):
    """A page: a scroll view holding a list whose last row is at ``last_y``, a floating button at ``fab_y``, a bar and a tab bar."""
    def node(i, kind, label, parent, x, y, w, h):
        return {"index": i, "type": kind, "label": label, "parentIndex": parent, "rect": {"x": x, "y": y, "width": w, "height": h}}
    return [node(0, "Application", "App", None, 0, 0, 402, 874),
            node(1, "NavigationBar", "", 0, 0, 62, 402, 54), node(2, "Button", "Menu", 1, 20, 66, 36, 36),
            node(3, "ScrollView", "", 0, 0, 0, 402, 874), node(4, "Other", "", 3, 16, 120, 370, 700),
            node(5, "StaticText", "Row one", 4, 16, 120, 370, 60), node(6, "StaticText", "Last row", 4, 16, last_y, 370, 60),
            node(7, "Other", "Vertical scroll bar, 2 pages", 3, 369, 116, 30, 600),
            node(8, "Button", "Add Task", 0, 16, fab_y, 370, 52),
            node(9, "TabBar", "Tab Bar", 0, 0, 791, 402, 83), node(10, "Button", "Home", 9, 25, 795, 77, 54)]


class FloatingTests(unittest.TestCase):
    def test_a_button_over_the_last_row_intersects(self) -> None:
        """Fails if: a button over the last row intersects no longer holds."""
        got = capture.floating_overlaps(tree(fab_y=690))
        self.assertTrue(got["intersects"])
        self.assertEqual(got["lastContent"]["label"], "Last row")
        self.assertEqual([f["label"] for f in got["floating"]], ["Add Task"])
        self.assertEqual([c["label"] for c in got["covers"]], ["Last row"])

    def test_a_button_clear_of_the_last_row_does_not(self) -> None:
        """Fails if: a button clear of the last row does not no longer holds."""
        got = capture.floating_overlaps(tree(fab_y=770))
        self.assertFalse(got["intersects"])
        self.assertEqual(got["covers"], [])

    def test_a_button_over_an_earlier_row_is_listed_in_covers_only(self) -> None:
        """Fails if: a button over an earlier row is listed in covers only no longer holds."""
        got = capture.floating_overlaps(tree(fab_y=110, last_y=700))
        self.assertFalse(got["intersects"])
        self.assertEqual([c["label"] for c in got["covers"]], ["Row one"])

    def test_chrome_buttons_and_scroll_bars_are_never_floating_controls_or_content(self) -> None:
        """Fails if: chrome buttons and scroll bars are never floating controls or content no longer holds."""
        got = capture.floating_overlaps(tree(fab_y=770))
        self.assertEqual([f["label"] for f in got["floating"]], ["Add Task"])
        self.assertNotIn("Vertical scroll bar, 2 pages", [c["label"] for c in got["covers"]])

    def test_an_invisible_control_is_not_floating(self) -> None:
        """Fails if: an invisible control is not floating no longer holds."""
        nodes = tree(fab_y=770)
        nodes.append({"index": 11, "type": "Button", "label": "Close Navigation", "parentIndex": 0, "hittable": False,
                      "rect": {"x": 300, "y": 62, "width": 102, "height": 812}})
        self.assertEqual([f["label"] for f in capture.floating_overlaps(nodes)["floating"]], ["Add Task"])
        nodes[-1].update(hittable=True, identifier="nav.flyout.scrim")  # reads as hittable on some runs: the identifier names it
        self.assertEqual([f["label"] for f in capture.floating_overlaps(nodes)["floating"]], ["Add Task"])

    def test_an_empty_state_in_its_own_scroll_view_counts_as_content(self) -> None:
        """Fails if: an empty state in its own scroll view counts as content no longer holds."""
        nodes = tree(fab_y=700, last_y=300)
        nodes += [{"index": 11, "type": "ScrollView", "label": "", "parentIndex": 0, "rect": {"x": 0, "y": 424, "width": 402, "height": 356}},
                  {"index": 12, "type": "StaticText", "label": "Nothing due", "parentIndex": 11, "rect": {"x": 72, "y": 690, "width": 257, "height": 20}}]
        got = capture.floating_overlaps(nodes)
        self.assertEqual(got["lastContent"]["label"], "Nothing due")
        self.assertTrue(got["intersects"])

    def test_no_scroll_view_or_no_content_is_reported_empty(self) -> None:
        """Fails if: no scroll view or no content is reported empty no longer holds."""
        self.assertIsNone(capture.floating_overlaps([])["scrollView"])
        bare = [n for n in tree(700) if n["index"] in (0, 3)]
        self.assertFalse(capture.floating_overlaps(bare)["intersects"])


class EndStopTests(unittest.TestCase):
    def test_derive_tags_and_ids_the_stop(self) -> None:
        """Fails if: derive tags and ids the stop no longer holds."""
        row = faults.derive({"id": "chores"}, faults.FAULTS["empty"], stop="end", text_size="accessibility-large")
        self.assertEqual((row["id"], row["stop"]), ("chores.empty.accessibility-large.stop-end", "end"))
        self.assertIn("stop:end", row["state_tags"])
        rest = faults.derive({"id": "chores"}, faults.FAULTS["empty"])
        self.assertNotIn("stop-", rest["id"])

    def test_annotate_puts_the_result_on_the_record_and_markdown_lists_it(self) -> None:
        """Fails if: annotate puts the result on the record and markdown lists it no longer holds."""
        records = [{"id": "p", "verdict": "fail"}, {"id": "q", "verdict": "pass"}]
        found = capture.floating_overlaps(tree(690))
        plrun.annotate_floating(records, [{"id": "p", "floating": {"reference": found, "candidate": capture.floating_overlaps(tree(770))}}, {"id": "q"}])
        self.assertTrue(records[0]["floatingOverlap"]["reference"]["intersects"])
        self.assertFalse(records[0]["floatingOverlap"]["candidate"]["intersects"])
        self.assertNotIn("floatingOverlap", records[1])
        text = plrun.floating_markdown(records)
        self.assertIn("| p | reference | Last row | Add Task | yes | Last row |", text)
        self.assertIn("| p | candidate | Last row | Add Task | no | none |", text)


class SimGuardTests(unittest.TestCase):
    def test_protected_udids_match_whole_or_first_eight_in_any_case(self) -> None:
        """Fails if: a protected simulator slips through as a short or lower-case UDID."""
        for udid in ("D14299B9", "d14299b9", "366D4D0F-8AE1-44F1-988B-E4D2DBDD1672", " 366d4d0f "):
            self.assertTrue(simguard.is_protected(udid), udid)
        for udid in ("", "D14299", "74239575-A116-4C48-BEA0-599948E52E39", "2559ED4B-6DBA-4B56-B92F-2C2C7DC3CF31"):
            self.assertFalse(simguard.is_protected(udid), udid)

    def test_guard_needs_the_pool_and_every_device_gate(self) -> None:
        """Fails if: guard accepts a missing pool gate or a missing device gate."""
        simguard.guard(["A", "B"], {"DEVCAP_HELD": "simulator,device-A,device-B"})
        for held in ("", "simulator", "simulator,device-A", "device-A,device-B"):
            with self.assertRaises(simguard.Refused, msg=held):
                simguard.guard(["A", "B"], {"DEVCAP_HELD": held})

    def test_protection_wins_over_a_hold(self) -> None:
        """Fails if: a hold on a protected simulator lets a tool use it."""
        with self.assertRaises(simguard.Refused) as caught:
            simguard.guard(["366D4D0F-8AE1-44F1-988B-E4D2DBDD1672"], {"DEVCAP_HELD": "simulator,device-366D4D0F-8AE1-44F1-988B-E4D2DBDD1672"})
        self.assertIn("protected", str(caught.exception))


class RenameTests(unittest.TestCase):
    def test_exact_strings_are_replaced_at_any_depth(self) -> None:
        """Fails if: exact strings are replaced at any depth no longer holds."""
        got = faults.apply_renames({"a": ["Old Name", {"b": "Old Name"}], "c": "Old Name here", "d": 3}, {"Old Name": "New Name"})
        self.assertEqual(got, {"a": ["New Name", {"b": "New Name"}], "c": "Old Name here", "d": 3})

    def test_staging_renames_the_publication_only(self) -> None:
        """Fails if: staging renames the publication only no longer holds."""
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / launch.PREVIEW_SUBPATH
            folder.mkdir(parents=True)
            (folder / "bootstrap.json").write_text(json.dumps({"entities": {}}))
            (folder / "publication.json").write_text(json.dumps({"tiles": [{"title": "Old Name"}]}))
            faults.stage_candidate(Path(tmp), None, {"Old Name": "New Name"})
            self.assertEqual(json.loads((folder / "publication.json").read_text()), {"tiles": [{"title": "New Name"}]})
            self.assertEqual(json.loads((folder / "bootstrap.json").read_text()), {"entities": {}})


class EvidenceTests(unittest.TestCase):
    def test_side_by_side_is_the_two_widths_plus_the_gap(self) -> None:
        """Fails if: side by side is the two widths plus the gap no longer holds."""
        with tempfile.TemporaryDirectory() as tmp:
            a = solid(Path(tmp) / "a.png", (200, 0, 0), size=(10, 8))
            b = solid(Path(tmp) / "b.png", (0, 0, 200), size=(6, 12))
            out = faults.side_by_side(a, b, Path(tmp) / "o" / "s.png", gap=4)
            raster = png_raster.read(out)
            self.assertEqual(raster.size, (20, 12))
            self.assertEqual(tuple(raster.row(0)[0:3]), (200, 0, 0))
            self.assertEqual(tuple(raster.row(0)[14 * 3:14 * 3 + 3]), (0, 0, 200))

    def test_publish_writes_one_image_per_state_and_an_index(self) -> None:
        """Fails if: publish writes one image per state and an index no longer holds."""
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, out = Path(tmp) / "run", Path(tmp) / "out"
            solid(run_dir / "chores.empty" / "reference.png")
            solid(run_dir / "chores.empty" / "candidate.png")
            (run_dir / "manifest.json").write_text(json.dumps({"pairs": [
                {"id": "chores.empty", "reference_png": "chores.empty/reference.png", "candidate_png": "chores.empty/candidate.png"},
                {"id": "x.y", "skipped": "no link", "reference_png": ""}]}))
            (run_dir / "results.json").write_text(json.dumps([{"id": "chores.empty", "verdict": "fail"}]))
            rows = faults.publish(run_dir, out, "iphone", "abc1234")
            self.assertEqual([r["verdict"] for r in rows], ["fail", "skipped"])
            self.assertTrue((out / "chores.empty-iphone.png").is_file())
            self.assertIn("| chores.empty | fail |", (out / "index.md").read_text())


if __name__ == "__main__":
    unittest.main()
