#!/usr/bin/env python3
"""The verdict of the `pr-checks` aggregate job (hosted CI, .agents/workflow/ci.md).

A job that was skipped passes only when it was allowed to skip: scope-gated jobs (`macos-build`, `macos-test`,
`coverage-changed` (pull requests only), `build-release`) whose scope output says there was nothing to run, hosted macOS jobs while the repo variable ``HOSTED_MACOS`` is not ``on``, and the denylist
scan on a fork pull request. A core job that should have run and was skipped fails the aggregate,
so a wrong ``if`` can never turn it green with nothing run. A gated job missing from the workflow's ``needs`` fails it too, so dropping
one cannot let the aggregate pass blind. The macOS test matrix (`macos-test`, one leg per device family) runs the Smoke steps: a failed
leg fails the job. A matrix job's result is the worst of its legs. Failed and cancelled jobs always fail.

    NEEDS='<toJSON(needs)>' HOSTED_MACOS=on|'' EVENT=pull_request|push|... python3 tools/ci_aggregate.py

Stdlib only (macOS system Python 3.9 and Linux).
"""
from __future__ import annotations

import json
import os
import sys
from typing import Dict, List, Mapping

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


def problems(needs: Mapping[str, Mapping], hosted_macos: bool, event: str = "pull_request") -> List[str]:
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
    return found


def main() -> int:
    """Read the context from the process settings, print the verdict, and exit 1 when it must fail."""
    settings = dict(os.environ)
    needs = json.loads(settings.get("NEEDS", "{}"))
    hosted_macos = settings.get("HOSTED_MACOS", "") == "on"
    event = settings.get("EVENT", "pull_request")
    found = problems(needs, hosted_macos, event)
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
