"""``uitest_support.exact_count``: the count handed to ``xc_watch --expect-tests`` (plan skips and both filter kinds applied)."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import uitest_support as u  # noqa: E402

SUPPORT = Path(__file__).resolve().parents[1] / "uitest_support.py"
SOURCE = """
final class AlphaJourneyTests: XCTestCase {
    func testOne() {}
    func testTwo() {}
    func testThree() {}
}
final class BetaJourneyTests: XCTestCase {
    func testA() {}
    func testB() {}
}
"""


class ExactCountTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        folder = self.root / u.TEST_DIR
        folder.mkdir(parents=True)
        (folder / "Journeys.swift").write_text(SOURCE)

    def plan(self, **ui):
        path = self.root / "Plan.xctestplan"
        targets = [{"target": {"name": u.UNIT_TARGET}}, {"target": {"name": u.TARGET}, **ui}]
        path.write_text(json.dumps({"testTargets": targets}))
        return path

    def only(self, *names):
        return ["-only-testing:%s/%s" % (u.TARGET, n) for n in names]

    def test_a_filtered_class_loses_the_methods_the_plan_skips(self):
        plan = self.plan(skippedTests=["AlphaJourneyTests/testTwo()"])
        self.assertEqual(u.exact_count(self.only("AlphaJourneyTests"), plan, self.root), 2)
        self.assertEqual(u.count(self.only("AlphaJourneyTests"), plan, self.root), 3)  # the hold estimate keeps the source count

    def test_a_selected_tests_plan_limits_the_filter(self):
        plan = self.plan(selectedTests=["AlphaJourneyTests/testOne()", "BetaJourneyTests"])
        self.assertEqual(u.exact_count(self.only("AlphaJourneyTests", "BetaJourneyTests"), plan, self.root), 3)
        self.assertEqual(u.exact_count([], plan, self.root), 3)

    def test_skip_testing_removes_a_method_or_a_class(self):
        plan = self.plan()
        skip_method = ["-skip-testing:%s/AlphaJourneyTests/testOne" % u.TARGET]
        skip_class = ["-skip-testing:%s/BetaJourneyTests" % u.TARGET]
        self.assertEqual(u.exact_count(self.only("AlphaJourneyTests") + skip_method, plan, self.root), 2)
        self.assertEqual(u.exact_count(skip_class, plan, self.root), 3)
        self.assertEqual(u.exact_count([], plan, self.root), 5)

    def test_a_single_method_filter_counts_one(self):
        self.assertEqual(u.exact_count(self.only("BetaJourneyTests/testA"), self.plan(), self.root), 1)

    def test_no_exact_count_without_a_readable_plan(self):
        self.assertIsNone(u.exact_count([], None, self.root))
        self.assertIsNone(u.exact_count([], self.root / "missing.xctestplan", self.root))
        broken = self.root / "Broken.xctestplan"
        broken.write_text("{")
        self.assertIsNone(u.exact_count([], broken, self.root))

    def test_no_exact_count_for_a_selector_the_sources_cannot_expand(self):
        plan = self.plan()
        self.assertIsNone(u.exact_count(self.only("GhostJourneyTests"), plan, self.root))
        self.assertIsNone(u.exact_count(self.only("AlphaJourneyTests/testMissing"), plan, self.root))
        self.assertIsNone(u.exact_count(["-only-testing:%s/SomeUnitTests" % u.UNIT_TARGET], plan, self.root))

    def test_the_cli_prints_nothing_when_the_count_is_not_exact(self):
        env = {"FENTON_ROOT": str(self.root), "PATH": "/usr/bin:/bin"}
        run = lambda *a: subprocess.run([sys.executable, str(SUPPORT), "exact", *a], env=env, capture_output=True, text=True).stdout.strip()
        self.assertEqual(run("--plan", str(self.plan(skippedTests=["BetaJourneyTests"]))), "3")
        self.assertEqual(run(), "")


if __name__ == "__main__":
    unittest.main()
