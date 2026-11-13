"""The shared test-products cache (``tools/products_cache.py``): key, lock, validity and pruning. Fixtures only, no builds."""

import os
import plistlib
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from io import StringIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import products_cache as pc  # noqa: E402

XCODE = "Xcode 99\nBuild version 1\n"


def git(root, *args):
    subprocess.run(["git", "-C", str(root), "-c", "user.email=t@t", "-c", "user.name=t", *args], check=True, capture_output=True)


def make_repo(root):
    root = Path(root)
    git(root, "init", "-q")
    (root / "apple").mkdir()
    (root / "apple" / "A.swift").write_text("let a = 1\n")
    (root / "apple" / ".gitignore").write_text("")
    (root / "README.md").write_text("docs\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "one")
    return root


def bundle(path, files=("x",)):
    path = Path(path)
    (path / "Binaries" / "0").mkdir(parents=True, exist_ok=True)
    for name in files:
        (path / "Binaries" / "0" / name).write_text("bin")
    (path / "Tests").mkdir(exist_ok=True)
    with open(path / "Info.plist", "wb") as handle:
        plistlib.dump({"Version": 1}, handle)
    return path


def writer(content="bin", sleep=0.0, status=0, marker=None):
    """A build command that makes a valid bundle at the partial path (a python one-liner)."""
    code = ("import sys,time,pathlib,plistlib\\n"
            "p=pathlib.Path(sys.argv[1]);time.sleep(%s)\\n"
            "(p/'Binaries'/'0').mkdir(parents=True);(p/'Tests').mkdir();(p/'Binaries'/'0'/'x').write_text('%s')\\n"
            "plistlib.dump({'v':1},open(p/'Info.plist','wb'))\n"
            "%ssys.exit(%d)" % (sleep, content, "open(%r,'a').write('x')\n" % str(marker) if marker else "", status))
    return [sys.executable, "-c", code.replace("\\n", "\n"), "@PARTIAL@"]


class KeyTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = make_repo(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def key(self, *settings, root=None):
        return pc.products_key(list(settings), root or self.root, xcode=XCODE)

    def test_stable_and_independent_of_the_environment(self):
        before = self.key()
        os.environ["TEST_RUNNER_FENTON_APPEARANCE"] = "light"
        try:
            self.assertEqual(before, self.key())
        finally:
            del os.environ["TEST_RUNNER_FENTON_APPEARANCE"]

    def test_files_outside_apple_do_not_change_it(self):
        before = self.key()
        (self.root / "README.md").write_text("changed\n")
        git(self.root, "commit", "-qam", "docs")
        (self.root / "tools.sh").write_text("x")
        self.assertEqual(before, self.key())

    def test_a_dirty_file_changes_it_and_committing_it_does_not(self):
        before = self.key()
        (self.root / "apple" / "A.swift").write_text("let a = 2\n")
        dirty = self.key()
        self.assertNotEqual(before, dirty)
        git(self.root, "add", ".")
        self.assertEqual(dirty, self.key())  # staged
        git(self.root, "commit", "-qm", "two")
        self.assertEqual(dirty, self.key())  # committed

    def test_untracked_new_file_and_deletion_count(self):
        before = self.key()
        (self.root / "apple" / "B.swift").write_text("new")
        added = self.key()
        self.assertNotEqual(before, added)
        (self.root / "apple" / "B.swift").unlink()
        self.assertEqual(before, self.key())
        (self.root / "apple" / "A.swift").unlink()
        self.assertNotEqual(before, self.key())

    def test_a_second_clone_of_the_same_tree_agrees(self):
        with tempfile.TemporaryDirectory() as other:
            subprocess.run(["git", "clone", "-q", str(self.root), other + "/c"], check=True, capture_output=True)
            self.assertEqual(self.key(), self.key(root=Path(other) / "c"))

    def test_xcode_version_is_part_of_it(self):
        self.assertNotEqual(self.key(), pc.products_key([], self.root, xcode="Xcode 100\n"))


class EnsureTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        self.key = "0123456789abcdef"
        self.out = StringIO()

    def tearDown(self):
        self._tmp.cleanup()

    def ensure(self, command, key=None):
        return pc.ensure(key or self.key, command, self.dir, out=self.out)

    def test_builds_once_then_hits(self):
        self.assertEqual(self.ensure(writer()), 0)
        self.assertIn(f"products: built {self.key} in", self.out.getvalue())
        self.out.truncate(0)
        self.assertEqual(self.ensure(["false"]), 0)  # a hit never runs the build
        self.assertIn(f"products: hit {self.key}", self.out.getvalue())
        self.assertIn("saved ~", self.out.getvalue())
        self.assertEqual([p.name for p in self.dir.glob("*.partial.*")], [])

    def test_two_runs_for_one_missing_key_build_it_once(self):
        marker = self.dir / "builds"
        build = writer(sleep=1.0, marker=marker)
        results = []
        outs = [StringIO(), StringIO()]

        def run(out):
            results.append(pc.ensure(self.key, build, self.dir, out=out))

        threads = [threading.Thread(target=run, args=(out,)) for out in outs]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(results, [0, 0])
        self.assertEqual(marker.read_text(), "x")
        text = "".join(out.getvalue() for out in outs)
        self.assertEqual(text.count("products: built"), 1)
        self.assertEqual(text.count("products: hit"), 1)

    def test_a_failed_build_leaves_no_entry_and_a_retry_builds(self):
        self.assertEqual(self.ensure(writer(status=3)), 3)
        self.assertFalse((self.dir / (self.key + pc.SUFFIX)).exists())
        self.assertEqual(list(self.dir.glob("*.partial.*")), [])
        self.assertEqual(self.ensure(writer()), 0)

    def test_a_build_that_made_nothing_usable_is_refused(self):
        self.assertEqual(self.ensure([sys.executable, "-c", "import sys,os;os.makedirs(sys.argv[1])", "@PARTIAL@"]), 1)
        self.assertFalse((self.dir / (self.key + pc.SUFFIX)).exists())

    def test_a_corrupt_entry_is_replaced_not_used(self):
        final = self.dir / (self.key + pc.SUFFIX)
        final.mkdir()
        (final / "Info.plist").write_text("<plist><dict>")  # truncated
        self.assertFalse(pc.valid(final))
        self.assertEqual(self.ensure(writer()), 0)
        self.assertIn("products: built", self.out.getvalue())
        self.assertTrue(pc.valid(final))

    def test_validity_needs_plist_binaries_and_tests(self):
        good = bundle(self.dir / "good")
        self.assertTrue(pc.valid(good))
        for part in ("Info.plist", "Tests", "Binaries"):
            copy = bundle(self.dir / ("no-" + part))
            target = copy / part
            if target.is_dir():
                import shutil
                shutil.rmtree(target)
            else:
                target.unlink()
            self.assertFalse(pc.valid(copy), part)
        empty = bundle(self.dir / "empty")
        import shutil
        shutil.rmtree(empty / "Binaries" / "0")
        self.assertFalse(pc.valid(empty))


class PruneTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        self.now = time.time()

    def tearDown(self):
        self._tmp.cleanup()

    def entry(self, key, age, size=10):
        path = bundle(self.dir / (key + pc.SUFFIX))
        (path / "Binaries" / "0" / "x").write_text("b" * size)
        (self.dir / (key + ".json")).write_text("{}")
        os.utime(path, (self.now - age, self.now - age))
        return path

    def test_old_entries_and_the_stray_leftover_go_and_fresh_ones_stay(self):
        fresh = self.entry("a" * 16, 60)
        old = self.entry("b" * 16, 3 * 24 * 3600)
        stray = self.dir / ("c" * 16 + pc.SUFFIX + pc.SUFFIX)
        bundle(stray)
        removed = pc.prune(self.dir, now=self.now)
        self.assertTrue(fresh.exists())
        self.assertFalse(old.exists())
        self.assertFalse((self.dir / ("b" * 16 + ".json")).exists())
        self.assertFalse(stray.exists())
        self.assertIn(old.name, removed)

    def test_size_cap_removes_least_recently_used_but_spares_the_recent_and_the_current(self):
        hour = 3600
        a = self.entry("a" * 16, 30 * hour, size=100)
        b = self.entry("b" * 16, 20 * hour, size=100)
        current = self.entry("c" * 16, 40 * hour, size=100)
        recent = self.entry("d" * 16, 60, size=100)
        pc.prune(self.dir, keep="c" * 16, now=self.now, max_bytes=250)
        self.assertFalse(a.exists())
        self.assertFalse(b.exists())
        self.assertTrue(current.exists())
        self.assertTrue(recent.exists())

    def test_a_recent_corrupt_entry_is_left_alone_an_old_one_goes(self):
        recent = self.dir / ("e" * 16 + pc.SUFFIX)
        recent.mkdir()
        old = self.dir / ("f" * 16 + pc.SUFFIX)
        old.mkdir()
        os.utime(old, (self.now - 5 * 3600, self.now - 5 * 3600))
        pc.prune(self.dir, now=self.now)
        self.assertTrue(recent.exists())  # might be mid-write by another process
        self.assertFalse(old.exists())


if __name__ == "__main__":
    unittest.main()
