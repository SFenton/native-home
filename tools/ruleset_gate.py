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
from datetime import datetime, timezone
from typing import Callable, Dict, List, Optional, Sequence, Tuple

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


def utc(stamp: object) -> Optional[datetime]:
    """A GitHub timestamp (``...Z`` or with an offset, optional milliseconds) as an aware UTC datetime; None when it is not one."""
    if not isinstance(stamp, str) or not stamp:
        return None
    text = stamp.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        moment = datetime.fromisoformat(text)
    except ValueError:
        return None
    return (moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)).astimezone(timezone.utc)


def live_requirements(repo: str, branch: str = "main", fetch: Optional[Callable[[str, str], object]] = None,
                      fetch_one: Optional[Callable[[str, object], object]] = None) -> Dict[str, object]:
    """What the live rules on ``branch`` demand of a merge, for the verifier that vets a range of merged pull requests.

    Returns ``{contexts, updated_at, problems}``: ``contexts`` is every required status check as ``(name, integration_id)``
    (never hardcoded), ``updated_at`` the newest ``updated_at`` of those rulesets as an aware UTC datetime (None when unknown), and
    ``problems`` why the rules are not a gate (``check``'s findings, plus: no required checks, a ruleset that is not active, an
    unreadable ``updated_at``). Bypass actors are NOT a condition: the agent login cannot read them (GitHub hides the list), so a
    "none" would verify nothing; the per-commit evidence is the authority. Any failure is a problem; this never raises. ``check``
    and its exit codes are unchanged.
    """
    out: Dict[str, object] = {"contexts": [], "updated_at": None, "problems": []}
    try:
        rules = (fetch or fetch_rules)(repo, branch)
        listed = rules if isinstance(rules, list) else []
        ids = sorted({str(r["ruleset_id"]) for r in listed if isinstance(r, dict) and r.get("ruleset_id") is not None})
        rulesets = {ruleset_id: (fetch_one or fetch_ruleset)(repo, ruleset_id) for ruleset_id in ids}
        found = list(problems(rules, rulesets))
        contexts: List[Tuple[str, object]] = []
        for rule in listed:
            if isinstance(rule, dict) and rule.get("type") == "required_status_checks":
                for item in (rule.get("parameters") or {}).get("required_status_checks") or []:
                    pair = (str(item.get("context")), item.get("integration_id"))
                    if pair not in contexts:
                        contexts.append(pair)
        if not contexts:
            found.append("the ruleset requires no status check")
        newest: Optional[datetime] = None
        for ruleset_id, answer in rulesets.items():
            answer = answer if isinstance(answer, dict) else {}
            if answer.get("enforcement") != "active":
                found.append("the ruleset %s is not active" % ruleset_id)
            moment = utc(answer.get("updated_at"))
            if moment is None:
                found.append("the ruleset %s has no readable updated_at" % ruleset_id)
            elif newest is None or moment > newest:
                newest = moment
        out.update(contexts=contexts, updated_at=newest, problems=found)
    except Exception as error:  # noqa: BLE001 - any failure means "not a gate"
        out["problems"] = ["the rules of %s could not be read (%s)" % (repo, type(error).__name__)]
    return out


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
