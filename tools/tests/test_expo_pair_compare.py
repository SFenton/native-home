"""Tests for tools/expo_pair_compare.py: synthetic frames for the gate, recorded Expo evidence for the calibration."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import expo_pair_compare as epc  # noqa: E402
import png_raster  # noqa: E402

#: Where the recorded r8/r9 pairs live (override with ``EXPO_EVIDENCE_ROOT``); the tests needing them skip when absent.
EVIDENCE = Path(os.environ.get(
    "EXPO_EVIDENCE_ROOT", str(Path(__file__).resolve().parents[3] / "t3-b48b8cc0" / "build" / "evidence" / "t3-b48b8cc0")))

W, H = 300, 600  # density 1 frames keep the arithmetic readable; 1% = 1800 px, 0.25% = 450 px


def solid(path: Path, width: int, height: int, colour: tuple, paint: tuple = ()) -> Path:
    """Write a ``width`` x ``height`` PNG of one colour, with ``(box, colour)`` rectangles painted over it."""
    rows = [bytearray(bytes(colour) * width) for _ in range(height)]
    for (x0, y0, x1, y1), shade in paint:
        for y in range(y0, y1):
            rows[y][x0 * 3:x1 * 3] = bytes(shade) * (x1 - x0)
    png_raster.write(png_raster.Raster(width, height, b"".join(bytes(r) for r in rows)), path)
    return path


def args(**over: object) -> argparse.Namespace:
    base = dict(tolerance=8, max_diff_percent=1.0, max_block_percent=0.25, status_bar_pt=54.0, home_indicator_pt=34.0)
    base.update(over)
    return argparse.Namespace(**base)


class GateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def frame(self, name: str, *paint: tuple) -> Path:
        return solid(self.dir / name, W, H, (20, 20, 20), paint)

    def run_pair(self, cand_paint: tuple = (), **over: object) -> dict:
        ref = self.frame("ref.png")
        cand = self.frame("cand.png", *cand_paint)
        spec = {"id": "p", "capture": "c", "state": "s", "reference_png": ref, "candidate_png": cand, "reference_ax": None,
                "candidate_ax": None, "density": 1.0, "live_regions": over.pop("live_regions", []), "problems": []}
        return epc.judge(spec, self.dir, args(**over))

    def test_identical_frames_pass_and_write_outputs(self) -> None:
        record = self.run_pair()
        self.assertEqual(record["verdict"], "pass")
        self.assertTrue((self.dir / "p.json").is_file())
        self.assertTrue((self.dir / "p-diff.png").is_file())

    def test_change_within_tolerance_is_not_a_difference(self) -> None:
        record = self.run_pair((((0, 100, W, 300), (28, 28, 28)),))  # +8 exactly
        self.assertEqual(record["changedPixels"], 0)
        self.assertEqual(record["verdict"], "pass")

    def test_change_over_tolerance_counts(self) -> None:
        record = self.run_pair((((0, 100, 10, 110), (29, 20, 20)),))  # +9 on one channel
        self.assertEqual(record["changedPixels"], 100)
        self.assertEqual(record["verdict"], "pass")

    def test_global_limit_fails_scattered_changes(self) -> None:
        # 10x10 squares on a 20 px grid: well over 1% in total, each block only 100 px.
        record = self.run_pair(tuple(((x, y, x + 10, y + 10), (200, 20, 20))
                                     for y in range(100, 400, 20) for x in range(0, 290, 20)))
        self.assertGreater(record["changedPercent"], 1.0)
        self.assertLess(record["largestBlockPercent"], 0.25)
        self.assertEqual(record["verdict"], "fail")
        self.assertIn("of pixels differ", record["failures"][0])

    def test_one_contiguous_block_fails_even_under_global_limit(self) -> None:
        record = self.run_pair((((0, 100, 30, 120), (200, 20, 20)),))  # 600 px = 0.33%, one block
        self.assertLess(record["changedPercent"], 1.0)
        self.assertEqual(record["verdict"], "fail")
        self.assertIn("block", record["failures"][0])

    def test_diagonal_touch_is_one_block(self) -> None:
        record = self.run_pair((((100, 100, 110, 110), (200, 20, 20)), ((110, 110, 120, 120), (200, 20, 20))))
        self.assertEqual(record["largestBlockPixels"], 200)

    def test_status_bar_and_home_indicator_are_masked(self) -> None:
        record = self.run_pair((((0, 0, W, 40), (255, 255, 255)), ((0, H - 20, W, H), (255, 255, 255))))
        self.assertEqual(record["changedPixels"], 0)

    def test_declared_live_region_is_masked(self) -> None:
        paint = (((100, 200, 160, 260), (255, 0, 0)),)
        self.assertEqual(self.run_pair(paint)["verdict"], "fail")
        live = [{"label": "clock", "x": 90, "y": 190, "width": 80, "height": 80}]
        self.assertEqual(self.run_pair(paint, live_regions=live)["changedPixels"], 0)

    def test_size_mismatch_fails(self) -> None:
        ref = self.frame("ref.png")
        other = self.dir / "other.png"
        solid(other, W, H + 1, (0, 0, 0))
        result = epc.compare_images(ref, other, self.dir / "d.png", density=1.0, status_bar_pt=0, live_regions=[])
        self.assertTrue(result["failures"])

    def test_missing_screenshot_fails(self) -> None:
        spec = {"id": "m", "capture": "c", "state": "", "reference_png": None, "candidate_png": None, "reference_ax": None,
                "candidate_ax": None, "density": 1.0, "live_regions": [], "problems": []}
        self.assertEqual(epc.judge(spec, self.dir, args())["verdict"], "fail")

    def test_ax_equal_differs_and_skipped(self) -> None:
        self.assertEqual(epc.compare_ax(["a"], ["a"]), (True, []))
        self.assertIs(epc.compare_ax(None, ["a"])[0], None)
        equal, failures = epc.compare_ax(["a"], ["b"])
        self.assertFalse(equal)
        self.assertTrue(failures)

    def test_manifest_and_cli_exit_codes(self) -> None:
        self.frame("ref.png")
        self.frame("good.png")
        self.frame("bad.png", ((0, 100, 60, 200), (255, 0, 0)))
        entries = [{"id": "good", "reference_png": "ref.png", "candidate_png": "good.png", "density": 1, "status_bar_pt": 0},
                   {"id": "bad", "reference_png": "ref.png", "candidate_png": "bad.png", "density": 1, "status_bar_pt": 0}]
        manifest = self.dir / "m.json"
        out, md = self.dir / "out", self.dir / "out.md"
        manifest.write_text(json.dumps({"pairs": entries[:1]}))
        self.assertEqual(epc.main(["--manifest", str(manifest), "--out", str(out), "--markdown", str(md)]), 0)
        manifest.write_text(json.dumps({"pairs": entries}))
        self.assertEqual(epc.main(["--manifest", str(manifest), "--out", str(out), "--markdown", str(md)]), 1)
        self.assertIn("1 of 2 pairs pass", md.read_text())
        self.assertEqual(epc.main(["--manifest", str(self.dir / "none.json"), "--out", str(out)]), 2)


@unittest.skipUnless((EVIDENCE / "bedroom-waking-regression-r9" / "reference" / "case.json").is_file(), "recorded evidence absent")
class RecordedEvidenceTests(unittest.TestCase):
    """Calibration: the r9 residuals pass and the r8 capture that differed by 53.7% fails."""

    def specs(self, run: str) -> list:
        return epc.pairs_from_folders(EVIDENCE / run / "reference", EVIDENCE / run / "candidate", run)

    def judge_all(self, run: str) -> list:
        with tempfile.TemporaryDirectory() as out:
            return [epc.judge(spec, Path(out), args()) for spec in self.specs(run)]

    def test_r9_pairs_pass(self) -> None:
        for run in ("bedroom-waking-regression-r9", "bedroom-wake-editor-scroll-r9", "bedroom-wake-editor-save-r9"):
            records = self.judge_all(run)
            self.assertTrue(records)
            for record in records:
                self.assertEqual(record["verdict"], "pass", (run, record["id"], record["failures"]))

    def test_r8_53_percent_pair_fails(self) -> None:
        records = {r["state"]: r for r in self.judge_all("bedroom-wake-editor-flow-r8")}
        self.assertEqual(records["new-exit"]["verdict"], "fail")
        self.assertGreater(records["new-exit"]["changedPercent"], 30)
        for state in ("weekly-editor", "existing-actions", "new-editor", "new-actions"):
            self.assertEqual(records[state]["verdict"], "pass", state)


if __name__ == "__main__":
    unittest.main()
