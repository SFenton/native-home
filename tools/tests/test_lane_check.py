"""``tools/lane_check.py``: overlap at lane start, the revert guard, the hooks path and the denylist scan, against throwaway repositories.

Each shape comes from the T-gh-native-gate post-mortem (Action 1): a lane started over an open PR (#18), a soft-reset squash over a
base another session's fetch had moved (#25), ``core.hooksPath`` as an absolute path, and ``house_scan`` found late.
"""

import importlib.util
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
        return lane(clone, "check", "--only", "hooks")

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


if __name__ == "__main__":
    unittest.main()
