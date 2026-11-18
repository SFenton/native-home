"""Comment-only diffs are dropped from the changed-file coverage gate (``tools/coverage_gate.py``).

Each test makes a throwaway git repository, commits a Swift file, edits it and asks the gate what it
would still check, so the classifier is proven against real ``git diff`` output.
"""

import contextlib
import io
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools import coverage_gate

NAME = "apple/Sources/Core/Thing.swift"
BASE = """import Foundation

/// Doubles a value.
func double(_ value: Int) -> Int {
    // multiply
    let result = value * 2
    /* old
       block */
    return result
}
"""


class CommentOnlyTests(unittest.TestCase):
    """The gate skips a diff that provably leaves code unchanged and gates every doubtful one."""

    def setUp(self) -> None:
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.git("init", "-q")
        self.write(BASE)
        self.git("add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
        self.base = self.git("rev-parse", "HEAD").strip()

    def git(self, *args: str) -> str:
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True, check=True).stdout

    def commit(self) -> None:
        """Commit the current file as the new base."""
        self.git("add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base2")
        self.base = self.git("rev-parse", "HEAD").strip()

    def write_bytes(self, text: str) -> None:
        """Write ``text`` with its line endings untouched."""
        path = self.root / NAME
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode("utf-8"))

    def write(self, text: str) -> None:
        path = self.root / NAME
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def drop(self) -> tuple[list[str], str]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            kept = coverage_gate.drop_comment_only([NAME], self.base, self.root)
        return kept, out.getvalue()

    def assertSkipped(self, text: str) -> None:
        self.write(text)
        kept, out = self.drop()
        self.assertEqual(kept, [])
        self.assertIn(f"skipped (comment-only): {NAME}", out)

    def assertGated(self, text: str) -> None:
        self.write(text)
        kept, out = self.drop()
        self.assertEqual(kept, [NAME])
        self.assertNotIn("skipped", out)

    def test_comment_only_diff_is_skipped(self) -> None:
        self.assertSkipped(BASE.replace("// multiply", "/// multiply it\n    // twice").replace("/// Doubles", "// Doubles"))

    def test_block_comment_edit_is_skipped(self) -> None:
        self.assertSkipped(BASE.replace("       block */", "       block, reworded\n       again */"))

    def test_nested_block_comment_is_skipped(self) -> None:
        self.assertSkipped(BASE.replace("/* old", "/* old /* inner */ still comment"))

    def test_whitespace_only_change_is_skipped(self) -> None:
        self.assertSkipped(BASE.replace("    let result", "        let result").replace("import Foundation\n", "import Foundation  \n\n"))

    def test_trailing_comment_edit_is_skipped(self) -> None:
        self.assertSkipped(BASE.replace("value * 2", "value * 2 // twice"))

    def test_uncommenting_by_removing_markers_is_gated(self) -> None:
        old = "func f() {\n    /*\n    run()\n    */\n}\n"
        self.write(old)
        self.commit()
        self.assertGated("func f() {\n    run()\n}\n")

    def test_commenting_out_unchanged_code_is_gated(self) -> None:
        self.write("func f() {\n    // start\n    run()\n    // end\n}\n")
        self.commit()
        self.assertGated("func f() {\n    /* start\n    run()\n    end */\n}\n")

    def test_multiline_string_reindent_is_gated(self) -> None:
        self.write('let s = """\n    hello\n    """\n')
        self.commit()
        self.assertGated('let s = """\n      hello\n    """\n')

    def test_multiline_string_comment_markers_are_content(self) -> None:
        self.write('let s = """\n    // not a comment\n    """\n')
        self.commit()
        self.assertGated('let s = """\n    // a changed string\n    """\n')

    def test_quote_inside_interpolation_does_not_open_a_comment(self) -> None:
        self.write('let s = "\\("/*")"\nlet a = 1\n')
        self.commit()
        self.assertGated('let s = "\\("/*")"\nlet a = 2\n')

    def test_raw_string_is_exact(self) -> None:
        self.write('let s = #"a "quoted" // x"#\n')
        self.commit()
        self.assertGated('let s = #"a "quoted"  // x"#\n')

    def test_deleted_code_line_is_gated(self) -> None:
        self.assertGated(BASE.replace("    let result = value * 2\n", ""))

    def test_code_after_block_comment_is_gated(self) -> None:
        self.assertGated(BASE.replace("    return result", "    /* x */ return result * 2"))

    def test_comment_marker_inside_string_is_code(self) -> None:
        self.assertGated(BASE.replace("    return result\n", '    let url = "http://x"\n    return result\n'))

    def test_mixed_file_is_gated(self) -> None:
        self.assertGated(BASE.replace("// multiply", "// multiply it").replace("value * 2", "value * 3"))

    def test_unterminated_block_comment_is_gated(self) -> None:
        self.assertGated(BASE + "/* never closed\n")

    def test_regex_literal_is_doubt_and_gated(self) -> None:
        self.write("let r = /a+/\n")
        self.commit()
        self.assertGated("let r = /a+/ // note\n")

    def test_if_region_comment_edit_is_skipped_and_code_edit_gated(self) -> None:
        base = "#if DEBUG\nlet a = 1 // dbg\n#else\nlet a = 2\n#endif\n"
        self.write(base)
        self.commit()
        self.assertSkipped(base.replace("// dbg", "// debug build"))
        self.assertGated(base.replace("let a = 2", "let a = 3"))

    def test_hash_raw_string_holding_quote_hash_is_exact(self) -> None:
        self.write('let s = ##"a "# // b"##\nlet n = 1\n')
        self.commit()
        self.assertSkipped('let s = ##"a "# // b"## // note\nlet n = 1\n')
        self.assertGated('let s = ##"a "# // c"##\nlet n = 1\n')
        self.assertGated('let s = ##"a "# // b"##\nlet n = 2\n')

    def test_unicode_escape_is_exact(self) -> None:
        self.write('let s = "\\u{41} // x"\n')
        self.commit()
        self.assertGated('let s = "\\u{42} // x"\n')
        self.assertSkipped('let s = "\\u{41} // x" // note\n')

    def test_crlf_endings_are_skipped_and_code_edits_gated(self) -> None:
        crlf = BASE.replace("\n", "\r\n")
        self.write_bytes(crlf)
        self.commit()
        self.assertSkipped(crlf.replace("// multiply", "// multiply it"))
        self.assertGated(crlf.replace("value * 2", "value * 3"))

    def test_lone_cr_ends_a_line_comment(self) -> None:
        self.write_bytes("// a\rlet x = 1\n")
        self.commit()
        self.assertGated("// a\rlet x = 2\n")

    def test_regex_after_keyword_is_gated(self) -> None:
        for keyword in ("return", "case", "try"):
            with self.subTest(keyword):
                self.write(f"func f() {{\n    {keyword} /https?:\\/\\//.firstMatch(in: s) != nil\n}}\n")
                self.commit()
                self.assertGated(f"func f() {{\n    {keyword} /https?:\\/\\//.firstMatch(in: s) == nil\n}}\n")

    def test_regex_builder_line_after_paren_is_gated(self) -> None:
        self.write("let r = Regex {\n    Capture(x)\n    /a+/\n}\n")
        self.commit()
        self.assertGated("let r = Regex {\n    Capture(x)\n    /b+/\n}\n")

    def test_prefix_operator_spacing_is_code(self) -> None:
        self.write("let v = a -b\n")
        self.commit()
        self.assertGated("let v = a - b\n")

    def test_line_join_after_return_is_gated(self) -> None:
        self.write("func f() {\n    return\n    x\n}\n")
        self.commit()
        self.assertGated("func f() {\n    return x\n}\n")

    def test_spaced_division_still_skips_on_comment_edit(self) -> None:
        self.write("let v = a / b\n")
        self.commit()
        self.assertSkipped("let v = a / b // half\n")

    def test_renamed_file_is_gated(self) -> None:
        self.git("mv", NAME, "apple/Sources/Core/Renamed.swift")
        path = self.root / "apple/Sources/Core/Renamed.swift"
        path.write_text(path.read_text().replace("// multiply", "// multiply it"), encoding="utf-8")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            kept = coverage_gate.drop_comment_only(["apple/Sources/Core/Renamed.swift"], self.base, self.root)
        self.assertEqual(kept, ["apple/Sources/Core/Renamed.swift"])
        self.assertNotIn("skipped", out.getvalue())

    def test_new_file_and_no_base_are_gated(self) -> None:
        self.assertEqual(coverage_gate.drop_comment_only([NAME], None, self.root), [NAME])
        new = self.root / "apple/Sources/Core/New.swift"
        new.write_text("// only a comment\n", encoding="utf-8")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            kept = coverage_gate.drop_comment_only(["apple/Sources/Core/New.swift"], self.base, self.root)
        self.assertEqual(kept, ["apple/Sources/Core/New.swift"])

    def test_unchanged_file_is_gated(self) -> None:
        self.assertGated(BASE)


class CodeStreamTests(unittest.TestCase):
    """The scanner strips comments, keeps strings exact and refuses what it cannot judge."""

    def test_comments_vanish_and_whitespace_collapses(self) -> None:
        self.assertEqual(
            coverage_gate.code_stream("a  /* b /* c */ d */ b // e\n\n\n  c"),
            [("code", "a b\nc")],
        )

    def test_strings_are_exact(self) -> None:
        self.assertEqual(
            coverage_gate.code_stream('x = "a  // b"  + #"c"#'),
            [("code", "x = "), ("string", '"a  // b"'), ("code", "  + ".replace("  ", " ")), ("string", '#"c"#')],
        )

    def test_interpolation_with_quotes(self) -> None:
        stream = coverage_gate.code_stream('let s = "\\("a)" + "/*")" // c\nz')
        self.assertEqual(stream[1], ("string", '"\\("a)" + "/*")"'))

    def test_doubt_raises(self) -> None:
        for text in ('"open', "/* open", 'let s = """\nopen', '"\\(1 // c\n)"'):
            with self.assertRaises(coverage_gate.ScanDoubt, msg=text):
                coverage_gate.code_stream(text)

    def test_identical_files_are_not_comment_only(self) -> None:
        self.assertFalse(coverage_gate.is_comment_only("a\n", "a\n"))


if __name__ == "__main__":
    unittest.main()
