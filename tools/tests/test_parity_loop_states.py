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
from parity_loop import capture, faults, launch, run as plrun, sidecar, states  # noqa: E402
from parity_loop.common import read_json  # noqa: E402
from parity_loop_fakes import FakeWorld, solid  # noqa: E402

SURFACES = read_json(states.SURFACES_FILE)
BY_ID = {s["id"]: s for s in SURFACES["surfaces"]}
HOLD = {"DEVCAP_HELD": "simulator"}
plrun.DEVICES.setdefault("test", {"scale": 1, "pose": "folded", "size": [120, 200]})


def catalog(*items):
    return {"items": [dict({"devices": ["iphone", "duo", "ipad"], "area": "a"}, **i) for i in items]}


def surface(sid, **kw):
    return dict({"id": sid, "in_scope": True, "presence": "both", "reach": {}, "deep_link": {}}, **kw)


class CoverageTests(unittest.TestCase):
    def test_a_row_per_surface_and_family_the_atlas_lists(self) -> None:
        doc = states.build(catalog({"id": "home", "kind": "page"}, {"id": "loc", "kind": "modal", "devices": ["iphone", "duo"]}),
                           {"surfaces": [surface("home"), surface("loc")]})
        self.assertEqual(sorted((r["id"], r["family"]) for r in doc["rows"]),
                         [("home", "duo"), ("home", "ipad"), ("home", "iphone"), ("loc", "duo"), ("loc", "iphone")])
        self.assertEqual(doc["counts"]["total"], {"covered": 5, "missing": 0, "skipped": 0, "total": 5})

    def test_proposals_and_watch_are_not_rows(self) -> None:
        doc = states.build(catalog({"id": "p", "kind": "proposal"}, {"id": "w", "kind": "page", "devices": ["watch"]}), {"surfaces": []})
        self.assertEqual(doc["rows"], [])

    def test_component_without_a_row_is_missing_and_reads_studio(self) -> None:
        doc = states.build(catalog({"id": "tile", "kind": "component", "mockup": "components/tile.html", "presentedFrom": ["home"]}), {"surfaces": []})
        row = doc["rows"][0]
        self.assertEqual((row["status"], row["reference_source"], row["candidate_source"]), ("missing", "studio", "native"))
        self.assertIn("home", row["reach_candidate"])
        self.assertIn("Studio", row["reach_reference"])

    def test_native_only_and_out_of_scope_are_not_covered(self) -> None:
        doc = states.build(catalog({"id": "n", "kind": "page"}, {"id": "o", "kind": "page"}, {"id": "e", "kind": "modal"}),
                           {"surfaces": [surface("n", presence="native-only"), surface("o", in_scope=False), surface("e", presence="expo-only")]})
        by = {r["id"]: r for r in doc["rows"] if r["family"] == "duo"}
        self.assertEqual((by["n"]["status"], by["n"]["reference_source"]), ("missing", "studio"))
        self.assertEqual(by["o"]["status"], "skipped")
        self.assertEqual(by["e"]["status"], "skipped")

    def test_reach_text_names_gallery_page_press_path_and_link(self) -> None:
        row = surface("c", gallery_page="chores", reach={"reference": [{"press": "Chores"}], "candidate": [{"press": "A"}, {"press": "B"}]},
                      deep_link={"candidate": "x://y"})
        reach = states.reach_text(row, {"id": "c"})
        self.assertEqual(reach["reference"], "gallery page chores; press Chores")
        self.assertEqual(reach["candidate"], "press A > B; deep link")

    def test_state_classes_come_from_hint_words(self) -> None:
        self.assertEqual(states.state_classes(["offline (chip)", "Empty list", "unavailable", "loading"]), ["empty", "loading", "offline", "unavailable"])
        self.assertEqual(states.state_classes(["ax5"]), [])

    def test_the_shipped_atlas_joins_every_page_modal_and_flow(self) -> None:
        doc = states.build(read_json(states.CATALOG_FILE), SURFACES)
        counts = doc["counts"]["by_kind"]
        for kind in ("page", "modal", "flow"):
            self.assertEqual(counts[kind]["missing"] + counts[kind]["covered"] + counts[kind]["skipped"], counts[kind]["total"])
        self.assertEqual(counts["component"]["covered"], 0)
        self.assertGreater(counts["modal"]["covered"], 100)

    def test_markdown_lists_rows_of_one_status(self) -> None:
        doc = states.build(catalog({"id": "tile", "kind": "component"}), {"surfaces": []})
        text = states.markdown(doc, "missing")
        self.assertIn("| tile | component | iphone | studio |", text)

    def test_cli_writes_json_and_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out, md = Path(tmp) / "c.json", Path(tmp) / "c.md"
            self.assertEqual(states.main(["--json", str(out), "--markdown", str(md)]), 0)
            self.assertEqual(read_json(out)["schema"], "parity-states-coverage/1")
            self.assertIn("| all |", md.read_text())

    def test_cli_reports_a_missing_file(self) -> None:
        self.assertEqual(states.main(["--catalog", "/nonexistent/c.json"]), 2)


class FaultTableTests(unittest.TestCase):
    def test_every_class_the_brief_names_is_staged(self) -> None:
        self.assertEqual({f.state_class for f in faults.FAULTS.values()}, {"error", "unavailable", "offline", "loading", "empty"})

    def test_native_flag_keys_are_the_preview_flags(self) -> None:
        known = {"connection", "failCalls", "empty", "gateDelayMs", "animationsPaused", "reduceMotion"}
        self.assertTrue(faults.MANAGED_FLAGS <= known)

    def test_reference_variables_are_gallery_names_only(self) -> None:
        for name in faults.MANAGED_VARIABLES:
            self.assertTrue(name.startswith("FENTON_GALLERY_"), name)

    def test_a_delay_must_match_on_both_sides_and_stay_in_range(self) -> None:
        loading = faults.FAULTS["loading"]
        faults.check_fault(loading)
        with self.assertRaises(faults.Refused):
            faults.check_fault(faults.Fault("x", "loading", {"FENTON_GALLERY_GATE_DELAY_MS": "10"}, {"gateDelayMs": 20}, frozenset()))
        with self.assertRaises(faults.Refused):
            faults.check_fault(faults.Fault("x", "loading", {}, {"gateDelayMs": 61_000}, frozenset()))

    def test_matrix_pairs_only_where_the_reference_has_a_mechanism(self) -> None:
        rows = faults.matrix(SURFACES["surfaces"])
        got = {(r["surface"], r["fault"]) for r in rows if r["status"] == "paired"}
        self.assertIn(("chores", "empty"), got)
        self.assertIn(("security", "unavailable"), got)
        self.assertIn(("performance-screen", "loading"), got)
        self.assertNotIn(("home", "empty"), got)
        self.assertEqual(next(r for r in rows if (r["surface"], r["fault"]) == ("home", "empty"))["status"], "no-reference")

    def test_write_surfaces_are_never_in_the_matrix(self) -> None:
        writes = {s["id"] for s in SURFACES["surfaces"] if s.get("writes_on_reach")}
        self.assertTrue(writes)
        self.assertTrue(writes.isdisjoint({r["surface"] for r in faults.matrix(SURFACES["surfaces"])}))

    def test_matrix_markdown_names_each_fault(self) -> None:
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
        (self.data / launch.FIXTURE_SUBPATH / "receipt.json").write_text("{}")
        faults.stage_reference(self.data, "chores", faults.FAULTS["empty"])
        config = json.loads(self.ref.read_text())
        self.assertEqual(config["variables"], {"FENTON_GALLERY": "chores", "FENTON_GALLERY_SCHEME": "light", "FENTON_GALLERY_EMPTY": "1"})
        self.assertFalse((self.data / launch.FIXTURE_SUBPATH / "receipt.json").exists())

    def test_the_next_fault_replaces_the_last_and_clean_removes_it(self) -> None:
        faults.stage_reference(self.data, "security", faults.FAULTS["error"])
        faults.stage_reference(self.data, "security", faults.FAULTS["unavailable"])
        variables = json.loads(self.ref.read_text())["variables"]
        self.assertNotIn("FENTON_GALLERY_FAIL", variables)
        self.assertEqual(variables["FENTON_GALLERY_SCENARIO"], "unavailable")
        faults.stage_reference(self.data, "security", None)
        self.assertEqual(set(json.loads(self.ref.read_text())["variables"]), {"FENTON_GALLERY", "FENTON_GALLERY_SCHEME"})

    def test_loading_pauses_the_reference_arcs_and_clean_unpauses(self) -> None:
        faults.stage_reference(self.data, "performance", faults.FAULTS["loading"])
        config = json.loads(self.ref.read_text())
        self.assertTrue(config["pauseContinuousAnimations"])
        self.assertEqual(config["variables"]["FENTON_GALLERY_GATE_DELAY_MS"], "20000")
        faults.stage_reference(self.data, "performance", None)
        self.assertNotIn("pauseContinuousAnimations", json.loads(self.ref.read_text()))

    def test_candidate_flags_replace_managed_ones_and_keep_the_rest(self) -> None:
        faults.stage_candidate(self.data, faults.FAULTS["offline"])
        self.assertEqual(json.loads(self.cand.read_text())["flags"], {"reduceMotion": True, "connection": "offline"})
        faults.stage_candidate(self.data, faults.FAULTS["empty"])
        self.assertEqual(json.loads(self.cand.read_text())["flags"], {"reduceMotion": True, "empty": True})
        faults.stage_candidate(self.data, None)
        self.assertEqual(json.loads(self.cand.read_text())["flags"], {"reduceMotion": True})

    def test_unavailable_changes_entities_and_a_later_fault_undoes_it(self) -> None:
        faults.stage_candidate(self.data, faults.FAULTS["unavailable"])
        self.assertEqual(json.loads(self.cand.read_text())["entities"][KEY]["state"], "unavailable")
        faults.stage_candidate(self.data, None)
        config = json.loads(self.cand.read_text())
        self.assertEqual(config["entities"][KEY]["state"], "locked")
        self.assertNotIn("_pristine_entities", config)

    def test_a_missing_bootstrap_is_refused(self) -> None:
        self.cand.unlink()
        with self.assertRaises(faults.Refused):
            faults.stage_candidate(self.data, None)

    def test_staging_touches_no_secret_or_server_key(self) -> None:
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

    def test_both_simulators_are_left_clean(self) -> None:
        faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path)
        self.assertNotIn("FENTON_GALLERY_EMPTY", self.reference_bootstrap()["variables"])
        cand = json.loads((self.world.root / "candidate" / "data" / launch.PREVIEW_SUBPATH / "bootstrap.json").read_text())
        self.assertNotIn("flags", cand)

    def test_the_candidate_is_staged_before_its_launch(self) -> None:
        launches = []
        original = faults.stage_candidate
        faults.stage_candidate = lambda d, f: (launches.append(f and f.id), original(d, f))[1]
        try:
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["empty"], self.pin, env=HOLD, pin_path=self.pin_path)
        finally:
            faults.stage_candidate = original
        self.assertEqual(launches[0], "empty")

    def test_live_mode_is_refused_before_anything_runs(self) -> None:
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context("live"), plrun.select(SURFACES, ["chores"]), ["empty"], env={**HOLD, "PARITY_LIVE_GO": "1"})
        self.assertEqual(self.world.calls["reference"], [])

    def test_an_unpaired_surface_and_fault_is_refused(self) -> None:
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context(), plrun.select(SURFACES, ["home"]), ["empty"], env=HOLD)

    def test_an_unknown_fault_is_refused(self) -> None:
        with self.assertRaises(faults.Refused):
            faults.run_faults(self.context(), plrun.select(SURFACES, ["chores"]), ["melt"], env=HOLD)

    def test_the_launcher_itself_refuses_live(self) -> None:
        ctx = self.context("live")
        with self.assertRaises(faults.Refused):
            faults.fault_launcher()(ctx.halves["reference"], {"fault": "empty"}, capture.ReachPlan("gallery"), ctx)

    def test_the_cli_refuses_without_a_hold(self) -> None:
        self.assertEqual(faults.main(["run", "--surfaces", "chores", "--faults", "empty", "--reference-udid", "A", "--reference-agent", "x",
                                      "--candidate-udid", "B", "--candidate-agent", "y", "--reference-pin", "none", "--out", str(self.dir / "o")]), 2)


class EvidenceTests(unittest.TestCase):
    def test_side_by_side_is_the_two_widths_plus_the_gap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            a = solid(Path(tmp) / "a.png", (200, 0, 0), size=(10, 8))
            b = solid(Path(tmp) / "b.png", (0, 0, 200), size=(6, 12))
            out = faults.side_by_side(a, b, Path(tmp) / "o" / "s.png", gap=4)
            raster = png_raster.read(out)
            self.assertEqual(raster.size, (20, 12))
            self.assertEqual(tuple(raster.row(0)[0:3]), (200, 0, 0))
            self.assertEqual(tuple(raster.row(0)[14 * 3:14 * 3 + 3]), (0, 0, 200))

    def test_publish_writes_one_image_per_state_and_an_index(self) -> None:
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
