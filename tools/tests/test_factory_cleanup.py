"""Archive-only factory cleanup preserves subjects and verifies restoration."""

from __future__ import annotations

import base64
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
    def __init__(self, case, canary=None):
        self.case = case
        self.temporary = tempfile.TemporaryDirectory()
        case.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.origin = self.root / "origin.git"
        self.repo = self.root / "primary"
        self.other_clone = self.root / "secondary"
        self.canary = canary
        self.task = ("task-" + canary) if canary is not None else "fixture"
        self.lane = self.root / (
            ("lane-" + canary) if canary is not None else "lane"
        )
        self.branch = (
            BRANCH + "-" + canary if canary is not None else BRANCH
        )
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
        (self.repo / "tools" / "triage").mkdir(parents=True)
        (self.repo / "tools" / "triage" / "config.json").write_text(
            '{"workflow_base":"main"}\n', encoding="utf-8"
        )
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
        self.git(self.other_clone, "fetch", "-q", "origin", "main")
        self.git(
            self.other_clone,
            "checkout",
            "-q",
            "-b",
            "main",
            "origin/main",
        )
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
            self.branch,
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
            task=self.task,
            branch_created=self.branch,
        )
        pull = factory_lease.PullRequestEvidence(
            17,
            REPOSITORY,
            "main",
            self.branch,
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
        other_identity = factory_lease.discover_repository(self.other_clone)
        self.other_store = factory_lease.LeaseStore(other_identity, now=NOW)
        with self.other_store.writer_lock():
            pass
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

    def git_snapshot(self):
        return {
            "config": self.git(
                self.repo, "config", "--local", "--list", "--show-origin"
            ),
            "refs": self.git(
                self.repo,
                "for-each-ref",
                "--format=%(refname)%00%(objectname)",
                "refs/heads",
            ),
            "worktrees": self.git(
                self.repo, "worktree", "list", "--porcelain"
            ),
            "subject": self.subject_snapshot(),
        }

    def args(self):
        return {
            "now": self.now,
            "pr_provider": self.pulls,
            "process_provider": self.processes,
            "external_provider": self.external,
        }

    def write_records(self, transform):
        for record in self.store.read_records()[0]:
            changed = transform(dict(record))
            if changed is None:
                continue
            path = (
                self.store.root
                / "leases"
                / record["class"]
                / (record["lease_id"] + ".json")
            )
            path.write_bytes(factory_cleanup._canonical_bytes(changed))
            os.chmod(path, 0o600)

    def receipt(self, digest):
        return json.loads(
            (
                self.store.root / "archive" / digest / "receipt.json"
            ).read_text()
        )

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

    def test_duplicate_and_empty_payloads_archive_restore_and_replay(self):
        (self.fixture.lane / "duplicate-a").write_bytes(b"same bytes\n")
        (self.fixture.lane / "duplicate-b").write_bytes(b"same bytes\n")
        (self.fixture.lane / "empty-a").write_bytes(b"")
        (self.fixture.lane / "empty-b").write_bytes(b"")
        result = self.fixture.plan()
        applied = self.fixture.apply(result)
        self.assertEqual((applied.archived, applied.held, applied.replay), (1, 0, False))
        archive = self.fixture.store.root / "archive" / result.digest
        candidate = archive / self.fixture.worktree_id / "1"
        manifest = json.loads((candidate / "manifest.json").read_text())
        names = {
            row["path"]: row["payload"]
            for row in manifest["files"]
            if row["path"]
            in {
                base64.b64encode(name).decode("ascii")
                for name in (b"duplicate-a", b"duplicate-b", b"empty-a", b"empty-b")
            }
        }
        self.assertEqual(len(names), 4)
        self.assertEqual(len(set(names.values())), 4)
        restored = archive / "duplicates-restored"
        expected = json.loads(result.plan_path.read_text())["candidates"][0]["expected"]
        factory_cleanup._restore_archive(candidate, restored, expected)
        factory_cleanup._verify_restore(restored, expected)
        for name in ("duplicate-a", "duplicate-b", "empty-a", "empty-b"):
            self.assertEqual(
                (restored / name).read_bytes(), (self.fixture.lane / name).read_bytes()
            )
        replay = self.fixture.apply(result)
        self.assertTrue(replay.replay)

    def test_restore_preserves_index_worktree_and_ignored_leaves(self):
        result = self.fixture.plan()
        self.fixture.apply(result)
        expected = json.loads(result.plan_path.read_text())["candidates"][0][
            "expected"
        ]
        archive = self.fixture.store.root / "archive" / result.digest
        candidate = archive / self.fixture.worktree_id / "1"
        restored = archive / "proof-restore"
        original_git = factory_cleanup._git

        def no_source_objects(root, *arguments, **values):
            self.assertNotIn(
                Path(root).resolve(),
                (self.fixture.repo.resolve(), self.fixture.lane.resolve()),
            )
            return original_git(root, *arguments, **values)

        with mock.patch.object(factory_cleanup, "_git", no_source_objects):
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
        def read_failure(original):
            def capture(binding, payload_dir=None):
                if payload_dir is None:
                    return original(binding, payload_dir)
                with mock.patch.object(
                    os, "read", side_effect=OSError("synthetic read failure")
                ):
                    return original(binding, payload_dir)

            return capture

        def short_write(original):
            def capture(binding, payload_dir=None):
                if payload_dir is None:
                    return original(binding, payload_dir)
                calls = 0
                original_write = os.write

                def injected(descriptor, data):
                    nonlocal calls
                    calls += 1
                    if calls == 1 and data:
                        return original_write(descriptor, data[:1])
                    if calls == 2:
                        return 0
                    return original_write(descriptor, data)

                with mock.patch.object(os, "write", injected):
                    return original(binding, payload_dir)

            return capture

        failure_points = (
            ("read", "_capture_expected", read_failure, "archive_failed"),
            ("short", "_capture_expected", short_write, "archive_failed"),
            (
                "bundle",
                "_bundle",
                lambda original: lambda binding, candidate_dir: (
                    (_ for _ in ()).throw(
                        factory_cleanup.CleanupError("bundle_failed")
                    )
                ),
                "bundle_failed",
            ),
            (
                "publish",
                "os.rename",
                lambda original: lambda source, destination: (
                    (_ for _ in ()).throw(
                        OSError("synthetic publish failure")
                    )
                ),
                "publication_failed",
            ),
        )
        for label, symbol, replacement, reason in failure_points:
            with self.subTest(symbol=label):
                fixture, result, before = self._fresh()
                owner = factory_cleanup
                attribute = symbol
                if symbol == "os.rename":
                    owner = os
                    attribute = "rename"
                original = getattr(owner, attribute)
                with mock.patch.object(owner, attribute, replacement(original)):
                    with self.assertRaises(factory_cleanup.CleanupError) as raised:
                        fixture.apply(result)
                self.assertEqual(raised.exception.reason, reason)
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
        expected = json.loads(result.plan_path.read_text())["candidates"][0]["expected"]
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
        omitted_entry = next(
            entry
            for entry in manifest["expected"]["entries"]
            if factory_cleanup._encoded_path(entry["path"]) == b"untracked"
        )
        omitted = next(
            row for row in manifest["files"] if row["path"] == omitted_entry["path"]
        )
        manifest["files"].remove(omitted)
        manifest["expected"]["entries"].remove(omitted_entry)
        for row in manifest["expected"]["index"]["entries"]:
            self.assertNotEqual(row["path"], omitted_entry["path"])
        (candidate / "files" / omitted["payload"]).unlink()
        manifest_path.write_bytes(factory_cleanup._canonical_bytes(manifest))
        os.chmod(manifest_path, 0o600)
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "archive_manifest"
        ):
            factory_cleanup._restore_archive(
                candidate,
                fixture.store.root / "archive" / result.digest / "restored",
                expected,
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

        omitted_payload = clone("omitted-payload")
        manifest = json.loads(
            (omitted_payload / "manifest.json").read_text()
        )
        first = (omitted_payload / "files" / manifest["files"][0]["payload"])
        first.unlink()
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "input_unreadable"
        ):
            factory_cleanup._restore_archive(
                omitted_payload,
                fixture.store.root / "staging" / "restore-omitted-payload",
                expected,
            )

        for label, mutate in (
            (
                "mode",
                lambda value: value["expected"]["entries"][0].update(
                    {"mode": value["expected"]["entries"][0]["mode"] ^ 1}
                ),
            ),
            (
                "target",
                lambda value: next(
                    entry
                    for entry in value["expected"]["entries"]
                    if entry["kind"] == "link"
                ).update(
                    {
                        "target": base64.b64encode(b"different").decode(
                            "ascii"
                        )
                    }
                ),
            ),
        ):
            tampered = clone(label)
            path = tampered / "manifest.json"
            value = json.loads(path.read_text())
            mutate(value)
            path.write_bytes(factory_cleanup._canonical_bytes(value))
            with self.assertRaisesRegex(
                factory_cleanup.CleanupError, "archive_manifest"
            ):
                factory_cleanup._restore_archive(
                    tampered,
                    fixture.store.root / "staging" / ("restore-" + label),
                    expected,
                )

        bundle_only = clone("bundle-only")
        for child in tuple(bundle_only.iterdir()):
            if child.name != "commits.bundle":
                if child.is_dir() and not child.is_symlink():
                    factory_cleanup._remove_private_tree(child)
                else:
                    child.unlink()
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "input_unreadable"
        ):
            factory_cleanup._restore_archive(
                bundle_only,
                fixture.store.root / "staging" / "restore-bundle-only",
                expected,
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

    def test_capture_change_holds_candidate_and_cleans_staging(self):
        for reason in ("tree_changed", "index_changed", "path_changed"):
            with self.subTest(reason=reason):
                fixture, result, before = self._fresh()
                original = factory_cleanup._capture_expected

                def changed(binding, payload_dir=None):
                    if payload_dir is not None:
                        raise factory_cleanup.CleanupError(reason)
                    return original(binding, payload_dir)

                with mock.patch.object(
                    factory_cleanup, "_capture_expected", changed
                ):
                    applied = fixture.apply(result)
                self.assertEqual((applied.archived, applied.held), (0, 1))
                self.assertEqual(
                    fixture.receipt(result.digest)["outcomes"][0].get("reason"),
                    reason,
                )
                self.assertEqual(fixture.subject_snapshot(), before)
                stage = fixture.store.root / "staging"
                self.assertTrue(
                    not stage.exists()
                    or not any(
                        path.name.startswith(result.digest + "-")
                        for path in stage.iterdir()
                    )
                )


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
        for reused in (True, False):
            with self.subTest(reused=reused):
                fixture = CleanupFixture(self)
                fixture.make_archive_changes()
                result = fixture.plan()
                (fixture.lane / "untracked").write_bytes(b"replacement")
                old_inspect = factory_cleanup.factory_lease.inspect_worktree
                expected_inode = json.loads(
                    result.plan_path.read_text()
                )["candidates"][0]["binding"]["inode"]

                def changed_inode(path, identity):
                    binding = old_inspect(path, identity)
                    return factory_lease.WorktreeBinding(
                        path=binding.path,
                        device=binding.device,
                        inode=(
                            expected_inode
                            if reused
                            else expected_inode + 1
                        ),
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
                    changed_inode,
                ):
                    applied = factory_cleanup.apply_cleanup(
                        fixture.repo,
                        result.plan_path,
                        result.digest,
                        **fixture.args(),
                    )
                self.assertEqual(applied.held, 1)
                self.assertEqual(
                    fixture.receipt(result.digest)["outcomes"][0].get("reason"),
                    "tree_changed" if reused else "path_changed",
                )
                self.assertEqual(
                    (fixture.lane / "untracked").read_bytes(), b"replacement"
                )

    def test_04_swap_between_revalidation_and_archive_open_holds(self):
        for ancestor in (False, True):
            with self.subTest(ancestor=ancestor):
                fixture = CleanupFixture(self)
                fixture.make_archive_changes()
                result = fixture.plan()
                outside = fixture.root / "outside-swap"
                outside.mkdir()
                (outside / "private").write_bytes(b"outside private")
                original = factory_cleanup._capture_expected
                moved = fixture.root / "moved-before-open"

                def swap(binding, payload_dir=None):
                    if payload_dir is not None:
                        if ancestor:
                            os.rename(fixture.lane, moved)
                            fixture.lane.symlink_to(
                                outside, target_is_directory=True
                            )
                        else:
                            (fixture.lane / "untracked").unlink()
                            (fixture.lane / "untracked").symlink_to(
                                outside / "private"
                            )
                    return original(binding, payload_dir)

                with mock.patch.object(
                    factory_cleanup, "_capture_expected", swap
                ):
                    applied = fixture.apply(result)
                reason = (
                    "path_changed" if ancestor else "tree_changed"
                )
                self.assertEqual((applied.archived, applied.held), (0, 1))
                self.assertEqual(
                    fixture.receipt(result.digest)["outcomes"][0]["reason"],
                    reason,
                )
                archive = fixture.store.root / "archive" / result.digest
                self.assertFalse(
                    any(
                        b"outside private" in path.read_bytes()
                        for path in archive.rglob("*")
                        if path.is_file()
                    )
                )
                self.assertEqual(
                    (outside / "private").read_bytes(), b"outside private"
                )

    def test_04_matching_recreation_is_archive_only_never_removed(self):
        fixture = CleanupFixture(self)
        result = fixture.plan()
        expected_binding = json.loads(result.plan_path.read_text())[
            "candidates"
        ][0]["binding"]
        moved = fixture.root / "original-recreation"
        os.rename(fixture.lane, moved)
        shutil.copytree(moved, fixture.lane, symlinks=True)
        def same_inode(path, identity):
            return factory_lease.WorktreeBinding(
                path=Path(expected_binding["path"]),
                device=expected_binding["device"],
                inode=expected_binding["inode"],
                branch=expected_binding["branch"],
                head=expected_binding["head"],
                gitfile=Path(expected_binding["gitfile"]),
                admin_dir=Path(expected_binding["admin_dir"]),
                backpointer=Path(expected_binding["backpointer"]),
                nonce_path=Path(expected_binding["nonce_path"]),
                common_dir=Path(expected_binding["common_dir"]),
            )

        actual_root_inode = fixture.lane.stat().st_ino
        original_fstat = os.fstat

        def recreated_fstat(descriptor):
            value = original_fstat(descriptor)
            if (
                stat.S_ISDIR(value.st_mode)
                and value.st_ino == actual_root_inode
            ):
                fields = list(value)
                fields[1] = expected_binding["inode"]
                return os.stat_result(fields)
            return value

        with mock.patch.object(
            factory_cleanup.factory_lease, "inspect_worktree", same_inode
        ), mock.patch.object(
            factory_lease, "lease_matches_worktree", return_value=True
        ), mock.patch.object(
            factory_cleanup.os, "fstat", recreated_fstat
        ):
            applied = fixture.apply(result)
        self.assertEqual(
            (applied.archived, applied.held),
            (1, 0),
            fixture.receipt(result.digest)["outcomes"][0].get("reason"),
        )
        self.assertTrue(fixture.lane.exists())
        self.assertTrue(moved.exists())
        self.assertEqual(
            (fixture.lane / "tracked.txt").read_bytes(),
            (moved / "tracked.txt").read_bytes(),
        )

    def test_attested_release_requires_main_and_trusted_origin(self):
        for field, replacement in (
            ("target", "release/other"),
            ("repository", "other/project"),
        ):
            with self.subTest(field=field):
                fixture = CleanupFixture(self)
                fixture.make_archive_changes()
                result = fixture.plan()

                def change(record):
                    if record["release"] is not None:
                        record = json.loads(json.dumps(record))
                        record["release"]["merged"][field] = replacement
                    return record

                fixture.write_records(change)
                applied = fixture.apply(result)
                self.assertEqual((applied.archived, applied.held), (0, 1))
                self.assertEqual(
                    fixture.receipt(result.digest)["outcomes"][0]["reason"],
                    "pr_changed",
                )
                archive = fixture.store.root / "archive" / result.digest
                self.assertFalse(
                    (
                        archive
                        / fixture.worktree_id
                    ).exists()
                )

    def test_descendant_pull_request_head_accepts_local_ancestor(self):
        tree = self.fixture.git(self.fixture.lane, "rev-parse", "HEAD^{tree}")
        descendant = self.fixture.git(
            self.fixture.lane,
            "commit-tree",
            tree,
            "-p",
            self.fixture.lane_head,
            "-m",
            "descendant evidence",
        )

        def change(record):
            record = json.loads(json.dumps(record))
            if record["release"] is not None:
                record["release"]["merged"]["head_oid"] = descendant
            return record

        self.fixture.write_records(change)
        pull = factory_lease.PullRequestEvidence(
            17,
            REPOSITORY,
            "main",
            BRANCH,
            "MERGED",
            descendant,
            NOW,
        )
        self.fixture.pulls = PositivePullRequests((pull,))
        result = self.fixture.plan()
        applied = self.fixture.apply(result)
        self.assertEqual((applied.archived, applied.held), (1, 0))

    def test_05_commit_reset_branch_ref_and_same_tip_checkout_preserve_refs(self):
        for change in ("commit", "reset", "switch", "ref", "symbolic"):
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
                elif change == "ref":
                    fixture.git(
                        fixture.repo,
                        "branch",
                        "lanes/attached-same-tip",
                        fixture.lane_head,
                    )
                else:
                    fixture.git(
                        fixture.repo,
                        "branch",
                        "lanes/symbolic-target",
                        fixture.lane_head,
                    )
                    fixture.git(
                        fixture.lane,
                        "symbolic-ref",
                        "HEAD",
                        "refs/heads/lanes/symbolic-target",
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
                if change == "symbolic":
                    self.assertEqual(
                        fixture.receipt(result.digest)["outcomes"][0]["reason"],
                        "lease_changed",
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
        self.assertEqual(reason, "class_active_hold")

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
        self.assertEqual(
            partial_fixture.receipt(partial_result.digest)["outcomes"][0]["reason"],
            "process_unknown",
        )

    def test_pid_reuse_outside_is_positive_and_live_child_group_holds(self):
        def holder(record):
            record = json.loads(json.dumps(record))
            if record["class"] in ("worktree", "branch"):
                record["holder"] = {"pid": 913, "start": "original wrapper"}
            return record

        self.fixture.write_records(holder)
        outside = CompleteProcesses(
            pids=frozenset({913}),
            cwds=(self.fixture.root / "outside",),
            starts={913: "different start"},
            pgids=frozenset(),
        )
        result = self.fixture.plan()
        applied = factory_cleanup.apply_cleanup(
            self.fixture.repo,
            result.plan_path,
            result.digest,
            **dict(self.fixture.args(), process_provider=outside),
        )
        self.assertEqual((applied.archived, applied.held), (1, 0))

        child_fixture = CleanupFixture(self)
        def child_holder(record):
            record = json.loads(json.dumps(record))
            if record["class"] in ("worktree", "branch"):
                record["holder"] = {"pid": 914, "start": "dead wrapper"}
            return record

        child_fixture.write_records(child_holder)
        child_group = CompleteProcesses(
            pids=frozenset({9877}),
            cwds=(child_fixture.root / "outside",),
            starts={9877: "live child"},
            pgids=frozenset({914}),
        )
        child_result = child_fixture.plan()
        held = factory_cleanup.apply_cleanup(
            child_fixture.repo,
            child_result.plan_path,
            child_result.digest,
            **dict(child_fixture.args(), process_provider=child_group),
        )
        self.assertEqual((held.archived, held.held), (0, 1))
        self.assertEqual(
            child_fixture.receipt(child_result.digest)["outcomes"][0]["reason"],
            "active_hold",
        )

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
        self.assertEqual(self._held_reason(result), "lease_changed")

    def test_07_expired_active_and_stale_plan_generation_hold_exactly(self):
        active = CleanupFixture(self)
        active.make_archive_changes()
        result = active.plan()

        def expire_active(record):
            record = json.loads(json.dumps(record))
            record["state"] = "active"
            record["release"] = None
            return record

        active.write_records(expire_active)
        applied = active.apply(result)
        self.assertEqual(applied.held, 1)
        self.assertEqual(
            active.receipt(result.digest)["outcomes"][0]["reason"],
            "lease_unreleased",
        )

        stale = CleanupFixture(self)
        stale.make_archive_changes()
        stale_result = stale.plan()
        value = json.loads(stale_result.plan_path.read_text())
        value["candidates"][0]["lease_generation"] += 1
        raw = factory_cleanup._canonical_bytes(value)
        digest = hashlib.sha256(raw).hexdigest()
        path = stale_result.plan_path.parent / (digest + ".json")
        path.write_bytes(raw)
        os.chmod(path, 0o600)
        applied = factory_cleanup.apply_cleanup(
            stale.repo, path, digest, **stale.args()
        )
        self.assertEqual(applied.held, 1)
        self.assertEqual(
            stale.receipt(digest)["outcomes"][0]["reason"], "lease_changed"
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
        sibling = factory_cleanup.plan_cleanup(
            self.fixture.other_clone,
            **self.fixture.args(),
        )
        self.assertEqual((sibling.planned, sibling.held), (0, 0))

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

    def test_08_invalid_records_and_marker_reuse_hold_without_archive(self):
        mutations = (
            "missing",
            "duplicate",
            "corrupt",
            "oversize",
            "extra",
            "wrong_class",
            "wrong_repository",
            "wrong_nonce",
            "wrong_backlink",
            "missing_branch",
            "marker_only",
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                fixture = CleanupFixture(self)
                fixture.make_archive_changes()
                result = fixture.plan()
                records = fixture.store.read_records()[0]
                worktree = next(
                    record for record in records if record["class"] == "worktree"
                )
                branch = next(
                    record for record in records if record["class"] == "branch"
                )
                worktree_path = (
                    fixture.store.root
                    / "leases"
                    / "worktree"
                    / (worktree["lease_id"] + ".json")
                )
                if mutation == "missing":
                    worktree_path.unlink()
                elif mutation == "duplicate":
                    duplicate = worktree_path.parent / ("f" * 32 + ".json")
                    duplicate.write_bytes(worktree_path.read_bytes())
                    os.chmod(duplicate, 0o600)
                elif mutation == "corrupt":
                    worktree_path.write_bytes(b"{broken\n")
                elif mutation == "oversize":
                    worktree_path.write_bytes(b"x" * (128 * 1024))
                elif mutation == "extra":
                    value = json.loads(worktree_path.read_text())
                    value["unexpected"] = True
                    worktree_path.write_bytes(
                        factory_cleanup._canonical_bytes(value)
                    )
                elif mutation == "wrong_class":
                    value = json.loads(worktree_path.read_text())
                    value["class"] = "unknown"
                    worktree_path.write_bytes(
                        factory_cleanup._canonical_bytes(value)
                    )
                elif mutation == "wrong_repository":
                    value = json.loads(worktree_path.read_text())
                    value["repo"]["common_dir"] = str(fixture.other_clone)
                    worktree_path.write_bytes(
                        factory_cleanup._canonical_bytes(value)
                    )
                elif mutation == "wrong_nonce":
                    value = json.loads(worktree_path.read_text())
                    value["subject"]["nonce_path"] = str(
                        fixture.store.root / "wrong-nonce"
                    )
                    worktree_path.write_bytes(
                        factory_cleanup._canonical_bytes(value)
                    )
                elif mutation == "wrong_backlink":
                    value = json.loads(worktree_path.read_text())
                    value["subject"]["backpointer"] = str(
                        fixture.store.root / "wrong-backlink"
                    )
                    worktree_path.write_bytes(
                        factory_cleanup._canonical_bytes(value)
                    )
                elif mutation == "missing_branch":
                    (
                        fixture.store.root
                        / "leases"
                        / "branch"
                        / (branch["lease_id"] + ".json")
                    ).unlink()
                else:
                    worktree_path.unlink()
                    marker = {
                        "v": 1,
                        "lease_id": "e" * 32,
                        "generation": 1,
                        "class": "run_marker",
                        "repo": worktree["repo"],
                        "subject": {
                            "parent_lease_id": worktree["lease_id"],
                            "parent_generation": 1,
                            "path": str(
                                fixture.lane / "build" / "runs" / "proof.running"
                            ),
                            "label": "proof",
                            "nonce": "e" * 32,
                        },
                        "creator": "bg_run",
                        "task": "fixture",
                        "thread": None,
                        "holder": None,
                        "created": NOW,
                        "renewed": NOW,
                        "expires": NOW + factory_lease.LEASE_TTL_SECONDS,
                        "state": "released",
                        "release": {
                            "at": NOW,
                            "reason": "ended",
                            "merged": None,
                        },
                    }
                    marker_path = (
                        fixture.store.root
                        / "leases"
                        / "run_marker"
                        / (marker["lease_id"] + ".json")
                    )
                    marker_path.write_bytes(
                        factory_cleanup._canonical_bytes(marker)
                    )
                    os.chmod(marker_path, 0o600)
                applied = fixture.apply(result)
                self.assertEqual((applied.archived, applied.held), (0, 1))
                expected_reason = (
                    "lease_unknown"
                    if mutation == "duplicate"
                    else "lease_changed"
                )
                self.assertEqual(
                    fixture.receipt(result.digest)["outcomes"][0]["reason"],
                    expected_reason,
                )
                archive = fixture.store.root / "archive" / result.digest
                self.assertFalse(
                    (
                        archive / fixture.worktree_id / "1"
                    ).exists()
                )

    def test_08_symlinked_store_and_opposite_order_keep_exact_candidate(self):
        fixture = CleanupFixture(self)
        fixture.make_archive_changes()
        result = fixture.plan()
        moved = fixture.root / "real-factory"
        os.rename(fixture.store.root, moved)
        fixture.store.root.symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "path_changed"
        ):
            fixture.apply(result)

        ordered = CleanupFixture(self)
        ordered.make_archive_changes()
        foreign = ordered.root / "foreign-worktree"
        ordered.git(
            ordered.repo,
            "worktree",
            "add",
            "-q",
            "-b",
            "lanes/foreign",
            str(foreign),
            "main",
        )
        original = factory.GitReader.worktrees

        def reversed_rows(reader):
            return tuple(reversed(original(reader)))

        with mock.patch.object(factory.GitReader, "worktrees", reversed_rows):
            plan = factory_cleanup.plan_cleanup(ordered.repo, **ordered.args())
        value = json.loads(plan.plan_path.read_text())
        self.assertEqual(plan.planned, 1)
        self.assertEqual(plan.held, 1)
        self.assertEqual(
            value["candidates"][0]["binding"]["path"], str(ordered.lane)
        )

    def test_08_caller_subdirectory_and_workflow_base_remain_stable(self):
        fixture = CleanupFixture(self)
        fixture.make_archive_changes()
        child = fixture.repo / "caller" / "nested"
        child.mkdir(parents=True)
        plan = factory_cleanup.plan_cleanup(child, **fixture.args())
        self.assertEqual(plan.planned, 1)
        self.assertEqual(
            json.loads(plan.plan_path.read_text())["workflow_base"], "main"
        )
        applied = factory_cleanup.apply_cleanup(
            child, plan.plan_path, plan.digest, **fixture.args()
        )
        self.assertEqual((applied.archived, applied.held), (1, 0))

        configured = CleanupFixture(self)
        (configured.repo / "tools" / "triage" / "config.json").write_text(
            '{"workflow_base":"release/other"}\n', encoding="utf-8"
        )
        configured_plan = factory_cleanup.plan_cleanup(
            configured.repo, **configured.args()
        )
        self.assertEqual(
            json.loads(configured_plan.plan_path.read_text())["workflow_base"],
            "release/other",
        )

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

    def test_09_multiple_candidates_publish_one_journal_without_removal(self):
        fixture = CleanupFixture(self)
        second = fixture.root / "second-lane"
        second_branch = "lanes/archive-second"
        fixture.git(
            fixture.repo,
            "worktree",
            "add",
            "-q",
            "-b",
            second_branch,
            str(second),
            "main",
        )
        (second / "tracked.txt").write_text("second lane\n", encoding="utf-8")
        fixture.git(second, "add", "tracked.txt")
        fixture.git(second, "commit", "-qm", "second")
        second_head = fixture.git(second, "rev-parse", "HEAD")
        second_id, second_branch_id = fixture.store.create_worktree(
            second,
            "lane_new",
            task="second",
            branch_created=second_branch,
        )
        pulls = PositivePullRequests(
            (
                factory_lease.PullRequestEvidence(
                    17,
                    REPOSITORY,
                    "main",
                    fixture.branch,
                    "MERGED",
                    fixture.lane_head,
                    NOW,
                ),
                factory_lease.PullRequestEvidence(
                    18,
                    REPOSITORY,
                    "main",
                    second_branch,
                    "MERGED",
                    second_head,
                    NOW,
                ),
            )
        )
        fixture.pulls = pulls
        fixture.store.reconcile(second_branch_id, provider=pulls)
        records, invalid = fixture.store.read_records()
        self.assertEqual(invalid, 0)
        fixture.expiry = max(record["expires"] for record in records)
        fixture.now = fixture.expiry + 1
        before = fixture.git_snapshot()
        result = factory_cleanup.plan_cleanup(fixture.repo, **fixture.args())
        self.assertEqual((result.planned, result.held), (2, 0))
        applied = fixture.apply(result)
        self.assertEqual((applied.archived, applied.held), (2, 0))
        archive = fixture.store.root / "archive" / result.digest
        receipt = json.loads((archive / "receipt.json").read_text())
        self.assertEqual(len(receipt["outcomes"]), 2)
        self.assertEqual(
            {
                item["lease_id"] for item in receipt["outcomes"]
            },
            {fixture.worktree_id, second_id},
        )
        self.assertEqual(fixture.git_snapshot(), before)
        self.assertEqual((second / "tracked.txt").read_text(), "second lane\n")
        self.assertEqual(
            len(tuple((fixture.store.root / "archive").iterdir())), 1
        )

    def test_12_late_writes_survive_and_never_trigger_destructive_work(self):
        mutations = (
            "tracked",
            "untracked",
            "ignored",
            "commit",
            "marker",
            "build",
            "ancestor",
        )
        for initially_dirty in (False, True):
            for mutation in mutations:
                with self.subTest(dirty=initially_dirty, mutation=mutation):
                    fixture = CleanupFixture(self)
                    if initially_dirty:
                        fixture.make_archive_changes()
                    if mutation == "untracked":
                        fixture.git(
                            fixture.repo,
                            "config",
                            "status.showUntrackedFiles",
                            "no",
                        )
                    result = fixture.plan()
                    calls = []
                    surviving = {}
                    original_run = factory_cleanup._run

                    def instrument(
                        command, cwd=None, input_bytes=None, write_root=None
                    ):
                        calls.append(tuple(command))
                        return original_run(
                            command, cwd, input_bytes, write_root=write_root
                        )

                    def late(stage, source, destination):
                        if stage != "before_publish":
                            return
                        if mutation == "tracked":
                            (fixture.lane / "tracked.txt").write_bytes(
                                b"late tracked\x00"
                            )
                        elif mutation == "untracked":
                            (fixture.lane / "late-untracked").write_bytes(
                                b"late untracked"
                            )
                        elif mutation == "ignored":
                            (fixture.lane / "build" / "research").mkdir(
                                parents=True, exist_ok=True
                            )
                            (
                                fixture.lane
                                / "build"
                                / "research"
                                / "late-ignored"
                            ).write_bytes(b"late ignored")
                        elif mutation == "commit":
                            (fixture.lane / "late-commit").write_bytes(
                                b"late commit"
                            )
                            fixture.git(fixture.lane, "add", "late-commit")
                            fixture.git(fixture.lane, "commit", "-qm", "late")
                        elif mutation == "marker":
                            (fixture.lane / "build" / "runs").mkdir(
                                parents=True, exist_ok=True
                            )
                            (
                                fixture.lane
                                / "build"
                                / "runs"
                                / "late.running"
                            ).write_bytes(b"late marker")
                        elif mutation == "build":
                            (fixture.lane / "build" / "output").mkdir(
                                parents=True, exist_ok=True
                            )
                            (
                                fixture.lane / "build" / "output" / "late"
                            ).write_bytes(b"late output")
                        else:
                            moved = fixture.root / "surviving-lane"
                            outside = fixture.root / "outside"
                            outside.mkdir()
                            (outside / "outside").write_bytes(b"outside")
                            os.rename(fixture.lane, moved)
                            fixture.lane.symlink_to(
                                outside, target_is_directory=True
                            )
                            surviving["moved"] = moved
                            surviving["outside"] = outside
                        surviving["tree"] = (
                            None
                            if mutation == "ancestor"
                            else fixture.subject_snapshot()
                        )
                        surviving["worktrees"] = fixture.git(
                            fixture.repo, "worktree", "list", "--porcelain"
                        )
                        surviving["refs"] = fixture.git(
                            fixture.repo,
                            "for-each-ref",
                            "--format=%(refname)%00%(objectname)",
                            "refs/heads",
                        )
                        surviving["oid"] = fixture.git(
                            fixture.repo, "rev-parse", "refs/heads/" + BRANCH
                        )

                    with mock.patch.object(factory_cleanup, "_run", instrument):
                        applied = factory_cleanup.apply_cleanup(
                            fixture.repo,
                            result.plan_path,
                            result.digest,
                            publish_hook=late,
                            **fixture.args(),
                        )
                    self.assertEqual((applied.archived, applied.held), (1, 0))
                    self.assertEqual(
                        fixture.git(
                            fixture.repo, "worktree", "list", "--porcelain"
                        ),
                        surviving["worktrees"],
                    )
                    self.assertEqual(
                        fixture.git(
                            fixture.repo,
                            "for-each-ref",
                            "--format=%(refname)%00%(objectname)",
                            "refs/heads",
                        ),
                        surviving["refs"],
                    )
                    self.assertEqual(
                        fixture.git(
                            fixture.repo, "rev-parse", "refs/heads/" + BRANCH
                        ),
                        surviving["oid"],
                    )
                    self.assertFalse(
                        any(
                            "remove" in command
                            or "prune" in command
                            or "--force" in command
                            for command in calls
                        )
                    )
                    if mutation == "ancestor":
                        self.assertTrue(fixture.lane.is_symlink())
                        self.assertEqual(
                            os.readlink(fixture.lane),
                            str(surviving["outside"]),
                        )
                        self.assertEqual(
                            (
                                surviving["outside"] / "outside"
                            ).read_bytes(),
                            b"outside",
                        )
                        self.assertTrue(
                            (surviving["moved"] / "tracked.txt").is_file()
                        )
                    else:
                        self.assertEqual(
                            fixture.subject_snapshot(), surviving["tree"]
                        )

    def test_13_changed_external_and_pr_evidence_is_read_again(self):
        result = self.fixture.plan()

        class PartialPullRequests(factory_lease.PullRequestProvider):
            def list_for_branch(self, repository, branch):
                item = factory_lease.PullRequestEvidence(
                    17,
                    repository,
                    "main",
                    branch,
                    "MERGED",
                    self_fixture.lane_head,
                    NOW,
                )
                return (item,) * 30

        class BrokenPullRequests(factory_lease.PullRequestProvider):
            def list_for_branch(self, repository, branch):
                raise RuntimeError("synthetic provider failure")

        self_fixture = self.fixture
        cases = (
            ("thread_active", CompleteExternal(thread_active=True), self.fixture.pulls),
            (
                "thread_unknown",
                CompleteExternal(thread_active=None),
                self.fixture.pulls,
            ),
            ("external_unknown", CompleteExternal(complete=False), self.fixture.pulls),
            ("t3_owned", CompleteExternal(t3_owned=True), self.fixture.pulls),
            ("active_hold", CompleteExternal(devcap_active=True), self.fixture.pulls),
            ("pr_missing", self.fixture.external, PositivePullRequests(())),
            (
                "pr_partial",
                self.fixture.external,
                PartialPullRequests(),
            ),
            (
                "pr_error",
                self.fixture.external,
                BrokenPullRequests(),
            ),
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
            (
                "wrong_base",
                self.fixture.external,
                PositivePullRequests(
                    (
                        factory_lease.PullRequestEvidence(
                            17,
                            REPOSITORY,
                            "release/other",
                            BRANCH,
                            "MERGED",
                            self.fixture.lane_head,
                            NOW,
                        ),
                    )
                ),
            ),
            (
                "wrong_repository",
                self.fixture.external,
                PositivePullRequests(
                    (
                        factory_lease.PullRequestEvidence(
                            17,
                            "other/project",
                            "main",
                            BRANCH,
                            "MERGED",
                            self.fixture.lane_head,
                            NOW,
                        ),
                    )
                ),
            ),
            (
                "wrong_head",
                self.fixture.external,
                PositivePullRequests(
                    (
                        factory_lease.PullRequestEvidence(
                            17,
                            REPOSITORY,
                            "main",
                            BRANCH,
                            "MERGED",
                            "1" * 40,
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
                    "thread_unknown": "thread_unknown",
                    "external_unknown": "external_unknown",
                    "t3_owned": "t3_owned",
                    "active_hold": "active_hold",
                    "open": "open_successor",
                    "pr_partial": "pr_partial",
                    "pr_error": "pr_unknown",
                }.get(label, "pr_changed")
                self.assertEqual(receipt["outcomes"][0]["reason"], expected_reason)
                self.assertFalse(
                    (
                        self.fixture.store.root
                        / "archive"
                        / result.digest
                        / self.fixture.worktree_id
                    ).exists()
                )
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
        before = fixture.git_snapshot()
        writes = []
        original = factory_cleanup._publish_file
        commands = []
        original_run = factory_cleanup._run

        def bounded(path, raw):
            writes.append(Path(path))
            return original(path, raw)

        def command_probe(command, cwd=None, input_bytes=None, write_root=None):
            commands.append((tuple(command), write_root))
            return original_run(
                command, cwd, input_bytes, write_root=write_root
            )

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
            (
                "git",
                "-C",
                str(fixture.repo),
                "symbolic-ref",
                "-d",
                "HEAD",
            ),
            (
                "git",
                "-C",
                str(fixture.repo),
                "symbolic-ref",
                "-q",
                "HEAD",
                "refs/heads/main",
            ),
            (
                "git",
                "-C",
                str(fixture.repo),
                "checkout",
                "-q",
                "--detach",
                fixture.lane_head,
            ),
        )
        for command in denied:
            with self.assertRaisesRegex(
                factory_cleanup.CleanupError, "command_denied"
            ):
                factory_cleanup._run(command)
        staging = fixture.store.root / "staging"
        factory_cleanup._mkdir_private(staging)
        outside = fixture.root / "outside-bundle"
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "command_denied"
        ):
            factory_cleanup._run(
                (
                    "git",
                    "-C",
                    str(fixture.repo),
                    "bundle",
                    "create",
                    str(outside),
                    "HEAD",
                ),
                write_root=staging,
            )
        escape = staging / "escape"
        escape.symlink_to(fixture.root, target_is_directory=True)
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "command_denied|path_changed"
        ):
            factory_cleanup._run(
                (
                    "git",
                    "-C",
                    str(fixture.repo),
                    "bundle",
                    "create",
                    str(escape / "bundle"),
                    "HEAD",
                ),
                write_root=staging,
            )
        with mock.patch.object(
            factory_cleanup, "_publish_file", bounded
        ), mock.patch.object(factory_cleanup, "_run", command_probe):
            fixture.apply(result)
        for path in writes:
            self.assertTrue(
                path == fixture.store.root
                or factory.path_is_within(path, fixture.store.root)
            )
        self.assertEqual(fixture.git_snapshot(), before)
        self.assertTrue(any(root is not None for _command, root in commands))
        self.assertFalse(
            any("simctl" in command for command, _root in commands)
        )
        with mock.patch.object(
            factory_cleanup, "MAX_COMMAND_OUTPUT_BYTES", 1
        ):
            with self.assertRaisesRegex(
                factory_cleanup.CleanupError, "command_output_too_large"
            ):
                factory_cleanup._run(
                    ("git", "-C", str(fixture.repo), "rev-parse", "HEAD")
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

    def publish_raw(self, raw):
        digest = hashlib.sha256(raw).hexdigest()
        path = self.result.plan_path.parent / (digest + ".json")
        path.write_bytes(raw)
        os.chmod(path, 0o600)
        return path, digest

    def assert_refused_before_side_effects(
        self, path, digest, reason, repo=None
    ):
        repo = repo or self.fixture.repo
        with mock.patch.object(
            factory_lease.LeaseStore,
            "read_records",
            side_effect=AssertionError("lease read"),
        ) as records, mock.patch.object(
            factory_lease.LeaseStore,
            "writer_lock",
            side_effect=AssertionError("lock"),
        ) as lock, mock.patch.object(
            factory_lease,
            "inspect_worktree",
            side_effect=AssertionError("inspection"),
        ) as inspection, mock.patch.object(
            factory,
            "GitResourceProvider",
            side_effect=AssertionError("provider"),
        ) as provider, mock.patch.object(
            factory_cleanup,
            "_capture_expected",
            side_effect=AssertionError("candidate open"),
        ) as capture, mock.patch.object(
            factory_cleanup,
            "_prepare_store_dirs",
            side_effect=AssertionError("store write"),
        ) as preparation, mock.patch.object(
            factory_cleanup,
            "_publish_file",
            side_effect=AssertionError("publication"),
        ) as publication:
            with self.assertRaisesRegex(factory_cleanup.CleanupError, reason):
                factory_cleanup.apply_cleanup(
                    repo,
                    path,
                    digest,
                    now=self.fixture.now,
                )
        for probe in (
            records,
            lock,
            inspection,
            provider,
            capture,
            preparation,
            publication,
        ):
            self.assertEqual(probe.call_count, 0)
        self.assertFalse((self.fixture.store.root / "archive").exists())

    def test_input_gate_precedes_candidate_provider_lock_and_writes(self):
        missing = self.result.plan_path.parent / ("f" * 64 + ".json")
        invalid = (
            (missing, "f" * 64, "input_file"),
            (self.result.plan_path, self.result.digest + "0", "input_digest"),
            (self.result.plan_path, "0" * 64, "input_name"),
        )
        for path, approve, reason in invalid:
            with self.subTest(reason=reason):
                self.assert_refused_before_side_effects(path, approve, reason)
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "arguments_invalid"
        ):
            factory_cleanup._parser().parse_args(["apply", "--plan", "x"])

    def test_duplicate_noncanonical_forbidden_and_expired_inputs_fail(self):
        raw = self.result.plan_path.read_bytes()
        duplicate = raw.replace(b'"v":1', b'"v":1,"v":1', 1)
        duplicate_path, duplicate_digest = self.publish_raw(duplicate)
        self.assert_refused_before_side_effects(
            duplicate_path, duplicate_digest, "input_duplicate"
        )
        noncanonical = raw.replace(b'":', b'": ', 1)
        plain_path, plain_digest = self.publish_raw(noncanonical)
        self.assert_refused_before_side_effects(
            plain_path, plain_digest, "input_noncanonical"
        )
        value = json.loads(raw)
        value["action"] = "remove"
        forbidden = factory_cleanup._canonical_bytes(value)
        forbidden_path, forbidden_digest = self.publish_raw(forbidden)
        self.assert_refused_before_side_effects(
            forbidden_path, forbidden_digest, "input_action"
        )
        value["action"] = "archive_only"
        value["created"] = self.fixture.now - 86400
        expired = factory_cleanup._canonical_bytes(value)
        expired_path, expired_digest = self.publish_raw(expired)
        self.assert_refused_before_side_effects(
            expired_path, expired_digest, "plan_expired"
        )
        value["created"] = self.fixture.now + 1
        future = factory_cleanup._canonical_bytes(value)
        future_path, future_digest = self.publish_raw(future)
        self.assert_refused_before_side_effects(
            future_path, future_digest, "plan_future"
        )
        value = json.loads(raw)
        value["candidates"][0]["binding"]["path"] = str(
            self.fixture.lane / ".." / self.fixture.lane.name
        )
        traversal = factory_cleanup._canonical_bytes(value)
        traversal_path, traversal_digest = self.publish_raw(traversal)
        self.assert_refused_before_side_effects(
            traversal_path, traversal_digest, "input_path"
        )

    def test_valid_plan_just_inside_window_reaches_archive(self):
        value = json.loads(self.result.plan_path.read_text())
        value["created"] = self.fixture.now - 86399
        path, digest = self.publish_raw(factory_cleanup._canonical_bytes(value))
        applied = factory_cleanup.apply_cleanup(
            self.fixture.repo, path, digest, **self.fixture.args()
        )
        self.assertEqual((applied.archived, applied.held), (1, 0))

    def test_edited_digest_is_refused_before_any_other_work(self):
        original = self.result.plan_path.read_bytes()
        edited = original.replace(b'"held":0', b'"held":1', 1)
        self.assertNotEqual(edited, original)
        self.result.plan_path.write_bytes(edited)
        self.assert_refused_before_side_effects(
            self.result.plan_path, self.result.digest, "input_digest"
        )

    def test_unregistered_subject_and_config_change_are_exact_holds(self):
        moved = self.fixture.root / "unregistered"
        os.rename(self.fixture.lane, moved)
        applied = self.fixture.apply(self.result)
        self.assertEqual(applied.held, 1)
        self.assertEqual(
            self.fixture.receipt(self.result.digest)["outcomes"][0]["reason"],
            "path_changed",
        )
        os.rename(moved, self.fixture.lane)
        (self.fixture.repo / "tools" / "triage" / "config.json").write_text(
            '{"workflow_base":"release/other"}\n', encoding="utf-8"
        )
        with self.assertRaisesRegex(
            factory_cleanup.CleanupError, "workflow_base_changed"
        ):
            factory_cleanup.apply_cleanup(
                self.fixture.repo,
                self.result.plan_path,
                self.result.digest,
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
        backup = self.result.plan_path.with_name("saved-plan")
        self.result.plan_path.rename(backup)
        self.result.plan_path.symlink_to(external)
        self.assert_refused_before_side_effects(
            self.result.plan_path, self.result.digest, "input_file"
        )
        self.result.plan_path.unlink()
        backup.rename(self.result.plan_path)
        (self.result.plan_path.parent / "linked.json").unlink()
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
        self.assert_refused_before_side_effects(
            self.result.plan_path,
            self.result.digest,
            "input_outside_store",
            repo=self.fixture.other_clone,
        )

    def test_output_hides_private_canaries_on_main_paths(self):
        def prepared(canary="private-canary-913"):
            fixture = CleanupFixture(self, canary)

            def holder(record):
                record = json.loads(json.dumps(record))
                if record["class"] in ("worktree", "branch"):
                    record["holder"] = {
                        "pid": 913,
                        "start": "original wrapper",
                    }
                return record

            fixture.write_records(holder)
            outside = fixture.root / "outside"
            outside.mkdir()
            fixture.processes = CompleteProcesses(
                pids=frozenset({913}),
                cwds=(outside,),
                starts={913: "different wrapper start"},
                pgids=frozenset(),
            )
            return fixture

        def run_main(fixture, arguments, apply_changes=None):
            stdout = io.StringIO()
            stderr = io.StringIO()
            previous = Path.cwd()
            planned = []
            actual_plan = factory_cleanup.plan_cleanup
            actual_apply = factory_cleanup.apply_cleanup
            values = fixture.args()

            def fake_plan(repo):
                result = actual_plan(repo, **values)
                planned.append(result)
                return result

            def fake_apply(repo, plan_path, approve):
                extra = dict(values)
                if apply_changes is not None:
                    extra.update(apply_changes)
                return actual_apply(repo, plan_path, approve, **extra)

            try:
                os.chdir(fixture.repo)
                with mock.patch.object(
                    factory_cleanup, "plan_cleanup", fake_plan
                ), mock.patch.object(
                    factory_cleanup, "apply_cleanup", fake_apply
                ), contextlib.redirect_stdout(
                    stdout
                ), contextlib.redirect_stderr(stderr):
                    code = factory_cleanup.main(arguments)
            finally:
                os.chdir(previous)
            return code, stdout.getvalue(), stderr.getvalue(), planned

        def assert_private(fixture, result, receipt=True):
            plan_text = result.plan_path.read_text()
            candidate = json.loads(plan_text)["candidates"][0]
            self.assertEqual(candidate["binding"]["path"], str(fixture.lane))
            self.assertEqual(candidate["binding"]["branch"], fixture.branch)
            self.assertEqual(candidate["task"], fixture.task)
            self.assertEqual(candidate["holder_pid"], 913)
            if receipt:
                receipt_value = fixture.receipt(result.digest)
                outcome = receipt_value["outcomes"][0]
                self.assertEqual(outcome["task"], fixture.task)
                self.assertEqual(outcome["holder_pid"], 913)
                self.assertEqual(outcome["path"], str(fixture.lane))
                self.assertEqual(outcome["branch"], fixture.branch)

        positive = prepared()
        positive_before = positive.git_snapshot()
        commands = []
        writes = []
        original_run = factory_cleanup._run
        original_publish = factory_cleanup._publish_file

        def command_probe(command, cwd=None, input_bytes=None, write_root=None):
            commands.append((tuple(command), write_root))
            return original_run(
                command, cwd, input_bytes, write_root=write_root
            )

        def publish_probe(path, raw):
            writes.append(Path(path))
            return original_publish(path, raw)

        with mock.patch.object(
            factory_cleanup, "_run", command_probe
        ), mock.patch.object(factory_cleanup, "_publish_file", publish_probe):
            code, stdout, stderr, plans = run_main(positive, ["plan"])
            self.assertEqual(code, 0)
            plan_result = plans[0]
            code, apply_out, apply_err, _plans = run_main(
                positive,
                ["apply", "--plan", str(plan_result.plan_path), "--approve", plan_result.digest],
            )
        public = stdout + stderr + apply_out + apply_err
        self.assertNotIn(str(positive.lane), public)
        self.assertNotIn(positive.branch, public)
        self.assertNotIn(positive.task, public)
        self.assertNotIn("913", public)
        self.assertEqual((code, apply_err), (0, ""))
        assert_private(positive, plan_result)
        self.assertEqual(positive.git_snapshot(), positive_before)
        self.assertTrue(
            all(
                path == positive.store.root
                or factory.path_is_within(path, positive.store.root)
                for path in writes
            )
        )
        self.assertTrue(any(root is not None for _command, root in commands))

        skipped = prepared("skip-canary-913")
        skipped_before = skipped.git_snapshot()
        _code, _out, _err, skipped_plans = run_main(skipped, ["plan"])
        skipped_result = skipped_plans[0]
        with mock.patch.object(
            factory_cleanup, "_run", command_probe
        ), mock.patch.object(factory_cleanup, "_publish_file", publish_probe):
            code, stdout, stderr, _plans = run_main(
                skipped,
                [
                    "apply",
                    "--plan",
                    str(skipped_result.plan_path),
                    "--approve",
                    skipped_result.digest,
                ],
                {
                    "external_provider": CompleteExternal(thread_active=True),
                },
            )
        self.assertEqual(code, 0)
        self.assertNotIn(skipped.task, stdout + stderr)
        assert_private(skipped, skipped_result)
        self.assertEqual(skipped.git_snapshot(), skipped_before)

        failed = prepared("failure-canary-913")
        failed_before = failed.git_snapshot()
        _code, _out, _err, failed_plans = run_main(failed, ["plan"])
        failed_result = failed_plans[0]
        with mock.patch.object(
            factory_cleanup,
            "_bundle",
            side_effect=factory_cleanup.CleanupError("bundle_failed"),
        ), mock.patch.object(
            factory_cleanup, "_run", command_probe
        ), mock.patch.object(factory_cleanup, "_publish_file", publish_probe):
            code, stdout, stderr, _plans = run_main(
                failed,
                [
                    "apply",
                    "--plan",
                    str(failed_result.plan_path),
                    "--approve",
                    failed_result.digest,
                ],
            )
        self.assertEqual(code, 1)
        self.assertIn("bundle_failed", stderr)
        self.assertNotIn(failed.task, stdout + stderr)
        assert_private(failed, failed_result, receipt=False)
        self.assertEqual(failed.git_snapshot(), failed_before)
        self.assertFalse(
            (
                failed.store.root / "archive" / failed_result.digest
            ).exists()
        )

        recovery = prepared("recovery-canary-913")
        recovery_before = recovery.git_snapshot()
        _code, _out, _err, recovery_plans = run_main(recovery, ["plan"])
        recovery_result = recovery_plans[0]
        with mock.patch.object(
            factory_cleanup, "_run", command_probe
        ), mock.patch.object(factory_cleanup, "_publish_file", publish_probe):
            with self.assertRaises(KeyboardInterrupt):
                run_main(
                    recovery,
                    [
                        "apply",
                        "--plan",
                        str(recovery_result.plan_path),
                        "--approve",
                        recovery_result.digest,
                    ],
                    {
                        "publish_hook": lambda *_args: (
                            (_ for _ in ()).throw(KeyboardInterrupt())
                        )
                    },
                )
            code, stdout, stderr, _plans = run_main(
                recovery,
                [
                    "apply",
                    "--plan",
                    str(recovery_result.plan_path),
                    "--approve",
                    recovery_result.digest,
                ],
            )
        self.assertEqual(code, 0)
        self.assertNotIn(recovery.task, stdout + stderr)
        assert_private(recovery, recovery_result)
        self.assertEqual(recovery.git_snapshot(), recovery_before)
        self.assertTrue(commands)
        self.assertTrue(
            all(
                any(
                    path == candidate.store.root
                    or factory.path_is_within(path, candidate.store.root)
                    for candidate in (
                        positive,
                        skipped,
                        failed,
                        recovery,
                    )
                )
                for path in writes
            )
        )

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
