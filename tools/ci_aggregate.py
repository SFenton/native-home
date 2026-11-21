#!/usr/bin/env python3
"""The verdict of the `pr-checks` aggregate job (hosted CI, .agents/workflow/ci.md).

A job that was skipped passes only when it was allowed to skip: scope-gated jobs (`macos-build`, `macos-test`,
`coverage-changed` (pull requests only), `build-release`) whose scope output says there was nothing to run, hosted macOS jobs while the repo variable ``HOSTED_MACOS`` is not ``on``, and the denylist
scan on a fork pull request. A core job that should have run and was skipped fails the aggregate,
so a wrong ``if`` can never turn it green with nothing run. A gated job missing from the workflow's ``needs`` fails it too, so dropping
one cannot let the aggregate pass blind. The macOS test matrix (`macos-test`, one leg per device family) runs the Smoke steps: a failed
leg fails the job. A matrix job's result is the worst of its legs. Failed and cancelled jobs always fail.

    NEEDS='<toJSON(needs)>' HOSTED_MACOS=on|'' EVENT=pull_request|push|... python3 tools/ci_aggregate.py

The base-trusted policy can opt in after a pull request policy job has run:

    python3 tools/ci_aggregate.py --policy-aware --policy-job pr-policy --policy-result verdict.json

The legacy invocation above intentionally has exactly its old behavior.  In
policy mode a missing, skipped, failed, cancelled or malformed ``pr-policy``
result is red on a pull request; a trusted ``pass`` or ``product_only`` no-op
is green.

Stdlib only (macOS system Python 3.9 and Linux).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

#: Jobs that must succeed.
CORE = ("scope", "linux-checks", "tool-tests-core")
#: job -> (scope job that decides it, output key, hosted macOS?). Skipping is allowed when that output is not 'true'.
GATED = {
    "build-release": ("scope", "release", True),
    "macos-build": ("scope", "app", True),
    "macos-test": ("scope", "app", True),
    "coverage-changed": ("scope", "app", True),
}
#: Gated jobs that run on a push to main only: a pull request or manual run may skip them.
PUSH_ONLY = ("build-release",)
#: Gated jobs that run on a pull request only: a push to main or a manual run may skip them.
PR_ONLY = ("coverage-changed",)
#: Jobs that only a fork pull request skips.
BOTH = ("denylist-scan",)
POLICY_JOB = "pr-policy"
POLICY_ALIASES = ("pr-policy", "policy")
POLICY_OUTCOMES = {"pass", "fail", "hold", "noop"}
POLICY_REASONS = {
    "append_only",
    "base_checkout_dirty",
    "base_checkout_unreadable",
    "base_sha_mismatch",
    "base_sha_unreadable",
    "driver_not_base",
    "git_objects_unreadable",
    "head_checkout_dirty",
    "head_checkout_unreadable",
    "head_sha_mismatch",
    "head_sha_unreadable",
    "jev_threshold",
    "no_changes",
    "policy_internal",
    "product_only",
    "retirement_invalid",
    "retirement_mismatch",
    "scope_unreadable",
    "tier0_lost_count",
    "tier0_malformed",
    "tier0_missing_summary",
    "tier0_new_failure",
    "tier0_pass",
    "tier0_unavailable",
    "tier1_required",
    "trusted_separation",
    "trusted_tool_unreadable",
}
SHA_RE = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")


def _policy_json(value: Any) -> Tuple[Optional[Dict[str, Any]], str]:
    """Parse a verdict object or a JSON object encoded in a job output."""
    if isinstance(value, Mapping):
        return dict(value), ""
    if not isinstance(value, str) or not value.strip():
        return None, "malformed policy result (missing verdict)"
    try:
        parsed = json.loads(value)
    except ValueError:
        return None, "malformed policy result (invalid JSON)"
    return (parsed, "") if isinstance(parsed, dict) else (None, "malformed policy result (not an object)")


def _policy_result_problem(verdict: Optional[Dict[str, Any]], parse_problem: str) -> str:
    if parse_problem:
        return parse_problem
    if not isinstance(verdict, dict):
        return "malformed policy result (not an object)"
    outcome = verdict.get("outcome")
    reasons = verdict.get("reasons")
    if verdict.get("schema") != 1 or outcome not in POLICY_OUTCOMES:
        return "malformed policy result (schema or outcome)"
    if not isinstance(reasons, list) or not reasons or \
            any(not isinstance(reason, str) or reason not in POLICY_REASONS for reason in reasons) or \
            len(set(reasons)) != len(reasons):
        return "malformed policy result (reasons)"
    base_sha, head_sha = verdict.get("base_sha"), verdict.get("head_sha")
    if any(extra not in {"schema", "outcome", "reasons", "base_sha", "head_sha"} for extra in verdict):
        return "malformed policy result (unexpected field)"
    if outcome == "fail":
        if base_sha not in ("", None) and not (isinstance(base_sha, str) and SHA_RE.fullmatch(base_sha)):
            return "malformed policy result (base SHA)"
        if head_sha not in ("", None) and not (isinstance(head_sha, str) and SHA_RE.fullmatch(head_sha)):
            return "malformed policy result (head SHA)"
    elif not (isinstance(base_sha, str) and SHA_RE.fullmatch(base_sha) and
              isinstance(head_sha, str) and SHA_RE.fullmatch(head_sha)):
        return "malformed policy result (SHAs)"
    if outcome == "noop" and reasons != ["product_only"]:
        return "malformed policy result (no-op proof)"
    if outcome == "hold" and "tier1_required" not in reasons:
        return "malformed policy result (hold reason)"
    if outcome == "pass" and any(reason not in {"no_changes", "tier0_pass"} for reason in reasons):
        return "malformed policy result (pass reason)"
    if outcome == "fail" and any(reason in {"no_changes", "product_only", "tier0_pass"} for reason in reasons):
        return "malformed policy result (failure reason)"
    return ""


def _policy_job(needs: Mapping[str, Mapping], name: str) -> Optional[Mapping]:
    names = POLICY_ALIASES if name in ("", POLICY_JOB) else (name,)
    found = [(candidate, needs[candidate]) for candidate in names if candidate in needs]
    if not found:
        return None
    if len(found) > 1:
        return {"result": "ambiguous"}
    return found[0][1]


def policy_problems(needs: Mapping[str, Mapping], event: str, verdict: Any = None,
                    parse_problem: str = "", job_name: str = POLICY_JOB) -> List[str]:
    """Why the base-trusted policy verdict fails for this pull request."""
    if event != "pull_request":
        return []
    job = _policy_job(needs, job_name)
    if job is None:
        return [f"{job_name or POLICY_JOB}: missing from needs"]
    state = str(job.get("result", ""))
    if state in ("failure", "cancelled", "skipped"):
        return [f"{job_name or POLICY_JOB}: {state} (the policy result is required)"]
    if state != "success":
        return [f"{job_name or POLICY_JOB}: {state or 'missing'} (the policy result is malformed)"]
    selected = verdict
    if selected is None:
        outputs = job.get("outputs", {}) or {}
        for key in ("verdict", "policy", "result_json"):
            if key in outputs:
                selected = outputs[key]
                break
    parsed, problem = _policy_json(selected)
    problem = parse_problem or problem
    problem = _policy_result_problem(parsed, problem)
    if problem:
        return [problem]
    if parsed["outcome"] in ("fail", "hold"):
        return [f"policy: {parsed['outcome']} ({', '.join(parsed['reasons'])})"]
    return []


def problems(needs: Mapping[str, Mapping], hosted_macos: bool, event: str = "pull_request",
            *, policy: Any = None, policy_aware: bool = False, policy_parse_problem: str = "",
            policy_job: str = POLICY_JOB) -> List[str]:
    """Why the aggregate must fail, one line per job; empty when it may pass."""
    result: Dict[str, str] = {name: str(job.get("result", "")) for name, job in needs.items()}
    found: List[str] = []
    for name, state in sorted(result.items()):
        if state in ("failure", "cancelled"):
            found.append("%s: %s" % (name, state))
    for name in CORE:
        if result.get(name) != "success" and result.get(name) not in ("failure", "cancelled"):
            found.append("%s: %s (a core job that should run must succeed)" % (name, result.get(name, "missing")))
    for name in GATED:
        if name not in result:
            found.append("%s: missing from needs (the aggregate must list every gated job)" % name)
    for name, (scope_job, key, macos) in GATED.items():
        if name not in result or result[name] != "skipped":
            continue
        if name in PUSH_ONLY and event != "push":
            continue
        if name in PR_ONLY and event != "pull_request":
            continue
        outputs = needs.get(scope_job, {}).get("outputs", {}) or {}
        wanted = outputs.get(key) == "true"
        if wanted and not (macos and not hosted_macos):
            found.append("%s: skipped although the scope asked for it" % name)
    for name in BOTH:
        if result.get(name) not in ("success", "skipped"):
            if result.get(name) not in ("failure", "cancelled"):
                found.append("%s: %s" % (name, result.get(name, "missing")))
    if policy_aware:
        found.extend(policy_problems(needs, event, policy, policy_parse_problem, policy_job))
    return found


def _read_policy(path: str, inline: str) -> Tuple[Any, str]:
    if inline:
        return _policy_json(inline)
    if not path:
        return None, ""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError:
        return None, "malformed policy result (unreadable file)"
    return _policy_json(text)


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Read the context from the process settings, print the verdict, and exit 1 when it must fail."""
    parser = argparse.ArgumentParser(description="The pr-checks aggregate verdict.")
    parser.add_argument("--policy-aware", action="store_true")
    parser.add_argument("--policy-job", default=POLICY_JOB)
    parser.add_argument("--policy-result", default="", metavar="PATH")
    cli = list(argv) if argv is not None else (sys.argv[1:] if __name__ == "__main__" else [])
    args = parser.parse_args(cli)
    settings = dict(os.environ)
    needs = json.loads(settings.get("NEEDS", "{}"))
    hosted_macos = settings.get("HOSTED_MACOS", "") == "on"
    event = settings.get("EVENT", "pull_request")
    aware = args.policy_aware or settings.get("POLICY_AWARE", "").lower() in ("1", "on", "true")
    result_path = args.policy_result or settings.get("POLICY_RESULT", "")
    inline = settings.get("POLICY_VERDICT", "")
    policy, parse_problem = _read_policy(result_path, inline)
    found = problems(
        needs,
        hosted_macos,
        event,
        policy=policy,
        policy_aware=aware,
        policy_parse_problem=parse_problem,
        policy_job=args.policy_job,
    )
    summary = " ".join("%s=%s" % (n, j.get("result")) for n, j in sorted(needs.items()))
    print("job results: %s" % summary)
    if found:
        print("pr-checks failed:")
        for line in found:
            print("  " + line)
        return 1
    print("pr-checks: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
