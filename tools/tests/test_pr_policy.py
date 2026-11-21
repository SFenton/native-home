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
        for name in (
            "pr_policy.py",
            "lane_land.py",
            "agent_eval.py",
            "agent_eval_case.py",
            "agent_eval_measure.py",
            "ci_aggregate.py",
        ):
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
        git(self.tmp, "clone", "-q", str(self.base), str(self.head))

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

    def run(self, *, driver=None, base_sha=None, head_sha=None, result=None, extra_env=None,
            with_base_sha=True, with_head_sha=True):
        actual_base = git(self.base, "rev-parse", "HEAD")
        actual_head = git(self.head, "rev-parse", "HEAD")
        result = result or self.tmp / "policy.json"
        command = [
            sys.executable,
            str(driver or self.base / "tools" / "pr_policy.py"),
            "--base-checkout", str(self.base),
            "--head-checkout", str(self.head),
        ]
        if with_base_sha:
            command += ["--base-sha", base_sha or actual_base]
        if with_head_sha:
            command += ["--head-sha", head_sha or actual_head]
        command += ["--out", str(result)]
        environment = dict(os.environ)
        environment.update(extra_env or {})
        proc = subprocess.run(
            command,
            capture_output=True,
            text=True,
            env=environment,
        )
        try:
            verdict = json.loads(proc.stdout)
        except ValueError as exc:
            raise AssertionError(f"driver did not print JSON: stdout={proc.stdout!r} stderr={proc.stderr!r}") from exc
        self.assert_exact_shas(verdict, actual_base, actual_head)
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
                aggregate_code = aggregate.main([
                    "--policy-aware",
                    "--policy-result", str(result),
                    "--expect-base-sha", verdict["base_sha"],
                    "--expect-head-sha", verdict["head_sha"],
                ])
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
        self.assert_policy(repos, "trusted_separation", "fail")

    def test_the_driver_must_run_from_the_base_checkout(self):
        repos = PolicyRepos(self)
        code, verdict, _result = repos.run(driver=repos.head / "tools" / "pr_policy.py")
        self.assertEqual(code, 1)
        self.assertEqual(verdict["reasons"], ["driver_not_base"])

    def test_both_sha_arguments_are_required_and_bound_to_checkout_heads(self):
        repos = PolicyRepos(self)
        for missing in ("base", "head"):
            with self.subTest(missing=missing):
                args = [
                    sys.executable,
                    str(repos.base / "tools" / "pr_policy.py"),
                    "--base-checkout", str(repos.base),
                    "--head-checkout", str(repos.head),
                    "--out", str(repos.tmp / f"missing-{missing}.json"),
                ]
                if missing != "base":
                    args += ["--base-sha", git(repos.base, "rev-parse", "HEAD")]
                if missing != "head":
                    args += ["--head-sha", git(repos.head, "rev-parse", "HEAD")]
                proc = subprocess.run(args, capture_output=True, text=True)
                self.assertEqual(proc.returncode, 2)
        for label in ("base", "head"):
            with self.subTest(mismatch=label):
                wrong = "0" * 40
                kwargs = {f"{label}_sha": wrong}
                code, verdict, _result = repos.run(**kwargs)
                self.assertEqual(code, 1)
                self.assertEqual(verdict["reasons"], [f"{label}_sha_mismatch"])
                self.assertEqual(
                    verdict[f"{label}_sha"],
                    git(getattr(repos, label), "rev-parse", "HEAD"),
                )

    def test_dirty_base_or_head_checkout_is_refused(self):
        for label in ("base", "head"):
            with self.subTest(label=label):
                repos = PolicyRepos(self)
                write(getattr(repos, label) / "tools" / "old.py", "DIRTY = True\n")
                code, verdict, _result = repos.run()
                self.assertEqual(code, 1)
                self.assertEqual(verdict["reasons"], [f"{label}_checkout_dirty"])

    def test_head_driver_grader_and_threshold_are_never_trusted(self):
        mutations = (
            (
                "driver",
                "tools/pr_policy.py",
                "print('{\\\"schema\\\":1,\\\"outcome\\\":\\\"pass\\\"}')\n",
                "tier0_pass",
                "pass",
            ),
            (
                "grader",
                "tools/agent_eval_case.py",
                "raise SystemExit(0)\n",
                "tier0_pass",
                "pass",
            ),
            (
                "threshold",
                "contracts/jev/questions/policy.sample.json",
                json.dumps(dict(
                    QUESTION,
                    accept=dict(QUESTION["accept"], yes_above=0.6),
                )),
                "jev_threshold",
                "fail",
            ),
        )
        for name, path, content, reason, outcome in mutations:
            with self.subTest(name=name):
                repos = PolicyRepos(self)
                write(repos.head / path, content)
                repos.commit(repos.head)
                self.assert_policy(repos, reason, outcome)

    def test_a_base_change_after_tier_zero_fails_the_fingerprint(self):
        repos = PolicyRepos(self)
        trusted = repos.base / "tools" / "trusted-marker"
        write(
            repos.head / "tools" / "triage" / "hass_triage.py",
            "from pathlib import Path\n"
            "def route_rule(issue, nightly=False):\n"
            f"    Path({str(trusted)!r}).write_text('tampered\\n', encoding='utf-8')\n"
            "    return 'researcher'\n\n"
            "def ledger_level(issue, nightly=False):\n"
            "    return 1\n",
        )
        repos.commit(repos.head)
        self.assertTrue(trusted.exists() is False)
        self.assert_policy(repos, "trusted_checkout_changed", "fail")
        self.assertTrue(trusted.exists())

    def test_child_cannot_forge_the_output_or_inherit_actions_state(self):
        repos = PolicyRepos(self)
        output = repos.tmp / "parent-verdict.json"
        actions_output = repos.tmp / "actions-output"
        leak_marker = repos.tmp / "environment-leak"
        inherited = {
            "GITHUB_OUTPUT": str(actions_output),
            "GITHUB_ENV": str(actions_output),
            "GITHUB_STEP_SUMMARY": str(actions_output),
            "GITHUB_TOKEN": str(actions_output),
            "GH_TOKEN": str(actions_output),
            "ACTIONS_RUNTIME_TOKEN": str(actions_output),
            "GIT_DIR": str(actions_output),
            "GIT_CONFIG_GLOBAL": str(actions_output),
            "PYTHONUSERBASE": str(actions_output),
            "PYTHONWARNINGS": "ignore",
            "PYTHONHASHSEED": "123",
        }
        write(
            repos.head / "tools" / "triage" / "hass_triage.py",
            "import os\n"
            "from pathlib import Path\n"
            "def route_rule(issue, nightly=False):\n"
            f"    leaked = [name for name, value in {inherited!r}.items() "
            "if os.environ.get(name) == value]\n"
            f"    if leaked: Path({str(leak_marker)!r}).write_text(','.join(leaked))\n"
            f"    Path({str(output)!r}).write_text('{{\"outcome\":\"pass\",\"forged\":true}}')\n"
            "    return 'researcher'\n\n"
            "def ledger_level(issue, nightly=False):\n"
            "    return 1\n",
        )
        repos.commit(repos.head)
        code, verdict, result = repos.run(result=output, extra_env=inherited)
        self.assertEqual(code, 0, verdict)
        self.assertEqual(verdict["outcome"], "pass")
        self.assertEqual(json.loads(result.read_text(encoding="utf-8")), verdict)
        self.assertFalse(actions_output.exists())
        self.assertFalse(leak_marker.exists())

    def test_scope_uses_merge_base_when_the_head_is_behind_the_base(self):
        repos = PolicyRepos(self)
        base_only = dict(ROUTE_CASE, id="base-only")
        write(
            repos.base / "evals" / "agents" / "routing-replay" / "cases" /
            "base-only.json",
            json.dumps(base_only),
        )
        repos.commit(repos.base)
        write(repos.head / "apple" / "Sources" / "Product.swift", "struct Product {}\n")
        repos.commit(repos.head)
        self.assert_policy(repos, "product_only", "noop")

    def test_scope_without_a_merge_base_is_unreadable(self):
        repos = PolicyRepos(self)
        shutil.rmtree(repos.head / ".git")
        git(repos.head, "init", "-q")
        git(repos.head, "add", "-A")
        git(
            repos.head,
            "-c", "user.name=Policy Test",
            "-c", "user.email=policy@example.invalid",
            "-c", "commit.gpgSign=false",
            "commit", "-q", "-m", "unrelated",
        )
        code, verdict, _result = repos.run()
        self.assertEqual(code, 1)
        self.assertEqual(verdict["reasons"], ["scope_unreadable"])

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
