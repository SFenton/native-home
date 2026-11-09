#!/usr/bin/env python3
"""Does the live ruleset on main make GitHub the merge gate? Auto-merge is armed only when it does (fails closed).

The gate is the ruleset `main-checks` (.agents/workflow/ci.md#merge-gate): at least one approving review and the required check
`pr-checks`. ``tools/ship.sh`` and ``tools/hooks/merge_guard.py`` arm or allow `gh pr merge N --auto --squash` only while both rules
are live on the branch; if `gh api` fails, or either rule is missing, nothing is armed.

    ruleset_gate.py [--repo OWNER/NAME] [--branch main]    exit 0 when both rules are live, 1 when not, 2 on a usage error

Stdlib only (macOS system Python 3.9 and Linux).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from typing import Callable, List, Optional, Sequence

#: The check GitHub requires before a merge: the aggregate job of pr-checks.yml.
REQUIRED_CHECK = "pr-checks"
GH_TIMEOUT = 20


def fetch_rules(repo: str, branch: str = "main") -> object:
    """The rules in force on ``branch`` (all active rulesets, flattened by GitHub), parsed from `gh api`; raises on any failure."""
    out = subprocess.run(["gh", "api", f"repos/{repo}/rules/branches/{branch}"], capture_output=True, text=True,
                         timeout=GH_TIMEOUT, check=True).stdout
    return json.loads(out)


def problems(rules: object) -> List[str]:
    """Why the rules do not make GitHub the gate, one line each; empty when an approval and the `pr-checks` check are both required."""
    if not isinstance(rules, list):
        return ["the rules could not be read (unexpected answer)"]
    approvals = 0
    contexts = set()
    for rule in rules:
        if not isinstance(rule, dict):
            continue
        params = rule.get("parameters") or {}
        if rule.get("type") == "pull_request":
            approvals = max(approvals, int(params.get("required_approving_review_count") or 0))
        elif rule.get("type") == "required_status_checks":
            contexts.update(str(check.get("context")) for check in params.get("required_status_checks") or [] if isinstance(check, dict))
    found: List[str] = []
    if approvals < 1:
        found.append("the ruleset does not require an approving review")
    if REQUIRED_CHECK not in contexts:
        found.append("the ruleset does not require the %s check" % REQUIRED_CHECK)
    return found


def check(repo: str, branch: str = "main", fetch: Optional[Callable[[str, str], object]] = None) -> List[str]:
    """``problems`` for the live rules of ``repo``; a failed fetch is a problem (fails closed)."""
    try:
        rules = (fetch or fetch_rules)(repo, branch)
    except Exception as error:  # noqa: BLE001 - any failure means "do not arm"
        return ["the rules of %s could not be fetched (%s)" % (repo, type(error).__name__)]
    return problems(rules)


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Print the verdict; exit 0 when both rules are live, 1 otherwise."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--repo", default="SFenton/native-home")
    parser.add_argument("--branch", default="main")
    args = parser.parse_args(argv)
    found = check(args.repo, args.branch)
    if found:
        print("ruleset_gate: not arming auto-merge on %s:" % args.repo)
        for line in found:
            print("  " + line)
        return 1
    print("ruleset_gate: %s requires an approval and %s" % (args.repo, REQUIRED_CHECK))
    return 0


if __name__ == "__main__":
    sys.exit(main())
