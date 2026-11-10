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
                 macos_build=macos, macos_test=macos, build_release=macos)
    base["scope"]["outputs"] = {"app": "true", "release": "true"}
    base.update({k.replace("_", "-"): {"result": v, "outputs": {}} for k, v in overrides.items()})
    return base


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
        for job in ("macos-build", "macos-test"):
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

    def test_the_macos_job_may_not_skip_on_a_pull_request_that_needs_it(self):
        self.assertTrue(agg.problems(run_of(macos="skipped"), True, "pull_request"))

    def test_a_failed_or_cancelled_macos_job_fails_the_aggregate(self):
        """The Smoke steps are part of the macos job and required: a failed device step fails the job and so this."""
        for state in ("failure", "cancelled"):
            self.assertTrue(agg.problems(run_of(macos=state), True))

    def test_a_gated_job_missing_from_needs_fails(self):
        """Dropping a job from the workflow's `needs` must not let the aggregate pass blind."""
        for gone in ("macos-build", "macos-test", "build-release"):
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
            with mock.patch.dict(os.environ, {"NEEDS": json.dumps(run), "HOSTED_MACOS": "on"}):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(agg.main(), code)


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
