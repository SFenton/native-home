"""Lints the hosted-CI rules in the workflow files (text only: no YAML library on the runner's system Python)."""

import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github" / "workflows"
MACOS_GUARD = "vars.HOSTED_MACOS == 'on'"


def jobs(name):
    """{job id: text} of one workflow file."""
    text = (WORKFLOWS / name).read_text(encoding="utf-8")
    body = text.split("\njobs:\n", 1)[1]
    parts = re.split(r"^  ([A-Za-z0-9_-]+):\n", body, flags=re.M)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}


def all_files():
    return sorted(WORKFLOWS.glob("*.yml"))


def runs_on(text):
    return re.search(r"^    runs-on: (.*)$", text, re.M).group(1)


def is_hosted_macos(label):
    """A job on a GitHub-hosted Mac image (xcode-*, macos-*), not a self-hosted runner."""
    return "self-hosted" not in label and re.search(r"xcode-|macos-", label, re.I) is not None


class RuleTests(unittest.TestCase):
    def test_every_action_is_pinned_by_sha(self):
        for path in all_files():
            for line in path.read_text(encoding="utf-8").splitlines():
                found = re.search(r"\buses:\s*(\S+)", line)
                if found and not found.group(1).startswith("./"):
                    self.assertRegex(found.group(1), r"@[0-9a-f]{40}$", "%s: %s" % (path.name, line.strip()))

    def test_no_privileged_triggers(self):
        for path in all_files():
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("pull_request_target", text.replace("never `pull_request_target`", ""), path.name)
            self.assertNotIn("issue_comment:", text, path.name)

    def test_every_hosted_macos_job_is_behind_the_hosted_macos_variable(self):
        """No visibility check (empty on `schedule`): the repository variable, unset by default, in every workflow and trigger."""
        found = 0
        for path in all_files():
            for job, text in jobs(path.name).items():
                if not is_hosted_macos(runs_on(text)):
                    continue
                found += 1
                condition = re.search(r"^    if: (.*)$", text, re.M)
                self.assertIsNotNone(condition, "%s/%s is a hosted Mac job without an if:" % (path.name, job))
                self.assertIn(MACOS_GUARD, condition.group(1), "%s/%s lacks the HOSTED_MACOS guard" % (path.name, job))
                self.assertNotIn("repository.private", condition.group(1), "%s/%s keys a Mac job on visibility" % (path.name, job))
        self.assertEqual(found, 3)  # macos, build-release, runtimes smoke

    def test_the_runner_label_variable_is_validated(self):
        for path in all_files():
            for job, text in jobs(path.name).items():
                if "vars.HOSTED_XCODE_LABEL" in runs_on(text):
                    self.assertIn("startsWith(vars.HOSTED_XCODE_LABEL, 'xcode-')", runs_on(text), "%s/%s" % (path.name, job))
                    self.assertIn("'xcode-27'", runs_on(text))

    def test_no_pr_or_main_job_runs_on_a_self_hosted_runner(self):
        for name in ("pr-checks.yml",):
            for job, text in jobs(name).items():
                self.assertNotIn("self-hosted", runs_on(text), "%s/%s" % (name, job))
                self.assertNotIn("repository.private", text, "%s/%s" % (name, job))

    def test_the_aggregate_keeps_its_name_and_covers_the_jobs(self):
        text = jobs("pr-checks.yml")["pr-checks"]
        self.assertIn("if: always()", text)
        for needed in ("scope", "linux-checks", "tool-tests-core", "denylist-scan", "macos", "build-release"):
            self.assertRegex(text, r"[\[ ,]%s[,\]\s]" % re.escape(needed))
        self.assertTrue((WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8").startswith("name: pr-checks\n"))
        self.assertIn("toJSON(needs)", text)
        self.assertIn("python3 tools/ci_aggregate.py", text)
        self.assertNotIn("success|skipped", text)

    def test_python_tool_test_jobs_leave_hosted_mode_off_and_compare_against_the_base(self):
        for job in ("linux-checks", "tool-tests-core"):
            self.assertNotIn("FENTON_CI_HOSTED", jobs("pr-checks.yml")[job], job)
            self.assertIn("tools/ci_new_failures.py --base", jobs("pr-checks.yml")[job])

    def test_hosted_macos_jobs_use_the_hosted_mode_and_no_devcap(self):
        for job in ("macos", "build-release"):
            text = jobs("pr-checks.yml")[job]
            self.assertIn('FENTON_CI_HOSTED: "1"', text, job)
            self.assertNotIn("devcap", text, job)
            self.assertNotIn("self-hosted", text, job)

    def test_caches_save_from_main_only_and_key_on_package_resolved_and_the_selected_xcode(self):
        text = (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8")
        for block in re.findall(r"actions/cache/(?:save|restore)@.*?(?=\n      - |\n\n)", text, flags=re.S):
            self.assertIn("hashFiles('apple/Package.resolved')", block)
            self.assertIn("steps.xcode.outputs.version", block)
        for step in re.findall(r"- name: Save [^\n]*\n\s+if: ([^\n]*)", text):
            self.assertIn("github.ref == 'refs/heads/main'", step)
        self.assertNotIn("actions/cache@", text)
        self.assertNotIn("xcode27.1", text)

    def test_denylist_job_prints_counts_only_masks_terms_and_is_lenient_until_strict(self):
        text = jobs("pr-checks.yml")["denylist-scan"]
        self.assertIn("head.repo.full_name == github.repository", text)
        self.assertIn("umask 077", text)
        self.assertIn("denylist not available (fork PR or secret unset); the local pr_land check covers it", text)
        self.assertIn("tools/ci_denylist.py mask", text)
        self.assertIn("tools/house_scan.py denylist", text)
        self.assertIn("--base-ref", text)
        self.assertIn("vars.DENYLIST_STRICT", text)
        self.assertIn("TODO: fail on any hit once go_public_gate passes", text)
        self.assertRegex(text, r"Delete the denylist file\n\s+if: always\(\)")
        self.assertNotRegex(text, r"\bcat\b|echo \"?\$DENYLIST")

    def test_tool_tests_live_in_pr_checks_and_only_the_report_job_may_write_issues(self):
        self.assertFalse((WORKFLOWS / "tool-tests.yml").exists())
        text = (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8")
        self.assertRegex(text.split("\njobs:\n", 1)[0], r"permissions:\n  contents: read\n(?!  issues)")
        for job, body in jobs("pr-checks.yml").items():
            if job == "report-red-main":
                self.assertIn("issues: write", body)
            else:
                self.assertNotIn("issues:", body, job)

    def test_the_red_run_report_is_main_and_manual_only_with_a_dry_run(self):
        body = jobs("pr-checks.yml")["report-red-main"]
        condition = re.search(r"^    if: (.*)$", body, re.M).group(1)
        self.assertIn("github.event_name == 'push'", condition)
        self.assertIn("github.event_name == 'workflow_dispatch'", condition)
        self.assertNotIn("pull_request", condition)
        self.assertIn("inputs.report_dry_run", condition)
        self.assertIn('if [ "$DRY_RUN" = "true" ]', body)
        self.assertLess(body.index('"$DRY_RUN" = "true"'), body.index("gh issue create"))
        self.assertNotIn("report-red-main", jobs("pr-checks.yml")["pr-checks"].split("steps:")[0])

    def test_linux_checks_merge_the_small_jobs_and_core_stays_apart(self):
        text = jobs("pr-checks.yml")
        self.assertIn("tools/run_tool_tests.sh", text["linux-checks"])
        self.assertIn("PART: triage", text["linux-checks"])
        self.assertIn("PART: release", text["linux-checks"])
        self.assertNotIn("PART: core", text["linux-checks"])
        self.assertIn("PART: core", text["tool-tests-core"])
        self.assertNotIn("matrix", text["linux-checks"] + text["tool-tests-core"])

    def test_self_hosted_jobs_never_trigger_on_pull_requests_without_the_private_gate(self):
        for name in ("nightly.yml", "ios-release.yml", "ios-release-build.yml"):
            text = (WORKFLOWS / name).read_text(encoding="utf-8")
            self.assertNotIn("pull_request", text.split("\njobs:\n", 1)[0].replace("pull_request_target", ""), name)

    def test_permissions_are_read_only_at_the_top(self):
        for name in ("pr-checks.yml", "runtimes.yml"):
            self.assertRegex((WORKFLOWS / name).read_text(encoding="utf-8"), r"\npermissions:\n  contents: read\n")

    def test_the_macos_job_builds_before_any_simulator_boots_and_runs_swift_test_last(self):
        text = jobs("pr-checks.yml")["macos"]
        build = text.index("tools/ci_macos.sh build")
        smoke = text.index("tools/ci_macos.sh smoke iphone")
        swift = text.index("tools/ci_macos.sh swift-test")
        self.assertLess(build, smoke)
        self.assertLess(smoke, swift)
        self.assertNotIn("simctl boot", text)  # no simulator boots outside sim_settle.sh, after the build
        script = (Path(__file__).resolve().parents[1] / "ci_macos.sh").read_text(encoding="utf-8")
        self.assertLess(script.index("--build-only"), script.index("$SETTLE"))
        self.assertIn("timeout-minutes:", text)

    def test_smoke_is_advisory_and_the_build_and_swift_test_are_required(self):
        text = jobs("pr-checks.yml")["macos"]
        steps = re.split(r"\n      - ", text)
        by_name = {s.split("\n", 1)[0]: s for s in steps if s.startswith("name: ")}
        for name, body in by_name.items():
            advisory = name.startswith(("name: Smoke on", "name: Journeys the diff"))
            self.assertEqual("continue-on-error: true" in body, advisory or name == "name: Simulator diagnostics", name)
        self.assertIn("name: Build the test products", by_name)
        self.assertIn("name: swift test", by_name)
        self.assertNotIn("affected_tests.py --swift", (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8"))

    def test_the_smoke_layout_input_picks_sequential_or_parallel_slim_with_sequential_the_default(self):
        text = (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8")
        self.assertRegex(text, r"smoke_layout:\n(?:.*\n)*?        options: \[sequential, parallel-slim\]\n        default: sequential")
        macos = jobs("pr-checks.yml")["macos"]
        self.assertIn("FENTON_INSTALL_SIMSLIM: ${{ inputs.smoke_layout == 'parallel-slim' && '1' || '0' }}", macos)
        self.assertIn("tools/ci_macos.sh smoke all", macos)
        for family in ("iphone", "duo", "ipad"):
            self.assertIn("name: xcresult-%s" % family, macos)
        setup = (Path(__file__).resolve().parents[1] / "ci_hosted_setup.sh").read_text(encoding="utf-8")
        self.assertIn("simslim-v0.14.0-macos-arm64.tar.gz", setup)
        self.assertRegex(setup, r'SIMSLIM_SHA256="[0-9a-f]{64}"')
        self.assertIn("shasum -a 256 -c", setup)
        self.assertIn("--parallel-families", (Path(__file__).resolve().parents[1] / "ci_macos.sh").read_text(encoding="utf-8"))

    def test_the_release_build_runs_on_a_push_to_main_only(self):
        text = jobs("pr-checks.yml")["build-release"]
        self.assertIn("github.event_name == 'push'", re.search(r"^    if: (.*)$", text, re.M).group(1))

    def test_the_macos_job_hosted_build_settings_come_from_the_workflow_env_only(self):
        text = jobs("pr-checks.yml")["macos"]
        self.assertIn('FENTON_HOSTED_BUILD_SETTINGS: "ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO"', text)
        self.assertIn("sudo mdutil -a -i off || true", text)
        script = (Path(__file__).resolve().parents[1] / "ios_uitest.sh").read_text(encoding="utf-8")
        self.assertIn("$CI_HOSTED == 1 && -n \"${FENTON_HOSTED_BUILD_SETTINGS:-}\"", script)
        self.assertNotIn("ARCHS=arm64", script)


class ScopeFilterTests(unittest.TestCase):
    """The `scope` job selects jobs with dorny/paths-filter (pinned by SHA); tools/ci_scope.py is gone."""

    def text(self):
        return jobs("pr-checks.yml")["scope"]

    def test_the_filter_is_pinned_and_the_old_script_is_gone(self):
        self.assertRegex(self.text(), r"uses: dorny/paths-filter@[0-9a-f]{40} # v\d+\.\d+\.\d+")
        self.assertFalse((WORKFLOWS.parents[1] / "tools" / "ci_scope.py").exists())
        self.assertNotIn("ci_scope", (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8"))

    def test_only_the_scope_job_may_read_pull_requests(self):
        self.assertIn("pull-requests: read", self.text())
        for job, text in jobs("pr-checks.yml").items():
            if job != "scope":
                self.assertNotIn("pull-requests", text, job)

    def test_the_ios_driving_tools_count_as_app(self):
        pattern = re.search(r"app_tools: '(\{[^']*\})'", self.text()).group(1)
        for needed in ("tools/ios_uitest.sh", "tools/affected_tests.py", "tools/sim_*.sh", "tools/simslim/**", "tools/ci_hosted*",
                       "tools/products_cache.py", "tools/xc_watch.py", "tools/ci_macos.sh"):
            self.assertIn(needed, pattern)
        script = (WORKFLOWS.parents[1] / "tools" / "ios_uitest.sh").read_text(encoding="utf-8")
        for called in ("products_cache.py", "xc_watch.py", "affected_tests.py", "test_suites.py", "uitest_support.py", "lane_base.py"):
            self.assertIn(called, script)
            self.assertIn(called, pattern)

    def test_docs_and_tools_do_not_count_and_a_push_to_main_runs_everything(self):
        text = self.text()
        for negation in ("!**/*.md", "!.agents/**", "!tools/**", "!contracts/test-map*"):
            self.assertIn(negation, text)
        self.assertIn("steps.filter.outcome == 'skipped' && 'true'", text)
        self.assertIn("predicate-quantifier: every", text)

    def test_the_manual_run_can_test_the_filter_on_given_commits(self):
        text = (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8")
        self.assertIn("scope_base:", text)
        self.assertIn("scope_head:", text)
        self.assertIn("base: ${{ inputs.scope_base }}", text)


if __name__ == "__main__":
    unittest.main()
