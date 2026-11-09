"""``tools/test_suites.py``: selectors, globs, nesting, exclude, cycles, ``--within`` and the committed manifest."""

import subprocess
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import test_suites  # noqa: E402

CLASSES = {
    "SetupJourneyTests": {"testStepOne": False, "testStepTwo": False, "testOther": False},
    "ChoresPageJourneyTests": {"testPageAudit": False, "testListPassesAudit": False},
    "ChoresWideLayoutJourneyTests": {"testSplitPassesAudit": False},
    "ChoresLiveJourneyTests": {"testLiveAudit": True},
    "FoodHubJourneyTests": {"testHubAtAX5": False},
}
MAP = {"layoutJourneys": ["ChoresWideLayoutJourneyTests"]}


def resolver(suites):
    return test_suites.Resolver(suites, CLASSES, MAP)


class SelectorTests(unittest.TestCase):
    def test_class_glob_and_method_glob(self):
        r = resolver({})
        self.assertEqual(len(r.selector("Chores*JourneyTests")), 4)
        self.assertEqual(r.selector("Setup*JourneyTests/testStep*"), {"SetupJourneyTests/testStepOne", "SetupJourneyTests/testStepTwo"})
        self.assertEqual(len(r.selector("*/test*Audit*")), 4)
        self.assertEqual(r.selector("FoodHubJourneyTests/testHubAtAX5()"), {"FoodHubJourneyTests/testHubAtAX5"})

    def test_plan_and_map_selectors(self):
        r = resolver({})
        self.assertIn("ChoresLiveJourneyTests/testLiveAudit", r.selector("plan:Live"))
        self.assertEqual(r.selector("map:layoutJourneys"), {"ChoresWideLayoutJourneyTests/testSplitPassesAudit"})

    def test_nesting_and_exclude(self):
        r = resolver({"chores": {"include": ["Chores*"]},
                      "audits": {"include": ["*/test*Audit*"]},
                      "pure": {"include": ["suite:audits"], "exclude": ["ChoresLive*", "Chores*Wide*"]}})
        self.assertEqual(r.suite("pure", []), {"ChoresPageJourneyTests/testPageAudit", "ChoresPageJourneyTests/testListPassesAudit"})

    def test_union_of_suites_and_selectors(self):
        r = resolver({"a": {"include": ["FoodHub*"]}})
        self.assertEqual(len(r.resolve(["a"], ["SetupJourneyTests/testOther"])), 2)

    def test_cycle_and_unknown(self):
        r = resolver({"a": {"include": ["suite:b"]}, "b": {"include": ["suite:a"]}, "c": {"include": ["suite:zzz"]}, "d": {"include": ["plan:Nope"]}})
        for name in ("a", "c", "d"):
            with self.assertRaises(test_suites.SuiteError):
                r.suite(name, [])
        self.assertTrue(any("cycle" in p for p in test_suites.check(r)))

    def test_check_flags_selectors_matching_nothing(self):
        problems = test_suites.check(resolver({"x": {"include": ["Food*", "Missing*"]}}))
        self.assertEqual(len(problems), 1)
        self.assertIn("Missing*", problems[0])


class ArgsTests(unittest.TestCase):
    def test_whole_class_collapses_and_partial_lists_methods(self):
        ids = ["SetupJourneyTests/testStepOne", "FoodHubJourneyTests/testHubAtAX5"]
        self.assertEqual(test_suites.only_testing(ids, CLASSES),
                         ["-only-testing:FentonHomeUITests/FoodHubJourneyTests", "-only-testing:FentonHomeUITests/SetupJourneyTests/testStepOne"])

    def test_within_intersects_with_a_changed_list(self):
        ids = ["ChoresPageJourneyTests/testPageAudit", "FoodHubJourneyTests/testHubAtAX5", "SetupJourneyTests/testStepOne"]
        got = test_suites.within(ids, "-only-testing:FentonHomeUITests/ChoresPageJourneyTests -only-testing:FentonHomeUITests/SetupJourneyTests/testStepOne")
        self.assertEqual(got, [ids[0], ids[2]])
        self.assertEqual(test_suites.within(ids, ""), [])

    def test_owning_plan(self):
        self.assertEqual(test_suites.owning_plan(["FoodHubJourneyTests/testHubAtAX5"], CLASSES), "Gate")
        self.assertTrue(test_suites.owning_plan(["FoodHubJourneyTests/testHubAtAX5", "ChoresLiveJourneyTests/testLiveAudit"], CLASSES).startswith("mixed:"))


class CommittedManifestTests(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(TOOLS / "test_suites.py"), *args], capture_output=True, text=True)

    def test_check_passes(self):
        out = self.run_cli("check")
        self.assertEqual(out.returncode, 0, out.stderr)

    def test_list_and_resolve(self):
        self.assertIn("audits", self.run_cli("list", "--no-times").stdout)
        out = self.run_cli("resolve", "--only-testing", "smoke")
        self.assertEqual(out.returncode, 0)
        self.assertIn("-only-testing:FentonHomeUITests/", out.stdout)

    def test_unknown_selection_fails(self):
        self.assertEqual(self.run_cli("args", "--suite", "no-such-suite").returncode, 2)
        self.assertEqual(self.run_cli("resolve", "NoSuchClass*").returncode, 2)


if __name__ == "__main__":
    unittest.main()
