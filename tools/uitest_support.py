#!/usr/bin/env python3
"""Helpers for ``tools/ios_uitest.sh`` that are awkward in bash 3.2.

    uitest_support.py count [--plan FILE] [-only-testing:T/C[/m] …]   number of test methods the run selects
    uitest_support.py exact [--plan FILE] [-only-testing:… -skip-testing:… …]   exact number the plan and filters run, or nothing
    uitest_support.py parts --plan FILE N                               the plan's UI test classes split into N balanced parts (one `-only-testing:` line per part)
    uitest_support.py hold COUNT                                       device hold in seconds for COUNT tests
    uitest_support.py hosted-hold [CLASS …]                            device hold in seconds for the app-hosted unit tests (all, or those classes)
    uitest_support.py products-key [SETTING …]                         content hash naming the .xctestproducts bundle (tools/products_cache.py)
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set

ROOT = Path(__file__).resolve().parents[1]
TEST_DIR = "apple/Apps/iOSUITests"
HOSTED_DIR = "apple/Apps/iOSTests"
TARGET = "FentonHomeUITests"
UNIT_TARGET = "FentonHomeTests"
OWNER = re.compile(r"^\s*(?:final\s+|public\s+|open\s+)*(?:class|extension)\s+(\w+)")
TEST_FUNC = re.compile(r"^\s*func\s+(test\w*)\s*\(")
#: A class named by a filter but not found in the sources is assumed to hold this many tests.
UNKNOWN_CLASS = 10
SECONDS_PER_TEST = 120
HOLD_BASE, HOLD_FLOOR, HOLD_CAP = 300, 600, 7200
#: The app-hosted unit tests (``--hosted``) take about 3.1 s each plain: 790 tests in 2,436 s (the full run ``hosted-full-1``,
#: 2026-11-10). The hold is the measured time times 1.5 plus ten minutes, never under 900 s; the old fixed 1800 s ended the
#: suite part way, and 6 s a test was twice the measured time.
HOSTED_MEASURED_SECONDS, HOSTED_MARGIN, HOSTED_BASE, HOSTED_FLOOR = 3.1, 1.5, 600, 900


def tests_by_class(root: Path = ROOT, directory: str = TEST_DIR) -> Dict[str, List[str]]:
    """Map each test class in `directory` (UI tests by default; extensions included) to its ``func test…`` names."""
    found: Dict[str, List[str]] = {}
    for path in sorted((root / directory).rglob("*.swift")):
        owner = ""
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if match := OWNER.match(line):
                owner = match.group(1)
            elif owner and (match := TEST_FUNC.match(line)):
                found.setdefault(owner, []).append(match.group(1))
    return found


def selection(spec: str, classes: Dict[str, List[str]]) -> int:
    """Count the tests one ``Target/Class[/method]`` selector names."""
    parts = [part for part in spec.split("/") if part]
    parts = parts[1:] if len(parts) > 1 else []  # drop the target
    if not parts:
        return sum(len(names) for names in classes.values())
    if len(parts) >= 2:
        return 1
    return len(classes[parts[0]]) if parts[0] in classes else UNKNOWN_CLASS


def plan_selectors(plan: Optional[Path]) -> List[str]:
    """``selectedTests`` of a test plan as selectors, or an empty list when it selects everything."""
    if not plan or not plan.is_file():
        return []
    try:
        data = json.loads(plan.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    out: List[str] = []
    for target in data.get("testTargets", []):
        for name in target.get("selectedTests", []):
            out.append("T/" + name.replace("()", ""))
    return out


def count(filters: List[str], plan: Optional[Path] = None, root: Path = ROOT) -> int:
    """How many test methods a run with these ``-only-testing:`` filters (and plan) selects."""
    classes = tests_by_class(root)
    specs = [f.split(":", 1)[1] for f in filters if f.startswith("-only-testing:")] or plan_selectors(plan)
    if not specs:
        return sum(len(names) for names in classes.values())
    return sum(selection(spec, classes) for spec in specs)


def plan_lists(plan: Path) -> Optional[Dict[str, Optional[List[str]]]]:
    """``selectedTests`` (``None`` = everything) and ``skippedTests`` of the plan's UI test target; ``None`` if unreadable."""
    try:
        data = json.loads(plan.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    for entry in data.get("testTargets", []):
        if entry.get("target", {}).get("name") == TARGET:
            return {"selected": entry.get("selectedTests"), "skipped": entry.get("skippedTests", [])}
    return None


def expand(spec: str, ids: Set[str]) -> Optional[Set[str]]:
    """The ``Class/method`` ids a selector (``[Target/]Class[/method[()]]``) names; ``None`` for the unit-test target."""
    parts = [part for part in spec.replace("()", "").split("/") if part]
    if parts and parts[0] == UNIT_TARGET:
        return None
    if parts and parts[0] == TARGET:
        parts = parts[1:]
    if not parts:
        return set(ids)
    if len(parts) == 1:
        return {i for i in ids if i.split("/", 1)[0] == parts[0]}
    return {i for i in ids if i == "/".join(parts[:2])}


def all_ids(root: Path = ROOT) -> Set[str]:
    """Every ``Class/method`` id of the UI test sources."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import test_plans

    return {f"{c}/{m}" for c, tests in test_plans.scan(root / TEST_DIR).items() for m in tests}


def plan_ids(plan: Path, root: Path = ROOT) -> Optional[Set[str]]:
    """The UI test ids the plan's own selection and skips leave, or ``None`` when the plan is unreadable."""
    lists = plan_lists(plan)
    if lists is None:
        return None
    ids = all_ids(root)
    chosen = set(ids)
    if lists["selected"] is not None:
        chosen = set()
        for spec in lists["selected"] or []:
            chosen |= expand(spec, ids) or set()
    for spec in lists["skipped"] or []:
        chosen -= expand(spec, ids) or set()
    return chosen


def split_parts(plan: Path, parts: int, root: Path = ROOT) -> List[List[str]]:
    """The plan's UI test classes in `parts` groups of near-equal test count (greedy, biggest class first).

    Each group is a list of ``-only-testing:FentonHomeUITests/Class`` filters. A class stays whole, so the app-reuse of a journey
    class (one resident app per class) is never cut in two. Empty groups are dropped.
    """
    chosen = plan_ids(plan, root) or set()
    sizes: Dict[str, int] = {}
    for test_id in chosen:
        sizes[test_id.split("/", 1)[0]] = sizes.get(test_id.split("/", 1)[0], 0) + 1
    groups: List[List[str]] = [[] for _ in range(max(1, parts))]
    loads = [0] * len(groups)
    for name, size in sorted(sizes.items(), key=lambda item: (-item[1], item[0])):
        index = loads.index(min(loads))
        groups[index].append(f"-only-testing:{TARGET}/{name}")
        loads[index] += size
    return [sorted(group) for group in groups if group]


def exact_count(args: List[str], plan: Optional[Path], root: Path = ROOT) -> Optional[int]:
    """The UI tests a run really executes: the plan's selection and skips, ``-only-testing`` and ``-skip-testing`` applied.

    Built on the sources scanner of ``tools/test_plans.py`` (the one the plans and the nightly shards come from) and the plan
    file itself. ``None`` when the count cannot be exact: no readable plan, or a filter naming a target, class or method the
    sources do not have. Unit tests the Gate plan also runs are not counted, so the real total is at least this.
    """
    if not plan or not plan.is_file():
        return None
    lists = plan_lists(plan)
    if lists is None:
        return None
    chosen = plan_ids(plan, root)
    if chosen is None:
        return None
    ids = set(chosen) | all_ids(root)
    only = [a.split(":", 1)[1] for a in args if a.startswith("-only-testing:")]
    if only:
        wanted: Set[str] = set()
        for spec in only:
            found = expand(spec, ids)
            if not found:
                return None  # another target, or a class or method the sources do not have
            wanted |= found
        chosen &= wanted
    for spec in (a.split(":", 1)[1] for a in args if a.startswith("-skip-testing:")):
        chosen -= expand(spec, ids) or set()
    return len(chosen)


def hold_for(tests: int) -> int:
    """120 s per test plus five minutes, never under ten minutes or over 7200 s."""
    return max(HOLD_FLOOR, min(HOLD_CAP, SECONDS_PER_TEST * tests + HOLD_BASE))


def hosted_hold(classes: List[str], root: Path = ROOT) -> int:
    """Device hold for the app-hosted unit tests: all of them, or only `classes` (``FENTON_HOSTED_FILTER``). The measured 3.1 s a test
    times 1.5 plus ten minutes, never under 900 s or over 7200 s; a class the sources do not have counts as ``UNKNOWN_CLASS`` tests."""
    found = tests_by_class(root, HOSTED_DIR)
    tests = sum(len(found.get(name, [])) or UNKNOWN_CLASS for name in classes) if classes else sum(map(len, found.values()))
    return max(HOSTED_FLOOR, min(HOLD_CAP, math.ceil(HOSTED_MEASURED_SECONDS * HOSTED_MARGIN * tests) + HOSTED_BASE))


def git(*args: str, root: Path = ROOT) -> str:
    """Stdout of a git command, or an empty string when it fails."""
    out = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else ""


def products_key(settings: List[str], root: Path = ROOT) -> str:
    """The products-cache key (see ``tools/products_cache.py``): content of apple/, build settings, Xcode."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import products_cache

    return products_cache.products_key(settings, root)


def tally_verdict(text: str) -> "tuple[int, List[str]]":
    """(status, lines to print) for a run's tally (``LABEL ran skipped`` per family, from ``xc_watch --tally``).

    EMPTY (status 1) when families reported and none ran a test, which covers ``--only FAMILY`` naming a family that skipped everything.
    When another family ran tests, a family that ran none is family-gated (an iPad-only journey on iPhone): a NOTE, status 0."""
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) in (3, 4) and parts[1].isdigit() and parts[2].isdigit():
            rows.append((parts[0], int(parts[1]), int(parts[2])))
    if not rows:
        return 0, []
    if not any(ran for _, ran, _ in rows):
        detail = "; ".join(f"{label} ran 0, skipped {skipped}" for label, _, skipped in rows)
        return 1, [f"EMPTY: no family ran a test, every selected test skipped ({detail}); --allow-empty if intended"]
    return 0, [f"NOTE: {label} ran no test ({skipped} skipped): family-gated journeys; another family ran them"
               for label, ran, skipped in rows if not ran]


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    command, rest = argv[0], argv[1:]
    root = Path(os.environ.get("FENTON_ROOT", ROOT))
    if command == "count":
        plan = None
        if rest[:1] == ["--plan"]:
            plan, rest = Path(rest[1]), rest[2:]
        print(count(rest, plan, root))
    elif command == "exact":
        plan = None
        if rest[:1] == ["--plan"]:
            plan, rest = Path(rest[1]), rest[2:]
        total = exact_count(rest, plan, root)
        print("" if total is None else total)
    elif command == "parts":
        if rest[:1] != ["--plan"] or len(rest) < 3:
            print(__doc__, file=sys.stderr)
            return 2
        for group in split_parts(Path(rest[1]), int(rest[2]), root):
            print(" ".join(group))
    elif command == "hold":
        print(hold_for(int(rest[0])))
    elif command == "hosted-hold":
        print(hosted_hold(rest, root))
    elif command == "tally":
        status, lines = tally_verdict(Path(rest[0]).read_text(encoding="utf-8") if Path(rest[0]).is_file() else "")
        print("\n".join(lines))
        return status
    elif command == "tally-ran":  # exit 0 when LABEL's family ran a test, or reported nothing; 1 when it ran none (all skipped)
        path = Path(rest[0])
        rows = [line.split() for line in path.read_text().splitlines()] if path.is_file() else []
        mine = [r for r in rows if len(r) >= 3 and r[0] == rest[1] and r[1].isdigit()]
        return 0 if not mine or int(mine[-1][1]) > 0 else 1
    elif command == "tally-empty":  # exit 0 when xc_watch marked a run EMPTY (it ran nothing and printed `EMPTY:`)
        path = Path(rest[0])
        return 0 if path.is_file() and any(line.split()[-1:] == ["empty"] for line in path.read_text().splitlines()) else 1
    elif command == "products-key":
        print(products_key(rest, root))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
