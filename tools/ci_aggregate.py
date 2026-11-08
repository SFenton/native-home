#!/usr/bin/env python3
"""The verdict of the `pr-checks` aggregate job (hosted CI, .agents/workflow/ci.md).

A job that was skipped passes only when it was allowed to skip: scope-gated jobs (`build-release*`, `swift-test*`) whose scope output
says there was nothing to run, hosted macOS jobs while the repo variable ``HOSTED_MACOS`` is not ``on``, the jobs of the other
visibility set, and the denylist scan on a fork pull request. A core job that should have run and was skipped fails the aggregate,
so a wrong ``if`` can never turn it green with nothing run. ``sim-smoke`` (the device Smoke plan, a matrix whose
single result is ``failure`` when any leg fails) is one of the gated jobs. Failed and cancelled jobs always fail.

    NEEDS='<toJSON(needs)>' PRIVATE=true|false HOSTED_MACOS=on|'' python3 tools/ci_aggregate.py

Stdlib only (macOS system Python 3.9 and Linux).
"""
from __future__ import annotations

import json
import os
import sys
from typing import Dict, List, Mapping

#: Jobs that must succeed while the repo is private / public.
CORE_PRIVATE = ("scope", "repo-checks")
CORE_PUBLIC = ("scope-hosted", "repo-checks-hosted", "tool-tests-hosted")
#: job -> (scope job that decides it, output key, hosted macOS?). Skipping is allowed when that output is not 'true'.
GATED = {
    "build-release": ("scope", "release", False),
    "swift-test": ("scope", "app", False),
    "build-release-hosted": ("scope-hosted", "release", True),
    "swift-test-hosted": ("scope-hosted", "app", True),
    "sim-smoke": ("scope-hosted", "app", True),
}
#: Jobs that run in both states; only a fork pull request skips the denylist scan.
BOTH = ("denylist-scan",)
OTHER_SET_PRIVATE = ("scope-hosted", "repo-checks-hosted", "tool-tests-hosted", "swift-test-hosted", "build-release-hosted", "sim-smoke")
OTHER_SET_PUBLIC = ("scope", "repo-checks", "build-release", "swift-test")


def problems(needs: Mapping[str, Mapping], private: bool, hosted_macos: bool) -> List[str]:
    """Why the aggregate must fail, one line per job; empty when it may pass."""
    result: Dict[str, str] = {name: str(job.get("result", "")) for name, job in needs.items()}
    found: List[str] = []
    for name, state in sorted(result.items()):
        if state in ("failure", "cancelled"):
            found.append("%s: %s" % (name, state))
    for name in (CORE_PRIVATE if private else CORE_PUBLIC):
        if result.get(name) != "success" and result.get(name) not in ("failure", "cancelled"):
            found.append("%s: %s (a core job that should run must succeed)" % (name, result.get(name, "missing")))
    other = OTHER_SET_PRIVATE if private else OTHER_SET_PUBLIC
    for name in GATED:
        if name not in other and name not in result:
            found.append("%s: missing from needs (the aggregate must list every gated job of the active set)" % name)
    for name, (scope_job, key, macos) in GATED.items():
        if name in other or name not in result or result[name] != "skipped":
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
    private = settings.get("PRIVATE", "") == "true"
    hosted_macos = settings.get("HOSTED_MACOS", "") == "on"
    found = problems(needs, private, hosted_macos)
    summary = " ".join("%s=%s" % (n, j.get("result")) for n, j in sorted(needs.items()))
    print("job results: %s" % summary)
    if found:
        print("pr-checks failed:")
        for line in found:
            print("  " + line)
        return 1
    print("pr-checks: ok (%s set)" % ("private" if private else "public"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
