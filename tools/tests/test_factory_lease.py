"""Private factory leases are bounded, identity-bound and serialized."""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import factory_lease  # noqa: E402


class FakePullRequests(factory_lease.PullRequestProvider):
    repository = "example/project"

    def __init__(self, values):
        self.values = tuple(values)

    def list_for_branch(self, repository, branch):
        return self.values


class LeaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.origin = self.root / "origin.git"
        self.repo = self.root / "repo"
        self.lane = self.root / "lane"
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
        (self.repo / "tracked.txt").write_text("base\n")
        self.git(self.repo, "add", "-A")
        self.git(self.repo, "commit", "-qm", "base")
        self.git(self.repo, "push", "-q", "-u", "origin", "main")
        self.git(
            self.repo,
            "worktree",
            "add",
            "-q",
            "-b",
            "agents/proof",
            str(self.lane),
            "main",
        )
        (self.lane / "tracked.txt").write_text("lane\n")
        self.git(self.lane, "add", "tracked.txt")
        self.git(self.lane, "commit", "-qm", "lane")
        self.identity = factory_lease.discover_repository(self.repo)
        self.now = int(self.identity and 2_000_000_000)
        self.store = factory_lease.LeaseStore(self.identity, now=self.now)

    def git(self, cwd, *arguments):
        return subprocess.run(
            ["git", *arguments],
            cwd=cwd,
            env=self.env,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    def records(self, store=None):
        records, invalid = (store or self.store).read_records()
        self.assertEqual(invalid, 0)
        return records

    def record_path(self, resource_class, lease_id):
        return (
            self.identity.common_dir
            / "factory"
            / "leases"
            / resource_class
            / (lease_id + ".json")
        )

    def test_create_binds_nonce_and_private_modes_without_duplicate_keys(self):
        worktree_id, branch_id = self.store.create_worktree(
            self.lane, "lane_new", task="proof", branch_created="agents/proof"
        )
        records = {record["lease_id"]: record for record in self.records()}
        self.assertEqual(set(records), {worktree_id, branch_id})
        nonce = (
            self.lane
            / ".git"
        )
        admin = Path(nonce.read_text().strip().removeprefix("gitdir: ")).resolve()
        self.assertEqual((admin / "factory-lease").read_text().strip(), worktree_id)
        for path in (
            self.identity.common_dir / "factory",
            self.identity.common_dir / "factory" / "leases",
            self.identity.common_dir / "factory" / "locks",
            self.identity.common_dir / "factory" / "leases" / "worktree",
            admin,
        ):
            if path == admin:
                continue
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
        for path in (
            self.record_path("worktree", worktree_id),
            self.record_path("branch", branch_id),
            admin / "factory-lease",
        ):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        raw = self.record_path("worktree", worktree_id).read_text()
        self.record_path("worktree", worktree_id).write_text(
            '{"v":1,"v":1}\n'
        )
        records, invalid = self.store.read_records()
        self.assertEqual(len(records), 1)
        self.assertEqual(invalid, 1)
        self.record_path("worktree", worktree_id).write_text(raw)

    def test_closed_schema_oversize_corruption_and_symlink_are_not_usable(self):
        worktree_id, _branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        path = self.record_path("worktree", worktree_id)
        raw = json.loads(path.read_text())
        raw["unexpected"] = True
        path.write_text(json.dumps(raw))
        records, invalid = self.store.read_records()
        self.assertEqual(len(records), 1)
        self.assertEqual(invalid, 1)
        path.write_text(" " * (factory_lease.MAX_RECORD_BYTES + 1))
        records, invalid = self.store.read_records()
        self.assertEqual(len(records), 1)
        self.assertEqual(invalid, 1)
        path.unlink()
        external = self.root / "external"
        external.write_text("{}")
        path.symlink_to(external)
        records, invalid = self.store.read_records()
        self.assertEqual(len(records), 1)
        self.assertEqual(invalid, 1)

    def test_future_expiry_holds_but_future_events_and_wrong_times_fail(self):
        worktree_id, _branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        record = self.record_path("worktree", worktree_id).read_text()
        value = json.loads(record)
        self.assertGreater(value["expires"], self.now)
        factory_lease.validate_record(value, self.now, self.identity)
        value["renewed"] = self.now + 1
        value["expires"] = value["renewed"] + factory_lease.LEASE_TTL_SECONDS
        with self.assertRaises(factory_lease.InvalidLease):
            factory_lease.validate_record(value, self.now, self.identity)
        value = json.loads(record)
        value["expires"] += 1
        with self.assertRaises(factory_lease.InvalidLease):
            factory_lease.validate_record(value, self.now, self.identity)

    def test_release_requires_expiry_for_finish_and_renewal_invalidates_release(self):
        worktree_id, _branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        self.store.release(worktree_id, "ended")
        released = [
            record for record in self.records() if record["lease_id"] == worktree_id
        ][0]
        self.assertEqual(released["state"], "released")
        self.assertIsNone(released["release"]["merged"])
        self.store._now += 1
        self.store.renew_worktree(self.lane, "agents/proof")
        renewed = [
            record for record in self.records() if record["lease_id"] == worktree_id
        ][0]
        self.assertEqual(renewed["state"], "active")
        self.assertIsNone(renewed["release"])
        self.assertEqual(renewed["generation"], 2)

    def test_atomic_failure_leaves_no_record_or_nonce(self):
        original = self.store._write_record
        calls = []

        def fail_branch(record):
            calls.append(record["class"])
            if record["class"] == "branch":
                raise OSError("synthetic")
            original(record)

        with mock.patch.object(self.store, "_write_record", fail_branch):
            with self.assertRaises(OSError):
                self.store.create_worktree(
                    self.lane,
                    "lane_new",
                    branch_created="agents/proof",
                )
        self.assertEqual(calls, ["worktree", "branch"])
        records, invalid = self.store.read_records()
        self.assertEqual((records, invalid), ((), 0))
        gitfile = self.lane / ".git"
        admin = Path(gitfile.read_text().strip().removeprefix("gitdir: "))
        self.assertFalse((admin / "factory-lease").exists())

    def test_writer_lock_conflict_never_falls_back_to_unlocked_write(self):
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
                str(self.identity.common_dir),
                self.identity.root_commit,
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            env=self.env,
        )
        try:
            self.assertEqual(child.stdout.readline().strip(), "locked")
            with self.assertRaises(factory_lease.LockBusy):
                self.store.create_worktree(
                    self.lane,
                    "lane_new",
                    branch_created="agents/proof",
                )
            self.assertEqual(self.records(), ())
        finally:
            if child.stdin is not None:
                child.stdin.write("\n")
                child.stdin.flush()
            child.wait(timeout=10)
            if child.stdin is not None:
                child.stdin.close()
            if child.stdout is not None:
                child.stdout.close()

    def test_replaced_path_does_not_reuse_stale_admin_identity(self):
        worktree_id, _branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        record = [
            value for value in self.records() if value["lease_id"] == worktree_id
        ][0]
        shutil.rmtree(self.lane)
        self.lane.mkdir()
        (self.lane / "sentinel").write_text("foreign")
        self.assertFalse(
            factory_lease.lease_matches_worktree(
                record,
                self.lane,
                "agents/proof",
                self.git(self.repo, "rev-parse", "agents/proof"),
            )
        )
        self.assertTrue((self.lane / "sentinel").exists())

    def test_reconcile_attests_only_one_same_repo_merged_generation(self):
        worktree_id, branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        head = self.git(self.lane, "rev-parse", "HEAD")
        valid = factory_lease.PullRequestEvidence(
            41, FakePullRequests.repository, "main", "agents/proof", "MERGED", head, self.now
        )
        wrong_repo = factory_lease.PullRequestEvidence(
            42, "example/other", "main", "agents/proof", "MERGED", head, self.now
        )
        with self.assertRaises(factory_lease.InvalidLease):
            self.store.reconcile(
                branch_id, provider=FakePullRequests((valid, wrong_repo, valid))
            )
        with self.assertRaises(factory_lease.InvalidLease):
            self.store.reconcile(
                branch_id,
                provider=FakePullRequests(
                    (
                        valid,
                        factory_lease.PullRequestEvidence(
                            43,
                            FakePullRequests.repository,
                            "main",
                            "agents/proof",
                            "OPEN",
                            head,
                            self.now,
                        ),
                    )
                ),
            )
        self.store.reconcile(branch_id, provider=FakePullRequests((valid,)))
        records = {record["lease_id"]: record for record in self.records()}
        for lease_id in (worktree_id, branch_id):
            release = records[lease_id]["release"]
            self.assertEqual(release["reason"], "merged")
            self.assertEqual(release["merged"]["local_tip"], head)
            self.assertEqual(release["merged"]["head_oid"], head)
            self.assertEqual(release["merged"]["generation"], 1)
        main_head = self.git(self.repo, "rev-parse", "main")
        self.assertNotEqual(main_head, head)

    def test_changed_tip_or_closed_pull_request_is_not_merge_evidence(self):
        _worktree_id, branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        (self.lane / "tracked.txt").write_text("changed\n")
        self.git(self.lane, "add", "tracked.txt")
        self.git(self.lane, "commit", "-qm", "changed")
        head = self.git(self.lane, "rev-parse", "HEAD")
        provider = FakePullRequests(
            (
                factory_lease.PullRequestEvidence(
                    51,
                    FakePullRequests.repository,
                    "main",
                    "agents/proof",
                    "MERGED",
                    head,
                    self.now,
                ),
            )
        )
        with self.assertRaises(factory_lease.InvalidLease):
            self.store.reconcile(branch_id, provider=provider)
        self.git(self.lane, "reset", "-q", "--hard", "HEAD^")
        old_head = self.git(self.lane, "rev-parse", "HEAD")
        closed = FakePullRequests(
            (
                factory_lease.PullRequestEvidence(
                    52,
                    FakePullRequests.repository,
                    "main",
                    "agents/proof",
                    "CLOSED",
                    old_head,
                    self.now,
                ),
            )
        )
        with self.assertRaises(factory_lease.InvalidLease):
            self.store.reconcile(branch_id, provider=closed)

    def test_adoption_rejects_registry_style_or_ambiguous_evidence(self):
        with self.assertRaises(factory_lease.InvalidLease):
            self.store.adopt_worktree(
                self.lane,
                {
                    "reviewed": False,
                    "repo": self.identity.as_json(),
                    "path": str(self.lane),
                    "branch": "agents/proof",
                    "head": self.git(self.lane, "rev-parse", "HEAD"),
                    "generation": 1,
                    "creation": "fixture",
                },
            )
        self.assertEqual(self.records(), ())
        gitfile = self.lane / ".git"
        admin = Path(gitfile.read_text().strip().removeprefix("gitdir: "))
        self.assertFalse((admin / "factory-lease").exists())


if __name__ == "__main__":
    unittest.main()
