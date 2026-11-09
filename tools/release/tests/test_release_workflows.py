"""Lints the release workflows and script flags: the owner's flow (merge, CI, bump, build, TestFlight) as assertions.

No YAML library is available on the runner's system Python, so the workflow files are read by indentation: a block is
the lines under a key until the next key at the same indent.
"""

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
    def test_no_push_pull_request_or_tag_trigger_builds_or_uploads(self):
        self.assertEqual(set(triggers("ios-release-build.yml")), {"workflow_dispatch"})

    def test_the_bump_waits_for_pr_checks_on_main_and_keeps_manual_runs(self):
        on = triggers("version-bump.yml")
        self.assertEqual(set(on), {"workflow_run", "workflow_dispatch"})
        run = "\n".join(on["workflow_run"])
        self.assertIn("workflows: [pr-checks]", run)
        self.assertIn("types: [completed]", run)
        self.assertIn("branches: [main]", run)
        job = read("version-bump.yml")
        # only a successful push run of pr-checks; the commit bumped is the one that was checked
        self.assertIn("github.event.workflow_run.conclusion == 'success'", job)
        self.assertIn("github.event.workflow_run.event == 'push'", job)
        self.assertIn("vars.HASS_VERSION_BUMP_ENABLED == 'true'", job)
        self.assertGreaterEqual(job.count("github.event.workflow_run.head_sha"), 2)  # checkout ref and bump --head
        self.assertIn('--head "$HEAD_SHA"', job)

    def test_pr_checks_still_runs_on_pushes_to_main(self):
        on = triggers("pr-checks.yml")
        self.assertIn("main", "\n".join(on["push"]))
        self.assertIn("pull_request", on)

    def test_bump_serializes_and_never_cancels(self):
        concurrency = blocks(read("version-bump.yml"))["concurrency"]
        text = "\n".join(concurrency)
        self.assertIn("group: version-bump", text)
        self.assertIn("cancel-in-progress: false", text)

    def test_bump_dispatches_testflight_only_when_enabled_and_never_by_tag_push(self):
        text = read("version-bump.yml")
        self.assertIn('if [ "$TESTFLIGHT" = "true" ]', text)
        self.assertIn("vars.HASS_TESTFLIGHT_ENABLED", text)
        self.assertIn("gh workflow run ios-release-build.yml --ref main", text)
        self.assertIn("actions: write", text)
        self.assertNotIn("gh workflow run ios-release.yml", text,
                         "the bump must not start the IPA workflow (owner, 2026-10-29: it holds the Mac runner)")

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
                         ["ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_PRIVATE_KEY"])
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
        self.assertIn("ios/v*", "\n".join(push))
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

    def test_a_partial_api_key_is_refused(self):
        out = self.dry("--asc-key-id", "KEYID")
        self.assertEqual(out.returncode, 2)
        self.assertIn("path, a key id and an issuer id", out.stderr)

    def test_source_must_be_an_app_checkout(self):
        out = self.dry("--source", "/nonexistent")
        self.assertEqual(out.returncode, 2)


if __name__ == "__main__":
    unittest.main()
