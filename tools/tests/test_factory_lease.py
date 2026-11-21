"""Private factory leases are bounded, identity-bound and serialized."""

from __future__ import annotations

import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import factory  # noqa: E402
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

    def worktree_report_with_inode(self, record, inode, now):
        snapshot = factory.LeaseSnapshot(
            identity=self.identity,
            records=(record,),
            invalid=0,
        )
        provider = factory.GitResourceProvider(
            "worktrees",
            self.repo,
            factory.GitReader(self.repo, factory.ReadOnlyRunner()),
            snapshot,
            now=now,
        )
        processes = mock.Mock()
        processes.inventory.return_value = factory.ProcessObservation(
            pids=frozenset(),
            cwds=(),
            starts={},
            pgids=frozenset(),
        )
        original_lstat = Path.lstat

        def lstat(path):
            info = original_lstat(path)
            if path == self.lane:
                values = list(info)
                values[stat.ST_INO] = inode
                return os.stat_result(values)
            return info

        with mock.patch.object(Path, "lstat", new=lstat):
            return factory.build_report((provider,), processes)["worktrees"]

    def test_rebuilt_path_with_reused_inode_is_held_by_content(self):
        worktree_id, _branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        record = [
            value for value in self.records() if value["lease_id"] == worktree_id
        ][0]
        original_inode = record["subject"]["inode"]
        gitfile = (self.lane / ".git").read_bytes()
        shutil.rmtree(self.lane)
        self.lane.mkdir()
        (self.lane / ".git").write_bytes(gitfile)
        (self.lane / "sentinel").write_text("foreign")
        report = self.worktree_report_with_inode(
            record, original_inode, self.now
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(
            {
                reason
                for reason, count in report["hold_reasons"].items()
                if count
            },
            {
                "active_hold",
                "dirty",
                "not_finished",
                "unmerged",
                "untracked",
            },
        )

    def test_rebuilt_path_with_different_inode_has_unknown_owner(self):
        worktree_id, _branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        record = [
            value for value in self.records() if value["lease_id"] == worktree_id
        ][0]
        different_inode = record["subject"]["inode"] + 1
        gitfile = (self.lane / ".git").read_bytes()
        shutil.rmtree(self.lane)
        self.lane.mkdir()
        (self.lane / ".git").write_bytes(gitfile)
        (self.lane / "sentinel").write_text("foreign")
        report = self.worktree_report_with_inode(
            record, different_inode, self.now
        )
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(
            {
                reason
                for reason, count in report["hold_reasons"].items()
                if count
            },
            {"dirty", "unknown_owner", "unmerged", "untracked"},
        )

    def test_matching_rebuilt_clean_attested_tree_is_eligible_after_expiry(self):
        worktree_id, branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        head = self.git(self.lane, "rev-parse", "HEAD")
        self.store.reconcile(
            branch_id,
            provider=FakePullRequests(
                (
                    factory_lease.PullRequestEvidence(
                        40,
                        FakePullRequests.repository,
                        "main",
                        "agents/proof",
                        "MERGED",
                        head,
                        self.now,
                    ),
                )
            ),
        )
        record = [
            value for value in self.records() if value["lease_id"] == worktree_id
        ][0]
        original_inode = record["subject"]["inode"]
        gitfile = (self.lane / ".git").read_bytes()
        shutil.rmtree(self.lane)
        self.lane.mkdir()
        (self.lane / ".git").write_bytes(gitfile)
        self.git(self.lane, "reset", "--hard", "-q", "HEAD")
        report = self.worktree_report_with_inode(
            record, original_inode, record["expires"] + 1
        )
        self.assertEqual(
            (report["total"], report["eligible"], report["held"]),
            (1, 1, 0),
        )
        self.assertTrue(
            all(count == 0 for count in report["hold_reasons"].values())
        )

    def test_prunable_worktree_does_not_break_an_existing_subject(self):
        missing = self.root / "missing-lane"
        self.git(
            self.repo,
            "worktree",
            "add",
            "-q",
            "-b",
            "agents/missing",
            str(missing),
            "main",
        )
        shutil.rmtree(missing)
        inventory = self.git(
            self.lane, "worktree", "list", "--porcelain"
        )
        self.assertIn("prunable ", inventory)
        worktree_id, _branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        self.assertTrue(worktree_id)

    def test_process_start_normalizes_real_and_padded_ps_output(self):
        completed = subprocess.run(
            ["ps", "-o", "lstart=", "-p", str(os.getpid())],
            capture_output=True,
            text=True,
            check=True,
            env=self.env,
        )
        raw = completed.stdout
        self.assertTrue(raw.strip())
        self.assertEqual(
            factory_lease.process_start(os.getpid()),
            factory_lease.normalize_process_start(raw),
        )
        padded = "Sat Nov  7 09:26:17 2026"
        self.assertEqual(
            factory_lease.normalize_process_start(padded),
            "Sat Nov 7 09:26:17 2026",
        )

    def test_path_reuse_creates_and_renews_only_the_new_nonce(self):
        first_id, _branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        self.git(self.repo, "worktree", "remove", "--force", str(self.lane))
        self.git(
            self.repo,
            "worktree",
            "add",
            "-q",
            str(self.lane),
            "agents/proof",
        )
        second_id, branch_id = self.store.create_worktree(
            self.lane, "lane_new", task="replacement"
        )
        self.assertNotEqual(first_id, second_id)
        self.assertIsNone(branch_id)
        nonce = (
            Path((self.lane / ".git").read_text().strip().removeprefix("gitdir: "))
            / "factory-lease"
        )
        self.assertEqual(nonce.read_text().strip(), second_id)
        self.assertEqual(
            self.store.renew_worktree(self.lane, "agents/proof"), second_id
        )
        marker = self.lane / "build" / "runs" / "replacement.running"
        marker.parent.mkdir(parents=True)
        run_id = self.store.begin_run(
            self.lane, marker.resolve(), "replacement", os.getpid()
        )
        self.assertIsNotNone(run_id)
        records = {record["lease_id"]: record for record in self.records()}
        self.assertGreater(records[second_id]["generation"], 1)
        self.assertEqual(
            records[run_id]["subject"]["parent_lease_id"], second_id
        )

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

    def test_reconcile_rejects_wrong_or_ambiguous_generation_attribution(self):
        _worktree_id, branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        head = self.git(self.lane, "rev-parse", "HEAD")

        def evidence(**changes):
            values = {
                "number": 44,
                "repository": FakePullRequests.repository,
                "base": "main",
                "branch": "agents/proof",
                "state": "MERGED",
                "head_oid": head,
                "created_at": self.now,
            }
            values.update(changes)
            return factory_lease.PullRequestEvidence(**values)

        rejected = (
            evidence(repository="example/other"),
            evidence(base="other"),
            evidence(branch="agents/other"),
            evidence(created_at=self.now - 1),
            evidence(created_at=None),
            evidence(state="UNKNOWN"),
        )
        for item in rejected:
            with self.subTest(item=item):
                with self.assertRaises(factory_lease.InvalidLease):
                    self.store.reconcile(
                        branch_id, provider=FakePullRequests((item,))
                    )

        class Broken(factory_lease.PullRequestProvider):
            def list_for_branch(self, repository, branch):
                raise factory_lease.LeaseError(
                    "pull request evidence unavailable"
                )

        with self.assertRaises(factory_lease.LeaseError):
            self.store.reconcile(branch_id, provider=Broken())

    def test_reconcile_serializes_a_competing_renewal(self):
        _worktree_id, branch_id = self.store.create_worktree(
            self.lane, "lane_new", branch_created="agents/proof"
        )
        head = self.git(self.lane, "rev-parse", "HEAD")
        child_code = (
            "import sys\n"
            "from pathlib import Path\n"
            "sys.path.insert(0, %r)\n"
            "import factory_lease\n"
            "identity=factory_lease.RepositoryIdentity("
            "Path(sys.argv[1]), sys.argv[2])\n"
            "store=factory_lease.LeaseStore(identity, now=%d)\n"
            "try:\n"
            " store.renew_worktree(Path(sys.argv[3]), %r)\n"
            "except factory_lease.LockBusy:\n"
            " print('busy')\n"
        ) % (str(TOOLS), self.now, "agents/proof")

        class Racing(factory_lease.PullRequestProvider):
            repository = "example/project"

            def list_for_branch(inner, repository, branch):
                completed = subprocess.run(
                    [
                        sys.executable,
                        "-c",
                        child_code,
                        str(self.identity.common_dir),
                        self.identity.root_commit,
                        str(self.lane),
                    ],
                    capture_output=True,
                    text=True,
                    env=self.env,
                    check=True,
                )
                self.assertEqual(completed.stdout.strip(), "busy")
                return (
                    factory_lease.PullRequestEvidence(
                        45,
                        repository,
                        "main",
                        branch,
                        "MERGED",
                        head,
                        self.now,
                    ),
                )

        self.store.reconcile(branch_id, provider=Racing())
        self.assertEqual(
            self.store.renew_worktree(self.lane, "agents/proof"),
            [
                record["lease_id"]
                for record in self.records()
                if record["class"] == "worktree"
            ][0],
        )

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

    def test_adoption_is_fixture_only_and_absent_from_cli(self):
        evidence = {
            "reviewed": True,
            "repo": self.identity.as_json(),
            "path": str(self.lane),
            "branch": "agents/proof",
            "head": self.git(self.lane, "rev-parse", "HEAD"),
            "generation": 1,
            "creation": "fixture",
        }
        with self.assertRaises(factory_lease.InvalidLease):
            self.store.adopt_worktree(self.lane, evidence)
        fixture = factory_lease.LeaseStore(
            self.identity, now=self.now, store_root=self.root / "fixture-store"
        )
        lease_id = fixture.adopt_worktree(self.lane, evidence)
        self.assertTrue(lease_id)
        with self.assertRaises(factory_lease.InvalidLease):
            fixture.adopt_worktree(self.lane, evidence)
        err = io.StringIO()
        with redirect_stderr(err):
            with self.assertRaises(SystemExit):
                factory_lease.main(["adopt"])
        self.assertNotIn(str(self.lane), err.getvalue())

    def test_original_leaf_symlink_is_rejected_without_following(self):
        external = self.root / "external"
        external.write_text("private")
        linked = self.root / "linked"
        linked.symlink_to(external)
        with self.assertRaises(OSError):
            factory_lease._read_path_nofollow(linked, 1024)
        self.assertEqual(external.read_text(), "private")

    def test_git_and_cli_timeouts_become_fixed_lease_errors(self):
        timeout = subprocess.TimeoutExpired(
            ["git", "-C", str(self.repo), "status"], 60
        )
        with mock.patch.object(
            factory_lease.subprocess, "run", side_effect=timeout
        ):
            with self.assertRaises(factory_lease.LeaseError):
                factory_lease._git(self.repo, "status")
            out, err = io.StringIO(), io.StringIO()
            with redirect_stdout(out), redirect_stderr(err):
                result = factory_lease.main(
                    [
                        "renew",
                        "--repo",
                        str(self.repo),
                        "--worktree",
                        str(self.lane),
                    ]
                )
        self.assertEqual(result, 1)
        self.assertEqual(out.getvalue(), "")
        self.assertEqual(
            err.getvalue(), "factory lease operation failed\n"
        )
        self.assertNotIn(str(self.repo), err.getvalue())

    def test_cli_canary_has_no_identity_output_on_success_or_failure(self):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            result = factory_lease.main(
                [
                    "create",
                    "--repo",
                    str(self.repo),
                    "--worktree",
                    str(self.lane),
                    "--creator",
                    "lane_new",
                    "--branch-created",
                    "agents/proof",
                ]
            )
        self.assertEqual(result, 0)
        self.assertEqual((out.getvalue(), err.getvalue()), ("", ""))
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            result = factory_lease.main(
                [
                    "create",
                    "--repo",
                    str(self.repo),
                    "--worktree",
                    str(self.lane),
                    "--creator",
                    "lane_new",
                    "--branch-created",
                    "agents/proof",
                ]
            )
        self.assertEqual(result, 1)
        self.assertEqual(out.getvalue(), "")
        self.assertEqual(
            err.getvalue(), "factory lease operation failed\n"
        )
        self.assertNotIn(str(self.repo), err.getvalue())
        self.assertNotIn(str(self.lane), err.getvalue())

    def test_lease_writes_and_commands_cross_only_recorded_boundaries(self):
        identity = self.identity
        binding = factory_lease.inspect_worktree(self.lane, identity)
        writes = []
        commands = []
        original_record = self.store._write_record
        original_nonce = self.store._write_nonce
        original_run = subprocess.run

        def record(record):
            destination = self.store._record_file(
                record["class"], record["lease_id"]
            )
            self.assertTrue(
                factory_lease.path_is_within(
                    destination, identity.common_dir / "factory"
                )
            )
            writes.append(("record", destination))
            return original_record(record)

        def nonce(path, lease_id):
            self.assertEqual(path, binding.nonce_path)
            writes.append(("nonce", path))
            return original_nonce(path, lease_id)

        def run(command, **values):
            commands.append(tuple(str(value) for value in command))
            if (
                command[0] != "git"
                or "-C" not in command
                or any(
                    value
                    in (
                        "fetch",
                        "prune",
                        "clean",
                        "reset",
                        "checkout",
                        "config",
                    )
                    for value in command
                )
            ):
                raise AssertionError("denied command boundary")
            return original_run(command, **values)

        with mock.patch.object(
            self.store, "_write_record", side_effect=record
        ), mock.patch.object(
            self.store, "_write_nonce", side_effect=nonce
        ), mock.patch.object(factory_lease.subprocess, "run", side_effect=run):
            self.store.create_worktree(
                self.lane,
                "lane_new",
                task="boundary",
                branch_created="agents/proof",
            )
            with self.assertRaises(AssertionError):
                nonce(self.root / "denied" / "nonce", "f" * 32)
            with self.assertRaises(AssertionError):
                record({"class": "../../../denied", "lease_id": "f" * 32})
        self.assertEqual(
            sorted(kind for kind, _path in writes),
            ["nonce", "record", "record"],
        )
        self.assertTrue(commands)
        with self.assertRaisesRegex(
            AssertionError, "denied command boundary"
        ):
            run(["git", "-C", str(self.repo), "clean", "-fd"])
        denied_store = self.root / "denied" / "record.json"
        self.assertFalse(
            factory_lease.path_is_within(
                denied_store, identity.common_dir / "factory"
            )
        )


if __name__ == "__main__":
    unittest.main()
