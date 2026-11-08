#!/usr/bin/env python3
"""The verdict of the `pr-checks` aggregate job (hosted CI, .agents/workflow/ci.md).

A job that was skipped passes only when it was allowed to skip: scope-gated jobs (`build-release-hosted`, `swift-test-hosted`) whose
scope output says there was nothing to run, hosted macOS jobs while the repo variable ``HOSTED_MACOS`` is not ``on``, and the denylist
scan on a fork pull request. A core job that should have run and was skipped fails the aggregate,
so a wrong ``if`` can never turn it green with nothing run. Failed and cancelled jobs always fail.

    NEEDS='<toJSON(needs)>' HOSTED_MACOS=on|'' python3 tools/ci_aggregate.py

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
    "build-release-hosted": ("scope", "release", True),
    "swift-test-hosted": ("scope", "app", True),
}
#: Jobs that only a fork pull request skips.
BOTH = ("denylist-scan",)


def problems(needs: Mapping[str, Mapping], hosted_macos: bool) -> List[str]:
    """Why the aggregate must fail, one line per job; empty when it may pass."""
    result: Dict[str, str] = {name: str(job.get("result", "")) for name, job in needs.items()}
    found: List[str] = []
    for name, state in sorted(result.items()):
        if state in ("failure", "cancelled"):
            found.append("%s: %s" % (name, state))
    for name in CORE:
        if result.get(name) != "success" and result.get(name) not in ("failure", "cancelled"):
            found.append("%s: %s (a core job that should run must succeed)" % (name, result.get(name, "missing")))
    for name, (scope_job, key, macos) in GATED.items():
        if name not in result or result[name] != "skipped":
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
    found = problems(needs, hosted_macos)
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
