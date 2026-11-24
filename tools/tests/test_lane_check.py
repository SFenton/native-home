"""``tools/lane_check.py``: overlap at lane start, the revert guard, the hooks path and the denylist scan, against throwaway repositories.

Each shape comes from the T-gh-native-gate post-mortem (Action 1): a lane started over an open PR (#18), a soft-reset squash over a
base another session's fetch had moved (#25), ``core.hooksPath`` as an absolute path, and ``house_scan`` found late.
"""

import contextlib
import importlib.util
import io
import json
import os
import stat
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
LANE_CHECK = TOOLS / "lane_check.py"
ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
       "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
HOOK = "#!/bin/sh\nexit 0\n"


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=ENV, capture_output=True, text=True, check=True).stdout.strip()


def commit(repo, name, text, message):
    """Write ``name`` in ``repo`` and commit it."""
    path = Path(repo) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", message)


def make_repo(tmp):
    """A clone of a bare origin with a.txt, b.txt and .githooks/pre-push on main, plus a second clone for 'another session'."""
    origin = Path(tmp) / "origin.git"
    git(tmp, "init", "-q", "--bare", "-b", "main", str(origin))
    clone = Path(tmp) / "clone"
    git(tmp, "clone", "-q", str(origin), str(clone))
    (clone / ".githooks").mkdir()
    (clone / ".githooks" / "pre-push").write_text(HOOK)
    (clone / ".githooks" / "pre-push").chmod(stat.S_IRWXU)
    commit(clone, "a.txt", "a\n", "init")
    commit(clone, "b.txt", "b\n", "add b")
    git(clone, "push", "-q", "-u", "origin", "main")
    other = Path(tmp) / "other"
    git(tmp, "clone", "-q", str(origin), str(other))
    return clone, other


def other_checkout_hooks(tmp, clone):
    """The ``.githooks`` of a second clone of the same origin (another checkout), with a pre-push identical to the lane's."""
    second = Path(tmp) / "second"
    git(tmp, "clone", "-q", str(Path(tmp) / "origin.git"), str(second))
    return second / ".githooks"


def fake_gh(tmp, prs):
    """A ``gh`` on PATH that answers ``pr list`` with ``prs``; returns the env to run lane_check under."""
    bin_dir = Path(tmp) / "bin"
    bin_dir.mkdir(exist_ok=True)
    gh = bin_dir / "gh"
    gh.write_text("#!/bin/sh\ncat <<'EOF'\n" + json.dumps(prs) + "\nEOF\n")
    gh.chmod(stat.S_IRWXU)
    return {**ENV, "PATH": f"{bin_dir}{os.pathsep}{ENV['PATH']}"}


def lane(cwd, *args, env=None):
    return subprocess.run([sys.executable, str(LANE_CHECK), *args], cwd=cwd, env=env or ENV, capture_output=True, text=True)


def start(clone, env, *paths, ack=None):
    extra = ["--ack-overlap", ack] if ack else []
    return lane(clone, "start", "--task", "T-x", "--branch", "agents/x", "--paths", *paths, *extra, env=env)


class OverlapTests(unittest.TestCase):
    def test_open_pr_touching_a_declared_path_stops_the_start(self):
        """Fails if: `start` lets a lane begin while another open PR touches one of its paths (the #18 shape), or names the wrong PR."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/x")
            env = fake_gh(tmp, [{"number": 18, "headRefName": "agents/other", "files": [{"path": "tools/ship.sh"}]}])
            done = start(clone, env, "tools/ship.sh")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("open PR #18", done.stdout)

    def test_a_directory_prefix_and_a_glob_match_but_other_paths_and_the_own_branch_do_not(self):
        """Fails if: matching ignores directory prefixes and globs, or flags a PR on unrelated files or on the lane's own branch."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/x")
            prs = [{"number": 3, "headRefName": "agents/o", "files": [{"path": "tools/tests/test_a.py"}]}]
            self.assertEqual(start(clone, fake_gh(tmp, prs), "tools/tests/").returncode, 1)
            self.assertEqual(start(clone, fake_gh(tmp, prs), "tools/tests/test_*.py").returncode, 1)
            self.assertEqual(start(clone, fake_gh(tmp, prs), "docs/").returncode, 0)
            own = [{"number": 4, "headRefName": "agents/x", "files": [{"path": "docs/a.md"}]}]
            self.assertEqual(start(clone, fake_gh(tmp, own), "docs/").returncode, 0)

    def test_ack_overlap_lets_the_start_through_and_records_the_reason(self):
        """Fails if: `--ack-overlap` still exits 1, or the reason is not printed and recorded in the lane-base file."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/x")
            env = fake_gh(tmp, [{"number": 18, "headRefName": "o", "files": [{"path": "a.txt"}]}])
            done = start(clone, env, "a.txt", ack="disjoint hunks")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("disjoint hunks", done.stdout)
            record = json.loads((Path(git(clone, "rev-parse", "--absolute-git-dir")) / "lane-base").read_text())
            self.assertEqual(record["ack_overlap"], "disjoint hunks")

    def test_a_commit_merged_on_origin_main_since_the_previous_lane_stops_the_start(self):
        """Fails if: a commit that landed on origin/main after the previous lane's base and touches a declared path is not reported."""
        with TemporaryDirectory() as tmp:
            clone, other = make_repo(tmp)
            env = fake_gh(tmp, [])
            git(clone, "switch", "-q", "-c", "agents/first")
            first = lane(clone, "start", "--task", "T-1", "--branch", "agents/first", "--paths", "docs/", env=env)
            self.assertEqual(first.returncode, 0, first.stderr)
            commit(other, "docs/x.md", "x\n", "Docs change")
            git(other, "push", "-q", "origin", "main")
            git(clone, "switch", "-q", "-c", "agents/x")
            done = start(clone, env, "docs/")
            self.assertEqual(done.returncode, 1, done.stdout)
            self.assertIn("Docs change", done.stdout)
            self.assertEqual(start(clone, env, "tools/").returncode, 0)

    def test_start_records_the_base_in_the_worktree_local_file(self):
        """Fails if: the base is not the fetched origin/main sha, or is written somewhere another worktree's fetch could move."""
        with TemporaryDirectory() as tmp:
            clone, other = make_repo(tmp)
            commit(other, "c.txt", "c\n", "moved")
            git(other, "push", "-q", "origin", "main")
            git(clone, "switch", "-q", "-c", "agents/x")
            done = start(clone, fake_gh(tmp, []), "zzz/")
            self.assertEqual(done.returncode, 0, done.stderr)
            record = json.loads((Path(git(clone, "rev-parse", "--absolute-git-dir")) / "lane-base").read_text())
            self.assertEqual(record["base"], git(other, "rev-parse", "HEAD"))
            self.assertEqual(record["task"], "T-x")


class LedgerTests(unittest.TestCase):
    def test_start_adds_the_branch_to_the_task_ledger_entry(self):
        """Fails if: `start` does not record the lane branch in the task's ledger entry (so the retro digest cannot read its review records),
        records it twice on a rerun, or fails the start when the entry does not exist."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/x")
            tasks = Path(tmp) / "tasks"
            tasks.mkdir()
            (tasks / "T-x.json").write_text(json.dumps({"id": "T-x", "rounds": {"design": 0, "review": 0}}))
            env = {**fake_gh(tmp, []), "TASKS_DIR": str(tasks)}
            for _ in range(2):
                self.assertEqual(start(clone, env, "zzz/").returncode, 0)
            self.assertEqual(json.loads((tasks / "T-x.json").read_text())["branches"], ["agents/x"])
            env["TASKS_DIR"] = str(Path(tmp) / "none")
            done = start(clone, env, "zzz/")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("not added to the ledger", done.stderr)


class RevertGuardTests(unittest.TestCase):
    def moved_base_lane(self, tmp):
        """A started lane with one commit, and origin/main moved by another session (a.txt changed) and fetched."""
        clone, other = make_repo(tmp)
        git(clone, "switch", "-q", "-c", "agents/x")
        self.assertEqual(start(clone, fake_gh(tmp, []), "zzz/").returncode, 0)
        commit(clone, "b.txt", "lane\n", "Lane change")
        commit(other, "a.txt", "merged elsewhere\n", "Other session")
        git(other, "push", "-q", "origin", "main")
        git(clone, "fetch", "-q", "origin")
        return clone

    def test_a_soft_reset_over_a_moved_base_that_puts_back_a_merged_file_fails(self):
        """Fails if: `check` accepts a commit built by `git reset --soft origin/main` from an old tree (the #25 shape) or does not name the reverted file."""
        with TemporaryDirectory() as tmp:
            clone = self.moved_base_lane(tmp)
            git(clone, "reset", "-q", "--soft", "origin/main")
            git(clone, "commit", "-q", "-m", "Squash")
            done = lane(clone, "check", "--only", "revert")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("a.txt", done.stderr)
            self.assertIn("reverts origin/main since base", done.stderr)

    def test_squash_onto_the_lane_base_is_safe_and_passes(self):
        """Fails if: `squash` resets onto the moved origin/main instead of the recorded base, or `check` rejects the safe squash."""
        with TemporaryDirectory() as tmp:
            clone = self.moved_base_lane(tmp)
            base = json.loads((Path(git(clone, "rev-parse", "--absolute-git-dir")) / "lane-base").read_text())["base"]
            self.assertEqual(lane(clone, "squash").returncode, 0)
            self.assertEqual(git(clone, "rev-parse", "HEAD"), base)
            git(clone, "commit", "-q", "-m", "Squash")
            done = lane(clone, "check", "--only", "revert")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(git(clone, "show", "HEAD:a.txt"), "a")

    def test_a_revert_in_an_earlier_commit_is_found_even_when_the_last_commit_is_innocent(self):
        """Fails if: the revert guard looks only at the last commit, so a bad squash followed by another commit passes."""
        with TemporaryDirectory() as tmp:
            clone = self.moved_base_lane(tmp)
            git(clone, "reset", "-q", "--soft", "origin/main")
            git(clone, "commit", "-q", "-m", "Squash")
            commit(clone, "c.txt", "later\n", "Later")
            done = lane(clone, "check", "--only", "revert")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("a.txt", done.stderr)

    def test_after_a_rebase_squash_still_targets_the_recorded_base(self):
        """Fails if: `squash` errors after a plain rebase onto origin/main, or resets onto anything but the recorded base."""
        with TemporaryDirectory() as tmp:
            clone = self.moved_base_lane(tmp)
            base = json.loads((Path(git(clone, "rev-parse", "--absolute-git-dir")) / "lane-base").read_text())["base"]
            git(clone, "rebase", "-q", "origin/main")
            self.assertEqual(lane(clone, "check", "--only", "revert").returncode, 0)
            self.assertEqual(lane(clone, "squash").returncode, 0)
            self.assertEqual(git(clone, "rev-parse", "HEAD"), base)
            git(clone, "commit", "-q", "-m", "Squash")
            self.assertEqual(git(clone, "show", "HEAD:a.txt"), "merged elsewhere")
            self.assertEqual(lane(clone, "check", "--only", "revert").returncode, 0)

    def test_a_recorded_base_gone_from_history_falls_back_to_the_fork_point_and_is_re_recorded(self):
        """Fails if: `squash` errors or guesses when the recorded base is not in HEAD's history, or leaves the stale base recorded."""
        with TemporaryDirectory() as tmp:
            clone = self.moved_base_lane(tmp)
            fork = git(clone, "merge-base", "HEAD", "origin/main")
            path = Path(git(clone, "rev-parse", "--absolute-git-dir")) / "lane-base"
            record = json.loads(path.read_text())
            git(clone, "switch", "-q", "--detach", fork)
            commit(clone, "side.txt", "s\n", "side")
            record["base"] = git(clone, "rev-parse", "HEAD")
            git(clone, "switch", "-q", "agents/x")
            path.write_text(json.dumps(record) + "\n")
            done = lane(clone, "squash")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("history was rewritten", done.stdout)
            self.assertEqual(git(clone, "rev-parse", "HEAD"), fork)
            self.assertEqual(json.loads(path.read_text())["base"], fork)

    def test_a_lane_that_reverts_its_own_change_is_not_flagged(self):
        """Fails if: a lane's own revert commit (file equal to the base again) is reported as reverting origin/main."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/x")
            self.assertEqual(start(clone, fake_gh(tmp, []), "zzz/").returncode, 0)
            commit(clone, "b.txt", "lane\n", "change")
            commit(clone, "b.txt", "b\n", "put it back")
            self.assertEqual(lane(clone, "check", "--only", "revert").returncode, 0)

    def test_without_a_recorded_base_the_revert_check_is_skipped_and_squash_refuses(self):
        """Fails if: `check` fails a lane that never ran `start`, or `squash` guesses a base."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/x")
            self.assertEqual(lane(clone, "check", "--only", "revert").returncode, 0)
            done = lane(clone, "squash")
            self.assertEqual(done.returncode, 2)
            self.assertIn("lane_check.py start", done.stderr)

    def test_the_shape_note_prints_the_safe_squash_for_several_commits(self):
        """Fails if: a lane of two commits gets no advice to squash onto the lane base."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/x")
            self.assertEqual(start(clone, fake_gh(tmp, []), "zzz/").returncode, 0)
            commit(clone, "b.txt", "1\n", "one")
            commit(clone, "b.txt", "2\n", "two")
            done = lane(clone, "check", "--only", "shape")
            self.assertEqual(done.returncode, 0)
            self.assertIn("lane_check.py squash", done.stderr)


class HooksPathTests(unittest.TestCase):
    def hooks(self, clone):
        """The check with no ``setup.sh`` beside the script, so it can only refuse (the repair is tested in HooksRepairTests)."""
        bare = Path(clone).parent / "norepair"
        bare.mkdir(exist_ok=True)
        (bare / "lane_check.py").write_text(LANE_CHECK.read_text())
        return subprocess.run([sys.executable, str(bare / "lane_check.py"), "check", "--only", "hooks"], cwd=clone, env=ENV,
                              capture_output=True, text=True)

    def test_relative_and_absolute_forms_of_the_repos_own_githooks_pass(self):
        """Fails if: either `.githooks` or the absolute path to this worktree's own .githooks is refused."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "config", "core.hooksPath", ".githooks")
            self.assertEqual(self.hooks(clone).returncode, 0)
            git(clone, "config", "core.hooksPath", str(clone / ".githooks"))
            self.assertEqual(self.hooks(clone).returncode, 0)

    def test_another_checkouts_githooks_is_refused_even_with_an_identical_pre_push(self):
        """Fails if: an absolute core.hooksPath to another checkout's .githooks is accepted because its pre-push matches HEAD's
        (that hook runs the other checkout's unchecked tools/ scripts), or the refusal does not say to run tools/setup.sh."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            elsewhere = Path(tmp) / "elsewhere"
            elsewhere.mkdir()
            (elsewhere / "pre-push").write_text("#!/bin/sh\nexit 1\n")
            git(clone, "config", "core.hooksPath", str(elsewhere))
            done = self.hooks(clone)
            self.assertEqual(done.returncode, 1)
            self.assertIn("tools/setup.sh", done.stderr)
            (elsewhere / "pre-push").write_text(HOOK)
            self.assertEqual(self.hooks(clone).returncode, 1)
            self.assertIn("tools/setup.sh", self.hooks(clone).stderr)
            git(clone, "config", "core.hooksPath", str(other_checkout_hooks(tmp, clone)))
            self.assertEqual(self.hooks(clone).returncode, 1)

    def test_an_unset_hooks_path_fails(self):
        """Fails if: a repository with no core.hooksPath passes (the new-worktree-has-no-hooks case)."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            self.assertEqual(self.hooks(clone).returncode, 1)


class HooksRepairTests(unittest.TestCase):
    """A foreign, absolute or missing hooks path is repaired once by ``tools/setup.sh``; the rewrite is announced and logged."""

    def flips(self, clone):
        log = Path(git(clone, "rev-parse", "--path-format=absolute", "--git-common-dir")) / "hooks-path-flips"
        return log.read_text().splitlines() if log.is_file() else []

    def test_a_path_into_another_checkout_is_rewritten_announced_and_logged(self):
        """Fails if: a foreign absolute hooks path is not rewritten to .githooks, the one-line notice is missing, or the old value
        and time are not appended to hooks-path-flips."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            foreign = str(other_checkout_hooks(tmp, clone))
            git(clone, "config", "core.hooksPath", foreign)
            done = lane(clone, "check", "--only", "hooks")
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertEqual(git(clone, "config", "core.hooksPath"), ".githooks")
            self.assertIn(f"rewritten from {foreign} to .githooks", done.stdout)
            rows = self.flips(clone)
            self.assertEqual(len(rows), 1, rows)
            when, old, where = rows[0].split("\t")
            self.assertEqual((old, where), (foreign, str(clone.resolve())))
            self.assertRegex(when, r"^\d{4}-\d\d-\d\dT")

    def test_an_absolute_path_to_a_missing_folder_is_rewritten(self):
        """Fails if: an absolute path that leads nowhere is left for the owner to fix by hand."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "config", "core.hooksPath", "/nonexistent/other-checkout/.githooks")
            self.assertEqual(lane(clone, "check", "--only", "hooks").returncode, 0)
            self.assertEqual(git(clone, "config", "core.hooksPath"), ".githooks")

    def with_setup(self, clone, script):
        """A copy of lane_check with a stub ``setup.sh`` beside it; returns the check's result."""
        folder = Path(clone).parent / "stubbed"
        folder.mkdir(exist_ok=True)
        (folder / "lane_check.py").write_text(LANE_CHECK.read_text())
        (folder / "setup.sh").write_text(script)
        return subprocess.run([sys.executable, str(folder / "lane_check.py"), "check", "--only", "hooks"], cwd=clone, env=ENV,
                              capture_output=True, text=True)

    def test_a_repair_that_does_not_take_still_refuses_and_says_it_ran(self):
        """Fails if: a setup.sh that exits 0 without fixing the path lets the check pass, logs a flip or prints the rewrite line, or the
        refusal still tells the agent to run tools/setup.sh (it just ran)."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            foreign = "/elsewhere/.githooks"
            git(clone, "config", "core.hooksPath", foreign)
            done = self.with_setup(clone, "#!/bin/sh\nexit 0\n")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertEqual(git(clone, "config", "core.hooksPath"), foreign)
            self.assertNotIn("rewritten", done.stdout + done.stderr)
            self.assertEqual(self.flips(clone), [])
            self.assertIn("tools/setup.sh ran", done.stderr)
            self.assertNotIn("Run tools/setup.sh", done.stderr)
            # push_guard refuses any command naming the key, so advice containing it would send an agent in a loop.
            self.assertNotIn("hooksPath", done.stderr)
            self.assertNotIn("--show-origin", done.stderr)
            self.assertIn("blocked", done.stderr)

    def test_a_busy_config_lock_is_named_in_the_refusal(self):
        """Fails if: a setup.sh that hit git's config lock is reported as an override instead of a busy lock, or passes."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "config", "core.hooksPath", "/elsewhere/.githooks")
            done = self.with_setup(clone, "#!/bin/sh\necho 'error: could not lock config file .git/config: File exists' >&2\nexit 255\n")
            self.assertEqual(done.returncode, 1)
            self.assertIn("config lock was busy", done.stderr)
            self.assertEqual(self.flips(clone), [])

    def test_a_higher_precedence_override_still_refuses_with_the_real_setup(self):
        """Fails if: the check passes, or logs a flip, while an environment-level setting keeps the wrong path in force."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            env = {**ENV, "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.hooksPath", "GIT_CONFIG_VALUE_0": "/elsewhere/.githooks"}
            done = lane(clone, "check", "--only", "hooks", env=env)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("higher-precedence", done.stderr)
            self.assertEqual(self.flips(clone), [])

    def test_an_unset_path_is_repaired_and_logged_as_unset(self):
        """Fails if: the unset case is not repaired by setup.sh, or the flip row does not record the old value as (unset)."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            done = lane(clone, "check", "--only", "hooks")
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertEqual(git(clone, "config", "core.hooksPath"), ".githooks")
            self.assertIn("rewritten from (unset) to .githooks", done.stdout)
            self.assertEqual(self.flips(clone)[0].split("\t")[1], "(unset)")

    def test_a_correct_path_runs_nothing_and_logs_nothing(self):
        """Fails if: a good absolute path is rewritten or logged (setup.sh must run only after a failed check)."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            absolute = str(clone / ".githooks")
            git(clone, "config", "core.hooksPath", absolute)
            done = lane(clone, "check", "--only", "hooks")
            self.assertEqual(done.returncode, 0)
            self.assertNotIn("rewritten", done.stdout)
            self.assertEqual(git(clone, "config", "core.hooksPath"), absolute)
            self.assertEqual(self.flips(clone), [])


class HooksNoRepairTests(unittest.TestCase):
    """The --no-repair hooks diagnostic never runs setup or writes the shared Git directory."""

    def run_stubbed(self, clone, *args, script="#!/bin/sh\nexit 0\n", marker=None):
        folder = Path(clone).parent / "no-repair-tool"
        folder.mkdir(exist_ok=True)
        (folder / "lane_check.py").write_text(LANE_CHECK.read_text())
        (folder / "setup.sh").write_text(script)
        env = ENV if marker is None else {**ENV, "NO_REPAIR_MARKER": str(marker)}
        return subprocess.run([sys.executable, str(folder / "lane_check.py"), *args], cwd=clone, env=env,
                              capture_output=True, text=True)

    def common_dir_snapshot(self, clone):
        common = Path(git(clone, "rev-parse", "--path-format=absolute", "--git-common-dir"))
        return sorted((str(path.relative_to(common)), path.is_file(), path.stat().st_size if path.is_file() else None)
                      for path in common.rglob("*"))

    def test_wrong_setup_fails_without_repair_or_common_dir_write(self):
        """Fails if: no-repair invokes setup, rewrites config, logs a flip, or modifies the common Git directory."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            foreign = "/elsewhere/.githooks"
            git(clone, "config", "core.hooksPath", foreign)
            marker = Path(tmp) / "setup-ran"
            before = self.common_dir_snapshot(clone)
            done = self.run_stubbed(
                clone, "check", "--only", "hooks", "--no-repair",
                script="#!/bin/sh\nprintf ran > \"$NO_REPAIR_MARKER\"\nexit 0\n", marker=marker)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("Stop and report", done.stderr)
            self.assertNotIn("Run tools/setup.sh", done.stderr)
            self.assertEqual(git(clone, "config", "core.hooksPath"), foreign)
            self.assertFalse(marker.exists())
            self.assertEqual(self.common_dir_snapshot(clone), before)
            repaired = lane(clone, "check", "--only", "hooks")
            self.assertEqual(repaired.returncode, 0, repaired.stdout + repaired.stderr)
            self.assertEqual(git(clone, "config", "core.hooksPath"), ".githooks")

    def test_correct_setup_succeeds_without_invoking_setup(self):
        """Fails if: the non-repairing diagnostic refuses a correct setup or invokes setup on success."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "config", "core.hooksPath", ".githooks")
            marker = Path(tmp) / "setup-ran"
            done = self.run_stubbed(
                clone, "check", "--only", "hooks", "--no-repair",
                script="#!/bin/sh\nprintf ran > \"$NO_REPAIR_MARKER\"\nexit 0\n", marker=marker)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertFalse(marker.exists())

    def test_unset_setup_fails_without_repair(self):
        """Fails if: an unset hooks path is repaired or accepted by the diagnostic."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            marker = Path(tmp) / "setup-ran"
            done = self.run_stubbed(
                clone, "check", "--only", "hooks", "--no-repair",
                script="#!/bin/sh\nprintf ran > \"$NO_REPAIR_MARKER\"\nexit 0\n", marker=marker)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertFalse(marker.exists())
            shown = subprocess.run(["git", "config", "--get", "core.hooksPath"], cwd=clone, env=ENV,
                                   capture_output=True, text=True, check=False)
            self.assertNotEqual(shown.returncode, 0)


class ScanTests(unittest.TestCase):
    def scan(self, tmp, clone, text):
        denylist = Path(tmp) / "deny.txt"
        denylist.write_text("zebracorn-marker\n")
        env = {**ENV, "HOUSE_SCAN_DENYLIST": str(denylist), "HOME": tmp}
        git(clone, "switch", "-q", "-c", "agents/x")
        commit(clone, "notes.md", text, "Add notes")
        return lane(clone, "check", "--only", "scan", env=env)

    def test_a_denylist_hit_added_by_the_lane_fails_before_any_push(self):
        """Fails if: `check` passes a lane whose commit adds a denylist term, or prints the term itself."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            done = self.scan(tmp, clone, "see zebracorn-marker here\n")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("notes.md", done.stdout + done.stderr)
            self.assertNotIn("zebracorn-marker", done.stdout + done.stderr)

    def test_a_clean_lane_passes_the_scan(self):
        """Fails if: a lane with no denylist hit is refused."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            done = self.scan(tmp, clone, "nothing to see\n")
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)


class JevCheckTests(unittest.TestCase):
    DOC = ".agents/workflow/a.md"

    def lane_with_jev(self, tmp, fresh=True):
        """A lane branch whose repository carries a doc, a learning.home question and a one-pair labels fixture."""
        clone, _ = make_repo(tmp)
        git(clone, "switch", "-q", "-c", "agents/x")
        (clone / ".agents/workflow").mkdir(parents=True)
        (clone / self.DOC).write_text("# Doc A\n\n> **What:** does a. **Read when:** touching a.\n\n## Rule\n\nThe anchor-phrase lives here.\n")
        (clone / "contracts/jev/questions").mkdir(parents=True)
        spec = importlib.util.spec_from_file_location("jev_ask_t", TOOLS / "jev_ask.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules["jev_ask_t"] = module
        spec.loader.exec_module(module)
        criteria = module.learning_criteria(clone) if fresh else {"AGENTS.md": "old"}
        (clone / "contracts/jev/questions/learning.home.json").write_text(json.dumps({"version": 1, "criteria": criteria}))
        (clone / "tools/tests/fixtures").mkdir(parents=True)
        (clone / "tools/tests/fixtures/jev_section_labels.json").write_text(json.dumps(
            {"pairs": [{"file": self.DOC, "question": "Where does the anchor live?", "any_of": ["anchor-phrase"]}]}))
        git(clone, "add", "-A")
        git(clone, "commit", "-q", "-m", "docs")
        return clone

    def test_fresh_questions_and_intact_anchors_pass(self):
        """Fails if: `check --only jev` refuses a repository whose generated questions and label anchors are current."""
        with TemporaryDirectory() as tmp:
            done = lane(self.lane_with_jev(tmp), "check", "--only", "jev")
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_a_stale_learning_home_fails(self):
        """Fails if: `check` passes a lane whose learning.home criteria no longer match the .agents docs."""
        with TemporaryDirectory() as tmp:
            done = lane(self.lane_with_jev(tmp, fresh=False), "check", "--only", "jev")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("learning.home is stale", done.stderr)

    def test_an_exception_in_the_sync_check_is_a_named_failure_not_a_traceback(self):
        """Fails if: a corrupt question file makes `check` print a traceback instead of `jev: error <type>: <message>`."""
        with TemporaryDirectory() as tmp:
            clone = self.lane_with_jev(tmp)
            (clone / "contracts/jev/questions/learning.home.json").write_text("{not json")
            done = lane(clone, "check", "--only", "jev")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("jev: error JSONDecodeError:", done.stderr)
            self.assertNotIn("Traceback", done.stderr)

    def test_a_removed_doc_anchor_fails_and_names_the_file_and_anchor(self):
        """Fails if: a doc edit that removes a labeled phrase passes `check`, or the failure omits the file or the anchor."""
        with TemporaryDirectory() as tmp:
            clone = self.lane_with_jev(tmp)
            (clone / self.DOC).write_text("# Doc A\n\n> **What:** does a. **Read when:** touching a.\n\n## Rule\n\nNothing here now.\n")
            done = lane(clone, "check", "--only", "jev")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn(self.DOC, done.stderr)
            self.assertIn("anchor-phrase", done.stderr)


class OverlapCheckTests(unittest.TestCase):
    def lane_changing(self, tmp, env, name):
        """A lane started on an unrelated declared path that then changes ``name``."""
        clone, _ = make_repo(tmp)
        git(clone, "switch", "-q", "-c", "agents/x")
        self.assertEqual(start(clone, env, "zzz/").returncode, 0)
        commit(clone, name, "{}\n", "change")
        return clone

    def test_an_open_pr_touching_a_file_the_branch_changes_fails_even_if_undeclared(self):
        """Fails if: an open PR touching tools/triage/config.json passes `check` because only the declared paths were compared."""
        with TemporaryDirectory() as tmp:
            prs = [{"number": 7, "headRefName": "agents/other", "files": [{"path": "tools/triage/config.json"}]}]
            env = fake_gh(tmp, prs)
            clone = self.lane_changing(tmp, env, "tools/triage/config.json")
            done = lane(clone, "check", "--only", "overlap", env=env)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("#7", done.stderr)
            self.assertIn("tools/triage/config.json", done.stderr)

    def test_a_pr_on_other_files_and_the_own_branch_pass(self):
        """Fails if: `check` refuses a branch whose changed files no other open PR touches, or counts its own PR."""
        with TemporaryDirectory() as tmp:
            prs = [{"number": 7, "headRefName": "agents/other", "files": [{"path": "elsewhere.txt"}]},
                   {"number": 8, "headRefName": "agents/x", "files": [{"path": "tools/triage/config.json"}]}]
            env = fake_gh(tmp, prs)
            clone = self.lane_changing(tmp, env, "tools/triage/config.json")
            done = lane(clone, "check", "--only", "overlap", env=env)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_main_files_arriving_by_merge_are_not_the_branchs_own(self):
        """Fails if: after merging origin/main (a commit touching tools/triage/config.json) into the lane, overlap flags that file or
        main's commit, or stops firing for a file the lane itself changes that an open PR also touches."""
        with TemporaryDirectory() as tmp:
            prs = [{"number": 7, "headRefName": "agents/other",
                    "files": [{"path": "tools/triage/config.json"}, {"path": "lane.txt"}]}]
            env = fake_gh(tmp, prs)
            clone = self.lane_changing(tmp, env, "lane.txt")
            other = Path(tmp) / "other"
            git(other, "pull", "-q")
            commit(other, "tools/triage/config.json", "{}\n", "main touches the config")
            git(other, "push", "-q", "origin", "main")
            git(clone, "fetch", "-q", "origin")
            git(clone, "merge", "-q", "--no-edit", "origin/main")
            done = lane(clone, "check", "--only", "overlap", env=env)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("lane.txt", done.stderr)
            self.assertNotIn("tools/triage/config.json", done.stderr)
            self.assertNotIn("main touches the config", done.stderr)

    def test_a_merged_main_file_alone_leaves_overlap_clean(self):
        """Fails if: a file that only arrived from origin/main by merge, and that an open PR touches, fails the lane."""
        with TemporaryDirectory() as tmp:
            prs = [{"number": 7, "headRefName": "agents/other", "files": [{"path": "tools/triage/config.json"}]}]
            env = fake_gh(tmp, prs)
            clone = self.lane_changing(tmp, env, "lane.txt")
            other = Path(tmp) / "other"
            git(other, "pull", "-q")
            commit(other, "tools/triage/config.json", "{}\n", "main touches the config")
            git(other, "push", "-q", "origin", "main")
            git(clone, "fetch", "-q", "origin")
            git(clone, "merge", "-q", "--no-edit", "origin/main")
            done = lane(clone, "check", "--only", "overlap", env=env)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_gh_unavailable_warns_once_and_does_not_fail(self):
        """Fails if: a failing `gh` makes `check` fail, or prints no warn line naming why."""
        with TemporaryDirectory() as tmp:
            env = fake_gh(tmp, [])
            clone = self.lane_changing(tmp, env, "lane.txt")
            gh = Path(tmp) / "bin" / "gh"
            gh.write_text("#!/bin/sh\necho 'network unreachable' >&2\nexit 1\n")
            done = lane(clone, "check", "--only", "overlap", env=env)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            warns = [line for line in done.stderr.splitlines() if "warn" in line]
            self.assertEqual(len(warns), 1, done.stderr)
            self.assertIn("network unreachable", warns[0])

    def test_a_network_call_that_hangs_times_out_with_a_lane_error(self):
        """Fails if: `run` waits past its timeout instead of raising LaneError."""
        spec = importlib.util.spec_from_file_location("lane_check_t", LANE_CHECK)
        module = importlib.util.module_from_spec(spec)
        sys.modules["lane_check_t"] = module
        spec.loader.exec_module(module)
        with self.assertRaises(module.LaneError) as caught:
            module.run(["sleep", "5"], timeout=0.2)
        self.assertIn("timed out", str(caught.exception))
        self.assertEqual(module.NETWORK_TIMEOUT, 15.0)

    def test_a_commit_merged_on_origin_main_since_the_base_fails(self):
        """Fails if: a commit that landed on origin/main after the lane base and touches a changed file passes `check`."""
        with TemporaryDirectory() as tmp:
            env = fake_gh(tmp, [])
            clone = self.lane_changing(tmp, env, "b.txt")
            other = Path(tmp) / "other"
            git(other, "pull", "-q")
            commit(other, "b.txt", "merged elsewhere\n", "other change")
            git(other, "push", "-q", "origin", "main")
            done = lane(clone, "check", "--only", "overlap", env=env)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("other change", done.stderr)


class ScopeCheckTests(unittest.TestCase):
    def lane_declaring(self, tmp, *paths):
        """A lane on agents/x that declared ``paths`` at start."""
        clone, _ = make_repo(tmp)
        git(clone, "switch", "-q", "-c", "agents/x")
        env = fake_gh(tmp, [])
        self.assertEqual(start(clone, env, *paths).returncode, 0)
        return clone, env

    def test_a_stray_file_fails_and_is_named_while_declared_files_pass(self):
        """Fails if: a file outside the declared paths passes `check --only scope`, is not named, or a declared file/dir/glob is flagged."""
        with TemporaryDirectory() as tmp:
            clone, env = self.lane_declaring(tmp, "tools/lane_check.py", "tools/tests", "docs/*.md")
            commit(clone, "tools/lane_check.py", "x\n", "in scope")
            commit(clone, "tools/tests/t.py", "x\n", "in dir")
            commit(clone, "docs/a.md", "x\n", "in glob")
            self.assertEqual(lane(clone, "check", "--only", "scope", env=env).returncode, 0)
            commit(clone, "tools/test_devcap.py", "x\n", "stray")
            done = lane(clone, "check", "--only", "scope", env=env)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("tools/test_devcap.py", done.stderr)
            self.assertNotIn("docs/a.md", done.stderr)

    def test_an_uncommitted_stray_file_fails(self):
        """Fails if: an untracked file outside the declared paths escapes the check."""
        with TemporaryDirectory() as tmp:
            clone, env = self.lane_declaring(tmp, "tools/")
            (clone / "stray.txt").write_text("x\n")
            done = lane(clone, "check", "--only", "scope", env=env)
            self.assertEqual(done.returncode, 1)
            self.assertIn("stray.txt", done.stderr)

    def test_ack_scope_passes_prints_and_is_recorded(self):
        """Fails if: --ack-scope still fails, omits the reason, or a later plain `check` fails again."""
        with TemporaryDirectory() as tmp:
            clone, env = self.lane_declaring(tmp, "tools/")
            commit(clone, "stray.txt", "x\n", "stray")
            done = lane(clone, "check", "--only", "scope", "--ack-scope", "needed for the fixture", env=env)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertIn("needed for the fixture", done.stdout)
            self.assertEqual(lane(clone, "check", "--only", "scope", env=env).returncode, 0)

    def test_a_synced_jev_question_file_is_exempt(self):
        """Fails if: a contracts/jev/questions file, which `jev_ask.py sync` writes, counts as out of scope."""
        with TemporaryDirectory() as tmp:
            clone, env = self.lane_declaring(tmp, "tools/")
            commit(clone, "contracts/jev/questions/learning.json", "{}\n", "sync")
            done = lane(clone, "check", "--only", "scope", env=env)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_an_ack_covers_only_the_files_it_named(self):
        """Fails if: after one --ack-scope, a stray file added later passes, or the acked file stops passing."""
        with TemporaryDirectory() as tmp:
            clone, env = self.lane_declaring(tmp, "tools/")
            commit(clone, "stray.txt", "x\n", "stray")
            self.assertEqual(lane(clone, "check", "--only", "scope", "--ack-scope", "why", env=env).returncode, 0)
            commit(clone, "second.txt", "x\n", "another stray")
            done = lane(clone, "check", "--only", "scope", env=env)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("second.txt", done.stderr)
            self.assertNotIn("stray.txt,", done.stderr)

    def test_untracked_files_in_a_subdirectory_are_repo_relative(self):
        """Fails if: running from a subdirectory reports an untracked file relative to it, so a declared file looks stray or a stray looks declared."""
        with TemporaryDirectory() as tmp:
            clone, env = self.lane_declaring(tmp, "tools/")
            (clone / "tools").mkdir(exist_ok=True)
            (clone / "tools" / "new.py").write_text("x\n")
            self.assertEqual(lane(clone / "tools", "check", "--only", "scope", env=env).returncode, 0)
            (clone / "docs").mkdir()
            (clone / "docs" / "n.md").write_text("x\n")
            done = lane(clone / "docs", "check", "--only", "scope", env=env)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("docs/n.md", done.stderr)

    def test_files_that_arrive_from_a_newer_main_do_not_count(self):
        """Fails if: after merging a newer origin/main into the lane, main's files are reported as strays."""
        with TemporaryDirectory() as tmp:
            clone, env = self.lane_declaring(tmp, "tools/")
            commit(clone, "tools/mine.py", "x\n", "mine")
            other = Path(tmp) / "other"
            git(other, "pull", "-q")
            commit(other, "unrelated/from_main.txt", "x\n", "main moves")
            git(other, "push", "-q", "origin", "main")
            git(clone, "fetch", "-q", "origin")
            git(clone, "merge", "-q", "--no-edit", "origin/main")
            done = lane(clone, "check", "--only", "scope", env=env)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_a_lane_branch_without_start_gets_a_loud_warning_but_passes(self):
        """Fails if: an agents/* branch with no lane base fails, or only gets the quiet note instead of WARNING."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/y")
            done = lane(clone, "check", "--only", "scope")
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertIn("WARNING", done.stderr)

    def test_no_lane_base_fails_open_with_a_note(self):
        """Fails if: a checkout with no recorded lane base fails the scope check, or says nothing."""
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            git(clone, "switch", "-q", "-c", "scratch/x")
            commit(clone, "stray.txt", "x\n", "stray")
            done = lane(clone, "check", "--only", "scope")
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertIn("scope check skipped", done.stderr)


class CiCheckTests(unittest.TestCase):
    """``check --only ci``: CI's cheap repo checks, each its own subprocess, one ``name exit=N`` line each (A1 of the PR 122 retro)."""

    COPIED = ("pattern_guard.py", "components_index.py", "house_scan.py", "affected_tests.py")
    OWNED = "apple/Sources/HassDesign/Owned.swift"
    REGISTRY = {"schemaVersion": 1, "componentScopes": ["apple/Sources/HassDesign/**/*.swift"], "internal": [], "patterns": [{
        "id": "owned", "title": "Owned", "status": "current", "doc": ".agents/patterns/owned.md", "summary": "s", "keywords": ["owned"],
        "web": [], "canonical": {"apple": [{"path": "apple/Sources/HassDesign/Owned.swift", "symbol": "Owned"}]},
        "owns": ["apple/Sources/HassDesign/Owned.swift"], "guards": [], "related": {"patterns": []}, "supersedes": [], "supersededBy": None}]}

    def ci_clone(self, tmp):
        """A repository carrying the real pattern, component-index and house-scan tools over one owned HassDesign file, all committed clean."""
        clone, _ = make_repo(tmp)
        git(clone, "switch", "-q", "-c", "agents/x")
        (clone / "tools").mkdir()
        for name in self.COPIED:
            (clone / "tools" / name).write_text((TOOLS / name).read_text())
        (clone / "contracts").mkdir()
        (clone / "contracts/patterns.json").write_text(json.dumps(self.REGISTRY))
        (clone / "contracts/house_scan.json").write_text((TOOLS.parent / "contracts/house_scan.json").read_text())
        (clone / ".agents/patterns").mkdir(parents=True)
        (clone / ".agents/patterns/owned.md").write_text("# Owned\n\nOwned files: Owned.swift\n")
        (clone / self.OWNED).parent.mkdir(parents=True)
        (clone / self.OWNED).write_text("public struct Owned {}\n")
        subprocess.run([sys.executable, str(clone / "tools/components_index.py")], cwd=clone, env=ENV, check=True, capture_output=True)
        git(clone, "add", "-A")
        git(clone, "commit", "-q", "-m", "ci tools")
        return clone

    def test_a_clean_tree_passes_and_each_command_prints_its_exit(self):
        """Fails if: a tree every CI check accepts is refused, or a command's `name exit=N` line is missing."""
        with TemporaryDirectory() as tmp:
            clone = self.ci_clone(tmp)
            done = lane(clone, "check", "--only", "ci")
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            for name in ("house_scan", "pattern_guard", "components_index"):
                self.assertIn(f"{name} exit=0", done.stdout)
            self.assertIn("rules_lint skipped", done.stdout)
            for name in ("mockups_check", "mockups_index"):  # this fixture carries no mockup tools, so CI's first step is reported skipped
                self.assertRegex(done.stdout, rf"{name} (exit=0|skipped)")

    def test_an_unowned_design_file_a_stale_index_and_a_house_literal_fail_naming_three_commands(self):
        """Fails if: any of the three CI failures goes unreported, the failing command is not named, or the check exits 0 (the PR 122 shape)."""
        with TemporaryDirectory() as tmp:
            clone = self.ci_clone(tmp)
            commit(clone, "apple/Sources/HassDesign/Fresh.swift", "public struct Fresh {}\n", "unowned file")
            commit(clone, "apple/Tests/HassDesignTests/FreshTests.swift", 'let host = "' + ".".join(["192", "168", "1", "77"]) + '"\nlet camera = "' + "camera" + ".kitchen_door_cam" + '"\n', "house literal")
            done = lane(clone, "check", "--only", "ci")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            for name in ("house_scan", "pattern_guard", "components_index"):
                self.assertIn(f"{name} exit=1", done.stdout + done.stderr)
            for command in ("python3 tools/house_scan.py", "python3 tools/pattern_guard.py", "python3 tools/components_index.py --check"):
                self.assertIn(f"`{command}` exit=1", done.stderr)

    def test_the_commands_are_the_workflows_in_its_order_with_both_mockups_steps_first(self):
        """Fails if: a cheap linux-checks step (the two Mockups commands included) is missing, or the order differs from pr-checks.yml."""
        spec = importlib.util.spec_from_file_location("lane_check_o", LANE_CHECK)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        names = [name for name, _ in module.ci_commands(Path("/r"), "main")]
        self.assertEqual(names, ["mockups_check", "mockups_index", "pattern_guard", "components_index", "jev", "house_scan",
                                 "rules_lint", "lint_motion", "test_plans", "test_suites"])

    def test_the_private_denylist_is_never_read_and_a_pipe_free_command_reports_its_own_code(self):
        """Fails if: the child sees the caller's denylist, a failing command's own exit code (7) is replaced, or a later command is skipped."""
        spec = importlib.util.spec_from_file_location("lane_check_t", LANE_CHECK)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with TemporaryDirectory() as tmp:
            private = Path(tmp) / "private.txt"
            private.write_text("secret\n")
            probe = Path(tmp) / "probe.sh"
            probe.write_text('#!/bin/sh\n[ "$HOUSE_SCAN_DENYLIST" != "%s" ] && [ ! -e "$HOUSE_SCAN_DENYLIST" ]\n' % private)
            seven = Path(tmp) / "seven.sh"
            seven.write_text("#!/bin/sh\nexit 7\n")
            for script in (probe, seven):
                script.chmod(stat.S_IRWXU)
            saved = os.environ.get("HOUSE_SCAN_DENYLIST")
            os.environ["HOUSE_SCAN_DENYLIST"] = str(private)
            try:
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    why = module.check_ci("main", Path(tmp), [("probe", [str(probe)]), ("seven", [str(seven)]), ("after", [str(probe)])])
            finally:
                if saved is None:
                    del os.environ["HOUSE_SCAN_DENYLIST"]
                else:
                    os.environ["HOUSE_SCAN_DENYLIST"] = saved
            self.assertEqual(out.getvalue().splitlines(), ["probe exit=0", "seven exit=7", "after exit=0"])
            self.assertIn("seven.sh` exit=7", why)
            self.assertNotIn("probe.sh", why)


def load_lane_check():
    """``lane_check.py`` as a module."""
    spec = importlib.util.spec_from_file_location("lane_check_sep", LANE_CHECK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def lane_base_path(clone):
    """Where ``start`` writes the lane base in ``clone``."""
    return Path(git(clone, "rev-parse", "--absolute-git-dir")) / "lane-base"


class SeparationAndTestsCheckTests(unittest.TestCase):
    """``check --only separation`` and ``--only tests``, and the separation rule at ``start`` (A1 of the merge-route retro)."""

    CONFIG = "tools/triage/config.json"
    HOOK_FILE = "tools/hooks/x.py"
    REVIEWER = ".claude/agents/reviewer.md"

    def policy_lane(self, tmp, stub=None):
        """A lane on agents/x whose base holds the real lander and policy modules (and a stub ``run_tool_tests.sh`` when given)."""
        clone, _ = make_repo(tmp)
        (clone / "tools").mkdir(exist_ok=True)
        for name in ("lane_land.py", "pr_policy.py"):
            (clone / "tools" / name).write_text((TOOLS / name).read_text())
        if stub is not None:
            runner = clone / "tools" / "run_tool_tests.sh"
            runner.write_text(stub)
            runner.chmod(stat.S_IRWXU)
        git(clone, "add", "-A")
        git(clone, "commit", "-q", "-m", "policy tools")
        git(clone, "push", "-q", "origin", "main")
        git(clone, "switch", "-q", "-c", "agents/x")
        return clone

    def test_a_behaviour_path_with_an_evaluation_path_fails_and_names_both(self):
        """Fails if: the #214 shape (triage config plus a hook) passes locally, or the failure names neither file."""
        with TemporaryDirectory() as tmp:
            clone = self.policy_lane(tmp)
            commit(clone, self.CONFIG, "{}\n", "config")
            commit(clone, self.HOOK_FILE, "x\n", "hook")
            done = lane(clone, "check", "--only", "separation")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("trusted_separation", done.stderr)
            self.assertIn(self.HOOK_FILE, done.stderr)
            self.assertIn(self.CONFIG, done.stderr)

    def test_an_evaluation_path_alone_passes_and_an_uncommitted_pair_fails(self):
        """Fails if: the config file alone is refused, or an uncommitted pair escapes the check."""
        with TemporaryDirectory() as tmp:
            clone = self.policy_lane(tmp)
            commit(clone, self.CONFIG, "{}\n", "config")
            self.assertEqual(lane(clone, "check", "--only", "separation").returncode, 0)
            (clone / self.HOOK_FILE).parent.mkdir(parents=True, exist_ok=True)
            (clone / self.HOOK_FILE).write_text("x\n")
            self.assertEqual(lane(clone, "check", "--only", "separation").returncode, 1)

    def test_start_refuses_declared_paths_that_cannot_travel_together(self):
        """Fails if: a brief that declares the config file and a reviewer file starts, or the refusal leaves a recorded lane base."""
        with TemporaryDirectory() as tmp:
            clone = self.policy_lane(tmp)
            done = start(clone, fake_gh(tmp, []), self.CONFIG, self.REVIEWER)
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn(self.CONFIG, done.stderr)
            self.assertIn(self.REVIEWER, done.stderr)
            self.assertFalse(lane_base_path(clone).exists())

    def test_start_expands_a_glob_against_the_tree_and_accepts_one_side_alone(self):
        """Fails if: a glob that covers both kinds passes unexpanded, or one side alone is refused."""
        with TemporaryDirectory() as tmp:
            clone = self.policy_lane(tmp)
            commit(clone, self.CONFIG, "{}\n", "config")
            commit(clone, self.HOOK_FILE, "x\n", "hook")
            git(clone, "push", "-q", "origin", "agents/x")
            env = fake_gh(tmp, [])
            self.assertEqual(start(clone, env, "tools/*/*.json", "tools/hooks/*").returncode, 1)
            self.assertEqual(start(clone, env, "tools/triage/*", "tools/hooks/*").returncode, 1)
            self.assertEqual(start(clone, env, self.CONFIG).returncode, 0)

    def test_a_failing_tool_test_run_reports_its_exit_and_names_the_module(self):
        """Fails if: a failing run passes, `tests exit=N` is missing, or the failing module is not named."""
        stub = "#!/bin/sh\necho 'FAIL: test_pin (test_hass_triage.Pins.test_pin)' >&2\nexit 3\n"
        with TemporaryDirectory() as tmp:
            clone = self.policy_lane(tmp, stub)
            commit(clone, "tools/x.py", "x\n", "tool change")
            done = lane(clone, "check", "--only", "tests")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("tests exit=3", done.stdout)
            self.assertIn("test_hass_triage", done.stderr)

    def test_a_green_run_passes_with_its_exit_printed(self):
        """Fails if: a passing run fails, or `tests exit=0` is not printed."""
        with TemporaryDirectory() as tmp:
            clone = self.policy_lane(tmp, "#!/bin/sh\necho ran\nexit 0\n")
            commit(clone, "tools/x.py", "x\n", "tool change")
            done = lane(clone, "check", "--only", "tests")
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertIn("tests exit=0", done.stdout)

    def test_a_docs_only_diff_skips_the_tests_and_says_so(self):
        """Fails if: a docs-only default run starts the suite, or hides that it skipped it."""
        with TemporaryDirectory() as tmp:
            clone = self.policy_lane(tmp, "#!/bin/sh\necho RAN\nexit 9\n")
            commit(clone, "docs/a.md", "x\n", "docs only")
            module = load_lane_check()
            out = io.StringIO()
            cwd = os.getcwd()
            os.chdir(clone)
            try:
                with contextlib.redirect_stdout(out):
                    why = module.check_tests("main")
            finally:
                os.chdir(cwd)
            self.assertIsNone(why)
            self.assertIn("tests skipped", out.getvalue())
            self.assertNotIn("RAN", out.getvalue())

    def test_a_dropped_reviewer_phrase_fails_a_pin_in_a_test_named_for_another_file(self):
        """Fails if: the #215 class (an edit that drops a phrase another module pins) passes `tests`."""
        stub = '#!/bin/sh\ncd "$(dirname "$0")/.." && python3 -m unittest discover -s pins\n'
        with TemporaryDirectory() as tmp:
            clone, _ = make_repo(tmp)
            (clone / "tools").mkdir()
            (clone / "pins").mkdir()
            (clone / ".claude/agents").mkdir(parents=True)
            (clone / self.REVIEWER).write_text("The System API check.\n")
            (clone / "pins/test_other_file.py").write_text(
                "import unittest\nfrom pathlib import Path\n\n\nclass Pin(unittest.TestCase):\n    def test_definition(self):\n"
                "        self.assertIn('System API', Path('.claude/agents/reviewer.md').read_text())\n")
            runner = clone / "tools" / "run_tool_tests.sh"
            runner.write_text(stub)
            runner.chmod(stat.S_IRWXU)
            git(clone, "add", "-A")
            git(clone, "commit", "-q", "-m", "base")
            git(clone, "push", "-q", "origin", "main")
            git(clone, "switch", "-q", "-c", "agents/x")
            self.assertEqual(lane(clone, "check", "--only", "tests").returncode, 0)
            commit(clone, self.REVIEWER, "The check.\n", "reword")
            done = lane(clone, "check", "--only", "tests")
            self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
            self.assertIn("test_other_file", done.stderr)

    def test_failing_modules_reads_unittest_ids(self):
        """Fails if: a FAIL or ERROR line does not yield its module, or a loader failure names `unittest`."""
        out = ("FAIL: test_a (test_pr_land.Reviewer.test_a)\nERROR: test_b (tools.release.tests.test_x.Cls.test_b) (i=1)\n"
               "ERROR: test_broken (unittest.loader._FailedTest.test_broken)\nFAIL: test_old (test_older.Cls)\nok\n")
        self.assertEqual(load_lane_check().failing_modules(out), ["test_broken", "test_older", "test_pr_land", "tools.release.tests.test_x"])


if __name__ == "__main__":
    unittest.main()
