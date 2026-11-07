"""Unit tests for ``tools/release/versioning.py`` against throwaway git repositories."""

import datetime as dt
import io
import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from tools.release import versioning as v

OCT = dt.datetime(2026, 10, 1, 12, tzinfo=dt.timezone.utc)
NOV = dt.datetime(2026, 11, 2, 12, tzinfo=dt.timezone.utc)
SRC = "apple/Sources/HassUI/"


class Repo:
    """A scratch git repository with helpers for commits, merges and tags."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.run("init", "-q", "-b", "main")
        self.run("config", "user.email", "t@example.com")
        self.run("config", "user.name", "T")
        self.run("config", "commit.gpgsign", "false")
        self.run("config", "tag.gpgsign", "false")
        self.git = v.Git(root)

    def run(self, *args: str) -> str:
        return subprocess.run(["git", "-C", str(self.root)] + list(args), check=True,
                              capture_output=True, text=True).stdout

    def commit(self, message: str, *paths: str) -> str:
        for path in paths:
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text((target.read_text() if target.exists() else "") + message + "\n")
            self.run("add", path)
        self.run("commit", "-q", "--allow-empty", "-m", message)
        return self.run("rev-parse", "HEAD").strip()

    def tag(self, name: str, ref: str = "HEAD") -> None:
        self.run("tag", "-a", name, ref, "-m", name)


class VersionTests(unittest.TestCase):
    def test_parse_and_format(self):
        self.assertEqual(v.parse_version("2610.01.01"), (2610, 1, 1))
        self.assertEqual(v.parse_version("2610.31.99"), (2610, 31, 99))
        for bad in ("2610.01", "2610.1.01", "2610.01.1", "2610.01.100", "1.0", "2613.01.01", "2600.01.01",
                    "2610.00.01", "2610.32.01", "2610.01.00", "abc", ""):
            self.assertFalse(v.is_version(bad), bad)
        self.assertEqual(v.format_version(2610, 1, 7), "2610.01.07")
        with self.assertRaises(ValueError):
            v.format_version(2610, 1, 100)

    def test_next_version_resets_daily_and_never_goes_back(self):
        self.assertEqual(v.next_version(None, OCT), "2610.01.01")
        self.assertEqual(v.next_version("2610.01.01", OCT), "2610.01.02")
        self.assertEqual(v.next_version("2610.01.07", NOV), "2611.02.01")
        self.assertEqual(v.next_version("2610.01.07", OCT + dt.timedelta(days=1)), "2610.02.01")
        self.assertEqual(v.next_version("2611.02.03", OCT), "2611.02.04")
        with self.assertRaises(ValueError):
            v.next_version("2610.01.99", OCT)
        pdt = dt.datetime(2026, 9, 30, 20, tzinfo=dt.timezone(dt.timedelta(hours=-7)))
        self.assertEqual(v.next_version(None, pdt), "2610.01.01")  # UTC date

    def test_ordering_is_numeric(self):
        ordered = sorted(["2610.10.01", "2610.02.11", "2611.01.01", "2610.02.02", "2609.30.50"],
                         key=v.parse_version)
        self.assertEqual(ordered, ["2609.30.50", "2610.02.02", "2610.02.11", "2610.10.01", "2611.01.01"])

    def test_tags(self):
        self.assertEqual(v.tag_for("ios", "2610.01.01"), "ios/v2610.01.01")
        self.assertEqual(v.parse_tag("refs/tags/ios/v2610.12.03"), ("ios", "2610.12.03"))
        for bad in ("ios/released/2610.01.01", "android/v2610.01.01", "ios/v2610.01", "v2610.01.01"):
            with self.assertRaises(ValueError):
                v.parse_tag(bad)


class PathAndTrailerTests(unittest.TestCase):
    def test_app_paths(self):
        self.assertTrue(v.matches("ios", SRC + "Features/Rooms/RoomsView.swift"))
        self.assertTrue(v.matches("ios", "apple/Sources/HassCore/Rooms/RoomsConfig.swift"))
        self.assertTrue(v.matches("ios", "apple/Apps/iOS/Info.plist"))
        self.assertTrue(v.matches("ios", "apple/Apps/watchOS/FentonHomeWatchApp.swift"))
        self.assertTrue(v.matches("ios", "apple/Apps/Widgets/HomeLiveActivity.swift"))
        self.assertTrue(v.matches("ios", "apple/project.yml"))
        self.assertTrue(v.matches("ios", "apple/Design/AppIcon/icon.png"))
        self.assertFalse(v.matches("ios", "apple/Tests/HassCoreTests/X.swift"))
        self.assertFalse(v.matches("ios", "apple/Apps/iOSTests/ScrollFitTests.swift"))
        self.assertFalse(v.matches("ios", "apple/Apps/iOSUITests/HomeJourneyTests.swift"))
        self.assertFalse(v.matches("ios", "apple/Sources/HassUI/README.md"))
        self.assertFalse(v.matches("ios", ".agents/workflow/versioning.md"))
        self.assertFalse(v.matches("ios", "tools/release/versioning.py"))

    def test_trailers(self):
        message = ("Fix rows\n\nBody text.\n\nRelease-Note: Rows load faster.\n"
                   "release-note-ios: iPhone rows load faster.\nRelease-Note-Android: ignored\n"
                   "Release-Note-Watch: none\nRelease-note:\n")
        self.assertEqual(v.parse_trailers(message), {"*": ["Rows load faster."], "ios": ["iPhone rows load faster."]})

    def test_merge_subject_uses_pr_title(self):
        self.assertEqual(v.subject("Merge pull request #4 from a/b\n\nFix the Rooms tab\n"), "Fix the Rooms tab")
        self.assertEqual(v.subject("Plain subject\n\nbody"), "Plain subject")


class GitFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Repo(Path(self.tmp.name))
        self.repo.commit("Initial app", "apple/Sources/HassCore/A.swift")

    def tearDown(self):
        self.tmp.cleanup()

    def test_plan_bump_first_then_only_on_app_changes(self):
        git = self.repo.git
        plan = v.plan_bump(git, "ios", "HEAD", OCT)
        self.assertEqual((plan["bump"], plan["reason"], plan["version"]), (True, "first_version", "2610.01.01"))
        self.repo.tag("ios/v2610.01.01")
        self.assertEqual(v.plan_bump(git, "ios", "HEAD", OCT)["reason"], "already_tagged")
        self.repo.commit("Docs only", "docs/x.md", "apple/Tests/HassCoreTests/T.swift")
        self.assertEqual(v.plan_bump(git, "ios", "HEAD", OCT)["reason"], "no_app_changes")
        forced = v.plan_bump(git, "ios", "HEAD", OCT, force=True)
        self.assertEqual((forced["reason"], forced["version"]), ("forced", "2610.01.02"))
        self.repo.commit("Change", SRC + "B.swift")
        plan = v.plan_bump(git, "ios", "HEAD", NOV)
        self.assertEqual((plan["reason"], plan["version"], plan["previous"]),
                         ("app_changed", "2611.02.01", "2610.01.01"))

    def test_no_app_files_means_no_first_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Repo(Path(tmp))
            repo.commit("Docs", "README.md")
            self.assertEqual(v.plan_bump(repo.git, "ios", "HEAD", OCT)["reason"], "no_app_files")

    def test_bump_tags_and_is_idempotent(self):
        result = v.bump(self.repo.git, ["ios"], "HEAD", OCT)
        self.assertEqual([b["tag"] for b in result["bumped"]], ["ios/v2610.01.01"])
        self.assertEqual(self.repo.git.version_tags("ios"), [("2610.01.01", "ios/v2610.01.01")])
        self.assertEqual(self.repo.run("tag", "-l", "-n1", "ios/v*").split(None, 1)[1].strip(),
                         "iOS 2610.01.01 (first_version)")
        again = v.bump(self.repo.git, ["ios"], "HEAD", OCT)
        self.assertEqual((again["bumped"], again["skipped"][0]["reason"]), ([], "already_tagged"))

    def test_bump_push_publishes_the_tag(self):
        with tempfile.TemporaryDirectory() as tmp:
            origin = Path(tmp) / "origin.git"
            subprocess.run(["git", "init", "-q", "--bare", str(origin)], check=True)
            self.repo.run("remote", "add", "origin", str(origin))
            v.bump(self.repo.git, ["ios"], "HEAD", OCT, push=True)
            remote = subprocess.run(["git", "-C", str(origin), "tag", "-l"], capture_output=True, text=True).stdout
            self.assertEqual(remote.split(), ["ios/v2610.01.01"])

    def test_late_run_for_older_commit_does_not_bump(self):
        old = self.repo.git.rev("HEAD")
        self.repo.commit("Change", SRC + "B.swift")
        self.repo.tag("ios/v2610.01.01")
        self.assertEqual(v.plan_bump(self.repo.git, "ios", old, OCT)["reason"], "behind_previous_tag")

    def _history(self):
        """2610.01.01 (released) → 2610.01.02 → 2610.01.03, with notes between."""
        r = self.repo
        r.tag("ios/v2610.01.01")
        r.commit("Speed up rooms\n\nRelease-Note: Rooms: Rooms load faster.", SRC + "R.swift")
        r.tag("ios/v2610.01.02")
        r.commit("Cameras\n\nRelease-Note-iOS: Cameras: The live view opens sooner.", SRC + "C.swift")
        r.commit("Refactor\n\nRelease-Note: none", SRC + "D.swift")
        r.commit("Merge pull request #7 from x/y\n\n[Bug] Fix the Duo hinge (#7)", SRC + "E.swift")
        r.tag("ios/v2610.01.03")

    def test_user_notes_between_tags(self):
        self._history()
        git = self.repo.git
        self.assertEqual(v.user_notes(git, "ios", "ios/v2610.01.01", "ios/v2610.01.02"),
                         ["Rooms: Rooms load faster."])
        # Table order: Rooms, then Cameras, then uncategorized; an untrailered merged PR contributes its cleaned
        # title, and ``Release-Note: none`` contributes nothing.
        self.assertEqual(v.user_notes(git, "ios", "ios/v2610.01.01", "ios/v2610.01.03"),
                         ["Rooms: Rooms load faster.", "Cameras: The live view opens sooner.", "Fix the Duo hinge"])
        self.assertEqual(v.user_notes(git, "ios", "ios/v2610.01.02", "ios/v2610.01.03"),
                         ["Cameras: The live view opens sooner.", "Fix the Duo hinge"])

    def test_release_notes_markdown(self):
        self._history()
        git = self.repo.git
        text = v.release_notes(git, "ios/v2610.01.03")
        self.assertIn("## What's new in 2610.01.03", text)
        self.assertIn("- Cameras: The live view opens sooner.", text)
        self.assertIn("Changes since `ios/v2610.01.02`.", text)
        self.assertNotIn("Refactor", text)
        first = v.release_notes(git, "ios/v2610.01.01")
        self.assertNotIn("Changes since", first)
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(v.main(["--repo", str(self.repo.root), "notes", "--tag", "ios/v2610.01.03"]), 0)
        self.assertEqual(out.getvalue(), text)

    def test_notes_are_the_net_difference_replaces_tester_and_reverts(self):
        r = self.repo
        r.tag("ios/v2610.01.01")
        r.commit("a\n\nRelease-Note: Rooms: Rows fade in slowly.", SRC + "S1.swift")
        r.commit("b\n\nRelease-Note: Rooms: Rows fade in quickly.\nRelease-Note-Replaces: Rows fade in slowly.",
                 SRC + "S2.swift")
        r.commit("c\n\nRelease-Note: Settings: Reset asks first.", SRC + "S3.swift")
        reverted = r.git("rev-parse", "HEAD").strip()
        r.commit('Revert "c"\n\nThis reverts commit %s.' % reverted, SRC + "S3.swift")
        r.commit("d\n\nRelease-Note-Tester-iOS: Fixed a crash in the new row fade.", SRC + "S4.swift")
        r.tag("ios/v2610.01.02")
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.01", "ios/v2610.01.02"),
                         ["Rooms: Rows fade in quickly."])
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.01", "ios/v2610.01.02", tester=True),
                         ["Rooms: Rows fade in quickly.", "Fixed a crash in the new row fade."])
        # A notes-only commit (no app files) can undo an unreleased note.
        r.commit("Notes\n\nRelease-Note-Replaces: Rooms: Rows fade in quickly.", "docs/notes.md")
        r.tag("ios/v2610.01.03")
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.01", "ios/v2610.01.03"), [])
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.02", "ios/v2610.01.03"), [])
        self.assertEqual(v.parse_revisions("Release-Note-Replaces: A note.\nRelease-Note-Tester-Watch: T.\n"
                                           "Release-Note-Tester: none"),
                         ({"*": ["A note."]}, {"ios": ["T."]}))

    def test_commits_reverted_inside_a_merge_leave_no_notes(self):
        r = self.repo
        r.tag("ios/v2610.01.01")
        r.run("checkout", "-q", "-b", "report")
        r.commit("Bad\n\nRelease-Note: Rooms: Wrong.", SRC + "A.swift")
        bad = r.git("rev-parse", "HEAD").strip()
        r.commit('Revert "Bad"\n\nThis reverts commit %s.' % bad, SRC + "A.swift")
        r.commit("Good\n\nRelease-Note: Rooms: Tools sit next to search.", SRC + "B.swift")
        r.run("checkout", "-q", "main")
        r.commit("Earlier\n\nRelease-Note: Rooms: Keep me.", SRC + "C.swift")
        r.run("merge", "-q", "--no-ff", "report", "-m", "Merge pull request #9 from x/report\n\nTools")
        r.tag("ios/v2610.01.02")
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.01", "ios/v2610.01.02"),
                         ["Rooms: Keep me.", "Rooms: Tools sit next to search."])

    def test_pending_notes_follow_the_latest_release_tag(self):
        self._history()
        self.repo.commit("x\n\nRelease-Note-Tester: Fixed the new refresh.", SRC + "R2.swift")
        before = v.pending_notes(self.repo.git, "ios")
        self.assertIsNone(before["release"])
        self.repo.tag("ios/released/2610.01.02")
        after = v.pending_notes(self.repo.git, "ios")
        self.assertEqual(after["release"], "2610.01.02")
        self.assertNotIn("Rooms: Rooms load faster.", after["notes"])
        self.assertIn("Cameras: The live view opens sooner.", after["notes"])
        self.assertEqual(after["tester"], ["Fixed the new refresh."])
        self.assertEqual(self.repo.git.released_from_tags("ios"), ["2610.01.02"])

    def test_check_notes_requires_a_trailer_for_app_changes(self):
        r = self.repo
        base = r.git.rev("HEAD")
        r.commit("Docs", "docs/a.md")
        self.assertEqual(v.notes_check(r.git, base, "HEAD"), {"platforms": [], "has_release_note": False, "ok": True})
        r.commit("Tweak rows", SRC + "Row.swift")
        missing = v.notes_check(r.git, base, "HEAD")
        self.assertEqual((missing["platforms"], missing["ok"]), (["ios"], False))
        self.assertTrue(v.notes_check(r.git, base, "HEAD", "Fix\n\nRelease-Note: none")["ok"])
        r.commit("More\n\nRelease-Note-iOS: Rows are taller.", SRC + "Row2.swift")
        self.assertTrue(v.notes_check(r.git, base, "HEAD")["ok"])
        body = r.root / "body.md"
        body.write_text("no trailer", encoding="utf-8")
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(v.main(["--repo", str(r.root), "check-notes", "--base", base, "--head", "HEAD~1",
                                     "--body-file", str(body)]), 1)
            self.assertEqual(v.main(["--repo", str(r.root), "check-notes", "--base", base, "--head", "HEAD"]), 0)

    def test_notes_are_grouped_by_category(self):
        notes = ["Settings: Reset asks first.", "Fixed a crash.", "Rooms: Rows fade in once.",
                 "cameras: The live view reconnects.", "Rooms: Pull to refresh works.", "Note: not a category."]
        self.assertEqual(v.by_category(notes), [
            "Rooms: Rows fade in once.", "Rooms: Pull to refresh works.", "cameras: The live view reconnects.",
            "Settings: Reset asks first.", "Fixed a crash.", "Note: not a category."])
        self.assertEqual(v.note_category("Live Activities: The island shows the job."), "Live Activities")
        self.assertIsNone(v.note_category("Rooms:no space"))
        self.assertEqual(v.infer_category("The thermostat dial is smoother"), "Climate")
        self.assertEqual(v.infer_category("Camera notifications show a live view"), "Cameras")
        self.assertIsNone(v.infer_category("Something happened"))
        self.assertEqual(v.strip_category("Rooms: Rows fade in once."), "Rows fade in once.")

    def test_clean_title(self):
        self.assertEqual(v.clean_title("[Bug] fix the hinge (#12)"), "Fix the hinge")
        self.assertEqual(v.clean_title("iOS widgets refresh"), "iOS widgets refresh")


class CommandLineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Repo(Path(self.tmp.name))
        self.repo.commit("Initial app", "apple/Sources/HassCore/A.swift")

    def tearDown(self):
        self.tmp.cleanup()

    def cli(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out):
            code = v.main(["--repo", str(self.repo.root)] + list(argv))
        return code, out.getvalue()

    def test_bump_describe_and_build_settings_round_trip(self):
        code, out = self.cli("bump", "--now", "2026-10-26T09:00:00Z")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["bumped"][0]["tag"], "ios/v2610.26.01")
        code, out = self.cli("latest-tag")
        self.assertEqual(json.loads(out), {"platform": "ios", "tag": "ios/v2610.26.01", "version": "2610.26.01"})
        sha = self.repo.git.rev("HEAD")
        code, out = self.cli("describe", "--tag", "ios/v2610.26.01", "--build", "57")
        self.assertEqual(json.loads(out), {"platform": "ios", "version": "2610.26.01", "tag": "ios/v2610.26.01",
                                           "sha": sha, "previous": None, "build": "57"})
        code, out = self.cli("build-settings", "--tag", "ios/v2610.26.01", "--build", "57")
        self.assertEqual(out.split("\n"), ["MARKETING_VERSION=2610.26.01", "CURRENT_PROJECT_VERSION=57",
                                           "HASS_GIT_SHA=" + sha, ""])

    def test_bump_force_second_version_same_day(self):
        self.cli("bump", "--now", "2026-10-26T09:00:00Z")
        code, out = self.cli("bump", "--now", "2026-10-26T10:00:00Z")
        self.assertEqual(json.loads(out)["skipped"][0]["reason"], "already_tagged")
        self.repo.commit("Change", SRC + "B.swift")
        code, out = self.cli("bump", "--now", "2026-10-26T11:00:00Z")
        self.assertEqual(json.loads(out)["bumped"][0]["version"], "2610.26.02")

    def test_errors_are_json_and_exit_one(self):
        code, out = self.cli("describe", "--tag", "ios/v1.0")
        self.assertEqual(code, 1)
        self.assertIn("not a version tag", json.loads(out)["error"])

    def test_pending_notes_cli(self):
        self.repo.tag("ios/v2610.01.01")
        self.repo.commit("a\n\nRelease-Note: Rooms: Faster.", SRC + "A.swift")
        code, out = self.cli("pending-notes")
        doc = json.loads(out)
        self.assertEqual((doc["release"], doc["notes"]), (None, ["Rooms: Faster."]))
        code, out = self.cli("pending-notes", "--released", "2610.01.01")
        self.assertEqual(json.loads(out)["release"], "2610.01.01")


if __name__ == "__main__":
    unittest.main()
