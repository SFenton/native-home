"""``tools/proof_check.py`` reads synthetic proof manifests without executing them."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
SCRIPT = TOOLS / "proof_check.py"
HEADERS = (
    "control id",
    "test",
    "one-rule mutant",
    "sites",
    "earlier checks",
    "assertion that must fail",
    "status",
)
ISOLATED = {
    **os.environ,
    "HOME": "",
    "GIT_AUTHOR_NAME": "Synthetic",
    "GIT_AUTHOR_EMAIL": "synthetic@example.invalid",
    "GIT_COMMITTER_NAME": "Synthetic",
    "GIT_COMMITTER_EMAIL": "synthetic@example.invalid",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_SYSTEM": "/dev/null",
}


def git(root, *args):
    return subprocess.run(
        ["git", *args],
        cwd=root,
        env=ISOLATED,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def code_span(text):
    return "``" + text + "``" if "`" in text else "`" + text + "`"


class ProofCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        ISOLATED["HOME"] = str(self.root)
        git(self.repo, "init", "-q", "-b", "main")
        self.write(
            "src/value.py",
            'FLAG = "ok"\n'
            'OTHER = "same"\n'
            'REPEAT = "same"\n'
            'LEFT = "a|b"\n'
            'TICK = "`tick`"\n'
            'LINES = (\n'
            '    "left"\n'
            '    "right"\n'
            ')\n'
            "\n"
            "def choose():\n"
            '    return "ok"\n',
        )
        self.write(
            "notes/raw.txt",
            "plain text\nbad: )\n",
        )
        self.write(
            "tests/test_value.py",
            "import unittest\n"
            "\n"
            "class ValueTests(unittest.TestCase):\n"
            "    def test_ok(self):\n"
            '        self.assertEqual("ok", "ok")\n'
            "\n"
            "    def test_multiline(self):\n"
            "        self.assertEqual(\n"
            '            "ok",\n'
            '            "ok",\n'
            "        )\n"
            "\n"
            "    def test_context(self):\n"
            "        with self.assertRaises(ValueError):\n"
            '            raise ValueError("expected")\n'
            "\n"
            "    def test_bare(self):\n"
            "        assert True\n"
            "\n"
            "    def test_plain(self):\n"
            "        value = 1\n"
            "        return value\n"
            "\n"
            "def test_function():\n"
            "    assert True\n",
        )
        self.write(
            "tests/test_broken.py",
            "import pathlib\n\nPath = pathlib.Path(__file__).parents[1] / 'import-marker'\nPath.write_text('ran')\n",
        )
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-q", "-m", "fixture")
        git(self.repo, "branch", "fixture-head")
        self.head = git(self.repo, "rev-parse", "HEAD")

    def write(self, relative, text):
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def note_path(self, name="manifest.md"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def line(self, relative, needle, occurrence=1):
        lines = (self.repo / relative).read_text(encoding="utf-8").splitlines()
        found = [index for index, line in enumerate(lines, 1) if needle in line]
        return found[occurrence - 1]

    def mutant(self, find='FLAG = "ok"', replace='FLAG = "changed"', file="src/value.py"):
        return json.dumps({"file": file, "find": find, "replace": replace}, ensure_ascii=True)

    def row(
        self,
        control="green",
        test="tests/test_value.py::ValueTests.test_ok",
        mutant=None,
        assertion=None,
    ):
        if mutant is None:
            mutant = self.mutant()
        if assertion is None:
            assertion = "tests/test_value.py:" + str(
                self.line("tests/test_value.py", "self.assertEqual")
            )
        return [control, test, mutant, "one", "fixture committed", assertion, "not executed"]

    def table(self, rows, headers=HEADERS):
        result = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
        for row in rows:
            cells = [
                code_span(row[0]),
                code_span(row[1]),
                code_span(row[2].replace("|", r"\|")),
                row[3],
                row[4],
                code_span(row[5]),
                row[6],
            ]
            result.append("| " + " | ".join(cells) + " |")
        return "\n".join(result)

    def write_note(self, text=None, rows=None, heads=None, name="manifest.md"):
        if text is None:
            rows = rows if rows is not None else [self.row()]
            text = (self.table(rows) + "\n")
        if heads is not None:
            text += "".join("\nmanifest-head: " + code_span(head) + "\n" for head in heads)
        elif rows is not None:
            text += "\nmanifest-head: " + code_span(self.head) + "\n"
        path = self.note_path(name)
        path.write_text(text, encoding="utf-8")
        return path

    def run_tool(self, note, head=None, repo=None):
        command = [
            sys.executable,
            str(SCRIPT),
            str(note),
            "--head",
            head or self.head,
            "--repo",
            str(self.repo if repo is None else repo),
        ]
        env = dict(ISOLATED)
        env["HOME"] = str(self.root)
        return subprocess.run(command, cwd=self.root, env=env, capture_output=True, text=True)

    def assert_run(self, result, code, *lines):
        self.assertEqual(result.returncode, code, result.stderr or result.stdout)
        self.assertEqual(result.stdout.splitlines(), list(lines))
        self.assertEqual(result.stderr, "")

    def test_green_row_accepts_a_branch_name_for_the_head(self):
        note = self.write_note()
        result = self.run_tool(note, "fixture-head")
        self.assert_run(result, 0, "green: ok", "proof_check: 1 rows, 0 not ok")

    def test_absent_ambiguous_and_missing_file_report_distinct_rows(self):
        rows = [
            self.row("missing", mutant=self.mutant('MISSING: true', "MISSING: false")),
            self.row("twice", mutant=self.mutant('OTHER = "same"', 'OTHER = "changed"')),
            self.row("gone", mutant=self.mutant(file="src/gone.py")),
        ]
        self.write("src/value.py", (self.repo / "src/value.py").read_text() + 'OTHER = "same"\n')
        git(self.repo, "add", "src/value.py")
        git(self.repo, "commit", "-q", "-m", "duplicate")
        self.head = git(self.repo, "rev-parse", "HEAD")
        # The duplicate fixture reproduces the R233-6 shape: the exact find is present twice.
        note = self.write_note(rows=rows)
        result = self.run_tool(note)
        self.assert_run(
            result,
            1,
            "missing: absent",
            "twice: ambiguous 2",
            "gone: absent (no such file at head)",
            "proof_check: 3 rows, 3 not ok",
        )

    def test_identity_and_unparseable_replacements_are_named(self):
        rows = [
            self.row("identity", mutant=self.mutant('FLAG = "ok"', 'FLAG = "ok"')),
            self.row("half-call", mutant=self.mutant('return "ok"', "return choose(")),
            self.row("empty-body", mutant=self.mutant("def choose():\n    return \"ok\"", "def choose():")),
        ]
        note = self.write_note(rows=rows)
        result = self.run_tool(note)
        self.assert_run(
            result,
            1,
            "identity: identity",
            "half-call: unparseable",
            "empty-body: unparseable",
            "proof_check: 3 rows, 3 not ok",
        )

    def test_non_python_file_has_no_parse_check(self):
        row = self.row(
            "text",
            test="tests/test_value.py::test_function",
            mutant=self.mutant("plain text", "bad: )", "notes/raw.txt"),
        )
        note = self.write_note(rows=[row])
        self.assert_run(
            self.run_tool(note),
            0,
            "text: ok",
            "proof_check: 1 rows, 0 not ok",
        )

    def test_assertion_spans_cover_calls_bare_asserts_and_with_headers(self):
        file = "tests/test_value.py"
        assert_line = self.line(file, "self.assertEqual", 1)
        multiline_line = self.line(file, '"ok",', 1)
        with_line = self.line(file, "with self.assertRaises")
        bare_line = self.line(file, "assert True", 1)
        rows = [
            self.row("call", assertion=file + ":" + str(assert_line)),
            self.row("multiline", assertion=file + ":" + str(multiline_line)),
            self.row("with", assertion=file + ":" + str(with_line)),
            self.row("bare", assertion=file + ":" + str(bare_line)),
            self.row("body", assertion=file + ":" + str(self.line(file, "raise ValueError"))),
            self.row("plain", assertion=file + ":" + str(self.line(file, "value = 1"))),
        ]
        note = self.write_note(rows=rows)
        result = self.run_tool(note)
        self.assert_run(
            result,
            1,
            "call: ok",
            "multiline: ok",
            "with: ok",
            "bare: ok",
            "body: not_assertion",
            "plain: not_assertion",
            "proof_check: 6 rows, 2 not ok",
        )

    def test_leaf_missing_reports_wrong_class_wrong_name_and_missing_file(self):
        rows = [
            self.row("class", test="tests/test_value.py::OtherTests.test_ok"),
            self.row("name", test="tests/test_value.py::ValueTests.test_unknown"),
            self.row("file", test="tests/missing.py::test_ok"),
        ]
        note = self.write_note(rows=rows)
        result = self.run_tool(note)
        self.assert_run(
            result,
            1,
            "class: leaf_missing tests/test_value.py::OtherTests.test_ok",
            "name: leaf_missing tests/test_value.py::ValueTests.test_unknown",
            "file: leaf_missing tests/missing.py::test_ok",
            "proof_check: 3 rows, 3 not ok",
        )

    def test_missing_duplicate_and_different_manifest_heads_mismatch(self):
        note_body = self.table([self.row()])
        for index, heads in enumerate(([], [self.head, self.head], ["0" * 40])):
            note = self.write_note(note_body, heads=heads, name=f"head-{index}.md")
            result = self.run_tool(note)
            self.assert_run(
                result,
                1,
                "green: head_mismatch",
                "proof_check: 1 rows, 1 not ok",
            )

    def test_pinned_short_head_matches_only_after_resolving_commit(self):
        note = self.write_note()
        result = self.run_tool(note, self.head[:12])
        self.assert_run(result, 0, "green: ok", "proof_check: 1 rows, 0 not ok")

    def test_compound_objects_arrays_and_multiple_code_spans(self):
        first = self.mutant()
        rows = [
            self.row("objects", mutant=first + " " + self.mutant(replace="FLAG = 2")),
            self.row("array", mutant="[" + first + "]"),
            self.row("spans", mutant=first),
        ]
        text = self.table(rows)
        text = text.replace(code_span(first), code_span(first) + " " + code_span(first))
        note = self.write_note(text, heads=[self.head], name="compound.md")
        result = self.run_tool(note)
        self.assert_run(
            result,
            1,
            "objects: compound",
            "array: compound",
            "spans: compound",
            "proof_check: 3 rows, 3 not ok",
        )

    def test_malformed_cells_are_reported_by_cell_name(self):
        valid = json.loads(self.mutant())
        variants = [
            ("json", "not json", "malformed one-rule mutant"),
            ("key", json.dumps({k: v for k, v in valid.items() if k != "find"}), "malformed one-rule mutant"),
            ("extra", json.dumps({**valid, "extra": "x"}), "malformed one-rule mutant"),
            ("type", json.dumps({**valid, "replace": 1}), "malformed one-rule mutant"),
        ]
        rows = [self.row(name, mutant=body) for name, body, _ in variants]
        bad_test = self.row("test")
        bad_test[1] = "not an id"
        bad_assertion = self.row("assertion")
        bad_assertion[5] = "not-a-location"
        rows.extend([bad_test, bad_assertion])
        note = self.write_note(rows=rows)
        result = self.run_tool(note)
        expected = [name + ": " + status for name, _, status in variants]
        expected.extend(["test: malformed test", "assertion: malformed assertion"])
        expected.append(f"proof_check: 6 rows, 6 not ok")
        self.assert_run(result, 1, *expected)

    def test_multiple_faults_keep_the_required_order(self):
        self.write(
            "src/value.py",
            (self.repo / "src/value.py").read_text() + '\nOTHER = "same"\n',
        )
        git(self.repo, "add", "src/value.py")
        git(self.repo, "commit", "-q", "-m", "multiple faults")
        self.head = git(self.repo, "rev-parse", "HEAD")
        row = self.row(
            "many",
            test="tests/test_value.py::Missing.test_ok",
            mutant=self.mutant('OTHER = "same"', 'OTHER = "same" +'),
            assertion="tests/test_value.py:" + str(self.line("tests/test_value.py", "value = 1")),
        )
        note = self.write_note(text=self.table([row]), heads=["0" * 40])
        result = self.run_tool(note)
        self.assert_run(
            result,
            1,
            "many: ambiguous 2; unparseable; not_assertion; leaf_missing tests/test_value.py::Missing.test_ok; head_mismatch",
            "proof_check: 1 rows, 1 not ok",
        )

    def test_unsafe_paths_are_malformed_and_are_not_sent_to_git(self):
        bad_paths = ["/absolute.py", "pkg/../value.py", "-option.py"]
        rows = [
            self.row(f"mutant-{index}", mutant=self.mutant(file=path))
            for index, path in enumerate(bad_paths)
        ]
        for index, path in enumerate(bad_paths):
            row = self.row(f"test-{index}")
            row[1] = path + "::test_function"
            rows.append(row)
            row = self.row(f"assertion-{index}")
            row[5] = path + ":1"
            rows.append(row)
        sys.path.insert(0, str(TOOLS))
        try:
            import proof_check
        finally:
            sys.path.pop(0)
        note = self.write_note(rows=rows)
        real_show = proof_check.read_blob
        seen = []

        def checked_show(repo, head, path):
            seen.append(path)
            self.assertNotIn(path, bad_paths)
            return real_show(repo, head, path)

        with mock.patch.object(proof_check, "read_blob", side_effect=checked_show):
            code, output = proof_check.check(note, self.repo, self.head)
        self.assertEqual(code, 1)
        self.assertEqual(len(output), 10)
        self.assertTrue(all("malformed " in line for line in output[:-1]))
        self.assertTrue(all("src/value.py" == path or path.startswith("tests/") for path in seen))

    def test_no_manifest_and_manifest_without_rows_exit_one(self):
        for text in (
            "No table here.\n",
            "| " + " | ".join(HEADERS) + " |\n| " + " | ".join("---" for _ in HEADERS) + " |\n",
        ):
            note = self.write_note(text=text)
            self.assert_run(
                self.run_tool(note),
                1,
                "proof_check: no manifest",
            )

    def test_two_manifest_tables_are_checked_in_order_and_headers_reorder(self):
        first = self.write_note(rows=[self.row("first")], name="first.md")
        second = self.table([self.row("second")])
        columns = ["status", "assertion that must fail", "earlier checks", "sites", "one-rule mutant", "test", "control id"]
        old = self.row("third")
        reordered = [
            old[6],
            old[5],
            old[4],
            old[3],
            code_span(old[2].replace("|", r"\|")),
            old[1],
            code_span(old[0]),
        ]
        third = "| " + " | ".join(columns) + " |\n| " + " | ".join("---" for _ in columns) + " |\n| "
        third += " | ".join(
            [
                reordered[0],
                code_span(reordered[1]),
                reordered[2],
                reordered[3],
                reordered[4],
                code_span(reordered[5]),
                reordered[6],
            ]
        ) + " |"
        text = first.read_text() + "\n" + second + "\n" + third
        note = self.write_note(text=text, name="two.md")
        result = self.run_tool(note)
        self.assert_run(
            result,
            0,
            "first: ok",
            "second: ok",
            "third: ok",
            "proof_check: 3 rows, 0 not ok",
        )

    def test_escaped_pipe_backtick_and_newline_are_read_verbatim(self):
        rows = [
            self.row("pipe", mutant=self.mutant('LEFT = "a|b"', 'LEFT = "c|d"')),
            self.row("tick", mutant=self.mutant('TICK = "`tick`"', 'TICK = "plain"')),
            self.row("lines", mutant=self.mutant('    "left"\n    "right"', '    "changed"')),
        ]
        note = self.write_note(rows=rows)
        self.assert_run(
            self.run_tool(note),
            0,
            "pipe: ok",
            "tick: ok",
            "lines: ok",
            "proof_check: 3 rows, 0 not ok",
        )

    def test_reader_never_imports_fixture_code_or_changes_git_state(self):
        note = self.write_note(
            rows=[
                self.row(
                    "read-only",
                    test="tests/test_broken.py::test_function",
                    mutant=self.mutant(file="tests/test_broken.py", find="Path.write_text('ran')", replace="pass"),
                    assertion="tests/test_value.py:" + str(self.line("tests/test_value.py", "assert True", 2)),
                )
            ]
        )
        dirty_before = git(self.repo, "status", "--porcelain=v1")
        tree_before = git(self.repo, "write-tree")
        result = self.run_tool(note)
        self.assertEqual(git(self.repo, "status", "--porcelain=v1"), dirty_before)
        self.assertEqual(git(self.repo, "write-tree"), tree_before)
        self.assertFalse((self.repo / "import-marker").exists())
        self.assert_run(
            result,
            1,
            "read-only: leaf_missing tests/test_broken.py::test_function",
            "proof_check: 1 rows, 1 not ok",
        )

    def test_usage_environment_errors_are_single_stderr_lines(self):
        missing = self.note_path("missing.md")
        result = self.run_tool(missing)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertEqual(len(result.stderr.splitlines()), 1)
        non_repo = self.root / "non-repo"
        non_repo.mkdir()
        result = self.run_tool(self.write_note(), repo=non_repo)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(len(result.stderr.splitlines()), 1)
        result = self.run_tool(self.write_note(), "not-a-commit")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(len(result.stderr.splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
