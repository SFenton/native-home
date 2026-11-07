"""``tools/ios_uitest.sh`` default hold scaling and per-run build stamp."""

import os
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "ios_uitest.sh"


def hold(*args, **env):
    run_env = {**os.environ, "FENTON_UITEST_PRINT_HOLD": "1"}
    run_env.pop("FENTON_DEVCAP_HOLD", None)
    run_env.update(env)
    out = subprocess.run(["bash", str(SCRIPT), *args], env=run_env, capture_output=True, text=True, check=True)
    return int(out.stdout.strip().splitlines()[-1])


def filters(files, test_map=None, *args, **env):
    """The per-family argument lists a ``--changed`` dry run would hand xcodebuild: {family: [args]}."""
    run_env = {**os.environ, "FENTON_UITEST_PRINT_FILTERS": "1", "FENTON_AFFECTED_FILES": " ".join(files)}
    if test_map:
        run_env["FENTON_TEST_MAP"] = str(test_map)
    run_env.update(env)
    out = subprocess.run(["bash", str(SCRIPT), "--changed", "--force", *args], env=run_env, capture_output=True, text=True)
    lines = [line.split(": ", 1) for line in out.stdout.splitlines() if line.split(": ", 1)[0] in ("iphone", "duo", "ipad")]
    return {family: rest.split() for family, rest in lines}, out


class PerFamilyFilterTests(unittest.TestCase):
    def test_each_family_gets_its_own_only_testing_list(self):
        got, out = filters(["apple/Sources/HassUI/Features/RoomDevices/HumidifierSheet.swift"])
        self.assertEqual(out.returncode, 0, out.stderr)
        pose = "-only-testing:FentonHomeUITests/RoomDevicesHumidifierPoseJourneyTests"
        self.assertEqual(got["duo"], [pose])
        self.assertEqual(got["ipad"], [pose])
        self.assertIn(pose, got["iphone"])
        self.assertEqual(len(got["iphone"]), 3)

    def test_caller_arguments_reach_every_family(self):
        got, _ = filters(["apple/Sources/HassUI/Features/RoomDevices/HumidifierSheet.swift"], None, "FOO=bar")
        for family in ("iphone", "duo", "ipad"):
            self.assertIn("FOO=bar", got[family])

    def test_a_blanket_rule_gives_every_family_the_same_list(self):
        got, _ = filters(["apple/Sources/HassDesign/SheetFit.swift"])
        self.assertEqual(got["iphone"], got["duo"])
        self.assertEqual(got["iphone"], got["ipad"])

    def test_a_family_with_no_layout_journey_is_left_to_the_smoke_plan(self):
        got, out = filters(["apple/Sources/HassUI/Features/Chores/ChoresView.swift"])
        self.assertEqual(list(got), ["iphone"])
        self.assertIn("-only-testing", " ".join(got["iphone"]))

    def test_the_ledger_key_covers_the_family_filter(self):
        text = SCRIPT.read_text()
        self.assertIn('family_args "$1"', text)
        self.assertIn('echo "${FAMILY_ARGS[*]-}|plan:$PLAN_ARGS', text)


class HoldTests(unittest.TestCase):
    def test_hold_follows_the_selected_test_count(self):
        self.assertEqual(hold("-only-testing:FentonHomeUITests/ShellJourneyTests/testX"), 600)  # 120 + 300, floored at 10 minutes
        self.assertEqual(hold("-only-testing:A/B/c", "-only-testing:A/B/d", "-only-testing:A/B/e", "-only-testing:A/B/f"), 780)

    def test_a_whole_class_counts_its_methods(self):
        count = int(subprocess.run(["python3", str(SCRIPT.parent / "uitest_support.py"), "count",
                                    "-only-testing:FentonHomeUITests/ShellJourneyTests"],
                                   capture_output=True, text=True, check=True).stdout)
        self.assertGreater(count, 1)
        self.assertEqual(hold("-only-testing:FentonHomeUITests/ShellJourneyTests"), max(600, min(7200, 120 * count + 300)))

    def test_hold_is_capped(self):
        self.assertEqual(hold(*[f"-only-testing:A/C{i}/m" for i in range(100)]), 7200)

    def test_unfiltered_run_is_capped_too(self):
        self.assertEqual(hold("--full"), 7200)

    def test_environment_override_wins(self):
        self.assertEqual(hold("-only-testing:A", FENTON_DEVCAP_HOLD="99"), 99)

    def test_unfiltered_run_needs_full(self):
        out = subprocess.run(["bash", str(SCRIPT)], capture_output=True, text=True, env={**os.environ, "FENTON_UITEST_PRINT_HOLD": ""})
        self.assertEqual(out.returncode, 2)
        for hint in ("--changed", "-only-testing", "--plan Smoke", "--full"):
            self.assertIn(hint, out.stderr)

    def test_smoke_plan_needs_no_full(self):
        out = subprocess.run(["bash", str(SCRIPT), "--plan", "Smoke", "--only", "nowhere"], capture_output=True, text=True,
                             env={**os.environ, "FENTON_UITEST_PRINT_HOLD": ""})
        self.assertNotIn("nightly/release tier", out.stderr)

    def test_on_demand_plans_need_no_full(self):
        for plan in ("Capture", "Perf", "Live"):
            out = subprocess.run(["bash", str(SCRIPT), "--plan", plan, "--only", "nowhere"], capture_output=True, text=True,
                                 env={**os.environ, "FENTON_UITEST_PRINT_HOLD": ""})
            self.assertNotIn("nightly/release tier", out.stderr, plan)

    def test_unfiltered_gate_plan_needs_full(self):
        out = subprocess.run(["bash", str(SCRIPT), "--plan", "Gate"], capture_output=True, text=True,
                             env={**os.environ, "FENTON_UITEST_PRINT_HOLD": ""})
        self.assertEqual(out.returncode, 2)
        self.assertIn("nightly/release tier", out.stderr)

    def test_products_come_from_the_cache_helper_into_a_partial_path_ending_in_the_extension(self):
        # xcodebuild appends ".xctestproducts" to a path without it; the helper's @PARTIAL@ name ends with it.
        text = SCRIPT.read_text()
        self.assertIn('products_cache.py" ensure --key "$PRODUCTS_KEY"', text)
        self.assertIn('-testProductsPath @PARTIAL@', text)
        self.assertNotIn('BUILD_STAMP', text)

    def test_the_key_does_not_see_the_environment(self):
        text = SCRIPT.read_text()
        self.assertIn('products_cache.py" key ${SETTINGS[@]', text)
        key_line = [line for line in text.splitlines() if line.startswith("PRODUCTS_KEY=")][0]
        self.assertNotIn("ENV_HASH", key_line)

    def test_unknown_plan_is_refused(self):
        out = subprocess.run(["bash", str(SCRIPT), "--plan", "Nope"], capture_output=True, text=True)
        self.assertEqual(out.returncode, 2)


def dry(*args, files=None, **env):
    """Dry run (FENTON_UITEST_PRINT_FILTERS) of ``ios_uitest.sh`` with ``args``: ({family: [args]}, completed process)."""
    run_env = {**os.environ, "FENTON_UITEST_PRINT_FILTERS": "1"}
    if files:
        run_env["FENTON_AFFECTED_FILES"] = " ".join(files)
    run_env.update(env)
    out = subprocess.run(["bash", str(SCRIPT), "--force", *args], env=run_env, capture_output=True, text=True)
    lines = [line.split(": ", 1) for line in out.stdout.splitlines() if line.split(": ", 1)[0] in ("iphone", "duo", "ipad")]
    return {family: rest.split() for family, rest in lines}, out


class SuiteSelectionTests(unittest.TestCase):
    CHORES = ["apple/Sources/HassUI/Features/Chores/ChoresView.swift"]

    def test_suite_resolves_to_only_testing_filters_on_every_family(self):
        got, out = dry("--suite", "smoke")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(sorted(got), ["duo", "ipad", "iphone"])
        self.assertTrue(all(a.startswith("-only-testing:FentonHomeUITests/") for a in got["iphone"]))
        self.assertEqual(got["iphone"], got["duo"])

    def test_tests_selector_and_caller_arguments(self):
        got, out = dry("--tests", "ChoresPageJourneyTests", "FOO=bar", "--only", "ipad")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(list(got), ["ipad"])
        self.assertIn("-only-testing:FentonHomeUITests/ChoresPageJourneyTests", got["ipad"])
        self.assertIn("FOO=bar", got["ipad"])

    def test_suite_and_tests_combine(self):
        got, _ = dry("--suite", "smoke", "--tests", "ChoresPageJourneyTests")
        self.assertIn("-only-testing:FentonHomeUITests/ChoresPageJourneyTests", got["iphone"])
        self.assertGreater(len(got["iphone"]), 1)

    def test_changed_intersects_with_the_suite(self):
        got, out = dry("--changed", "--suite", "audits", files=self.CHORES)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(list(got), ["iphone"])
        classes = {a.split("/")[1] for a in got["iphone"]}
        self.assertTrue(classes and all(c.startswith("Chores") for c in classes), classes)
        self.assertTrue(all("Audit" in a for a in got["iphone"]), got["iphone"])

    def test_changed_with_no_overlap_runs_nothing(self):
        got, out = dry("--changed", "--suite", "bedroom", files=self.CHORES)
        self.assertEqual(out.returncode, 0)
        self.assertEqual(got, {})
        self.assertIn("nothing", out.stdout)

    def test_unknown_suite_or_empty_selection_is_refused(self):
        self.assertEqual(dry("--suite", "no-such-suite")[1].returncode, 2)
        self.assertEqual(dry("--tests", "NoSuchClass*")[1].returncode, 2)

    def test_the_ledger_key_carries_the_resolved_tests(self):
        a, _ = dry("--tests", "ChoresPageJourneyTests")
        b, _ = dry("--tests", "ChoresSwipeJourneyTests")
        self.assertNotEqual(a["iphone"], b["iphone"])
        text = SCRIPT.read_text()
        self.assertIn('[[ $CHANGED == 1 || $SELECTING == 1 ]] || return 0', text)

    def test_the_owning_plan_is_used_when_none_is_given(self):
        out = subprocess.run(["bash", str(SCRIPT), "--suite", "perf", "--only", "nowhere"], capture_output=True, text=True,
                             env={**os.environ, "FENTON_UITEST_PRINT_HOLD": ""})
        self.assertNotIn("nightly/release tier", out.stderr)


if __name__ == "__main__":
    unittest.main()


class FamilyGatedTallyTests(unittest.TestCase):
    """A fake iPad-only class across three families: iPhone and Duo skip every test, iPad runs them. That run passes."""

    def verdict(self, text):
        sys.path.insert(0, str(SCRIPT.parent))
        import uitest_support
        return uitest_support.tally_verdict(text)

    def test_an_ipad_only_class_passes_when_one_family_ran_it(self):
        status, lines = self.verdict("xcodebuild_iphone 0 2\nxcodebuild_duo 0 2\nxcodebuild_ipad 2 0\n")
        self.assertEqual(status, 0)
        self.assertEqual(len(lines), 2)
        self.assertTrue(all(line.startswith("NOTE:") for line in lines))

    def test_empty_when_no_family_ran_a_test_or_the_only_family_skipped_everything(self):
        status, lines = self.verdict("xcodebuild_iphone 0 2\nxcodebuild_duo 0 2\nxcodebuild_ipad 0 2\n")
        self.assertEqual((status, lines[0].startswith("EMPTY:")), (1, True))
        self.assertEqual(self.verdict("xcodebuild_iphone 0 2\n")[0], 1)  # --only iphone leaves one row

    def test_no_tally_and_normal_runs_are_quiet(self):
        self.assertEqual(self.verdict(""), (0, []))
        self.assertEqual(self.verdict("a 5 0\nb 5 1\n"), (0, []))

    def test_cli_tally_exit_codes_and_the_script_uses_it(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "t"
            path.write_text("a 0 1\nb 0 1\n")
            run = lambda *a: subprocess.run([sys.executable, str(SCRIPT.parent / "uitest_support.py"), *a], capture_output=True, text=True)
            self.assertEqual(run("tally", str(path)).returncode, 1)
            path.write_text("a 0 1\nb 3 0\n")
            self.assertEqual(run("tally", str(path)).returncode, 0)
            path.write_text("a 0 0 empty\n")
            self.assertEqual(run("tally-empty", str(path)).returncode, 0)
            self.assertEqual(run("tally-empty", str(Path(tmp) / "none")).returncode, 1)
        text = SCRIPT.read_text()
        self.assertIn('uitest_support.py" tally "$FENTON_TALLY"', text)
        self.assertIn("--tally", text)


class SkippedLedgerTests(unittest.TestCase):
    """An all-skipped family is recorded ``skipped``, never ``pass``; only a real pass short-circuits a later run."""

    def setUp(self):
        import tempfile
        sys.path.insert(0, str(SCRIPT.parent))
        import affected_tests
        self.at = affected_tests
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_a_skipped_record_is_not_a_pass(self):
        self.at.record("t1", "f", "iphone", self.root, result="skipped")
        self.assertFalse(self.at.seen("t1", "f", "iphone", self.root))
        self.assertEqual(self.at.result_of("t1", "f", "iphone", self.root), "skipped")

    def test_a_real_pass_still_short_circuits(self):
        self.at.record("t1", "f", "ipad", self.root)
        self.assertTrue(self.at.seen("t1", "f", "ipad", self.root))
        self.assertEqual(self.at.result_of("t1", "f", "ipad", self.root), "pass")
        self.assertEqual(self.at.result_of("t1", "f", "duo", self.root), "")

    def test_tally_ran_decides_the_result_the_script_records(self):
        path = self.root / "tally"
        path.write_text("xcodebuild_iphone 0 2\nxcodebuild_ipad 2 0\n")
        run = lambda label: subprocess.run([sys.executable, str(SCRIPT.parent / "uitest_support.py"), "tally-ran", str(path), label]).returncode
        self.assertEqual((run("xcodebuild_iphone"), run("xcodebuild_ipad"), run("xcodebuild_duo")), (1, 0, 0))

    def test_replaying_a_skipped_family_on_its_own_is_empty(self):
        sys.path.insert(0, str(SCRIPT.parent))
        import uitest_support
        # the script appends `xcodebuild_iphone 0 0` for a recorded-skipped family; with --only iphone that is the whole tally
        status, lines = uitest_support.tally_verdict("xcodebuild_iphone 0 0\n")
        self.assertEqual((status, lines[0].startswith("EMPTY:")), (1, True))

    def test_an_identical_rerun_of_a_passing_gated_run_is_not_empty(self):
        # ipad recorded as pass (script appends `ipad 1 0`), iphone and duo recorded as skipped (`0 0`): the rerun passes
        sys.path.insert(0, str(SCRIPT.parent))
        import uitest_support
        self.assertEqual(uitest_support.tally_verdict("xcodebuild_iphone 0 0\nxcodebuild_duo 0 0\nxcodebuild_ipad 1 0\n")[0], 0)
        text = SCRIPT.read_text()
        self.assertIn('echo "xcodebuild_$family 1 0" >> "$FENTON_TALLY"', text)
        self.assertIn("--allow-empty --impact", (SCRIPT.parent / "apple_coverage.sh").read_text())

    def test_the_script_records_and_replays_skips(self):
        text = SCRIPT.read_text()
        self.assertIn('--result "$result"', text)
        self.assertIn('tally-ran "$FENTON_TALLY" "xcodebuild_$family"', text)
        self.assertIn("recorded_skipped", text)
        self.assertIn('echo "xcodebuild_$family 0 0" >> "$FENTON_TALLY"', text)

    def test_cli_record_and_result(self):
        tool = str(SCRIPT.parent / "affected_tests.py")
        out = lambda *a: subprocess.run([sys.executable, tool, *a, "--tree", "t9", "--device", "duo", "--filter", "x"], capture_output=True, text=True, cwd=self.root)
        self.assertEqual(out("result").stdout.strip(), "")


class EmptyRunTests(unittest.TestCase):
    """An empty run (nothing executed, or every test skipped) fails unless ``--allow-empty``."""

    def test_every_family_run_requires_tests_unless_allowed(self):
        text = SCRIPT.read_text()
        self.assertIn("local require=(--require-tests)", text)
        self.assertIn("[[ $ALLOW_EMPTY == 1 ]] && require=()", text)

    def test_the_flag_is_accepted_and_announced_for_the_digest(self):
        out = subprocess.run(["bash", str(SCRIPT), "--allow-empty", "--only", "iphone", "--full"],
                             env={**os.environ, "FENTON_UITEST_PRINT_FILTERS": "1"}, capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("allow-empty:", out.stdout)

    def test_navperf_and_coverage_carry_the_same_rule(self):
        tools = SCRIPT.parent
        navperf = (tools / "ios_navperf.sh").read_text()
        self.assertIn("--allow-empty", navperf)
        self.assertIn("EMPTY: $family produced no NAVPERF rows", navperf)
        coverage = (tools / "apple_coverage.sh").read_text()
        self.assertIn("REQUIRE=(--require-tests)", coverage)
        self.assertIn("FENTON_COV_ALLOW_EMPTY", coverage)


class MissingFamilySimulatorTests(unittest.TestCase):
    """A selected family whose simulator is not in the pool is a GAP with its own exit code, never a silent skip."""

    POOL = (
        "-- iOS 27.0 --\n"
        "    iPhone 17 Pro (11111111-1111-1111-1111-111111111111) (Shutdown) \n"
        "    iPad Pro 11-inch (M5) (22222222-2222-2222-2222-222222222222) (Shutdown) \n"
    )

    def run_with_pool(self, pool_text, *args, **env):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            pool = Path(tmp) / "pool.txt"
            pool.write_text(pool_text)
            run_env = {k: v for k, v in os.environ.items() if not k.startswith("FENTON_SIM_")}
            run_env.update({"FENTON_SIM_LIST_FILE": str(pool)})
            run_env.update(env)
            return subprocess.run(["bash", str(SCRIPT), "--force", "-only-testing:FentonHomeUITests/NoSuchClass", *args],
                                  env=run_env, capture_output=True, text=True)

    def test_a_pool_without_the_duo_reports_a_gap_and_exits_78(self):
        out = self.run_with_pool(self.POOL, "--only", "duo")
        self.assertEqual(out.returncode, 78, out.stdout + out.stderr)
        self.assertIn("GAP: duo simulator not in pool (iPhone Duo (HASS))", out.stdout)

    def test_the_duo_name_follows_the_override(self):
        out = self.run_with_pool(self.POOL, "--only", "duo", FENTON_SIM_DUO="Some Duo")
        self.assertEqual(out.returncode, 78)
        self.assertIn("GAP: duo simulator not in pool (Some Duo)", out.stdout)

    def test_only_the_selected_family_is_checked(self):
        out = self.run_with_pool("-- iOS 27.0 --\n", "--only", "ipad")
        self.assertEqual(out.returncode, 78)
        self.assertEqual(out.stdout.count("GAP:"), 1)
        self.assertIn("GAP: ipad simulator not in pool (iPad Pro 11-inch (M5))", out.stdout)

    HASS_POOL = (
        "-- iOS 27.0 --\n"
        "    iPhone Duo (HASS) (33333333-3333-3333-3333-333333333333) (Shutdown) \n"
        "    iPhone Duo (HASS) (pool 2) (44444444-4444-4444-4444-444444444444) (Shutdown) \n"
    )

    def test_a_bare_name_is_not_satisfied_by_a_longer_sibling_or_pool_clone(self):
        out = self.run_with_pool(self.HASS_POOL, "--only", "duo", FENTON_SIM_DUO="iPhone Duo")
        self.assertEqual(out.returncode, 78, out.stdout + out.stderr)
        self.assertIn("GAP: duo simulator not in pool (iPhone Duo)", out.stdout)

    def test_a_failing_simulator_list_is_an_error_not_a_gap(self):
        out = self.run_with_pool("", "--only", "duo", FENTON_SIM_LIST_FILE="/nonexistent/pool.txt")
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertNotIn("GAP:", out.stdout)
        self.assertIn("could not list the simulator pool", out.stderr)


class HostedModeSimulatorTests(unittest.TestCase):
    """FENTON_CI_HOSTED=1 names the xcode-27 image's simulators; unset, the local names stay."""

    def gaps(self, family, **extra):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            pool = Path(tmp) / "pool.txt"
            pool.write_text("-- iOS 27.0 --\n")
            run_env = {k: v for k, v in dict(os.environ).items() if not k.startswith(("FENTON_SIM_", "FENTON_CI_", "RUNNER_ENV"))}
            run_env.update({"FENTON_SIM_LIST_FILE": str(pool), **extra})
            return subprocess.run(["bash", str(SCRIPT), "--force", "-only-testing:FentonHomeUITests/NoSuchClass", "--only", family],
                                  env=run_env, capture_output=True, text=True)

    def test_hosted_defaults_are_the_image_devices(self):
        for family, name in (("iphone", "iPhone 17"), ("duo", "iPhone Duo"), ("ipad", "iPad Pro 11-inch (M5)")):
            out = self.gaps(family, FENTON_CI_HOSTED="1", RUNNER_ENVIRONMENT="github-hosted")
            self.assertEqual(out.returncode, 78, out.stdout + out.stderr)
            self.assertIn("GAP: %s simulator not in pool (%s)" % (family, name), out.stdout)

    def test_hosted_names_follow_the_override(self):
        out = self.gaps("iphone", FENTON_CI_HOSTED="1", RUNNER_ENVIRONMENT="github-hosted", FENTON_SIM_IPHONE="iPhone 18 Pro")
        self.assertIn("GAP: iphone simulator not in pool (iPhone 18 Pro)", out.stdout)

    def test_unset_keeps_the_local_names(self):
        self.assertIn("(iPhone 17 Pro)", self.gaps("iphone").stdout)
        self.assertIn("(iPhone Duo (HASS))", self.gaps("duo").stdout)
        self.assertIn("(iPhone 17 Pro)", self.gaps("iphone", FENTON_CI_HOSTED="0").stdout)

    def test_the_variable_alone_never_leaves_the_local_names_or_holds(self):
        """On a self-hosted runner (or a Mac) FENTON_CI_HOSTED=1 without RUNNER_ENVIRONMENT=github-hosted changes nothing."""
        self.assertIn("(iPhone 17 Pro)", self.gaps("iphone", FENTON_CI_HOSTED="1").stdout)
        self.assertIn("(iPhone 17 Pro)", self.gaps("iphone", FENTON_CI_HOSTED="1", RUNNER_ENVIRONMENT="self-hosted").stdout)
