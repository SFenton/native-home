"""Lane and ship scripts (``tools/lane_new.sh``, ``tools/ship.sh``) against throwaway repositories."""

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
    for name in ("lane_new.sh", "ship.sh", "ship_guard.sh"):
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
  "api repos/SFenton/native-home/rules/branches/main") cat "$GH_RULES" ;;
  "api repos/SFenton/native-home/rulesets/7") echo '{"current_user_can_bypass": "never"}' ;;
  "pr ready") exit 0 ;;
  "pr merge") exit "${GH_MERGE_RC:-0}" ;;
esac
exit 0
"""
BOTH = ('[{"type": "pull_request", "ruleset_id": 7, "parameters": {"required_approving_review_count": 1, "dismiss_stale_reviews_on_push": true, "require_last_push_approval": true}}, '
        '{"type": "required_status_checks", "ruleset_id": 7, "parameters": {"required_status_checks": [{"context": "pr-checks", "integration_id": 15368}]}}]')


class ShipArmTests(unittest.TestCase):
    """After the PR opens on native-home, ship.sh arms auto-merge only while the live ruleset requires an approval and pr-checks."""

    def run_ship(self, rules, repo="SFenton/native-home", merge_rc="0"):
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            shutil.copy(TOOLS / "ruleset_gate.py", clone / "tools" / "ruleset_gate.py")
            git(clone, "switch", "-q", "-c", "claude/x")
            (clone / "a.txt").write_text("x")
            fake = Path(tmp) / "bin"
            fake.mkdir()
            (fake / "gh").write_text(GH_STUB)
            (fake / "gh").chmod(0o755)
            rules_file = Path(tmp) / "rules.json"
            rules_file.write_text(rules)
            log = Path(tmp) / "gh.log"
            env = {**ENV, "PATH": f"{fake}{os.pathsep}{ENV['PATH']}", "GH_LOG": str(log), "GH_RULES": str(rules_file),
                   "GH_REPO_NAME": repo, "GH_MERGE_RC": merge_rc}
            done = subprocess.run(["bash", "tools/ship.sh", "Add a", "--pr"], cwd=clone, env=env, capture_output=True, text=True)
            return done, log.read_text()

    def test_both_rules_live_marks_ready_and_arms_auto_merge(self):
        done, log = self.run_ship(BOTH)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("pr ready 7 -R SFenton/native-home", log)
        self.assertIn("pr merge 7 -R SFenton/native-home --auto --squash", log)
        self.assertIn("auto-merge armed on #7", done.stdout)

    def test_a_ruleset_without_an_approval_or_without_pr_checks_arms_nothing(self):
        no_approval = BOTH.replace('"required_approving_review_count": 1', '"required_approving_review_count": 0')
        no_check = BOTH.replace('"pr-checks"', '"other"')
        for rules in (no_approval, no_check, "[]", "not json"):
            with self.subTest(rules=rules[:30]):
                done, log = self.run_ship(rules)
                self.assertEqual(done.returncode, 0, done.stderr)
                self.assertNotIn("pr merge", log)
                self.assertNotIn("pr ready", log)
                self.assertIn("auto-merge not armed", done.stderr)

    def test_another_repository_arms_nothing_and_does_not_even_read_the_ruleset(self):
        done, log = self.run_ship(BOTH, repo="SFenton/Fenton-HASS-Native")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("pr merge", log)
        self.assertNotIn("rules/branches", log)

    def test_a_failed_arm_is_a_notice_not_a_failed_ship(self):
        done, _ = self.run_ship(BOTH, merge_rc="1")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("could not arm auto-merge", done.stderr)


if __name__ == "__main__":
    unittest.main()
