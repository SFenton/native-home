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


GOOD_BODY = "## Summary\nPages load faster on iPhone. Nothing else changes.\n\n## Tests\n- unit (HassCore): cache test (pass)"


def make_repo(tmp):
    """A clone of a bare origin whose ``tools/`` holds the scripts under test; returns (clone, origin)."""
    origin = Path(tmp) / "origin.git"
    git(tmp, "init", "-q", "--bare", "-b", "main", str(origin))
    clone = Path(tmp) / "clone"
    git(tmp, "clone", "-q", str(origin), str(clone))
    (clone / "tools").mkdir()
    for name in ("lane_new.sh", "ship.sh", "ship_guard.sh", "review_verdict.py", "lane_check.py", "pr_text.py", "pr_text_words.json"):
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
            done = self.ship(clone, "Add a", "--pr", "--draft", "--body", GOOD_BODY, extra_env={"GH_LOG": str(log)}, path_prefix=str(fake))
            self.assertEqual(done.returncode, 0, done.stderr)
            args = log.read_text().splitlines()
            self.assertEqual(args[:2], ["pr", "create"])
            self.assertIn("--draft", args)
            self.assertEqual(args[args.index("--assignee") + 1], "SFenton")
            body = "\n".join(args[args.index("--body") + 1:args.index("--assignee")])
            self.assertEqual(body, GOOD_BODY)
            self.assertNotIn("Generated with", "\n".join(args))

    def refused_ship(self, *args):
        """Ship with ``--pr`` against a fake ``gh``; returns (result, whether gh was called to create, commits added)."""
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
            done = self.ship(clone, *args, extra_env={"GH_LOG": str(log)}, path_prefix=str(fake))
            return done, log.exists(), git(clone, "rev-list", "--count", "main..HEAD")

    def test_pr_with_a_refused_description_stops_before_commit_and_push(self):
        """Fails if: ``ship.sh --pr`` opens a pull request or commits when ``body-check --strict`` refuses the description (no
        sections, a generated-by footer, a fix sent elsewhere without a name), or the refusal hides the checker's line."""
        footer = GOOD_BODY + "\n\n\U0001F916 Generated with [Claude Code](https://claude.com/claude-code)\n"
        elsewhere = GOOD_BODY.replace("Nothing else changes.", "That fix is in a different repository.")
        for body in ("Why", footer, elsewhere):
            done, created, commits = self.refused_ship("Add a", "--pr", "--body", body)
            self.assertEqual(done.returncode, 1, body)
            self.assertIn("the description was refused", done.stderr)
            self.assertFalse(created)
            self.assertEqual(commits, "0")
        self.assertIn("footer", self.refused_ship("Add a", "--pr", "--body", footer)[0].stderr)
        self.assertIn("different repository", self.refused_ship("Add a", "--pr", "--body", elsewhere)[0].stderr)

    def test_pr_with_a_refused_title_or_no_body_stops(self):
        """Fails if: a title longer than 70 characters or an empty description reaches ``gh pr create``."""
        done, created, commits = self.refused_ship("A" * 80, "--pr", "--body", GOOD_BODY)
        self.assertEqual((done.returncode, created, commits), (1, False, "0"))
        self.assertIn("the title was refused", done.stderr)
        done, created, _ = self.refused_ship("Add a", "--pr")
        self.assertEqual((done.returncode, created), (1, False))

    def test_a_push_without_a_pull_request_is_not_checked(self):
        """Fails if: the description check runs on a ship that opens no pull request."""
        done, _created, commits = self.refused_ship("Add a", "--no-push")
        self.assertEqual((done.returncode, commits), (0, "1"))

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
            done = subprocess.run(["bash", "tools/ship.sh", "Add a", "--pr", "--body", GOOD_BODY], cwd=clone, env=env, capture_output=True, text=True)
            return done, log.read_text() if log.exists() else "", arm_log.read_text() if arm_log.exists() else ""

    def test_ship_runs_pr_land_with_the_pr_number_after_the_pr_opens(self):
        """Fails if: ship.sh arms with its own gh pr merge, or does not call pr_land.py with the PR number once the PR exists."""
        done, log, arm = self.run_ship()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(arm.strip(), "7")
        self.assertIn("armed #7", done.stdout)
        self.assertNotIn("pr merge", log)
        self.assertLess(log.index("pr create"), log.index("repo view"))

    def test_ship_prints_the_waiter_command_on_native_home_only(self):
        """Fails if: ship.sh stops printing the ci_wait.py start line after the arm on native-home, or prints it for another repository."""
        done, _, _ = self.run_ship()
        self.assertIn("ship: start the waiter: tools/bg_run.py ci-7 --timeout 7200 -- python3 tools/ci_wait.py 7", done.stdout)
        other, _, arm = self.run_ship(repo="someone/else")
        self.assertEqual((other.returncode, arm), (0, ""))
        self.assertNotIn("ci_wait", other.stdout + other.stderr)

    def test_ship_runs_no_preflight_and_its_exit_is_unchanged(self):
        """Fails if: ship.sh calls the retired preflight again or a refused arm changes its exit code."""
        self.assertNotIn("land" + "_preflight", (TOOLS / "ship.sh").read_text())
        done, _, _ = self.run_ship(arm_rc="1")
        self.assertEqual(done.returncode, 0, done.stderr)

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
                self.assertIn("ship: not armed (see above); expected until the reviewer passes this head, then land it with tools/pr_land.sh 7", done.stderr)

    def test_another_repository_never_runs_pr_land(self):
        """Fails if: ship.sh arms a pull request of a repository other than SFenton/native-home."""
        done, log, arm = self.run_ship(repo="SFenton/Fenton-HASS-Native")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(arm, "")
        self.assertNotIn("pr merge", log)


class ShipPushThenReviewTests(unittest.TestCase):
    """Push, then review (owner, 2026-11-10): a native-home origin is pushed without a reviewer pass; the hook install and a readable origin are still required."""

    def ship_with_origin(self, url, passed, hooks=True):
        """Run ship.sh with ``origin`` set to ``url``; returns the result. ``self.pushed`` says whether ``claude/x`` reached the local bare origin.
        An ssh-form url is served by a fake ``GIT_SSH_COMMAND`` that runs ``git receive-pack`` on the local bare repository, so nothing touches the network."""
        with TemporaryDirectory() as tmp:
            clone, origin = make_repo(tmp)
            fake_ssh = Path(tmp) / "fake_ssh.sh"
            fake_ssh.write_text('#!/bin/sh\nexec git receive-pack "%s"\n' % origin)
            fake_ssh.chmod(0o755)
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
                git(clone, "config", "core.hooksPath", ".githooks" if hooks is True else str(clone / ".githooks"))
            git(clone, "remote", "set-url", "origin", url)
            done = subprocess.run(["bash", "tools/ship.sh", "Add a"], cwd=clone, capture_output=True, text=True,
                                  env={**ENV, "HOME": str(home), "GIT_SSH_COMMAND": str(fake_ssh)})
            self.pushed = subprocess.run(["git", "rev-parse", "--verify", "-q", "refs/heads/claude/x"], cwd=origin, env=ENV).returncode == 0
            return done

    def test_native_home_without_a_pass_is_pushed(self):
        """Fails if: ship.sh asks for the reviewer's pass before the push again (the 2026-11-09 review-before-push rule)."""
        done = self.ship_with_origin("git@github.com:SFenton/native-home.git", passed=False)
        self.assertNotIn("needs the reviewer's pass", done.stderr)
        self.assertNotIn("review before push", done.stderr)
        self.assertNotIn("tools/setup.sh", done.stderr)
        self.assertNotIn("not a readable GitHub URL", done.stderr)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(self.pushed, "the branch must reach the (local, fake-ssh) origin without a pass")

    def test_native_home_without_the_git_hook_installed_is_refused(self):
        done = self.ship_with_origin("git@github.com:SFenton/native-home.git", passed=True, hooks=False)
        self.assertEqual(done.returncode, 1)
        self.assertIn("tools/setup.sh", done.stderr)
        self.assertNotIn("pushed", done.stdout)
        self.assertFalse(self.pushed)

    def test_an_absolute_hooks_path_to_the_repos_githooks_is_accepted(self):
        """Fails if: ship.sh refuses core.hooksPath given as the absolute path of the repo's own .githooks (the flip that stopped lane D)."""
        done = self.ship_with_origin("git@github.com:SFenton/native-home.git", passed=False, hooks="absolute")
        self.assertNotIn("tools/setup.sh", done.stderr)
        self.assertNotIn("needs the reviewer's pass", done.stderr)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(self.pushed)

    def test_an_unreadable_origin_fails_closed(self):
        done = self.ship_with_origin("nonsense", passed=True)
        self.assertEqual(done.returncode, 1)
        self.assertIn("not a readable GitHub URL", done.stderr)
        self.assertFalse(self.pushed)


RECORD_STUB = """import os, sys
open(os.environ["RECORD_LOG"], "a").write(" ".join(sys.argv[1:]) + "\\n")
"""
GIT_WRAPPER = """#!/bin/sh
echo "$@" >> "$GIT_LOG"
exec "$REAL_GIT" "$@"
"""
JEV_STUB = "import sys\nsys.exit(%d)\n"


class ShipUpdateTests(unittest.TestCase):
    """``--update``: an amended lane branch is force-pushed with a lease on the sha it fetched, then the check and the arm run again."""

    def setup_lane(self, tmp, branch="agents/x", jev=None, pushed=True):
        clone, origin = make_repo(tmp)
        home = Path(tmp) / "home"
        home.mkdir()
        use_home(clone, home)
        verdict = clone / "tools" / "review_verdict.py"
        # classify the throwaway origin as native-home so the post-push steps run
        verdict.write_text(verdict.read_text().replace(
            "def remote_kind(url: str) -> str:", "def remote_kind(url: str) -> str:\n    return 'native-home'\n\n\ndef _kind(url: str) -> str:", 1))
        (clone / "tools" / "review").mkdir()
        (clone / "tools" / "review" / "record.py").write_text(RECORD_STUB)
        (clone / "tools" / "pr_land.py").write_text(ARM_STUB)
        if jev is not None:
            (clone / "tools" / "jev_ask.py").write_text(JEV_STUB % jev)
        git(clone, "config", "core.hooksPath", ".githooks")
        git(clone, "switch", "-q", "-c", branch)
        (clone / "a.txt").write_text("x")
        git(clone, "add", "-A")
        git(clone, "commit", "-q", "-m", "Add a")
        if pushed:
            git(clone, "push", "-q", "-u", "origin", branch)
        fake = Path(tmp) / "bin"
        fake.mkdir()
        (fake / "gh").write_text(GH_STUB)
        (fake / "gh").chmod(0o755)
        (fake / "git").write_text(GIT_WRAPPER)
        (fake / "git").chmod(0o755)
        env = {**ENV, "PATH": f"{fake}{os.pathsep}{ENV['PATH']}", "HOME": str(home), "GH_LOG": str(Path(tmp) / "gh.log"),
               "GH_REPO_NAME": "SFenton/native-home", "PRLAND_LOG": str(Path(tmp) / "arm.log"), "RECORD_LOG": str(Path(tmp) / "record.log"),
               "GIT_LOG": str(Path(tmp) / "git.log"), "REAL_GIT": shutil.which("git")}
        return clone, origin, home, env

    def amend(self, clone, home, reviewed=True):
        (clone / "a.txt").write_text("y")
        git(clone, "add", "-A")
        git(clone, "commit", "-q", "--amend", "-m", "Add a again")
        head = git(clone, "rev-parse", "HEAD")
        if reviewed:
            record_pass(home, head)
        return head

    def ship(self, clone, env, *args):
        return subprocess.run(["bash", "tools/ship.sh", "Add a", *args], cwd=clone, env=env, capture_output=True, text=True)

    def test_an_amended_branch_is_pushed_with_a_lease_and_the_check_and_arm_rerun(self):
        """Fails if: --update pushes without a lease pinned to the fetched origin sha, leaves origin on the old head, skips the ai-review post
        for the new head, or does not re-arm the PR."""
        with TemporaryDirectory() as tmp:
            clone, origin, home, env = self.setup_lane(tmp)
            old = git(clone, "rev-parse", "HEAD")
            head = self.amend(clone, home)
            done = self.ship(clone, env, "--update")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(git(origin, "rev-parse", "agents/x"), head)
            pushes = [l for l in Path(env["GIT_LOG"]).read_text().splitlines() if l.startswith("push")]
            self.assertTrue(any(f"--force-with-lease=refs/heads/agents/x:{old}" in l for l in pushes), pushes)
            self.assertNotIn("--force ", " ".join(pushes))
            self.assertEqual(Path(env["RECORD_LOG"]).read_text().strip(), f"--post-check {head} --repo SFenton/native-home")
            self.assertEqual(Path(env["PRLAND_LOG"]).read_text().strip(), "7")
            self.assertNotIn("pr create", Path(env["GH_LOG"]).read_text())

    def test_a_plain_ship_of_the_amended_branch_cannot_overwrite_it(self):
        """Fails if: a plain ship of an amended branch force-pushes (--update must be the only route)."""
        with TemporaryDirectory() as tmp:
            clone, origin, home, env = self.setup_lane(tmp)
            old = git(origin, "rev-parse", "agents/x")
            self.amend(clone, home)
            done = self.ship(clone, env)
            self.assertNotEqual(done.returncode, 0)
            self.assertEqual(git(origin, "rev-parse", "agents/x"), old)

    def test_only_agents_and_port_branches_may_be_force_pushed(self):
        """Fails if: --update force-pushes a claude/*, feature or lookalike branch, or commits before refusing."""
        for branch in ("claude/x", "feature/y", "agentsx"):
            with self.subTest(branch=branch), TemporaryDirectory() as tmp:
                clone, origin, home, env = self.setup_lane(tmp, branch=branch)
                head = self.amend(clone, home)
                (clone / "dirty.txt").write_text("d")
                done = self.ship(clone, env, "--update")
                self.assertEqual(done.returncode, 1)
                self.assertIn("agents/* or port/*", done.stderr)
                self.assertNotEqual(git(origin, "rev-parse", branch), head)
                self.assertEqual(git(clone, "rev-parse", "HEAD"), head)
        with TemporaryDirectory() as tmp:
            clone, origin, home, env = self.setup_lane(tmp, branch="port/z")
            head = self.amend(clone, home)
            self.assertEqual(self.ship(clone, env, "--update").returncode, 0)
            self.assertEqual(git(origin, "rev-parse", "port/z"), head)

    def test_a_commit_someone_else_pushed_first_is_never_overwritten(self):
        """Fails if: --update leases on whatever origin has (a fresh fetch) and overwrites a commit this checkout never had."""
        with TemporaryDirectory() as tmp:
            clone, origin, home, env = self.setup_lane(tmp)
            other = Path(tmp) / "other"
            git(tmp, "clone", "-q", str(origin), str(other))
            git(other, "switch", "-q", "agents/x")
            (other / "theirs.txt").write_text("t")
            git(other, "add", "-A")
            git(other, "commit", "-q", "-m", "Theirs")
            git(other, "push", "-q", "origin", "agents/x")
            theirs = git(origin, "rev-parse", "agents/x")
            self.amend(clone, home)
            done = self.ship(clone, env, "--update")
            self.assertEqual(done.returncode, 1)
            self.assertIn("someone else pushed it", done.stderr)
            self.assertEqual(git(origin, "rev-parse", "agents/x"), theirs)
            self.assertFalse(Path(env["RECORD_LOG"]).exists())

    def test_a_remote_commit_already_in_head_is_a_valid_lease(self):
        """Fails if: --update refuses a lane whose origin sha is an ancestor of HEAD (a fast-forward-able branch)."""
        with TemporaryDirectory() as tmp:
            clone, origin, home, env = self.setup_lane(tmp)
            (clone / "b.txt").write_text("b")
            git(clone, "add", "-A")
            git(clone, "commit", "-q", "-m", "More")
            record_pass(home, git(clone, "rev-parse", "HEAD"))
            self.assertEqual(self.ship(clone, env, "--update").returncode, 0)
            self.assertEqual(git(origin, "rev-parse", "agents/x"), git(clone, "rev-parse", "HEAD"))

    def test_an_unreadable_origin_gets_its_own_message(self):
        """Fails if: a failed ls-remote is reported as 'no branch on origin' (which tells the agent to ship plainly)."""
        with TemporaryDirectory() as tmp:
            clone, origin, home, env = self.setup_lane(tmp)
            self.amend(clone, home)
            git(clone, "remote", "set-url", "origin", str(Path(tmp) / "gone.git"))
            done = self.ship(clone, env, "--update")
            self.assertEqual(done.returncode, 1)
            self.assertIn("could not read origin", done.stderr)
            self.assertNotIn("ship it plainly", done.stderr)

    def test_a_branch_not_on_origin_has_nothing_to_update(self):
        """Fails if: --update creates a branch on origin or force-pushes when the lease has nothing to pin."""
        with TemporaryDirectory() as tmp:
            clone, origin, home, env = self.setup_lane(tmp, pushed=False)
            record_pass(home, git(clone, "rev-parse", "HEAD"))
            done = self.ship(clone, env, "--update")
            self.assertEqual(done.returncode, 1)
            self.assertIn("ship it plainly first", done.stderr)
            self.assertEqual(subprocess.run(["git", "rev-parse", "--verify", "-q", "agents/x"], cwd=origin, env=ENV).returncode, 1)

    def test_an_amended_head_without_its_own_pass_is_pushed_for_review(self):
        """Fails if: --update refuses an amended head for lacking a pass (push, then review, owner 2026-11-10), or tries to post ai-review for a head with no pass."""
        with TemporaryDirectory() as tmp:
            clone, origin, home, env = self.setup_lane(tmp)
            self.amend(clone, home, reviewed=False)
            done = self.ship(clone, env, "--update")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(git(origin, "rev-parse", "agents/x"), git(clone, "rev-parse", "HEAD"))
            self.assertFalse(Path(env["RECORD_LOG"]).exists(), "no pass yet: ship must not try to post ai-review")

    def test_a_stale_jev_question_list_blocks_every_push_with_the_sync_command(self):
        """Fails if: ship.sh pushes while `jev_ask.py sync --check` fails (CI would go red), or the message omits the sync command."""
        with TemporaryDirectory() as tmp:
            clone, origin, home, env = self.setup_lane(tmp, jev=1)
            self.amend(clone, home)
            old = git(origin, "rev-parse", "agents/x")
            for args in ((), ("--update",)):
                done = self.ship(clone, env, *args)
                self.assertEqual(done.returncode, 1)
                self.assertIn("python3 tools/jev_ask.py sync", done.stderr)
                self.assertIn("failed or is stale", done.stderr)
                self.assertEqual(git(origin, "rev-parse", "agents/x"), old)
            (clone / "tools" / "jev_ask.py").write_text(JEV_STUB % 0)
            git(clone, "add", "-A")
            git(clone, "commit", "-q", "--amend", "--no-edit")
            record_pass(home, git(clone, "rev-parse", "HEAD"))
            self.assertEqual(self.ship(clone, env, "--update").returncode, 0)

    def test_no_push_runs_no_jev_check(self):
        """Fails if: a --no-push commit is blocked by the Jev check (it guards the push, not the commit)."""
        with TemporaryDirectory() as tmp:
            clone, _, _, env = self.setup_lane(tmp, jev=1)
            (clone / "b.txt").write_text("b")
            done = self.ship(clone, env, "--no-push")
            self.assertEqual(done.returncode, 0, done.stderr)


if __name__ == "__main__":
    unittest.main()
