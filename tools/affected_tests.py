#!/usr/bin/env python3
"""Per-change test selection and the passing-run ledger (test tiers, .agents/testing/apple/README.md).

``affected_tests.py``                 what the diff against the lane's base (tools/lane_base.py) needs: swift filters, journeys, families
``affected_tests.py --swift``         `--filter A --filter B` for `swift test`
``affected_tests.py --journeys``      `-only-testing:FentonHomeUITests/Class …` for `tools/ios_uitest.sh` (the iPhone list)
``affected_tests.py --journeys --device duo``  the journeys one family runs (iphone: all of them; duo, ipad: the layout ones)
``affected_tests.py --families``      device families that run the affected journeys (iphone duo ipad)
``affected_tests.py --smoke-families``  families that run only the Smoke plan (`ios_uitest.sh --only F --plan Smoke`)
``affected_tests.py --environment``   `NAME=value` lines a `--changed` run gives the journeys (``changedEnvironment`` of the map)
``affected_tests.py tree-hash``       hash of the apple/ tree as it is now (tracked, modified and untracked files)
``affected_tests.py seen|record|result --device D --filter F [--result pass|skipped]``   the ledger of passing runs in build/testruns/

Selection comes from contracts/test-map.json (longest path prefix wins), then file-name conventions, then the file's
module test target (`apple/Sources/HassUI/…` -> `HassUITests`). A file none of those know prints a request for a targeted
pick; it never widens to the full suite (the full suite is the nightly tier). Journeys run on the primary family (iPhone)
and the Smoke plan on the others. A journey the matched rule lists in `layout_journeys`, or a `layoutJourneys` class whose own test file changed, also
runs on Duo and iPad (`journeys_by_family`); the other journeys of the change stay on iPhone. A rule tagged `layout_sensitive`
without `layout_journeys` is blanket: all its journeys run on all three families.
Exit status is 0 when everything resolved, 3 when a file needs a pick.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence

ROOT = Path(__file__).resolve().parent.parent
MAP_PATH = ROOT / "contracts" / "test-map.json"
LEDGER_DIR = "build/testruns"
TREE_PATHS = ("apple",)
SOURCES = "apple/Sources/"
TESTS = "apple/Tests/"
JOURNEYS = "apple/Apps/iOSUITests/"
CLASS_RE = re.compile(r"^\s*(?:final\s+)?(?:public\s+)?class\s+(\w+)\s*:", re.M)
SUITE_RE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:final\s+)?(?:struct|class)\s+(\w+)", re.M)


def git(*args: str, env: Optional[Dict[str, str]] = None, root: Path = ROOT) -> str:
    """Run git in ``root`` and return stdout (empty on failure)."""
    result = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, env=env)
    return result.stdout if result.returncode == 0 else ""


def default_base(root: Path = ROOT) -> str:
    """The diff base: the branch the work came from (``tools/lane_base.py``; ``FENTON_AFFECTED_BASE`` comes first there)."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import lane_base
        return lane_base.base_ref(root)
    except LookupError as error:
        print(f"affected_tests: {error}; diffing against HEAD, so committed changes select no tests", file=sys.stderr)
        return "HEAD"
    finally:
        sys.path.pop(0)


def changed_files(base: Optional[str] = None, root: Path = ROOT) -> List[str]:
    """Files changed on this branch since it left ``base`` (default ``default_base()``), plus uncommitted and untracked ones."""
    base = base or default_base(root)
    point = git("merge-base", base, "HEAD", root=root).strip() or base
    names = set(git("diff", "--name-only", point, root=root).split())
    names.update(git("ls-files", "--others", "--exclude-standard", root=root).split())
    return sorted(names)


def load_map(path: Path = MAP_PATH) -> Dict:
    """The test map, or an empty one when the file is missing."""
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {"rules": [], "ignore": [], "families": ["iphone", "duo", "ipad"], "journeyTarget": "FentonHomeUITests"}


def classes_in(path: Path) -> List[str]:
    """Test class or suite names declared in a Swift file."""
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return []
    found = CLASS_RE.findall(text) + SUITE_RE.findall(text)
    return sorted({name for name in found if name.endswith("Tests") or name.endswith("Test")})


def convention(file: str, root: Path = ROOT) -> Optional[Dict[str, List[str]]]:
    """Selection for a file by naming convention, or ``None`` when nothing matches."""
    path = Path(file)
    if file.startswith(JOURNEYS) and path.suffix == ".swift":
        names = classes_in(root / file)
        if names:
            return {"swift": [], "journeys": names}
        return None
    if file.startswith(TESTS) and path.suffix == ".swift":
        names = classes_in(root / file)  # test identifiers are types, not file stems
        return {"swift": names, "journeys": []} if names else None
    if file.startswith(SOURCES) and path.suffix == ".swift":
        stem = path.stem.split("+")[0]
        tests = sorted({name for p in (root / "apple" / "Tests").rglob(f"{stem}*Tests.swift") for name in classes_in(p)})
        journeys = sorted({p.stem for p in (root / JOURNEYS).glob(f"{stem}JourneyTests.swift")})
        if tests or journeys:
            return {"swift": tests, "journeys": journeys}
    return None


def module_tests(file: str, root: Path = ROOT) -> Optional[str]:
    """The test target of a Swift file's module (``apple/Sources/HassUI/…`` -> ``HassUITests``), or ``None``."""
    if file.startswith(SOURCES) and file.endswith(".swift"):
        module = file[len(SOURCES):].split("/", 1)[0]
        if (root / "apple" / "Tests" / f"{module}Tests").is_dir():
            return f"{module}Tests"
    return None


def select(files: Iterable[str], test_map: Dict, root: Path = ROOT) -> Dict:
    """Resolve changed files to filters, journeys, families, ignored files and files needing a pick."""
    rules = test_map.get("rules", [])
    ignore = tuple(test_map.get("ignore", []))
    swift: List[str] = []
    journeys: List[str] = []
    families: List[str] = []
    blanket = False  # a layout_sensitive rule without layout_journeys: every journey on every family
    layout_set: List[str] = []  # journeys a matched rule names as layout journeys
    all_families = list(test_map.get("families", ["iphone", "duo", "ipad"]))
    layout_known = set(test_map.get("layoutJourneys", []))
    edited_layout: List[str] = []  # layoutJourneys classes whose own test file changed
    ignored: List[str] = []
    unknown: List[str] = []

    def add(into: List[str], items: Sequence[str]) -> None:
        into.extend(item for item in items if item not in into)

    for file in files:
        if file.startswith(ignore):
            ignored.append(file)
            continue
        if file.startswith(TESTS) and not (root / file).exists():
            ignored.append(file)  # a deleted test file has nothing to run
            continue
        if file.startswith(TESTS) or file.startswith(JOURNEYS):
            hit = convention(file, root)  # a changed test file selects its own classes first
            if hit:
                add(swift, hit["swift"]); add(journeys, hit["journeys"])
                add(edited_layout, [name for name in hit["journeys"] if name in layout_known])
                continue
        matches = [rule for rule in rules if file.startswith(rule["prefix"])]
        if matches:
            longest = max(len(rule["prefix"]) for rule in matches)
            for rule in matches:
                if len(rule["prefix"]) == longest:
                    add(swift, rule.get("swift", [])); add(journeys, rule.get("journeys", []))
                    add(families, rule.get("families", []))
                    add(layout_set, rule.get("layout_journeys", []))
                    if rule.get("layout_sensitive") and not rule.get("layout_journeys"):
                        blanket = True
            continue
        hit = convention(file, root)
        module = module_tests(file, root)
        if hit:
            add(swift, hit["swift"]); add(journeys, hit["journeys"])
        elif module:
            add(swift, [module])  # no rule, no test named after it: its module's whole test target
        elif file.endswith((".md", ".json", ".txt", ".html", ".js", ".css", ".png", ".svg", ".yml", ".yaml", ".sh", ".py")):
            ignored.append(file)
        else:
            unknown.append(file)
    # iPhone (the default family) runs every selected journey. The others run all of them for a blanket layout_sensitive rule or
    # a rule's explicit `families`, otherwise only the layout journeys; no journeys means no device run.
    default = list(test_map.get("defaultFamilies", ["iphone"]))
    layout_all = set(layout_set) | set(edited_layout)  # a rule's source file selecting a layoutJourneys class does not widen the run
    layout_picked = [name for name in journeys if name in layout_all]
    by_family: Dict[str, List[str]] = {}
    for family in all_families:
        if not journeys:
            by_family[family] = []
        elif family in default or blanket or family in families:
            by_family[family] = list(journeys)
        else:
            by_family[family] = list(layout_picked)
    layout = blanket or bool(layout_picked)
    run = [f for f in all_families if by_family[f]]
    # The families a change does not target still get the Smoke plan: the shell, a sheet, an audit, AX5 and rotation.
    smoke = [f for f in all_families if journeys and f not in run]
    return {"swift": swift, "journeys": journeys, "journeys_by_family": by_family,
            "families": run, "smoke_families": smoke, "layout_sensitive": layout,
            "ignored": ignored, "unknown": unknown, "target": test_map.get("journeyTarget", "FentonHomeUITests")}


def swift_args(result: Dict) -> str:
    """`--filter A --filter B` for swift test."""
    return " ".join(f"--filter {name}" for name in result["swift"])


def journey_args(result: Dict, family: str = "") -> str:
    """`-only-testing:Target/Class …` for ios_uitest.sh: the iPhone list, or ``family``'s own list."""
    names = result.get("journeys_by_family", {}).get(family, result["journeys"]) if family else result["journeys"]
    return " ".join(f"-only-testing:{result['target']}/{name}" for name in names)


def environment_args(result: Dict, test_map: Dict) -> str:
    """`NAME=value` lines (the map's ``changedEnvironment``) for a pull request run, or nothing when no journey is selected.

    The pull request tier narrows the audits that loop (the Inventory pages audit covers one representative space instead of
    six); the nightly and release runs do not use ``--changed``, so they get no such variable and run the full loops.
    """
    if not result["journeys"]:
        return ""
    return "\n".join(f"{name}={value}" for name, value in sorted(test_map.get("changedEnvironment", {}).items()))


def unknown_request(result: Dict) -> str:
    """The request for a targeted pick, or an empty string."""
    if not result["unknown"]:
        return ""
    lines = ["NEEDS A PICK: no test mapping for these files (the full suite is the nightly tier, not a fallback):"]
    lines += [f"  {name}" for name in result["unknown"]]
    lines.append("Pick the suites that cover them and run `swift test --filter <Suite>` / "
                 "`tools/ios_uitest.sh -only-testing:FentonHomeUITests/<Class>`, then add a rule to "
                 "contracts/test-map.json so the next change finds them.")
    return "\n".join(lines)


# MARK: - Ledger of passing runs

def tree_hash(root: Path = ROOT) -> str:
    """Hash of the apple/ tree including uncommitted and untracked files, without touching the real index."""
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(tmp) / "index"))
        git("read-tree", "HEAD", env=env, root=root)
        git("add", "-A", "--", *TREE_PATHS, env=env, root=root)
        return git("write-tree", env=env, root=root).strip() or "unknown"


def ledger_key(tree: str, filter_text: str, device: str) -> str:
    """Stable key for one (tree, filter, device) run."""
    return hashlib.sha1("\0".join((tree, filter_text.strip(), device)).encode()).hexdigest()[:20]


def ledger_path(tree: str, filter_text: str, device: str, root: Path = ROOT) -> Path:
    return root / LEDGER_DIR / f"{ledger_key(tree, filter_text, device)}.json"


def seen(tree: str, filter_text: str, device: str, root: Path = ROOT) -> bool:
    """True when this exact run already passed."""
    try:
        return json.loads(ledger_path(tree, filter_text, device, root).read_text()).get("result") == "pass"
    except (OSError, ValueError):
        return False


def result_of(tree: str, filter_text: str, device: str, root: Path = ROOT) -> str:
    """The recorded result of this exact run: ``pass``, ``skipped`` (it ran, but every selected test skipped), or empty."""
    try:
        return str(json.loads(ledger_path(tree, filter_text, device, root).read_text()).get("result") or "")
    except (OSError, ValueError):
        return ""


def record(tree: str, filter_text: str, device: str, root: Path = ROOT, result: str = "pass") -> Path:
    """Record a finished run: ``pass``, or ``skipped`` when no test ran (never a pass, so it cannot short-circuit a later run)."""
    path = ledger_path(tree, filter_text, device, root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"tree": tree, "filter": filter_text, "device": device, "result": result}) + "\n")
    return path


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", nargs="?", choices=("tree-hash", "seen", "record", "result"))
    parser.add_argument("--base", default=None, help="diff base (default: tools/lane_base.py)")
    parser.add_argument("--files", nargs="*", help="use these files instead of the git diff")
    parser.add_argument("--map", default=str(MAP_PATH))
    parser.add_argument("--swift", action="store_true")
    parser.add_argument("--journeys", action="store_true")
    parser.add_argument("--families", action="store_true")
    parser.add_argument("--smoke-families", action="store_true")
    parser.add_argument("--environment", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--device", default="")
    parser.add_argument("--filter", default="")
    parser.add_argument("--tree", default="")
    parser.add_argument("--result", default="pass", choices=("pass", "skipped"))
    args = parser.parse_args(argv)

    if args.command == "tree-hash":
        print(tree_hash())
        return 0
    if args.command in ("seen", "record", "result"):
        tree = args.tree or tree_hash()
        if args.command == "record":
            record(tree, args.filter, args.device, result=args.result)
            return 0
        if args.command == "result":
            print(result_of(tree, args.filter, args.device))
            return 0
        return 0 if seen(tree, args.filter, args.device) else 1

    files = args.files if args.files is not None else changed_files(args.base)
    test_map = load_map(Path(args.map))
    result = select(files, test_map)
    request = unknown_request(result)
    if args.swift:
        print(swift_args(result))
    elif args.journeys:
        print(journey_args(result, args.device))
    elif args.families:
        print(" ".join(result["families"]))
    elif args.smoke_families:
        print(" ".join(result["smoke_families"]))
    elif args.environment:
        print(environment_args(result, test_map))
    elif args.json:
        print(json.dumps(result, indent=1))
    else:
        print(f"files: {len(files)} changed, {len(result['ignored'])} need no tests")
        print(f"swift test: {swift_args(result) or '(none)'}")
        print(f"journeys:   {journey_args(result) or '(none)'}  on {' '.join(result['families']) or 'no device'}"
              + (" (layout-sensitive)" if result["layout_sensitive"] else ""))
        for family, names in result["journeys_by_family"].items():
            if names and names != result["journeys"]:
                print(f"  {family}: {journey_args(result, family)}")
        if result["smoke_families"]:
            print(f"smoke:      --plan Smoke on {' '.join(result['smoke_families'])}")
    if request:
        print(request, file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
