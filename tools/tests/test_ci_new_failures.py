"""Tests for tools/ci_new_failures.py with a stubbed test runner."""
import io
import subprocess
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_new_failures as ci  # noqa: E402

HEAD = subprocess.run(["git", "-C", str(ci.ROOT), "rev-parse", "HEAD"], stdout=subprocess.PIPE, text=True).stdout.strip()


def fail(*names):
    return 1, "".join(f"FAIL: {n} (m.C)\n" for n in names) + "FAILED\n"


class Stub:
    """Runner stub: the first call is the checkout, the second the base worktree."""

    def __init__(self, current, base):
        self.results = [current, base]
        self.trees = []

    def __call__(self, tree):
        self.trees.append(tree)
        return self.results[len(self.trees) - 1]


def run(stub, base=HEAD):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = ci.main(["--base", base], runner=stub)
    return code, out.getvalue()


class NewFailuresTests(unittest.TestCase):
    def test_all_pass(self):
        stub = Stub((0, "OK\n"), None)
        self.assertEqual(run(stub)[0], 0)
        self.assertEqual(len(stub.trees), 1)

    def test_only_base_failures(self):
        code, out = run(Stub(fail("a", "b"), fail("a", "b", "c")))
        self.assertEqual(code, 0)
        self.assertIn("existing (ignored, owner 2026-11-04):", out)
        self.assertIn("fixed:\n  c (m.C)", out)

    def test_one_new_failure(self):
        code, out = run(Stub(fail("a", "n"), fail("a")))
        self.assertEqual(code, 1)
        self.assertIn("new:\n  n (m.C)", out)

    def test_base_run_without_results(self):
        self.assertEqual(run(Stub(fail("a"), (2, "boom\n")))[0], 1)

    def test_part_runs_one_slice_on_both_sides(self):
        calls = []
        real = ci.run_script
        ci.run_script = lambda tree, part=None: calls.append(part) or ((1, "FAIL: a (m.C)\nFAILED\n") if len(calls) == 1 else (1, "FAIL: a (m.C)\nFAILED\n"))
        try:
            with redirect_stdout(io.StringIO()):
                code = ci.main(["--base", HEAD, "--part", "core"])
        finally:
            ci.run_script = real
        self.assertEqual((code, calls), (0, ["core", "core"]))

    def test_base_missing(self):
        self.assertEqual(run(Stub(fail("a"), fail("a")), base="0" * 40)[0], 1)

    def test_current_failure_without_ids(self):
        self.assertEqual(run(Stub((1, "crash\n"), fail("a")))[0], 1)

    def test_worktree_cleaned_up(self):
        stub = Stub(fail("a"), fail("a"))
        run(stub)
        base_tree = stub.trees[1]
        self.assertFalse(base_tree.exists())
        listing = subprocess.run(["git", "-C", str(ci.ROOT), "worktree", "list"], stdout=subprocess.PIPE, text=True).stdout
        self.assertNotIn(str(base_tree), listing)

    def test_worktree_cleaned_up_when_runner_raises(self):
        trees = []

        def boom(tree):
            trees.append(tree)
            if len(trees) == 1:
                return fail("a")
            raise RuntimeError("x")

        with self.assertRaises(RuntimeError):
            run(boom)
        self.assertFalse(trees[1].exists())


if __name__ == "__main__":
    unittest.main()
