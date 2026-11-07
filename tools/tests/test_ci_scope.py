"""tools/ci_scope.py: when a pull request may skip the compile checks."""

import sys
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_scope as s  # noqa: E402


class ScopeTests(unittest.TestCase):
    def test_docs_only_changes_skip(self):
        self.assertFalse(s.needs_compile(["README.md", ".agents/workflow/ci.md", ".agents/design/mockups/a/b.html",
                                          ".claude/settings.json", ".github/pull_request_template.md", "PROGRESS.md"]))
        self.assertEqual(s.scope(["README.md", ".agents/a.md"]), "docs")

    def test_tools_only_changes_run_the_python_tests_but_no_swift(self):
        for path in ("tools/devcap.py", "tools/hooks/tier_guard.py", "tools/tests/test_x.py", "contracts/test-map.json",
                     "contracts/test-map.schema.json", "docs/a.html", "tools/test_plans.py"):
            files = ["docs/a.md", path]
            self.assertEqual(s.scope(files), "tools", path)
            self.assertFalse(s.needs_compile(files), path)
            self.assertFalse(s.needs_release(files), path)

    def test_anything_else_runs_swift_tests(self):
        for path in ("apple/Sources/HassUI/A.swift", "tools/push_fixtures/relay.json", "contracts/patterns.json",
                     ".github/workflows/pr-checks.yml", "apple/Package.resolved", "Makefile"):
            self.assertTrue(s.needs_compile(["docs/a.md", path]), path)
            self.assertEqual(s.scope(["tools/a.py", path]), "app", path)

    def test_the_release_build_runs_only_when_apple_changes(self):
        self.assertTrue(s.needs_release(["tools/a.py", "apple/Sources/HassUI/A.swift"]))
        self.assertTrue(s.needs_release(["apple/project.yml"]))
        self.assertFalse(s.needs_release(["Makefile", ".github/workflows/nightly.yml", "tools/push_fixtures/relay.json"]))
        self.assertTrue(s.needs_release([]))

    def test_empty_diff_runs_everything(self):
        self.assertTrue(s.needs_compile([]))

    def test_a_huge_file_list_still_decides_correctly(self):
        many = ["apple/Sources/HassUI/File%d.swift" % i for i in range(5000)]
        self.assertTrue(s.needs_compile(many))
        self.assertTrue(s.needs_compile([".agents/a%d.md" % i for i in range(5000)] + many[:1]))
        self.assertFalse(s.needs_compile(["tools/t%d.py" % i for i in range(5000)]))
        self.assertFalse(s.needs_compile([".agents/a%d.md" % i for i in range(5000)]))

    def test_cli_prints_the_decision_and_fails_open(self):
        cases = ((["x.md"], ["app=false", "release=false", "scope=docs"]),
                 (["tools/a.py"], ["app=false", "release=false", "scope=tools"]),
                 (["apple/A.swift"], ["app=true", "release=true", "scope=app"]),
                 (["Makefile"], ["app=true", "release=false", "scope=app"]),
                 (None, ["app=true", "release=true", "scope=app"]))
        for files, expect in cases:
            out = StringIO()
            with mock.patch.object(s, "changed_files", return_value=files), redirect_stdout(out):
                self.assertEqual(s.main(["--base", "abc"]), 0)
            self.assertEqual(out.getvalue().split(), expect)
