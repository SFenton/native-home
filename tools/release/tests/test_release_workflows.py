"""Lints the release workflows and script flags: the owner's flow (merge to main, bump, signed IPA artifact, TestFlight) as assertions.

No YAML library is available on the runner's system Python, so the workflow files are read by indentation: a block is
the lines under a key until the next key at the same indent.
"""

import os
import re
import subprocess
import unittest
from pathlib import Path
from typing import Dict, List

ROOT = Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / ".github" / "workflows"
SCRIPT = ROOT / "tools" / "release" / "testflight_upload.sh"


def read(name: str) -> str:
    return (WORKFLOWS / name).read_text(encoding="utf-8")


def blocks(text: str, indent: int = 0) -> Dict[str, List[str]]:
    """Map each ``key:`` at ``indent`` spaces to the lines nested under it."""
    out: Dict[str, List[str]] = {}
    key = None
    pattern = re.compile(r"^%s([A-Za-z_][\w-]*):(.*)$" % (" " * indent))
    for line in text.splitlines():
        found = pattern.match(line)
        if found:
            key = found.group(1)
            out[key] = [found.group(2).strip()]
        elif key and (line.startswith(" " * (indent + 1)) or not line.strip()):
            out[key].append(line)
        elif line.strip() and not line.lstrip().startswith("#"):
            key = None
    return out


def triggers(name: str) -> Dict[str, List[str]]:
    return blocks("\n".join(blocks(read(name))["on"]), 2)


class FlowTests(unittest.TestCase):
    @staticmethod
    def code(text: str) -> str:
        """The workflow without comment-only lines (a comment may name what the job must not do)."""
        return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))

    @staticmethod
    def jobs() -> Dict[str, List[str]]:
        return blocks("\n".join(blocks(read("ios-release.yml"))["jobs"]), 2)

    def test_no_push_pull_request_or_tag_trigger_builds_or_uploads(self):
        self.assertEqual(set(triggers("ios-release-build.yml")), {"workflow_dispatch"})

    def test_the_pipeline_runs_on_a_push_to_main_with_no_pr_checks_dependency(self):
        on = triggers("ios-release.yml")
        self.assertEqual(set(on), {"push", "workflow_dispatch"})
        push = blocks("\n".join(on["push"]), 4)
        self.assertEqual(set(push), {"branches"})
        self.assertIn("[main]", push["branches"][0])
        text = read("ios-release.yml")
        code = self.code(text)
        self.assertNotIn("workflow_run", code)
        self.assertNotIn("pr-checks", code)
        self.assertNotIn("HASS_VERSION_BUMP_ENABLED", text)
        inputs = blocks("\n".join(on["workflow_dispatch"]), 4)["inputs"]
        self.assertEqual(set(blocks("\n".join(inputs), 6)), {"tag", "force"})
        self.assertFalse((WORKFLOWS / "version-bump.yml").exists(), "folded into ios-release.yml: one bumper, no race")

    def test_the_pipeline_runs_no_tests_coverage_or_simulator(self):
        code = self.code(read("ios-release.yml"))
        for banned in ("swift test", "xcodebuild test", "apple_coverage", "ios_uitest", "simctl", "affected_tests", "run_tool_tests",
                       "build-for-testing", "FENTON_SIM_"):
            self.assertNotIn(banned, code)

    def test_pr_checks_still_runs_on_pushes_to_main(self):
        on = triggers("pr-checks.yml")
        self.assertIn("main", "\n".join(on["push"]))
        self.assertIn("pull_request", on)

    def test_bump_serializes_and_never_cancels(self):
        bump = "\n".join(self.jobs()["bump"])
        self.assertIn("group: ios-release-bump", bump)
        self.assertIn("cancel-in-progress: false", bump)
        self.assertIn("contents: write", bump)
        self.assertIn("actions: write", bump)
        self.assertIn("runs-on: ubuntu-24.04", bump)
        self.assertNotIn("secrets.", bump, "the bump needs no secrets, so it always runs")
        self.assertIn('--head "$GITHUB_SHA"', bump)
        self.assertIn("--push", bump)
        self.assertIn("tag: ${{ steps.bump.outputs.tag }}", bump)

    def test_bump_dispatches_testflight_only_when_enabled_and_never_by_tag_push(self):
        text = read("ios-release.yml")
        self.assertIn('[ "$TESTFLIGHT" = "true" ]', text)
        self.assertIn("vars.HASS_TESTFLIGHT_ENABLED", text)
        self.assertIn("gh workflow run ios-release-build.yml --ref main", text)
        self.assertNotIn("gh workflow run ios-release.yml", text)
        self.assertNotIn("tags:", "\n".join(triggers("ios-release.yml")["push"]), "a tag push (GITHUB_TOKEN) starts nothing; the ipa job is a job")

    def test_a_dispatched_tag_is_validated_and_rebuilt_without_a_bump(self):
        bump = "\n".join(self.jobs()["bump"])
        self.assertIn("^ios/v[0-9]{4}", bump)
        self.assertIn('echo "tag=$REBUILD_TAG" >> "$GITHUB_OUTPUT"', bump)
        self.assertLess(bump.index('echo "tag=$REBUILD_TAG"'), bump.index("args=(bump"))

    def test_the_ipa_job_is_hosted_signed_from_the_environment_and_only_after_a_tag(self):
        ipa = "\n".join(self.jobs()["ipa"])
        self.assertIn("needs: bump", ipa)
        self.assertIn("needs.bump.outputs.tag != ''", ipa)
        self.assertIn("vars.HOSTED_MACOS == 'on'", ipa)  # the repo-wide switch for hosted macOS jobs
        self.assertIn("environment: release-signing", ipa)
        self.assertIn("vars.HOSTED_XCODE_LABEL", ipa)
        self.assertIn("'xcode-27'", ipa)
        self.assertIn("vars.HOSTED_DEVELOPER_DIR", ipa)
        self.assertIn('FENTON_CI_HOSTED: "1"', ipa)
        self.assertNotIn("self-hosted", ipa)
        self.assertRegex(ipa, r"permissions:\s*\n\s*contents: read")
        self.assertNotIn("contents: write", ipa)
        self.assertIn("timeout-minutes: 90", ipa)
        self.assertIn("group: ios-release-ipa-${{ needs.bump.outputs.tag }}", ipa)
        self.assertIn("persist-credentials: false", ipa)

    def test_the_signing_secrets_are_exactly_the_checklist_and_named_in_the_error(self):
        text = read("ios-release.yml")
        names = ["APPLE_DEVELOPMENT_P12_BASE64", "APPLE_DEVELOPMENT_P12_PASSWORD", "APPLE_DISTRIBUTION_P12_BASE64",
                 "APPLE_DISTRIBUTION_P12_PASSWORD", "ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_PRIVATE_KEY"]
        self.assertEqual(sorted(set(re.findall(r"secrets\.(\w+)", text))), names)
        check = text[text.index("Check the signing secrets"):text.index("Prepare the runner")]
        for name in names:
            self.assertIn(name, check.split("run: |")[1], "the missing-secret loop must name every secret")
        self.assertIn("::error title=ios-release cannot sign::", check)
        self.assertIn("testflight.md", check)

    def test_the_keychain_is_temporary_unlocked_for_codesign_and_checked(self):
        text = read("ios-release.yml")
        for command in ("openssl rand -hex 24", "::add-mask::$password", "security create-keychain", "-lut 21600", "security unlock-keychain",
                        "-A -t cert -f pkcs12", "security set-key-partition-list -S apple-tool:,apple:",
                        "security list-keychain -d user -s", "security default-keychain -s", "security find-identity -v -p codesigning"):
            self.assertIn(command, text)
        self.assertIn('"$count" -lt 2', text)  # fewer than the two identities fails
        self.assertLess(text.index("-A -t cert -f pkcs12"), text.index("set-key-partition-list"))
        self.assertLess(text.index("set-key-partition-list"), text.index("Archive and export the IPA"))

    def test_the_build_uses_the_hosted_script_with_a_date_build_number(self):
        text = read("ios-release.yml")
        self.assertIn("date -u +%Y%m%d%H%M", text)
        self.assertIn('tools/release/ios_ipa_build.sh "$TAG" "$build"', text)
        self.assertIn("command -v xcodegen > /dev/null || brew install xcodegen", text)  # the line tools/ci_hosted_setup.sh runs

    def test_the_default_server_is_never_a_repository_variable_and_never_in_the_public_ipa_job(self):
        for path in sorted(WORKFLOWS.glob("*.yml")):
            self.assertNotIn("vars.HASS_DEFAULT_SERVER", path.read_text(encoding="utf-8"),
                             "%s: a repository variable is printed in the log by the env block; use a secret" % path.name)
        self.assertNotIn("HASS_DEFAULT_SERVER", read("ios-release.yml"))
        self.assertIn("secrets.HASS_DEFAULT_SERVER", read("ios-release-build.yml"))

    def test_the_pipeline_runs_on_main_only(self):
        jobs = self.jobs()
        self.assertIn("if: ${{ github.ref == 'refs/heads/main' }}", "\n".join(jobs["bump"]))
        self.assertIn("github.ref == 'refs/heads/main'", "\n".join(jobs["ipa"]))

    def test_the_keychain_step_never_prints_the_identities(self):
        text = read("ios-release.yml")
        step = text[text.index("Temporary keychain with the signing identities"):text.index("App Store Connect API key (temporary file)")]
        for line in step.splitlines():
            if line.lstrip().startswith("#"):
                continue
            if "echo" in line and "$identities" in line:
                self.assertIn("| grep", line, "an identities listing is echoed: " + line)  # only piped into grep, never printed
        self.assertNotIn("sed -E", step)
        self.assertIn("valid signing identities: $count", step)

    def test_the_ipa_is_a_workflow_artifact_and_never_a_release_asset(self):
        text = read("ios-release.yml")
        code = self.code(text)
        self.assertRegex(text, r"uses: actions/upload-artifact@[0-9a-f]{40} # v")
        self.assertIn("name: FentonHome-${{ steps.build.outputs.version }}", text)
        self.assertIn("retention-days: 30", text)
        self.assertIn("if-no-files-found: error", text)
        self.assertIn("steps.build.outputs.ipa", text)
        self.assertIn("steps.build.outputs.dsyms", text)
        self.assertNotIn("gh release", code)
        self.assertNotIn("softprops", code)

    def test_cleanup_runs_always_and_removes_the_keychain_certificates_and_key(self):
        text = read("ios-release.yml")
        cleanup = text[text.index("Remove the keychain"):]
        self.assertIn("if: always()", cleanup)
        self.assertIn('security delete-keychain "$RELEASE_KEYCHAIN"', cleanup)
        self.assertIn('rm -f "$RUNNER_TEMP"/apple-*.p12', cleanup)
        self.assertIn('rm -rf "$RUNNER_TEMP/asc"', cleanup)
        self.assertNotIn('echo "$ASC_PRIVATE_KEY"', text)

    def test_release_build_is_gated_on_main_the_variable_and_the_environment(self):
        text = read("ios-release-build.yml")
        job = blocks("\n".join(blocks(text)["jobs"]), 2)["testflight"]
        header = "\n".join(job)
        self.assertIn("github.ref == 'refs/heads/main'", header)
        self.assertIn("vars.HASS_TESTFLIGHT_ENABLED == 'true'", header)
        self.assertIn("inputs.dry_run == true", header)
        self.assertIn("environment: testflight", header)
        self.assertIn("group: ios-release-build", header)
        self.assertIn("cancel-in-progress: false", header)
        self.assertIn("self-hosted", header)

    def test_release_build_has_the_inputs_and_only_the_three_secrets(self):
        text = read("ios-release-build.yml")
        inputs = blocks("\n".join(triggers("ios-release-build.yml")["workflow_dispatch"]), 4)["inputs"]
        self.assertEqual(set(blocks("\n".join(inputs), 6)), {"version_tag", "dry_run"})
        self.assertEqual(sorted(set(re.findall(r"secrets\.(\w+)", text))),
                         ["ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_PRIVATE_KEY", "HASS_DEFAULT_SERVER"])
        code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
        self.assertNotRegex(code, r"(?i)p12|IOS_DIST|keychain")
        self.assertNotIn("FentonHomeWatch", text)

    def test_the_api_key_file_is_temporary_and_removed_even_on_failure(self):
        text = read("ios-release-build.yml")
        self.assertIn("$RUNNER_TEMP/asc", text)
        cleanup = text[text.index("Remove the API key"):]
        self.assertIn("if: always()", cleanup)
        self.assertIn('rm -rf "$RUNNER_TEMP/asc"', cleanup)
        self.assertNotIn("echo \"$ASC_PRIVATE_KEY\"", text)

    def test_the_release_loop_is_the_queue_not_the_tag_that_woke_it(self):
        text = read("ios-release-build.yml")
        self.assertIn("tools/release/testflight_queue.py", text)
        self.assertIn("fetch-tags: true", text)
        self.assertNotIn("tools/release/testflight_upload.sh", text)  # the queue runs it, once per pending version

    def test_ledger_tags_cannot_start_the_ipa_workflow(self):
        push = triggers("ios-release.yml")["push"]
        self.assertNotIn("tags", "\n".join(push))  # only a push to main starts it, so neither ios/v* nor ios/tf/* tags can
        self.assertFalse(re.fullmatch(r"ios/v.*", "ios/tf/2610.29.01"))

    def test_pr_checks_runs_the_new_tests(self):
        script = (ROOT / "tools" / "run_tool_tests.sh").read_text()
        for module in ("test_testflight_queue", "test_release_workflows"):
            self.assertIn(module, script)


class UploadScriptTests(unittest.TestCase):
    def dry(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([str(SCRIPT), "--dry-run", "--tag", "ios/v2610.29.01"] + list(args),
                              capture_output=True, text=True)

    def test_default_holds_a_devcap_slot_and_has_no_key(self):
        out = self.dry()
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("devcap.py", out.stdout)
        self.assertNotIn("authenticationKey", out.stdout)
        self.assertNotIn("FentonHomeWatch", out.stdout)

    def test_no_devcap_and_the_api_key_reach_both_xcodebuild_steps(self):
        out = self.dry("--no-devcap", "--asc-key-path", "/tmp/AuthKey_X.p8", "--asc-key-id", "KEYID",
                       "--asc-issuer-id", "ISSUER")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertNotIn("devcap.py", out.stdout)
        commands = [line for line in out.stdout.splitlines() if "xcodebuild" in line]
        self.assertEqual(len(commands), 2)
        for line in commands:
            self.assertIn("-allowProvisioningUpdates", line)
            self.assertIn("-authenticationKeyPath /tmp/AuthKey_X.p8", line)
            self.assertIn("-authenticationKeyID KEYID", line)
            self.assertIn("-authenticationKeyIssuerID ISSUER", line)
        self.assertIn("exportArchive", commands[1])

    def test_the_default_server_value_never_reaches_the_output(self):
        env = dict(os.environ, HASS_DEFAULT_SERVER="https://house.example.invalid")
        out = subprocess.run([str(SCRIPT), "--dry-run", "--tag", "ios/v2610.29.01"], capture_output=True, text=True, env=env)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertNotIn("house.example.invalid", out.stdout + out.stderr)
        self.assertIn("HASS_DEFAULT_SERVER=", out.stdout)
        self.assertIn("***", out.stdout)

    def test_a_partial_api_key_is_refused(self):
        out = self.dry("--asc-key-id", "KEYID")
        self.assertEqual(out.returncode, 2)
        self.assertIn("path, a key id and an issuer id", out.stderr)

    def test_source_must_be_an_app_checkout(self):
        out = self.dry("--source", "/nonexistent")
        self.assertEqual(out.returncode, 2)


if __name__ == "__main__":
    unittest.main()
