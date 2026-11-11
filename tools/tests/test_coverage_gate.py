"""Coverage classification and measurement (``tools/coverage_gate.py``).

Each test builds a small source tree and LLVM export in a temporary directory, so nothing here runs a
build or reads the real ``.build``.
"""

import contextlib
import io
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools import coverage_gate

RULES = {
    "thresholds": {"logic": 95},
    "swift": {
        "sourceRoots": ["apple/Sources/**/*.swift"],
        "logic": ["apple/Sources/Core/**/*.swift", "apple/Sources/Model/**/*.swift"],
        "unmeasured": ["apple/Sources/UI/**/*.swift"],
        "exclude": [],
    },
}


class CoverageGateTests(unittest.TestCase):
    """The gate names unclassified files and measures declaration-only files as zero lines."""

    def setUp(self) -> None:
        self.tmp = TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def write_sources(self, *names: str) -> None:
        for name in names:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// source\n", encoding="utf-8")

    def report(self, lines: dict[str, tuple[int, int]]) -> Path:
        files = [
            {"filename": str(self.root / name), "summary": {"lines": {"covered": covered, "count": count}}}
            for name, (covered, count) in lines.items()
        ]
        path = self.root / "report.json"
        path.write_text(json.dumps({"data": [{"files": files}]}), encoding="utf-8")
        return path

    def run_gate(self, *args: str) -> tuple[int, str, str]:
        rules = self.root / "rules.json"
        rules.write_text(json.dumps(RULES), encoding="utf-8")
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = coverage_gate.main(
                ["--language", "swift", "--root", str(self.root), "--rules", str(rules), *args]
            )
        return status, out.getvalue(), err.getvalue()

    def test_classify_only_names_each_unclassified_file_and_module(self) -> None:
        self.write_sources(
            "apple/Sources/Core/A.swift",
            "apple/Sources/UI/B.swift",
            "apple/Sources/Telemetry/Log.swift",
            "apple/Sources/Telemetry/Sub/Record.swift",
        )
        status, _, err = self.run_gate("--classify-only")
        self.assertEqual(status, 1)
        self.assertIn("2 production source file(s) are not classified", err)
        self.assertIn("apple/Sources/Telemetry", err)
        self.assertIn("\n  apple/Sources/Telemetry/Log.swift", err)
        self.assertIn("\n  apple/Sources/Telemetry/Sub/Record.swift", err)

    def test_classify_only_needs_no_report_and_passes_when_complete(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        status, out, err = self.run_gate("--classify-only")
        self.assertEqual((status, err), (0, ""))
        self.assertIn("swift.logic: 1 source files classified", out)

    def test_report_is_required_without_classify_only(self) -> None:
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            self.run_gate()

    def test_declaration_only_file_counts_as_zero_lines_and_is_listed(self) -> None:
        self.write_sources(
            "apple/Sources/Core/A.swift",
            "apple/Sources/Core/Protocol.swift",
            "apple/Sources/UI/B.swift",
        )
        report = self.report({"apple/Sources/Core/A.swift": (96, 100), "apple/Sources/UI/B.swift": (19, 20)})
        status, out, err = self.run_gate("--report", str(report))
        self.assertEqual((status, err), (0, ""))
        self.assertIn("1 file(s) have no LLVM record", out)
        self.assertIn("\n  apple/Sources/Core/Protocol.swift", out)
        self.assertIn("swift.logic: 96/100 lines = 96.00% across 2 files", out)

    def test_module_with_no_records_is_an_error(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/Model/M.swift")
        report = self.report({"apple/Sources/Core/A.swift": (96, 100)})
        status, _, err = self.run_gate("--report", str(report))
        self.assertEqual(status, 1)
        self.assertIn("no coverage records for module(s) apple/Sources/Model", err)

    def test_low_coverage_fails_with_the_number(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/A.swift": (90, 100), "apple/Sources/UI/B.swift": (9, 10)})
        status, out, err = self.run_gate("--report", str(report))
        self.assertEqual(status, 1)
        self.assertIn("swift.logic: 90.00% is below 95%", err)
        self.assertNotIn("swift.ux", out)
        self.assertNotIn("swift.unmeasured", out)

    def test_unmeasured_file_never_fails_or_is_reported(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift", "apple/Sources/UI/C.swift")
        # B is at 0% and C has no record at all; the module has records, so neither is an error or a line.
        report = self.report({"apple/Sources/Core/A.swift": (96, 100), "apple/Sources/UI/B.swift": (0, 50)})
        status, out, err = self.run_gate("--report", str(report))
        self.assertEqual((status, err), (0, ""))
        self.assertIn("swift.logic: 96/100", out)
        self.assertNotIn("UI/", out)
        self.assertNotIn("unmeasured", out)

    def test_unmeasured_module_with_no_records_is_not_an_error(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/A.swift": (96, 100)})
        status, _, err = self.run_gate("--report", str(report))
        self.assertEqual((status, err), (0, ""))

    def test_logic_is_still_gated_beside_unmeasured_source(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/A.swift": (94, 100), "apple/Sources/UI/B.swift": (10, 10)})
        status, _, err = self.run_gate("--report", str(report))
        self.assertEqual(status, 1)
        self.assertIn("swift.logic: 94.00% is below 95%", err)

    def test_files_on_only_unmeasured_files_has_nothing_to_gate(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/A.swift": (1, 100), "apple/Sources/UI/B.swift": (0, 20)})
        status, out, err = self.run_gate("--report", str(report), "--files", "apple/Sources/UI/B.swift")
        self.assertEqual((status, err), (0, ""))
        self.assertIn("swift: no changed file is subject to coverage; nothing to gate", out)

    def test_baseline_ux_entries_from_an_old_file_are_ignored(self) -> None:
        self.write_sources("apple/Sources/Core/Z.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/Z.swift": (50, 100), "apple/Sources/UI/B.swift": (1, 20)})
        baseline = self.root / "baseline.json"
        baseline.write_text(json.dumps({"apple/Sources/Core/Z.swift": 50.0, "apple/Sources/UI/B.swift": 90.0}), encoding="utf-8")
        args = ("--report", str(report), "--baseline", str(baseline), "--files")
        self.assertEqual(self.run_gate(*args, "apple/Sources/Core/Z.swift", "apple/Sources/UI/B.swift")[0], 0)

    def test_new_unclassified_folder_fails_classification_by_name(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift", "apple/Sources/NewKit/N.swift")
        status, _, err = self.run_gate("--classify-only")
        self.assertEqual(status, 1)
        self.assertIn("apple/Sources/NewKit", err)
        self.assertIn("not classified as logic, unmeasured", err)

    def test_unmeasured_must_not_carry_a_threshold(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        RULES["thresholds"]["unmeasured"] = 95
        self.addCleanup(RULES["thresholds"].pop, "unmeasured")
        status, _, err = self.run_gate("--classify-only")
        self.assertEqual(status, 1)
        self.assertIn("never unmeasured", err)

    def test_files_gates_only_the_changed_files(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/Core/Z.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/A.swift": (96, 100), "apple/Sources/Core/Z.swift": (10, 100),
                              "apple/Sources/UI/B.swift": (19, 20)})
        status, out, err = self.run_gate("--report", str(report), "--files", "apple/Sources/Core/A.swift")
        self.assertEqual((status, err), (0, ""))
        self.assertIn("swift.logic: changed files 96/100", out)
        status, _, err = self.run_gate("--report", str(report), "--files", "apple/Sources/Core/Z.swift")
        self.assertEqual(status, 1)
        self.assertIn("changed files at 10.00% are below 95%", err)

    def test_files_baseline_lets_an_old_gap_stand_but_not_a_regression(self) -> None:
        self.write_sources("apple/Sources/Core/Z.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/Z.swift": (50, 100), "apple/Sources/UI/B.swift": (19, 20)})
        baseline = self.root / "baseline.json"
        baseline.write_text(json.dumps({"apple/Sources/Core/Z.swift": 50.0}), encoding="utf-8")
        args = ("--report", str(report), "--files", "apple/Sources/Core/Z.swift", "--baseline", str(baseline))
        self.assertEqual(self.run_gate(*args)[0], 0)
        baseline.write_text(json.dumps({"apple/Sources/Core/Z.swift": 80.0}), encoding="utf-8")
        status, _, err = self.run_gate(*args)
        self.assertEqual(status, 1)
        self.assertIn("below its baseline 80.00%", err)

    def test_files_ignores_files_outside_every_category(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/A.swift": (1, 100), "apple/Sources/UI/B.swift": (19, 20)})
        status, out, _ = self.run_gate("--report", str(report), "--files", "README.md")
        self.assertEqual(status, 0)
        self.assertIn("nothing to gate", out)

    def test_unclassified_file_fails_but_still_reports_numbers(self) -> None:
        self.write_sources(
            "apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift", "apple/Sources/Extra/C.swift"
        )
        report = self.report({"apple/Sources/Core/A.swift": (96, 100), "apple/Sources/UI/B.swift": (9, 10)})
        status, out, err = self.run_gate("--report", str(report))
        self.assertEqual(status, 1)
        self.assertIn("\n  apple/Sources/Extra/C.swift", err)
        self.assertIn("swift.logic: 96/100", out)

    def foreign_report(self, foreign: dict[str, tuple[int, int]], local: dict[str, tuple[int, int]]) -> Path:
        files = [
            {"filename": name, "summary": {"lines": {"covered": c, "count": n}}}
            for name, (c, n) in foreign.items()
        ]
        files += [
            {"filename": str(self.root / name), "summary": {"lines": {"covered": c, "count": n}}}
            for name, (c, n) in local.items()
        ]
        path = self.root / "report.json"
        path.write_text(json.dumps({"data": [{"files": files}]}), encoding="utf-8")
        return path

    def test_changed_file_missing_because_records_came_from_another_checkout_fails_loudly(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.foreign_report(
            {"/other/checkout/apple/Sources/Core/A.swift": (10, 10), "/other/checkout/apple/Sources/UI/B.swift": (1, 1)},
            {},
        )
        status, out, err = self.run_gate("--report", str(report), "--files", "apple/Sources/Core/A.swift")
        self.assertEqual(status, 1)
        self.assertIn("2 records are under /other/checkout/apple/Sources, outside this checkout", err)
        self.assertNotIn("declarations only", out)

    def test_changed_file_missing_with_no_drops_keeps_the_old_message(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/UI/B.swift": (19, 20)})
        status, out, err = self.run_gate("--report", str(report), "--files", "apple/Sources/Core/A.swift")
        self.assertEqual(status, 0)
        self.assertIn("has no LLVM record (declarations only, or compiled only for iOS)", out)
        self.assertNotIn("outside this checkout", err)

    def test_sdk_records_outside_the_root_are_not_counted_as_drops(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift")
        report = self.foreign_report({"/Applications/Xcode.app/SDK/Foundation.swift": (1, 2)}, {})
        dropped: list[str] = []
        coverage_gate.llvm_file_totals([report], self.root, dropped)
        self.assertEqual(dropped, [])

    def test_in_root_records_are_unchanged_when_foreign_records_sit_beside_them(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.foreign_report(
            {"/other/checkout/apple/Sources/Core/Z.swift": (1, 1)},
            {"apple/Sources/Core/A.swift": (96, 100), "apple/Sources/UI/B.swift": (19, 20)},
        )
        status, out, err = self.run_gate("--report", str(report), "--files", "apple/Sources/Core/A.swift")
        self.assertEqual((status, err), (0, ""))
        self.assertIn("swift.logic: changed files 96/100", out)

    def test_module_of_uses_the_directory_under_sources(self) -> None:
        self.assertEqual(
            coverage_gate.module_of("apple/Sources/HassUI/Features/Feedback/Sheet.swift"),
            "apple/Sources/HassUI",
        )
        self.assertEqual(coverage_gate.module_of("tools/x.swift"), "tools")


if __name__ == "__main__":
    unittest.main()
