#!/usr/bin/env python3
"""Plans the nightly journeys: shards of at most 60 UI tests per devcap hold, per test plan.

    tools/nightly_plan.py [--max-tests 60] [--filter SUBSTRING] [--plans Gate,Live]

Prints one JSON line, ``{"include": [{"plan", "shard", "tests", "last", "filters": "<-only-testing:… …>"}]}``, for a
workflow matrix. The plans partition the journeys (tools/test_plans.py): the nightly runs Gate and Live, the weekly run
adds Capture, Perf is dispatched by hand. A shard is whole test classes (a class with more tests than the limit is split by
method), so ``tools/ios_uitest.sh --parallel-families --plan PLAN --force FILTERS`` runs it on all three families at once with
the script's own devcap holds. Shards are packed by test count, not by last-known durations (cheap and stable; a duration
ledger can replace the count later). ``--filter`` keeps only classes whose name contains the substring (a tiny nightly).
Stdlib only (macOS system Python 3.9).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
UITESTS = ROOT / "apple" / "Apps" / "iOSUITests"
TARGET = "FentonHomeUITests"
FAMILIES = ["iphone", "duo", "ipad"]
DEFAULT_PLANS = ["Gate", "Live"]
CLASS_RE = re.compile(r"^\s*(?:final\s+)?class\s+(\w+)\s*:\s*\w*TestCase", re.M)
TEST_RE = re.compile(r"^\s*func\s+(test\w*)\s*\(", re.M)


def scan(folder: Path = UITESTS) -> Dict[str, List[str]]:
    """UI test classes with their test method names, in file order."""
    found: Dict[str, List[str]] = {}
    for path in sorted(folder.glob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="replace")
        classes = list(CLASS_RE.finditer(text))
        for i, match in enumerate(classes):
            end = classes[i + 1].start() if i + 1 < len(classes) else len(text)
            tests = TEST_RE.findall(text[match.end():end])
            if tests:
                found.setdefault(match.group(1), []).extend(tests)
    return found


def shards(classes: Dict[str, List[str]], max_tests: int = 60) -> List[Dict[str, object]]:
    """Greedy first-fit-in-order packing; a class over the limit is split into method chunks."""
    units: List[Dict[str, object]] = []
    for name, tests in classes.items():
        if len(tests) <= max_tests:
            units.append({"filters": ["-only-testing:%s/%s" % (TARGET, name)], "tests": len(tests)})
        else:
            for i in range(0, len(tests), max_tests):
                chunk = tests[i:i + max_tests]
                units.append({"filters": ["-only-testing:%s/%s/%s" % (TARGET, name, t) for t in chunk], "tests": len(chunk)})
    out: List[Dict[str, object]] = []
    for unit in units:
        for shard in out:
            if shard["tests"] + unit["tests"] <= max_tests:  # type: ignore[operator]
                shard["filters"].extend(unit["filters"])  # type: ignore[union-attr]
                shard["tests"] += unit["tests"]  # type: ignore[operator]
                break
        else:
            out.append({"filters": list(unit["filters"]), "tests": unit["tests"]})  # type: ignore[call-overload]
    return out


def scan_plans(plans: List[str]) -> Dict[str, Dict[str, List[str]]]:
    """``{plan: {class: [tests]}}`` for ``plans`` (Gate, Capture, Perf, Live), from tools/test_plans.py's classification."""
    import test_plans  # tools/ is on sys.path when this runs as a script or is imported by the tests
    parts = test_plans.partition(test_plans.scan())
    return {name: parts[name] for name in plans if name in parts}


def plan(by_plan: Dict[str, Dict[str, List[str]]], max_tests: int = 60, needle: Optional[str] = None) -> Dict[str, object]:
    """The workflow matrix: shards per plan, whole classes (a class over the limit is split by method).

    A shard runs on every family at once (``ios_uitest.sh --parallel-families --plan PLAN``), so a family is not a matrix axis.
    """
    include: List[Dict[str, object]] = []
    for name, classes in by_plan.items():
        if needle:
            classes = {k: v for k, v in classes.items() if needle.lower() in k.lower()}
        for shard in shards(classes, max_tests):
            include.append({"plan": name, "tests": shard["tests"], "filters": " ".join(shard["filters"])})  # type: ignore[arg-type]
    for i, entry in enumerate(include, 1):
        entry["shard"] = i
        entry["last"] = i == len(include)
    return {"include": include}


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--max-tests", type=int, default=60)
    parser.add_argument("--filter", default="")
    parser.add_argument("--plans", default=",".join(DEFAULT_PLANS), help="test plans to run (Gate,Live nightly; Capture weekly)")
    args = parser.parse_args(argv)
    plans = [p for p in args.plans.split(",") if p]
    document = plan(scan_plans(plans), args.max_tests, args.filter or None)
    if not document["include"]:
        print("no UI tests match the filter", file=sys.stderr)
        return 1
    print(json.dumps(document))
    return 0


if __name__ == "__main__":
    sys.exit(main())
