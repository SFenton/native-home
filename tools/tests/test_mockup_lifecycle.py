"""Mockup lifecycle: the Stop hook ``tools/hooks/mockup_hub_guard.py`` and the status rules of ``tools/mockups_check.py``."""

import io
import json
import os
import subprocess
import sys
import time
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS / "hooks"))
sys.path.insert(0, str(TOOLS))
import mockup_hub_guard  # noqa: E402
import mockups_check  # noqa: E402


def touch(path: Path, when: float) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("x")
    os.utime(path, (when, when))
    return path


class HubGuardTests(unittest.TestCase):
    def reason(self, root: Path, changed):
        with mock.patch.object(mockup_hub_guard, "changed_mockups", return_value=changed):
            return mockup_hub_guard.stale_reason(root)

    def test_no_mockup_change_is_never_blocked(self):
        with TemporaryDirectory() as d:
            self.assertIsNone(self.reason(Path(d), []))

    def test_changed_mockup_without_a_rebuild_is_blocked(self):
        with TemporaryDirectory() as d:
            root = Path(d)
            page = touch(root / "m.html", 100)
            self.assertIn("rebuilt", self.reason(root, [page]))
            touch(root / "build" / "mockups-hub.built", 50)
            self.assertIn("rebuilt", self.reason(root, [page]))

    def test_rebuilt_but_unpublished_is_blocked_until_marked(self):
        with TemporaryDirectory() as d:
            root = Path(d)
            page = touch(root / "m.html", 100)
            touch(root / "build" / "mockups-hub.built", 200)
            self.assertIn("published", self.reason(root, [page]))
            touch(root / "build" / "mockups-hub.published", 300)
            self.assertIsNone(self.reason(root, [page]))

    def test_second_stop_attempt_passes(self):
        with mock.patch("sys.stdin", io.StringIO(json.dumps({"stop_hook_active": True}))):
            self.assertEqual(mockup_hub_guard.main(), 0)

    def test_blocking_message_names_the_skill_and_the_hub(self):
        with TemporaryDirectory() as d:
            root = Path(d)
            page = touch(root / "m.html", 100)
            err = io.StringIO()
            with mock.patch("sys.stdin", io.StringIO("{}")), mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": d}), \
                    mock.patch.object(mockup_hub_guard, "_lines", return_value=[]), \
                    mock.patch.object(mockup_hub_guard, "changed_mockups", return_value=[page]), redirect_stderr(err):
                self.assertEqual(mockup_hub_guard.main(), 2)
            self.assertIn("mockup-hub/SKILL.md", err.getvalue())
            self.assertIn("claude.ai/artifact/", err.getvalue())


def run_git(root: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)


class SessionScopeTests(unittest.TestCase):
    """Content-hash scope against a real repo: a checkout, a touch or another session's old file never blocks."""

    PAGE = ".agents/design/mockups/page.html"

    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve() / "wt"
        self.root.mkdir()
        run_git(self.root, "init", "-q", "-b", "main")
        run_git(self.root, "config", "user.email", "t@t")
        run_git(self.root, "config", "user.name", "t")
        self.page = touch(self.root / self.PAGE, 100)
        run_git(self.root, "add", "-A")
        run_git(self.root, "commit", "-qm", "base")
        run_git(self.root, "update-ref", "refs/remotes/origin/main", "HEAD")
        run_git(self.root, "checkout", "-q", "-b", "lane")
        run_git(self.root, "config", "branch.lane.sh-base", "origin/main")
        env = mock.patch.dict(os.environ, {"SH_MOCKUP_HUB_CACHE": str(Path(self.tmp.name) / "cache")})
        env.start()
        self.addCleanup(env.stop)
        self.event = {"session_id": "s1", "cwd": str(self.root)}

    def start(self):
        with mock.patch("sys.stdin", io.StringIO(json.dumps(self.event))):
            self.assertEqual(mockup_hub_guard.main(["--session-start"]), 0)
        return mockup_hub_guard.session_start(self.root, self.event)

    def test_fresh_worktree_with_new_looking_files_does_not_trigger(self):
        # A lane that already committed mockups, checked out just now (fresh mtimes): same bytes as at session start.
        touch(self.root / ".agents/design/mockups/lane.svg", 100)
        run_git(self.root, "add", "-A")
        run_git(self.root, "commit", "-qm", "lane work")
        snap = self.start()
        os.utime(self.root / ".agents/design/mockups/lane.svg", None)  # the checkout made it look new
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, snap), [])
        self.assertIsNone(mockup_hub_guard.stale_reason(self.root, snap))

    def test_a_real_change_blocks_until_republished(self):
        snap = self.start()
        self.page.write_text("edited")
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, snap), [self.page])
        self.assertIn("rebuilt", mockup_hub_guard.stale_reason(self.root, snap))

    def test_a_new_untracked_file_counts(self):
        snap = self.start()
        made = touch(self.root / ".agents/design/mockups/proposals/x/x.html", 900)
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, snap), [made])

    def test_a_committed_change_since_the_lane_base_counts(self):
        snap = self.start()
        self.page.write_text("edited")
        run_git(self.root, "commit", "-qam", "edit")
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, snap), [self.page])

    def test_touch_only_does_not_count(self):
        snap = self.start()
        os.utime(self.page, (9999, 9999))
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, snap), [])

    def test_markdown_is_not_published(self):
        snap = self.start()
        touch(self.root / ".agents/design/mockups/README.md", 900)
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, snap), [])

    def test_session_started_elsewhere_still_blocks_in_the_worktree(self):
        # SessionStart ran in the primary checkout; the session then works (and stops) in this linked worktree.
        primary = Path(self.tmp.name).resolve() / "primary"
        primary.mkdir()
        run_git(primary, "init", "-q", "-b", "main")
        transcript = Path(self.tmp.name) / "t.jsonl"
        transcript.write_text("{}")
        event = {"session_id": "s1", "cwd": str(primary), "transcript_path": str(transcript)}
        with mock.patch("sys.stdin", io.StringIO(json.dumps(event))):
            self.assertEqual(mockup_hub_guard.main(["--session-start"]), 0)
        stop = {**event, "cwd": str(self.root)}
        self.page.write_text("edited")
        with mock.patch("sys.stdin", io.StringIO(json.dumps(stop))), redirect_stderr(io.StringIO()):
            self.assertEqual(mockup_hub_guard.main(), 2)

    def test_fallback_ignores_a_fresh_checkout_and_old_files(self):
        transcript = Path(self.tmp.name) / "t.jsonl"
        transcript.write_text("{}")
        stop = {"session_id": "other", "cwd": str(self.root), "transcript_path": str(transcript)}
        os.utime(self.page, None)  # the checkout made the clean file look new
        with mock.patch("sys.stdin", io.StringIO(json.dumps(stop))):
            self.assertEqual(mockup_hub_guard.main(), 0)
        old = touch(self.root / ".agents/design/mockups/old.svg", 100)  # another session's dirty file, older than this one
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, None, time.time()), [])
        self.assertNotIn(old, mockup_hub_guard.changed_mockups(self.root, None, time.time()))

    def test_fallback_counts_a_commit_made_this_session(self):
        since = time.time() - 5
        self.page.write_text("edited")
        run_git(self.root, "commit", "-qam", "edit")
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, None, since), [self.page])

    def test_unknown_start_and_no_snapshot_still_checks_dirty_files(self):
        self.page.write_text("edited")
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, None, None), [self.page])

    def test_the_first_snapshot_is_kept_on_resume(self):
        self.start()
        self.page.write_text("edited")
        self.start()  # resume or compaction fires SessionStart again
        self.assertEqual(mockup_hub_guard.changed_mockups(self.root, mockup_hub_guard.session_start(self.root, self.event)), [self.page])

    def test_stop_hook_end_to_end(self):
        self.start()
        self.page.write_text("edited")
        with mock.patch("sys.stdin", io.StringIO(json.dumps(self.event))), redirect_stderr(io.StringIO()):
            self.assertEqual(mockup_hub_guard.main(), 2)

    def test_lane_base_prefers_the_recorded_base_then_the_remote_default(self):
        self.assertEqual(mockup_hub_guard.lane_base(self.root), "origin/main")
        run_git(self.root, "config", "branch.lane.sh-base", "origin/claude/uikit-port")
        self.assertEqual(mockup_hub_guard.lane_base(self.root), "origin/claude/uikit-port")
        run_git(self.root, "config", "--unset", "branch.lane.sh-base")
        self.assertEqual(mockup_hub_guard.lane_base(self.root), "origin/main")

    def test_snapshot_lives_outside_the_worktree(self):
        self.start()
        path = mockup_hub_guard.snapshot_path(self.root, "s1")
        self.assertTrue(path.exists())
        self.assertNotIn(self.root, path.parents)


class CatalogRuleTests(unittest.TestCase):
    def setUp(self):
        patch = mock.patch.dict(os.environ)  # CI sets GITHUB_BASE_REF and GITHUB_HEAD_REF in every PR step
        patch.start()
        self.addCleanup(patch.stop)
        os.environ.pop("GITHUB_BASE_REF", None)
        os.environ.pop("GITHUB_HEAD_REF", None)
        mockups_check.problems.clear()

    def test_decided_needs_a_decision_and_superseded_a_successor(self):
        mockups_check.check_status({"id": "a", "status": "decided"})
        mockups_check.check_status({"id": "b", "status": "decided", "decision": "PR #12"})
        mockups_check.check_status({"id": "c", "status": "superseded"})
        mockups_check.check_status({"id": "d", "status": "wat"})
        self.assertEqual(len(mockups_check.problems), 3)
        self.assertTrue(any("a is decided" in p for p in mockups_check.problems))

    def test_in_flight_on_main_or_a_deleted_branch_fails(self):
        mockups_check.check_in_flight({"id": "a", "inFlight": {"branch": "main"}})
        self.assertEqual(len(mockups_check.problems), 1)
        with mock.patch.object(mockups_check, "vcs", side_effect=lambda *a: (0, "") if a[:1] == ("rev-parse",) and "origin/main" in a else (1, "")):
            mockups_check.check_in_flight({"id": "b", "inFlight": {"branch": "claude/gone"}})
        self.assertTrue(any("deleted from origin" in p for p in mockups_check.problems))

    def test_in_flight_merged_branch_fails_and_open_branch_passes(self):
        def vcs(*a):
            if a[0] in ("config", "symbolic-ref"):
                return 1, ""
            if a[0] == "rev-parse":
                return 0, "sha"
            if a[0] == "merge-base":
                return (0, "") if a[-2] == "origin/claude/merged" else (1, "")
            return 0, "+ abc"  # cherry: one commit not on main
        with mock.patch.object(mockups_check, "vcs", side_effect=vcs):
            mockups_check.check_in_flight({"id": "m", "inFlight": {"branch": "claude/merged"}})
            self.assertEqual(len(mockups_check.problems), 1)
            mockups_check.check_in_flight({"id": "o", "inFlight": {"branch": "claude/open"}})
        self.assertEqual(len(mockups_check.problems), 1)

    def test_squash_merged_branch_fails(self):
        def vcs(*a):
            if a[0] in ("config", "symbolic-ref"):
                return 1, ""  # no recorded base, no remote default: origin/main
            if a[0] == "rev-parse" and a[-1].endswith("^{tree}"):
                return 0, "tree123"
            if a[0] == "rev-parse":
                return 0, "sha"
            if a[0] == "merge-base":
                return 1, ""
            if a[0] == "cherry":
                return 0, "+ abc"
            return 0, "tree123\n"  # merge-tree: the merge result is origin/main's own tree
        with mock.patch.object(mockups_check, "vcs", side_effect=vcs), mock.patch.object(mockups_check.subprocess, "run", side_effect=OSError):
            mockups_check.check_in_flight({"id": "sq", "inFlight": {"branch": "claude/squashed"}})
        self.assertTrue(any("squash" in p for p in mockups_check.problems))

    def test_in_flight_equal_to_the_head_branch_fails(self):
        entry = {"id": "h", "inFlight": {"branch": "claude/mine"}}
        with mock.patch.dict(os.environ, {"GITHUB_HEAD_REF": "claude/mine"}):
            mockups_check.check_in_flight(entry)
        self.assertTrue(any("own head branch" in p for p in mockups_check.problems))

    def test_head_falls_back_to_the_checked_out_branch(self):
        def vcs(*a):
            return (0, "claude/mine") if a[:2] == ("rev-parse", "--abbrev-ref") else (0, "sha")
        env = {k: v for k, v in os.environ.items() if k != "GITHUB_HEAD_REF"}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(mockups_check, "vcs", side_effect=vcs):
            mockups_check.check_in_flight({"id": "h", "inFlight": {"branch": "claude/mine"}})
        self.assertTrue(any("own head branch" in p for p in mockups_check.problems))

    def test_head_on_the_workflow_base_passes(self):
        """A PR from another branch into claude/uikit-port, with an unmerged marker for a third branch, is clean."""
        calls = []

        def vcs(*a):
            calls.append(a)
            if a[0] in ("config", "symbolic-ref"):
                return 1, ""
            if a[0] == "merge-base":
                return 1, ""
            if a[0] == "merge-tree":
                return 0, "mergedtree"
            return (0, "+ abc") if a[0] == "cherry" else (0, "sha")
        env = {"GITHUB_HEAD_REF": "claude/other", "GITHUB_BASE_REF": "claude/uikit-port"}
        with mock.patch.dict(os.environ, env), mock.patch.object(mockups_check, "vcs", side_effect=vcs), \
                mock.patch.object(mockups_check.subprocess, "run", side_effect=OSError):
            mockups_check.check_in_flight({"id": "o", "inFlight": {"branch": "claude/open"}})
            self.assertEqual(mockups_check.base_ref(), "origin/claude/uikit-port")
        self.assertEqual(mockups_check.problems, [])
        self.assertIn(("merge-base", "--is-ancestor", "origin/claude/open", "origin/claude/uikit-port"), calls)

    def test_missing_base_ref_falls_back_to_main(self):
        with mock.patch.dict(os.environ, {"GITHUB_BASE_REF": "gone"}), mock.patch.object(mockups_check, "vcs", return_value=(1, "")):
            self.assertEqual(mockups_check.base_ref(), "origin/main")

    def test_local_base_is_the_recorded_sh_base_then_the_remote_default_then_main(self):
        def vcs(recorded, default):
            def run(*a):
                if a[:2] == ("rev-parse", "--abbrev-ref"):
                    return 0, "agents/x"
                if a[0] == "config":
                    return (0, recorded) if recorded else (1, "")
                if a[0] == "symbolic-ref":
                    return (0, default) if default else (1, "")
                return 1, ""
            return run
        for recorded, default, want in (("origin/claude/uikit-port", "origin/main", "origin/claude/uikit-port"),
                                        ("", "origin/claude/uikit-port", "origin/claude/uikit-port"),
                                        ("", "", "origin/main")):
            with mock.patch.object(mockups_check, "vcs", side_effect=vcs(recorded, default)):
                self.assertEqual(mockups_check.base_ref(), want)

    def test_declared_sources_reads_strings_and_objects(self):
        text = "x({ source: ['apple/A.swift', { path: '.agents/b.md', note: '(n)' }], spec: ['.agents/c.md'] })"
        self.assertEqual(mockups_check.declared_sources(text), ["apple/A.swift", ".agents/b.md"])


if __name__ == "__main__":
    unittest.main()
