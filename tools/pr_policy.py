#!/usr/bin/env python3
"""Base-trusted pull-request policy for agent, rule, grader and Jev changes.

The checkout containing this file is the trusted base.  The driver accepts a
separate clean base and head checkout, compares their exact trees, imports the
policy and evaluator only from the base, and emits one small JSON verdict.

    python3 BASE/tools/pr_policy.py --base-checkout BASE --head-checkout HEAD \
        --base-sha BASE_SHA --head-sha HEAD_SHA

Tier 0 runs locally from trusted code.  A changed Jev question deliberately
remains a ``hold`` until a trusted tier-1 result can be enforced without a
pull-request credential.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
SHA_RE = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
SCHEMA = 1

PASS = "pass"
FAIL = "fail"
HOLD = "hold"
NOOP = "noop"

# Only this positively identified, self-contained product tree can skip tier 0.
PRODUCT_PATHS = ("apple/**",)
# These extend the older lander separation set for neutral roles and executable
# routing, runner and adapter inputs.
EXTRA_BEHAVIOUR_PATHS = (
    ".claude/**",
    ".agents/**",
    "agents/roles/**",
    "tools/triage/**",
    "tools/**/*runner*.py",
    "tools/**/*adapter*.py",
)
EXTRA_EVAL_PATHS: Tuple[str, ...] = ()

Change = Tuple[str, str, str, str]


class PolicyError(Exception):
    """A policy failure represented by an enumerated verdict reason."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def _git(checkout: Path, *args: str, text: bool = True) -> subprocess.CompletedProcess:
    """Run one read-only Git plumbing command with repository hooks disabled."""
    safe = ("-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
            "-c", "protocol.ext.allow=never")
    env = dict(os.environ)
    env.update({"GIT_NO_REPLACE_OBJECTS": "1", "GIT_TERMINAL_PROMPT": "0"})
    env.pop("LANE_LAND", None)
    return subprocess.run(
        ["git", "-C", str(checkout), *safe, *args],
        capture_output=True,
        text=text,
        env=env,
    )


def verify_checkout(path: Path, expected: str, label: str) -> str:
    """Return the clean checkout's exact commit after verifying its advertised SHA."""
    checkout = path.resolve()
    if not checkout.is_dir() or not (checkout / ".git").exists():
        raise PolicyError(f"{label}_checkout_unreadable")
    inside = _git(checkout, "rev-parse", "--is-inside-work-tree")
    head = _git(checkout, "rev-parse", "--verify", "-q", "HEAD^{commit}")
    if inside.returncode != 0 or inside.stdout.strip() != "true" or head.returncode != 0:
        raise PolicyError(f"{label}_checkout_unreadable")
    actual = head.stdout.strip()
    if not SHA_RE.fullmatch(actual):
        raise PolicyError(f"{label}_sha_unreadable")
    if expected and (not SHA_RE.fullmatch(expected.lower()) or expected.lower() != actual):
        raise PolicyError(f"{label}_sha_mismatch")
    status = _git(checkout, "status", "--porcelain=v1", "--untracked-files=all")
    if status.returncode != 0 or status.stdout:
        raise PolicyError(f"{label}_checkout_dirty")
    return actual


def _object_dir(checkout: Path) -> Path:
    common = _git(checkout, "rev-parse", "--git-common-dir")
    if common.returncode != 0:
        raise PolicyError("git_objects_unreadable")
    result = Path(common.stdout.strip())
    if not result.is_absolute():
        result = checkout / result
    result = (result / "objects").resolve()
    if not result.is_dir():
        raise PolicyError("git_objects_unreadable")
    return result


def trusted_object_repo(base: Path, head: Path) -> "TemporaryObjectRepo":
    """A temporary Git view that can read base and head objects without checkout code."""
    return TemporaryObjectRepo(base, head)


class TemporaryObjectRepo:
    """A temporary repository whose object database exposes two read-only inputs."""

    def __init__(self, base: Path, head: Path):
        import tempfile

        self._temporary = tempfile.TemporaryDirectory(prefix="pr-policy-objects-")
        self.path = Path(self._temporary.name)
        initialized = _git(self.path, "init", "-q")
        if initialized.returncode != 0:
            self.close()
            raise PolicyError("git_objects_unreadable")
        alternates = self.path / ".git" / "objects" / "info" / "alternates"
        try:
            alternates.write_text(
                f"{_object_dir(base)}\n{_object_dir(head)}\n",
                encoding="utf-8",
            )
        except OSError as exc:
            self.close()
            raise PolicyError("git_objects_unreadable") from exc

    def close(self) -> None:
        self._temporary.cleanup()

    def __enter__(self) -> "TemporaryObjectRepo":
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()


def _tree(checkout: Path, sha: str) -> Dict[str, Tuple[str, str, str]]:
    proc = _git(checkout, "ls-tree", "-rz", "--full-tree", sha, text=False)
    if proc.returncode != 0:
        raise PolicyError("scope_unreadable")
    rows: Dict[str, Tuple[str, str, str]] = {}
    for raw in proc.stdout.split(b"\0"):
        if not raw:
            continue
        try:
            meta, raw_path = raw.split(b"\t", 1)
            mode, kind, oid = meta.decode("ascii").split()
            path = raw_path.decode("utf-8")
        except (ValueError, UnicodeDecodeError) as exc:
            raise PolicyError("scope_unreadable") from exc
        if "\n" in path or "\t" in path or path.startswith("/") or ".." in path.split("/"):
            raise PolicyError("scope_unreadable")
        rows[path] = (mode, kind, oid)
    return rows


def changed_paths(base: Path, base_sha: str, head: Path, head_sha: str) -> List[Change]:
    """Return a complete, no-renames base-to-head diff, with both rename sides."""
    before, after = _tree(base, base_sha), _tree(head, head_sha)
    rows: List[Change] = []
    for path in sorted(before.keys() | after.keys()):
        old, new = before.get(path), after.get(path)
        if old == new:
            continue
        if old is None:
            rows.append(("A", path, "", str(new[2])))
        elif new is None:
            rows.append(("D", path, str(old[2]), ""))
        else:
            rows.append(("T" if old[:2] != new[:2] else "M", path, old[2], new[2]))
    return rows


def load_tool(base: Path, name: str) -> Any:
    """Import one trusted module from the base checkout."""
    path = base / "tools" / f"{name}.py"
    if not path.is_file():
        raise PolicyError("trusted_tool_unreadable")
    spec = importlib.util.spec_from_file_location(f"pr_policy_{name}", path)
    if spec is None or spec.loader is None:
        raise PolicyError("trusted_tool_unreadable")
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except (ImportError, OSError, SyntaxError, ValueError) as exc:
        raise PolicyError("trusted_tool_unreadable") from exc
    return module


def _check_separation(lander: Any, rows: Sequence[Change]) -> None:
    try:
        lander.check_separation(rows)
    except lander.Refused as exc:
        raise PolicyError("trusted_separation") from exc
    paths = [path for _status, path, _old, _new in rows]
    behaviour = lander.BEHAVIOUR_PATHS + EXTRA_BEHAVIOUR_PATHS
    evaluation = lander.EVAL_PATHS + EXTRA_EVAL_PATHS
    if any(lander.matches(path, behaviour) for path in paths) and \
            any(lander.matches(path, evaluation) for path in paths):
        raise PolicyError("trusted_separation")


def _run_prechecks(lander: Any, objects: TemporaryObjectRepo, rows: Sequence[Change],
                   head_sha: str) -> None:
    _check_separation(lander, rows)
    try:
        lander.check_paths(rows, (), lander.DEFAULT_APPEND_ONLY)
    except lander.Refused as exc:
        raise PolicyError("append_only") from exc
    try:
        lander.check_jev_thresholds(objects.path, rows)
    except lander.Refused as exc:
        raise PolicyError("jev_threshold") from exc
    try:
        lander.check_retired(objects.path, head_sha, rows)
    except lander.Refused as exc:
        raise PolicyError("retirement_invalid") from exc


def _retirement_agreement(lander: Any, evaluator: Any, base: Path, head: Path,
                          rows: Sequence[Change]) -> None:
    own = base / "evals" / "agents" / "routing-replay" / "cases"
    base_active = {path.name: path for path in evaluator.case_files(own)}
    moved = {
        Path(old).name
        for old, _new in lander.retire_moves(rows)
        if f"evals/agents/routing-replay/cases/{Path(old).name}" == old
        and Path(old).name in base_active
    }
    _active, classified_retired = evaluator.tier0_sets(base, head)
    classified = {path.name for path in classified_retired if path.name in base_active}
    if moved != classified:
        raise PolicyError("retirement_mismatch")


def _suite_map(evaluator: Any, suites: Any) -> Dict[str, Dict[str, Any]]:
    if not isinstance(suites, list):
        raise PolicyError("tier0_malformed")
    found: Dict[str, Dict[str, Any]] = {}
    for suite in suites:
        if not isinstance(suite, dict) or not isinstance(suite.get("name"), str):
            raise PolicyError("tier0_malformed")
        name = suite["name"]
        if name in found or not isinstance(suite.get("cases"), int) or \
                not isinstance(suite.get("failures"), list):
            raise PolicyError("tier0_malformed")
        if suite["cases"] < 0:
            raise PolicyError("tier0_malformed")
        found[name] = suite
    required = {evaluator.SUITE, evaluator.RETIRED_SUITE}
    if set(found) != required:
        raise PolicyError("tier0_missing_summary")
    return found


def _active_failures(suite: Dict[str, Any]) -> Set[str]:
    failures: Set[str] = set()
    for row in suite.get("failures", []):
        if not isinstance(row, (list, tuple)) or not row or not isinstance(row[0], str):
            raise PolicyError("tier0_malformed")
        failures.add(row[0])
    return failures


def _run_tier0(evaluator: Any, base: Path, head: Path) -> None:
    try:
        base_suites = evaluator.evaluate(base, tier=0, target=base)
        head_suites = evaluator.evaluate(base, tier=0, target=head)
    except (OSError, RuntimeError, ValueError) as exc:
        raise PolicyError("tier0_unavailable") from exc
    base_map, head_map = _suite_map(evaluator, base_suites), _suite_map(evaluator, head_suites)
    base_total = sum(suite["cases"] for suite in base_map.values())
    head_total = sum(suite["cases"] for suite in head_map.values())
    if head_total < base_total:
        raise PolicyError("tier0_lost_count")
    base_failures = _active_failures(base_map[evaluator.SUITE])
    head_failures = _active_failures(head_map[evaluator.SUITE])
    if head_failures - base_failures:
        raise PolicyError("tier0_new_failure")


def _verdict(base_sha: str, head_sha: str, outcome: str, reasons: Sequence[str]) -> Dict[str, Any]:
    return {
        "schema": SCHEMA,
        "outcome": outcome,
        "reasons": sorted(set(reasons)),
        "base_sha": base_sha,
        "head_sha": head_sha,
    }


def evaluate_policy(base: Path, head: Path, base_sha: str = "", head_sha: str = "") -> Dict[str, Any]:
    """Evaluate one pull request and return a diff-independent machine verdict."""
    base, head = base.resolve(), head.resolve()
    if base == head or base != ROOT:
        raise PolicyError("driver_not_base")
    actual_base = verify_checkout(base, base_sha, "base")
    actual_head = verify_checkout(head, head_sha, "head")
    lander, evaluator = load_tool(base, "lane_land"), load_tool(base, "agent_eval")
    rows = changed_paths(base, actual_base, head, actual_head)
    with trusted_object_repo(base, head) as objects:
        _run_prechecks(lander, objects, rows, actual_head)
        _retirement_agreement(lander, evaluator, base, head, rows)
    if not rows:
        return _verdict(actual_base, actual_head, PASS, ("no_changes",))
    if all(lander.matches(path, PRODUCT_PATHS) for _s, path, _o, _n in rows):
        return _verdict(actual_base, actual_head, NOOP, ("product_only",))
    _run_tier0(evaluator, base, head)
    verify_checkout(base, actual_base, "base")
    verify_checkout(head, actual_head, "head")
    changed_questions = any(
        lander.matches(path, (lander.JEV_QUESTIONS,))
        for _status, path, _old, _new in rows
    )
    if changed_questions:
        return _verdict(actual_base, actual_head, HOLD, ("tier1_required",))
    return _verdict(actual_base, actual_head, PASS, ("tier0_pass",))


def _write(path: Optional[str], verdict: Dict[str, Any]) -> None:
    text = json.dumps(verdict, sort_keys=True, separators=(",", ":"))
    print(text)
    if not path:
        return
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text + "\n", encoding="utf-8")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Base-trusted pull-request policy.")
    parser.add_argument("--base-checkout", "--base", dest="base", required=True, type=Path)
    parser.add_argument("--head-checkout", "--head", dest="head", required=True, type=Path)
    parser.add_argument("--base-sha", default="")
    parser.add_argument("--head-sha", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args(argv)
    verdict: Dict[str, Any]
    try:
        verdict = evaluate_policy(args.base, args.head, args.base_sha, args.head_sha)
    except PolicyError as exc:
        try:
            base_sha = verify_checkout(args.base.resolve(), args.base_sha, "base")
            head_sha = verify_checkout(args.head.resolve(), args.head_sha, "head")
        except PolicyError:
            base_sha = head_sha = ""
        verdict = _verdict(base_sha, head_sha, FAIL, (exc.reason,))
    except Exception:
        print("pr_policy: internal policy failure", file=sys.stderr)
        verdict = _verdict("", "", FAIL, ("policy_internal",))
    _write(args.out or None, verdict)
    return 0 if verdict["outcome"] in (PASS, NOOP) else 1


if __name__ == "__main__":
    sys.exit(main())
