#!/usr/bin/env python3
"""Generates the Xcode test plans in apple/TestPlans/ from the UI journey sources (test tiers, .agents/testing/apple/README.md).

    tools/test_plans.py               write Gate, Smoke, Capture, Perf and Live .xctestplan files
    tools/test_plans.py --check       exit 1 when a committed plan is stale (pr-checks repo-checks runs this)
    tools/test_plans.py --counts      print how many tests each plan runs

Suites of contracts/test-suites.json marked ``"plan": true`` also get a ``Suite-NAME.xctestplan`` (runnable from Xcode).

Every test in apple/Apps/iOSUITests lands in exactly one of Gate, Capture, Perf or Live, by a mechanical rule
(first match wins, so a test is never in two):

* **Excluded**: ``TempScrollWedgeTests`` (a probe, in no plan).
* **Perf**: a class named ``*PerformanceTests`` or ``PerformanceJourneyTests`` (XCTest metrics, signposts).
* **Capture**: a method named ``testCapture*``, a method ending ``Screenshots`` (the ``…AuditsAndScreenshots`` looks), a class
  named ``*Capture*`` (``LightSheetCaptureTests``), and the Motion gallery sweep (``MotionJourneyTests`` methods whose name has
  ``Gallery``, ``EveryComponent`` or ``ToggleAll``). They write screenshots or walk a gallery; they assert little a Gate
  test does not.
* **Live**: the test needs the real house: it calls ``FentonHomeApp.launchSignedIn(`` (directly or through a helper of its class),
  its name starts ``testLive``, or its class is a camera class (``CameraJourneyTests``, ``CameraViewerFitJourneyTests``: WebRTC
  and HLS against the live cameras). Without ``TEST_RUNNER_FENTON_HASS_*`` credentials these skip anyway.
* **Gate**: everything else (fixture galleries, signed-out screens): deterministic, no house, no media.

**Smoke** is not a partition: ten-odd named tests (the ``smoke`` list of contracts/test-map.json) that touch every shell mechanism once, for the families a change
does not target. Gate runs with code coverage off and test timeouts on (300 s default, 900 s maximum).
Stdlib only (macOS system Python 3.9).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import uuid
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
UITESTS = ROOT / "apple" / "Apps" / "iOSUITests"
PLANS = ROOT / "apple" / "TestPlans"
TARGET = "FentonHomeUITests"
UNIT_TARGET = "FentonHomeTests"
CONTAINER = "container:FentonHome.xcodeproj"
EXCLUDED_CLASSES = {"TempScrollWedgeTests"}
CAMERA_CLASSES = {"CameraJourneyTests", "CameraViewerFitJourneyTests"}
CLASS_RE = re.compile(r"\bclass\s+(\w+)\s*:\s*\w*TestCase\b")
FUNC_RE = re.compile(r"\bfunc\s+(\w+)\s*\(")
CALL_RE = re.compile(r"\b(\w+)\s*\(")
MAP_PATH = ROOT / "contracts" / "test-map.json"


def load_smoke(path: Path = MAP_PATH) -> List[Tuple[str, str]]:
    """The Smoke tests as ``(class, method)``, from the ``smoke`` list of contracts/test-map.json (``Class/testName``).

    They touch each shell mechanism once: a signed-out screen, the tab shell, a sheet opening and closing, an audit, AX5,
    rotation and the Duo hinge.
    """
    entries = json.loads(path.read_text()).get("smoke", [])
    return [tuple(entry.split("/", 1)) for entry in entries]  # type: ignore[misc]


SMOKE = load_smoke()
PLAN_NAMES = ["Gate", "Smoke", "Capture", "Perf", "Live"]
TEST_OPTIONS = {"testTimeoutsEnabled": True, "defaultTestExecutionTimeAllowance": 300, "maximumTestExecutionTimeAllowance": 900}


def mask(text: str) -> str:
    """``text`` with comments and string contents blanked (same length), so braces inside them do not count."""
    out = list(text)
    i, n = 0, len(text)

    def blank(a: int, b: int) -> None:
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        two = text[i:i + 2]
        if two == "//":
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j); i = j
        elif two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            blank(i, j); i = j
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j < 0 else j + 3
            blank(i + 3, j - 3 if j - 3 > i + 3 else j); i = j
        elif text[i] == '"':
            j = i + 1
            depth = 0
            while j < n:
                c = text[j]
                if c == "\\" and j + 1 < n:
                    if text[j + 1] == "(":
                        depth += 1
                        j += 2
                        continue
                    j += 2
                    continue
                if depth and c == "(":
                    depth += 1
                elif depth and c == ")":
                    depth -= 1
                elif c == '"' and not depth:
                    break
                elif c == "\n" and not depth:
                    break
                j += 1
            blank(i + 1, j); i = j + 1
        else:
            i += 1
    return "".join(out)


def match_brace(masked: str, open_at: int) -> int:
    """Index just after the ``}`` closing the ``{`` at ``open_at`` (end of text when unbalanced)."""
    depth = 0
    for i in range(open_at, len(masked)):
        if masked[i] == "{":
            depth += 1
        elif masked[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
    return len(masked)


def scan_file(text: str) -> Dict[str, Dict[str, bool]]:
    """``{class: {test method: needs the live house}}`` for one source file."""
    masked = mask(text)
    found: Dict[str, Dict[str, bool]] = {}
    for cls in CLASS_RE.finditer(masked):
        start = masked.find("{", cls.end())
        if start < 0:
            continue
        end = match_brace(masked, start)
        body = masked[start:end]
        funcs: Dict[str, str] = {}
        for fn in FUNC_RE.finditer(body):
            open_at = body.find("{", fn.end())
            if open_at < 0:
                continue
            funcs[fn.group(1)] = body[open_at:match_brace(body, open_at)]
        live: Set[str] = {name for name, src in funcs.items() if "launchSignedIn(" in src}
        changed = True
        while changed:  # a helper that signs in makes every test that calls it live
            changed = False
            for name, src in funcs.items():
                if name not in live and any(c in live and c != name for c in CALL_RE.findall(src)):
                    live.add(name)
                    changed = True
        tests = {name: name in live for name in funcs if name.startswith("test")}
        if tests:
            found.setdefault(cls.group(1), {}).update(tests)
    return found


def scan(folder: Path = UITESTS) -> Dict[str, Dict[str, bool]]:
    """All UI test classes with their test methods and whether each needs the live house."""
    found: Dict[str, Dict[str, bool]] = {}
    for path in sorted(folder.glob("*.swift")):
        for cls, tests in scan_file(path.read_text(encoding="utf-8", errors="replace")).items():
            found.setdefault(cls, {}).update(tests)
    return found


def classify(cls: str, method: str, live: bool) -> Optional[str]:
    """The plan that owns a test (``None`` for an excluded one)."""
    if cls in EXCLUDED_CLASSES:
        return None
    if cls.endswith("PerformanceTests") or cls == "PerformanceJourneyTests":
        return "Perf"
    if (method.startswith("testCapture") or method.endswith("Screenshots") or "Capture" in cls
            or (cls == "MotionJourneyTests" and re.search(r"Gallery|EveryComponent|ToggleAll", method))):
        return "Capture"
    if live or method.startswith("testLive") or cls in CAMERA_CLASSES:
        return "Live"
    return "Gate"


def partition(classes: Dict[str, Dict[str, bool]]) -> Dict[str, Dict[str, List[str]]]:
    """``{plan: {class: [methods]}}`` for the four partitioning plans."""
    plans: Dict[str, Dict[str, List[str]]] = {name: {} for name in ("Gate", "Capture", "Perf", "Live")}
    for cls, tests in sorted(classes.items()):
        for method, live in sorted(tests.items()):
            plan = classify(cls, method, live)
            if plan:
                plans[plan].setdefault(cls, []).append(method)
    return plans


def identifiers(chosen: Dict[str, List[str]], classes: Dict[str, Dict[str, bool]], invert: bool) -> List[str]:
    """Plan entries for the tests in ``chosen`` (or, inverted, every other test): a class name when the whole class qualifies."""
    out: List[str] = []
    for cls in sorted(classes):
        methods = sorted(m for m in classes[cls] if (m in chosen.get(cls, [])) != invert)
        if not methods:
            continue
        elif len(methods) == len(classes[cls]):
            out.append(cls)
        else:
            out.extend(f"{cls}/{m}()" for m in methods)
    return out


def target(name: str, **extra: object) -> Dict[str, object]:
    entry: Dict[str, object] = {"target": {"containerPath": CONTAINER, "name": name}}
    entry.update(extra)
    return entry


def document(name: str, selected: Optional[List[str]], skipped: Optional[List[str]], units: bool) -> Dict[str, object]:
    """One .xctestplan document."""
    ui: Dict[str, object] = {}
    if selected is not None:
        ui["selectedTests"] = selected
    if skipped:
        ui["skippedTests"] = skipped
    targets = [target(TARGET, parallelizable=False, **ui)]
    if units:
        targets.insert(0, target(UNIT_TARGET, parallelizable=False))
    return {
        "configurations": [{"id": str(uuid.uuid5(uuid.NAMESPACE_URL, "fenton-hass-native/testplan/" + name)).upper(),
                            "name": "Configuration 1", "options": {}}],
        "defaultOptions": dict(TEST_OPTIONS, codeCoverage=False),
        "testTargets": targets,
        "version": 1,
    }


def build(classes: Dict[str, Dict[str, bool]]) -> Dict[str, Dict[str, object]]:
    """Plan name -> document. Raises ``ValueError`` when a Smoke test does not exist."""
    parts = partition(classes)
    for cls, method in SMOKE:
        if method not in classes.get(cls, {}):
            raise ValueError(f"Smoke test {cls}/{method} does not exist in {UITESTS.relative_to(ROOT)}")
    smoke: Dict[str, List[str]] = {}
    for cls, method in SMOKE:
        smoke.setdefault(cls, []).append(method)
    docs = {"Gate": document("Gate", None, identifiers(parts["Gate"], classes, invert=True), units=True),
            "Smoke": document("Smoke", identifiers(smoke, classes, invert=False), None, units=False)}
    for name in ("Capture", "Perf", "Live"):
        docs[name] = document(name, identifiers(parts[name], classes, invert=False), None, units=False)
    return docs


def suite_documents(classes: Dict[str, Dict[str, bool]]) -> Dict[str, Dict[str, object]]:
    """``Suite-NAME`` plan documents for the suites of contracts/test-suites.json marked ``"plan": true`` (tools/test_suites.py)."""
    import test_suites  # lazy: test_suites imports this module

    suites = test_suites.load_manifest()
    resolver = test_suites.Resolver(suites, classes)
    docs: Dict[str, Dict[str, object]] = {}
    for name in sorted(suites):
        if suites[name].get("plan"):
            chosen: Dict[str, List[str]] = {}
            for test in resolver.suite(name, []):
                cls, method = test.split("/", 1)
                chosen.setdefault(cls, []).append(method)
            docs["Suite-" + name] = document("Suite-" + name, identifiers(chosen, classes, invert=False), None, units=False)
    return docs


def render(doc: Dict[str, object]) -> str:
    return json.dumps(doc, indent=2) + "\n"


def counts(classes: Dict[str, Dict[str, bool]]) -> Dict[str, int]:
    parts = partition(classes)
    result = {name: sum(len(v) for v in parts[name].values()) for name in parts}
    result["Smoke"] = len(SMOKE)
    return result


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true", help="fail when a plan file is stale or missing")
    parser.add_argument("--counts", action="store_true", help="print the number of tests per plan")
    parser.add_argument("--dir", default=str(PLANS))
    args = parser.parse_args(argv)
    classes = scan()
    try:
        docs = build(classes)
    except ValueError as error:
        print(f"test_plans: {error}", file=sys.stderr)
        return 2
    if args.counts:
        for name, count in counts(classes).items():
            print(f"{name}: {count}")
        return 0
    folder = Path(args.dir)
    stale: List[str] = []
    docs.update(suite_documents(classes))
    for name in list(PLAN_NAMES) + sorted(n for n in docs if n not in PLAN_NAMES):
        path = folder / f"{name}.xctestplan"
        text = render(docs[name])
        if args.check:
            if not path.exists() or path.read_text() != text:
                stale.append(path.name)
        else:
            folder.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    if args.check:
        if stale:
            print("test_plans: stale or missing: %s. Run `python3 tools/test_plans.py` and commit apple/TestPlans/." % ", ".join(stale),
                  file=sys.stderr)
            return 1
        print("test plans are current")
    return 0


if __name__ == "__main__":
    sys.exit(main())
