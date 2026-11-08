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
        self.assertGreaterEqual(found, 4)

    def test_the_runner_label_variable_is_validated(self):
        for path in all_files():
            for job, text in jobs(path.name).items():
                if "vars.HOSTED_XCODE_LABEL" in runs_on(text):
                    self.assertIn("startsWith(vars.HOSTED_XCODE_LABEL, 'xcode-')", runs_on(text), "%s/%s" % (path.name, job))
                    self.assertIn("'xcode-27'", runs_on(text))

    def test_no_pr_or_main_job_runs_on_a_self_hosted_runner(self):
        for name in ("pr-checks.yml", "tool-tests.yml"):
            for job, text in jobs(name).items():
                self.assertNotIn("self-hosted", runs_on(text), "%s/%s" % (name, job))
                self.assertNotIn("repository.private", text, "%s/%s" % (name, job))

    def test_the_aggregate_keeps_its_name_and_covers_both_sets(self):
        text = jobs("pr-checks.yml")["pr-checks"]
        self.assertIn("if: always()", text)
        for needed in ("scope-hosted", "repo-checks-hosted", "tool-tests-hosted", "denylist-scan", "swift-test-hosted", "build-release-hosted"):
            self.assertRegex(text, r"[\[ ,]%s[,\]\s]" % re.escape(needed))
        self.assertNotIn("sim-smoke", text.split("steps:")[0].split("needs:")[1])
        self.assertTrue((WORKFLOWS / "pr-checks.yml").read_text(encoding="utf-8").startswith("name: pr-checks\n"))
        self.assertIn("toJSON(needs)", text)
        self.assertIn("python3 tools/ci_aggregate.py", text)
        self.assertNotIn("success|skipped", text)

    def test_python_tool_test_jobs_leave_hosted_mode_off_and_compare_against_the_base(self):
        for name, job in (("pr-checks.yml", "repo-checks-hosted"), ("pr-checks.yml", "tool-tests-hosted"), ("tool-tests.yml", "tool-tests-hosted")):
            self.assertNotIn("FENTON_CI_HOSTED", jobs(name)[job], "%s/%s" % (name, job))
        self.assertIn("tools/ci_new_failures.py --base", jobs("pr-checks.yml")["tool-tests-hosted"])

    def test_hosted_macos_jobs_use_the_hosted_mode_and_no_devcap(self):
        for job in ("swift-test-hosted", "build-release-hosted", "sim-smoke"):
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

    def test_least_privilege_in_tool_tests(self):
        text = (WORKFLOWS / "tool-tests.yml").read_text(encoding="utf-8")
        self.assertRegex(text.split("\njobs:\n", 1)[0], r"permissions:\n  contents: read\n(?!  issues)")
        self.assertIn("issues: write", jobs("tool-tests.yml")["report-hosted"])

    def test_self_hosted_jobs_never_trigger_on_pull_requests_without_the_private_gate(self):
        for name in ("nightly.yml", "ios-release.yml", "ios-release-build.yml"):
            text = (WORKFLOWS / name).read_text(encoding="utf-8")
            self.assertNotIn("pull_request", text.split("\njobs:\n", 1)[0].replace("pull_request_target", ""), name)

    def test_permissions_are_read_only_at_the_top(self):
        for name in ("pr-checks.yml", "runtimes.yml", "tool-tests.yml"):
            self.assertRegex((WORKFLOWS / name).read_text(encoding="utf-8"), r"\npermissions:\n  contents: read\n")

    def test_sim_smoke_builds_before_it_boots_and_settles_with_a_heartbeat(self):
        text = jobs("pr-checks.yml")["sim-smoke"]
        build = text.index("--build-only")
        settle = text.index("tools/sim_settle.sh")
        smoke = text.index("- name: Smoke plan on")
        self.assertLess(build, settle)
        self.assertLess(settle, smoke)
        self.assertNotIn("simctl boot", text)  # no simulator boots outside sim_settle.sh, after the build
        self.assertEqual(text.count("tools/ci_heartbeat.sh run --"), 2)
        self.assertIn("timeout-minutes: ${{ matrix.family == 'duo' && 60 || 90 }}", text)

    def test_sim_smoke_hosted_build_settings_come_from_the_workflow_env_only(self):
        text = jobs("pr-checks.yml")["sim-smoke"]
        self.assertIn('FENTON_HOSTED_BUILD_SETTINGS: "ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO"', text)
        self.assertIn("sudo mdutil -a -i off || true", text)
        script = (Path(__file__).resolve().parents[1] / "ios_uitest.sh").read_text(encoding="utf-8")
        self.assertIn("$CI_HOSTED == 1 && -n \"${FENTON_HOSTED_BUILD_SETTINGS:-}\"", script)
        self.assertNotIn("ARCHS=arm64", script)


if __name__ == "__main__":
    unittest.main()
