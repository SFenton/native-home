"""Synthetic tests for the read-only broad-exception call map."""

from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from textwrap import dedent


SCRIPT = Path(__file__).resolve().parents[1] / "catch_map.py"


class CatchMapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def source(self, text):
        value = dedent(text).lstrip()
        path = self.root / "sample.py"
        path.write_text(value, encoding="utf-8")
        return path

    def run_path(self, path, *arguments):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path), *arguments],
            check=False,
            capture_output=True,
            text=True,
        )

    def run_source(self, text, *arguments):
        path = self.source(text)
        return self.run_path(path, *arguments), path

    def assert_output(self, text, arguments, expected):
        result, path = self.run_source(text, *arguments)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.stdout.splitlines(), [
            line.format(path=path) for line in expected
        ])

    def test_call_in_broad_try_reports_handler(self):
        self.assert_output(
            """
            def owner():
                try:
                    _run()
                except Exception:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:3 _run in def owner: handler 4-5 Exception -> pass"],
        )

    def test_nested_inner_narrow_reports_outer(self):
        self.assert_output(
            """
            def owner():
                try:
                    try:
                        _run()
                    except ValueError:
                        pass
                except Exception:
                    return
            """,
            ("--callee", "_run"),
            ["{path}:4 _run in def owner: handler 7-8 Exception -> return"],
        )

    def test_nested_inner_broad_reports_inner(self):
        self.assert_output(
            """
            def owner():
                try:
                    try:
                        _run()
                    except Exception:
                        raise
                except BaseException:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:4 _run in def owner: handler 5-6 Exception -> raise"],
        )

    def test_bare_except_is_reported_as_bare(self):
        self.assert_output(
            """
            def owner():
                try:
                    _run()
                except:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:3 _run in def owner: handler 4-5 bare -> pass"],
        )

    def test_broad_tuple_reports_its_source_text(self):
        self.assert_output(
            """
            def owner():
                try:
                    _run()
                except (ValueError, Exception):
                    pass
            """,
            ("--callee", "_run"),
            [
                "{path}:3 _run in def owner: handler 4-5 "
                "(ValueError, Exception) -> pass"
            ],
        )

    def test_narrow_handlers_leave_call_unguarded(self):
        for narrow in ("ValueError", "(KeyError, TypeError)"):
            with self.subTest(narrow=narrow):
                self.assert_output(
                    f"""
                    def owner():
                        try:
                            _run()
                        except {narrow}:
                            pass
                    """,
                    ("--callee", "_run"),
                    ["{path}:3 _run in def owner: unguarded"],
                )

    def test_call_in_handler_body_is_unguarded(self):
        self.assert_output(
            """
            def owner():
                try:
                    work()
                except Exception:
                    _run()
            """,
            ("--callee", "_run"),
            ["{path}:5 _run in def owner: unguarded"],
        )

    def test_call_in_handler_body_reports_outer_handler(self):
        self.assert_output(
            """
            def owner():
                try:
                    try:
                        work()
                    except Exception:
                        _run()
                except BaseException:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:6 _run in def owner: handler 7-8 BaseException -> pass"],
        )

    def test_nested_function_has_its_own_scope_and_owner(self):
        self.assert_output(
            """
            class Worker:
                def outer(self):
                    try:
                        def inner():
                            _run()
                    except Exception:
                        pass
            """,
            ("--callee", "_run"),
            ["{path}:5 _run in def inner: unguarded"],
        )

    def test_async_function_has_its_own_scope_and_owner(self):
        self.assert_output(
            """
            def outer():
                try:
                    async def inner():
                        _run()
                except Exception:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:4 _run in def inner: unguarded"],
        )

    def test_lambda_has_its_own_scope_and_owner(self):
        self.assert_output(
            """
            def outer():
                try:
                    worker = lambda: _run()
                except Exception:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:3 _run in def <lambda>: unguarded"],
        )

    def test_function_decorator_call_uses_outer_scope(self):
        self.assert_output(
            """
            def outer():
                try:
                    @_run()
                    def inner():
                        pass
                except Exception:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:3 _run in def outer: handler 6-7 Exception -> pass"],
        )

    def test_function_default_call_uses_outer_scope(self):
        self.assert_output(
            """
            def outer():
                try:
                    def inner(value=_run()):
                        pass
                except Exception:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:3 _run in def outer: handler 5-6 Exception -> pass"],
        )

    def test_class_base_call_uses_outer_scope(self):
        self.assert_output(
            """
            def outer():
                try:
                    class Inner(_run()):
                        pass
                except Exception:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:3 _run in def outer: handler 5-6 Exception -> pass"],
        )

    def test_with_inside_try_reports_outer_handler(self):
        self.assert_output(
            """
            def owner():
                try:
                    with context():
                        _run()
                except Exception:
                    pass
            """,
            ("--callee", "_run"),
            ["{path}:4 _run in def owner: handler 5-6 Exception -> pass"],
        )

    def test_try_finally_only_is_unguarded(self):
        self.assert_output(
            """
            def owner():
                try:
                    _run()
                finally:
                    cleanup()
            """,
            ("--callee", "_run"),
            ["{path}:3 _run in def owner: unguarded"],
        )

    def test_else_and_finally_calls_are_not_guarded_by_try(self):
        self.assert_output(
            """
            def owner():
                try:
                    work()
                except Exception:
                    pass
                else:
                    _run()
                finally:
                    _run()
            """,
            ("--callee", "_run"),
            [
                "{path}:7 _run in def owner: unguarded",
                "{path}:9 _run in def owner: unguarded",
            ],
        )

    def test_each_handler_outcome_word(self):
        cases = {
            "pass": ("pass", 4),
            "return": ("return 1", 4),
            "log": ("log('retry')", 4),
            "raise": ("raise RuntimeError()", 4),
            "other": ("value = 1", 4),
        }
        for outcome, (body, handler_line) in cases.items():
            with self.subTest(outcome=outcome):
                self.assert_output(
                    f"""
                    def owner():
                        try:
                            _run()
                        except Exception:
                            {body}
                    """,
                    ("--callee", "_run"),
                    [
                        f"{{path}}:3 _run in def owner: handler "
                        f"{handler_line}-5 Exception -> {outcome}"
                    ],
                )
        self.assert_output(
            """
            def owner():
                for item in items:
                    try:
                        _run()
                    except Exception:
                        continue
            """,
            ("--callee", "_run"),
            ["{path}:4 _run in def owner: handler 5-6 Exception -> continue"],
        )

    def test_bare_and_attribute_callee_matching(self):
        self.assert_output(
            """
            class Worker:
                def owner(self):
                    self._run()
                    _run()
                    self._run_other()
            """,
            ("--callee", "_run"),
            [
                "{path}:3 _run in def Worker.owner: unguarded",
                "{path}:4 _run in def Worker.owner: unguarded",
            ],
        )

    def test_two_callee_flags_form_a_line_order_union(self):
        self.assert_output(
            """
            def owner():
                second()
                first()
                model.second()
                first_extra()
            """,
            ("--callee", "first", "--callee", "second"),
            [
                "{path}:2 second in def owner: unguarded",
                "{path}:3 first in def owner: unguarded",
                "{path}:4 second in def owner: unguarded",
            ],
        )

    def test_handlers_lists_every_broad_handler_with_try_range(self):
        self.assert_output(
            """
            def owner():
                try:
                    work()
                except ValueError:
                    pass
                except (ValueError, Exception):
                    log('retry')
                try:
                    other()
                finally:
                    cleanup()
                try:
                    last()
                except BaseException:
                    return
            """,
            ("--handlers",),
            [
                "{path}:6-7 handler (ValueError, Exception) -> log "
                "try 2-7 in def owner",
                "{path}:14-15 handler BaseException -> return "
                "try 12-15 in def owner",
            ],
        )

    def test_five_runner_shapes_list_five_guarded_calls(self):
        self.assert_output(
            """
            def owner():
                try:
                    _run("one")
                except Exception:
                    pass
                try:
                    _run("two")
                    after()
                except Exception:
                    pass
                try:
                    for item in items:
                        _run("three")
                except Exception:
                    pass
                try:
                    with context():
                        _run("four")
                except Exception:
                    pass
                for item in items:
                    try:
                        if ready:
                            _run("five")
                    except Exception:
                        log("retry")
                        continue
            """,
            ("--callee", "_run"),
            [
                "{path}:3 _run in def owner: handler 4-5 Exception -> pass",
                "{path}:7 _run in def owner: handler 9-10 Exception -> pass",
                "{path}:13 _run in def owner: handler 14-15 Exception -> pass",
                "{path}:18 _run in def owner: handler 19-20 Exception -> pass",
                "{path}:24 _run in def owner: handler 25-27 Exception -> continue",
            ],
        )

    def test_unreadable_and_invalid_files_report_once_and_exit_zero(self):
        missing = self.root / "missing.py"
        bad = self.source("def broken(:\n")
        for path in (missing, bad):
            with self.subTest(path=path):
                result = self.run_path(path, "--callee", "_run")
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                lines = result.stderr.splitlines()
                self.assertEqual(len(lines), 1, result.stderr)
                self.assertTrue(lines[0].startswith(f"{path}: "), result.stderr)

    def test_run_does_not_change_temporary_directory_or_source_bytes(self):
        path = self.source(
            """
            try:
                _run()
            except Exception:
                pass
            """
        )
        before_names = sorted(item.name for item in self.root.iterdir())
        before_bytes = path.read_bytes()
        result = self.run_path(path, "--callee", "_run", "--handlers")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(item.name for item in self.root.iterdir()), before_names)
        self.assertEqual(path.read_bytes(), before_bytes)


if __name__ == "__main__":
    unittest.main()
