"""``uitest_support.exact_count``: the count handed to ``xc_watch --expect-tests`` (plan skips and both filter kinds applied)."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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


class IterationHoldTests(unittest.TestCase):
    """A stress run (`-test-iterations N`) repeats every test, so the hold grows with N up to the cap."""
    CLASSES = ["C%d" % i for i in range(6)]

    def hold(self, iterations, per_class=20):
        found = {name: ["t%d" % i for i in range(per_class)] for name in self.CLASSES}
        with mock.patch.object(u, "tests_by_class", return_value=found):
            return u.hosted_hold(self.CLASSES, Path("."), iterations)

    def test_iterations_are_read_from_the_run_arguments(self):
        self.assertEqual(u.iterations_in(["-only-testing:X", "-test-iterations", "6"]), 6)
        self.assertEqual(u.iterations_in(["-test-iterations=15"]), 15)
        self.assertEqual(u.iterations_in([]), 1)
        self.assertEqual(u.iterations_in(["-test-iterations", "x"]), 1)
        self.assertEqual(u.iterations_in(["-test-iterations"]), 1)

    def test_six_iterations_hold_longer_than_one_pass(self):
        single, six = self.hold(1), self.hold(6)
        self.assertGreater(six, single)
        self.assertGreater(six, 16 * 60)  # the 16 minute hold that killed the progressing 6-iteration run
        # the per-test part scales by 6; the fixed base is paid once
        self.assertEqual(six - u.HOSTED_BASE, (single - u.HOSTED_BASE) * 6)

    def test_the_hold_stays_under_the_cap(self):
        self.assertEqual(self.hold(1000), u.HOLD_CAP)
        self.assertEqual(u.hold_for(500, 50), u.HOLD_CAP)

    def test_hold_for_scales_per_test_seconds(self):
        self.assertEqual(u.hold_for(10, 3) - u.HOLD_BASE, (u.hold_for(10) - u.HOLD_BASE) * 3)

    def test_the_cli_reads_iterations_after_the_separator(self):
        env = {"FENTON_ROOT": str(Path(__file__).resolve().parents[2]), "PATH": "/usr/bin:/bin"}
        run = lambda *a: int(subprocess.run([sys.executable, str(SUPPORT), *a], env=env, capture_output=True, text=True).stdout)
        self.assertGreater(run("hosted-hold", "--", "-test-iterations", "2"), run("hosted-hold"))
        self.assertGreater(run("hold", "20", "-test-iterations", "6"), run("hold", "20"))


if __name__ == "__main__":
    unittest.main()
