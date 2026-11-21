"""Archive-only factory cleanup preserves subjects and verifies restoration."""

from __future__ import annotations

import contextlib
import hashlib
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
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import factory  # noqa: E402
import factory_cleanup  # noqa: E402
import factory_lease  # noqa: E402


NOW = 2_000_000_000
REPOSITORY = "fixture/project"
BRANCH = "lanes/archive-proof"


class PositivePullRequests(factory_lease.PullRequestProvider):
    repository = REPOSITORY

    def __init__(self, items):
        self.items = tuple(items)
        self.calls = 0

    def list_for_branch(self, repository, branch):
        self.calls += 1
        return self.items


class CompleteExternal(factory_cleanup.ExternalProvider):
    def __init__(self, **changes):
        values = {
            "complete": True,
            "t3_owned": False,
            "thread_active": False,
            "devcap_active": False,
        }
        values.update(changes)
        self.value = factory_cleanup.ExternalObservation(**values)
        self.calls = 0

    def observe(self, repo, path, binding, record):
        self.calls += 1
        return self.value


class CompleteProcesses(factory.ProcessProvider):
    def __init__(self, **changes):
        values = {
            "pids": frozenset(),
            "cwds": (),
            "starts": {},
            "pgids": frozenset(),
        }
        values.update(changes)
        self.value = factory.ProcessObservation(**values)
        self.calls = 0

    def inventory(self):
        self.calls += 1
        return self.value


class CleanupFixture:
    def __init__(self, case):
        self.case = case
        self.temporary = tempfile.TemporaryDirectory()
        case.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.origin = self.root / "origin.git"
        self.repo = self.root / "primary"
        self.other_clone = self.root / "secondary"
        self.lane = self.root / "lane"
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_AUTHOR_NAME": "fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
            "LC_ALL": "C",
        }
        self.git(self.root, "init", "-q", "--bare", "-b", "main", str(self.origin))
        self.git(self.root, "clone", "-q", str(self.origin), str(self.repo))
        self.git(self.root, "clone", "-q", str(self.origin), str(self.other_clone))
        (self.repo / ".gitignore").write_text(
            "build/research/\nbuild/evidence/\nbuild/handoff/\nbuild/review/\n"
            "build/output/\n",
            encoding="utf-8",
        )
        (self.repo / "tracked.txt").write_text("base\n", encoding="utf-8")
        (self.repo / "delete.txt").write_text("delete me\n", encoding="utf-8")
        (self.repo / "run.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        os.chmod(self.repo / "run.sh", 0o755)
        (self.repo / "target.txt").write_text("target\n", encoding="utf-8")
        (self.repo / "link").symlink_to("target.txt")
        self.git(self.repo, "add", "-A")
        self.git(self.repo, "commit", "-qm", "base")
        self.git(self.repo, "push", "-q", "-u", "origin", "main")
        self.git(
            self.repo,
            "remote",
            "set-url",
            "origin",
            "https://github.com/%s.git" % REPOSITORY,
        )
        self.git(
            self.repo,
            "worktree",
            "add",
            "-q",
            "-b",
            BRANCH,
            str(self.lane),
            "main",
        )
        (self.lane / "tracked.txt").write_text(
            "lane commit\n", encoding="utf-8"
        )
        self.git(self.lane, "add", "tracked.txt")
        self.git(self.lane, "commit", "-qm", "lane")
        self.lane_head = self.git(self.lane, "rev-parse", "HEAD")
        self.identity = factory_lease.discover_repository(self.repo)
        self.store = factory_lease.LeaseStore(self.identity, now=NOW)
        worktree_id, branch_id = self.store.create_worktree(
            self.lane,
            "lane_new",
            task="fixture",
            branch_created=BRANCH,
        )
        pull = factory_lease.PullRequestEvidence(
            17,
            REPOSITORY,
            "main",
            BRANCH,
            "MERGED",
            self.lane_head,
            NOW,
        )
        self.pulls = PositivePullRequests((pull,))
        self.store.reconcile(branch_id, provider=self.pulls)
        records, invalid = self.store.read_records()
        case.assertEqual(invalid, 0)
        self.expiry = max(record["expires"] for record in records)
        self.now = self.expiry + 1
        self.worktree_id = worktree_id
        self.branch_id = branch_id
        self.processes = CompleteProcesses()
        self.external = CompleteExternal()
        self.before = self.subject_snapshot()

    def git(self, cwd, *arguments):
        return subprocess.run(
            ["git", *arguments],
            cwd=str(cwd),
            env=self.env,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    def make_archive_changes(self):
        (self.lane / "tracked.txt").write_text(
            "staged index\n", encoding="utf-8"
        )
        self.git(self.lane, "add", "tracked.txt")
        (self.lane / "tracked.txt").write_text(
            "unstaged work\n", encoding="utf-8"
        )
        (self.lane / "delete.txt").unlink()
        os.chmod(self.lane / "run.sh", 0o700)
        (self.lane / "untracked").write_text("new leaf\n", encoding="utf-8")
        (self.lane / "build" / "research" / "nested").mkdir(
            parents=True, exist_ok=True
        )
        (self.lane / "build" / "research" / "one").write_text(
            "evidence one\n", encoding="utf-8"
        )
        (
            self.lane
            / "build"
            / "research"
            / "nested"
            / "two"
        ).write_text("evidence two\n", encoding="utf-8")
        (self.lane / "link").unlink()
        (self.lane / "link").symlink_to("untracked")

    def subject_snapshot(self):
        values = {}
        for base, directories, files in os.walk(
            self.lane, followlinks=False
        ):
            directories.sort()
            files.sort()
            base_path = Path(base)
            for name in directories + files:
                path = base_path / name
                relative = path.relative_to(self.lane).as_posix()
                if relative == ".git" or relative.startswith(".git/"):
                    continue
                info = path.lstat()
                if stat.S_ISLNK(info.st_mode):
                    values[relative] = ("link", os.readlink(path))
                elif stat.S_ISDIR(info.st_mode):
                    values[relative] = ("directory", stat.S_IMODE(info.st_mode))
                else:
                    values[relative] = (
                        "file",
                        stat.S_IMODE(info.st_mode),
                        path.read_bytes(),
                    )
        worktree_list = self.git(self.repo, "worktree", "list", "--porcelain")
        refs = self.git(
            self.repo,
            "for-each-ref",
            "--format=%(refname)%00%(objectname)",
            "refs/heads",
        )
        lease = {
            path.relative_to(self.store.root).as_posix(): path.read_bytes()
            for path in self.store.root.rglob("*")
            if path.is_file()
            and not any(
                part in ("plans", "staging", "archive")
                for part in path.relative_to(self.store.root).parts
            )
        }
        return {
            "tree": values,
            "worktrees": worktree_list,
            "refs": refs,
            "lease": lease,
            "index": (Path(
                self.git(self.lane, "rev-parse", "--git-path", "index")
            )).read_bytes(),
        }

    def args(self):
        return {
            "now": self.now,
            "pr_provider": self.pulls,
            "process_provider": self.processes,
            "external_provider": self.external,
        }

    def plan(self):
        result = factory_cleanup.plan_cleanup(self.repo, **self.args())
        self.case.assertEqual((result.planned, result.held), (1, 0))
        return result

    def apply(self, result):
        return factory_cleanup.apply_cleanup(
            self.repo,
            result.plan_path,
            result.digest,
            **self.args(),
        )


class ArchiveProofTests(unittest.TestCase):
    def setUp(self):
        self.fixture = CleanupFixture(self)
        self.fixture.make_archive_changes()
        self.before = self.fixture.subject_snapshot()

    def test_positive_archive_restore_replay_and_preservation(self):
        result = self.fixture.plan()
        applied = self.fixture.apply(result)
        self.assertEqual((applied.archived, applied.held, applied.replay), (1, 0, False))
        self.assertEqual(self.fixture.subject_snapshot(), self.before)
        replay = self.fixture.apply(result)
        self.assertEqual((replay.archived, replay.held, replay.replay), (1, 0, True))
        archives = tuple(
            (self.fixture.store.root / "archive").iterdir()
        )
        self.assertEqual(len(archives), 1)
        receipt = json.loads((archives[0] / "receipt.json").read_text())
        self.assertEqual(receipt["outcomes"][0]["outcome"], "archived")

    def test_restore_preserves_index_worktree_and_ignored_leaves(self):
        result = self.fixture.plan()
        self.fixture.apply(result)
        expected = json.loads(result.plan_path.read_text())["candidates"][0][
            "expected"
        ]
        archive = self.fixture.store.root / "archive" / result.digest
        candidate = archive / self.fixture.worktree_id / "1"
        restored = archive / "proof-restore"
        factory_cleanup._restore_archive(candidate, restored, expected)
        factory_cleanup._verify_restore(restored, expected)
        self.assertEqual(
            subprocess.run(
                ["git", "-C", str(restored), "status", "--porcelain=v1"],
                check=True,
                capture_output=True,
                text=True,
                env=self.fixture.env,
            ).stdout,
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(self.fixture.lane),
                    "status",
                    "--porcelain=v1",
                ],
                check=True,
                capture_output=True,
                text=True,
                env=self.fixture.env,
            ).stdout,
        )
        self.assertEqual(
            (restored / "build" / "research" / "one").read_text(),
            "evidence one\n",
        )
        self.assertEqual(
            (
                restored
                / "build"
                / "research"
                / "nested"
                / "two"
            ).read_text(),
            "evidence two\n",
        )
        staged_oid = self.fixture.git(
            self.fixture.lane, "rev-parse", ":tracked.txt"
        )
        restored_oid = subprocess.run(
            ["git", "-C", str(restored), "rev-parse", ":tracked.txt"],
            check=True,
            capture_output=True,
            text=True,
            env=self.fixture.env,
        ).stdout.strip()
        self.assertEqual(restored_oid, staged_oid)
        restored_blob = subprocess.run(
            ["git", "-C", str(restored), "cat-file", "blob", staged_oid],
            check=True,
            capture_output=True,
            env=self.fixture.env,
        ).stdout
        self.assertEqual(restored_blob, b"staged index\n")

    def test_unselected_ignored_and_special_content_hold(self):
        (self.fixture.lane / "build" / "output").mkdir(parents=True)
        (self.fixture.lane / "build" / "output" / "object").write_text(
            "artifact"
        )
        result = factory_cleanup.plan_cleanup(
            self.fixture.repo, **self.fixture.args()
        )
        self.assertEqual((result.planned, result.held, result.unknown), (0, 1, 0))
        fifo = self.fixture.lane / "special"
        os.mkfifo(fifo)
        result = factory_cleanup.plan_cleanup(
            self.fixture.repo, **self.fixture.args()
        )
        self.assertEqual(result.planned, 0)


class FailureAndRestoreProofTests(unittest.TestCase):
    def _fresh(self):
        fixture = CleanupFixture(self)
        fixture.make_archive_changes()
        result = fixture.plan()
        before = fixture.subject_snapshot()
        return fixture, result, before

    def test_01_failures_leave_no_archive_or_success_receipt(self):
        failure_points = (
            (
                "_capture_expected",
                lambda original: (
                    lambda binding, payload_dir=None: (
                        (_ for _ in ()).throw(
                            factory_cleanup.CleanupError("archive_failed")
                        )
                        if payload_dir is not None
                        else original(binding, payload_dir)
                    )
                ),
            ),
            (
                "_write_all",
                lambda original: (
                    lambda descriptor, data: (
                        (_ for _ in ()).throw(
                            factory_cleanup.CleanupError("archive_failed")
                        )
                    )
                ),
            ),
            (
                "_bundle",
                lambda original: (
                    lambda binding, candidate_dir: (
                        (_ for _ in ()).throw(
                            factory_cleanup.CleanupError("bundle_failed")
                        )
                    )
                ),
            ),
            (
                "os.rename",
                lambda original: (
                    lambda source, destination: (
                        (_ for _ in ()).throw(
                            OSError("synthetic publish failure")
                        )
                    )
                ),
            ),
        )
        for symbol, replacement in failure_points:
            with self.subTest(symbol=symbol):
                fixture, result, before = self._fresh()
                owner = factory_cleanup
                attribute = symbol
                if symbol == "os.rename":
                    owner = os
                    attribute = "rename"
                original = getattr(owner, attribute)
                with mock.patch.object(owner, attribute, replacement(original)):
                    with self.assertRaises(factory_cleanup.CleanupError):
                        fixture.apply(result)
                self.assertEqual(fixture.subject_snapshot(), before)
                archive = fixture.store.root / "archive"
                self.assertTrue(
                    not archive.exists() or tuple(archive.iterdir()) == ()
                )
                if archive.exists():
                    self.assertFalse(any(
                        child.name == result.digest for child in archive.iterdir()
                    ))

    def test_02_omitted_payload_and_manifest_are_rejected(self):
        fixture, result, _before = self._fresh()
        fixture.apply(result)
        candidate = (
            fixture.store.root
            / "archive"
            / result.digest
            / fixture.worktree_id
            / "1"
        )
        manifest_path = candidate / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        omitted = manifest["files"].pop(0)
        (candidate / "files" / omitted["payload"]).unlink()
        manifest_path.write_text(
            json.dumps(
                manifest,
                sort_keys=True,
                separators=(",", ":"),
                ensure_ascii=True,
            )
            + "\n"
        )
        os.chmod(manifest_path, 0o600)
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "archive_manifest"
        ):
            factory_cleanup._restore_archive(
                candidate,
                fixture.store.root / "archive" / result.digest / "restored",
                manifest["expected"],
            )

    def test_03_restore_rejects_each_tamper_without_outside_writes(self):
        original_fixture = self._fresh()
        fixture, result, _before = original_fixture
        fixture.apply(result)
        source = (
            fixture.store.root
            / "archive"
            / result.digest
            / fixture.worktree_id
            / "1"
        )
        expected = json.loads(result.plan_path.read_text())["candidates"][0][
            "expected"
        ]
        sentinel = fixture.root / "outside-sentinel"
        sentinel.write_bytes(b"outside")

        def clone(name):
            target = fixture.store.root / "staging" / name
            shutil.copytree(source, target)
            return target

        flipped = clone("flipped")
        payload = sorted((flipped / "files").iterdir())[0]
        raw = bytearray(payload.read_bytes())
        raw[0] ^= 1
        payload.write_bytes(raw)
        with self.assertRaises(factory_cleanup.CleanupError):
            factory_cleanup._restore_archive(
                flipped, fixture.store.root / "staging" / "restore-flipped", expected
            )

        omitted = clone("omitted")
        (omitted / "commits.bundle").unlink()
        with self.assertRaises(factory_cleanup.CleanupError):
            factory_cleanup._restore_archive(
                omitted, fixture.store.root / "staging" / "restore-omitted", expected
            )

        parent_link = clone("parent-link")
        manifest_path = parent_link / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["expected"]["entries"][0]["path"] = "../outside-sentinel"
        manifest_path.write_bytes(factory_cleanup._canonical_bytes(manifest))
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "archive_manifest|input_path"
        ):
            factory_cleanup._restore_archive(
                parent_link,
                fixture.store.root / "staging" / "restore-parent",
                expected,
            )
        self.assertEqual(sentinel.read_bytes(), b"outside")


class IdentityHeadProcessLeaseProofTests(unittest.TestCase):
    def setUp(self):
        self.fixture = CleanupFixture(self)
        self.fixture.make_archive_changes()

    def _held_reason(self, result, **changes):
        applied = factory_cleanup.apply_cleanup(
            self.fixture.repo,
            result.plan_path,
            result.digest,
            **dict(self.fixture.args(), **changes),
        )
        receipt = json.loads(
            (
                self.fixture.store.root
                / "archive"
                / result.digest
                / "receipt.json"
            ).read_text()
        )
        self.assertEqual(applied.held, 1)
        return receipt["outcomes"][0]["reason"]

    def test_04_leaf_and_ancestor_replacement_never_archives_outside_bytes(self):
        leaf_fixture = self.fixture
        result = leaf_fixture.plan()
        sentinel = leaf_fixture.root / "leaf-sentinel"
        sentinel.write_bytes(b"sentinel")
        before = (leaf_fixture.lane / "untracked").read_bytes()
        (leaf_fixture.lane / "untracked").unlink()
        (leaf_fixture.lane / "untracked").symlink_to(sentinel)
        self.assertEqual(self._held_reason(result), "tree_changed")
        self.assertEqual(sentinel.read_bytes(), b"sentinel")
        archive = leaf_fixture.store.root / "archive" / result.digest
        self.assertFalse(
            any(b"sentinel" in path.read_bytes()
                for path in archive.rglob("*")
                if path.is_file())
        )
        self.assertNotEqual((leaf_fixture.lane / "untracked").read_bytes(), before)

        ancestor_fixture = CleanupFixture(self)
        ancestor_result = ancestor_fixture.plan()
        moved = ancestor_fixture.root / "moved-lane"
        os.rename(ancestor_fixture.lane, moved)
        outside = ancestor_fixture.root / "outside"
        outside.mkdir()
        (outside / "private").write_bytes(b"private")
        ancestor_fixture.lane.symlink_to(outside, target_is_directory=True)
        applied = factory_cleanup.apply_cleanup(
            ancestor_fixture.repo,
            ancestor_result.plan_path,
            ancestor_result.digest,
            **ancestor_fixture.args(),
        )
        self.assertEqual(applied.held, 1)
        self.assertEqual((outside / "private").read_bytes(), b"private")

    def test_04_recreated_same_inode_with_different_bytes_is_tree_changed(self):
        result = self.fixture.plan()
        (self.fixture.lane / "untracked").write_bytes(b"replacement")
        old_inspect = factory_cleanup.factory_lease.inspect_worktree

        def same_inode(path, identity):
            binding = old_inspect(path, identity)
            return factory_lease.WorktreeBinding(
                path=binding.path,
                device=result and binding.device,
                inode=json.loads(result.plan_path.read_text())["candidates"][0][
                    "binding"
                ]["inode"],
                branch=binding.branch,
                head=binding.head,
                gitfile=binding.gitfile,
                admin_dir=binding.admin_dir,
                backpointer=binding.backpointer,
                nonce_path=binding.nonce_path,
                common_dir=binding.common_dir,
            )

        with mock.patch.object(
            factory_cleanup.factory_lease,
            "inspect_worktree",
            same_inode,
        ):
            self.assertEqual(self._held_reason(result), "tree_changed")
        self.assertEqual(
            (self.fixture.lane / "untracked").read_bytes(), b"replacement"
        )

    def test_05_commit_reset_branch_ref_and_same_tip_checkout_preserve_refs(self):
        for change in ("commit", "reset", "switch", "ref"):
            with self.subTest(change=change):
                fixture = CleanupFixture(self)
                fixture.make_archive_changes()
                result = fixture.plan()
                if change == "commit":
                    (fixture.lane / "after-plan").write_text("commit")
                    fixture.git(fixture.lane, "add", "after-plan")
                    fixture.git(fixture.lane, "commit", "-qm", "after plan")
                elif change == "reset":
                    fixture.git(fixture.lane, "reset", "--soft", "HEAD^")
                elif change == "switch":
                    fixture.git(fixture.repo, "branch", "lanes/same-tip", fixture.lane_head)
                    fixture.git(
                        fixture.lane,
                        "switch",
                        "lanes/same-tip",
                    )
                else:
                    fixture.git(
                        fixture.repo,
                        "branch",
                        "lanes/attached-same-tip",
                        fixture.lane_head,
                    )
                    fixture.git(
                        fixture.repo,
                        "update-ref",
                        "refs/heads/" + BRANCH,
                        fixture.lane_head,
                    )
                refs = fixture.git(
                    fixture.repo,
                    "for-each-ref",
                    "--format=%(refname)%00%(objectname)",
                    "refs/heads",
                )
                applied = fixture.apply(result)
                self.assertEqual(applied.held, 0 if change == "ref" else 1)
                self.assertEqual(
                    fixture.git(
                        fixture.repo,
                        "for-each-ref",
                        "--format=%(refname)%00%(objectname)",
                        "refs/heads",
                    ),
                    refs,
                )

    def test_06_process_revalidation_and_partial_sources_hold_without_signals(self):
        result = self.fixture.plan()
        with mock.patch("os.kill", side_effect=AssertionError), mock.patch(
            "os.killpg", side_effect=AssertionError
        ):
            reason = self._held_reason(
                result,
                process_provider=CompleteProcesses(
                    cwds=(self.fixture.lane / "child",),
                    pids=frozenset({9876}),
                    starts={9876: "synthetic start"},
                    pgids=frozenset({9876}),
                ),
            )
        self.assertIn(reason, ("class_live_process", "class_active_hold"))

        partial_fixture = CleanupFixture(self)
        partial_fixture.make_archive_changes()
        partial_result = partial_fixture.plan()
        partial = CompleteProcesses(cwds=None, starts=None, pgids=None)
        applied = factory_cleanup.apply_cleanup(
            partial_fixture.repo,
            partial_result.plan_path,
            partial_result.digest,
            **dict(partial_fixture.args(), process_provider=partial),
        )
        self.assertEqual(applied.held, 1)

    def test_07_live_expired_and_new_generation_leases_hold(self):
        result = self.fixture.plan()
        newer = factory_lease.LeaseStore(
            self.fixture.identity, now=self.fixture.now
        )
        newer.renew_worktree(self.fixture.lane, BRANCH)
        records, invalid = newer.read_records()
        self.assertEqual(invalid, 0)
        branch_id = next(
            record["lease_id"]
            for record in records
            if record["class"] == "branch"
        )
        newer.reconcile(branch_id, provider=self.fixture.pulls)
        self.assertEqual(self._held_reason(result), "lease_live")

    def test_07_future_record_is_incomplete_and_never_archived(self):
        result = self.fixture.plan()
        record_path = (
            self.fixture.store.root
            / "leases"
            / "worktree"
            / (self.fixture.worktree_id + ".json")
        )
        record = json.loads(record_path.read_text())
        record["renewed"] = self.fixture.now + 1
        record["expires"] = record["renewed"] + factory_lease.LEASE_TTL_SECONDS
        record_path.write_text(json.dumps(record, sort_keys=True) + "\n")
        self.assertIn(
            self._held_reason(result), ("lease_changed", "lease_unknown")
        )


class OwnershipExternalConcurrencyProofTests(unittest.TestCase):
    def setUp(self):
        self.fixture = CleanupFixture(self)
        self.fixture.make_archive_changes()

    def test_08_ownership_t3_protection_and_clone_isolation(self):
        for external in (
            CompleteExternal(t3_owned=True),
            CompleteExternal(thread_active=True),
            CompleteExternal(complete=False),
            CompleteExternal(devcap_active=True),
        ):
            with self.subTest(external=external.value):
                fixture = CleanupFixture(self)
                fixture.make_archive_changes()
                result = factory_cleanup.plan_cleanup(
                    fixture.repo,
                    **dict(fixture.args(), external_provider=external),
                )
                self.assertEqual(result.planned, 0)
                self.assertGreater(result.held, 0)
        record = self.fixture.store.read_records()[0][0]
        self.assertTrue(
            any(
                candidate["class"] == "worktree"
                for candidate in self.fixture.store.read_records()[0]
            )
        )
        sibling = factory_cleanup.plan_cleanup
        with self.assertRaises(factory_lease.LeaseError):
            sibling(
                self.fixture.other_clone,
                **self.fixture.args(),
            )

    def test_08_invalid_duplicate_and_missing_leases_are_not_candidates(self):
        mutations = ("missing", "duplicate", "corrupt")
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                fixture = CleanupFixture(self)
                fixture.make_archive_changes()
                record_path = (
                    fixture.store.root
                    / "leases"
                    / "worktree"
                    / (fixture.worktree_id + ".json")
                )
                if mutation == "missing":
                    record_path.unlink()
                elif mutation == "duplicate":
                    duplicate = (
                        record_path.parent
                        / ("f" * 32 + ".json")
                    )
                    duplicate.write_bytes(record_path.read_bytes())
                else:
                    record_path.write_text("{broken")
                result = factory_cleanup.plan_cleanup(
                    fixture.repo, **fixture.args()
                )
                self.assertEqual(result.planned, 0)
                self.assertEqual(result.held, 1)

    def test_08_clean_and_dirty_controls_each_have_one_archive_only_plan(self):
        clean = CleanupFixture(self)
        result = factory_cleanup.plan_cleanup(clean.repo, **clean.args())
        self.assertEqual(result.planned, 1)
        dirty = json.loads(result.plan_path.read_text())["candidates"][0]
        self.assertEqual(dirty["action"], "archive_only")
        self.assertNotIn("ignored", dirty["expected"])

        dirty_fixture = CleanupFixture(self)
        dirty_fixture.make_archive_changes()
        dirty_result = dirty_fixture.plan()
        self.assertEqual(
            json.loads(dirty_result.plan_path.read_text())["candidates"][0][
                "action"
            ],
            "archive_only",
        )

    def test_09_real_subprocess_lock_and_replay_have_one_publication(self):
        result = self.fixture.plan()
        plan_value = json.loads(result.plan_path.read_text())
        head = plan_value["candidates"][0]["release"]["head_oid"]
        child_code = """
import json
import sys
from pathlib import Path
sys.path.insert(0, %r)
import factory
import factory_cleanup
import factory_lease

class Pulls(factory_lease.PullRequestProvider):
    repository = %r
    def list_for_branch(self, repository, branch):
        return (factory_lease.PullRequestEvidence(17, repository, "main", branch, "MERGED", %r, %r),)

class Processes(factory.ProcessProvider):
    def inventory(self):
        return factory.ProcessObservation(frozenset(), (), {}, frozenset())

class External(factory_cleanup.ExternalProvider):
    def observe(self, repo, path, binding, record):
        return factory_cleanup.ExternalObservation(True, False, False, False)

def locked():
    print("locked", flush=True)
    sys.stdin.readline()

result = factory_cleanup.apply_cleanup(
    Path(%r), Path(%r), %r, now=%r, pr_provider=Pulls(),
    process_provider=Processes(), external_provider=External(),
    lock_hook=locked)
print("done", flush=True)
""" % (
            str(TOOLS),
            REPOSITORY,
            head,
            NOW,
            str(self.fixture.repo),
            str(result.plan_path),
            result.digest,
            self.fixture.now,
        )
        child = subprocess.Popen(
            [sys.executable, "-c", child_code],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=self.fixture.env,
        )
        self.addCleanup(
            lambda: child.poll() is None and child.terminate()
        )
        self.assertEqual(child.stdout.readline().strip(), "locked")
        with self.assertRaisesRegex(factory_cleanup.CleanupError, "busy"):
            self.fixture.apply(result)
        writer_code = """
import sys
sys.path.insert(0, %r)
from pathlib import Path
import factory_lease
identity = factory_lease.discover_repository(Path(%r))
try:
    with factory_lease.LeaseStore(identity, now=%r).writer_lock():
        print("acquired", flush=True)
except factory_lease.LockBusy:
    print("busy", flush=True)
""" % (str(TOOLS), str(self.fixture.repo), self.fixture.now)
        writer = subprocess.run(
            [sys.executable, "-c", writer_code],
            capture_output=True,
            text=True,
            env=self.fixture.env,
            check=True,
        )
        self.assertEqual(writer.stdout.strip(), "busy")
        child.stdin.write("\n")
        child.stdin.flush()
        self.assertEqual(child.stdout.readline().strip(), "done")
        self.assertEqual(child.wait(timeout=10), 0, child.stderr.read())
        child.stdin.close()
        child.stdout.close()
        child.stderr.close()
        replay = self.fixture.apply(result)
        self.assertTrue(replay.replay)
        self.assertEqual(
            len(tuple((self.fixture.store.root / "archive").iterdir())), 1
        )

    def test_12_late_writes_survive_and_never_trigger_destructive_work(self):
        mutations = ("tracked", "untracked", "ignored", "commit", "marker", "build")
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                fixture = CleanupFixture(self)
                fixture.make_archive_changes()
                result = fixture.plan()
                calls = []
                original_run = factory_cleanup._run

                def instrument(command, cwd=None, input_bytes=None):
                    calls.append(tuple(command))
                    return original_run(command, cwd, input_bytes)

                def late(stage, source, destination):
                    if stage != "before_publish":
                        return
                    if mutation == "tracked":
                        (fixture.lane / "tracked.txt").write_text("late tracked")
                    elif mutation == "untracked":
                        (fixture.lane / "late").write_text("late untracked")
                    elif mutation == "ignored":
                        (fixture.lane / "build" / "research").mkdir(
                            parents=True, exist_ok=True
                        )
                        (fixture.lane / "build" / "research" / "late").write_text(
                            "late ignored"
                        )
                    elif mutation == "commit":
                        (fixture.lane / "late-commit").write_text("late commit")
                        fixture.git(fixture.lane, "add", "late-commit")
                        fixture.git(fixture.lane, "commit", "-qm", "late")
                    elif mutation == "marker":
                        (fixture.lane / "build" / "runs").mkdir(
                            parents=True, exist_ok=True
                        )
                        (
                            fixture.lane / "build" / "runs" / "late.running"
                        ).write_text("{}")
                    else:
                        (fixture.lane / "build" / "output").mkdir(
                            parents=True, exist_ok=True
                        )
                        (fixture.lane / "build" / "output" / "late").write_text(
                            "late output"
                        )

                with mock.patch.object(factory_cleanup, "_run", instrument):
                    applied = factory_cleanup.apply_cleanup(
                        fixture.repo,
                        result.plan_path,
                        result.digest,
                        publish_hook=late,
                        **fixture.args(),
                    )
                self.assertEqual(applied.archived, 1)
                self.assertTrue(fixture.lane.exists())
                self.assertFalse(any(
                    "remove" in command
                    or "prune" in command
                    or "--force" in command
                    for command in calls
                ))
                self.assertTrue(
                    fixture.git(
                        fixture.repo, "rev-parse", "refs/heads/" + BRANCH
                    )
                )

    def test_13_changed_external_and_pr_evidence_is_read_again(self):
        result = self.fixture.plan()
        cases = (
            ("thread_active", CompleteExternal(thread_active=True), self.fixture.pulls),
            ("pr_missing", self.fixture.external, PositivePullRequests(())),
            (
                "open",
                self.fixture.external,
                PositivePullRequests(
                    (
                        factory_lease.PullRequestEvidence(
                            19,
                            REPOSITORY,
                            "main",
                            BRANCH,
                            "OPEN",
                            self.fixture.lane_head,
                            NOW,
                        ),
                    )
                ),
            ),
            (
                "pr_stale",
                self.fixture.external,
                PositivePullRequests(
                    (
                        factory_lease.PullRequestEvidence(
                            18,
                            REPOSITORY,
                            "main",
                            BRANCH,
                            "MERGED",
                            self.fixture.lane_head,
                            NOW,
                        ),
                    )
                ),
            ),
        )
        for label, external, pulls in cases:
            with self.subTest(reason=label):
                applied = factory_cleanup.apply_cleanup(
                    self.fixture.repo,
                    result.plan_path,
                    result.digest,
                    **dict(
                        self.fixture.args(),
                        external_provider=external,
                        pr_provider=pulls,
                    ),
                )
                self.assertEqual(applied.held, 1)
                receipt = json.loads(
                    (
                        self.fixture.store.root
                        / "archive"
                        / result.digest
                        / "receipt.json"
                    ).read_text()
                )
                expected_reason = {
                    "thread_active": "thread_active",
                    "open": "open_successor",
                }.get(label, "pr_changed")
                self.assertEqual(receipt["outcomes"][0]["reason"], expected_reason)
                (self.fixture.store.root / "archive" / result.digest).rename(
                    self.fixture.store.root / "archive" / (result.digest + "-" + label)
                )


class IntegrationInputBoundaryPlatformProofTests(unittest.TestCase):
    def test_10_11_scoped_production_observation_and_order_are_deterministic(self):
        fixture = CleanupFixture(self)
        fixture.make_archive_changes()
        original = factory.GitReader.worktrees

        def reversed_worktrees(reader):
            return tuple(reversed(original(reader)))

        with mock.patch.object(factory.GitReader, "worktrees", reversed_worktrees):
            result = factory_cleanup.plan_cleanup(
                fixture.repo, **fixture.args()
            )
        self.assertEqual(result.planned, 1)
        candidate = json.loads(result.plan_path.read_text())["candidates"][0]
        self.assertEqual(candidate["binding"]["path"], str(fixture.lane))
        self.assertEqual(candidate["action"], "archive_only")

        wrong_target = PositivePullRequests(
            (
                factory_lease.PullRequestEvidence(
                    17,
                    REPOSITORY,
                    "other",
                    BRANCH,
                    "MERGED",
                    fixture.lane_head,
                    NOW,
                ),
            )
        )
        wrong = factory_cleanup.plan_cleanup(
            fixture.repo, **dict(fixture.args(), pr_provider=wrong_target)
        )
        self.assertEqual(wrong.planned, 0)

    def test_10_11_ancestry_only_fresh_base_and_held_parent_never_enter(self):
        ancestry = CleanupFixture(self)
        active = factory_lease.LeaseStore(
            ancestry.identity, now=ancestry.now
        )
        active.renew_worktree(ancestry.lane, BRANCH)
        active.release(ancestry.worktree_id, "ended")
        result = factory_cleanup.plan_cleanup(ancestry.repo, **ancestry.args())
        self.assertEqual(result.planned, 0)

        fresh = CleanupFixture(self)
        fresh_head = fresh.git(fresh.repo, "rev-parse", "main")
        fresh.git(fresh.lane, "checkout", "-B", "lanes/fresh", fresh_head)
        result = factory_cleanup.plan_cleanup(fresh.repo, **fresh.args())
        self.assertEqual(result.planned, 0)

        held_parent = CleanupFixture(self)
        nested = held_parent.lane / "nested-worktree"
        nested_parent = held_parent.repo
        held_parent.git(
            nested_parent,
            "worktree",
            "add",
            "-q",
            "-b",
            "lanes/nested",
            str(nested),
            "main",
        )
        result = factory_cleanup.plan_cleanup(
            held_parent.repo, **held_parent.args()
        )
        self.assertEqual(result.planned, 0)

    def test_14_gate_accepts_only_registered_canonical_recent_exact_plan(self):
        fixture = CleanupFixture(self)
        fixture.make_archive_changes()
        result = fixture.plan()
        value = json.loads(result.plan_path.read_text())
        for age, reason in ((-1, "plan_future"), (86400, "plan_expired")):
            with self.subTest(age=age):
                changed = dict(value)
                changed["created"] = fixture.now - age
                raw = factory_cleanup._canonical_bytes(changed)
                digest = hashlib.sha256(raw).hexdigest()
                path = result.plan_path.parent / (digest + ".json")
                path.write_bytes(raw)
                os.chmod(path, 0o600)
                with self.assertRaisesRegex(
                    factory_cleanup.CleanupError, reason
                ):
                    factory_cleanup.apply_cleanup(
                        fixture.repo,
                        path,
                        digest,
                        **fixture.args(),
                    )
        changed = dict(value)
        changed["created"] = fixture.now - 1
        raw = factory_cleanup._canonical_bytes(changed)
        digest = hashlib.sha256(raw).hexdigest()
        valid = result.plan_path.parent / (digest + ".json")
        valid.write_bytes(raw)
        os.chmod(valid, 0o600)
        applied = factory_cleanup.apply_cleanup(
            fixture.repo, valid, digest, **fixture.args()
        )
        self.assertEqual(applied.archived, 1)

    def test_14_unregistered_subject_passes_input_but_not_identity_gate(self):
        fixture = CleanupFixture(self)
        fixture.make_archive_changes()
        result = fixture.plan()
        moved = fixture.root / "moved-plan-subject"
        os.rename(fixture.lane, moved)
        applied = fixture.apply(result)
        self.assertEqual(applied.held, 1)
        receipt = json.loads(
            (
                fixture.store.root
                / "archive"
                / result.digest
                / "receipt.json"
            ).read_text()
        )
        self.assertEqual(receipt["outcomes"][0]["reason"], "path_changed")

    def test_15_commands_destinations_and_outputs_stay_inside_boundary(self):
        fixture = CleanupFixture(self)
        fixture.make_archive_changes()
        result = fixture.plan()
        writes = []
        original = factory_cleanup._publish_file

        def bounded(path, raw):
            writes.append(Path(path))
            return original(path, raw)

        denied = (
            ("git", "-C", str(fixture.repo), "worktree", "remove", "x"),
            ("git", "-C", str(fixture.repo), "fetch", "origin"),
            ("xcrun", "simctl", "delete", "x"),
            (
                "git",
                "-C",
                str(fixture.repo),
                "config",
                "x.y",
                "z",
            ),
        )
        for command in denied:
            with self.assertRaisesRegex(
                factory_cleanup.CleanupError, "command_denied"
            ):
                factory_cleanup._run(command)
        with mock.patch.object(factory_cleanup, "_publish_file", bounded):
            fixture.apply(result)
        for path in writes:
            self.assertTrue(
                path == fixture.store.root
                or factory.path_is_within(path, fixture.store.root)
            )
        source = Path(factory_cleanup.__file__).read_text()
        self.assertNotIn("tarfile", source)
        self.assertNotIn("os.kill(", source)
        self.assertNotIn("shutil.rmtree", source)

    def test_16_python39_symlink_root_shuffled_rows_and_incomplete_facts(self):
        self.assertGreaterEqual(sys.version_info[:2], (3, 9))
        fixture = CleanupFixture(self)
        fixture.make_archive_changes()
        alias = fixture.root / "primary-alias"
        alias.symlink_to(fixture.repo, target_is_directory=True)
        original = factory.GitReader.worktrees

        def shuffled(reader):
            values = list(original(reader))
            return tuple(reversed(values))

        with mock.patch.object(factory.GitReader, "worktrees", shuffled):
            result = factory_cleanup.plan_cleanup(alias, **fixture.args())
        self.assertEqual(result.planned, 1)
        unknown = CompleteProcesses(cwds=None, starts=None, pgids=None)
        applied = factory_cleanup.apply_cleanup(
            alias,
            result.plan_path,
            result.digest,
            **dict(fixture.args(), process_provider=unknown),
        )
        self.assertEqual(applied.held, 1)

    def test_crash_before_and_after_publish_replays_one_receipt(self):
        fixture = CleanupFixture(self)
        fixture.make_archive_changes()
        result = fixture.plan()
        with self.assertRaises(KeyboardInterrupt):
            factory_cleanup.apply_cleanup(
                fixture.repo,
                result.plan_path,
                result.digest,
                publish_hook=lambda *_args: (_ for _ in ()).throw(
                    KeyboardInterrupt()
                ),
                **fixture.args(),
            )
        self.assertTrue(
            any(
                path.name.startswith(result.digest + "-")
                for path in (fixture.store.root / "staging").iterdir()
            )
        )
        retried = fixture.apply(result)
        self.assertTrue(retried.archived == 1 and not retried.replay)

        def after(stage, _source, _destination):
            if stage == "after_publish":
                raise KeyboardInterrupt()

        second = CleanupFixture(self)
        second_result = second.plan()
        with self.assertRaises(KeyboardInterrupt):
            factory_cleanup.apply_cleanup(
                second.repo,
                second_result.plan_path,
                second_result.digest,
                publish_hook=after,
                **second.args(),
            )
        replay = second.apply(second_result)
        self.assertTrue(replay.replay)



class InputAndBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.fixture = CleanupFixture(self)
        self.result = self.fixture.plan()

    def rewrite_plan(self, transform):
        value = json.loads(self.result.plan_path.read_text())
        transform(value)
        raw = factory_cleanup._canonical_bytes(value)
        self.result.plan_path.write_bytes(raw)
        digest = hashlib.sha256(raw).hexdigest()
        return self.result.plan_path, digest

    def test_input_gate_precedes_candidate_provider_lock_and_writes(self):
        with mock.patch.object(
            self.fixture.store, "read_records", side_effect=AssertionError
        ), mock.patch.object(
            self.fixture.external, "observe", side_effect=AssertionError
        ):
            for approve in ("0" * 64, self.result.digest + "0"):
                with self.subTest(approve=approve):
                    with self.assertRaises(factory_cleanup.CleanupError):
                        factory_cleanup.apply_cleanup(
                            self.fixture.repo,
                            self.result.plan_path,
                            approve,
                            **self.fixture.args(),
                        )

    def test_duplicate_noncanonical_forbidden_and_expired_inputs_fail(self):
        raw = self.result.plan_path.read_bytes()
        with self.assertRaises(factory_cleanup.CleanupError):
            factory_cleanup._strict_json(
                b'{"v":1,"v":1}\n', factory_cleanup.MAX_PLAN_BYTES
            )
        self.result.plan_path.write_bytes(raw.replace(b'":', b'": ', 1))
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "input_digest|input_noncanonical"
        ):
            self.fixture.apply(self.result)
        self.result.plan_path.write_bytes(raw)
        path = self.result.plan_path
        value = json.loads(raw)
        value["action"] = "remove"
        changed = factory_cleanup._canonical_bytes(value)
        path.write_bytes(changed)
        with self.assertRaises(factory_cleanup.CleanupError):
            factory_cleanup.apply_cleanup(
                self.fixture.repo,
                path,
                hashlib.sha256(changed).hexdigest(),
                **self.fixture.args(),
            )
        value["action"] = "archive_only"
        value["created"] = self.fixture.now - 86400
        expired = factory_cleanup._canonical_bytes(value)
        expired_digest = hashlib.sha256(expired).hexdigest()
        expired_path = path.parent / (expired_digest + ".json")
        expired_path.write_bytes(expired)
        os.chmod(expired_path, 0o600)
        with self.assertRaisesRegex(factory_cleanup.CleanupError, "plan_expired"):
            factory_cleanup.apply_cleanup(
                self.fixture.repo,
                expired_path,
                expired_digest,
                **self.fixture.args(),
            )

    def test_linked_out_of_store_plan_and_clone_replay_fail_before_identity(self):
        external = self.fixture.root / "outside-plan"
        shutil.copyfile(self.result.plan_path, external)
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "input_outside_store"
        ):
            factory_cleanup.apply_cleanup(
                self.fixture.repo,
                external,
                self.result.digest,
                **self.fixture.args(),
            )
        linked = self.fixture.store.root / "plans" / "linked.json"
        linked.symlink_to(external)
        with self.assertRaises(factory_cleanup.CleanupError):
            factory_cleanup.apply_cleanup(
                self.fixture.repo,
                linked,
                self.result.digest,
                **self.fixture.args(),
            )
        lexical = (
            self.result.plan_path.parent
            / ".."
            / "plans"
            / self.result.plan_path.name
        )
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "input_path"
        ):
            factory_cleanup.apply_cleanup(
                self.fixture.repo,
                lexical,
                self.result.digest,
                **self.fixture.args(),
            )
        with self.assertRaises(factory_lease.LeaseError):
            factory_cleanup.apply_cleanup(
                self.fixture.other_clone,
                self.result.plan_path,
                self.result.digest,
                **self.fixture.args(),
            )

    def test_output_hides_private_canaries_and_cli_has_only_two_commands(self):
        canary = "/synthetic/private-name pid-913"
        stdout = io.StringIO()
        stderr = io.StringIO()
        previous = Path.cwd()
        try:
            os.chdir(self.fixture.repo)
            with contextlib.redirect_stdout(
                stdout
            ), contextlib.redirect_stderr(stderr):
                code = factory_cleanup.main(["plan"])
        finally:
            os.chdir(previous)
        self.assertNotIn(canary, stdout.getvalue() + stderr.getvalue())
        self.assertIn("result=", stdout.getvalue() + stderr.getvalue())
        parser = factory_cleanup._parser()
        self.assertEqual(parser.parse_args(["plan"]).command, "plan")
        with self.assertRaises(factory_cleanup.CleanupError):
            parser.parse_args(["remove"])


def _runner(command, cwd=None):
    return subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=True,
    )


if __name__ == "__main__":
    unittest.main()
