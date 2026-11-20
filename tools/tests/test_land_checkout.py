"""``tools/land_checkout.py``: a clean ``origin/main`` tree for ``pr_land``. Real git, a bare origin, no mocks of git.

The primary checkout in the fixture is 45 commits behind with an uncommitted conflicting edit, as in ``build/retro/pr167-phase.md``.
"""

import io
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
import land_checkout  # noqa: E402
import merge_guard  # noqa: E402
import worktree_guard  # noqa: E402

ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
PINNED = ["tools/pr_land.sh", "tools/pr_land.py", "tools/house_scan.py", "tools/agent_login.py", "tools/pr_blockers.py",
          "tools/review_verdict.py", "tools/ruleset_gate.py", "tools/request_repo.py", "tools/triage/config.json"]


def git(where, *args):
    return subprocess.run(["git", "-C", str(where), *args], check=True, capture_output=True, text=True, env=dict(os.environ, **ENV)).stdout.strip()


class LandFixture(unittest.TestCase):
    """A bare origin, a seed clone that moves origin on, and a primary checkout that stays behind and dirty."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(os.path.realpath(self._tmp.name))
        self.origin = self.root / "origin.git"
        git(self.root, "init", "-q", "--bare", "-b", "main", str(self.origin))
        self.seed = self.root / "seed"
        git(self.root, "clone", "-q", str(self.origin), str(self.seed))
        for name in PINNED:
            path = self.seed / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"{name} v0\n")
        git(self.seed, "add", "-A")
        git(self.seed, "commit", "-qm", "seed")
        git(self.seed, "push", "-q", "origin", "HEAD:main")
        self.primary = self.root / "sessions" / "primary"
        self.primary.parent.mkdir()
        git(self.root, "clone", "-q", str(self.origin), str(self.primary))
        self.advance(45)
        (self.primary / "tools" / "pr_land.py").write_text("another session's conflicting edit\n")
        (self.primary / ".gitignore").write_text("build/\n")
        self.land = self.primary / "build" / "land-main"

    def advance(self, commits):
        """Move origin's main on by ``commits`` commits, each editing ``tools/pr_land.py``."""
        for _ in range(commits):
            path = self.seed / "tools" / "pr_land.py"
            path.write_text(path.read_text() + "x\n")
            git(self.seed, "commit", "-qam", "step")
        git(self.seed, "push", "-q", "origin", "HEAD:main")

    def run_tool(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        before = os.getcwd()
        os.chdir(self.primary)
        try:
            with redirect_stdout(out), redirect_stderr(err):
                code = land_checkout.main(list(extra))
        finally:
            os.chdir(before)
        return code, out.getvalue().strip().splitlines(), err.getvalue()


class LandCheckoutTests(LandFixture):
    def test_prints_a_tree_the_guard_accepts_for_a_stale_dirty_checkout(self):
        self.assertFalse(merge_guard.pr_land_matches_base("tools/pr_land.sh 5", str(self.primary / "tools" / "pr_land.sh")))
        code, lines, _ = self.run_tool()
        self.assertEqual(code, 0)
        self.assertEqual(lines[-1], f"land from: {self.land}")
        self.assertEqual(git(self.land, "hash-object", "tools/pr_land.py"), git(self.seed, "hash-object", "tools/pr_land.py"))
        self.assertNotEqual(git(self.land, "hash-object", "tools/pr_land.py"), git(self.primary, "hash-object", "tools/pr_land.py"))
        self.assertTrue(merge_guard.pr_land_matches_base("tools/pr_land.sh 5", str(self.land / "tools" / "pr_land.sh")))
        self.assertEqual(git(self.land, "rev-parse", "HEAD"), git(self.seed, "rev-parse", "HEAD"))
        self.assertEqual(subprocess.run(["git", "-C", str(self.land), "symbolic-ref", "-q", "HEAD"], capture_output=True).returncode, 1)  # detached
        self.assertIn("conflicting edit", (self.primary / "tools" / "pr_land.py").read_text())  # the dirty checkout is left alone

    def test_a_second_call_after_origin_moves_advances_the_same_tree(self):
        self.run_tool()
        marker = self.land / ".git"
        before = git(self.land, "rev-parse", "HEAD")
        self.advance(2)
        code, lines, err = self.run_tool()
        self.assertEqual((code, lines[-1]), (0, f"land from: {self.land}"))
        self.assertIn("advanced", err)
        self.assertNotEqual(git(self.land, "rev-parse", "HEAD"), before)
        self.assertEqual(git(self.land, "rev-parse", "HEAD"), git(self.seed, "rev-parse", "HEAD"))
        self.assertTrue(marker.exists())

    def test_a_dirty_land_tree_is_recreated_not_repaired(self):
        self.run_tool()
        (self.land / "tools" / "pr_land.py").write_text("edited in the land tree\n")
        (self.land / "stray.txt").write_text("untracked\n")
        code, lines, err = self.run_tool()
        self.assertEqual((code, lines[-1]), (0, f"land from: {self.land}"))
        self.assertIn("recreated", err)
        self.assertFalse((self.land / "stray.txt").exists())
        self.assertTrue(merge_guard.pr_land_matches_base("tools/pr_land.sh 5", str(self.land / "tools" / "pr_land.sh")))

    def test_a_folder_that_is_not_a_worktree_is_replaced(self):
        self.land.mkdir(parents=True)
        (self.land / "junk").write_text("x\n")
        code, lines, _ = self.run_tool()
        self.assertEqual((code, lines[-1]), (0, f"land from: {self.land}"))
        self.assertFalse((self.land / "junk").exists())

    def test_no_fetch_gives_failed_and_no_path(self):
        git(self.primary, "remote", "set-url", "origin", str(self.root / "gone.git"))
        code, lines, err = self.run_tool()
        self.assertEqual(code, 1)
        self.assertEqual(lines, ["land from: failed"])
        self.assertIn("fetch", err)
        self.assertFalse(self.land.exists())

    def test_a_tree_that_still_differs_is_failed(self):
        with mock.patch.object(merge_guard, "pr_land_matches_base", return_value=False):
            code, lines, err = self.run_tool()
        self.assertEqual((code, lines), (1, ["land from: failed"]))
        self.assertIn("still differ", err)

    def test_the_nested_tree_is_not_in_the_callers_git_status(self):
        self.run_tool()
        self.assertTrue(self.land.is_dir())
        status = git(self.primary, "status", "--porcelain", "--untracked-files=all")
        self.assertNotIn("build", status)
        self.assertIn("tools/pr_land.py", status)  # the caller's own edit still shows

    def test_path_option_overrides_the_default(self):
        elsewhere = self.root / "elsewhere"
        code, lines, _ = self.run_tool("--path", str(elsewhere))
        self.assertEqual((code, lines[-1]), (0, f"land from: {elsewhere}"))


class GuardFixtureTests(LandFixture):
    """What ``merge_guard`` and ``worktree_guard`` say about landing from the printed tree (the Steward's open questions)."""

    def setUp(self):
        super().setUp()
        self.run_tool()
        merge_guard._CWD = None
        self.addCleanup(setattr, merge_guard, "_CWD", None)

    def verdict(self, command, cwd, agent=True):
        with mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": ""}):
            return merge_guard.reason(command, str(cwd), agent)

    def test_the_sanctioned_form_passes_from_the_land_tree_cwd(self):
        """The main session after ``cd <land tree>``: the payload cwd is the tree, so the relative script is the tree's."""
        self.assertIsNone(self.verdict("tools/pr_land.sh 5", self.land))

    def test_the_same_form_is_refused_from_the_stale_checkout(self):
        why = self.verdict("tools/pr_land.sh 5", self.primary)
        self.assertIn("differs from origin", why or "")

    def test_a_chained_cd_is_not_the_sanctioned_form(self):
        """A sub-agent's cwd resets between calls, so it cannot ``cd`` first and then land; the one-command chain is refused too."""
        why = self.verdict(f"cd {self.land} && tools/pr_land.sh 5", self.primary)
        self.assertIsNotNone(why)

    def test_an_absolute_path_to_the_land_tree_is_not_sanctioned(self):
        why = self.verdict(f"{self.land}/tools/pr_land.sh 5", self.primary)
        self.assertIn("exactly", why or "")

    def test_worktree_guard_allows_adding_a_detached_worktree_and_the_tool_command(self):
        self.assertIsNone(worktree_guard.bash_reason(f"git worktree add --detach {self.root}/other origin/main", str(self.primary)))
        self.assertIsNone(worktree_guard.bash_reason("python3 tools/land_checkout.py", str(self.primary)))
        self.assertIsNone(worktree_guard.bash_reason(f"git -C {self.land} checkout --detach origin/main", str(self.primary)))


if __name__ == "__main__":
    unittest.main()
