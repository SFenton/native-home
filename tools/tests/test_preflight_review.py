"""``tools/preflight_review.py``: stale doc names, facade guard entries and tests without a ``Fails if:`` line.

Every check is advisory (warn only), so the tests assert findings, not exit codes, apart from the git-error exit.
"""

import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent

spec = importlib.util.spec_from_file_location("preflight_review", TOOLS / "preflight_review.py")
pf = importlib.util.module_from_spec(spec)
sys.modules["preflight_review"] = pf
spec.loader.exec_module(pf)


def sh(root, *args):
    subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)


def write(root, rel, text):
    path = Path(root) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def registry(facades):
    return json.dumps({"patterns": [{"id": "weather", "guards": [{"id": pf.GUARD_ID, "facades": facades}]}]})


class Repo:
    """A fixture git repo with `origin/main` at the base commit and HEAD one change ahead."""

    def __init__(self, tmp, base_files):
        self.root = Path(tmp)
        sh(self.root, "init", "-q", "-b", "main")
        sh(self.root, "config", "user.email", "t@example.com")
        sh(self.root, "config", "user.name", "T")
        for rel, text in base_files.items():
            write(self.root, rel, text)
        self.commit("base")
        sh(self.root, "update-ref", "refs/remotes/origin/main", "HEAD")

    def commit(self, message):
        sh(self.root, "add", "-A")
        sh(self.root, "commit", "-q", "-m", message)

    def findings(self, check, note=""):
        return [f for f in pf.run(self.root, "main", note) if f.check == check]


WIDGET = """public enum Widget {
    public static var title: String { "t" }
    public static func oldHelper() -> Int {
        let tempValue = 1
        return tempValue
    }
    public static var oldHelperName: String { "x" }
    public static var leaves: Int { 2 }
    public enum Nested {
        public static var inner: Int { 3 }
    }
}
"""
DOC = ("# Widget\n\nCall `Widget.oldHelper` for the count, or `oldHelperName`. The tree leaves and the "
       "tempValue stay prose. Also `leaves` and `tempValue`.\nSee apple/Sources/Old/Gone.swift.\n")


def strip(text, *needles):
    return "".join(line + "\n" for line in text.splitlines() if not any(n in line for n in needles))


class StaleDocNameTests(unittest.TestCase):
    def repo(self, tmp, extra=None):
        files = {"apple/Sources/A/Widget.swift": WIDGET, "apple/Sources/Old/Gone.swift": "// gone\n",
                 ".agents/patterns/widget.md": DOC}
        return Repo(tmp, {**files, **(extra or {})})

    def test_removed_members_and_deleted_paths_are_reported_with_line(self):
        """Fails if: a removed member or deleted path no longer produces a finding for the doc line naming it."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp)
            write(repo.root, "apple/Sources/A/Widget.swift", strip(WIDGET, "oldHelperName"))
            body = WIDGET.replace("    public static func oldHelper() -> Int {\n        let tempValue = 1\n        return tempValue\n    }\n", "")
            write(repo.root, "apple/Sources/A/Widget.swift", strip(body, "oldHelperName"))
            (repo.root / "apple/Sources/Old/Gone.swift").unlink()
            repo.commit("remove")
            labels = sorted(f.message.split(",")[0] for f in repo.findings("stale-doc-name"))
            self.assertEqual(labels, ["still names path apple/Sources/Old/Gone.swift",
                                      "still names symbol Widget.oldHelper", "still names symbol oldHelperName"])
            self.assertEqual({f.where for f in repo.findings("stale-doc-name")},
                             {".agents/patterns/widget.md:3", ".agents/patterns/widget.md:4"})

    def test_local_let_plain_word_and_prose_are_not_reported(self):
        """Fails if: a local `let`, a lowercase common word or an unquoted word is reported as a stale name."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp)
            write(repo.root, "apple/Sources/A/Widget.swift", strip(WIDGET, "tempValue", "leaves"))
            repo.commit("remove local and common word")
            self.assertEqual(repo.findings("stale-doc-name"), [])

    def test_nested_member_reports_under_the_nested_type_only(self):
        """Fails if: the enclosing type of a nested member is lost, so the qualified doc name no longer matches."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp, {".agents/patterns/n.md": "Use Nested.inner here, not Widget.inner.\n"})
            write(repo.root, "apple/Sources/A/Widget.swift", strip(WIDGET, "inner"))
            repo.commit("remove nested")
            hits = repo.findings("stale-doc-name")
            self.assertEqual([(f.where, f.message.split(",")[0]) for f in hits],
                             [(".agents/patterns/n.md:1", "still names symbol Nested.inner")])

    def test_test_files_and_archive_docs_are_ignored(self):
        """Fails if: a declaration removed from apple/Tests, or a mention under .agents/archive, is reported."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp, {"apple/Tests/WidgetTests.swift": "struct ScratchHelper {\n    func scratchHelper() {}\n}\n",
                                   ".agents/archive/old.md": "Call `Widget.oldHelper` and `oldHelperName`.\n"})
            write(repo.root, "apple/Tests/WidgetTests.swift", "// emptied\n")
            write(repo.root, ".agents/patterns/widget.md", "# Widget\n")
            write(repo.root, "apple/Sources/A/Widget.swift", strip(WIDGET, "oldHelperName"))
            repo.commit("edit")
            self.assertEqual(repo.findings("stale-doc-name"), [])

    def test_name_redeclared_elsewhere_is_not_reported_but_a_longer_name_does_not_hide_it(self):
        """Fails if: still_declared stops looking at the head, or lets a longer name (a prefix match) hide a removal."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp)
            moved = strip(WIDGET, "oldHelperName")
            write(repo.root, "apple/Sources/A/Widget.swift", moved)
            write(repo.root, "apple/Sources/A/Other.swift", "public enum Other {\n    public static var oldHelperName: String { \"x\" }\n"
                                                           "    public static func oldHelperNameExtra() {}\n}\n")
            repo.commit("move oldHelperName")
            self.assertEqual([f for f in repo.findings("stale-doc-name") if "oldHelperName" in f.message], [])
            declared = pf.declared_on_head(repo.root, "HEAD")
            self.assertTrue(pf.still_declared("oldHelperName", declared))
            self.assertTrue(pf.still_declared("oldHelperNameExtra", declared))
            self.assertFalse(pf.still_declared("oldHelperNam", declared))

    def test_prefix_of_a_declared_name_is_still_reported(self):
        """Fails if: a removed `oldHelperName` is hidden because `oldHelperNameExtra` is declared (ERE `\\b` bug)."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp, {"apple/Sources/A/Other.swift": "public enum Other {\n    public static func oldHelperNameExtra() {}\n}\n"})
            write(repo.root, "apple/Sources/A/Widget.swift", strip(WIDGET, "oldHelperName"))
            repo.commit("remove")
            self.assertEqual([f.message.split(",")[0] for f in repo.findings("stale-doc-name")],
                             ["still names symbol oldHelperName"])

    def test_rename_reports_the_old_path(self):
        """Fails if: a renamed file's old path is not treated as removed."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp)
            sh(repo.root, "mv", "apple/Sources/Old/Gone.swift", "apple/Sources/Old/Moved.swift")
            repo.commit("rename")
            hits = repo.findings("stale-doc-name")
            self.assertEqual(len(hits), 1)
            self.assertIn("path apple/Sources/Old/Gone.swift", hits[0].message)

    def test_scan_decls_pops_nested_types_and_flags_locals(self):
        """Fails if: a member after a nested type is credited to the nested type, or a local counts as a member."""
        by_name = {d.name: d for d in pf.scan_decls(WIDGET.splitlines())}
        self.assertEqual((by_name["inner"].owner, by_name["Nested"].owner, by_name["title"].owner),
                         ("Nested", "Widget", "Widget"))
        self.assertFalse(by_name["tempValue"].member)
        after = pf.scan_decls("enum A {\n    enum B {\n        static var x = 1\n    }\n    static var y = 2\n}\n".splitlines())
        self.assertEqual({d.name: d.owner for d in after}, {"A": "", "B": "A", "x": "B", "y": "A"})

    def test_parse_diff_tracks_added_lines_and_removed_old_lines(self):
        """Fails if: parse_diff loses the new line numbers of additions or the old line numbers of removals."""
        diffs = pf.parse_diff("M\ta.swift\n", "diff --git a/a.swift b/a.swift\n--- a/a.swift\n+++ b/a.swift\n"
                              "@@ -2,1 +2,2 @@\n-    func old()\n+    func new()\n+    func extra()\n")
        self.assertEqual((diffs[0].added, diffs[0].removed), ({2, 3}, [(2, "    func old()")]))


FACADE = """public enum Thing {
    public enum Page {
        public static var inner: String { HouseConfigSource.active.read { $0.thing.inner } ?? "" }
    }
    /// A name.
    public static var known: String { HouseConfigSource.active.read { $0.thing.known } ?? "" }
    public static var fresh: String { HouseConfigSource.active.read { $0.thing.fresh } ?? "" }
    public static func withParams(_ id: String) -> String { HouseConfigSource.active.read { $0.thing[id] } ?? "" }
    public static func color(read: Read) -> Int { read(1) }
}
"""
SOURCE = "apple/Sources/HassCore/Thing.swift"


class FacadeGuardTests(unittest.TestCase):
    def repo(self, tmp, facades):
        write(tmp, "contracts/patterns.json", registry(facades))
        return Repo(tmp, {SOURCE: "public enum Thing {}\n"})

    def test_new_member_after_a_nested_type_is_reported_under_the_outer_type(self):
        """Fails if: a member following a nested type is attributed to the nested type (or to nothing)."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp, {"Thing": ["known"], "Page": ["inner"]})
            write(repo.root, SOURCE, FACADE)
            repo.commit("add")
            hits = repo.findings("facade-guard")
            self.assertEqual([f.where for f in hits], [SOURCE + ":7"])
            self.assertIn("Thing.fresh", hits[0].message)

    def test_listed_members_parameter_functions_and_read_parameters_are_clean(self):
        """Fails if: a listed member, a parameterised func or a `read:` parameter is reported."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp, {"Thing": ["known", "fresh"], "Page": ["inner"]})
            write(repo.root, SOURCE, FACADE)
            repo.commit("add")
            self.assertEqual(repo.findings("facade-guard"), [])

    def test_house_config_source_itself_is_not_a_facade(self):
        """Fails if: the HouseConfigSource.active mechanism is reported as a facade."""
        lines = ("public enum HouseConfigSource {\n    public static var active: Store { HouseConfigSource.active.read { $0 } }\n"
                 "    public static func read<T>(_ f: (X) -> T) -> T? { nil }\n}\n").splitlines()
        self.assertEqual(pf.facade_members(lines), [])

    def test_untouched_unlisted_member_is_not_reported(self):
        """Fails if: a facade member the diff did not touch is reported."""
        with TemporaryDirectory() as tmp:
            repo = self.repo(tmp, {})
            write(repo.root, "apple/Sources/HassCore/Other.swift", "enum Other { static let x = 1 }\n")
            repo.commit("unrelated")
            self.assertEqual(repo.findings("facade-guard"), [])

    def test_member_through_a_local_read_helper_is_reported(self):
        """Fails if: a member that calls the file's own `read { }` helper is missed."""
        source = ("public enum Bed {\n    private static func read<T>(_ f: (X) -> T) -> T? {\n"
                  "        HouseConfigSource.active.read { f($0.bed) }\n    }\n"
                  "    public static var pump: String { read { $0.pump } ?? \"\" }\n}\n")
        self.assertEqual([(t, n) for _, t, n, _ in pf.facade_members(source.splitlines())], [("Bed", "pump")])

    def test_real_registry_map_is_loaded_through_pattern_guard(self):
        """Fails if: the facade map no longer loads from contracts/patterns.json through pattern_guard."""
        self.assertIn("HomeConfig", pf.load_facades(REPO))


SWIFT_TESTS = """final class ThingTests: XCTestCase {
    /// Fails if: the title stops being trimmed.
    func testTitleIsTrimmed() {}

    func testUndocumented() {}
}
"""
PY_TESTS = '''class T(unittest.TestCase):
    def test_documented(self):
        """Fails if: the parser drops the last row."""

    # Fails if: the flag is ignored.
    def test_commented(self):
        pass

    def test_bare(self):
        pass

    def test_string(self):
        text = """
def test_inside_a_string(self):
    pass
"""
        self.assertTrue(text)
'''


class FailsIfTests(unittest.TestCase):
    def test_swift_test_without_a_fails_if_line_warns(self):
        """Fails if: an undocumented Swift test is not reported, or a documented one is."""
        with TemporaryDirectory() as tmp:
            repo = Repo(tmp, {"apple/Tests/HassCoreTests/ThingTests.swift": "final class ThingTests {}\n"})
            write(repo.root, "apple/Tests/HassCoreTests/ThingTests.swift", SWIFT_TESTS)
            repo.commit("tests")
            self.assertEqual([f.where for f in repo.findings("fails-if")], ["apple/Tests/HassCoreTests/ThingTests.swift:5"])

    def test_python_ast_ignores_a_def_inside_a_string_literal(self):
        """Fails if: a `def test_` inside a string counts as a test, or a docstring/comment `Fails if:` is missed."""
        with TemporaryDirectory() as tmp:
            repo = Repo(tmp, {"tools/tests/test_x.py": "import unittest\n"})
            write(repo.root, "tools/tests/test_x.py", "import unittest\n" + PY_TESTS)
            repo.commit("tests")
            self.assertEqual(sorted(f.message.split()[0] for f in repo.findings("fails-if")), ["test_bare", "test_string"])

    def test_regex_fallback_when_the_file_does_not_parse(self):
        """Fails if: an unparsable Python test file stops being checked at all."""
        found = pf.test_functions("tools/tests/test_y.py", ["def test_a(self):", "    x = (", ""])
        self.assertEqual([name for _, name, _ in found], ["test_a"])

    def test_note_line_naming_the_test_covers_it(self):
        """Fails if: a `Fails if` PR-note line naming the test no longer covers it."""
        with TemporaryDirectory() as tmp:
            repo = Repo(tmp, {"tools/tests/test_x.py": "import unittest\n"})
            write(repo.root, "tools/tests/test_x.py", "import unittest\n" + PY_TESTS)
            repo.commit("tests")
            covered = repo.findings("fails-if", "Fails if: test_bare and test_string pass when the flag is off")
            self.assertEqual(covered, [])
            self.assertEqual(len(repo.findings("fails-if", "test_bare is great")), 2)

    def test_tests_that_already_existed_are_not_reported(self):
        """Fails if: a test the diff did not add is reported."""
        with TemporaryDirectory() as tmp:
            repo = Repo(tmp, {"tools/tests/test_x.py": "import unittest\n" + PY_TESTS})
            write(repo.root, "tools/tests/test_x.py", "import unittest\n" + PY_TESTS + "\n# trailing\n")
            repo.commit("touch")
            self.assertEqual(repo.findings("fails-if"), [])


class CliTests(unittest.TestCase):
    def run_cli(self, root, *args):
        return subprocess.run([sys.executable, str(TOOLS / "preflight_review.py"), "--base", "main", *args],
                              cwd=root, capture_output=True, text=True)

    def test_findings_never_change_the_exit_code(self):
        """Fails if: a finding makes the CLI exit non-zero (all checks are advisory)."""
        with TemporaryDirectory() as tmp:
            repo = Repo(tmp, {"apple/Sources/Old/Gone.swift": "// gone\n", ".agents/a.md": "see apple/Sources/Old/Gone.swift\n"})
            (repo.root / "apple/Sources/Old/Gone.swift").unlink()
            repo.commit("delete")
            done = self.run_cli(repo.root)
            self.assertEqual(done.returncode, 0)
            self.assertIn("warn [stale-doc-name] .agents/a.md:1", done.stdout)

    def test_clean_diff_and_unknown_base(self):
        """Fails if: a clean diff does not print `preflight: clean`, or an unknown base does not exit 2."""
        with TemporaryDirectory() as tmp:
            repo = Repo(tmp, {"a.txt": "1\n"})
            write(repo.root, "a.txt", "2\n")
            repo.commit("edit")
            done = self.run_cli(repo.root)
            self.assertEqual((done.returncode, done.stdout.strip()), (0, "preflight: clean"))
            self.assertEqual(self.run_cli(repo.root, "--base", "nosuchref").returncode, 2)


if __name__ == "__main__":
    unittest.main()
