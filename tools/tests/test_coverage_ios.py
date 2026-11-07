"""iOS coverage export path remap (``tools/coverage_ios.py``) against the gate's reader.

The tests build small LLVM JSON exports in a temporary directory; no build or simulator runs.
"""

import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools import coverage_gate, coverage_ios

ROOT = Path("/work/this-checkout")
FOREIGN = "/work/other/.claude/worktrees/agent-x"
SDK = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/include/x.h"
FILE = "apple/Sources/HassUI/UIKitPort/UKPage.swift"


def record(name: str, covered: int, count: int = 10) -> dict:
    """One LLVM file record with line totals."""
    return {"filename": name, "summary": {"lines": {"covered": covered, "count": count}}}


def export(*records: dict) -> dict:
    """An LLVM export payload holding the records."""
    return {"type": "llvm.coverage.json.export", "version": "2.0.1", "data": [{"files": list(records)}]}


class RemapTests(unittest.TestCase):
    """Foreign-worktree source paths move to this root; everything else stays."""

    def test_foreign_worktree_is_found_by_the_gate_after_remap(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            payload = export(record(f"{FOREIGN}/{FILE}", 7))
            self.assertEqual(coverage_ios.remap_to_root(payload, root), {FOREIGN: 1})
            report = root / "ios.json"
            report.write_text(json.dumps(payload))
            self.assertEqual(coverage_gate.llvm_file_totals([report], root), {FILE: (7, 10)})

    def test_names_under_root_are_unchanged(self) -> None:
        payload = export(record(f"{ROOT}/{FILE}", 3), record(f"{ROOT}/apple/Apps/iOS/A.swift", 1))
        before = json.dumps(payload)
        self.assertEqual(coverage_ios.remap_to_root(payload, ROOT), {})
        self.assertEqual(json.dumps(payload), before)

    def test_sdk_paths_are_unchanged(self) -> None:
        payload = export(record(SDK, 1), record("/private/var/folders/x/gen.swift", 1))
        before = json.dumps(payload)
        self.assertEqual(coverage_ios.remap_to_root(payload, ROOT), {})
        self.assertEqual(json.dumps(payload), before)

    def test_apps_and_tests_folders_remap_too(self) -> None:
        payload = export(record(f"{FOREIGN}/apple/Apps/iOS/A.swift", 1), record(f"{FOREIGN}/apple/Tests/T.swift", 1))
        self.assertEqual(coverage_ios.remap_to_root(payload, ROOT), {FOREIGN: 2})
        self.assertEqual([r["filename"] for r in payload["data"][0]["files"]],
                         [f"{ROOT}/apple/Apps/iOS/A.swift", f"{ROOT}/apple/Tests/T.swift"])

    def test_ios_and_mac_records_for_one_file_still_merge_to_the_better(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            mac = root / "mac.json"
            ios = root / "ios.json"
            out = root / "merged.json"
            mac.write_text(json.dumps(export(record(f"{root}/{FILE}", 2, 5))))
            payload = export(record(f"{FOREIGN}/{FILE}", 9, 12))
            coverage_ios.remap_to_root(payload, root)
            ios.write_text(json.dumps(payload))
            coverage_ios.merge([mac, ios], out)
            self.assertEqual(coverage_gate.llvm_file_totals([out], root), {FILE: (9, 12)})


if __name__ == "__main__":
    unittest.main()
