"""The pr-checks aggregate verdict (tools/ci_aggregate.py) and the denylist decision (tools/ci_denylist.py)."""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_aggregate as agg  # noqa: E402
import ci_denylist as deny  # noqa: E402


def needs(**results):
    """A `needs` context: every job named gets a result; scope outputs come from app= / release= keyword pairs."""
    out = {name.replace("_", "-"): {"result": value, "outputs": {}} for name, value in results.items()}
    return out


def private_run(**overrides):
    base = needs(scope="success", repo_checks="success", build_release="success", swift_test="success", scope_hosted="skipped",
                 repo_checks_hosted="skipped", tool_tests_hosted="skipped", denylist_scan="success", swift_test_hosted="skipped",
                 build_release_hosted="skipped")
    base["scope"]["outputs"] = {"app": "true", "release": "true"}
    base.update({k.replace("_", "-"): {"result": v, "outputs": {}} for k, v in overrides.items()})
    return base


def public_run(macos="success", **overrides):
    base = needs(scope="skipped", repo_checks="skipped", build_release="skipped", swift_test="skipped", scope_hosted="success",
                 repo_checks_hosted="success", tool_tests_hosted="success", denylist_scan="success", swift_test_hosted=macos,
                 build_release_hosted=macos)
    base["scope-hosted"]["outputs"] = {"app": "true", "release": "true"}
    base.update({k.replace("_", "-"): {"result": v, "outputs": {}} for k, v in overrides.items()})
    return base


class AggregateTests(unittest.TestCase):
    def test_the_private_set_passes(self):
        self.assertEqual(agg.problems(private_run(), True, False), [])

    def test_the_public_set_passes_with_and_without_hosted_macos(self):
        self.assertEqual(agg.problems(public_run(), False, True), [])
        self.assertEqual(agg.problems(public_run(macos="skipped"), False, False), [])

    def test_a_skipped_core_job_fails(self):
        self.assertTrue(agg.problems(private_run(repo_checks="skipped"), True, False))
        self.assertTrue(agg.problems(private_run(scope="skipped"), True, False))
        self.assertTrue(agg.problems(public_run(tool_tests_hosted="skipped"), False, False))
        self.assertTrue(agg.problems(public_run(repo_checks_hosted="skipped"), False, True))

    def test_the_wrong_visibility_runs_nothing_and_fails(self):
        """A visibility evaluated wrongly (the empty value on a schedule) can never be green with nothing run."""
        self.assertTrue(agg.problems(public_run(), True, False))
        self.assertTrue(agg.problems(private_run(), False, False))

    def test_hosted_macos_may_skip_only_while_the_variable_is_off_or_the_scope_says_so(self):
        self.assertEqual(agg.problems(public_run(macos="skipped"), False, False), [])
        self.assertTrue(agg.problems(public_run(macos="skipped"), False, True))
        run = public_run(macos="skipped")
        run["scope-hosted"]["outputs"] = {"app": "false", "release": "false"}
        self.assertEqual(agg.problems(run, False, True), [])

    def test_a_scope_gated_mac_job_may_not_skip_when_the_scope_wanted_it(self):
        self.assertTrue(agg.problems(private_run(swift_test="skipped"), True, False))
        run = private_run(swift_test="skipped", build_release="skipped")
        run["scope"]["outputs"] = {"app": "false", "release": "false"}
        self.assertEqual(agg.problems(run, True, False), [])

    def test_the_denylist_scan_may_skip_for_a_fork_pull_request_only(self):
        self.assertEqual(agg.problems(private_run(denylist_scan="skipped"), True, False), [])
        self.assertTrue(agg.problems(private_run(denylist_scan="failure"), True, False))

    def test_failures_and_cancellations_always_fail(self):
        for state in ("failure", "cancelled"):
            self.assertTrue(agg.problems(private_run(swift_test=state), True, False))
            self.assertTrue(agg.problems(public_run(tool_tests_hosted=state), False, True))

    def test_sim_smoke_gates_the_aggregate(self):
        """A failed or cancelled device leg fails it; skipped passes only when HOSTED_MACOS is off or the scope has no app change."""
        for state in ("failure", "cancelled"):
            self.assertTrue(agg.problems(public_run(sim_smoke=state), False, True))
        self.assertEqual(agg.problems(public_run(sim_smoke="success"), False, True), [])
        self.assertEqual(agg.problems(public_run(macos="skipped", sim_smoke="skipped"), False, False), [])
        self.assertTrue(agg.problems(public_run(sim_smoke="skipped"), False, True))
        run = public_run(macos="skipped", sim_smoke="skipped")
        run["scope-hosted"]["outputs"] = {"app": "false", "release": "false"}
        self.assertEqual(agg.problems(run, False, True), [])
        self.assertEqual(agg.problems(private_run(sim_smoke="skipped"), True, False), [])

    def test_main_reads_the_context_and_exits_nonzero_on_a_problem(self):
        for run, private, code in ((private_run(), "true", 0), (private_run(repo_checks="skipped"), "true", 1)):
            old = dict(os.environ)
            os.environ.update({"NEEDS": json.dumps(run), "PRIVATE": private, "HOSTED_MACOS": ""})
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(agg.main(), code)
            finally:
                os.environ.clear()
                os.environ.update(old)


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
