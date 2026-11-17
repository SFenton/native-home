"""``tools/hooks/commit_guard.py``: a commit with staged ``build/`` paths and ``git add -f`` of a ``build/`` path are refused."""

import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS / "hooks"))
import commit_guard  # noqa: E402

ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
       "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=ENV, capture_output=True, text=True, check=True).stdout.strip()


class BuildGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = os.path.realpath(self.tmp.name)
        git(self.repo, "init", "-q", "-b", "lane")
        (Path(self.repo) / ".gitignore").write_text("build/\n")
        (Path(self.repo) / "src.txt").write_text("a\n")
        git(self.repo, "add", ".gitignore", "src.txt")
        git(self.repo, "commit", "-q", "-m", "init")
        (Path(self.repo) / "build" / "evidence").mkdir(parents=True)
        (Path(self.repo) / "build" / "evidence" / "x.md").write_text("x\n")
        (Path(self.repo) / "build" / "x.md").write_text("x\n")

    def reason(self, command, cwd=None):
        return commit_guard.command_reason(command, cwd or self.repo)

    def test_force_add_of_a_build_path_is_refused(self):
        for command in ("git add -f build/x.md", "git add --force build/evidence/x.md", "git add -fA build/", "git add --forc build/evidence",
                        "git add -f -- build/evidence/x.md", "git add -f src.txt build/evidence/x.md", "git add -f ./build/evidence"):
            with self.subTest(command=command):
                why = self.reason(command)
                self.assertIn("build/ evidence stays local", why or "")

    def test_a_forced_add_that_takes_in_the_ignored_tree_is_refused(self):
        for command in ("git add -f .", "git add -fA", "git add -Af", "git add --force -A", "git add -f -A", "git add -f *",
                        "git add --force --all", "git add -f build", "git add -f :/"):
            with self.subTest(command=command):
                self.assertIn("build/ evidence stays local", self.reason(command) or "")

    def test_a_forced_add_that_misses_build_passes(self):
        (Path(self.repo) / "docs").mkdir()
        (Path(self.repo) / "docs" / "a.md").write_text("a\n")
        for command in ("git add -f docs", "git add -f docs/a.md", "git add -fn docs", "git add -f src.txt"):
            with self.subTest(command=command):
                self.assertIsNone(self.reason(command))

    def test_an_unforced_add_all_passes_because_build_is_ignored(self):
        for command in ("git add -A", "git add .", "git add --all"):
            with self.subTest(command=command):
                self.assertIsNone(self.reason(command))

    def test_commit_a_with_a_modified_tracked_build_file_is_refused(self):
        git(self.repo, "add", "-f", "build/evidence/x.md")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "oops")
        (Path(self.repo) / "build" / "evidence" / "x.md").write_text("changed\n")
        for command in ("git commit -am msg", "git commit --all -m msg", "git commit -a -m msg"):
            with self.subTest(command=command):
                self.assertIn("build/evidence/x.md", self.reason(command) or "")
        self.assertIsNone(self.reason("git commit -m msg"))  # nothing staged: without -a the unstaged change is not committed

    def test_commit_a_ignores_a_deleted_tracked_build_file(self):
        git(self.repo, "add", "-f", "build/evidence/x.md")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "oops")
        (Path(self.repo) / "build" / "evidence" / "x.md").unlink()
        self.assertIsNone(self.reason("git commit -am msg"))

    def test_the_message_points_to_the_rule(self):
        self.assertIn("security.md#house-data", commit_guard.BUILD_WHY)

    def test_force_add_is_judged_against_the_repo_root(self):
        sub = os.path.join(self.repo, "build", "evidence")
        self.assertIn("stays local", self.reason("git add -f x.md", sub) or "")
        self.assertIn("stays local", self.reason("git add -f ../../build/evidence/x.md", sub) or "")
        self.assertIsNone(self.reason("git add -f ../../src.txt", sub))

    def test_other_adds_pass(self):
        for command in ("git add build/x.md", "git add -A", "git add -f src.txt", "git add -f docs/build/x.md", "git add -f builder/x.md",
                        "git status build/", "echo git add -f build/x.md"):
            with self.subTest(command=command):
                self.assertIsNone(self.reason(command))

    def test_a_commit_with_a_staged_build_path_is_refused(self):
        git(self.repo, "add", "-f", "build/evidence/x.md")
        why = self.reason("git commit -m msg")
        self.assertIn("build/ evidence stays local", why or "")
        self.assertIn("build/evidence/x.md", why)
        self.assertIsNotNone(self.reason("git commit -am msg"))

    def test_a_staged_build_path_is_found_from_a_subfolder(self):
        git(self.repo, "add", "-f", "build/evidence/x.md")
        self.assertIsNotNone(self.reason("git commit -m msg", os.path.join(self.repo, "build")))

    def test_a_commit_with_no_build_path_passes(self):
        (Path(self.repo) / "src.txt").write_text("b\n")
        git(self.repo, "add", "src.txt")
        self.assertIsNone(self.reason("git commit -m msg"))

    def test_a_commit_that_only_deletes_a_build_path_passes(self):
        git(self.repo, "add", "-f", "build/evidence/x.md")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "oops")
        git(self.repo, "rm", "-q", "--cached", "build/evidence/x.md")
        self.assertIsNone(self.reason("git commit -m cleanup"))

    def test_existing_refusals_stay(self):
        self.assertIn("--no-verify", self.reason("git commit --no-verify -m x") or "")
        git(self.repo, "checkout", "-q", "-b", "main")
        self.assertIn("'main'", self.reason("git commit -m x") or "")

    def test_the_reason_is_sent_back_through_block(self):
        self.assertIn("build/ evidence stays local", commit_guard.block(commit_guard.BUILD_WHY))


if __name__ == "__main__":
    unittest.main()
