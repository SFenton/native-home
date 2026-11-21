"""The pr-checks aggregate verdict (tools/ci_aggregate.py) and the denylist decision (tools/ci_denylist.py)."""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_aggregate as agg  # noqa: E402
import ci_denylist as deny  # noqa: E402


def needs(**results):
    """A `needs` context: every job named gets a result; scope outputs are set by the caller."""
    return {name.replace("_", "-"): {"result": value, "outputs": {}} for name, value in results.items()}


def run_of(macos="success", **overrides):
    """A pull request that changed app code and tools: every gated job wanted. `macos` is the state of the build and the test matrix."""
    base = needs(scope="success", linux_checks="success", tool_tests_core="success", denylist_scan="success",
                 macos_build=macos, macos_test=macos, coverage_changed=macos, build_release=macos)
    base["scope"]["outputs"] = {"app": "true", "release": "true"}
    base.update({k.replace("_", "-"): {"result": v, "outputs": {}} for k, v in overrides.items()})
    return base


BASE_SHA = "a" * 40
HEAD_SHA = "b" * 40


def policy_args(verdict):
    return {
        "policy": verdict,
        "policy_aware": True,
        "expect_base_sha": BASE_SHA,
        "expect_head_sha": HEAD_SHA,
    }


def valid_policy(outcome="pass", reasons=None):
    return {
        "schema": 1,
        "outcome": outcome,
        "reasons": reasons or ["tier0_pass"],
        "base_sha": BASE_SHA,
        "head_sha": HEAD_SHA,
    }


class AggregateTests(unittest.TestCase):
    def test_the_set_passes_with_and_without_hosted_macos(self):
        self.assertEqual(agg.problems(run_of(), True), [])
        self.assertEqual(agg.problems(run_of(macos="skipped"), False), [])

    def test_a_skipped_core_job_fails(self):
        self.assertTrue(agg.problems(run_of(tool_tests_core="skipped"), False))
        self.assertTrue(agg.problems(run_of(linux_checks="skipped"), True))
        self.assertTrue(agg.problems(run_of(scope="skipped"), True))

    def test_hosted_macos_may_skip_only_while_the_variable_is_off_or_the_scope_says_so(self):
        self.assertEqual(agg.problems(run_of(macos="skipped"), False), [])
        self.assertTrue(agg.problems(run_of(macos="skipped"), True))
        run = run_of(macos="skipped")
        run["scope"]["outputs"] = {"app": "false", "release": "false"}
        self.assertEqual(agg.problems(run, True), [])

    def test_one_failed_or_skipped_leg_of_the_macos_build_or_test_fails_the_aggregate(self):
        for job in ("macos-build", "macos-test", "coverage-changed"):
            for state in ("failure", "cancelled", "skipped"):
                run = run_of()
                run[job]["result"] = state
                self.assertTrue(agg.problems(run, True, "pull_request"), (job, state))
        run = run_of(macos="skipped")
        run["scope"]["outputs"]["app"] = "false"  # a docs-only diff skips both
        self.assertEqual(agg.problems(run, True, "pull_request"), [])

    def test_the_release_build_may_skip_off_main_but_not_on_a_push(self):
        run = run_of(build_release="skipped")
        self.assertEqual(agg.problems(run, True, "pull_request"), [])
        self.assertEqual(agg.problems(run, True, "workflow_dispatch"), [])
        self.assertTrue(agg.problems(run, True, "push"))

    def test_the_coverage_gate_may_skip_off_a_pull_request_but_not_on_one(self):
        """coverage-changed runs on pull requests only: a push to main or a manual run skips it; a PR that needs it may not."""
        run = run_of(coverage_changed="skipped")
        self.assertEqual(agg.problems(run, True, "push"), [])
        self.assertEqual(agg.problems(run, True, "workflow_dispatch"), [])
        self.assertTrue(agg.problems(run, True, "pull_request"))
        self.assertEqual(agg.problems(run_of(coverage_changed="skipped"), False, "pull_request"), [])
        for state in ("failure", "cancelled"):
            self.assertTrue(agg.problems(run_of(coverage_changed=state), True, "push"))

    def test_the_macos_job_may_not_skip_on_a_pull_request_that_needs_it(self):
        self.assertTrue(agg.problems(run_of(macos="skipped"), True, "pull_request"))

    def test_a_failed_or_cancelled_macos_job_fails_the_aggregate(self):
        """The Smoke steps are part of the macos job and required: a failed device step fails the job and so this."""
        for state in ("failure", "cancelled"):
            self.assertTrue(agg.problems(run_of(macos=state), True))

    def test_a_gated_job_missing_from_needs_fails(self):
        """Dropping a job from the workflow's `needs` must not let the aggregate pass blind."""
        for gone in ("macos-build", "macos-test", "coverage-changed", "build-release"):
            run = run_of()
            del run[gone]
            self.assertTrue(agg.problems(run, True), gone)

    def test_the_denylist_scan_may_skip_for_a_fork_pull_request_only(self):
        self.assertEqual(agg.problems(run_of(denylist_scan="skipped"), False), [])
        self.assertTrue(agg.problems(run_of(denylist_scan="failure"), False))

    def test_failures_and_cancellations_always_fail(self):
        for state in ("failure", "cancelled"):
            self.assertTrue(agg.problems(run_of(macos=state), True))
            self.assertTrue(agg.problems(run_of(tool_tests_core=state), True))

    def test_main_reads_the_context_and_exits_nonzero_on_a_problem(self):
        for run, code in ((run_of(), 0), (run_of(linux_checks="skipped"), 1)):
            with mock.patch.dict(os.environ, {
                "NEEDS": json.dumps(run),
                "HOSTED_MACOS": "on",
                "POLICY_VERDICT": "{broken",
                "POLICY_RESULT": "/not-used",
            }):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(agg.main(), code)

    def test_legacy_invocation_does_not_require_or_read_a_policy_result(self):
        run = run_of()
        run["pr-policy"] = {"result": "skipped", "outputs": {}}
        with mock.patch.dict(os.environ, {"NEEDS": json.dumps(run), "HOSTED_MACOS": "on"}):
            self.assertEqual(agg.problems(run, True), [])
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(agg.main(), 0)

        del run["pr-policy"]
        self.assertEqual(agg.problems(run, True, policy_aware=False), [])

    def test_policy_mode_requires_one_successful_job_and_verdict_on_pull_requests(self):
        valid = valid_policy()
        base = run_of()
        self.assertTrue(agg.problems(base, True, **policy_args(valid)))
        for state in ("skipped", "failure", "cancelled", ""):
            run = dict(base)
            run["pr-policy"] = {"result": state, "outputs": {"verdict": json.dumps(valid)}}
            self.assertTrue(agg.problems(run, True, **policy_args(valid)), state)
        run = dict(base)
        run["pr-policy"] = {"result": "success", "outputs": {"verdict": json.dumps(valid)}}
        self.assertEqual(agg.problems(run, True, **policy_args(valid)), [])

    def test_policy_mode_requires_every_event_except_the_default_branch_push(self):
        missing = run_of()
        for event in ("pull_request", "workflow_dispatch", "", "merge_group", "unknown"):
            with self.subTest(event=event):
                self.assertTrue(agg.problems(
                    missing, True, event, **policy_args(valid_policy())
                ))
        self.assertEqual(agg.problems(
            missing, True, "push", policy_aware=True,
            github_ref="refs/heads/main",
        ), [])

    def test_policy_mode_requires_policy_for_non_main_and_empty_push_refs(self):
        missing = run_of()
        for ref in ("refs/heads/feature", ""):
            with self.subTest(ref=ref):
                self.assertTrue(agg.problems(
                    missing, True, "push", policy_aware=True, github_ref=ref,
                ))

    def test_policy_mode_rejects_malformed_and_nonpassing_results(self):
        run = run_of()
        run["pr-policy"] = {"result": "success", "outputs": {}}
        for verdict in (
                None,
                "{broken",
                {"schema": 2, "outcome": "pass", "reasons": ["tier0_pass"], "base_sha": "a" * 40, "head_sha": "b" * 40},
                {"schema": 1, "outcome": "pass", "reasons": ["unknown"], "base_sha": "a" * 40, "head_sha": "b" * 40},
                {"schema": 1, "outcome": "hold", "reasons": ["tier1_required"],
                 "base_sha": "a" * 40, "head_sha": "b" * 40},
                {"schema": 1, "outcome": "fail", "reasons": ["tier0_new_failure"],
                 "base_sha": "a" * 40, "head_sha": "b" * 40}):
            self.assertTrue(agg.problems(run, True, **policy_args(verdict)), verdict)

    def test_policy_mode_binds_both_shas_and_rejects_missing_values(self):
        run = run_of()
        run["pr-policy"] = {"result": "success", "outputs": {}}
        verdict = valid_policy()
        self.assertEqual(agg.problems(run, True, **policy_args(verdict)), [])
        for label in ("base", "head"):
            with self.subTest(label=label):
                changed = dict(verdict)
                changed[f"{label}_sha"] = "c" * 40
                self.assertTrue(agg.problems(run, True, **policy_args(changed)))
                missing = dict(policy_args(verdict))
                missing[f"expect_{label}_sha"] = ""
                self.assertTrue(agg.problems(run, True, **missing))

    def test_policy_mode_uses_one_file_source_and_one_job_name(self):
        verdict = valid_policy()
        run = run_of()
        run["pr-policy"] = {
            "result": "success",
            "outputs": {
                "verdict": json.dumps(verdict),
                "policy": json.dumps(verdict),
                "result_json": json.dumps(verdict),
            },
        }
        self.assertTrue(agg.problems(run, True, policy_aware=True,
                                     expect_base_sha=BASE_SHA,
                                     expect_head_sha=HEAD_SHA))
        self.assertTrue(agg.problems(run, True, **{
            **policy_args(verdict),
            "policy_job": "policy",
        }))

    def test_policy_mode_accepts_a_proved_product_only_noop_and_push_unchanged(self):
        noop = valid_policy("noop", ["product_only"])
        run = run_of()
        run["pr-policy"] = {"result": "success", "outputs": {"verdict": json.dumps(noop)}}
        self.assertEqual(agg.problems(run, True, **policy_args(noop)), [])
        self.assertEqual(agg.problems(
            run_of(), True, "push", policy_aware=True,
            github_ref="refs/heads/main",
        ), [])

    def test_main_policy_aware_reads_an_actual_result_file(self):
        verdict = valid_policy()
        run = run_of()
        run["pr-policy"] = {"result": "success", "outputs": {}}
        with tempfile.TemporaryDirectory() as tmp:
            result = Path(tmp) / "policy.json"
            result.write_text(json.dumps(verdict))
            with mock.patch.dict(os.environ, {
                "NEEDS": json.dumps(run),
                "HOSTED_MACOS": "on",
                "EVENT": "pull_request",
            }):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(agg.main([
                        "--policy-aware",
                        "--policy-result", str(result),
                        "--expect-base-sha", BASE_SHA,
                        "--expect-head-sha", HEAD_SHA,
                    ]), 0)
            result.write_text("{broken")
            with mock.patch.dict(os.environ, {
                "NEEDS": json.dumps(run),
                "HOSTED_MACOS": "on",
                "EVENT": "pull_request",
            }):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(agg.main([
                        "--policy-aware",
                        "--policy-result", str(result),
                        "--expect-base-sha", BASE_SHA,
                        "--expect-head-sha", HEAD_SHA,
                    ]), 1)


class DenylistMaskTests(unittest.TestCase):
    def test_mask_prints_one_command_per_term_and_skips_comments(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "list.txt"
            path.write_text("# comment\n\nzebrafish\n  quokka  \n")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(deny.main(["mask", str(path)]), 0)
            self.assertEqual(out.getvalue().splitlines(), ["::add-mask::zebrafish", "::add-mask::quokka"])


if __name__ == "__main__":
    unittest.main()
