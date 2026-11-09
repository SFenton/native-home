"""``tools/test_impact.py``: line-range compaction, lcov parsing, profile grouping, stats."""

import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import test_impact  # noqa: E402

LCOV = """SF:/Users/x/repo/apple/Sources/HassUI/Features/Chores/ChoresView.swift
FN:10,body
DA:10,3
DA:11,3
DA:12,0
DA:13,1
DA:20,2
end_of_record
SF:/Users/x/repo/apple/Sources/HassCore/Store.swift
DA:1,0
end_of_record
SF:/Applications/Xcode.app/SDK/Foo.swift
DA:1,5
end_of_record
SF:/Users/x/repo/apple/Apps/iOS/App.swift
DA:1,5
end_of_record
"""


class CompactTests(unittest.TestCase):
    def test_runs_merge_and_duplicates_collapse(self):
        self.assertEqual(test_impact.compact([5, 1, 2, 3, 3, 9, 10]), [[1, 3], [5, 5], [9, 10]])
        self.assertEqual(test_impact.compact([]), [])

    def test_expand_inverts_compact(self):
        self.assertEqual(test_impact.expand([[1, 3], [7, 7]]), [1, 2, 3, 7])


class ParseTests(unittest.TestCase):
    def test_keeps_only_executed_lines_of_source_files_repo_relative(self):
        parsed = test_impact.parse_lcov(LCOV)
        self.assertEqual(parsed, {"apple/Sources/HassUI/Features/Chores/ChoresView.swift": [[10, 11], [13, 13], [20, 20]]})

    def test_repo_relative_ignores_other_paths(self):
        self.assertIsNone(test_impact.repo_relative("/x/apple/Apps/iOS/A.swift"))
        self.assertEqual(test_impact.repo_relative("/a/b/apple/Sources/X/Y.swift"), "apple/Sources/X/Y.swift")


class GroupTests(unittest.TestCase):
    def test_profiles_group_by_class_and_test_and_empty_files_are_dropped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "A.testOne.123.4.profraw").write_bytes(b"x")
            (root / "A.testOne.456.4.profraw").write_bytes(b"x")
            (root / "A.testTwo.789.4.profraw").write_bytes(b"x")
            (root / "A.testEmpty.1.4.profraw").write_bytes(b"")
            groups = test_impact.group_profiles(root)
        self.assertEqual({k: len(v) for k, v in groups.items()}, {"A.testOne": 2, "A.testTwo": 1})


class StatsTests(unittest.TestCase):
    DATA = {
        "C.a": {"f1": [[1, 5]], "f2": [[1, 1]]},
        "C.b": {"f1": [[4, 9]]},
        "C.c": {"f1": [[20, 30]], "f3": [[2, 2]]},
    }

    def test_stats_counts_files_lines_and_coverage(self):
        summary = test_impact.stats(self.DATA)
        self.assertEqual(summary["per_test"]["C.a"], (2, 6))
        self.assertEqual(summary["files_per_test"], {"median": 2, "max": 2})
        self.assertEqual(list(summary["per_file"].items())[0], ("f1", 3))

    def test_covering_by_file_and_by_line_range(self):
        self.assertEqual(test_impact.covering(self.DATA, "f1"), ["C.a", "C.b", "C.c"])
        self.assertEqual(test_impact.covering(self.DATA, "f1", (5, 6)), ["C.a", "C.b"])
        self.assertEqual(test_impact.covering(self.DATA, "f1", (10, 19)), [])
        self.assertEqual(test_impact.covering(self.DATA, "missing"), [])


if __name__ == "__main__":
    unittest.main()
