"""Tests for the parity-loop extensions of tools/expo_pair_compare.py: drift, required AX, mask files, status-bar equality."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import expo_pair_compare as epc  # noqa: E402
from parity_loop_fakes import solid  # noqa: E402

BIG = ((10, 100, 110, 190), (200, 40, 40))  # 100 x 90 = 9000 px of 24000 (37%): over every limit


def args(**over: object) -> argparse.Namespace:
    base = dict(tolerance=8, max_diff_percent=1.0, max_block_percent=0.25, status_bar_pt=54.0, home_indicator_pt=34.0,
                require_sidecar=False, drift=True, require_ax=False, status_bar_equal=False, status_bar_max_percent=0.5)
    base.update(over)
    return argparse.Namespace(**base)


def ax_file(path: Path, rows: list) -> Path:
    path.write_text(json.dumps({"normalized": rows}))
    return path


class CompareTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def spec(self, ref=(), cand=(), ref2=(), **extra: object) -> dict:
        spec = {"id": "p", "capture": "p", "state": "", "reference_png": solid(self.dir / "r.png", paint=ref),
                "candidate_png": solid(self.dir / "c.png", paint=cand), "reference2_png": solid(self.dir / "r2.png", paint=ref2),
                "reference_ax": None, "candidate_ax": None, "density": 1.0, "live_regions": [], "problems": [],
                "sidecars": {}, "ax_files": {}, "mask_files": []}
        spec.update(extra)
        return spec

    def test_identical_triple_passes_and_is_unclassified(self) -> None:
        record = epc.judge(self.spec(), self.dir, args())
        self.assertEqual(record["verdict"], "pass")
        self.assertEqual(record["class"], "unclassified")
        self.assertEqual(record["drift"]["changedPercent"], 0.0)

    def test_reference_drift_fails_the_pair_as_drift(self) -> None:
        record = epc.judge(self.spec(ref2=(BIG,)), self.dir, args())
        self.assertEqual(record["verdict"], "drift")
        self.assertGreater(record["drift"]["changedPercent"], 1.0)
        self.assertTrue(record["maskProposals"])
        self.assertTrue(any(f.startswith("drift:") for f in record["failures"]))

    def test_candidate_must_also_match_the_second_reference_shot(self) -> None:
        record = epc.judge(self.spec(ref=(BIG,), cand=(BIG,)), self.dir, args())
        self.assertIn("against the second reference shot", " ".join(record["failures"]))
        self.assertEqual(record["verdict"], "drift")  # the two reference shots differ too

    def test_drift_without_a_second_shot_is_refused(self) -> None:
        record = epc.judge(self.spec(reference2_png=None), self.dir, args())
        self.assertEqual(record["verdict"], "refused")

    def test_drift_off_ignores_the_second_shot(self) -> None:
        record = epc.judge(self.spec(ref2=(BIG,)), self.dir, args(drift=False))
        self.assertEqual(record["verdict"], "pass")
        self.assertNotIn("drift", record)

    def test_require_ax_fails_without_a_recorded_tree(self) -> None:
        record = epc.judge(self.spec(), self.dir, args(require_ax=True))
        self.assertEqual(record["verdict"], "fail")
        self.assertIn("AX tree not recorded", record["failures"][0])
        self.assertIs(record["allAXNodesEqual"], False)

    def test_require_ax_compares_the_normalised_sequences(self) -> None:
        row = {"role": "Button", "label": "A", "value": "", "enabled": True, "selected": False}
        other = dict(row, label="B")
        files = {"reference": ax_file(self.dir / "a.json", [row, other]), "candidate": ax_file(self.dir / "b.json", [row, other]),
                 "reference2": ax_file(self.dir / "c.json", [row, other])}
        self.assertEqual(epc.judge(self.spec(ax_files=files), self.dir, args(require_ax=True))["verdict"], "pass")
        files["candidate"] = ax_file(self.dir / "b.json", [other, row])  # same rows, other order
        record = epc.judge(self.spec(ax_files=files), self.dir, args(require_ax=True))
        self.assertEqual((record["verdict"], record["allAXNodesEqual"]), ("fail", False))
        self.assertEqual(record["axDiff"]["firstDifference"], 0)
        files["candidate"] = files["reference"]
        files["reference2"] = ax_file(self.dir / "c.json", [row])
        self.assertEqual(epc.judge(self.spec(ax_files=files), self.dir, args(require_ax=True))["verdict"], "drift")

    def test_mask_files_hide_a_live_region(self) -> None:
        unmasked = epc.judge(self.spec(cand=(BIG,), ref2=(BIG,)), self.dir, args(drift=False))
        self.assertEqual(unmasked["verdict"], "fail")
        mask = self.dir / "mask.json"
        mask.write_text(json.dumps([{"label": "live", "x": 0, "y": 90, "width": 120, "height": 100, "unit": "px"}]))
        masked = epc.judge(self.spec(cand=(BIG,), mask_files=[mask]), self.dir, args(drift=False, max_mask_percent=100))
        self.assertEqual(masked["verdict"], "pass")
        mask.write_text(json.dumps({"regions": []}))
        self.assertEqual(epc.load_regions([mask]), [])

    def test_status_bar_difference_beats_the_mask(self) -> None:
        bar = ((0, 0, 120, 20), (255, 255, 255))
        rects = {"clock": [0, 0, 120, 20]}
        record = epc.judge(self.spec(cand=(bar,), ref2=()), self.dir, args(status_bar_equal=True, status_bar_rects=rects))
        self.assertEqual(record["verdict"], "statusbar")
        self.assertGreater(record["statusBarDifferencePercent"], 0.5)
        same = epc.judge(self.spec(), self.dir, args(status_bar_equal=True, status_bar_rects=rects))
        self.assertEqual(same["verdict"], "pass")

    def test_status_bar_check_compares_only_the_items_not_the_band(self) -> None:
        size = (466, 300)  # a Duo-wide frame at density 1, so the profile rectangles fit

        def pair(cand_paint: tuple) -> dict:
            return self.spec(reference_png=solid(self.dir / "wr.png", size=size), candidate_png=solid(self.dir / "wc.png", paint=cand_paint, size=size),
                             reference2_png=solid(self.dir / "wr2.png", size=size))
        centre = ((150, 0, 300, 54), (255, 255, 255))  # page background between the clock and the indicators
        clock = ((400, 85, 430, 100), (255, 255, 255))  # the folded Duo's status items sit in the right-hand rail
        ok = epc.judge(pair((centre,)), self.dir, args(status_bar_equal=True))
        self.assertEqual((ok["verdict"], ok["statusBarDifferencePercent"]), ("pass", 0.0))
        bad = epc.judge(pair((clock,)), self.dir, args(status_bar_equal=True))
        self.assertEqual(bad["verdict"], "statusbar")
        self.assertEqual([n for n, _ in epc.status_bar_rects("duo", size, 1.0)], ["clock"])  # the ring is masked, not compared
        self.assertEqual(epc.status_bar_rects("duo", size, 2.0)[0][1][0], 322)  # (466 px / 2 - 72 pt) * 2
        self.assertEqual([n for n, _ in epc.status_bar_rects("iphone", size, 1.0)], ["clock", "indicators"])
        override = {"only": [0, 0, 10, 10]}
        self.assertEqual(epc.status_bar_rects("duo", size, 1.0, override), [("only", (0, 0, 10, 10))])

    def test_drift_uses_the_tighter_noise_floor_by_default(self) -> None:
        small = ((10, 100, 20, 105), (200, 40, 40))  # 50 px of 24000: 0.21%, under the 1.0% gate, over the 0.15% noise floor
        record = epc.judge(self.spec(ref2=(small,)), self.dir, args())
        self.assertEqual(record["verdict"], "drift")
        self.assertAlmostEqual(record["drift"]["changedPercent"], 0.2083, places=3)
        self.assertEqual(epc.judge(self.spec(ref2=(small,)), self.dir, args(drift_max_percent=1.0))["verdict"], "pass")
        self.assertEqual(epc.DRIFT_MAX_PERCENT, 0.15)

    def test_a_missing_second_reference_ax_tree_fails_instead_of_skipping(self) -> None:
        row = {"role": "Button", "label": "A", "value": "", "enabled": True, "selected": False}
        files = {"reference": ax_file(self.dir / "a.json", [row]), "candidate": ax_file(self.dir / "b.json", [row])}
        record = epc.judge(self.spec(ax_files=files), self.dir, args(require_ax=True))
        self.assertEqual(record["verdict"], "fail")
        self.assertIn("AX tree not recorded on reference2", record["failures"])
        files["reference2"] = self.dir / "does-not-exist.json"
        self.assertEqual(epc.judge(self.spec(ax_files=files), self.dir, args(require_ax=True))["verdict"], "fail")

    def test_masks_covering_too_much_of_the_image_refuse_the_pair(self) -> None:
        wide = self.dir / "wide.json"
        wide.write_text(json.dumps([{"label": "everything", "x": 0, "y": 60, "width": 120, "height": 100, "unit": "px"}]))  # 50%
        record = epc.judge(self.spec(mask_files=[wide]), self.dir, args())
        self.assertEqual(record["verdict"], "refused")
        self.assertIn("masks cover 50.0% of the image", record["failures"][0])
        self.assertEqual(record["maskedPercent"], 50.0)
        self.assertNotIn("changedPixels", record)

    def test_masked_percent_is_the_union_and_is_recorded_under_the_cap(self) -> None:
        overlapping = [{"x": 0, "y": 100, "width": 60, "height": 20, "unit": "px"}, {"x": 30, "y": 100, "width": 60, "height": 20, "unit": "px"}]
        self.assertEqual(epc.masked_percent((120, 200), 1.0, overlapping), 100.0 * 90 * 20 / 24000)
        small = self.dir / "small.json"
        small.write_text(json.dumps(overlapping))
        record = epc.judge(self.spec(mask_files=[small]), self.dir, args())
        self.assertEqual((record["verdict"], record["maskedPercent"]), ("pass", 7.5))
        self.assertEqual(epc.MAX_MASK_PERCENT, 15.0)

    def test_skipped_entry_and_exit_codes(self) -> None:
        manifest = {"pairs": [{"id": "s", "reference_png": "", "candidate_png": "", "skipped": "writes_on_reach and no deep link"}]}
        (self.dir / "m.json").write_text(json.dumps(manifest))
        out = self.dir / "out"
        self.assertEqual(epc.main(["--manifest", str(self.dir / "m.json"), "--out", str(out), "--markdown", str(self.dir / "t.md")]), 0)
        rows = json.loads((out / "results.json").read_text())
        self.assertEqual((rows[0]["verdict"], rows[0]["class"]), ("skipped", "unclassified"))
        self.assertIn("writes_on_reach", (self.dir / "t.md").read_text())

    def test_drift_verdict_exits_1(self) -> None:
        for name, paint in (("r.png", ()), ("c.png", ()), ("r2.png", (BIG,))):
            solid(self.dir / name, paint=paint)
        manifest = {"pairs": [{"id": "d", "reference_png": "r.png", "candidate_png": "c.png", "reference2_png": "r2.png", "density": 1}]}
        (self.dir / "m.json").write_text(json.dumps(manifest))
        self.assertEqual(epc.main(["--manifest", str(self.dir / "m.json"), "--out", str(self.dir / "o"), "--drift"]), 1)


if __name__ == "__main__":
    unittest.main()
