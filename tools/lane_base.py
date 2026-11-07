#!/usr/bin/env python3
"""The branch a lane's work came from: the base of the per-change test tier, and the failures that base already has.

``lane_base.py``           print the base ref for the current branch
``lane_base.py --why``     also print which rule chose it
``lane_base.py --sha``     print the merge-base commit of that ref and HEAD

Resolution order (first hit wins; a ref that does not exist is skipped silently):

1. ``FENTON_AFFECTED_BASE``
2. the open pull request's base branch (``gh pr view --json baseRefName``, 10 s, any error skips it)
3. a recorded parent: ``git config branch.<name>.sh-base`` (``tools/lane_new.sh`` writes it; any other way of creating a
   worktree records it with ``git config branch.$(git branch --show-current).sh-base origin/<parent>``)
4. the nearest long-lived branch: the remote default branch plus ``product_base`` and ``workflow_base`` of
   ``tools/triage/config.json`` (read-only; the one place to edit when a long-lived branch is added or retired);
   the one whose merge-base with HEAD is fewest commits behind HEAD wins, a tie goes to the default branch
5. the remote default branch (``origin/HEAD``)

Base failures (``build/baselines/<base-sha>.json`` in the main checkout) are INFORMATIONAL: they never change a pass or a
fail, and no script's exit status depends on them::

    lane_base.py baseline summary --command CMD --log FILE   print inherited / new / unaccounted failures; always exits 0
    lane_base.py baseline record  --command CMD --log FILE   only with HEAD at the base commit (clean tree), ids from the log
    lane_base.py baseline show    [--sha SHA]

A log with a crash, an unnamed failure or a count mismatch is reported "Unaccounted" (``parse_log``). With ``--command
ios_uitest`` the log is split by family (``== iphone:`` / ``===== ipad`` headers) and ids are keyed ``family:Class.test``.
A summary on the base commit itself records its failures as the baseline.
Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
CONFIG = "tools/triage/config.json"  # the one place that names the long-lived branches: workflow_base and product_base
CONFIG_KEYS = ("product_base", "workflow_base")
XC_FAILED = re.compile(r"Test Case '(?:-\[([\w.]+) (\w+)\]|([\w.]+)\.(\w+))' failed")
XC_ERROR = re.compile(r"error: (?:-\[([\w.]+) (\w+)\]|([\w.]+)\.(\w+)) : ")
XC_SUITE = re.compile(r"Test Suite '(.+?)' (?:passed|failed) at")
XC_EXECUTED = re.compile(r"Executed \d+ tests?, with (?:\d+ tests? skipped and )?(\d+) failures?")
ST_FAILED = re.compile(r"(?:^|\W)Test (?!run with )(.+?) failed after [\d.]+ seconds(?: with (\d+) issues?)?")
ST_RUN = re.compile(r"(?:^|\W)Test run with \d+ tests?(?: in \d+ suites?)? failed after [\d.]+ seconds with (\d+) issues?")
NOT_A_TEST_FAILURE = re.compile(
    r"Exited with|unexpected signal|Restarting after unexpected exit|Crash:|^(?:GAP|EMPTY|INFRA|ERROR):|\.swift:\d+:\d+: error:",
    re.M)


def git(*args: str, root: Path = ROOT) -> str:
    """Run git in ``root``; stdout, or empty on failure."""
    result = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def exists(ref: str, root: Path = ROOT) -> bool:
    """Whether ``ref`` names a commit."""
    return bool(ref) and bool(git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}", root=root))


def as_ref(branch: str, root: Path = ROOT) -> Optional[str]:
    """``origin/<branch>`` when it exists, else the local ``<branch>``, else ``None`` (a ``origin/x`` name stays as given)."""
    branch = branch.strip()
    for ref in ([branch] if branch.startswith("origin/") else [f"origin/{branch}", branch]):
        if exists(ref, root):
            return ref
    return None


def default_branch(root: Path = ROOT) -> Optional[str]:
    """The remote default branch as a ref (``origin/main``)."""
    head = git("symbolic-ref", "--quiet", "refs/remotes/origin/HEAD", root=root)
    if head:
        return head.replace("refs/remotes/", "", 1)
    return next((ref for ref in ("origin/main", "origin/master") if exists(ref, root)), None)


def long_lived(root: Path = ROOT) -> List[str]:
    """The long-lived branches ``tools/triage/config.json`` names (``product_base``, ``workflow_base``); empty when the file is missing."""
    try:
        data = json.loads((root / CONFIG).read_text())
    except (OSError, ValueError):
        return []
    return [data[key] for key in CONFIG_KEYS if isinstance(data.get(key), str)]


def pr_base(root: Path = ROOT) -> Optional[str]:
    """The base branch of the open pull request for HEAD's branch, or ``None`` (no PR, no ``gh``, offline, slow)."""
    try:
        out = subprocess.run(["gh", "pr", "view", "--json", "baseRefName", "-q", ".baseRefName"], cwd=root,
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return (out.stdout.strip() or None) if out.returncode == 0 else None


def distance(ref: str, root: Path = ROOT) -> int:
    """Commits on HEAD since it left ``ref`` (large when there is no merge-base)."""
    point = git("merge-base", ref, "HEAD", root=root)
    count = git("rev-list", "--count", f"{point}..HEAD", root=root) if point else ""
    return int(count) if count.isdigit() else 10 ** 9


def resolve(root: Path = ROOT, env: Optional[Dict[str, str]] = None,
            pr: Callable[[Path], Optional[str]] = pr_base) -> Tuple[str, str]:
    """``(ref, why)``: the base ref for HEAD's branch and the rule that chose it. Raises ``LookupError`` when nothing resolves."""
    env = os.environ if env is None else env
    given = env.get("FENTON_AFFECTED_BASE", "")
    if given:  # an explicit choice is taken as given
        return given, "FENTON_AFFECTED_BASE"
    base = pr(root)
    ref = as_ref(base, root) if base else None
    if ref:
        return ref, f"open PR base ({base})"
    branch = git("rev-parse", "--abbrev-ref", "HEAD", root=root)
    parent = git("config", "--get", f"branch.{branch}.sh-base", root=root) if branch and branch != "HEAD" else ""
    ref = as_ref(parent, root) if parent else None
    if ref:
        return ref, f"recorded parent (branch.{branch}.sh-base)"
    default = default_branch(root)
    candidates = [default] if default else []
    candidates += [ref for ref in (as_ref(name, root) for name in long_lived(root)) if ref and ref not in candidates]
    if candidates:
        nearest = min(candidates, key=lambda ref: distance(ref, root))  # min is stable: the default branch wins ties
        return nearest, f"nearest long-lived branch (of {', '.join(candidates)})"
    raise LookupError("no base ref: set FENTON_AFFECTED_BASE or fetch origin")


def base_ref(root: Path = ROOT) -> str:
    """The base ref (what ``affected_tests.py`` diffs against)."""
    return resolve(root)[0]


def merge_base(root: Path = ROOT, ref: Optional[str] = None) -> str:
    """The commit SHA where HEAD left the base (the key of the baseline store)."""
    ref = ref or base_ref(root)
    return git("merge-base", ref, "HEAD", root=root) or git("rev-parse", ref, root=root)


# MARK: - Base failures

def store_dir(root: Path = ROOT) -> Path:
    """``build/baselines`` of the main checkout, shared by every worktree."""
    common = git("rev-parse", "--git-common-dir", root=root)
    main = (root / common).resolve().parent if common else root
    return main / "build" / "baselines"


def load(sha: str, root: Path = ROOT) -> Dict:
    """The record for a base commit (empty shape when none)."""
    try:
        data = json.loads((store_dir(root) / f"{sha}.json").read_text())
    except (OSError, ValueError):
        data = {}
    data.setdefault("commands", {})
    data.setdefault("candidates", {})
    return data


def save(sha: str, data: Dict, root: Path = ROOT) -> None:
    """Write the record for a base commit."""
    path = store_dir(root) / f"{sha}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def parse_log(text: str) -> Tuple[List[str], Optional[str]]:
    """``(ids, problem)``: the failed tests in an XCTest or Swift Testing log, and why the list cannot be trusted (or ``None``).

    A log is *accounted* only when every failure is named and the counts agree with the runner's own totals
    (XCTest ``Executed N tests, with M failures``, Swift Testing ``Test run … with K issues``). A crash, restart, signal
    exit, GAP/EMPTY/INFRA line, compile error, or any count mismatch is a ``problem``: nothing may be subtracted.
    """
    if NOT_A_TEST_FAILURE.search(text):
        return [], "the log shows a crash, restart, infra line or compile error"
    ids = set()
    xc_cases = {f"{m[0] or m[2]}.{m[1] or m[3]}" for m in XC_FAILED.findall(text)}
    errors = XC_ERROR.findall(text)
    totals, last_suite = [], ""
    for line in text.splitlines():
        suite = XC_SUITE.search(line)
        if suite:
            last_suite = suite.group(1)
        executed = XC_EXECUTED.search(line)
        if executed:
            totals.append((last_suite, int(executed.group(1))))
            last_suite = ""
    top = [n for suite, n in totals if suite in ("All tests", "Selected tests")] or [n for suite, n in totals if suite.endswith(".xctest")]
    reported = sum(top) if top else None
    if xc_cases or errors or reported:
        if reported is None:
            return [], "XCTest failures without a totals line to check them against"
        if reported != len(errors) or not xc_cases or any(f"{e[0] or e[2]}.{e[1] or e[3]}" not in xc_cases for e in errors):
            return [], f"XCTest failures do not match the runner's total ({len(errors)} named, {reported} reported)"
        ids |= xc_cases
    st = [(name, int(n or 0)) for name, n in ST_FAILED.findall(text) if not name.startswith("Suite ") and "run with" not in name]
    runs = [int(k) for k in ST_RUN.findall(text)]
    if st or runs:
        if not runs or not st or sum(n for _, n in st) != sum(runs) or any(n == 0 for _, n in st):
            return [], "Swift Testing failures do not match the run summary's issue count"
        ids |= {f"swift-testing:{name}" for name, _ in st}
    return sorted(ids), None


def at_base(root: Path = ROOT, ref: Optional[str] = None) -> bool:
    """Whether HEAD *is* the merge-base commit (no commits ahead) with a clean tree: a run here is a run on the base."""
    return (git("rev-parse", "HEAD", root=root) == merge_base(root, ref) and not git("status", "--porcelain", root=root))


def record(command: str, ids: Iterable[str], root: Path = ROOT, sha: Optional[str] = None, merge: bool = False) -> str:
    """Record the failing ids of ``command`` on the base commit; returns the SHA.

    Refuses (``PermissionError``) unless HEAD is exactly that commit with a clean tree: ids come only from a run on the base.
    """
    ref = base_ref(root)
    sha = sha or merge_base(root, ref)
    if not at_base(root, ref) or git("rev-parse", "HEAD", root=root) != sha:
        raise PermissionError(f"HEAD is not the base commit {sha[:9]} (clean): run on the base commit to record its failures")
    data = load(sha, root)
    old = set(data["commands"].get(command, {}).get("failing", [])) if merge else set()
    data["commands"][command] = {"failing": sorted(old | set(ids)), "recorded": int(time.time())}
    data["base"] = ref
    save(sha, data, root)
    return sha


FAMILY_HEADER = re.compile(r"^(?:=====|==) (iphone|duo|ipad)\b", re.M)


def split_families(text: str) -> Dict[str, str]:
    """A whole-run journey log split into per-family sections by its headers (``{"": text}`` when it has none)."""
    marks = [(m.start(), m.group(1)) for m in FAMILY_HEADER.finditer(text)]
    if not marks:
        return {"": text}
    out: Dict[str, str] = {}
    for i, (start, family) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        out[family] = out.get(family, "") + text[start:end]
    return out


def summarize(command: str, text: str, root: Path = ROOT, ref: Optional[str] = None) -> List[str]:
    """Informational lines for a finished run's log: inherited failures, new failures, unaccounted ones. Never a verdict."""
    ref = ref or base_ref(root)
    sha = merge_base(root, ref)
    where = f"{ref} ({sha[:9]})"
    lines: List[str] = []
    new: List[str] = []
    already: List[str] = []
    unaccounted: List[str] = []
    known = None
    recorded = load(sha, root)["commands"].get(command)
    if recorded is not None:
        known = set(recorded.get("failing", []))
    on_base = at_base(root, ref)
    for family, part in split_families(text).items():
        ids, problem = parse_log(part)
        keyed = [f"{family}:{i}" if family else i for i in ids]
        if problem:
            if re.search(r"failed|Test Case|error:|\u2718|issue", part):
                unaccounted.append(f"{family or command}: {problem}")
            continue
        if on_base and keyed:
            record_ids = set(keyed) | set((known or set()))
            data = load(sha, root)
            data["commands"][command] = {"failing": sorted(record_ids), "recorded": int(time.time())}
            data["base"] = ref
            save(sha, data, root)
            lines.append(f"Recorded as the baseline of {where}: {', '.join(keyed)}")
            continue
        for i in keyed:
            (already if known is not None and i in known else new).append(i)
    if already:
        lines.append(f"Already failing on {where} (inherited): {', '.join(already)}")
    if new:
        lines.append(f"New failures: {', '.join(new)}")
        if known is None:
            lines.append(f"  (no {command} baseline recorded for {where}; every failure shows as new)")
    if unaccounted:
        lines.append(f"Unaccounted: {'; '.join(unaccounted)}")
    return lines


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--why", action="store_true")
    parser.add_argument("--sha", action="store_true")
    sub = parser.add_subparsers(dest="cmd")
    base = sub.add_parser("baseline")
    base.add_argument("action", choices=("record", "summary", "show"))
    base.add_argument("--command", default="")
    base.add_argument("--family", default="", help="key the recorded ids by device family")
    base.add_argument("--sha", dest="at", default=None)
    base.add_argument("--log", default="")
    args = parser.parse_args(argv)
    try:
        ref, why = resolve()
    except LookupError as error:
        print(f"lane_base: {error}", file=sys.stderr)
        return 2
    if args.cmd != "baseline":
        print(merge_base(ROOT, ref) if args.sha else (f"{ref}  # {why}" if args.why else ref))
        return 0
    if args.action == "show":
        print(json.dumps(load(args.at or merge_base(ROOT, ref)), indent=2, sort_keys=True))
        return 0
    try:
        text = Path(args.log).read_text(errors="replace") if args.log else ""
    except OSError:
        text = ""
    if args.action == "summary":  # informational: always exit 0
        try:
            for line in summarize(args.command, text, ref=ref):
                print(f"== {line}")
        except Exception as error:  # never let the summary affect a run
            print(f"== baseline summary unavailable: {error}")
        return 0
    if not args.log:
        print("lane_base: record takes its ids from --log (a run on the clean base commit), not the command line", file=sys.stderr)
        return 2
    ids, problem = parse_log(text)
    if problem or not ids:
        print(f"lane_base: nothing recorded: {problem or 'no failing tests in the log'}", file=sys.stderr)
        return 3
    ids = [f"{args.family}:{i}" for i in ids] if args.family else ids
    try:
        print(f"recorded {len(ids)} failing id(s) for {args.command} on {record(args.command, ids, sha=args.at)[:9]}")
    except PermissionError as error:
        print(f"lane_base: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
