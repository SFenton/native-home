"""Base-trusted pull-request policy behavior, through the real aggregate entry point."""

import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
TOOLS = REPO / "tools"
sys.path.insert(0, str(TOOLS))
import ci_aggregate as aggregate  # noqa: E402

ROUTE_CASE = {
    "id": "route-feature",
    "source": "policy fixture",
    "kind": "route",
    "input": {"title": "feature", "body": ""},
    "expect": {"route": "researcher", "level": 1},
}
QUESTION = {
    "id": "policy.sample",
    "mode": "active",
    "type": "noul",
    "instructions": "Decide the fixture.",
    "criteria": ["yes"],
    "accept": {"yes_above": 0.7, "min_confidence": 0.8, "no_below": 0.2},
    "target": {"precision": 0.9},
}


def git(repo, *args):
    proc = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout.strip()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class PolicyRepos:
    """Two clean repositories with one deterministic trusted tier-0 case."""

    def __init__(self, test, route="researcher", evaluator_tail=""):
        self.tmp = Path(tempfile.mkdtemp(prefix="pr-policy-test-"))
        test.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.base = self.tmp / "base"
        self.head = self.tmp / "head"
        self.base.mkdir()
        for name in ("pr_policy.py", "lane_land.py", "agent_eval.py", "agent_eval_case.py"):
            (self.base / "tools").mkdir(exist_ok=True)
            shutil.copy2(TOOLS / name, self.base / "tools" / name)
        agent_eval = self.base / "tools" / "agent_eval.py"
        if evaluator_tail:
            agent_eval.write_text(agent_eval.read_text(encoding="utf-8") + "\n" + evaluator_tail)
        write(
            self.base / "tools" / "triage" / "hass_triage.py",
            "def route_rule(issue, nightly=False):\n"
            f"    return {route!r}\n\n"
            "def ledger_level(issue, nightly=False):\n"
            "    return 1\n",
        )
        write(
            self.base / "evals" / "agents" / "routing-replay" / "cases" / "route-feature.json",
            json.dumps(ROUTE_CASE),
        )
        write(self.base / "contracts" / "jev" / "questions" / "policy.sample.json", json.dumps(QUESTION))
        write(self.base / "tools" / "old.py", "OLD = True\n")
        self._initialize(self.base)
        shutil.copytree(self.base, self.head, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        self._initialize(self.head)

    @staticmethod
    def _initialize(repo):
        git(repo, "init", "-q")
        git(repo, "add", "-A")
        git(repo, "-c", "user.name=Policy Test", "-c", "user.email=policy@example.invalid",
            "-c", "commit.gpgSign=false", "commit", "-q", "-m", "fixture")

    @staticmethod
    def commit(repo):
        git(repo, "add", "-A")
        git(repo, "-c", "user.name=Policy Test", "-c", "user.email=policy@example.invalid",
            "-c", "commit.gpgSign=false", "commit", "-q", "-m", "mutation")

    def run(self):
        base_sha, head_sha = git(self.base, "rev-parse", "HEAD"), git(self.head, "rev-parse", "HEAD")
        result = self.tmp / "policy.json"
        proc = subprocess.run(
            [
                sys.executable,
                str(self.base / "tools" / "pr_policy.py"),
                "--base-checkout", str(self.base),
                "--head-checkout", str(self.head),
                "--base-sha", base_sha,
                "--head-sha", head_sha,
                "--out", str(result),
            ],
            capture_output=True,
            text=True,
        )
        try:
            verdict = json.loads(proc.stdout)
        except ValueError as exc:
            raise AssertionError(f"driver did not print JSON: stdout={proc.stdout!r} stderr={proc.stderr!r}") from exc
        self.assert_exact_shas(verdict, base_sha, head_sha)
        return proc.returncode, verdict, result

    @staticmethod
    def assert_exact_shas(verdict, base_sha, head_sha):
        if verdict["base_sha"]:
            if verdict["base_sha"] != base_sha:
                raise AssertionError("the driver did not report the exact base SHA")
        if verdict["head_sha"]:
            if verdict["head_sha"] != head_sha:
                raise AssertionError("the driver did not report the exact head SHA")


def aggregate_needs():
    return {
        "scope": {"result": "success", "outputs": {"app": "false", "release": "false"}},
        "linux-checks": {"result": "success", "outputs": {}},
        "tool-tests-core": {"result": "success", "outputs": {}},
        "denylist-scan": {"result": "success", "outputs": {}},
        "macos-build": {"result": "skipped", "outputs": {}},
        "macos-test": {"result": "skipped", "outputs": {}},
        "coverage-changed": {"result": "skipped", "outputs": {}},
        "build-release": {"result": "skipped", "outputs": {}},
        "pr-policy": {"result": "success", "outputs": {}},
    }


class PrPolicyTests(unittest.TestCase):
    def assert_policy(self, repos, reason, outcome):
        driver_code, verdict, result = repos.run()
        self.assertEqual(verdict["outcome"], outcome, verdict)
        self.assertIn(reason, verdict["reasons"], verdict)
        self.assertEqual(driver_code, 0 if outcome in ("pass", "noop") else 1)
        with mock.patch.dict(os.environ, {
            "NEEDS": json.dumps(aggregate_needs()),
            "HOSTED_MACOS": "on",
            "EVENT": "pull_request",
        }):
            with contextlib.redirect_stdout(io.StringIO()):
                aggregate_code = aggregate.main(["--policy-aware", "--policy-result", str(result)])
        self.assertEqual(aggregate_code, 0 if outcome in ("pass", "noop") else 1)
        return verdict

    def test_broken_routing_is_red_even_when_the_head_grader_says_green(self):
        repos = PolicyRepos(self)
        write(
            repos.head / "tools" / "triage" / "hass_triage.py",
            "def route_rule(issue, nightly=False):\n"
            "    return 'designer'\n\n"
            "def ledger_level(issue, nightly=False):\n"
            "    return 1\n",
        )
        write(
            repos.head / "tools" / "agent_eval.py",
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "print('OK')\n"
            "sys.exit(0)\n",
        )
        repos.commit(repos.head)
        self.assert_policy(repos, "tier0_new_failure", "fail")

    def test_lost_count_without_a_new_failure_id_is_red(self):
        tail = """
_trusted_policy_evaluate = evaluate
def evaluate(root, *args, **kwargs):
    result = _trusted_policy_evaluate(root, *args, **kwargs)
    target = kwargs.get("target")
    if target and (Path(target) / "tools" / "lost-count").exists():
        result[0]["cases"] = 0
        result[0]["passed"] = 0
        result[0]["failures"] = []
    return result
"""
        repos = PolicyRepos(self, evaluator_tail=tail)
        write(repos.head / "tools" / "lost-count", "present\n")
        repos.commit(repos.head)
        self.assert_policy(repos, "tier0_lost_count", "fail")

    def test_neutral_role_and_eval_change_are_not_one_pull_request(self):
        repos = PolicyRepos(self)
        write(repos.head / "agents" / "roles" / "reviewer.md", "role\n")
        write(repos.head / "evals" / "agents" / "routing-replay" / "cases" / "new.json",
              json.dumps(dict(ROUTE_CASE, id="new")))
        repos.commit(repos.head)
        self.assert_policy(repos, "trusted_separation", "fail")

    def test_modified_active_case_is_rejected_by_append_only_policy(self):
        repos = PolicyRepos(self)
        changed = dict(ROUTE_CASE)
        changed["expect"] = {"route": "designer", "level": 1}
        write(repos.head / "evals" / "agents" / "routing-replay" / "cases" / "route-feature.json",
              json.dumps(changed))
        repos.commit(repos.head)
        self.assert_policy(repos, "append_only", "fail")

    def test_rename_includes_the_deleted_active_side_of_the_diff(self):
        repos = PolicyRepos(self)
        source = repos.head / "evals" / "agents" / "routing-replay" / "cases" / "route-feature.json"
        destination = source.with_name("renamed-feature.json")
        moved = dict(ROUTE_CASE, id="renamed-feature")
        write(destination, json.dumps(moved))
        source.unlink()
        repos.commit(repos.head)
        self.assert_policy(repos, "append_only", "fail")

    def test_invalid_retirement_and_same_name_copy_without_a_move_are_red(self):
        for invalid_copy in (False, True):
            with self.subTest(invalid_copy=invalid_copy):
                repos = PolicyRepos(self)
                active = repos.head / "evals" / "agents" / "routing-replay" / "cases" / "route-feature.json"
                retired = repos.head / "evals" / "agents" / "routing-replay" / "retired" / "route-feature.json"
                retired.parent.mkdir(parents=True, exist_ok=True)
                if invalid_copy:
                    shutil.copy2(active, retired)
                else:
                    shutil.move(active, retired)
                repos.commit(repos.head)
                self.assert_policy(
                    repos,
                    "retirement_mismatch" if invalid_copy else "retirement_invalid",
                    "fail",
                )

    def test_looser_jev_threshold_is_red_before_tier_zero(self):
        repos = PolicyRepos(self)
        looser = json.loads(json.dumps(QUESTION))
        looser["accept"]["yes_above"] = 0.6
        write(repos.head / "contracts" / "jev" / "questions" / "policy.sample.json", json.dumps(looser))
        repos.commit(repos.head)
        self.assert_policy(repos, "jev_threshold", "fail")

    def test_a_new_jev_question_must_start_in_shadow(self):
        repos = PolicyRepos(self)
        question = json.loads(json.dumps(QUESTION))
        question["id"] = "policy.new"
        write(repos.head / "contracts" / "jev" / "questions" / "policy.new.json", json.dumps(question))
        repos.commit(repos.head)
        self.assert_policy(repos, "jev_threshold", "fail")

    def test_changed_question_holds_without_exact_tier_one_evidence(self):
        repos = PolicyRepos(self)
        changed = json.loads(json.dumps(QUESTION))
        changed["instructions"] = "Decide the changed fixture."
        write(repos.head / "contracts" / "jev" / "questions" / "policy.sample.json", json.dumps(changed))
        repos.commit(repos.head)
        self.assert_policy(repos, "tier1_required", "hold")

    def test_preexisting_failure_does_not_fail_when_the_active_id_is_unchanged(self):
        repos = PolicyRepos(self, route="designer")
        write(repos.head / "tools" / "changed.txt", "trigger tier zero\n")
        repos.commit(repos.head)
        self.assert_policy(repos, "tier0_pass", "pass")

    def test_valid_byte_identical_retirement_preserves_the_trusted_total(self):
        repos = PolicyRepos(self)
        active = repos.head / "evals" / "agents" / "routing-replay" / "cases" / "route-feature.json"
        retired = repos.head / "evals" / "agents" / "routing-replay" / "retired" / "route-feature.json"
        retired.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(active, retired)
        write(
            repos.head / "evals" / "agents" / "routing-replay" / "retired" /
            "route-feature.json.reason.json",
            json.dumps({"kind": "target_removed", "path": "tools/old.py"}),
        )
        (repos.head / "tools" / "old.py").unlink()
        repos.commit(repos.head)
        self.assert_policy(repos, "tier0_pass", "pass")

    def test_pure_product_diff_is_a_proved_noop_without_running_replay(self):
        repos = PolicyRepos(self, route="designer")
        write(repos.head / "apple" / "Sources" / "Product.swift", "struct Product {}\n")
        repos.commit(repos.head)
        self.assert_policy(repos, "product_only", "noop")


if __name__ == "__main__":
    unittest.main()
