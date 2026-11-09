"""Lane and ship scripts (``tools/lane_new.sh``, ``tools/ship.sh``) against throwaway repositories."""

import json
import os
import shutil
import stat
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
       "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=ENV, capture_output=True, text=True, check=True).stdout.strip()


def make_repo(tmp):
    """A clone of a bare origin whose ``tools/`` holds the scripts under test; returns (clone, origin)."""
    origin = Path(tmp) / "origin.git"
    git(tmp, "init", "-q", "--bare", "-b", "main", str(origin))
    clone = Path(tmp) / "clone"
    git(tmp, "clone", "-q", str(origin), str(clone))
    (clone / "tools").mkdir()
    for name in ("lane_new.sh", "ship.sh", "ship_guard.sh", "review_verdict.py"):
        shutil.copy(TOOLS / name, clone / "tools" / name)
    (clone / ".gitignore").write_text("*.env\n.claude/worktrees/\n")
    (clone / "README.md").write_text("hi\n")
    git(clone, "add", "-A")
    git(clone, "commit", "-q", "-m", "init")
    git(clone, "push", "-q", "-u", "origin", "main")
    return clone, origin


class LaneTests(unittest.TestCase):
    def test_creates_a_worktree_on_its_own_branch_and_is_rerunnable(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            first = subprocess.run(["bash", "tools/lane_new.sh", "chores"], cwd=clone, env=ENV, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            lane = clone / ".claude" / "worktrees" / "chores"
            self.assertTrue((lane / ".git").exists())
            self.assertEqual(git(lane, "rev-parse", "--abbrev-ref", "HEAD"), "claude/chores")
            self.assertIn("lane created", first.stdout)
            self.assertIn("tools/bg_run.py", first.stdout)
            again = subprocess.run(["bash", "tools/lane_new.sh", "chores"], cwd=clone, env=ENV, capture_output=True, text=True)
            self.assertIn("lane exists", again.stdout)

    def test_from_inside_a_lane_does_not_nest(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            subprocess.run(["bash", "tools/lane_new.sh", "a"], cwd=clone, env=ENV, check=True, capture_output=True)
            lane = clone / ".claude" / "worktrees" / "a"
            shutil.copytree(clone / "tools", lane / "tools", dirs_exist_ok=True)
            subprocess.run(["bash", "tools/lane_new.sh", "b"], cwd=lane, env=ENV, check=True, capture_output=True)
            self.assertTrue((clone / ".claude" / "worktrees" / "b" / ".git").exists())
            self.assertFalse((lane / ".claude").exists())

    def test_usage(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            self.assertEqual(subprocess.run(["bash", "tools/lane_new.sh"], cwd=clone, env=ENV, capture_output=True).returncode, 2)


class ShipTests(unittest.TestCase):
    def ship(self, clone, *args, extra_env=None, path_prefix=None):
        env = {**ENV, **(extra_env or {})}
        if path_prefix:
            env["PATH"] = f"{path_prefix}{os.pathsep}{env['PATH']}"
        return subprocess.run(["bash", "tools/ship.sh", *args], cwd=clone, env=env, capture_output=True, text=True)

    def test_refuses_on_main(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            (clone / "a.txt").write_text("x")
            done = self.ship(clone, "Add a")
            self.assertEqual(done.returncode, 1)
            self.assertIn("refusing to commit on 'main'", done.stderr)

    def test_commits_with_trailer_and_pushes(self):
        with TemporaryDirectory() as tmp:
            clone, origin = make_repo(tmp)
            home = Path(tmp) / "home"
            home.mkdir()
            use_home(clone, home)
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            done = self.ship(clone, "Add a")
            self.assertEqual(done.returncode, 0, done.stderr)
            message = git(clone, "log", "-1", "--format=%B")
            self.assertIn("Add a", message)
            self.assertIn("Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>", message)
            self.assertEqual(git(origin, "rev-parse", "claude/x"), git(clone, "rev-parse", "HEAD"))

    def test_trailer_follows_ship_coauthor(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            self.ship(clone, "Add a", "--no-push", extra_env={"SHIP_COAUTHOR": "Claude Opus 5.5 <noreply@anthropic.com>"})
            self.assertIn("Co-Authored-By: Claude Opus 5.5", git(clone, "log", "-1", "--format=%B"))

    def test_note_adds_release_note_trailers_beside_the_coauthor(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            done = self.ship(clone, "Add a", "--no-push", "--note", "Rooms: The list loads faster.",
                             "--note", "Cameras: The live view opens sooner.")
            self.assertEqual(done.returncode, 0, done.stderr)
            message = git(clone, "log", "-1", "--format=%B")
            self.assertIn("Release-Note: Rooms: The list loads faster.\nRelease-Note: Cameras: The live view opens "
                          "sooner.\nCo-Authored-By:", message)

    def test_without_a_note_there_is_no_release_note_trailer(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            self.ship(clone, "Add a", "--no-push")
            self.assertNotIn("Release-Note", git(clone, "log", "-1", "--format=%B"))

    def test_refuses_secrets_and_leaves_nothing_staged(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "prod.p12").write_text("key")
            (clone / ".env.local").write_text("TOKEN=1")
            done = self.ship(clone, "Add keys", "--no-push")
            self.assertEqual(done.returncode, 1)
            self.assertIn("prod.p12", done.stderr)
            self.assertEqual(git(clone, "diff", "--cached", "--name-only"), "")

    def test_gitignored_env_files_are_simply_left_out(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "temp.env").write_text("TOKEN=1")
            (clone / "a.txt").write_text("x")
            done = self.ship(clone, "Add a", "--no-push")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertNotIn("temp.env", git(clone, "show", "--name-only", "--format=", "HEAD"))

    def test_pr_runs_gh_with_assignee_footer_and_body(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            fake = Path(tmp) / "bin"
            fake.mkdir()
            gh = fake / "gh"
            gh.write_text('#!/bin/sh\n[ "$2" = create ] && printf "%s\\n" "$@" > "$GH_LOG"\nexit 0\n')
            gh.chmod(gh.stat().st_mode | stat.S_IEXEC)
            log = Path(tmp) / "gh.log"
            done = self.ship(clone, "Add a", "--pr", "--draft", "--body", "Why", extra_env={"GH_LOG": str(log)}, path_prefix=str(fake))
            self.assertEqual(done.returncode, 0, done.stderr)
            args = log.read_text().splitlines()
            self.assertEqual(args[:2], ["pr", "create"])
            self.assertIn("--draft", args)
            self.assertEqual(args[args.index("--assignee") + 1], "SFenton")
            body = args[args.index("--body") + 1]
            self.assertTrue(body.startswith("Why"))
            self.assertIn("Generated with [Claude Code]", "\n".join(args))

    def test_nothing_to_commit_still_pushes(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "claude/x")
            done = self.ship(clone, "Nothing")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("nothing to commit", done.stdout)

    def test_base_drift_warns_but_never_changes_the_exit_code(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            shutil.copy(TOOLS / "base_drift.py", clone / "tools" / "base_drift.py")
            git(clone, "switch", "-q", "-c", "claude/uikit-port")
            git(clone, "push", "-q", "-u", "origin", "claude/uikit-port")
            (clone / "tools" / "triage").mkdir()
            (clone / "tools" / "triage" / "config.json").write_text('{"workflow_base": "claude/uikit-port"}')
            (clone / "local.txt").write_text("x")
            git(clone, "add", "local.txt")
            git(clone, "commit", "-q", "-m", "local only")
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            done = self.ship(clone, "Add a")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("base drift", done.stderr)
            self.assertIn("local only", done.stderr)

    def test_base_drift_clean_and_a_crash_do_not_warn_falsely(self):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            shutil.copy(TOOLS / "base_drift.py", clone / "tools" / "base_drift.py")
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            done = self.ship(clone, "Add a")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertNotIn("base drift", done.stderr)
            self.assertNotIn("base-drift check failed", done.stderr)
            (clone / "tools" / "base_drift.py").write_text("raise SystemExit(1)\n")
            (clone / "b.txt").write_text("x")
            done = self.ship(clone, "Add b")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("base-drift check failed (exit 1)", done.stderr)


GH_STUB = r"""#!/bin/sh
echo "$@" >> "$GH_LOG"
case "$1 $2" in
  "pr create") exit 0 ;;
  "pr view") echo 7 ;;
  "repo view") echo "$GH_REPO_NAME" ;;
esac
exit 0
"""
#: Stands in for tools/pr_land.py: records its argv and exits with ``PRLAND_RC`` (the real gates are tested in test_pr_land.py).
ARM_STUB = """import os, sys
open(os.environ["PRLAND_LOG"], "a").write(" ".join(sys.argv[1:]) + "\\n")
print(os.environ.get("PRLAND_SAYS", "armed #7"))
sys.exit(int(os.environ.get("PRLAND_RC", "0")))
"""


def use_home(clone, home):
    """Point the clone's copy of review_verdict.py at a fake account home (the real one reads the password database, not $HOME)."""
    path = clone / "tools" / "review_verdict.py"
    path.write_text(path.read_text().replace("Path(pwd.getpwuid(os.getuid()).pw_dir)", "Path(%r)" % str(home)))


def record_pass(home, sha, branch="claude__x"):
    """A verdict the way the reviewer's record.py --lane leaves it, in the fake home's trusted store."""
    folder = Path(home) / "hass-agents" / "reviews"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{branch}-{sha[:12]}.json").write_text(json.dumps({"verdict": "pass", "head": sha, "findings": [],
                                                                  "reviewer": {"agent_type": "reviewer", "session_id": "s"}}))


class ShipArmTests(unittest.TestCase):
    """After the PR opens on native-home, ship.sh arms through ``pr_land.py`` (which runs the gates and pins the head); ship itself never merges."""

    def run_ship(self, repo="SFenton/native-home", arm_rc="0"):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            (clone / "tools" / "pr_land.py").write_text(ARM_STUB)
            home = Path(tmp) / "home"
            home.mkdir()
            use_home(clone, home)
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            git(clone, "add", "-A")
            git(clone, "commit", "-q", "-m", "Add a")
            self.head = git(clone, "rev-parse", "HEAD")
            record_pass(home, self.head)
            fake = Path(tmp) / "bin"
            fake.mkdir()
            (fake / "gh").write_text(GH_STUB)
            (fake / "gh").chmod(0o755)
            log, arm_log = Path(tmp) / "gh.log", Path(tmp) / "arm.log"
            env = {**ENV, "PATH": f"{fake}{os.pathsep}{ENV['PATH']}", "GH_LOG": str(log), "GH_REPO_NAME": repo, "HOME": str(home),
                   "PRLAND_LOG": str(arm_log), "PRLAND_RC": arm_rc}
            done = subprocess.run(["bash", "tools/ship.sh", "Add a", "--pr"], cwd=clone, env=env, capture_output=True, text=True)
            return done, log.read_text() if log.exists() else "", arm_log.read_text() if arm_log.exists() else ""

    def test_ship_runs_pr_land_with_the_pr_number_after_the_pr_opens(self):
        """Fails if: ship.sh arms with its own gh pr merge, or does not call pr_land.py with the PR number once the PR exists."""
        done, log, arm = self.run_ship()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(arm.strip(), "7")
        self.assertIn("armed #7", done.stdout)
        self.assertNotIn("pr merge", log)
        self.assertLess(log.index("pr create"), log.index("repo view"))

    def test_ship_sh_contains_no_gh_pr_merge_command(self):
        """Fails if: ship.sh arms or merges itself again, bypassing the app-UI gate, the owner-kept set and the denylist check."""
        text = (TOOLS / "ship.sh").read_text()
        self.assertNotIn("gh pr merge", text)
        self.assertNotIn("ruleset_gate", text)
        self.assertIn("pr_land.py", text)

    def test_a_refusal_from_pr_land_is_a_notice_and_ship_still_exits_zero(self):
        """Fails if: a blocked or failed pr_land (a UI PR parked by the app-UI gate, no pass) fails ship, or goes unmentioned."""
        for rc in ("1", "2"):
            with self.subTest(rc=rc):
                done, _, arm = self.run_ship(arm_rc=rc)
                self.assertEqual(done.returncode, 0, done.stderr)
                self.assertEqual(arm.strip(), "7")
                self.assertIn("ship: not armed (see above); land it with tools/pr_land.sh 7", done.stderr)

    def test_another_repository_never_runs_pr_land(self):
        """Fails if: ship.sh arms a pull request of a repository other than SFenton/native-home."""
        done, log, arm = self.run_ship(repo="SFenton/Fenton-HASS-Native")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(arm, "")
        self.assertNotIn("pr merge", log)


class ShipReviewBeforePushTests(unittest.TestCase):
    """A native-home (or unreadable) origin refuses the push without a pass; nothing leaves the machine."""

    def ship_with_origin(self, url, passed, hooks=True):
        with TemporaryDirectory() as tmp:
            clone, origin = make_repo(tmp)
            home = Path(tmp) / "home"
            home.mkdir()
            use_home(clone, home)
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            git(clone, "add", "-A")
            git(clone, "commit", "-q", "-m", "Add a")
            if passed:
                record_pass(home, git(clone, "rev-parse", "HEAD"))
            if hooks:
                git(clone, "config", "core.hooksPath", ".githooks")
            git(clone, "remote", "set-url", "origin", url)
            done = subprocess.run(["bash", "tools/ship.sh", "Add a"], cwd=clone, env={**ENV, "HOME": str(home)}, capture_output=True, text=True)
            return done

    def test_native_home_without_a_pass_is_refused_before_the_push(self):
        done = self.ship_with_origin("git@github.com:SFenton/native-home.git", passed=False)
        self.assertEqual(done.returncode, 1)
        self.assertIn("needs the reviewer's pass", done.stderr)
        self.assertNotIn("pushed", done.stdout)

    def test_native_home_without_the_git_hook_installed_is_refused(self):
        done = self.ship_with_origin("git@github.com:SFenton/native-home.git", passed=True, hooks=False)
        self.assertEqual(done.returncode, 1)
        self.assertIn("tools/setup.sh", done.stderr)
        self.assertNotIn("pushed", done.stdout)

    def test_an_unreadable_origin_fails_closed(self):
        done = self.ship_with_origin("nonsense", passed=True)
        self.assertEqual(done.returncode, 1)
        self.assertIn("not a readable GitHub URL", done.stderr)


if __name__ == "__main__":
    unittest.main()
