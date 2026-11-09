"""``tools/test_plans.py``: classification of the UI journeys into Gate, Capture, Perf and Live, and the plan files."""

import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_plans as t  # noqa: E402

SOURCE = '''
final class SampleJourneyTests: JourneyTestCase {
    func openHome() throws -> XCUIApplication { try FentonHomeApp.launchSignedIn() }
    func testFixture() { let app = FentonHomeApp.launchGallery("chores"); _ = "launchSignedIn( in a string {" }
    func testSignedIn() throws { let app = try FentonHomeApp.launchSignedIn() }
    func testViaHelper() throws { let app = try openHome() }
    func testCaptureScreens() { /* launchSignedIn( */ }
    func testSprinklersAuditsAndScreenshots() {}
    func testLiveThing() {}
}
final class SamplePerformanceTests: JourneyTestCase { func testScroll() {} }
final class CameraJourneyTests: JourneyTestCase { func testViewer() {} }
final class TempScrollWedgeTests: JourneyTestCase { func testWedge() {} }
final class MotionJourneyTests: JourneyTestCase {
    func testGalleryListsEveryComponent() {}
    func testTabSwitchIsACut() {}
}
'''


class ClassifyTests(unittest.TestCase):
    def setUp(self):
        self.classes = t.scan_file(SOURCE)

    def plan_of(self, cls, method):
        return t.classify(cls, method, self.classes[cls][method])

    def test_rules(self):
        expect = {("SampleJourneyTests", "testFixture"): "Gate", ("SampleJourneyTests", "testSignedIn"): "Live",
                  ("SampleJourneyTests", "testViaHelper"): "Live", ("SampleJourneyTests", "testCaptureScreens"): "Capture",
                  ("SampleJourneyTests", "testSprinklersAuditsAndScreenshots"): "Capture",
                  ("SampleJourneyTests", "testLiveThing"): "Live", ("SamplePerformanceTests", "testScroll"): "Perf",
                  ("CameraJourneyTests", "testViewer"): "Live", ("TempScrollWedgeTests", "testWedge"): None,
                  ("MotionJourneyTests", "testGalleryListsEveryComponent"): "Capture",
                  ("MotionJourneyTests", "testTabSwitchIsACut"): "Gate"}
        for (cls, method), plan in expect.items():
            with self.subTest(test=f"{cls}/{method}"):
                self.assertEqual(self.plan_of(cls, method), plan)

    def test_every_test_is_in_exactly_one_plan(self):
        parts = t.partition(self.classes)
        seen = [(c, m) for plan in parts.values() for c, ms in plan.items() for m in ms]
        self.assertEqual(len(seen), len(set(seen)))
        total = sum(len(v) for v in self.classes.values()) - 1  # the excluded wedge probe
        self.assertEqual(len(seen), total)

    def test_gate_skips_what_other_plans_run_and_whole_classes_by_name(self):
        entries = t.identifiers(t.partition(self.classes)["Gate"], self.classes, invert=True)
        self.assertIn("SamplePerformanceTests", entries)
        self.assertIn("TempScrollWedgeTests", entries)
        self.assertIn("SampleJourneyTests/testSignedIn()", entries)
        self.assertNotIn("SampleJourneyTests/testFixture()", entries)


class RealPlansTests(unittest.TestCase):
    def test_the_real_journeys_partition_and_smoke_exists(self):
        classes = t.scan()
        docs = t.build(classes)
        self.assertEqual(sorted(docs), sorted(t.PLAN_NAMES))
        counts = t.counts(classes)
        self.assertEqual(counts["Gate"] + counts["Capture"] + counts["Perf"] + counts["Live"], sum(len(v) for v in classes.values()))
        self.assertGreater(counts["Gate"], counts["Live"])

    def test_gate_is_coverage_off_with_timeouts(self):
        options = t.build(t.scan())["Gate"]["defaultOptions"]
        self.assertFalse(options["codeCoverage"])
        self.assertTrue(options["testTimeoutsEnabled"])
        self.assertEqual(options["defaultTestExecutionTimeAllowance"], 300)

    def test_a_missing_smoke_test_is_an_error(self):
        with self.assertRaises(ValueError):
            t.build({"OnlyJourneyTests": {"testX": False}})

    def test_committed_plans_are_current(self):
        self.assertEqual(t.main(["--check"]), 0)

    def test_check_flags_a_stale_plan(self):
        with TemporaryDirectory() as tmp:
            self.assertEqual(t.main(["--check", "--dir", tmp]), 1)
            self.assertEqual(t.main(["--dir", tmp]), 0)
            self.assertEqual(t.main(["--check", "--dir", tmp]), 0)
            (Path(tmp) / "Gate.xctestplan").write_text(json.dumps({"version": 1}))
            self.assertEqual(t.main(["--check", "--dir", tmp]), 1)


if __name__ == "__main__":
    unittest.main()
