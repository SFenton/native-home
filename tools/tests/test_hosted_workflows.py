"""Lints the hosted-CI rules in the workflow files (text only: no YAML library on the runner's system Python)."""

import fnmatch
import hashlib
import http.server
import importlib.util
import io
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import textwrap
import threading
import unittest
import zipfile
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github" / "workflows"
MACOS_GUARD = "vars.HOSTED_MACOS == 'on'"


def jobs(name):
    """{job id: text} of one workflow file."""
    text = (WORKFLOWS / name).read_text(encoding="utf-8")
    body = text.split("\njobs:\n", 1)[1]
    parts = re.split(r"^  ([A-Za-z0-9_-]+):\n", body, flags=re.M)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}


def needs_list(text):
    """The names in a job's own `needs:` key, comments stripped (a comment naming a job must not count)."""
    code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    match = re.search(r"^    needs:\s*(\[[^\]]*\]|\S+)", code, flags=re.M)
    return [n.strip() for n in match.group(1).strip("[]").split(",")] if match else []


def executable(text):
    """Executable YAML text: comment-only lines never satisfy a wiring proof."""
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


def step_blocks(text):
    """The workflow's executable `steps:` entries, without a YAML dependency."""
    code = executable(text)
    body = code.split("\n    steps:\n", 1)[1] if "\n    steps:\n" in code else ""
    starts = list(re.finditer(r"(?m)^      - (?:name:|uses:|id:)", body))
    return [
        body[match.start():starts[index + 1].start() if index + 1 < len(starts) else len(body)]
        for index, match in enumerate(starts)
    ]


def named_step(text, name):
    return next(
        (block for block in step_blocks(text)
         if re.search(r"(?m)^      - name: %s$" % re.escape(name), block)),
        "",
    )


def inline_python(text, step_name):
    """One heredoc body from a named workflow step, after YAML block indentation."""
    block = named_step(text, step_name)
    match = re.search(
        r"(?m)^          python3 -B -[^\n]*<<'PY'\n(.*?)^          PY$",
        block,
        flags=re.S,
    )
    if match is None:
        raise AssertionError("missing inline Python in %s" % step_name)
    return textwrap.dedent(match.group(1))


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
        self.assertEqual(found, 11)  # macos-build, macos-test, coverage-changed, build-release, runtimes smoke, ios-release ipa, nightly build, journeys, hosted, coverage and live

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
        for needed in ("scope", "linux-checks", "tool-tests-core", "denylist-scan", "macos-build", "macos-test", "coverage-changed", "build-release"):
            self.assertRegex(text, r"[\[ ,]%s[,\]\s]" % re.escape(needed))
        self.assertTrue((WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8").startswith("name: pr-checks\n"))
        self.assertIn("toJSON(needs)", text)
        self.assertRegex(text, r"python3 (?:-B )?tools/ci_aggregate\.py")
        self.assertNotIn("success|skipped", text)

    def test_python_tool_test_jobs_leave_hosted_mode_off_and_compare_against_the_base(self):
        for job in ("linux-checks", "tool-tests-core"):
            self.assertNotIn("FENTON_CI_HOSTED", jobs("pr-checks.yml")[job], job)
            self.assertIn("tools/ci_new_failures.py --base", jobs("pr-checks.yml")[job])

    def test_hosted_macos_jobs_use_the_hosted_mode_and_no_devcap(self):
        for job in ("macos-build", "macos-test", "coverage-changed", "build-release"):
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
            if job in ("report-red-main", "close-red-main"):
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
        self.assertNotIn("matrix", text["linux-checks"])

    def test_the_core_tool_tests_run_in_four_shards_that_all_report(self):
        core = jobs("pr-checks.yml")["tool-tests-core"]
        self.assertIn("fail-fast: false", core)
        self.assertRegex(core, r"shard: \[0, 1, 2, 3\]")
        self.assertIn("FENTON_TOOL_SHARD: ${{ matrix.shard }}/4", core)
        self.assertIn("name: Tool tests (core ${{ matrix.shard }}/4)", core)
        self.assertIn("name: tool-tests-log-core-${{ matrix.shard }}", core)  # one artifact per shard (report-red-main reads tool-tests-log-*)

    def test_the_core_tool_tests_always_run(self):
        """Fails if: tool-tests-core gains an `if:` or the scope grows a core_tests output (some core tests read live apple/ files)."""
        core = jobs("pr-checks.yml")["tool-tests-core"]
        self.assertIsNone(re.search(r"^    if: ", core, re.M))
        self.assertNotIn("core_tests", (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8"))

    def test_self_hosted_jobs_never_trigger_on_pull_requests_without_the_private_gate(self):
        for name in ("nightly.yml", "ios-release.yml"):
            text = (WORKFLOWS / name).read_text(encoding="utf-8")
            self.assertNotIn("pull_request", text.split("\njobs:\n", 1)[0].replace("pull_request_target", ""), name)

    def test_permissions_are_read_only_at_the_top(self):
        for name in ("pr-checks.yml", "runtimes.yml"):
            self.assertRegex((WORKFLOWS / name).read_text(encoding="utf-8"), r"\npermissions:\n  contents: read\n")

    def test_the_products_are_built_once_and_every_family_tests_from_them(self):
        build = jobs("pr-checks.yml")["macos-build"]
        test = jobs("pr-checks.yml")["macos-test"]
        self.assertIn("tools/ci_macos.sh build", build)
        self.assertNotIn("tools/ci_macos.sh smoke", build)
        self.assertNotIn("simctl boot", build + test)  # no simulator boots outside sim_settle.sh, after the build
        script = (Path(__file__).resolve().parents[1] / "ci_macos.sh").read_text(encoding="utf-8")
        self.assertLess(script.index("--build-only"), script.index("$SETTLE"))
        self.assertIn("timeout-minutes:", build)
        self.assertIn("timeout-minutes:", test)
        # build -> pack -> upload (1 day) in one job; download -> unpack -> proven hit -> Smoke in the other
        self.assertLess(build.index("tools/ci_macos.sh build"), build.index("name: Upload the test products"))
        self.assertIn("name: macos-test-products", build)
        self.assertIn("retention-days: 1", build)
        self.assertIn("if-no-files-found: error", build)
        self.assertIn("artifact-ids: ${{ needs.macos-build.outputs.artifact-id }}", test)
        order = [test.index(text) for text in ("name: Download the test products", "name: Unpack the test products",
                                               "name: Reuse the built products", "tools/ci_macos.sh smoke")]
        self.assertEqual(order, sorted(order))
        self.assertIn("grep -q '^products: hit '", test)  # a key mismatch fails loudly instead of rebuilding
        self.assertIn("needs: [scope, macos-build]", test)

    def test_the_test_matrix_covers_the_three_families_and_every_report_survives(self):
        test = jobs("pr-checks.yml")["macos-test"]
        self.assertIn("fail-fast: false", test)
        self.assertRegex(test, r"family: \[iphone, duo, ipad\]")
        self.assertIn("name: macOS - Smoke ${{ matrix.family }}", test)
        self.assertIn("tools/ci_macos.sh smoke ${{ matrix.family }}", test)
        self.assertIn("tools/ci_macos.sh journeys ${{ matrix.family }}", test)
        self.assertIn("github.event_name == 'pull_request'", test.split("name: Journeys the diff reaches", 1)[1].split("run:", 1)[0])
        self.assertIn("name: xcresult-${{ matrix.family }}", test)
        self.assertIn("apple/.build/uitest-${{ matrix.family }}.xcresult/**", test)
        self.assertIn("include-hidden-files: true", test)

    def test_the_hosted_unit_tests_run_on_iphone_only_after_the_journeys_and_fail_the_job(self):
        test = jobs("pr-checks.yml")["macos-test"]
        step = test.split("name: Hosted tests the diff reaches on iphone", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("id: hosted", step)
        self.assertIn("tools/ci_macos.sh hosted iphone", step)
        condition = step.split("if: ", 1)[1].split("\n", 1)[0]
        for part in ("!cancelled()", "github.event_name == 'pull_request'", "matrix.family == 'iphone'"):
            self.assertIn(part, condition)
        timeout = int(re.search(r"timeout-minutes: (\d+)", step).group(1))
        job = int(re.search(r"timeout-minutes: (\d+)", test).group(1))
        self.assertGreaterEqual(timeout, 60)  # the whole suite fits
        self.assertGreater(job, timeout + 30)  # and Smoke and the journeys still fit in front of it
        self.assertNotIn("continue-on-error", step)  # a failed hosted step fails the job, as Smoke and the journeys do
        self.assertLess(test.index("tools/ci_macos.sh journeys"), test.index("tools/ci_macos.sh hosted iphone"))
        self.assertLess(test.index("tools/ci_macos.sh hosted iphone"), test.index("tools/ci_macos.sh swift-test"))
        self.assertEqual(test.count("steps.hosted.outcome == 'failure'"), 2)  # the diagnostics and the kept results follow a failed hosted step
        self.assertIn("uitest-${{ matrix.family }}-journeys.xcresult/**", test)  # the hosted run replaces the journeys' own bundle: both are kept
        self.assertNotIn("hosted iphone", jobs("pr-checks.yml")["macos-build"])

    def test_the_duo_leg_runs_the_tagged_hosted_classes_after_the_journeys_and_fails_the_job(self):
        test = jobs("pr-checks.yml")["macos-test"]
        step = test.split("name: Hosted fold tests the diff reaches on duo", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("id: hostedduo", step)
        self.assertIn("tools/ci_macos.sh hosted duo", step)
        condition = step.split("if: ", 1)[1].split("\n", 1)[0]
        for part in ("!cancelled()", "github.event_name == 'pull_request'", "matrix.family == 'duo'"):
            self.assertIn(part, condition)
        self.assertNotIn("continue-on-error", step)
        self.assertLess(test.index("tools/ci_macos.sh journeys"), test.index("tools/ci_macos.sh hosted duo"))
        self.assertLess(test.index("tools/ci_macos.sh hosted duo"), test.index("tools/ci_macos.sh swift-test"))
        self.assertEqual(test.count("steps.hostedduo.outcome == 'failure'"), 2)  # the diagnostics and the kept results follow it too

    def test_the_nightly_hosted_job_has_a_duo_leg_for_the_tagged_classes_and_reports_it(self):
        text = (Path(__file__).resolve().parents[2] / ".github" / "workflows" / "nightly.yml").read_text(encoding="utf-8")
        hosted = text.split("\n  hosted:\n", 1)[1].split("\n  live:\n", 1)[0]
        self.assertIn("tools/affected_tests.py --tagged duo", hosted)
        self.assertIn("tools/ios_uitest.sh --only duo --hosted --force", hosted)
        self.assertIn("--area hosted-duo", hosted)
        self.assertIn('expect="$expect,hosted-duo=1"', text)  # the report expects the Duo result as well
        self.assertIn("steps.runduo.outputs.code != '0'", hosted.split("Fail the hosted run", 1)[1])
        self.assertLess(hosted.index("--only iphone --hosted"), hosted.index("--only duo --hosted"))
        for step in ("Slim and settle the duo simulator", "Run the Duo hosted classes"):
            condition = hosted.split(step, 1)[1].split("if: ", 1)[1].split("\n", 1)[0]
            self.assertIn("steps.products.outcome == 'success'", condition)  # no Duo run after the products failed to load
        self.assertIn("id: products", hosted.split("Reuse the built products", 1)[1].split("- name:", 1)[0])
        self.assertIn("tools/ci_release_sims.sh", hosted.split("Slim and settle the duo simulator", 1)[1].split("- name:", 1)[0])  # one device at a time

    def test_the_scope_filter_watches_every_file_that_decides_hosted_selection(self):
        text = (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8")
        app_tools = re.search(r"app_tools: '\{(.*?)\}'", text).group(1).split(",")
        for path in ("tools/affected_tests.py", "tools/ios_uitest.sh", "tools/ci_macos.sh", "tools/uitest_support.py", "contracts/test-map*"):
            self.assertIn(path, app_tools)

    def test_swift_test_rides_the_ipad_leg_and_the_spm_cache_follows_it(self):
        test = jobs("pr-checks.yml")["macos-test"]
        self.assertEqual(test.count("tools/ci_macos.sh swift-test"), 1)
        self.assertIn("matrix.family == 'ipad'", test.split("name: swift test", 1)[1].split("run:", 1)[0])
        self.assertLess(test.index("tools/ci_macos.sh smoke"), test.index("tools/ci_macos.sh swift-test"))
        self.assertNotIn("swift-test", jobs("pr-checks.yml")["macos-build"])

    def test_every_macos_step_is_required_except_the_diagnostics(self):
        for job in ("macos-build", "macos-test"):
            text = jobs("pr-checks.yml")[job]
            steps = re.split(r"\n      - ", text)
            by_name = {s.split("\n", 1)[0]: s for s in steps if s.startswith("name: ")}
            for name, body in by_name.items():
                self.assertEqual("continue-on-error: true" in body, name == "name: Simulator diagnostics", "%s %s" % (job, name))
            head = text.split("    steps:\n", 1)[0]
            self.assertNotRegex(head, r"(?m)^    continue-on-error:")
        self.assertIn("name: Build the test products", jobs("pr-checks.yml")["macos-build"])
        self.assertIn("name: swift test", jobs("pr-checks.yml")["macos-test"])
        self.assertNotIn("affected_tests.py --swift", (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8"))

    def test_each_device_runs_slimmed_on_its_own_runner(self):
        text = (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8")
        for gone in ("smoke_layout", "parallel-slim", "FENTON_REQUIRE_SIMSLIM", "scope_base", "scope_head"):
            self.assertNotIn(gone, text)
        test = jobs("pr-checks.yml")["macos-test"]
        self.assertIn('FENTON_INSTALL_SIMSLIM: "1"', test)
        self.assertNotIn("FENTON_INSTALL_SIMSLIM", jobs("pr-checks.yml")["macos-build"])  # the build boots nothing
        self.assertIn("FENTON_HEALTH_BOOT_WALL", test)
        setup = (Path(__file__).resolve().parents[1] / "ci_hosted_setup.sh").read_text(encoding="utf-8")
        self.assertIn("simslim-v0.14.0-macos-arm64.tar.gz", setup)
        self.assertIn("shasum -a 256 -c", setup)
        self.assertIn("install-simslim", setup)
        smoke = (Path(__file__).resolve().parents[1] / "ci_macos.sh").read_text(encoding="utf-8")
        self.assertIn('"$HEARTBEAT" run -- "$SETTLE" "$target"', smoke)  # the Duo settle (#25) runs before every family's Smoke
        self.assertIn('"$HEARTBEAT" run -- "$SLIM" "$target"', smoke)

    def test_only_the_macos_test_job_installs_simslim(self):
        text = (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8")
        self.assertEqual(text.count("FENTON_INSTALL_SIMSLIM"), 1)  # macos-test; coverage-changed is host-only and boots no simulator

    def test_manual_runs_with_different_dry_run_flags_do_not_cancel_each_other(self):
        text = (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8")
        group = re.search(r"^  group: (.*)$", text, re.M).group(1)
        self.assertIn("inputs.report_dry_run", group)

    def test_main_runs_key_on_the_sha_and_never_cancel_while_pull_requests_do(self):
        text = (WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8")
        group = re.search(r"^  group: (.*)$", text, re.M).group(1)
        self.assertIn("github.event_name == 'push' && github.sha", group)
        self.assertIn("github.event.pull_request.number", group)
        cancel = re.search(r"^  cancel-in-progress: (.*)$", text, re.M).group(1)
        self.assertIn("github.event_name != 'push'", cancel)

    def test_swift_test_runs_the_full_suite_when_a_pr_touches_core_or_design(self):
        scope = jobs("pr-checks.yml")["scope"]
        for path in ("apple/Sources/HassCore/**", "apple/Sources/HassDesign/**", "apple/Tests/HassCoreTests/**", "apple/Tests/HassDesignTests/**"):
            self.assertIn(path, scope)
        self.assertIn("swift_full: ${{ steps.filter.outcome == 'skipped' && 'true' || steps.filter.outputs.swift_full }}", scope)
        step = jobs("pr-checks.yml")["macos-test"].split("name: swift test", 1)[1].split("run:", 1)[0]
        # An empty base makes ci_macos.sh run everything; '' is falsy in an expression, so it must be the `||` fallback, never an `&& ''` arm.
        self.assertIn("github.event_name == 'pull_request' && needs.scope.outputs.swift_full != 'true' && format('origin/{0}', github.base_ref) || ''", step)
        self.assertIn("FENTON_AFFECTED_BASE", step)

    def test_no_workflow_uses_the_falsy_empty_string_and_or_pattern(self):
        """`cond && '' || other` always yields `other` (an empty string is falsy), the bug that kept swift_full from ever running the full suite."""
        for path in all_files():
            self.assertNotRegex(path.read_text(encoding="utf-8"), r"&&\s*''\s*\|\|", path.name)

    def test_the_red_main_closer_fails_closed(self):
        body = jobs("pr-checks.yml")["close-red-main"]
        self.assertIn("ahead | identical)", body)
        self.assertNotIn('ahead | identical | ""', body)
        self.assertIn('*"HTTP 404"*', body)
        self.assertIn("left open", body)

    def test_the_changed_file_coverage_job_gates_pull_requests_and_fits_the_macos_cap(self):
        job = jobs("pr-checks.yml")["coverage-changed"]
        self.assertIn("tools/apple_coverage.sh --changed", job)
        self.assertIn('FENTON_CI_HOSTED: "1"', job)
        self.assertIn("needs: scope\n", job)  # starts beside macos-build: 2, then 4 runners, under the 5-concurrent cap
        cond = re.search(r"^    if: (.*)$", job, re.M).group(1)
        self.assertIn("github.event_name == 'pull_request'", cond)
        self.assertIn("needs.scope.outputs.app == 'true'", cond)
        self.assertNotIn("continue-on-error", job)
        self.assertNotIn("FENTON_INSTALL_SIMSLIM", job)  # host-only: no simulator
        self.assertIn("coverage-changed", jobs("pr-checks.yml")["pr-checks"].split("steps:")[0])

    def test_a_green_main_closes_the_red_main_issue(self):
        body = jobs("pr-checks.yml")["close-red-main"]
        cond = re.search(r"^    if: (.*)$", body, re.M).group(1)
        self.assertIn("github.event_name == 'push'", cond)
        self.assertIn("needs.pr-checks.result == 'success'", cond)
        self.assertIn('title="Tool tests red on ${BRANCH}"', body)
        self.assertIn("gh issue close", body)
        self.assertIn("RUN_URL", body)
        self.assertIn("needs: [pr-checks]", body)
        report = jobs("pr-checks.yml")["report-red-main"]
        self.assertIn('title="Tool tests red on ${BRANCH}"', report)  # the two jobs agree on the title

    def test_the_red_run_report_files_only_from_a_push_to_main(self):
        text = jobs("pr-checks.yml")["report-red-main"]
        cond = re.search(r"^    if: (.*)$", text, re.M).group(1)
        self.assertIn("github.event_name == 'push' && contains(needs.*.result, 'failure')", cond)
        self.assertIn("github.event_name == 'workflow_dispatch' && inputs.report_dry_run", cond)
        self.assertIn("DRY_RUN: ${{ github.event_name != 'push' && 'true' || 'false' }}", text)

    def test_the_release_build_runs_on_a_push_to_main_only(self):
        text = jobs("pr-checks.yml")["build-release"]
        self.assertIn("github.event_name == 'push'", re.search(r"^    if: (.*)$", text, re.M).group(1))

    def test_the_macos_jobs_hosted_build_settings_come_from_the_workflow_env_only_and_match(self):
        for job in ("macos-build", "macos-test"):  # a mismatch changes the products key: the test job would not find the build's bundle
            text = jobs("pr-checks.yml")[job]
            self.assertIn('FENTON_HOSTED_BUILD_SETTINGS: "ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO"', text, job)
            self.assertIn("sudo mdutil -a -i off || true", text, job)
            self.assertIn("FENTON_PRODUCTS_DIR=$RUNNER_TEMP/products", text, job)
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
                       "tools/products_cache.py", "tools/xc_watch.py", "tools/ci_macos.sh", "tools/ci_release_sims.sh"):
            self.assertIn(needed, pattern)
        macos = (WORKFLOWS.parents[1] / "tools" / "ci_macos.sh").read_text(encoding="utf-8")
        for tool in sorted(set(re.findall(r"\$ROOT/(tools/[A-Za-z0-9_./-]+\.(?:sh|py))", macos))):
            self.assertTrue((WORKFLOWS.parents[1] / tool).exists(), tool)
            self.assertTrue(any(fnmatch.fnmatchcase(tool, glob) for glob in pattern.strip("{}").split(",")),
                            "%s is called by ci_macos.sh but missing from app_tools" % tool)
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


class MergeGateTests(unittest.TestCase):
    def test_the_aggregate_fails_a_pull_request_not_from_sfenton_or_an_agent_login_in_this_repository(self):
        text = jobs("pr-checks.yml")["pr-checks"]
        step = text.split("- name: Author check", 1)[1].split("- name: Aggregate", 1)[0]
        self.assertIn("github.event_name == 'pull_request'", step)
        self.assertIn("github.event.pull_request.user.login", step)
        self.assertIn("github.event.pull_request.head.repo.full_name", step)
        self.assertIn("github.repository", step)
        self.assertIn("AGENT_LOGINS: ${{ vars.AGENT_LOGINS }}", step)
        self.assertIn('",${AGENT_LOGINS// /},SFenton,"', step)
        self.assertIn('*",$AUTHOR,"*) ;;', step)
        self.assertIn('"$HEAD_REPO" != "$THIS_REPO"', step)
        self.assertIn("exit 1", step)
        aggregate_steps = text.split("- name: Aggregate", 1)[1]
        self.assertIn("if: ${{ !cancelled() && github.event_name == 'pull_request' }}", aggregate_steps)
        self.assertIn("if: ${{ !cancelled() && github.event_name != 'pull_request' }}", aggregate_steps)


if __name__ == "__main__":
    unittest.main()


class NeedsListTests(unittest.TestCase):
    def test_the_aggregate_lists_the_macos_job_and_the_list_parser_ignores_comments(self):
        self.assertEqual(needs_list("    # needs: [sim-smoke]\n    needs: [a, b]\n"), ["a", "b"])
        listed = needs_list(jobs("pr-checks.yml")["pr-checks"])
        for needed in ("macos-build", "macos-test", "build-release", "linux-checks", "tool-tests-core"):
            self.assertIn(needed, listed)


class PullRequestPolicyWiringTests(unittest.TestCase):
    @staticmethod
    def problems(parsed):
        found = []
        emit = parsed.get("tier0-emit", "")
        policy = parsed.get("pr-policy", "")
        aggregate = parsed.get("pr-checks", "")
        if not emit:
            return ["job:tier0-emit"]
        if not re.search(r"(?m)^    if: .*github\.event_name == 'pull_request'", executable(emit)):
            found.append("job:tier0-emit:event")
        if "outputs:" in executable(emit) or "GITHUB_OUTPUT" in executable(emit):
            found.append("job:tier0-emit:no-output")
        if "permissions:\n      contents: read" not in executable(emit) or "secrets." in emit:
            found.append("job:tier0-emit:credentials")
        for name, ref in (
            ("Check out the event base", "${{ github.event.pull_request.base.sha }}"),
            ("Check out the event head", "${{ github.event.pull_request.head.sha }}"),
        ):
            step = named_step(emit, name)
            if not step or "ref: %s" % ref not in step or "fetch-depth: 0" not in step or \
                    "persist-credentials: false" not in step:
                found.append("checkout:tier0-emit:%s" % name.split()[-1])
        isolate = named_step(emit, "Collect tier-0 observations in isolation")
        for value, boundary in (
            ("sudo install -d -m 755", "isolation:input-copy"),
            ('sudo cp -a "$GITHUB_WORKSPACE/policy-base/." "$sandbox/base/"',
             "isolation:input-copy"),
            ('sudo cp -a "$GITHUB_WORKSPACE/policy-head/." "$sandbox/head/"',
             "isolation:input-copy"),
            ("sudo chown -R 65534:65534", "isolation:input-owner"),
            ("sudo env -i PATH=/usr/bin:/bin HOME=/tmp LANG=C", "isolation:outer-environment"),
            ("unshare --mount --pid --fork --net --mount-proc", "isolation:namespaces"),
            ('bash -s -- "$sandbox/base" "$sandbox/head" "$RUNNER_TEMP"',
             "isolation:staged-inputs"),
            ("mount -o remount,bind,ro /", "isolation:read-only"),
            ("mount -t tmpfs -o mode=700,uid=65534,gid=65534,size=32m tmpfs /tmp", "isolation:scratch"),
            ("mount -t tmpfs -o mode=700,uid=65534,gid=65534,size=1m tmpfs /run", "isolation:control-sockets"),
            ('mount -t tmpfs -o mode=700,uid=65534,gid=65534,size=1m tmpfs "$runner_temp"',
             "isolation:runner-files"),
            ("setpriv --reuid=65534 --regid=65534 --clear-groups", "isolation:non-root"),
            ("env -i PATH=/usr/bin:/bin HOME=/tmp TMPDIR=/tmp LANG=C", "isolation:environment"),
            ('git -C "$base" rev-parse --verify -q HEAD', "isolation:base-readable"),
            ('git -C "$head" rev-parse --verify -q HEAD', "isolation:head-readable"),
            ("timeout --signal=TERM --kill-after=5s 300s", "isolation:time"),
            ("ulimit -f 16384", "isolation:output"),
            ('python3 -B "$base/tools/agent_eval.py" --tier 0 --root "$base"', "collector:base"),
            ('--target "$head" --emit-observations /tmp/tier0-observations.json', "collector:contract"),
            ("> /dev/null 2>&1", "collector:child-logging"),
        ):
            if not isolate or value not in executable(isolate):
                found.append(boundary)
        upload = named_step(emit, "Upload tier-0 observations")
        if not upload or "actions/upload-artifact@b7c566a772e6b6bfb58ed0dc250532a479d7789f" not in upload or \
                "if: ${{ always() }}" not in upload or \
                "${{ format('tier0-observations-{0}-{1}', github.run_id, github.run_attempt) }}" not in upload or \
                "path: ${{ runner.temp }}/tier0-observations.json" not in upload or \
                "retention-days: 1" not in upload or "if-no-files-found: error" not in upload or \
                "overwrite: false" not in upload:
            found.append("artifact:emit-upload")

        if not policy:
            return found + ["job:pr-policy"]
        if needs_list(policy) != ["tier0-emit"]:
            found.append("job:pr-policy:needs")
        if "if: ${{ always() && github.event_name == 'pull_request' }}" not in executable(policy):
            found.append("job:pr-policy:event")
        if "actions: read" not in executable(policy) or "secrets." in policy:
            found.append("job:pr-policy:credentials")
        if "verdict: ${{ steps.verdict.outputs.verdict }}" not in executable(policy):
            found.append("verdict:trusted-output")
        for name, ref in (
            ("Check out the event base", "${{ github.event.pull_request.base.sha }}"),
            ("Check out the event head", "${{ github.event.pull_request.head.sha }}"),
        ):
            step = named_step(policy, name)
            if not step or "ref: %s" % ref not in step or "fetch-depth: 0" not in step or \
                    "persist-credentials: false" not in step:
                found.append("checkout:pr-policy:%s" % name.split()[-1])
        transport = named_step(policy, "Fetch one bounded artifact without unpacking")
        for value, boundary in (
            ("id: transport", "transport:identity"),
            ("continue-on-error: true", "transport:failed-download"),
            ("GH_TOKEN: ${{ github.token }}", "transport:permission"),
            ("ARTIFACT_NAME: ${{ format('tier0-observations-{0}-{1}', github.run_id, github.run_attempt) }}",
             "transport:attempt-name"),
            ("/actions/runs/%s/artifacts?%s", "transport:query"),
            ("ARCHIVE_LIMIT = 9 * 1024 * 1024", "transport:archive-bound"),
            ("MEMBER_LIMIT = 8 * 1024 * 1024", "transport:member-bound"),
            ('member.filename != "tier0-observations.json"', "transport:member-name"),
            ("len(members) != 1", "transport:member-count"),
            ("not stat.S_ISREG(mode)", "transport:member-type"),
            ("member.flag_bits & 0x1", "transport:member-encryption"),
            ('hmac.compare_digest(digest, digest_text)', "transport:digest"),
            ("os.open(str(output_path), flags, 0o600)", "transport:quarantine"),
        ):
            if not transport or value not in executable(transport):
                found.append(boundary)
        drive = named_step(policy, "Run the base policy driver")
        if not drive or "if: ${{ always() }}" not in drive or "id: verdict" not in drive or \
                'python3 -B "$GITHUB_WORKSPACE/policy-base/tools/pr_policy.py"' not in executable(drive) or \
                "--head-observations" not in drive or "--out" not in drive or \
                "driver_exit" not in drive or "GITHUB_OUTPUT" not in drive:
            found.append("verdict:driver-publication")
        if "$GITHUB_WORKSPACE/policy-head/tools/pr_policy.py" in policy:
            found.append("verdict:wrong-driver")

        if not aggregate:
            return found + ["job:pr-checks"]
        direct = needs_list(aggregate)
        if "tier0-emit" not in direct or "pr-policy" not in direct:
            found.append("aggregate:direct-needs")
        checkout = next(
            (step for step in step_blocks(aggregate)
             if "actions/checkout@" in step),
            "",
        )
        if "github.event_name == 'pull_request' && github.event.pull_request.base.sha || github.sha" not in checkout or \
                "fetch-depth: 0" not in checkout or "persist-credentials: false" not in checkout:
            found.append("aggregate:base-checkout")
        author = named_step(aggregate, "Author check")
        if not author or "github.event.pull_request.user.login" not in author or \
                "AGENT_LOGINS: ${{ vars.AGENT_LOGINS }}" not in author:
            found.append("aggregate:author")
        pr_step = named_step(aggregate, "Aggregate pull request")
        legacy = named_step(aggregate, "Aggregate trusted event")
        if not pr_step or "POLICY_VERDICT: ${{ needs.pr-policy.outputs.verdict }}" not in pr_step or \
                "printf '%s' \"$POLICY_VERDICT\"" not in pr_step or \
                "tools/ci_aggregate.py --policy-aware --policy-result" not in pr_step or \
                "--expect-base-sha \"$BASE_SHA\" --expect-head-sha \"$HEAD_SHA\"" not in pr_step:
            found.append("aggregate:pull-request")
        if not legacy or "github.event_name != 'pull_request'" not in legacy or \
                "--policy-aware" in legacy or "python3 -B tools/ci_aggregate.py" not in legacy:
            found.append("aggregate:legacy")
        return found

    def test_policy_workflow_wiring_is_complete(self):
        parsed = jobs("pr-checks.yml")
        self.assertEqual(self.problems(parsed), [])
        self.assertIn("if: always()", parsed["pr-checks"])

    def test_policy_workflow_mutations_fail_at_the_owned_boundary(self):
        parsed = jobs("pr-checks.yml")
        mutations = []

        def changed(label, expected, transform):
            copy = dict(parsed)
            transform(copy)
            mutations.append((label, expected, self.problems(copy)))

        changed(
            "missing emit", "job:tier0-emit",
            lambda graph: graph.pop("tier0-emit"),
        )
        changed(
            "emit output trusted", "job:tier0-emit:no-output",
            lambda graph: graph.__setitem__(
                "tier0-emit", graph["tier0-emit"].replace(
                    "    steps:\n", "    outputs:\n      verdict: bad\n    steps:\n", 1
                )
            ),
        )
        changed(
            "wrong head checkout", "checkout:tier0-emit:head",
            lambda graph: graph.__setitem__(
                "tier0-emit", graph["tier0-emit"].replace(
                    "ref: ${{ github.event.pull_request.head.sha }}",
                    "ref: ${{ github.event.pull_request.base.sha }}", 1
                )
            ),
        )
        changed(
            "emit job skipped", "job:tier0-emit:event",
            lambda graph: graph.__setitem__(
                "tier0-emit", graph["tier0-emit"].replace(
                    "if: ${{ github.event_name == 'pull_request' }}",
                    "if: ${{ false }}", 1
                )
            ),
        )
        changed(
            "collector can use the network", "isolation:namespaces",
            lambda graph: graph.__setitem__(
                "tier0-emit", graph["tier0-emit"].replace(" --net", "", 1)
            ),
        )
        changed(
            "collector Git checkouts retain the runner owner", "isolation:input-owner",
            lambda graph: graph.__setitem__(
                "tier0-emit", graph["tier0-emit"].replace(
                    "sudo chown -R 65534:65534", "sudo chown -R 0:0", 1
                )
            ),
        )
        changed(
            "collector inherits the runner environment", "isolation:outer-environment",
            lambda graph: graph.__setitem__(
                "tier0-emit", graph["tier0-emit"].replace(
                    "sudo env -i PATH=/usr/bin:/bin HOME=/tmp LANG=C", "sudo", 1
                )
            ),
        )
        changed(
            "artifact is overwritten", "artifact:emit-upload",
            lambda graph: graph.__setitem__(
                "tier0-emit", graph["tier0-emit"].replace(
                    "overwrite: false", "overwrite: true", 1
                )
            ),
        )
        changed(
            "artifact ignores the attempt", "artifact:emit-upload",
            lambda graph: graph.__setitem__(
                "tier0-emit", graph["tier0-emit"].replace(
                    "github.run_id, github.run_attempt",
                    "github.run_id, github.run_number", 1
                )
            ),
        )
        changed(
            "policy no longer waits", "job:pr-policy:needs",
            lambda graph: graph.__setitem__(
                "pr-policy", graph["pr-policy"].replace(
                    "needs: tier0-emit", "needs: scope", 1
                )
            ),
        )
        changed(
            "policy job skipped", "job:pr-policy:event",
            lambda graph: graph.__setitem__(
                "pr-policy", graph["pr-policy"].replace(
                    "if: ${{ always() && github.event_name == 'pull_request' }}",
                    "if: ${{ false }}", 1
                )
            ),
        )
        changed(
            "checkout credentials persist", "checkout:tier0-emit:base",
            lambda graph: graph.__setitem__(
                "tier0-emit", graph["tier0-emit"].replace(
                    "persist-credentials: false", "persist-credentials: true", 1
                )
            ),
        )
        changed(
            "broken transport stops running", "transport:failed-download",
            lambda graph: graph.__setitem__(
                "pr-policy", graph["pr-policy"].replace(
                    "continue-on-error: true", "continue-on-error: false", 1
                )
            ),
        )
        changed(
            "download query is broken", "transport:query",
            lambda graph: graph.__setitem__(
                "pr-policy", graph["pr-policy"].replace(
                    "/actions/runs/%s/artifacts?%s",
                    "/actions/runs/%s/artifact?%s", 1
                )
            ),
        )
        changed(
            "quarantine member bound grows", "transport:member-bound",
            lambda graph: graph.__setitem__(
                "pr-policy", graph["pr-policy"].replace(
                    "MEMBER_LIMIT = 8 * 1024 * 1024",
                    "MEMBER_LIMIT = 9 * 1024 * 1024", 1
                )
            ),
        )
        changed(
            "wrong driver checkout", "verdict:wrong-driver",
            lambda graph: graph.__setitem__(
                "pr-policy", graph["pr-policy"].replace(
                    'GITHUB_WORKSPACE/policy-base/tools/pr_policy.py',
                    'GITHUB_WORKSPACE/policy-head/tools/pr_policy.py', 1
                )
            ),
        )
        changed(
            "emit job removed from aggregate", "aggregate:direct-needs",
            lambda graph: graph.__setitem__(
                "pr-checks", graph["pr-checks"].replace("tier0-emit, ", "", 1)
            ),
        )
        changed(
            "aggregate uses the head checkout", "aggregate:base-checkout",
            lambda graph: graph.__setitem__(
                "pr-checks", graph["pr-checks"].replace(
                    "github.event.pull_request.base.sha || github.sha",
                    "github.event.pull_request.head.sha || github.sha", 1
                )
            ),
        )
        changed(
            "wrong verdict producer", "aggregate:pull-request",
            lambda graph: graph.__setitem__(
                "pr-checks", graph["pr-checks"].replace(
                    "needs.pr-policy.outputs.verdict",
                    "needs.tier0-emit.outputs.verdict", 1
                )
            ),
        )
        changed(
            "legacy aggregate becomes policy-aware", "aggregate:legacy",
            lambda graph: graph.__setitem__(
                "pr-checks", graph["pr-checks"].replace(
                    "name: Aggregate trusted event",
                    "name: Aggregate trusted event --policy-aware", 1
                ) + "\n        # --policy-aware\n"
            ),
        )
        changed(
            "author gate removed", "aggregate:author",
            lambda graph: graph.__setitem__(
                "pr-checks", graph["pr-checks"].replace(
                    "      - name: Author check", "      - name: Removed author gate", 1
                )
            ),
        )

        for label, expected, actual in mutations:
            self.assertIn(expected, actual, label)

    def test_macos_test_consumes_only_the_build_upload_artifact_id(self):
        build = jobs("pr-checks.yml")["macos-build"]
        test = jobs("pr-checks.yml")["macos-test"]
        upload = named_step(build, "Upload the test products")
        download = named_step(test, "Download the test products")
        require = named_step(test, "Require the immutable test-products artifact")
        self.assertIn("outputs:\n      artifact-id: ${{ steps.products.outputs.artifact-id }}", build)
        self.assertIn("id: products", upload)
        self.assertIn("ARTIFACT_ID: ${{ needs.macos-build.outputs.artifact-id }}", require)
        self.assertIn("artifact-ids: ${{ needs.macos-build.outputs.artifact-id }}", download)
        self.assertNotIn("name: macos-test-products", download)
        self.assertRegex(require, r"\*\[!0-9\]\*")


class PolicyInlinePythonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        policy = jobs("pr-checks.yml")["pr-policy"]
        cls.transport = inline_python(policy, "Fetch one bounded artifact without unpacking")
        cls.validator = inline_python(policy, "Run the base policy driver")
        module_path = WORKFLOWS.parents[1] / "tools" / "pr_policy.py"
        specification = importlib.util.spec_from_file_location("policy_driver_fixture", module_path)
        cls.policy_driver = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(cls.policy_driver)

    def test_every_inline_python_block_has_an_executable_fixture(self):
        policy = jobs("pr-checks.yml")["pr-policy"]
        self.assertEqual(policy.count("<<'PY'"), 2)
        self.assertTrue(self.transport.strip().startswith("import hashlib"))
        self.assertTrue(self.validator.strip().startswith("import json"))

    @staticmethod
    def archive(members):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w", zipfile.ZIP_STORED) as bundle:
            for name, payload, mode in members:
                member = zipfile.ZipInfo(name)
                member.create_system = 3
                member.external_attr = mode << 16
                bundle.writestr(member, payload)
        return data.getvalue()

    @staticmethod
    def encrypted(archive):
        data = bytearray(archive)
        local = data.index(b"PK\x03\x04")
        central = data.index(b"PK\x01\x02")
        data[local + 6] |= 1
        data[central + 8] |= 1
        return bytes(data)

    def run_transport(self, archive, download_status=200, http_status=200):
        state = {"archive": archive, "download_status": download_status, "http_status": http_status}

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, _format, *_args):
                pass

            def do_GET(self):
                if "/artifacts?" in self.path:
                    if state["http_status"] != 200:
                        self.send_response(state["http_status"])
                        self.end_headers()
                        return
                    name = "tier0-observations-11-2"
                    metadata = {
                        "total_count": 1,
                        "artifacts": [{
                            "id": 7,
                            "name": name,
                            "expired": False,
                            "workflow_run": {"id": 11},
                            "digest": "sha256:" + hashlib.sha256(state["archive"]).hexdigest(),
                        }],
                    }
                    body = json.dumps(metadata).encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                if self.path.endswith("/artifacts/7/zip"):
                    self.send_response(state["download_status"])
                    if state["download_status"] != 200:
                        self.end_headers()
                        return
                    self.send_header("Content-Length", str(len(state["archive"])))
                    self.end_headers()
                    try:
                        self.wfile.write(state["archive"])
                    except BrokenPipeError:
                        pass
                    return
                self.send_response(404)
                self.end_headers()

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.daemon = True
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix="policy-transport-") as directory:
                path = Path(directory) / "tier0-observations.json"
                env = dict(os.environ)
                env.update({
                    "GH_TOKEN": "fixture-token",
                    "API_URL": "http://127.0.0.1:%s" % server.server_port,
                    "REPOSITORY": "fixture/repository",
                    "RUN_ID": "11",
                    "RUN_ATTEMPT": "2",
                    "ARTIFACT_NAME": "tier0-observations-11-2",
                    "OBSERVATIONS_PATH": str(path),
                })
                result = subprocess.run(
                    [sys.executable, "-B", "-"],
                    input=self.transport,
                    text=True,
                    env=env,
                    capture_output=True,
                )
                payload = path.read_bytes() if path.exists() else None
                return result, payload
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_transport_accepts_only_one_bounded_regular_member(self):
        regular = stat.S_IFREG | 0o644
        payload = b'{"schema":1,"base_sha":"a","head_sha":"b","cases":{}}'
        valid = self.archive([("tier0-observations.json", payload, regular)])
        good, extracted = self.run_transport(valid)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertEqual(extracted, payload)

        invalid = {
            "transfer-too-large": b"x" * (9 * 1024 * 1024 + 1),
            "two-members": self.archive([
                ("tier0-observations.json", payload, regular),
                ("other.json", b"{}", regular),
            ]),
            "directory": self.archive([("tier0-observations.json/", b"", stat.S_IFDIR | 0o755)]),
            "link": self.archive([("tier0-observations.json", b"target", stat.S_IFLNK | 0o777)]),
            "wrong-name": self.archive([("observations.json", payload, regular)]),
            "encrypted": self.encrypted(valid),
            "truncated": valid[:-9],
        }
        oversized = self.archive([
            ("tier0-observations.json", b"x" * (8 * 1024 * 1024 + 1), regular),
        ])
        invalid["member-too-large"] = oversized
        for label, archive in invalid.items():
            result, extracted = self.run_transport(archive)
            self.assertNotEqual(result.returncode, 0, label)
            self.assertEqual(extracted, b"", label)

    def test_failed_download_leaves_no_observation_and_delivers_unavailable(self):
        regular = stat.S_IFREG | 0o644
        valid = self.archive([("tier0-observations.json", b"{}", regular)])
        result, extracted = self.run_transport(valid, download_status=503)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(extracted)
        with self.assertRaises(self.policy_driver.PolicyError) as caught:
            self.policy_driver._read_observations(
                Path("does-not-exist"), "a" * 40, "b" * 40,
            )
        self.assertEqual(caught.exception.reason, "tier0_unavailable")

    def run_validator(self, verdict, driver_exit, base_sha=None, head_sha=None):
        base_sha = base_sha or "a" * 40
        head_sha = head_sha or "b" * 40
        with tempfile.TemporaryDirectory(prefix="policy-verdict-") as directory:
            path = Path(directory) / "verdict.json"
            output = Path(directory) / "output"
            if isinstance(verdict, bytes):
                path.write_bytes(verdict)
            else:
                path.write_text(
                    json.dumps(verdict, sort_keys=True, separators=(",", ":")) + "\n",
                    encoding="utf-8",
                )
            env = dict(os.environ)
            env["GITHUB_OUTPUT"] = str(output)
            result = subprocess.run(
                [
                    sys.executable, "-B", "-", str(path), str(driver_exit),
                    base_sha, head_sha,
                ],
                input=self.validator,
                text=True,
                env=env,
                capture_output=True,
            )
            published = output.read_text(encoding="utf-8") if output.exists() else ""
            return result, published

    def test_verdict_publication_accepts_only_sha_bound_exit_pairings(self):
        passing = {
            "schema": 1,
            "outcome": "pass",
            "reasons": ["tier0_pass"],
            "base_sha": "a" * 40,
            "head_sha": "b" * 40,
        }
        failing = dict(passing, outcome="fail", reasons=["tier0_new_failure"])
        result, published = self.run_validator(passing, 0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(published.startswith("verdict="), published)

        result, published = self.run_validator(failing, 1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(published.startswith("verdict="), published)

        result, published = self.run_validator(
            dict(passing, base_sha="c" * 40), 0
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(published, "")

        result, published = self.run_validator(failing, 0)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(published, "")
