"""Motion pairs (``tools/motion_pairs``): onset detection, curve fits, pairing, the inventory and the recorder's gates.

Everything runs on synthetic series and fake commands: no simulator, no video, no Swift. The frame-level tests need numpy and are
skipped without it (the curve and pairing maths is pure Python on purpose).
"""

import json
import math
import random
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.motion_pairs import curves, inventory, pair, record
from tools.parity_loop.common import Result  # noqa: F401
from tools.motion_pairs.scenarios import Scenario, Step

try:
    import numpy as np
    from tools.motion_pairs import progress
except ImportError:  # pragma: no cover
    np = None


def irregular_times(end_ms, seed=1):
    """Frame times like the recorder's: near pairs 5 ms apart, then 12 to 17 ms."""
    rng = random.Random(seed)
    t, out = 0.0, []
    while t <= end_ms:
        out.append(t)
        t += rng.choice([5, 12, 12, 17])
    return out


def sample(fn, end_ms=800, seed=1, noise=0.0):
    rng = random.Random(seed + 100)
    return [(t, fn(t) + (rng.gauss(0, noise) if noise else 0.0)) for t in irregular_times(end_ms, seed)]


class OnsetTests(unittest.TestCase):
    def motion(self, tap_at, move_at, move_ms=400, step=12):
        """A tap highlight (small change) at ``tap_at``, then ``move_ms`` of strong change from ``move_at``, then quiet."""
        series = [(float(t), 0.0) for t in range(0, 3000, step)]
        out = []
        for t, _ in series:
            d = 0.0
            if tap_at <= t < tap_at + 3 * step:
                d = 0.4
            elif move_at <= t < move_at + move_ms:
                d = 6.0 * math.sin(math.pi * (t - move_at) / move_ms) + 0.3
            out.append((t, d))
        return out

    def test_onset_skips_the_tap_highlight_and_reports_the_lead(self):
        events = curves.segment_events(self.motion(tap_at=900, move_at=1000))
        self.assertEqual(len(events), 1)
        self.assertGreaterEqual(events[0].onset_ms, 1000)
        self.assertLess(events[0].onset_ms, 1060)

    def test_two_moves_become_two_events_in_order(self):
        one = self.motion(900, 1000)
        both = one + [(t + 3000, d) for t, d in one]
        events = curves.segment_events(both)
        self.assertEqual(len(events), 2)
        self.assertLess(events[0].onset_ms, events[1].onset_ms)
        self.assertGreaterEqual(events[1].onset_ms, 4000)

    def test_a_short_burst_is_not_an_event(self):
        series = [(float(t), 0.0) for t in range(0, 2000, 12)]
        series = [(t, 5.0 if 500 <= t < 540 else d) for t, d in series]
        self.assertEqual(curves.segment_events(series), [])

    def test_a_burst_that_never_passes_the_onset_threshold_is_not_an_event(self):
        series = [(float(t), 0.4 if 500 <= t < 900 else 0.0) for t in range(0, 2000, 12)]
        self.assertEqual(curves.segment_events(series), [])
        self.assertEqual(len(curves.segment_events(series, onset_threshold=0.2)), 1)

    def test_a_late_frame_gap_is_reported(self):
        events = curves.segment_events(self.motion(900, 1000, step=12))
        self.assertGreaterEqual(events[0].max_gap_ms, 11.9)


class ProgressTests(unittest.TestCase):
    def test_interpolate_clamps_and_blends(self):
        s = [(0.0, 0.0), (100.0, 1.0)]
        self.assertEqual(curves.interpolate(s, -5), 0.0)
        self.assertEqual(curves.interpolate(s, 500), 1.0)
        self.assertAlmostEqual(curves.interpolate(s, 25), 0.25)
        self.assertEqual(curves.interpolate([], 1), 0.0)

    def test_onset_of_progress_interpolates_the_crossing(self):
        s = [(0.0, 0.0), (10.0, 0.0), (20.0, 0.1), (30.0, 0.5)]
        self.assertAlmostEqual(curves.onset_of_progress(s, 0.02), 12.0)
        self.assertIsNone(curves.onset_of_progress([(0.0, 0.0), (5.0, 0.01)], 0.02))

    def test_settle_time_is_the_last_exit_from_the_band(self):
        f = curves.bezier(0, 0, 0.58, 1)
        s = sample(lambda t: f(t / 400), 800)
        settle = curves.settle_time(s)
        self.assertGreater(settle, 300)
        self.assertLess(settle, 400)
        self.assertTrue(all(abs(p - 1) <= 0.02 + 1e-9 for t, p in s if t > settle + 1))

    def test_settle_time_none_when_never_settled(self):
        self.assertIsNone(curves.settle_time([(0.0, 0.0), (100.0, 0.5)]))

    def test_a_spring_that_rings_settles_after_its_last_overshoot(self):
        f = curves.spring(0.4, 0.4)
        s = sample(lambda t: f(t / 1000), 1500)
        self.assertGreater(curves.overshoot(s), 0.05)
        self.assertGreater(curves.settle_time(s), 300)

    def test_median_curve_ignores_one_hitchy_take(self):
        f = curves.bezier(0, 0, 0.58, 1)
        good = [sample(lambda t: f(t / 400), 700, seed=s) for s in (1, 2, 3, 4)]
        slow = sample(lambda t: f(t / 900), 1000, seed=9)
        med = curves.median_curve(good + [slow])
        self.assertAlmostEqual(curves.interpolate(med, 400), 1.0, delta=0.03)

    def test_curve_distance_zero_for_equal_and_positive_for_shifted(self):
        a = [(float(t), min(t / 400, 1.0)) for t in range(0, 700, 10)]
        b = [(float(t), min(max(t - 80, 0) / 400, 1.0)) for t in range(0, 700, 10)]
        self.assertEqual(curves.curve_distance(a, a)["rmse"], 0.0)
        self.assertGreater(curves.curve_distance(a, b)["rmse"], 0.1)
        self.assertEqual(curves.curve_distance([], b)["rmse"], 1.0)


class FitTests(unittest.TestCase):
    def test_recovers_an_ease_out_and_its_duration(self):
        f = curves.bezier(0, 0, 0.58, 1)
        fit = curves.fit_curve(sample(lambda t: f(t / 400), 700, noise=0.003))
        self.assertEqual(fit.family, "ease-out")
        self.assertAlmostEqual(fit.params["duration_ms"], 400, delta=40)
        self.assertLess(fit.rmse, 0.02)

    def test_recovers_ease_in_out(self):
        f = curves.bezier(0.42, 0, 0.58, 1)
        fit = curves.fit_curve(sample(lambda t: f(t / 600), 900, seed=3))
        self.assertEqual(fit.family, "ease-in-out")
        self.assertAlmostEqual(fit.params["duration_ms"], 600, delta=50)

    def test_recovers_linear(self):
        fit = curves.fit_curve(sample(lambda t: min(t / 300, 1.0), 600, seed=4))
        self.assertEqual(fit.family, "linear")

    def test_recovers_a_bouncy_spring(self):
        f = curves.spring(0.5, 0.2)
        fit = curves.fit_curve(sample(lambda t: f(t / 1000), 1400, seed=5, noise=0.002))
        self.assertEqual(fit.family, "spring")
        self.assertAlmostEqual(fit.params["bounce"], 0.2, delta=0.1)
        self.assertAlmostEqual(fit.params["duration_ms"], 500, delta=100)

    def test_a_series_that_never_settles_has_no_fit(self):
        self.assertIsNone(curves.fit_curve(sample(lambda t: t / 2000, 500)))

    def test_too_few_samples_has_no_fit(self):
        self.assertIsNone(curves.fit_curve([(0.0, 0.0), (10.0, 0.5), (20.0, 1.0)]))

    def test_fit_serialises(self):
        f = curves.bezier(0, 0, 0.58, 1)
        out = curves.fit_curve(sample(lambda t: f(t / 400), 700)).as_json()
        self.assertIn("rmse", out)
        json.dumps(out)

    def test_bezier_endpoints_and_monotone(self):
        f = curves.bezier(0.25, 0.1, 0.25, 1)
        self.assertEqual((f(0), f(1)), (0.0, 1.0))
        values = [f(i / 50) for i in range(51)]
        self.assertEqual(values, sorted(values))

    def test_spring_starts_at_rest_ends_at_one_and_critical_has_no_overshoot(self):
        crit = curves.spring(0.4, 0.0)
        self.assertEqual(crit(0), 0.0)
        self.assertLess(max(crit(i / 100) for i in range(150)), 1.0)
        self.assertAlmostEqual(crit(3.0), 1.0, places=3)
        self.assertGreater(max(curves.spring(0.4, 0.3)(i / 100) for i in range(150)), 1.0)

    def test_classify_motion(self):
        self.assertEqual(curves.classify_motion(0.3, "x"), "slide-x")
        self.assertEqual(curves.classify_motion(2.3, "x"), "fade")
        self.assertEqual(curves.classify_motion(None, None), "none")
        self.assertEqual(curves.classify_motion(0.3, None), "fade")


def summary(settle, lead=60.0, spread=5.0, kind="slide-x", overshoot=0.0, family="ease-out", duration=None):
    f = curves.bezier(0, 0, 0.58, 1)
    return {"takes": 5, "usable": 5, "settleMs": settle, "settleSpreadMs": spread, "leadMs": lead, "leadSpreadMs": 4.0,
            "overshoot": overshoot, "kind": kind, "curve": [(float(t), f(t / (duration or settle))) for t in range(0, int(settle * 1.4), 10)]}


class PairTests(unittest.TestCase):
    def test_equal_sides_pass(self):
        v = pair.judge(summary(400), summary(400), pair.Tolerances())
        self.assertTrue(v["pass"], v)
        self.assertEqual(v["class"], "ok")

    def test_a_slower_side_fails_duration_and_curve(self):
        v = pair.judge(summary(350), summary(500), pair.Tolerances())
        self.assertFalse(v["pass"])
        self.assertIn("duration", v["verdict"])
        self.assertFalse(v["checks"]["duration"]["pass"])

    def test_a_small_difference_is_inside_the_duration_limit(self):
        v = pair.judge(summary(400), summary(430), pair.Tolerances())
        self.assertTrue(v["checks"]["duration"]["pass"])

    def test_a_different_type_fails_whatever_the_numbers(self):
        v = pair.judge(summary(400), summary(400, kind="fade"), pair.Tolerances())
        self.assertFalse(v["pass"])
        self.assertIn("type", v["verdict"])

    def test_noise_widens_the_duration_limit(self):
        noisy = pair.judge(summary(350, spread=80), summary(500, spread=80), pair.Tolerances())
        self.assertTrue(noisy["checks"]["duration"]["pass"])
        self.assertEqual(noisy["checks"]["duration"]["limit"], 160.0)

    def test_overshoot_difference_gates(self):
        v = pair.judge(summary(400), summary(400, overshoot=0.08), pair.Tolerances())
        self.assertFalse(v["checks"]["overshoot"]["pass"])

    def test_frame_diff_is_reported_but_does_not_gate_by_default(self):
        v = pair.judge(summary(400), summary(400), pair.Tolerances(), {"mean": 0.7, "worst": 0.9})
        self.assertFalse(v["checks"]["frameDiff"]["pass"])
        self.assertFalse(v["checks"]["frameDiff"]["gate"])
        self.assertTrue(v["pass"])
        gated = pair.Tolerances(gate=["frameDiff"])
        self.assertFalse(pair.judge(summary(400), summary(400), gated, {"mean": 0.7, "worst": 0.9})["pass"])

    def test_unusable_takes_are_unmeasured_not_passed(self):
        v = pair.judge({"takes": 5, "usable": 0}, summary(400), pair.Tolerances())
        self.assertFalse(v["pass"])
        self.assertEqual(v["verdict"], "unmeasured")
        self.assertEqual(v["class"], "infra")

    def test_tolerances_load_and_reject_unknown_names(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "t.json"
            path.write_text(json.dumps({"durationMs": 80, "curveRmse": 0.1}))
            tol = pair.Tolerances.load(path)
            self.assertEqual((tol.durationMs, tol.curveRmse, tol.leadMs), (80, 0.1, 50.0))
            path.write_text(json.dumps({"nope": 1}))
            with self.assertRaises(ValueError):
                pair.Tolerances.load(path)
        self.assertEqual(pair.Tolerances.load(None).durationMs, 40.0)

    def test_mad_is_robust_to_one_outlier(self):
        self.assertEqual(pair.mad([380, 400, 420, 410, 2000]), 10.0)
        self.assertEqual(pair.mad([]), 0.0)

    def test_summarize_side_takes_medians_and_skips_unfound(self):
        f = curves.bezier(0, 0, 0.58, 1)
        take = lambda settle, kind="slide-x": {"found": True, "settleMs": settle, "leadToOnsetMs": 40.0, "overshoot": 0.0, "kind": kind,
                                               "slideRatio": 0.6, "progress": [(float(t), f(t / settle)) for t in range(0, int(settle * 1.4), 10)]}
        out = pair.summarize_side([take(380), take(400), take(900), {"found": False}])
        self.assertEqual(out["usable"], 3)
        self.assertEqual(out["settleMs"], 400)
        self.assertEqual(out["kind"], "slide-x")
        self.assertEqual(pair.summarize_side([{"found": False}])["usable"], 0)


class TapAnchorTests(unittest.TestCase):
    def side(self, rest, onset, late=0):
        f = curves.bezier(0, 0, 0.58, 1)
        take = lambda r, o, l: {"found": True, "settleMs": 300.0, "leadToOnsetMs": 40.0, "overshoot": 0.0, "kind": "slide-x", "slideRatio": 0.5,
                                "lateOnset": l, "tapToRestMs": r, "tapToOnsetMs": o,
                                "progress": [(float(t), f(t / 300)) for t in range(0, 420, 10)]}
        return pair.summarize_side([take(rest + d, onset + d, False) for d in (-5, 0, 5)] + [take(rest, onset + 300, True)] * late)

    def test_a_late_onset_take_still_counts_for_tap_to_settled_and_shows_as_latency(self):
        s = self.side(800, 450, late=2)
        self.assertEqual((s["usable"], s["lateOnsetTakes"], s["tapTakes"]), (3, 2, 5))
        self.assertEqual(s["tapRestMs"], 800)
        self.assertGreater(s["tapOnsetSpreadMs"] + 1, 0)

    def test_duration_uses_tap_to_settled_and_latency_is_its_own_check(self):
        ref, nat = self.side(800, 450), self.side(790, 600)
        v = pair.judge(ref, nat, pair.Tolerances())
        self.assertEqual(v["checks"]["duration"]["basis"], "tap to settled")
        self.assertTrue(v["checks"]["duration"]["pass"])
        self.assertFalse(v["checks"]["latency"]["pass"])
        self.assertIn("latency", v["verdict"])

    def test_a_side_with_only_hitched_takes_is_still_judged_on_the_tap_basis_without_curve_checks(self):
        ref = self.side(800, 450)
        nat = pair.summarize_side([{"found": True, "settleMs": 80.0, "leadToOnsetMs": 0.0, "overshoot": 0.0, "kind": "slide-x", "lateOnset": True,
                                    "tapToRestMs": 810.0, "tapToOnsetMs": 460.0, "progress": [(0.0, 0.6), (50.0, 1.0)]}] * 3)
        self.assertEqual(nat["usable"], 0)
        v = pair.judge(ref, nat, pair.Tolerances())
        self.assertEqual(v["verdict"], "unmeasured: curve")
        self.assertFalse(v["pass"])
        self.assertNotIn("curve", v["checks"])
        self.assertFalse(v["curveMeasured"])

    def test_without_taps_the_onset_basis_is_used(self):
        f = curves.bezier(0, 0, 0.58, 1)
        take = {"found": True, "settleMs": 300.0, "leadToOnsetMs": 40.0, "overshoot": 0.0, "kind": "slide-x", "slideRatio": 0.5,
                "progress": [(float(t), f(t / 300)) for t in range(0, 420, 10)]}
        s = pair.summarize_side([take] * 3)
        v = pair.judge(s, s, pair.Tolerances())
        self.assertEqual(v["basis"], "onset")
        self.assertEqual(v["checks"]["duration"]["basis"], "onset to settled")

    def test_load_taps_reads_the_telemetry_beside_the_clip(self):
        from tools.motion_pairs import taps
        with TemporaryDirectory() as tmp:
            clip = Path(tmp) / "reference-1.mp4"
            (Path(tmp) / "reference-1.gesture-telemetry.json").write_text(json.dumps(
                {"events": [{"kind": "tap", "tMs": 1500.5}, {"kind": "swipe", "tMs": 2000}, {"kind": "tap", "tMs": 3800}]}))
            self.assertEqual(taps.load_taps(clip), [1500.5, 3800.0])
            self.assertIsNone(taps.load_taps(Path(tmp) / "other.mp4"))

    def test_event_steps_name_the_tap_behind_each_event(self):
        sc = Scenario("s", "s", "p", [Step("a", event="x"), Step("b"), Step("c", event="y")])
        self.assertEqual(sc.event_steps(), [0, 2])


class InventoryTests(unittest.TestCase):
    def test_expectation_finds_tokens_and_seconds(self):
        e = inventory.expectation("fill cross-fades `state` 0.6 s (Reduce Motion 0.2 s); rows insert with `standard`")
        self.assertEqual(sorted(e["tokens"]), ["standard", "state"])
        self.assertEqual(e["seconds"], [0.6, 0.2])
        self.assertTrue(inventory.expectation("Cut, no motion")["cut"])
        self.assertEqual(inventory.expectation("the statement of standards")["tokens"], [])

    def test_a_page_reached_by_a_tab_then_a_manual_step_is_a_push(self):
        tab = {"reach": {"candidate": [{"press": "Chores"}]}}
        deeper = {"reach": {"candidate": [{"press": "Chores"}, {"manual": "Tile: <resident> chores"}]}}
        self.assertEqual(inventory.page_kind(tab, {"presentedFrom": []}), "tab-switch")
        self.assertEqual(inventory.page_kind(deeper, {"presentedFrom": []}), "push")

    def test_presentation_kinds(self):
        for text, kind in [("sheet (form, fitted)", "sheet"), ("push inside sheet", "push-in-sheet"), ("alert + TextField", "alert"),
                           ("confirmationDialog", "dialog"), ("fullScreenCover", "full-screen-cover"), (None, "sheet")]:
            self.assertEqual(inventory.presentation_kind(text), kind)

    def test_policy_rows_come_from_the_section_3_table(self):
        md = "## 3. Decisions\n\n| Surface | First | Again | Why |\n|---|---|---|---|\n| **Tab switch** | Cut | Cut | x |\n| **Push** | System push | Same | y |\n\n### What now\n"
        rows = inventory.policy_rows(md)
        self.assertEqual([r["id"] for r in rows], ["policy:tab-switch", "policy:push"])
        self.assertTrue(rows[0]["expect"]["cut"])

    def write_fixture(self, tmp):
        catalog = {"items": [
            {"id": "home", "kind": "page", "area": "home", "title": "Home", "presentedFrom": [], "patterns": ["motion"], "motionHint": ["colours cross-fade `state` 0.6 s"]},
            {"id": "room", "kind": "page", "area": "rooms", "title": "Room", "presentedFrom": ["rooms"], "patterns": [], "motionHint": []},
            {"id": "edit-sheet", "kind": "modal", "area": "home", "title": "Edit", "presentation": "sheet (form, fitted)", "presentedFrom": ["home"], "patterns": [], "motionHint": []},
            {"id": "flyout", "kind": "flow", "area": "shell", "title": "Flyout", "presentedFrom": [], "patterns": [], "motionHint": ["panel slides in, `standard` 0.3 s"]},
            {"id": "future", "kind": "proposal", "area": "home", "title": "Later", "presentedFrom": [], "patterns": [], "motionHint": ["spins"]},
        ]}
        surfaces = {"surfaces": [
            {"id": "home", "reach": {"reference": [{"press": "Home"}], "candidate": [{"press": "Home"}]}, "routes": {"reference": "tab Home", "candidate": "page-home"}},
            {"id": "room", "reach": {"reference": [{"press": "Rooms"}, {"press": "A room"}], "candidate": [{"press": "Rooms"}, {"press": "A room"}]}, "routes": {}},
        ]}
        motion = "## 3. Decisions\n\n| S | F | A | W |\n|---|---|---|---|\n| **Tab switch** | Cut | Cut | x |\n\n### What\n"
        (tmp / "catalog.json").write_text(json.dumps(catalog))
        (tmp / "surfaces.json").write_text(json.dumps(surfaces))
        (tmp / "motion.md").write_text(motion)
        (tmp / "patterns").mkdir()
        (tmp / "patterns" / "motion.md").write_text("x")

    def test_build_lists_every_named_transition_with_triggers(self):
        with TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            self.write_fixture(tmp)
            data = inventory.build(tmp / "catalog.json", tmp / "motion.md", tmp / "surfaces.json", tmp / "patterns")
        ids = [t["id"] for t in data["transitions"]]
        self.assertEqual(ids, ["home:tab-switch", "home:control-1", "room:push", "edit-sheet:sheet", "flyout:flow-1", "policy:tab-switch", "calibration:primary-button-enabled"])
        self.assertEqual(data["proposalsSkipped"], 1)
        self.assertEqual(data["count"], 7)
        by = {t["id"]: t for t in data["transitions"]}
        self.assertEqual(by["room:push"]["trigger"]["reference"]["steps"], ["Rooms", "A room"])
        self.assertEqual(by["room:push"]["trigger"]["status"], "mapped")
        self.assertEqual(by["edit-sheet:sheet"]["trigger"]["status"], "unmapped")
        self.assertEqual(by["edit-sheet:sheet"]["trigger"]["from"], ["home"])
        self.assertEqual(by["home:control-1"]["patterns"], ["motion"])
        self.assertEqual(by["home:control-1"]["expect"]["tokens"], ["state"])
        self.assertEqual(data["byKind"]["push"], 1)

    def test_committed_inventory_has_the_structure_every_row_needs(self):
        committed = json.loads((Path(inventory.__file__).with_name("transitions.json")).read_text(encoding="utf-8"))
        rows = committed["transitions"]
        self.assertEqual(committed["count"], len(rows))
        self.assertEqual(len({t["id"] for t in rows}), len(rows), "transition ids are unique")
        for t in rows:
            self.assertTrue({"id", "kind", "title", "expect"} <= set(t), t["id"])
            self.assertIn("text", t["expect"])
            if t["kind"] != "policy":
                self.assertEqual(sorted(t["trigger"]), ["from", "native", "reference", "status"], t["id"])
                self.assertIn(t["trigger"]["status"], ("mapped", "unmapped", "calibrated"), t["id"])
        calibrated = [t["id"] for t in rows if t.get("scenario")]
        self.assertTrue(calibrated and all(t in {r["id"] for r in rows} for t in calibrated))
        self.assertEqual(sum(committed["byKind"].values()), len(rows))



class SafetyTests(unittest.TestCase):
    """The shared simulator guard, a fixtures-only publication and an explicit launch environment, all before any side effect."""
    REF = "74239575-A116-4C48-BEA0-599948E52E39"
    NAT = "2559ED4B-6DBA-4B56-B92F-2C2C7DC3CF31"

    def devices(self, ref=None, nat=None):
        self.agents = {"reference": FakeAgent(), "native": FakeAgent()}
        return {"reference": record.Device("reference", ref or self.REF, self.agents["reference"]),
                "native": record.Device("native", nat or self.NAT, self.agents["native"])}

    def held(self, *udids):
        return {"DEVCAP_HELD": ",".join(["simulator"] + ["device-" + u for u in udids])}

    def scenario(self):
        return Scenario("s", "s", "chores", [Step('label="A"', 100, "push")], lead_ms=100)

    def refused(self, devices, env):
        with TemporaryDirectory() as tmp:
            out = Path(tmp) / "takes"
            with self.assertRaises(record.simguard.Refused):
                record.record_pair(devices, self.scenario(), out, 1, env=env)
            self.assertFalse(out.exists(), "nothing was created before the refusal")
        self.assertEqual([a.calls for a in self.agents.values()], [[], []], "no agent call before the refusal")

    def test_protected_simulators_are_refused_before_any_side_effect(self):
        for udid in ("D14299B9-9F37-437D-85CE-208E13B01087", "366D4D0F-8AE1-44F1-988B-E4D2DBDD1672"):
            devices = self.devices(nat=udid)
            self.refused(devices, self.held(self.REF, udid))

    def test_a_missing_per_device_hold_is_refused_before_any_side_effect(self):
        self.refused(self.devices(), self.held(self.REF))  # the native gate is not held
        self.refused(self.devices(), {"DEVCAP_HELD": "simulator"})
        self.refused(self.devices(), {})

    def test_held_simulators_pass_the_guard(self):
        original = record.record_take
        record.record_take = lambda *a, **k: record.Take("x", 1, ok=True)
        try:
            with TemporaryDirectory() as tmp:
                out = record.record_pair(self.devices(), self.scenario(), Path(tmp) / "t", 1, env=self.held(self.REF, self.NAT))
        finally:
            record.record_take = original
        self.assertTrue(all(t.ok for ts in out.values() for t in ts))

    def test_the_dry_run_reports_a_protected_simulator(self):
        plan = record.dry_run(self.scenario(), None, None, Path("/tmp/motion-dry-x"), {"reference": self.REF, "native": "366D4D0F-8AE1-44F1-988B-E4D2DBDD1672"}, {})
        self.assertTrue(any("protected" in p for p in plan["problems"]))

    def test_a_publication_for_a_live_server_is_refused(self):
        self.assertEqual(record.fixture_problems({"endpoint": "http://127.0.0.1:4801", "entities": {}}), [])
        self.assertTrue(record.fixture_problems({"live": {"server": "https://ha.example", "accountID": "x"}}))
        self.assertTrue(record.fixture_problems({"endpoint": "https://ha.example:8123"}))
        self.assertTrue(record.fixture_problems({"server": "https://ha.example"}))

    def test_validate_publication_reads_the_bootstrap_and_relaunch_refuses_before_any_command(self):
        with TemporaryDirectory() as tmp:
            pub = Path(tmp) / "pub"
            (pub / "assets").mkdir(parents=True)
            (pub / "publication.json").write_text("{}")
            (pub / "bootstrap.json").write_text(json.dumps({"live": {"server": "https://ha.example"}}))
            self.assertTrue(any("'live'" in p for p in record.validate_publication(pub)))
            calls = []
            dev = record.Device("native", "U", FakeAgent(), publication=pub)
            with self.assertRaises(record.Refused):
                record.relaunch(dev, self.scenario(), False, runner=lambda argv, env=None, timeout=0: calls.append(argv), sleep=lambda s: None)
            self.assertEqual(calls, [])
            (pub / "bootstrap.json").write_text(json.dumps({"endpoint": "http://127.0.0.1:4801"}))
            self.assertEqual(record.validate_publication(pub), [])

    def test_launch_env_drops_inherited_child_variables_and_keeps_the_allowlist(self):
        base = {"PATH": "/usr/bin", "SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN": "secret", "SIMCTL_CHILD_FENTON_HASS_SERVER": "https://ha.example"}
        env = record.launch_env(base, True, {"FENTON_UK_EXTRAS": "1"})
        self.assertEqual({k for k in env if k.startswith("SIMCTL_CHILD_")}, {"SIMCTL_CHILD_FENTON_SYSTEM_SETTINGS", "SIMCTL_CHILD_FENTON_UK_EXTRAS"})
        self.assertEqual(env["SIMCTL_CHILD_FENTON_SYSTEM_SETTINGS"], "reduceMotion")
        self.assertEqual(env["PATH"], "/usr/bin")
        self.assertEqual(record.launch_env(base, False, {})["SIMCTL_CHILD_FENTON_SYSTEM_SETTINGS"], "none")
        with self.assertRaises(record.Refused):
            record.launch_env(base, False, {"FENTON_HASS_TOKEN": "x"})


class VerdictTests(unittest.TestCase):
    """A row is a pass only when everything that gates was measured on both sides."""

    def take(self, kind="slide-x", late=False, rest=800.0, onset=450.0, settle=300.0):
        f = curves.bezier(0, 0, 0.58, 1)
        return {"found": True, "settleMs": settle if kind != "cut" else 0.0, "leadToOnsetMs": 40.0, "overshoot": 0.0, "kind": kind, "slideRatio": 0.5,
                "lateOnset": late or kind == "cut", "tapToRestMs": rest, "tapToOnsetMs": onset,
                "progress": [(float(t), f(t / 300)) for t in range(0, 420, 10)] if kind != "cut" else [(0.0, 0.98), (10.0, 1.0)]}

    def side(self, kind="slide-x", late=False, n=5):
        return pair.summarize_side([self.take(kind, late) for _ in range(n)])

    def test_a_fixture_polluted_row_is_never_a_pass(self):
        row = {"pass": True, "verdict": "pass", "class": "ok", "checks": {"duration": {"pass": True}}}
        pair.mark_polluted(row, "native drew another page")
        self.assertFalse(row["pass"])
        self.assertEqual((row["verdict"], row["class"]), ("fixture-polluted", "fixture-polluted"))
        self.assertEqual(row["measured"]["verdict"], "pass")
        self.assertEqual(row["fixtureNote"], "native drew another page")

    def test_a_row_whose_curve_was_not_measured_on_a_side_is_unmeasured_not_a_pass(self):
        ref, nat = self.side(), self.side(late=True)
        v = pair.judge(ref, nat, pair.Tolerances())
        self.assertEqual(v["verdict"], "unmeasured: curve")
        self.assertFalse(v["pass"])
        both_on_time = pair.judge(self.side(), self.side(), pair.Tolerances())
        self.assertTrue(both_on_time["pass"])

    def test_a_cut_against_a_cut_passes_only_when_the_row_expects_a_cut_and_both_sides_measured_one(self):
        ref, nat = self.side("cut"), self.side("cut")
        ok = pair.judge(ref, nat, pair.Tolerances(), expects_cut=True)
        self.assertTrue(ok["pass"], ok)
        self.assertEqual(ok["verdict"], "pass")
        unexpected = pair.judge(ref, nat, pair.Tolerances(), expects_cut=False)
        self.assertEqual(unexpected["verdict"], "unmeasured: cut")
        self.assertFalse(unexpected["pass"])
        mixed = pair.summarize_side([self.take("cut"), self.take("slide-x", late=True), self.take("slide-x", late=True), self.take("slide-x", late=True)])
        self.assertNotEqual(mixed["kind"], "cut")
        self.assertFalse(pair.judge(ref, mixed, pair.Tolerances(), expects_cut=True)["pass"])
        untapped = [{**self.take("cut"), "tapToRestMs": None, "tapToOnsetMs": None} for _ in range(5)]
        no_tap = pair.summarize_side(untapped)
        verdict = pair.judge(no_tap, no_tap, pair.Tolerances(), expects_cut=True)
        self.assertTrue(verdict["verdict"].startswith("unmeasured"))
        self.assertFalse(verdict["pass"])

    def test_a_cut_against_a_movement_fails_on_type(self):
        v = pair.judge(self.side("cut"), self.side("fade"), pair.Tolerances(), expects_cut=True)
        self.assertFalse(v["pass"])
        self.assertIn("type", v["verdict"])

    def test_the_scenario_knows_which_events_expect_a_cut(self):
        from tools.motion_pairs import calibration
        self.assertTrue(calibration.CONTROL.expects_cut("disable"))
        self.assertFalse(calibration.CONTROL.expects_cut("enable"))
        self.assertFalse(calibration.CHORES.expects_cut("push"))


class ScenarioTests(unittest.TestCase):
    def test_events_follow_the_steps_that_name_one(self):
        sc = Scenario("s", "s", "chores", [Step("a", event="push"), Step("b"), Step({"reference": "r", "native": "n"}, event="sheet", onset_threshold=0.2)])
        self.assertEqual([e.name for e in sc.events()], ["push", "sheet"])
        self.assertEqual(sc.steps[2].selector("native"), "n")
        self.assertEqual(sc.steps[0].selector("reference"), "a")
        self.assertEqual(sc.sequence_ms(), 1000 + 1600 * 3)


class FakeAgent:
    def __init__(self, duration_ms=9000, fail=None):
        self.calls, self.duration_ms, self.fail = [], duration_ms, fail

    def call(self, *args, **kw):
        self.calls.append(args)
        if args[:2] == ("record", "start"):
            Path(args[2]).write_bytes(b"x")
            return {"success": self.fail != "start"}
        if args[:2] == ("record", "stop"):
            return {"success": True, "data": {"durationMs": self.duration_ms}}
        return {"success": True}

    def open_app(self, *a, **k):
        self.calls.append(("open",) + a)
        return {"success": True}


class RecordTests(unittest.TestCase):
    def setUp(self):
        self.scenario = Scenario("s", "s", "chores", [Step('label="A"', 100, "push"), Step('label="B"', 100, "pop")], native_prepare=["Chores"], lead_ms=100)
        self.runner = lambda argv, env=None, timeout=0: record.run(["true"])

    def device(self, agent, side="native"):
        return record.Device(side, "UDID", agent)

    def test_gate_on_load(self):
        self.assertEqual(record.gate_on_load(40, lambda: 12.0), 12.0)
        with self.assertRaises(record.LoadTooHigh):
            record.gate_on_load(40, lambda: 40.0)

    def test_a_loaded_host_refuses_the_take_before_touching_the_device(self):
        agent = FakeAgent()
        with TemporaryDirectory() as tmp:
            take = record.record_take(self.device(agent), self.scenario, Path(tmp) / "t.mp4", 1, sleep=lambda s: None, load=lambda: 99.0)
        self.assertFalse(take.ok)
        self.assertTrue(take.reason.startswith("load"))
        self.assertEqual(agent.calls, [])

    def test_a_take_presses_the_steps_between_record_start_and_stop(self):
        agent = FakeAgent(duration_ms=1500)
        original = record.relaunch
        record.relaunch = lambda *a, **k: None
        try:
            with TemporaryDirectory() as tmp:
                take = record.record_take(self.device(agent), self.scenario, Path(tmp) / "t.mp4", 1, sleep=lambda s: None, load=lambda: 5.0)
        finally:
            record.relaunch = original
        self.assertTrue(take.ok, take.reason)
        names = [c[:2] for c in agent.calls]
        self.assertEqual(names[0], ("record", "start"))
        self.assertIn("--hide-touches", agent.calls[0])
        self.assertEqual([c[1] for c in agent.calls if c[0] == "press"], ['label="A"', 'label="B"'])
        self.assertEqual(names[-1], ("record", "stop"))

    def test_a_runaway_recording_is_discarded_as_infra(self):
        agent = FakeAgent(duration_ms=54000)
        original = record.relaunch
        record.relaunch = lambda *a, **k: None
        try:
            with TemporaryDirectory() as tmp:
                take = record.record_take(self.device(agent), self.scenario, Path(tmp) / "t.mp4", 1, sleep=lambda s: None, load=lambda: 5.0)
        finally:
            record.relaunch = original
        self.assertFalse(take.ok)
        self.assertIn("infra", take.reason)

    def test_record_start_failure_is_reported(self):
        original = record.relaunch
        record.relaunch = lambda *a, **k: None
        try:
            with TemporaryDirectory() as tmp:
                take = record.record_take(self.device(FakeAgent(fail="start")), self.scenario, Path(tmp) / "t.mp4", 1, sleep=lambda s: None, load=lambda: 5.0)
        finally:
            record.relaunch = original
        self.assertFalse(take.ok)
        self.assertIn("record start", take.reason)

    def test_relaunch_sets_reduce_motion_explicitly_and_reaches_native_start(self):
        seen = []

        def runner(argv, env=None, timeout=0):
            seen.append((argv, (env or {}).get("SIMCTL_CHILD_FENTON_SYSTEM_SETTINGS")))
            return record.run(["true"])
        agent = FakeAgent()
        dev = record.Device("native", "U", agent)
        record.relaunch(dev, self.scenario, True, runner=runner, sleep=lambda s: None)
        launches = [s for s in seen if s[0][:3] == ["xcrun", "simctl", "launch"]]
        self.assertEqual(launches[0][1], "reduceMotion")
        self.assertEqual(launches[0][0][-1], "--server-ui-preview")
        self.assertIn(("call", "press", 'label="Chores"'), [("call",) + c for c in agent.calls if c[0] == "press"])
        record.relaunch(dev, self.scenario, False, runner=runner, sleep=lambda s: None)
        self.assertEqual([s for s in seen if s[0][:3] == ["xcrun", "simctl", "launch"]][1][1], "none")


    def test_gallery_mode_stages_the_bootstrap_sets_the_page_and_passes_the_environment(self):
        seen = []
        with TemporaryDirectory() as tmp:
            data = Path(tmp) / "data"
            data.mkdir()
            boot = Path(tmp) / "bootstrap.json"
            boot.write_text(json.dumps({"variables": {"FENTON_GALLERY": "chores"}}))

            def runner(argv, env=None, timeout=0):
                seen.append((argv, env))
                if argv[:3] == ["xcrun", "simctl", "get_app_container"]:
                    return Result(0, str(data) + "\n")
                return Result(0, "")
            scenario = Scenario("m", "m", "motion", [Step("x", 100, "e")], native_mode="gallery", env={"FENTON_UK_EXTRAS": "1"})
            dev = record.Device("native", "U", FakeAgent(), gallery_bootstrap=boot)
            record.relaunch(dev, scenario, False, runner=runner, sleep=lambda s: None)
            stored = json.loads((data / record.pl_launch.FIXTURE_SUBPATH / "bootstrap.json").read_text())
        self.assertEqual(stored["variables"]["FENTON_GALLERY"], "motion")
        launch = [s for s in seen if s[0][:3] == ["xcrun", "simctl", "launch"]][0]
        self.assertEqual(launch[0][-1], "--gallery-fixture")
        self.assertEqual(launch[1]["SIMCTL_CHILD_FENTON_UK_EXTRAS"], "1")
        self.assertEqual(launch[1]["SIMCTL_CHILD_FENTON_SYSTEM_SETTINGS"], "none")


class CalibrationTests(unittest.TestCase):
    def test_the_calibration_scenarios_register_with_their_events(self):
        from tools.motion_pairs import calibration
        self.assertEqual([e.name for e in calibration.CHORES.events()], ["push", "pop", "sheet", "dismiss"])
        self.assertEqual(calibration.CONTROL.native_mode, "gallery")
        self.assertLess(calibration.CONTROL.events()[0].onset_threshold, 1.0)


class RegressionTests(unittest.TestCase):
    """One test per bug the first four device runs turned up; each fails on the code that had it."""

    def take(self, duration_ms, steps=2):
        agent = FakeAgent(duration_ms=duration_ms)
        scenario = Scenario("s", "s", "chores", [Step('label="A"', 100, "push") for _ in range(steps)], lead_ms=100)
        original = record.relaunch
        record.relaunch = lambda *a, **k: None
        try:
            with TemporaryDirectory() as tmp:
                return record.record_take(record.Device("native", "U", agent), scenario, Path(tmp) / "t.mp4", 1,
                                          sleep=lambda s: None, load=lambda: 5.0), scenario
        finally:
            record.relaunch = original

    def test_each_press_adds_its_round_trip_to_the_length_allowance(self):
        # sequence 300 ms; the old limit was 300 + 4000; four presses of 1.2 s each (a real run: 11.5 s for 7.2 s) must pass
        take, scenario = self.take(300 + 4000 + 2500, steps=2)
        self.assertTrue(take.ok, take.reason)
        self.assertEqual(record.PRESS_MS, 1500)
        runaway, _ = self.take(300 + 4000 + 1500 * 2 + 500, steps=2)
        self.assertFalse(runaway.ok)

    def test_a_publication_folder_without_its_files_is_reported(self):
        with TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            parent = tmp / "fullpair"
            (parent / "pub" / "assets").mkdir(parents=True)
            (parent / "pub" / "bootstrap.json").write_text("{}")
            (parent / "pub" / "publication.json").write_text("{}")
            self.assertEqual(len(record.validate_publication(parent)), 3)
            self.assertEqual(record.validate_publication(parent / "pub"), [])

    def test_dry_run_flags_a_bad_publication_path_and_resolves_selectors(self):
        from tools.motion_pairs import calibration
        with TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            plan = record.dry_run(calibration.CHORES, tmp / "nope", None, tmp / "out", {"reference": "R", "native": "N"},
                                  {"reference": "a", "native": "b"}, simulators="R N")
            self.assertTrue(any("bootstrap.json" in p for p in plan["problems"]))
            self.assertEqual(plan["steps"][0]["press"][0], 'label="Your Chores"')
            self.assertEqual(plan["overrunLimitMs"], calibration.CHORES.sequence_ms() + 4000 + 1500 * 4)
            missing = record.dry_run(calibration.CHORES, tmp / "nope", None, tmp / "out", {"reference": "R", "native": "X"},
                                     {}, simulators="R N")
            self.assertTrue(any("X is not in simctl list" in p for p in missing["problems"]))
            gallery = record.dry_run(calibration.CONTROL, None, None, tmp / "out", {"reference": "R", "native": "N"}, {}, simulators="R N")
            self.assertTrue(any("--gallery-bootstrap" in p for p in gallery["problems"]))

    def test_a_small_control_burst_below_the_settle_floor_is_still_an_event(self):
        series = [(float(t), 0.05 if 500 <= t < 900 else 0.0) for t in range(0, 2000, 12)]
        events = curves.segment_events(series, floor=0.002, onset_threshold=0.02, settle_floor=0.006)
        self.assertEqual(len(events), 1)
        # with the full-screen settle floor nothing in the burst passes it: the event must still come back, ending at its onset
        flat = curves.segment_events(series, floor=0.002, onset_threshold=0.02)
        self.assertEqual(len(flat), 1)
        self.assertGreaterEqual(flat[0].end_ms, flat[0].onset_ms)

    @unittest.skipIf(np is None, "numpy not installed")
    def test_a_swap_inside_one_frame_is_a_cut_with_no_negative_settle(self):
        pts = np.arange(0, 800, 12.0)
        fr = np.zeros((len(pts), 100, 100), dtype=np.uint8)
        fr[30:] = 0
        for i, t in enumerate(pts):
            if t >= 300:
                fr[i, 30:40, 10:90] = 120
        # a fade after the swap keeps the burst long enough to count as an event
        for i, t in enumerate(pts):
            if 300 <= t < 600:
                fr[i, 41:45, 10:90] = int(40 * (t - 300) / 300)
        cfg = progress.EventConfig("toggle", onset_threshold=0.02, min_frames=6, roi=(0.0, 0.25, 1.0, 0.45))
        event = progress.analyze_events(pts, fr, [cfg])[0]
        self.assertTrue(event["found"])
        self.assertGreaterEqual(event["settleMs"], 0.0)
        self.assertEqual(event["kind"], "cut")
        self.assertIsNone(event["fit"])

    def test_takes_whose_first_changed_frame_is_part_way_are_not_used_for_timing(self):
        f = curves.bezier(0, 0, 0.58, 1)
        mk = lambda settle, late: {"found": True, "settleMs": settle, "leadToOnsetMs": 40.0, "overshoot": 0.0, "kind": "slide-x", "slideRatio": 0.6,
                                   "lateOnset": late, "progress": [(float(t), f(t / settle)) for t in range(0, int(settle * 1.4), 10)]}
        out = pair.summarize_side([mk(350, False), mk(60, True), mk(345, False), mk(80, True), mk(120, True)])
        self.assertEqual((out["usable"], out["lateOnsetTakes"]), (2, 3))
        self.assertAlmostEqual(out["settleMs"], 347.5, delta=1)
        none = pair.summarize_side([mk(60, True), mk(80, True)])
        self.assertEqual(none["usable"], 0)
        verdict = pair.judge(none, pair.summarize_side([mk(350, False)]), pair.Tolerances())
        self.assertEqual(verdict["verdict"], "unmeasured")
        self.assertIn("onset caught late: 2", verdict["reason"])

    @unittest.skipIf(np is None, "numpy not installed")
    def test_progress_marks_an_onset_that_starts_part_way(self):
        pts = np.arange(0, 900, 12.0)
        fr = np.zeros((len(pts), 60, 60), dtype=np.uint8)
        for i, t in enumerate(pts):
            u = 0.0 if t < 300 else min((t - 300) / 300.0 + 0.5, 1.0)  # the first changed frame is already half way
            fr[i, :, :] = int(200 * u)
        late = progress.analyze_events(pts, fr, [progress.EventConfig("push", min_frames=5)])[0]
        self.assertTrue(late["lateOnset"], late.get("p0"))

    @unittest.skipIf(np is None, "numpy not installed")
    def test_frame_sequence_diff_with_no_window_returns_zeros(self):
        pts = np.arange(0, 200, 12.0)
        fr = np.zeros((len(pts), 10, 10), dtype=np.uint8)
        for window in (-5.0, -1000.0):
            self.assertEqual(progress.frame_sequence_diff(pts, fr, 50, pts, fr, 50, window), {"mean": 0.0, "worst": 0.0})

    @unittest.skipIf(np is None, "numpy not installed")
    def test_a_faint_control_inside_its_roi_is_measured_without_a_crash(self):
        pts = np.arange(0, 700, 12.0)
        fr = np.zeros((len(pts), 100, 100), dtype=np.uint8)
        for i, t in enumerate(pts):
            u = min(max((t - 150) / 300.0, 0.0), 1.0)
            fr[i, 30:34, 10:90] = int(6 * u)  # a 6/255 change over a thin band: under the full-screen floors
        cfg = progress.EventConfig("toggle", onset_threshold=0.02, min_frames=6, roi=(0.0, 0.25, 1.0, 0.45))
        event = progress.analyze_events(pts, fr, [cfg])[0]
        self.assertTrue(event["found"])
        self.assertGreater(event["settleMs"], 100)


@unittest.skipIf(np is None, "numpy not installed")
class FrameTests(unittest.TestCase):
    def frames(self, mode, n=40, h=60, w=40):
        """A page replaced by another: ``slide`` pushes the new page in from the right, ``fade`` cross-fades."""
        rng = np.random.RandomState(3)
        old = (rng.rand(h, w) * 80).astype(np.float32)
        new = (rng.rand(h, w) * 80 + 120).astype(np.float32)
        out, pts = [], []
        for i in range(n):
            t = i * 12.0
            u = min(max((t - 120) / 360.0, 0.0), 1.0)
            p = 1 - (1 - u) ** 3
            if mode == "slide":
                s = int(round(w * (1 - p)))
                f = old.copy()
                f[:, s:] = new[:, : w - s]
            else:
                f = old * (1 - p) + new * p
            out.append(f.astype(np.uint8))
            pts.append(t)
        return np.array(pts), np.array(out)

    def run_events(self, mode):
        pts, fr = self.frames(mode)
        return progress.analyze_events(pts, fr, [progress.EventConfig("push", min_frames=8)])[0]

    def test_a_slide_is_found_with_onset_progress_and_slide_kind(self):
        e = self.run_events("slide")
        self.assertTrue(e["found"])
        self.assertTrue(e["kind"].startswith("slide-x"), e["kind"])
        self.assertLess(e["slideRatio"], 1.0)
        self.assertGreaterEqual(e["onsetMs"], 120)
        self.assertLess(e["onsetMs"], 200)
        self.assertEqual(e["fit"]["family"] in ("ease-out", "spring", "bezier", "ease"), True)

    def test_a_cross_fade_is_not_a_slide(self):
        e = self.run_events("fade")
        self.assertTrue(e["found"])
        self.assertEqual(e["kind"], "fade")
        self.assertGreater(e["slideRatio"], 1.5)

    def test_progress_runs_from_zero_to_one(self):
        e = self.run_events("fade")
        values = [p for t, p in e["progress"]]
        self.assertAlmostEqual(values[0], 0.0, delta=0.05)
        self.assertAlmostEqual(values[-1], 1.0, delta=0.05)
        self.assertAlmostEqual(e["settleMs"], 360, delta=140)

    def test_a_still_clip_has_no_event(self):
        pts = np.arange(0, 400, 12.0)
        fr = np.zeros((len(pts), 30, 20), dtype=np.uint8)
        self.assertFalse(progress.analyze_events(pts, fr, [progress.EventConfig("push")])[0]["found"])

    def test_a_roi_finds_a_small_control_the_full_frame_would_miss(self):
        pts = np.arange(0, 600, 12.0)
        fr = np.zeros((len(pts), 100, 100), dtype=np.uint8)
        for i, t in enumerate(pts):
            u = min(max((t - 120) / 300.0, 0.0), 1.0)
            fr[i, 5:25, 5:25] = int(200 * u)
        whole = progress.analyze_events(pts, fr, [progress.EventConfig("toggle", onset_threshold=1.0)])[0]
        self.assertFalse(whole["found"])
        roi = progress.analyze_events(pts, fr, [progress.EventConfig("toggle", onset_threshold=1.0, roi=(0.0, 0.0, 0.3, 0.3))])[0]
        self.assertTrue(roi["found"])
        self.assertEqual(roi["kind"] in ("fade", "slide-x", "slide-y"), True)

    def test_frame_sequence_diff_is_zero_for_identical_clips_and_high_for_different(self):
        pts, fr = self.frames("slide")
        same = progress.frame_sequence_diff(pts, fr, 120, pts, fr, 120, 300)
        self.assertEqual(same["mean"], 0.0)
        other = progress.frame_sequence_diff(pts, fr, 120, pts, 255 - fr, 120, 300)
        self.assertGreater(other["mean"], 0.5)

    def test_motion_series_is_the_mean_change_against_the_previous_frame(self):
        pts = np.array([0.0, 10.0, 20.0])
        fr = np.array([np.zeros((4, 4)), np.full((4, 4), 10), np.full((4, 4), 10)], dtype=np.uint8)
        series = progress.motion_series(pts, fr)
        self.assertEqual(series, [(10.0, 10.0), (20.0, 0.0)])


if __name__ == "__main__":
    unittest.main()
