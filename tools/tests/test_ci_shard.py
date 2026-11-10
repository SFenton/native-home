"""tools/ci_shard.py: the pr-checks core tool tests run in 4 shards, every module in exactly one, balanced, deterministic."""

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import ci_shard as shard  # noqa: E402

SHARDS = 4  # the pr-checks matrix; test_hosted_workflows pins the workflow side


class ExactlyOnceTests(unittest.TestCase):
    """Today's real core set: nothing dropped, nothing run twice, whatever the shard count."""

    def test_every_core_module_runs_in_exactly_one_shard(self):
        modules = shard.discover_modules()
        self.assertGreater(len(modules), 50)
        for count in (1, 2, 3, SHARDS, 7, 16):
            parts = [shard.shard_modules(index, count) for index in range(count)]
            flat = [name for part in parts for name in part]
            self.assertEqual(sorted(flat), modules, "count=%d" % count)
            self.assertEqual(len(flat), len(set(flat)), "count=%d: a module is in two shards" % count)

    def test_the_shards_hold_the_same_tests_discover_finds(self):
        """The unittest view of the same claim: loading each shard's modules by name finds as many tests as discovery."""
        tests_dir = str(shard.TESTS_DIR)
        added = tests_dir not in sys.path
        if added:
            sys.path.insert(0, tests_dir)
        try:
            loader = unittest.TestLoader()
            discovered = loader.discover(tests_dir).countTestCases()
            sharded = sum(loader.loadTestsFromNames(shard.shard_modules(index, SHARDS)).countTestCases() for index in range(SHARDS))
            self.assertEqual(sharded, discovered)
        finally:
            if added:
                sys.path.remove(tests_dir)

    def test_this_module_is_in_the_core_set(self):
        self.assertIn(Path(__file__).stem, shard.discover_modules())

    def test_the_split_is_deterministic(self):
        first = [shard.shard_modules(index, SHARDS) for index in range(SHARDS)]
        second = [shard.shard_modules(index, SHARDS) for index in range(SHARDS)]
        self.assertEqual(first, second)

    def test_the_recorded_weights_keep_the_shards_balanced(self):
        weights = shard.load_weights()
        self.assertTrue(weights, "tools/ci_shard_weights.json is empty or missing")
        parts = shard.assign(shard.discover_modules(), weights, SHARDS)
        fallback = sorted(weights.values())[len(weights) // 2]
        totals = [sum(weights.get(name, fallback) for name in part) for part in parts]
        self.assertLess(max(totals) / min(totals), 1.25, totals)


class AssignTests(unittest.TestCase):
    def test_the_heaviest_modules_spread_and_ties_break_by_index_then_name(self):
        weights = {"a": 10, "b": 10, "c": 10, "d": 10, "e": 1}
        self.assertEqual(shard.assign(list("abcde"), weights, 2), [["a", "c", "e"], ["b", "d"]])

    def test_a_module_without_a_weight_still_lands_in_a_shard(self):
        parts = shard.assign(["old", "new"], {"old": 5.0}, 2)
        self.assertEqual(sorted(name for part in parts for name in part), ["new", "old"])

    def test_no_weights_at_all_still_splits(self):
        parts = shard.assign(list("abcdef"), {}, 3)
        self.assertEqual([len(part) for part in parts], [2, 2, 2])

    def test_more_shards_than_modules_leaves_some_empty_and_loses_none(self):
        parts = shard.assign(["a", "b"], {}, 5)
        self.assertEqual(sorted(name for part in parts for name in part), ["a", "b"])

    def test_a_duplicate_name_runs_once(self):
        self.assertEqual(sum(len(part) for part in shard.assign(["a", "a", "b"], {}, 2)), 2)

    def test_a_shard_count_below_one_is_refused(self):
        with self.assertRaises(ValueError):
            shard.assign(["a"], {}, 0)

    def test_a_shard_index_outside_the_count_is_refused(self):
        for index in (-1, SHARDS):
            with self.assertRaises(ValueError):
                shard.shard_modules(index, SHARDS)


class FilesTests(unittest.TestCase):
    def test_discovery_matches_what_unittest_imports(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ("test_b.py", "test_a.py", "helper.py", "testdata.txt"):
                (Path(tmp) / name).write_text("")
            (Path(tmp) / "test_dir.py").mkdir()  # a directory with a test name is not a module
            self.assertEqual(shard.discover_modules(Path(tmp)), ["test_a", "test_b"])

    def test_the_weights_file_loads_and_skips_notes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "w.json"
            path.write_text(json.dumps({"_note": "x", "test_a": 3, "test_b": "4.5"}))
            self.assertEqual(shard.load_weights(path), {"test_a": 3.0, "test_b": 4.5})
            self.assertEqual(shard.load_weights(Path(tmp) / "missing.json"), {})

    def test_every_recorded_weight_names_a_real_module(self):
        """A renamed or deleted test file leaves a dead weight: drop it so the file stays the truth."""
        modules = set(shard.discover_modules())
        self.assertEqual(sorted(name for name in shard.load_weights() if name not in modules), [])


class CommandLineTests(unittest.TestCase):
    def test_main_prints_one_module_per_line(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(shard.main(["--shard", "0", "--of", str(SHARDS)]), 0)
        self.assertEqual(out.getvalue().split(), shard.shard_modules(0, SHARDS))

    def test_main_rejects_a_bad_shard(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(shard.main(["--shard", "4", "--of", "4"]), 2)

    def test_the_script_runs_as_a_program(self):
        out = subprocess.run([sys.executable, str(TOOLS / "ci_shard.py"), "--shard", "1", "--of", str(SHARDS)],
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.split(), shard.shard_modules(1, SHARDS))


class RunnerScriptTests(unittest.TestCase):
    """tools/run_tool_tests.sh core honours FENTON_TOOL_SHARD."""

    SCRIPT = TOOLS / "run_tool_tests.sh"

    def test_the_script_names_the_shard_variable_and_the_helper(self):
        text = self.SCRIPT.read_text(encoding="utf-8")
        self.assertIn("FENTON_TOOL_SHARD", text)
        self.assertIn("tools/ci_shard.py --shard", text)
        self.assertIn("discover -s tools/tests", text)  # unset: the whole set, as before

    def test_a_malformed_shard_value_fails_instead_of_running_everything(self):
        out = subprocess.run(["bash", str(self.SCRIPT), "core"], capture_output=True, text=True, timeout=60,
                             env={"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "FENTON_TOOL_SHARD": "x"})
        self.assertEqual(out.returncode, 1)
        self.assertIn("must be I/N", out.stderr)


if __name__ == "__main__":
    unittest.main()
