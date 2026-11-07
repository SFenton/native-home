"""``tools/clean.sh``: deletes only strictly inside build output and the scratchpad root."""

import os
import shutil
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory, mkdtemp

SCRIPT = Path(__file__).resolve().parents[1] / "clean.sh"
SCRATCH = Path(os.path.realpath("/tmp")) / f"claude-{os.getuid()}"


def git_init(path):
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q", str(path)], check=True)


class CleanTests(unittest.TestCase):
    def setUp(self):
        self._td = TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        base = Path(os.path.realpath(self._td.name))
        self.repo, self.outside = base / "repo", base / "outside"
        git_init(self.repo)
        for d in (self.repo / "build", self.repo / "apple" / ".build", self.outside,
                  self.repo / ".claude" / "worktrees" / "w1" / "build",
                  self.repo / ".claude" / "worktrees" / "w1" / "apple" / ".build-x"):
            d.mkdir(parents=True)
        SCRATCH.mkdir(exist_ok=True)
        self.tmp = Path(mkdtemp(dir=SCRATCH))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.victim = self.make(self.outside / "keep")

    def clean(self, *args, env=None, cwd=None):
        return subprocess.run([str(SCRIPT), *map(str, args)], cwd=cwd or self.repo, capture_output=True,
                              text=True, env={**os.environ, **(env or {})})

    def make(self, path):
        path.mkdir(parents=True, exist_ok=True)
        (path / "f").write_text("x")
        return path

    def assertRefused(self, *args, **kw):
        r = self.clean(*args, **kw)
        self.assertEqual(r.returncode, 1, (args, r.stderr))
        self.assertIn("refused", r.stderr)
        self.assertTrue((self.victim / "f").exists(), args)

    def test_allowed_paths_deleted(self):
        paths = [self.make(self.repo / "build" / "a"), self.make(self.repo / "apple" / ".build" / "debug"),
                 self.make(self.repo / ".claude" / "worktrees" / "w1" / "build" / "b"),
                 self.make(self.repo / ".claude" / "worktrees" / "w1" / "apple" / ".build-x" / "c"),
                 self.make(self.tmp / "scratch")]
        r = self.clean(*paths)
        self.assertEqual(r.returncode, 0, r.stderr)
        for p in paths:
            self.assertFalse(p.exists(), p)

    def test_relative_path(self):
        p = self.make(self.repo / "build" / "rel")
        self.assertEqual(self.clean("build/rel").returncode, 0)
        self.assertFalse(p.exists())

    def test_missing_path_is_noop(self):
        self.assertEqual(self.clean(self.repo / "build" / "nope").returncode, 0)

    def test_plain_file_and_trailing_slash(self):
        f = self.repo / "build" / "file.txt"
        f.write_text("x")
        d = self.make(self.repo / "build" / "dir")
        self.assertEqual(self.clean(f, f"{d}/").returncode, 0)
        self.assertFalse(f.exists() or d.exists())

    def test_odd_names_and_double_dash(self):
        a = self.make(self.repo / "build" / "has space")
        b = self.make(self.repo / "build" / "new\nline")
        c = self.make(self.repo / "build" / "-dash")
        self.assertEqual(self.clean(a, "--", c).returncode, 1)  # `--` not first is a path, refused
        self.assertTrue(a.exists() and c.exists())
        self.assertEqual(self.clean("--", a, b, c).returncode, 0)
        self.assertFalse(a.exists() or b.exists() or c.exists())

    def test_leading_dash_argument_is_a_path(self):
        self.make(self.repo / "-x")
        self.assertRefused("-x")
        self.assertTrue((self.repo / "-x" / "f").exists())
        self.assertRefused("-rf", self.repo / "build")

    def test_refusals(self):
        link = self.repo / "build" / "link"
        link.symlink_to(self.victim)
        for c in (self.repo / "build" / ".." / ".." / "outside" / "keep", self.victim, self.repo,
                  self.repo / "build", self.repo / "apple" / ".build", self.tmp.parent, self.repo / "apple",
                  link / "f", Path("/"), self.repo / ".claude" / "worktrees" / "w1" / "build"):
            self.assertRefused(c)
        self.assertTrue(self.repo.exists())

    def test_mixed_args_delete_nothing(self):
        good = self.make(self.repo / "build" / "good")
        r = self.clean(good, self.make(self.outside / "bad"))
        self.assertEqual(r.returncode, 1)
        self.assertTrue((good / "f").exists())

    def test_symlink_argument_is_unlinked_not_followed(self):
        inside = self.make(self.repo / "build" / "real")
        link_in, link_out = self.repo / "build" / "to-inside", self.repo / "build" / "to-outside"
        link_tmp = self.tmp / "to-outside"
        link_in.symlink_to(inside)
        link_out.symlink_to(self.victim)
        link_tmp.symlink_to(self.victim)
        r = self.clean(link_in, link_out, link_tmp)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(link_in.is_symlink() or link_out.is_symlink() or link_tmp.is_symlink())
        self.assertTrue((inside / "f").exists())
        self.assertTrue((self.victim / "f").exists())

    def test_symlinked_roots_are_ignored(self):
        (self.repo / "apple" / ".build-evil").symlink_to(self.outside)
        self.assertRefused(self.repo / "apple" / ".build-evil" / "keep")
        shutil.rmtree(self.repo / "build")
        (self.repo / "build").symlink_to(self.outside)
        self.assertRefused(self.repo / "build" / "keep")
        wts = self.repo / ".claude" / "worktrees"
        (wts / "w2").symlink_to(self.outside)
        (self.outside / "build").mkdir()
        self.make(self.outside / "build" / "keep")
        self.assertRefused(wts / "w2" / "build" / "keep")
        shutil.rmtree(wts / "w1" / "build")
        (wts / "w1" / "build").symlink_to(self.outside)
        self.assertRefused(wts / "w1" / "build" / "keep")
        shutil.rmtree(wts)
        wts.symlink_to(self.outside)
        self.assertRefused(wts / "w2" / "build" / "keep")
        self.assertTrue((self.outside / "build" / "keep").exists())

    def test_symlink_inside_scratch_dir_is_not_followed(self):
        (self.tmp / "dir").symlink_to(self.outside)
        self.assertRefused(self.tmp / "dir" / "keep")

    def test_env_overrides_have_no_effect(self):
        decoy = self.outside / "decoy"
        git_init(decoy)
        target = self.make(decoy / "build" / "x")
        env = {"GIT_DIR": str(decoy / ".git"), "GIT_COMMON_DIR": str(decoy / ".git"), "GIT_WORK_TREE": str(decoy),
               "HASS_CLEAN_REPO": str(decoy), "HASS_CLEAN_TMP": str(self.outside), "HASS_CLEAN_REPO_REAL": str(decoy)}
        self.assertRefused(target, env=env)
        self.assertTrue((target / "f").exists())
        own = self.make(self.repo / "build" / "own")
        self.assertEqual(self.clean(own, env=env).returncode, 0)
        self.assertFalse(own.exists())

    def test_no_args_is_usage_error(self):
        self.assertEqual(self.clean().returncode, 2)


if __name__ == "__main__":
    unittest.main()
