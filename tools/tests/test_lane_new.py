"""``lane_new.sh`` adds leases as bounded best effort, never as Git work."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import factory_lease  # noqa: E402


class LaneNewLeaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.origin = self.root / "origin.git"
        self.repo = self.root / "repo"
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_AUTHOR_NAME": "factory-test",
            "GIT_AUTHOR_EMAIL": "factory@example.invalid",
            "GIT_COMMITTER_NAME": "factory-test",
            "GIT_COMMITTER_EMAIL": "factory@example.invalid",
            "LC_ALL": "C",
        }
        self.git(self.root, "init", "-q", "--bare", "-b", "main", str(self.origin))
        self.git(self.root, "clone", "-q", str(self.origin), str(self.repo))
        (self.repo / "tools").mkdir()
        self.copy_helpers()
        (self.repo / ".gitignore").write_text(".claude/worktrees/\n")
        (self.repo / "README.md").write_text("base\n")
        self.git(self.repo, "add", "-A")
        self.git(self.repo, "commit", "-qm", "base")
        self.git(self.repo, "push", "-q", "-u", "origin", "main")

    def git(self, cwd, *arguments):
        return subprocess.run(
            ["git", *arguments],
            cwd=cwd,
            env=self.env,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    def copy_helpers(self):
        for name in ("lane_new.sh", "factory_lease.py"):
            shutil.copy(TOOLS / name, self.repo / "tools" / name)

    def run_lane(self, *arguments):
        return subprocess.run(
            ["bash", "tools/lane_new.sh", *arguments],
            cwd=self.repo,
            env=self.env,
            capture_output=True,
            text=True,
        )

    def store_records(self):
        identity = factory_lease.discover_repository(self.repo)
        records, invalid = factory_lease.LeaseStore(identity).read_records()
        self.assertEqual(invalid, 0)
        return records

    def test_new_worktree_and_branch_create_one_bound_pair(self):
        result = self.run_lane("proof")
        self.assertEqual(result.returncode, 0, result.stderr)
        lane = self.repo / ".claude" / "worktrees" / "proof"
        self.assertEqual(
            self.git(lane, "rev-parse", "--abbrev-ref", "HEAD"),
            "claude/proof",
        )
        records = self.store_records()
        self.assertEqual(
            sorted(record["class"] for record in records),
            ["branch", "worktree"],
        )
        self.assertEqual(result.stderr, "")
        self.assertIn("tools/bg_run.py", result.stdout)
        self.assertIn("tools/ship.sh", result.stdout)

    def test_new_worktree_on_existing_branch_claims_only_the_worktree(self):
        self.git(self.repo, "branch", "claude/existing", "main")
        self.git(
            self.repo,
            "config",
            "branch.claude/existing.sh-base",
            "origin/main",
        )
        result = self.run_lane("existing")
        self.assertEqual(result.returncode, 0, result.stderr)
        records = self.store_records()
        self.assertEqual(
            [record["class"] for record in records],
            ["worktree"],
        )
        self.assertEqual(
            self.git(
                self.repo,
                "config",
                "--get",
                "branch.claude/existing.sh-base",
            ),
            "origin/main",
        )

    def test_rerun_renews_one_validated_generation(self):
        first = self.run_lane("proof")
        self.assertEqual(first.returncode, 0, first.stderr)
        before = {
            record["lease_id"]: record["generation"]
            for record in self.store_records()
        }
        second = self.run_lane("proof")
        self.assertEqual(second.returncode, 0, second.stderr)
        after = {
            record["lease_id"]: record["generation"]
            for record in self.store_records()
        }
        self.assertEqual(set(after), set(before))
        self.assertEqual(
            {lease_id: generation + 1 for lease_id, generation in before.items()},
            after,
        )

    def test_unleased_or_mismatched_existing_lane_is_never_adopted(self):
        lane = self.repo / ".claude" / "worktrees" / "manual"
        self.git(
            self.repo,
            "worktree",
            "add",
            "-q",
            "-b",
            "claude/actual",
            str(lane),
            "main",
        )
        identity = factory_lease.discover_repository(self.repo)
        lease_id, branch_id = factory_lease.LeaseStore(
            identity
        ).create_worktree(lane, "lane_new", task="manual")
        self.assertIsNone(branch_id)
        result = self.run_lane("manual", "--branch", "claude/other")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stderr.count(
                "lane_new: lease bookkeeping unavailable (lane preserved)\n"
            ),
            1,
        )
        self.assertEqual(
            [record["lease_id"] for record in self.store_records()],
            [lease_id],
        )
        admin = Path(
            (lane / ".git").read_text().strip().removeprefix("gitdir: ")
        )
        self.assertEqual(
            (admin / "factory-lease").read_text().strip(), lease_id
        )

    def test_lock_failure_warns_once_and_preserves_git_result(self):
        identity = factory_lease.discover_repository(self.repo)
        child_code = (
            "import sys\n"
            "from pathlib import Path\n"
            "sys.path.insert(0, %r)\n"
            "import factory_lease\n"
            "identity=factory_lease.RepositoryIdentity(Path(sys.argv[1]), sys.argv[2])\n"
            "store=factory_lease.LeaseStore(identity)\n"
            "with store.writer_lock():\n"
            " print('locked', flush=True)\n"
            " sys.stdin.readline()\n"
        ) % str(TOOLS)
        child = subprocess.Popen(
            [
                sys.executable,
                "-c",
                child_code,
                str(identity.common_dir),
                identity.root_commit,
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            env=self.env,
        )
        try:
            self.assertEqual(child.stdout.readline().strip(), "locked")
            result = self.run_lane("contended")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("lane created", result.stdout)
            self.assertEqual(
                result.stderr.count(
                    "lane_new: lease bookkeeping unavailable (lane preserved)\n"
                ),
                1,
            )
            lane = self.repo / ".claude" / "worktrees" / "contended"
            self.assertTrue((lane / ".git").exists())
            self.assertEqual(self.store_records(), ())
        finally:
            if child.stdin is not None:
                child.stdin.write("\n")
                child.stdin.flush()
            child.wait(timeout=10)
            if child.stdin is not None:
                child.stdin.close()
            if child.stdout is not None:
                child.stdout.close()

    def test_missing_helper_preserves_original_lane_and_handoff(self):
        (self.repo / "tools" / "factory_lease.py").unlink()
        result = self.run_lane("legacy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(
            (
                self.repo
                / ".claude"
                / "worktrees"
                / "legacy"
                / ".git"
            ).exists()
        )
        self.assertIn("tools/ship.sh", result.stdout)
        self.assertEqual(
            result.stderr.count(
                "lane_new: lease bookkeeping unavailable (lane preserved)\n"
            ),
            1,
        )


if __name__ == "__main__":
    unittest.main()
