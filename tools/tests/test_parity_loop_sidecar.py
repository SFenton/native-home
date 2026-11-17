"""Tests for tools/parity_loop/sidecar.py and the sidecar refusal in tools/expo_pair_compare.py."""

from __future__ import annotations

import argparse
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import expo_pair_compare as epc  # noqa: E402
from parity_loop import sidecar  # noqa: E402
from parity_loop_fakes import FakeWorld, solid  # noqa: E402


def args(**over: object) -> argparse.Namespace:
    base = dict(tolerance=8, max_diff_percent=1.0, max_block_percent=0.25, status_bar_pt=54.0, home_indicator_pt=34.0,
                require_sidecar=True, drift=False, require_ax=False)
    base.update(over)
    return argparse.Namespace(**base)


class SidecarTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.world = FakeWorld(self.dir / "world")

    def collect(self, side: str, **kw: object) -> dict:
        png = solid(self.dir / f"{side}.png")
        return sidecar.collect(self.world.udid[side], side, png=png, scale=1, appearance="dark", runner=self.world, **kw)

    def test_collect_records_the_device_and_the_app(self) -> None:
        car = self.collect("reference", launch_args=["--gallery-fixture"], env_names=["B", "A"])
        self.assertEqual((car["model"], car["runtime"], car["runtimeBuild"]), ("iPhone-Duo", "iOS-27-1", "24A94401"))
        self.assertEqual((car["widthPx"], car["heightPx"], car["scale"], car["appearance"]), (120, 200, 1, "dark"))
        self.assertEqual((car["appVersion"], car["appBuild"]), ("1.0", "7"))
        self.assertEqual(len(car["bundleHash"]), 64)
        self.assertEqual(car["launchEnvNames"], ["A", "B"])
        self.assertIn("statusBarOverride", car)

    def test_bundle_identity_follows_file_content_and_names(self) -> None:
        app = self.dir / "a.app"
        app.mkdir()
        (app / "f").write_text("1")
        first = sidecar.bundle_identity(app)
        (app / "f").write_text("2")
        self.assertNotEqual(first, sidecar.bundle_identity(app))
        with self.assertRaises(ValueError):
            sidecar.bundle_identity(self.dir / "missing.app")

    def test_matching_halves_agree(self) -> None:
        self.assertEqual(sidecar.compare(self.collect("reference"), self.collect("candidate")), [])

    def test_every_must_match_field_refuses(self) -> None:
        ref, cand = self.collect("reference"), self.collect("candidate")
        for field in sidecar.MUST_MATCH:
            changed = copy.deepcopy(cand)
            changed[field] = "other"
            problems = sidecar.compare(ref, changed)
            self.assertTrue(any(field in p for p in problems), field)

    def test_missing_sidecar_unrecorded_field_and_same_app_refuse(self) -> None:
        ref, cand = self.collect("reference"), self.collect("candidate")
        self.assertEqual(sidecar.compare(None, cand), ["sidecar missing"])
        blank = dict(cand, widthPx=None)
        ref_blank = dict(ref, widthPx=None)
        self.assertTrue(any("widthPx is not recorded" in p for p in sidecar.compare(ref_blank, blank)))
        self.assertTrue(any("same app" in p for p in sidecar.compare(ref, dict(cand, bundleHash=ref["bundleHash"]))))
        self.assertTrue(any("must" not in p and "pin" in p for p in sidecar.compare(ref, cand, pins={"reference": "0" * 64})))
        self.assertEqual(sidecar.compare(ref, dict(ref), same_app=True), [])

    def test_judge_refuses_a_pair_whose_sidecars_differ(self) -> None:
        ref, cand = self.collect("reference"), self.collect("candidate")
        cand["appearance"] = "light"
        paths = {}
        for name, value in (("reference", ref), ("candidate", cand)):
            paths[name] = self.dir / f"{name}.sidecar.json"
            paths[name].write_text(json.dumps(value))
        spec = {"id": "p", "capture": "p", "state": "", "reference_png": self.dir / "reference.png", "candidate_png": self.dir / "candidate.png",
                "reference_ax": None, "candidate_ax": None, "density": 1.0, "live_regions": [], "problems": [],
                "sidecars": {**paths, "reference2": None}, "ax_files": {}}
        record = epc.judge(spec, self.dir, args())
        self.assertEqual(record["verdict"], "refused")
        self.assertTrue(any("appearance" in f for f in record["failures"]))
        self.assertNotIn("changedPixels", record)

    def test_main_exits_2_for_a_refused_pair(self) -> None:
        for side in ("reference", "candidate"):
            solid(self.dir / f"{side}.png")
        manifest = {"pairs": [{"id": "p", "reference_png": "reference.png", "candidate_png": "candidate.png", "density": 1}]}
        (self.dir / "m.json").write_text(json.dumps(manifest))
        code = epc.main(["--manifest", str(self.dir / "m.json"), "--out", str(self.dir / "out"), "--require-sidecar"])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
