"""``tools/affected_tests.py``: selection from contracts/test-map.json, unknown files, the ledger, ios_uitest flags."""

import contextlib
import importlib.util
import io
import json
import os
import re
import subprocess
import sys
import unittest
from unittest import mock
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
# Load by path (tools/ is not on sys.path).
_spec = importlib.util.spec_from_file_location("affected_tests", TOOLS / "affected_tests.py")
affected_tests = importlib.util.module_from_spec(_spec)
sys.modules["affected_tests"] = affected_tests
_spec.loader.exec_module(affected_tests)

REPO = TOOLS.parent
MAP = affected_tests.load_map()


def pick(*files, test_map=None):
    return affected_tests.select(files, test_map or MAP)


def git(root, *args):
    subprocess.run(["git", *args], cwd=root, check=True, capture_output=True,
                   env={"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
                        "GIT_COMMITTER_EMAIL": "t@t", "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"})


class SelectTests(unittest.TestCase):
    def test_pattern_source_maps_to_its_tests_and_journey(self):
        result = pick("apple/Sources/HassDesign/HeaderEdgeFadeModifier.swift")
        self.assertEqual(result["swift"], ["HeaderEdgeFade"])
        self.assertEqual(result["journeys"], ["HeaderFadeJourneyTests"])
        self.assertEqual(affected_tests.swift_args(result), "--filter HeaderEdgeFade")
        self.assertEqual(affected_tests.journey_args(result), "-only-testing:FentonHomeUITests/HeaderFadeJourneyTests")

    def test_longest_prefix_wins(self):
        result = pick("apple/Sources/HassDesign/ThermostatDial/Geometry.swift")
        self.assertEqual(result["swift"], ["ThermostatDial"])
        fallback = pick("apple/Sources/HassDesign/Announcer.swift")
        self.assertEqual(fallback["swift"], ["HassDesignTests"])

    def test_docs_tools_and_mockups_need_no_tests(self):
        result = pick("AGENTS.md", ".agents/patterns/x.md", "tools/foo.py", "PROGRESS.md", "contracts/test-map.json")
        self.assertEqual((result["swift"], result["journeys"], result["unknown"]), ([], [], []))
        self.assertEqual(len(result["ignored"]), 5)

    def test_changed_test_file_selects_its_own_classes(self):
        result = pick("apple/Tests/HassDesignTests/SheetFitTests.swift")
        self.assertIn("SheetFitTests", result["swift"])
        journey = pick("apple/Apps/iOSUITests/LocationJourneyTests.swift")
        self.assertEqual(journey["swift"], [])
        self.assertIn("LocationShadowJourneyTests", journey["journeys"])
        self.assertIn("LocationJourneyTests", journey["journeys"])

    def test_every_seeded_rule_names_real_tests(self):
        names = {p.name for p in (REPO / "apple" / "Tests").iterdir() if p.is_dir()}  # a whole test target is a valid filter
        for path in (REPO / "apple" / "Tests").rglob("*.swift"):
            names.update(affected_tests.classes_in(path))
        journeys = {p.stem for p in (REPO / "apple" / "Apps" / "iOSUITests").glob("*.swift")}
        journeys.update(c for p in (REPO / "apple" / "Apps" / "iOSUITests").glob("*.swift") for c in affected_tests.classes_in(p))
        stale = []
        for rule in MAP["rules"]:
            for name in rule["swift"]:
                if not any(re.search(name, known) for known in names):  # filters are regexes over type names
                    stale.append((rule["prefix"], name))
            for name in rule["journeys"]:
                if name not in journeys:
                    stale.append((rule["prefix"], name))
        self.assertEqual(stale, [])

    def test_filters_are_type_names_not_file_stems(self):
        self.assertIn("SplitPolicyTests", pick("apple/Sources/HassUI/App/Layout/SplitPolicy.swift")["swift"])
        self.assertIn("PushConfigTests", pick("apple/Sources/HassCore/Push/PushConfig.swift")["swift"])
        # LayoutPolicyTests.swift declares no LayoutPolicyTests type
        self.assertNotIn("LayoutPolicyTests", pick("apple/Tests/HassUITests/LayoutPolicyTests.swift")["swift"])
        self.assertIn("SplitPolicyTests", pick("apple/Tests/HassUITests/LayoutPolicyTests.swift")["swift"])

    def test_families_narrow_to_iphone_unless_the_surface_is_layout_sensitive(self):
        self.assertEqual(pick("apple/Sources/HassUI/Features/Chores/ChoresView.swift")["families"], ["iphone"])
        self.assertEqual(pick("apple/Sources/HassDesign/SheetFit.swift")["families"], ["iphone", "duo", "ipad"])
        self.assertEqual(pick("apple/Sources/HassUI/App/Layout/SplitPolicy.swift")["families"], ["iphone", "duo", "ipad"])
        self.assertEqual(pick("apple/Sources/HassDesign/PagedRow.swift")["families"], ["iphone", "duo", "ipad"])
        self.assertEqual(pick("apple/Apps/iOSUITests/TileLayoutJourneyTests.swift")["families"], ["iphone", "duo", "ipad"])
        self.assertEqual(pick("apple/Apps/iOSUITests/ChoresSwipeJourneyTests.swift")["families"], ["iphone"])
        self.assertEqual(pick("apple/Apps/iOSUITests/ChoresWideLayoutJourneyTests.swift")["families"], ["iphone", "duo", "ipad"])
        self.assertEqual(pick("apple/Sources/HassUI/UIKitPort/Features/Chores/UKTodoPageViewController.swift")["families"], ["iphone", "duo", "ipad"])

    def test_core_telemetry_and_activity_model_get_no_device_run(self):
        for file in ("apple/Sources/HassCore/Climate/ClimateLogic.swift", "apple/Sources/HassTelemetry/X.swift",
                     "apple/Sources/FentonActivityModel/ActivityCard.swift"):
            result = pick(file)
            self.assertEqual((result["journeys"], result["families"], result["unknown"]), ([], [], []), file)
            self.assertTrue(result["swift"])

    def test_project_and_helper_files_run_the_shell_smoke_journey(self):
        for file in ("apple/project.yml", "apple/Package.swift", "apple/Apps/iOSUITests/FentonHomeApp.swift",
                     "apple/Apps/iOSUITests/JourneyTestCase.swift"):
            result = pick(file)
            self.assertEqual((result["journeys"], result["families"], result["unknown"]), (["ShellJourneyTests"], ["iphone"], []), file)

    def test_shell_runs_on_every_family_and_a_deleted_test_needs_no_pick(self):
        self.assertEqual(pick("apple/Sources/HassUI/App/Shell/Rail.swift")["families"], ["iphone", "duo", "ipad"])
        result = pick("apple/Tests/HassUITests/NoSuchRemovedTests.swift")
        self.assertEqual((result["unknown"], result["swift"]), ([], []))

    def test_every_rule_prefix_exists(self):
        missing = [rule["prefix"] for rule in MAP["rules"]
                   if not list(REPO.glob(rule["prefix"] + "*"))]
        self.assertEqual(missing, [])

    def test_unmapped_swift_falls_back_to_its_module_test_target(self):
        empty = {"rules": [], "ignore": [], "families": ["iphone"], "journeyTarget": "T"}
        result = affected_tests.select(["apple/Sources/HassUI/Brand/Zzz.swift"], empty, REPO)
        self.assertEqual((result["swift"], result["unknown"]), (["HassUITests"], []))
        self.assertEqual(affected_tests.module_tests("apple/Sources/Brand/NewThing.swift", REPO), None)

    def test_other_families_get_the_smoke_plan_unless_layout_sensitive(self):
        chores = pick("apple/Sources/HassUI/Features/Chores/ChoresView.swift")
        self.assertEqual((chores["families"], chores["smoke_families"], chores["layout_sensitive"]), (["iphone"], ["duo", "ipad"], False))
        sheet = pick("apple/Sources/HassDesign/SheetFit.swift")
        self.assertEqual((sheet["families"], sheet["smoke_families"], sheet["layout_sensitive"]),
                         (["iphone", "duo", "ipad"], [], True))
        core = pick("apple/Sources/HassCore/Climate/ClimateLogic.swift")
        self.assertEqual((core["families"], core["smoke_families"]), ([], []))

    def test_smoke_list_names_real_journey_tests(self):
        classes = {}
        for path in (REPO / "apple" / "Apps" / "iOSUITests").glob("*.swift"):
            text = path.read_text()
            for name in affected_tests.classes_in(path):
                classes[name] = text
        self.assertGreaterEqual(len(MAP["smoke"]), 8)
        for entry in MAP["smoke"]:
            cls, method = entry.split("/")
            self.assertIn(cls, classes, entry)
            self.assertIn("func %s(" % method, classes[cls], entry)

    def test_unknown_source_asks_for_a_pick_and_never_the_full_suite(self):
        empty = {"rules": [], "ignore": [], "families": ["iphone"], "journeyTarget": "T"}
        result = affected_tests.select(["apple/Sources/Brand/NewThing.swift"], empty, REPO)
        self.assertEqual((result["swift"], result["journeys"]), ([], []))
        self.assertEqual(result["unknown"], ["apple/Sources/Brand/NewThing.swift"])
        request = affected_tests.unknown_request(result)
        self.assertIn("NEEDS A PICK", request)
        self.assertIn("NewThing.swift", request)
        self.assertIn("nightly", request)
        self.assertEqual(affected_tests.unknown_request(pick("AGENTS.md")), "")

    def test_file_name_convention_when_no_rule_matches(self):
        empty = {"rules": [], "ignore": [], "families": ["iphone"], "journeyTarget": "T"}
        result = affected_tests.select(["apple/Sources/HassDesign/PageIndicator.swift"], empty, REPO)
        self.assertIn("PageIndicatorTests", result["swift"])
        self.assertEqual(result["unknown"], [])

    def test_rule_families_override_the_default(self):
        custom = {"rules": [{"prefix": "a/", "swift": ["A"], "journeys": ["J"], "families": ["ipad"]}],
                  "ignore": [], "families": ["iphone", "duo", "ipad"]}
        self.assertEqual(affected_tests.select(["a/x.swift"], custom)["families"], ["iphone", "ipad"])
        self.assertEqual(affected_tests.select(["a/x.swift"], {**custom, "rules": [{"prefix": "a/", "swift": ["A"], "journeys": ["J"]}]})["families"],
                         ["iphone"])


class VacationRulesTests(unittest.TestCase):
    """The UIKit port keeps the vacation screens in one file (`UKVacation.swift`): it selects every vacation class."""
    SRC = "apple/Sources/HassUI/UIKitPort/Features/Household/"

    def test_the_solo_trip_screen_selects_the_mode_and_solo_trip_classes(self):
        self.assertEqual(pick(self.SRC + "UKVacation.swift")["journeys"],
                         ["VacationChooserJourneyTests", "VacationModeJourneyTests", "VacationConfirmJourneyTests", "VacationSoloTripJourneyTests"])


class InventoryRulesTests(unittest.TestCase):
    """The Inventory split (contracts/test-map.json): per-file rules select only the area classes that exercise the file."""
    SRC = "apple/Sources/HassUI/UIKitPort/Features/Inventory/"
    AREAS = ["InventoryListJourneyTests", "InventoryRowActionsJourneyTests", "InventorySheetsJourneyTests",
             "InventoryEditorJourneyTests", "InventoryScanJourneyTests"]

    def test_shared_files_and_the_fallback_select_every_area(self):
        for name in ("UKInventoryViewController.swift", "UKSomethingNew.swift"):
            self.assertEqual(sorted(pick(self.SRC + name)["journeys"]), sorted(self.AREAS), name)

    def test_ui_kit_files_select_every_area(self):
        # The port's screens are folder-ruled (the per-file split went with the SwiftUI files).
        for name in ("UKInventoryRow.swift", "UKInventoryRowActions.swift", "UKScanItemSheet.swift", "UKInventorySheets.swift"):
            self.assertEqual(sorted(pick(self.SRC + name)["journeys"]), sorted(self.AREAS), name)

    def test_the_base_selects_every_class_but_the_live_one(self):
        base = pick("apple/Apps/iOSUITests/InventoryJourneyTestCase.swift")["journeys"]
        self.assertEqual(base, self.AREAS)
        self.assertNotIn("InventoryLiveJourneyTests", base)

    def test_scan_files_also_select_the_scan_host_suites(self):
        self.assertIn("ScanItem", pick(self.SRC + "UKScanItemSheet.swift")["swift"])

    def test_inventory_is_not_layout_sensitive(self):
        self.assertEqual(pick(self.SRC + "UKInventoryViewController.swift")["families"], ["iphone"])


class DiffTests(unittest.TestCase):
    def test_changed_files_covers_commits_edits_and_untracked_files(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            git(root, "init", "-q", "-b", "main")
            (root / "a.txt").write_text("1")
            git(root, "add", "-A"); git(root, "commit", "-qm", "base")
            git(root, "branch", "origin-main")
            (root / "b.txt").write_text("2")
            git(root, "add", "-A"); git(root, "commit", "-qm", "work")
            (root / "a.txt").write_text("changed")
            (root / "c.txt").write_text("new")
            self.assertEqual(affected_tests.changed_files("origin-main", root), ["a.txt", "b.txt", "c.txt"])

    def test_the_base_comes_from_the_environment_at_call_time(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            git(root, "init", "-q", "-b", "main")
            (root / "a.txt").write_text("1")
            git(root, "add", "-A"); git(root, "commit", "-qm", "base")
            git(root, "branch", "lane-base")
            (root / "b.txt").write_text("2")
            git(root, "add", "-A"); git(root, "commit", "-qm", "work")
            with mock.patch.dict(os.environ, {"FENTON_AFFECTED_BASE": "lane-base"}):
                self.assertEqual(affected_tests.default_base(), "lane-base")
                self.assertEqual(affected_tests.changed_files(root=root), ["b.txt"])

    def test_default_base_is_what_the_resolver_picks(self):
        sys.path.insert(0, str(TOOLS))
        self.addCleanup(sys.path.remove, str(TOOLS))
        import lane_base
        with mock.patch.object(lane_base, "base_ref", return_value="origin/claude/some-port"):
            self.assertEqual(affected_tests.default_base(), "origin/claude/some-port")
        with mock.patch.object(lane_base, "base_ref", side_effect=LookupError("none")):
            self.assertEqual(affected_tests.default_base(), "HEAD")


class LedgerTests(unittest.TestCase):
    def test_key_depends_on_tree_filter_and_device(self):
        key = affected_tests.ledger_key
        self.assertEqual(key("t", "f", "d"), key("t", "f ", "d"))
        self.assertEqual(len({key("t", "f", "d"), key("u", "f", "d"), key("t", "g", "d"), key("t", "f", "e")}), 4)

    def test_only_a_recorded_pass_is_seen(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertFalse(affected_tests.seen("t", "f", "iphone", root))
            affected_tests.record("t", "f", "iphone", root)
            self.assertTrue(affected_tests.seen("t", "f", "iphone", root))
            self.assertFalse(affected_tests.seen("t", "f", "duo", root))
            self.assertFalse(affected_tests.seen("t2", "f", "iphone", root))
            affected_tests.ledger_path("t3", "f", "iphone", root).parent.mkdir(parents=True, exist_ok=True)
            affected_tests.ledger_path("t3", "f", "iphone", root).write_text("{broken")
            self.assertFalse(affected_tests.seen("t3", "f", "iphone", root))

    def test_tree_hash_follows_apple_edits_only(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            git(root, "init", "-q", "-b", "main")
            (root / "apple").mkdir()
            (root / "apple" / "A.swift").write_text("1")
            (root / "notes.md").write_text("x")
            git(root, "add", "-A"); git(root, "commit", "-qm", "base")
            before = affected_tests.tree_hash(root)
            (root / "notes.md").write_text("changed")
            self.assertEqual(affected_tests.tree_hash(root), before)
            (root / "apple" / "A.swift").write_text("2")
            edited = affected_tests.tree_hash(root)
            self.assertNotEqual(edited, before)
            (root / "apple" / "B.swift").write_text("new")
            self.assertNotEqual(affected_tests.tree_hash(root), edited)


class PlanFilterTests(unittest.TestCase):
    """``--journeys --plan``: a class the plan skips whole matches nothing, which xcodebuild reports as EMPTY."""

    def write_plan(self, folder, name, **target):
        entry = {"target": {"name": "FentonHomeUITests", "containerPath": "container:FentonHome.xcodeproj"}, **target}
        (Path(folder) / f"{name}.xctestplan").write_text(json.dumps({"testTargets": [entry]}))

    def test_skipped_tests_drop_a_whole_class_only(self):
        with TemporaryDirectory() as folder:
            self.write_plan(folder, "Gate", skippedTests=["ShellJourneyTests", "SecurityJourneyTests/testCapture()"])
            runs = lambda name: affected_tests.plan_runs("Gate", "FentonHomeUITests", name, Path(folder))
            self.assertFalse(runs("ShellJourneyTests"))
            self.assertTrue(runs("SecurityJourneyTests"))  # one method skipped, the rest run
            self.assertTrue(runs("ModalSizingJourneyTests"))

    def test_selected_tests_keep_only_the_named_classes(self):
        with TemporaryDirectory() as folder:
            self.write_plan(folder, "Smoke", selectedTests=["SheetBottomGapJourneyTests/testQuickLinks()"])
            runs = lambda name: affected_tests.plan_runs("Smoke", "FentonHomeUITests", name, Path(folder))
            self.assertTrue(runs("SheetBottomGapJourneyTests"))
            self.assertFalse(runs("SheetBottomGap"))
            self.assertFalse(runs("ShellJourneyTests"))

    def test_a_missing_plan_runs_everything(self):
        with TemporaryDirectory() as folder:
            self.assertTrue(affected_tests.plan_runs("Nope", "FentonHomeUITests", "ShellJourneyTests", Path(folder)))

    def test_journey_args_filter_to_the_plan(self):
        with TemporaryDirectory() as folder:
            self.write_plan(folder, "Gate", skippedTests=["ShellJourneyTests"])
            result = {"target": "FentonHomeUITests", "journeys": ["ShellJourneyTests", "ModalSizingJourneyTests"]}
            self.assertEqual(affected_tests.journey_args(result, plan="Gate", plans_dir=Path(folder)),
                             "-only-testing:FentonHomeUITests/ModalSizingJourneyTests")
            result["journeys"] = ["ShellJourneyTests"]
            self.assertEqual(affected_tests.journey_args(result, plan="Gate", plans_dir=Path(folder)), "")

    def test_the_committed_gate_plan_skips_the_shell_journeys(self):
        # The hosted iPhone failure (run 42451291334): the shell class is a Live-plan class, so Gate runs none of it.
        self.assertFalse(affected_tests.plan_runs("Gate", "FentonHomeUITests", "ShellJourneyTests"))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = affected_tests.main(["--journeys", "--plan", "Gate", "--files", "apple/Apps/iOSUITests/ShellJourneyTests.swift"])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue().strip(), "")

    def test_a_class_skipped_method_by_method_runs_nothing(self):
        with TemporaryDirectory() as folder:
            self.write_plan(folder, "Gate", skippedTests=["A/testOne()", "A/testTwo()", "B/testOne()"])
            runs = lambda name, methods: affected_tests.plan_runs("Gate", "FentonHomeUITests", name, Path(folder), methods)
            self.assertFalse(runs("A", ["testOne", "testTwo"]))
            self.assertTrue(runs("B", ["testOne", "testTwo"]))

    def test_a_disabled_target_runs_nothing(self):
        with TemporaryDirectory() as folder:
            self.write_plan(folder, "Gate", enabled=False, skippedTests=[])
            self.assertFalse(affected_tests.plan_runs("Gate", "FentonHomeUITests", "ModalSizingJourneyTests", Path(folder)))


class CommandLineTests(unittest.TestCase):
    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = affected_tests.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_outputs_for_a_file_list(self):
        files = ["--files", "apple/Sources/HassDesign/SheetFit.swift"]
        self.assertEqual(self.run_main("--swift", *files)[1].strip(), "--filter SheetFit")
        self.assertIn("-only-testing:FentonHomeUITests/ModalSizingJourneyTests", self.run_main("--journeys", *files)[1])
        self.assertEqual(self.run_main("--families", *files)[1].split(), ["iphone", "duo", "ipad"])
        self.assertEqual(self.run_main("--families", "--files", "apple/Sources/HassCore/Climate/X.swift")[1].split(), [])
        self.assertEqual(json.loads(self.run_main("--json", *files)[1])["swift"], ["SheetFit"])
        self.assertIn("swift test:", self.run_main(*files)[1])

    def test_environment_narrows_the_pull_request_audit_only_when_journeys_run(self):
        journeys = "apple/Sources/HassUI/UIKitPort/Features/Inventory/UKInventoryRow.swift"
        self.assertEqual(MAP["changedEnvironment"], {"FENTON_UITEST_SPACES": "all-food"})
        self.assertEqual(self.run_main("--environment", "--files", journeys)[1].strip(), "FENTON_UITEST_SPACES=all-food")
        self.assertEqual(self.run_main("--environment", "--files", "apple/Sources/HassCore/Climate/X.swift")[1].strip(), "")
        self.assertEqual(self.run_main("--environment", "--files", "AGENTS.md")[1].strip(), "")

    def test_unknown_files_exit_3_and_explain_on_stderr(self):
        code, out, err = self.run_main("--journeys", "--files", "Mystery/File.kt")
        self.assertEqual((code, out.strip()), (3, ""))
        self.assertIn("NEEDS A PICK", err)

    def test_ledger_commands(self):
        with TemporaryDirectory() as tmp:
            old = affected_tests.ROOT
            affected_tests.ROOT = Path(tmp)
            try:
                # record/seen take their root from the module default
                affected_tests.record.__defaults__ = (Path(tmp), "pass")
                affected_tests.result_of.__defaults__ = (Path(tmp),)
                affected_tests.seen.__defaults__ = (Path(tmp),)
                self.assertEqual(self.run_main("seen", "--tree", "T", "--device", "ipad", "--filter", "F")[0], 1)
                self.assertEqual(self.run_main("record", "--tree", "T", "--device", "ipad", "--filter", "F")[0], 0)
                self.assertEqual(self.run_main("seen", "--tree", "T", "--device", "ipad", "--filter", "F")[0], 0)
                self.assertEqual(self.run_main("record", "--tree", "T", "--device", "duo", "--filter", "F", "--result", "skipped")[0], 0)
                self.assertEqual(self.run_main("seen", "--tree", "T", "--device", "duo", "--filter", "F")[0], 1)  # a skipped record is not a pass
                self.assertEqual(affected_tests.result_of("T", "F", "duo"), "skipped")
            finally:
                affected_tests.ROOT = old
                affected_tests.record.__defaults__ = (old, "pass")
                affected_tests.result_of.__defaults__ = (old,)
                affected_tests.seen.__defaults__ = (old,)

    def test_tree_hash_command_prints_a_hash(self):
        code, out, _ = self.run_main("tree-hash")
        self.assertEqual(code, 0)
        self.assertRegex(out.strip(), r"^[0-9a-f]{40}$|^unknown$")


class PerFamilyTests(unittest.TestCase):
    """Duo and iPad run only the layout journeys of a change; iPhone runs them all."""

    SPLIT_MAP = {"families": ["iphone", "duo", "ipad"], "defaultFamilies": ["iphone"], "journeyTarget": "T",
           "layoutJourneys": ["PoseJourneyTests"], "ignore": [],
           "rules": [{"prefix": "apple/Sources/X/Split", "swift": ["X"], "journeys": ["AJourneyTests", "PoseJourneyTests", "BJourneyTests"],
                      "layout_journeys": ["PoseJourneyTests"]},
                     {"prefix": "apple/Sources/X/Blanket", "swift": ["X"], "journeys": ["AJourneyTests", "BJourneyTests"], "layout_sensitive": True},
                     {"prefix": "apple/Sources/X/Plain", "swift": ["X"], "journeys": ["AJourneyTests", "PoseJourneyTests"]},
                     {"prefix": "apple/Sources/X/Explicit", "swift": ["X"], "journeys": ["AJourneyTests"], "families": ["ipad"]}]}

    def pick(self, *files):
        return affected_tests.select(files, self.SPLIT_MAP, REPO)

    def test_layout_journeys_alone_go_to_duo_and_ipad(self):
        result = self.pick("apple/Sources/X/SplitView.swift")
        self.assertEqual(result["journeys_by_family"], {"iphone": ["AJourneyTests", "PoseJourneyTests", "BJourneyTests"],
                                                        "duo": ["PoseJourneyTests"], "ipad": ["PoseJourneyTests"]})
        self.assertEqual((result["families"], result["smoke_families"], result["layout_sensitive"]), (["iphone", "duo", "ipad"], [], True))
        self.assertEqual(result["journeys"], ["AJourneyTests", "PoseJourneyTests", "BJourneyTests"])  # the old key is the iPhone list

    def test_a_blanket_layout_sensitive_rule_sends_every_journey_everywhere(self):
        result = self.pick("apple/Sources/X/BlanketView.swift")
        for family in ("iphone", "duo", "ipad"):
            self.assertEqual(result["journeys_by_family"][family], ["AJourneyTests", "BJourneyTests"])

    def test_a_layout_journey_a_rule_merely_selects_stays_on_iphone(self):
        result = self.pick("apple/Sources/X/PlainView.swift")
        self.assertEqual(result["journeys_by_family"], {"iphone": ["AJourneyTests", "PoseJourneyTests"], "duo": [], "ipad": []})
        self.assertEqual((result["families"], result["smoke_families"], result["layout_sensitive"]), (["iphone"], ["duo", "ipad"], False))

    def test_an_explicit_family_runs_all_the_rules_journeys(self):
        result = self.pick("apple/Sources/X/ExplicitView.swift")
        self.assertEqual(result["journeys_by_family"], {"iphone": ["AJourneyTests"], "duo": [], "ipad": ["AJourneyTests"]})
        self.assertEqual(result["smoke_families"], ["duo"])

    def test_a_changed_layout_journey_file_runs_only_itself_on_the_wide_families(self):
        result = affected_tests.select(["apple/Apps/iOSUITests/ChoresWideLayoutJourneyTests.swift",
                                        "apple/Apps/iOSUITests/ChoresSwipeJourneyTests.swift"], MAP, REPO)
        self.assertEqual(result["journeys_by_family"]["duo"], ["ChoresWideLayoutJourneyTests"])
        self.assertEqual(result["journeys_by_family"]["iphone"], ["ChoresWideLayoutJourneyTests", "ChoresSwipeJourneyTests"])

    def test_no_journeys_means_empty_lists_everywhere(self):
        result = self.pick("apple/Sources/HassCore/Foo.swift")
        self.assertEqual(result["journeys_by_family"], {"iphone": [], "duo": [], "ipad": []})

    def test_journey_args_take_a_family(self):
        result = self.pick("apple/Sources/X/SplitView.swift")
        self.assertEqual(affected_tests.journey_args(result, "duo"), "-only-testing:T/PoseJourneyTests")
        self.assertEqual(affected_tests.journey_args(result), affected_tests.journey_args(result, "iphone"))
        self.assertEqual(affected_tests.journey_args(result).count("-only-testing"), 3)

    def test_cli_prints_the_family_list(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "map.json"
            path.write_text(json.dumps(self.SPLIT_MAP))
            for device, expected in (("", 3), ("iphone", 3), ("duo", 1), ("ipad", 1)):
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    affected_tests.main(["--map", str(path), "--files", "apple/Sources/X/SplitView.swift", "--journeys"]
                                        + (["--device", device] if device else []))
                self.assertEqual(out.getvalue().count("-only-testing"), expected, device)

    def test_real_split_suites_send_only_their_pose_class_to_duo_and_ipad(self):
        for file, pose in (("apple/Sources/HassUI/UIKitPort/Features/RoomDevices/UKHumidifierSheet.swift", "RoomDevicesHumidifierPoseJourneyTests"),
                           ("apple/Sources/HassUI/UIKitPort/Features/Vacuums/UKVacuumSheet.swift", "VacuumSplitPoseJourneyTests"),
                           ("apple/Sources/HassUI/UIKitPort/Features/Vacuums/UKVacuumsViewController.swift", "VacuumSplitPoseJourneyTests"),
                           ("apple/Sources/HassUI/UIKitPort/Features/Food/UKRecipesViewController.swift", "FoodWideLayoutJourneyTests"),
                           ("apple/Sources/HassUI/UIKitPort/Features/Food/UKRecipeDetail.swift", "FoodWideLayoutJourneyTests"),
                           ("apple/Sources/HassUI/UIKitPort/Features/Chores/UKTodoForms.swift", "ChoresWideLayoutJourneyTests"),
                           ("apple/Sources/HassUI/UIKitPort/Features/Chores/UKTodoPageViewController.swift", "ChoresWideLayoutJourneyTests")):
            result = affected_tests.select([file], MAP, REPO)
            # Food and Chores pages open beside each other in columns, so their UIKit rules also name ColumnRoutesJourneyTests
            expected = [pose, "ColumnRoutesJourneyTests"] if "/Features/Food/" in file or "/Features/Chores/" in file else [pose]
            self.assertEqual(result["journeys_by_family"]["duo"], expected, file)
            self.assertEqual(result["journeys_by_family"]["ipad"], expected, file)
            self.assertIn(pose, result["journeys_by_family"]["iphone"], file)
            self.assertGreater(len(result["journeys_by_family"]["iphone"]), 1, file)

    def test_shared_design_and_shell_rules_stay_blanket(self):
        for file in ("apple/Sources/HassDesign/SheetFit.swift", "apple/Sources/HassUI/App/Shell/Rail.swift"):
            result = affected_tests.select([file], MAP, REPO)
            self.assertEqual({tuple(v) for v in result["journeys_by_family"].values()}, {tuple(result["journeys"])}, file)

    def test_layout_journeys_are_a_subset_of_their_rules_journeys_and_real_classes(self):
        for rule in MAP["rules"]:
            for name in rule.get("layout_journeys", []):
                self.assertIn(name, rule["journeys"], rule["prefix"])
            self.assertFalse(rule.get("layout_sensitive") and rule.get("layout_journeys"), rule["prefix"])


class UitestFlagTests(unittest.TestCase):
    text = (TOOLS / "ios_uitest.sh").read_text()

    def test_changed_and_force_are_parsed(self):
        self.assertIn("--changed) CHANGED=1", self.text)
        self.assertIn("--force) FORCE=1", self.text)
        self.assertIn("affected --journeys", self.text)

    def test_unmapped_diff_runs_nothing(self):
        self.assertIn("nothing to run", self.text)
        self.assertNotIn("CHANGED_JOURNEYS:-", self.text)

    def test_passing_runs_are_recorded_and_skipped(self):
        self.assertIn("already_passed", self.text)
        self.assertIn("affected_tests.py\" record", self.text)

    def test_skip_key_covers_the_runtime_environment_and_never_skips_a_full_run(self):
        for needle in ("TEST_RUNNER_FENTON_", "env=$ENV_FILE", "xcodebuild -version", "sim:$(device_name", "$FULL_SUITE == 1"):
            self.assertIn(needle, self.text)

    def test_unmapped_changed_files_exit_with_the_pick_status(self):
        self.assertIn('exit "$AFFECTED_STATUS"', self.text)

    def test_changed_runs_export_the_map_environment_unless_the_caller_set_it(self):
        self.assertIn("affected --environment", self.text)
        self.assertIn('var="TEST_RUNNER_${pair%%=*}"', self.text)
        self.assertIn('[[ -z "${!var:-}" ]]', self.text)
        changed = self.text.index("if [[ $CHANGED == 1 ]]")
        self.assertLess(changed, self.text.index("--environment"))
        self.assertLess(self.text.index("--environment"), self.text.index('ENV_HASH="'))  # the skip key covers the narrowed audit

    def test_script_parses(self):
        subprocess.run(["bash", "-n", str(TOOLS / "ios_uitest.sh")], check=True)


if __name__ == "__main__":
    unittest.main()
