#!/usr/bin/env python3
"""Composes UI journey tests into named suites (contracts/test-suites.json) and resolves them to test ids.

    tools/test_suites.py list [--no-times]               each suite with its test count and estimated seconds
    tools/test_suites.py resolve NAME|SELECTOR …         Class/method ids, one per line (``--only-testing`` for xcodebuild args)
    tools/test_suites.py check                           fail on a selector that matches nothing, an unknown suite or plan, a cycle
    tools/test_suites.py args --suite A,B --tests 'X,Y' [--within '-only-testing:… …']   the ``-only-testing:`` args ios_uitest.sh runs
    tools/test_suites.py plan --suite … --tests …        the Xcode plan that owns the selection (``mixed:A,B`` when several)

A **selector** is one of (anything with a ``/`` or a glob character is matched against ``Class/method``; the method may carry ``()``):

* ``Class`` or ``Class*Glob``: every test of the matching classes.
* ``Class/testMethod`` or ``Class*/test*Audit*``: matching tests (fnmatch globs; ``*`` crosses the slash).
* ``plan:Gate``: the members of a tools/test_plans.py plan (Gate, Smoke, Capture, Perf, Live).
* ``map:layoutJourneys``: a class list of contracts/test-map.json.
* ``suite:name``: another suite (nesting; cycles are an error).

A suite is ``{"description": …, "include": [selectors], "exclude": [selectors], "plan": bool}``: the union of ``include`` minus the
union of ``exclude``. A bare name given to ``resolve``/``--suite`` is a suite; ``--tests`` takes selectors. The test list comes from
the same source scanner as the plans (``test_plans.scan``). Stdlib only (macOS system Python 3.9).
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import re
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_plans  # noqa: E402  (shared source scanner and plan classification)

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "contracts" / "test-suites.json"
TARGET = test_plans.TARGET
GLOB_CHARS = set("*?[")
TIME_RE = re.compile(r"Test Case '-\[\w+\.(\w+) (\w+)\]' (?:passed|failed) \(([\d.]+) seconds\)")
DEFAULT_SECONDS = 120.0  # the hold estimate ios_uitest.sh uses for a test with no recorded time


class SuiteError(Exception):
    """A manifest problem: unknown suite or plan, a cycle, or an empty selection."""


def load_manifest(path: Path = MANIFEST) -> Dict[str, Dict]:
    return json.loads(path.read_text()).get("suites", {})


def universe(classes: Dict[str, Dict[str, bool]]) -> List[str]:
    """Every ``Class/method`` id, sorted. Excluded probe classes are not part of any suite."""
    return sorted(f"{c}/{m}" for c, tests in classes.items() if c not in test_plans.EXCLUDED_CLASSES for m in tests)


def _plan_members(name: str, classes: Dict[str, Dict[str, bool]]) -> Set[str]:
    if name == "Smoke":
        return {f"{c}/{m}" for c, m in test_plans.load_smoke()}
    parts = test_plans.partition(classes)
    if name not in parts:
        raise SuiteError(f"unknown plan '{name}' (Gate, Smoke, Capture, Perf or Live)")
    return {f"{c}/{m}" for c, ms in parts[name].items() for m in ms}


class Resolver:
    """Resolves selectors and suites against the enumerated tests."""

    def __init__(self, suites: Dict[str, Dict], classes: Dict[str, Dict[str, bool]], test_map: Optional[Dict] = None) -> None:
        self.suites, self.classes = suites, classes
        self.all = universe(classes)
        self.test_map = test_map if test_map is not None else json.loads(test_plans.MAP_PATH.read_text())

    def selector(self, sel: str, stack: Optional[List[str]] = None) -> Set[str]:
        sel = sel.strip().replace("()", "")
        if sel.startswith("suite:"):
            return self.suite(sel[6:], stack or [])
        if sel.startswith("plan:"):
            return _plan_members(sel[5:], self.classes)
        if sel.startswith("map:"):
            key = sel[4:]
            names = self.test_map.get(key)
            if not isinstance(names, list):
                raise SuiteError(f"unknown test-map list '{key}'")
            return {t for t in self.all if t.split("/", 1)[0] in names}
        if "/" in sel:
            return {t for t in self.all if fnmatch.fnmatchcase(t, sel)}
        return {t for t in self.all if fnmatch.fnmatchcase(t.split("/", 1)[0], sel)}

    def suite(self, name: str, stack: List[str]) -> Set[str]:
        if name in stack:
            raise SuiteError("cycle: " + " -> ".join(stack + [name]))
        if name not in self.suites:
            raise SuiteError(f"unknown suite '{name}'")
        body = self.suites[name]
        chain = stack + [name]
        got: Set[str] = set()
        for sel in body.get("include", []):
            got |= self.selector(sel, chain)
        for sel in body.get("exclude", []):
            got -= self.selector(sel, chain)
        return got

    def resolve(self, names: Iterable[str] = (), selectors: Iterable[str] = ()) -> List[str]:
        got: Set[str] = set()
        for name in names:
            got |= self.suite(name, [])
        for sel in selectors:
            got |= self.selector(sel)
        return sorted(got)


def split_list(text: Optional[str]) -> List[str]:
    return [p for p in re.split(r"[,\s]+", text or "") if p]


def only_testing(ids: Iterable[str], classes: Dict[str, Dict[str, bool]]) -> List[str]:
    """``-only-testing:`` args; a class whose every test is selected collapses to the class name."""
    by_class: Dict[str, List[str]] = {}
    for test in ids:
        cls, method = test.split("/", 1)
        by_class.setdefault(cls, []).append(method)
    out: List[str] = []
    for cls in sorted(by_class):
        if len(by_class[cls]) == len(classes.get(cls, {})):
            out.append(f"-only-testing:{TARGET}/{cls}")
        else:
            out.extend(f"-only-testing:{TARGET}/{cls}/{m}" for m in sorted(by_class[cls]))
    return out


def within(ids: List[str], restriction: str) -> List[str]:
    """Keep the ids a ``-only-testing:`` list (the ``--changed`` journeys of one family) also names."""
    allowed = [a.split(":", 1)[1].split("/", 1)[1] for a in restriction.split() if a.startswith("-only-testing:") and "/" in a.split(":", 1)[1]]
    return [t for t in ids if any(t == a or t.split("/", 1)[0] == a for a in allowed)]


def timings(root: Path = ROOT) -> Dict[str, float]:
    """Median seconds per ``Class/method`` from build/runs logs (this checkout and the main one); ``uikit-*`` logs are skipped."""
    folders = [root / "build" / "runs"]
    common = subprocess.run(["git", "-C", str(root), "rev-parse", "--git-common-dir"], capture_output=True, text=True).stdout.strip()
    if common:
        folders.append((root / common).resolve().parent / "build" / "runs")
    seen: Dict[str, List[float]] = {}
    done: Set[Path] = set()
    for folder in folders:
        for log in sorted(folder.glob("*.log")) if folder.is_dir() else []:
            if log.name.startswith("uikit-") or log in done:
                continue
            done.add(log)
            for cls, method, secs in TIME_RE.findall(log.read_text(errors="replace")):
                seen.setdefault(f"{cls}/{method}", []).append(float(secs))
    return {k: statistics.median(v) for k, v in seen.items()}


def check(resolver: Resolver) -> List[str]:
    """Problems: a selector matching nothing, an unknown suite or plan, a cycle."""
    problems: List[str] = []
    for name, body in sorted(resolver.suites.items()):
        for field in ("include", "exclude"):
            for sel in body.get(field, []):
                try:
                    if not resolver.selector(sel, [name]) and not (field == "exclude" and sel.startswith("suite:")):
                        problems.append(f"{name}.{field}: '{sel}' matches no test")
                except SuiteError as error:
                    problems.append(f"{name}.{field}: {sel}: {error}")
        try:
            if not resolver.suite(name, []):
                problems.append(f"{name}: resolves to no tests")
        except SuiteError as error:
            problems.append(f"{name}: {error}")
    return problems


def selection_ids(resolver: Resolver, suite: Optional[str], tests: Optional[str]) -> List[str]:
    names, sels = split_list(suite), split_list(tests)
    if not names and not sels:
        raise SuiteError("nothing selected: give --suite and/or --tests")
    return resolver.resolve(names, sels)


def owning_plan(ids: List[str], classes: Dict[str, Dict[str, bool]]) -> str:
    plans = {test_plans.classify(c, m, classes[c][m]) or "none" for c, m in (t.split("/", 1) for t in ids)}
    return next(iter(plans)) if len(plans) == 1 else "mixed:" + ",".join(sorted(plans))


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--manifest", default=str(MANIFEST))
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("list"); p.add_argument("--no-times", action="store_true")
    p = sub.add_parser("resolve"); p.add_argument("items", nargs="+"); p.add_argument("--only-testing", action="store_true")
    sub.add_parser("check")
    for name in ("args", "plan"):
        p = sub.add_parser(name); p.add_argument("--suite"); p.add_argument("--tests"); p.add_argument("--within")
    args = parser.parse_args(argv)
    classes = test_plans.scan()
    resolver = Resolver(load_manifest(Path(args.manifest)), classes)
    try:
        if args.cmd == "check":
            problems = check(resolver)
            for line in problems:
                print("test_suites: " + line, file=sys.stderr)
            if not problems:
                print(f"{len(resolver.suites)} test suites are valid")
            return 1 if problems else 0
        if args.cmd == "list":
            times = {} if args.no_times else timings()
            for name in sorted(resolver.suites):
                ids = resolver.suite(name, [])
                known = sum(1 for t in ids if t in times)
                est = sum(times.get(t, DEFAULT_SECONDS) for t in ids)
                note = "" if args.no_times else f"  ~{est:6.0f}s ({known}/{len(ids)} timed)"
                flag = "  [xctestplan]" if resolver.suites[name].get("plan") else ""
                print(f"{name:24s}{len(ids):5d} tests{note}{flag}  {resolver.suites[name].get('description', '')}")
            return 0
        if args.cmd == "resolve":
            names = [i for i in args.items if i in resolver.suites]
            ids = resolver.resolve(names, [i for i in args.items if i not in resolver.suites])
            if not ids:
                raise SuiteError("selection matches no test")
            print("\n".join(only_testing(ids, classes) if args.only_testing else ids))
            return 0
        ids = selection_ids(resolver, args.suite, args.tests)
        if args.cmd == "plan":
            print(owning_plan(ids, classes) if ids else "none")
            return 0
        if args.within is not None:
            ids = within(ids, args.within)
        elif not ids:
            raise SuiteError("selection matches no test")
        print(" ".join(only_testing(ids, classes)))
        return 0
    except SuiteError as error:
        print(f"test_suites: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
