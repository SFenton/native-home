#!/usr/bin/env python3
"""Does the live ruleset on main make GitHub the merge gate? Auto-merge is armed only when it does (fails closed).

The gate is the ruleset `main-checks` (.agents/workflow/ci.md#merge-gate): a pull request is required (squash allowed, any approval count:
review happens before the push, see ``tools/review_verdict.py``), the required check `pr-checks` comes from GitHub Actions, and nothing bypasses it.
``tools/ship.sh`` and ``tools/hooks/merge_guard.py`` arm or allow the pinned auto-merge (squash, matched to the reviewed head) only while all of
that is live on the branch; if `gh api` fails, or any of it is missing, nothing is armed.

    ruleset_gate.py [--repo OWNER/NAME] [--branch main]    exit 0 when the gate is live, 1 when not, 2 on a usage error

Stdlib only (macOS system Python 3.9 and Linux).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from typing import Callable, Dict, List, Optional, Sequence

#: The check GitHub requires before a merge: the aggregate job of pr-checks.yml.
REQUIRED_CHECK = "pr-checks"
#: GitHub Actions app id: only it may report `pr-checks`.
REQUIRED_INTEGRATION = 15368
GH_TIMEOUT = 20


def fetch_rules(repo: str, branch: str = "main") -> object:
    """The rules in force on ``branch`` (all active rulesets, flattened by GitHub), parsed from `gh api`; raises on any failure."""
    out = subprocess.run(["gh", "api", f"repos/{repo}/rules/branches/{branch}"], capture_output=True, text=True,
                         timeout=GH_TIMEOUT, check=True).stdout
    return json.loads(out)


def fetch_ruleset(repo: str, ruleset_id: object) -> object:
    """One ruleset (`GET rulesets/ID`, which carries ``current_user_can_bypass``), parsed from `gh api`; raises on any failure."""
    out = subprocess.run(["gh", "api", f"repos/{repo}/rulesets/{int(str(ruleset_id))}"], capture_output=True, text=True,
                         timeout=GH_TIMEOUT, check=True).stdout
    return json.loads(out)


def problems(rules: object, rulesets: Optional[Dict[str, object]] = None) -> List[str]:
    """Why the rules do not make GitHub the gate, one line each; empty when everything below holds.

    The gate needs a ``pull_request`` rule (no approval count: the reviewer's pass is checked before the push; if the rule lists
    ``allowed_merge_methods`` it must include ``squash``), the `pr-checks` check bound to GitHub Actions (``integration_id`` 15368, so no
    token can post a status of that name) and ``current_user_can_bypass == "never"`` on each ruleset that carries those rules
    (``rulesets`` maps a ruleset id to its `GET rulesets/ID` answer). Malformed shapes raise; ``check`` turns that into a problem.
    """
    if not isinstance(rules, list):
        return ["the rules could not be read (unexpected answer)"]
    pull_request = False
    squash = True
    bound = False
    ids: List[str] = []
    for rule in rules:
        if not isinstance(rule, dict):
            continue
        params = rule.get("parameters") or {}
        kind = rule.get("type")
        if kind not in ("pull_request", "required_status_checks"):
            continue
        if rule.get("ruleset_id") is not None and str(rule["ruleset_id"]) not in ids:
            ids.append(str(rule["ruleset_id"]))
        if kind == "pull_request":
            pull_request = True
            methods = params.get("allowed_merge_methods")
            if methods is not None and "squash" not in methods:
                squash = False
        else:
            for item in params.get("required_status_checks") or []:
                if item.get("context") == REQUIRED_CHECK and item.get("integration_id") == REQUIRED_INTEGRATION:
                    bound = True
    found: List[str] = []
    if not pull_request:
        found.append("the ruleset does not require a pull request")
    if not squash:
        found.append("the ruleset does not allow squash merges")
    if not bound:
        found.append("the ruleset does not require the %s check from GitHub Actions (integration %d)" % (REQUIRED_CHECK, REQUIRED_INTEGRATION))
    if rulesets is not None:
        if not ids:
            found.append("the ruleset id is unknown, so bypass cannot be checked")
        for ruleset_id in ids:
            answer = rulesets.get(ruleset_id)
            if not isinstance(answer, dict) or answer.get("current_user_can_bypass") != "never":
                found.append("the ruleset %s can be bypassed (current_user_can_bypass is not 'never')" % ruleset_id)
    return found


def check(repo: str, branch: str = "main", fetch: Optional[Callable[[str, str], object]] = None,
          fetch_one: Optional[Callable[[str, object], object]] = None) -> List[str]:
    """``problems`` for the live rules of ``repo``; any failure or malformed answer is a problem (fails closed, never raises)."""
    try:
        rules = (fetch or fetch_rules)(repo, branch)
        ids = {str(r["ruleset_id"]) for r in rules if isinstance(r, dict) and r.get("ruleset_id") is not None} if isinstance(rules, list) else set()
        rulesets = {ruleset_id: (fetch_one or fetch_ruleset)(repo, ruleset_id) for ruleset_id in sorted(ids)}
        return problems(rules, rulesets)
    except Exception as error:  # noqa: BLE001 - any failure means "do not arm"
        return ["the rules of %s could not be read (%s)" % (repo, type(error).__name__)]


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Print the verdict; exit 0 when the gate is live, 1 otherwise."""
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
    print("ruleset_gate: %s requires a pull request and %s from GitHub Actions and allows no bypass" % (args.repo, REQUIRED_CHECK))
    return 0


if __name__ == "__main__":
    sys.exit(main())
