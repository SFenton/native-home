#!/usr/bin/env python3
"""Generate `contracts/components.json`: every shared view, type and modifier, with its owner.

The scope is `componentScopes` in `contracts/patterns.json` (`HassDesign`, `HassUI/Common`, `HassUI/Controls`).
Each entry holds the type (or modifier), its file, the pattern that owns it (or the reason it is internal), the
tests that cover its file (`contracts/test-map.json`, same selection as `tools/affected_tests.py`) and a
`systemApi` note taken from `.agents/design/apple/system-api-audit.md` when the audit covers it.

    python3 tools/components_index.py            # rewrite contracts/components.json
    python3 tools/components_index.py --check    # exit 1 when the file is stale (run by pr-checks)

Standard library only.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = "contracts/components.json"
AUDIT = ".agents/design/apple/system-api-audit.md"
TYPE_RE = re.compile(r"^(?P<access>(?:public|open|package|internal|private|fileprivate)\s+)?(?:final\s+)?"
                     r"(?P<kind>struct|class|enum|protocol|actor)\s+(?P<name>\w+)")
VIEW_EXT_RE = re.compile(r"^(?:public\s+)?extension\s+(?:SwiftUI\.)?View\b")
FUNC_RE = re.compile(r"^ {4}(?P<access>(?:public|open|package|internal|private|fileprivate)\s+)?(?:@\w+(?:\([^)]*\))?\s+)*"
                     r"(?:nonisolated\s+)?func\s+(?P<name>\w+)")


def _load(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def audit_notes(root: Path) -> list[tuple[str, str]]:
    """(matcher, note) pairs from the system-API audit table; a matcher ending in `*` is a prefix."""
    path = root / AUDIT
    if not path.is_file():
        return []
    notes = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| `"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split(" | ")]
        if len(cells) < 4:
            continue
        bold = re.search(r"\*\*(.+?)\*\*", cells[-1])
        verdict = re.sub(r"\s+", " ", (bold.group(1) if bold else cells[-1])).strip().rstrip(".,;")
        alternative = re.sub(r"\s+", " ", cells[1])[:200].rstrip(" ,;:.")
        note = f"{verdict}. System alternative: {alternative}. See {AUDIT}."
        for token in re.findall(r"`([A-Za-z_][\w*]*)`", cells[0]):
            notes.append((token, note))
    return notes


def system_api(name: str, stem: str, notes: list[tuple[str, str]]) -> str | None:
    """The audit note for a component: matched on its own name first, then on its file stem."""
    for candidate in (name, stem):
        for token, note in notes:
            if (token.endswith("*") and candidate.startswith(token[:-1])) or candidate == token:
                return note
    return None


def extract(text: str) -> list[tuple[str, str]]:
    """(kind, name) for each non-private top-level type and each non-private `View` modifier in a Swift file."""
    found: list[tuple[str, str]] = []
    in_view_extension = False
    for line in text.splitlines():
        if line.startswith("}"):
            in_view_extension = False
            continue
        if VIEW_EXT_RE.match(line):
            in_view_extension = True
            continue
        if (m := TYPE_RE.match(line)) and (m.group("access") or "").strip() not in ("private", "fileprivate"):
            found.append((m.group("kind"), m.group("name")))
        elif in_view_extension and (f := FUNC_RE.match(line)) and (f.group("access") or "").strip() not in (
                "private", "fileprivate"):
            found.append(("modifier", f.group("name")))
    return found


def build(root: Path = ROOT) -> dict[str, Any]:
    """The components document for `root`."""
    guard = _load("pattern_guard_for_components", HERE / "pattern_guard.py")
    affected = _load("affected_tests_for_components", HERE / "affected_tests.py")
    data = guard.load(root)
    test_map = affected.load_map(root / "contracts" / "test-map.json")
    notes = audit_notes(root)
    components = []
    for rel in guard.scope_files(data, root):
        text = (root / rel).read_text(encoding="utf-8", errors="replace")
        entries = extract(text) or [("extension", Path(rel).stem)]
        stem = Path(rel).stem
        pattern = guard.owning_pattern(data, rel)
        internal = guard.internal_reason(data, rel)
        picked = affected.select([rel], test_map, root)
        seen: set[tuple[str, str]] = set()
        for kind, name in entries:
            if (kind, name) in seen:  # overloads (AlertCopy.alert(...)) are one component
                continue
            seen.add((kind, name))
            entry: dict[str, Any] = {"name": name, "kind": kind, "file": rel, "pattern": pattern}
            if internal is not None:
                entry["internal"] = True
                entry["internalReason"] = internal
            entry["tests"] = {"swift": picked["swift"], "journeys": picked["journeys"]}
            note = system_api(name, stem, notes)
            if note:
                entry["systemApi"] = note
            components.append(entry)
    components.sort(key=lambda e: (e["file"], e["name"]))
    return {"schemaVersion": 1,
            "description": ("Generated by tools/components_index.py from the files in contracts/patterns.json "
                            "componentScopes; do not edit by hand. pattern: the owning pattern id; tests: the "
                            "swift test filters and journey classes that cover the file (contracts/test-map.json); "
                            "systemApi: the verdict of .agents/design/apple/system-api-audit.md when it covers the "
                            "component."),
            "components": components}


def render(doc: dict[str, Any]) -> str:
    """Canonical JSON text of the document."""
    return json.dumps(doc, indent=1, ensure_ascii=False) + "\n"


def main(argv: list[str] | None = None) -> int:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="exit 1 when contracts/components.json is stale")
    args = parser.parse_args(argv)
    text = render(build())
    target = ROOT / OUT
    if args.check:
        current = target.read_text(encoding="utf-8") if target.is_file() else ""
        if current != text:
            print(f"{OUT} is stale: run `python3 tools/components_index.py` and commit the result")
            return 1
        print(f"{OUT} is up to date")
        return 0
    target.write_text(text, encoding="utf-8")
    doc = json.loads(text)["components"]
    print(f"wrote {OUT}: {len(doc)} components")
    return 0


if __name__ == "__main__":
    sys.exit(main())
