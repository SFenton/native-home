"""Release health (``tools/release_health.py``): the three class checks and the one-issue-per-class sync. No network."""

import datetime as dt
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_health as rh  # noqa: E402

UTC = dt.timezone.utc
NOW = dt.datetime(2026, 11, 10, 6, 0, tzinfo=UTC)


def ago(days):
    return NOW - dt.timedelta(days=days)


def failing(cls, fingerprint="f1", detail="broken"):
    return rh.state(cls, rh.FAILING, fingerprint, detail)


class FakeGit:
    """A ``git`` callable answering the few commands the check makes."""

    def __init__(self, tags=("ios/v2611.01.01",), changed=("apple/Sources/HassUI/A.swift",), created="2026-11-01T00:00:00+00:00"):
        self.tags, self.changed, self.created = list(tags), list(changed), created

    def __call__(self, *args):
        if args[0] == "tag":
            return "\n".join(self.tags)
        if args[0] == "rev-parse":
            return "head" if args[-1].startswith("origin") else "tag" + args[-1]
        if args[0] == "diff":
            return "\n".join(self.changed)
        if args[0] == "for-each-ref":
            return self.created
        raise AssertionError(args)


class NoTagTests(unittest.TestCase):
    def test_app_change_and_old_tag_fails(self):
        res = rh.check_no_tag({"reason": "app_changed", "previous": "2611.01.01"}, ago(9), NOW)
        self.assertEqual((res["status"], res["fingerprint"]), (rh.FAILING, "ios/v2611.01.01"))
        self.assertIn("9 days", res["detail"])

    def test_young_tag_is_ok(self):
        self.assertEqual(rh.check_no_tag({"reason": "app_changed", "previous": "x"}, ago(6), NOW)["status"], rh.OK)

    def test_exactly_seven_days_fails(self):
        self.assertEqual(rh.check_no_tag({"reason": "app_changed", "previous": "x"}, ago(7), NOW)["status"], rh.FAILING)

    def test_nothing_waiting_is_ok_however_old(self):
        for reason in ("no_app_changes", "already_tagged", "behind_previous_tag"):
            self.assertEqual(rh.check_no_tag({"reason": reason, "previous": "x"}, ago(90), NOW)["status"], rh.OK, reason)

    def test_no_tag_at_all_with_app_files_fails(self):
        self.assertEqual(rh.check_no_tag({"reason": "first_version", "previous": None}, None, NOW)["status"], rh.FAILING)

    def test_unreadable_date_is_unknown(self):
        self.assertEqual(rh.check_no_tag({"reason": "app_changed", "previous": "x"}, None, NOW)["status"], rh.UNKNOWN)


class ReleaseFailedTests(unittest.TestCase):
    def test_newest_failure_fails_and_links_the_run(self):
        res = rh.check_release_failed([{"conclusion": "failure", "url": "https://x/runs/9", "databaseId": 9, "headSha": "abcdef0123456"}])
        self.assertEqual((res["status"], res["fingerprint"]), (rh.FAILING, "9"))
        self.assertIn("https://x/runs/9", res["detail"])

    def test_newest_success_is_ok_even_after_older_failure(self):
        runs = [{"conclusion": "success", "databaseId": 2}, {"conclusion": "failure", "databaseId": 1}]
        self.assertEqual(rh.check_release_failed(runs)["status"], rh.OK)

    def test_cancelled_and_skipped_are_passed_over(self):
        runs = [{"conclusion": "cancelled"}, {"conclusion": "skipped"}, {"conclusion": "failure", "databaseId": 4}]
        self.assertEqual(rh.check_release_failed(runs)["status"], rh.FAILING)
        runs = [{"conclusion": "cancelled"}, {"conclusion": "success"}, {"conclusion": "failure"}]
        self.assertEqual(rh.check_release_failed(runs)["status"], rh.OK)

    def test_no_runs_is_ok(self):
        self.assertEqual(rh.check_release_failed([])["status"], rh.OK)


class CertTests(unittest.TestCase):
    def test_parse_not_after_forms(self):
        want = dt.datetime(2027, 11, 10, 12, 0, 5, tzinfo=UTC)
        self.assertEqual(rh.parse_not_after("notAfter=Nov 10 12:00:05 2027 GMT"), want)
        self.assertEqual(rh.parse_not_after("Nov 10 12:00:05 2027 GMT"), want)
        self.assertEqual(rh.parse_not_after("2027-11-10T12:00:05Z"), want)
        self.assertIsNotNone(rh.parse_not_after("Nov  1 12:00:05 2027 GMT"))  # openssl pads single-digit days
        self.assertIsNone(rh.parse_not_after("garbage"))
        self.assertIsNone(rh.parse_not_after(""))

    def dates(self, dist, dev):
        def fmt(days):
            return (NOW + dt.timedelta(days=days)).strftime("%b %d %H:%M:%S %Y GMT")
        return {"Apple Distribution": fmt(dist), "Apple Development": fmt(dev)}

    def test_both_far_is_ok(self):
        self.assertEqual(rh.check_cert_expiry(self.dates(200, 100), NOW)["status"], rh.OK)

    def test_one_under_45_fails_and_names_it(self):
        res = rh.check_cert_expiry(self.dates(200, 44), NOW)
        self.assertEqual(res["status"], rh.FAILING)
        self.assertIn("Apple Development", res["fingerprint"])
        self.assertNotIn("Apple Distribution", res["fingerprint"])

    def test_exactly_45_days_is_ok_and_expired_fails(self):
        self.assertEqual(rh.check_cert_expiry(self.dates(45, 45), NOW)["status"], rh.OK)
        self.assertEqual(rh.check_cert_expiry(self.dates(-3, 300), NOW)["status"], rh.FAILING)

    def test_missing_dates_are_unknown_but_a_known_failure_still_fails(self):
        self.assertEqual(rh.check_cert_expiry({"Apple Distribution": "", "Apple Development": ""}, NOW)["status"], rh.UNKNOWN)
        dates = self.dates(10, 300)
        dates["Apple Development"] = ""
        self.assertEqual(rh.check_cert_expiry(dates, NOW)["status"], rh.FAILING)
        dates = self.dates(300, 300)
        dates["Apple Development"] = ""
        self.assertEqual(rh.check_cert_expiry(dates, NOW)["status"], rh.UNKNOWN)


class PlanTests(unittest.TestCase):
    def issue(self, cls, number=7, fingerprint="f1"):
        return {"number": number, "title": rh.TITLES[cls], "body": rh.render_body(failing(cls, fingerprint))}

    def test_titles_are_stable_and_unique(self):
        self.assertEqual(len(set(rh.TITLES.values())), 3)
        self.assertEqual(rh.TITLES["no-tag"], "Release health: no iOS version tag for 7 days")

    def test_failing_without_issue_creates_one(self):
        acts = rh.plan_actions([failing("no-tag")], [])
        self.assertEqual([a["do"] for a in acts], ["create"])
        self.assertEqual(acts[0]["title"], rh.TITLES["no-tag"])
        self.assertEqual(rh.fingerprint_of(acts[0]["body"], "no-tag"), "f1")

    def test_failing_with_same_fingerprint_does_nothing(self):
        self.assertEqual(rh.plan_actions([failing("no-tag")], [self.issue("no-tag")]), [])

    def test_changed_fingerprint_comments_and_rewrites_once(self):
        acts = rh.plan_actions([failing("no-tag", "f2", "new cause")], [self.issue("no-tag")])
        self.assertEqual([a["do"] for a in acts], ["update"])
        self.assertIn("new cause", acts[0]["comment"])
        self.assertEqual(rh.fingerprint_of(acts[0]["body"], "no-tag"), "f2")

    def test_healthy_closes_with_a_comment(self):
        acts = rh.plan_actions([rh.state("no-tag", rh.OK, detail="fine")], [self.issue("no-tag")])
        self.assertEqual([(a["do"], a["number"]) for a in acts], [("close", 7)])
        self.assertIn("Healthy again", acts[0]["comment"])

    def test_healthy_without_issue_and_unknown_do_nothing(self):
        self.assertEqual(rh.plan_actions([rh.state("no-tag", rh.OK)], []), [])
        self.assertEqual(rh.plan_actions([rh.state("no-tag", rh.UNKNOWN)], [self.issue("no-tag")]), [])

    def test_duplicates_fold_into_the_oldest(self):
        acts = rh.plan_actions([failing("no-tag")], [self.issue("no-tag", 9), self.issue("no-tag", 3)])
        self.assertEqual([(a["do"], a["number"]) for a in acts], [("fold", 9)])
        self.assertIn("#3", acts[0]["comment"])

    def test_classes_are_independent_and_other_issues_ignored(self):
        other = {"number": 1, "title": "Something else", "body": ""}
        acts = rh.plan_actions([failing("release-failed"), rh.state("cert-expiry", rh.OK)],
                               [other, self.issue("no-tag")])
        self.assertEqual([(a["do"], a["class"]) for a in acts], [("create", "release-failed")])

    def test_fingerprint_of_missing_marker(self):
        self.assertIsNone(rh.fingerprint_of("no marker", "no-tag"))
        self.assertIsNone(rh.fingerprint_of(rh.render_body(failing("cert-expiry")), "no-tag"))


class FakeRun:
    """Stands in for ``subprocess.run`` and records the ``gh`` calls."""

    def __init__(self, replies=None, code=0):
        self.calls, self.replies, self.code = [], replies or {}, code

    def __call__(self, cmd, input=None, capture_output=True, text=True):
        self.calls.append((cmd, input))
        key = " ".join(cmd[1:3])
        return mock.Mock(returncode=self.code, stdout=self.replies.get(key, ""), stderr="boom")


class GitHubTests(unittest.TestCase):
    def test_commands(self):
        run = FakeRun({"issue list": "[]", "run list": json.dumps([{"conclusion": "success"}])})
        gh = rh.GitHub("o/r", run=run)
        self.assertEqual(gh.open_issues(), [])
        self.assertEqual(gh.release_runs()[0]["conclusion"], "success")
        gh.create("T", "B")
        gh.edit_body(5, "B2")
        gh.comment(5, "C")
        gh.close(5)
        cmds = [" ".join(c[0][1:3]) for c in run.calls]
        self.assertEqual(cmds, ["issue list", "run list", "issue create", "issue edit", "issue comment", "issue close"])
        create = run.calls[2]
        self.assertIn("Workflow", create[0])
        self.assertEqual(create[1], "B")
        self.assertIn("ios-release.yml", run.calls[1][0])

    def test_dry_run_writes_nothing_and_failure_raises(self):
        run = FakeRun()
        gh = rh.GitHub("o/r", dry_run=True, run=run)
        with mock.patch("builtins.print"):
            gh.create("T", "B")
            gh.close(1)
        self.assertEqual(run.calls, [])
        with self.assertRaises(RuntimeError):
            rh.GitHub("o/r", run=FakeRun(code=1)).open_issues()

    def test_apply_actions(self):
        run = FakeRun()
        gh = rh.GitHub("o/r", run=run)
        did = rh.apply_actions(gh, [
            {"do": "create", "class": "a", "title": "T", "body": "B"},
            {"do": "update", "class": "b", "number": 2, "body": "B", "comment": "C"},
            {"do": "close", "class": "c", "number": 3, "comment": "C"},
            {"do": "fold", "class": "c", "number": 4, "comment": "C", "into": 3}])
        self.assertEqual(did, ["a: opened an issue", "b: updated #2", "c: closed #3", "c: closed #4"])
        self.assertEqual([" ".join(c[0][1:3]) for c in run.calls],
                         ["issue create", "issue edit", "issue comment", "issue comment", "issue close", "issue comment", "issue close"])


class CollectTests(unittest.TestCase):
    """The real ``versioning.plan_bump`` over a fake git: the shared "app changed since the tag" logic."""

    def collect(self, git):
        gh = mock.Mock()
        gh.release_runs.return_value = []
        dates = {"Apple Distribution": "", "Apple Development": ""}
        real = rh.load_versioning().Git(runner=lambda args: git(*args))
        return {r["class"]: r for r in rh.collect(real, gh, "origin/main", dates, NOW)}

    def test_old_tag_and_app_change_fails(self):
        git = FakeGit(created="2026-10-25T00:00:00+00:00")
        with mock.patch.object(rh.load_versioning().Git, "is_ancestor", return_value=True):
            res = self.collect(git)
        self.assertEqual(res["no-tag"]["status"], rh.FAILING)
        self.assertEqual(res["cert-expiry"]["status"], rh.UNKNOWN)

    def test_no_app_change_is_ok(self):
        git = FakeGit(changed=("README.md",), created="2026-10-25T00:00:00+00:00")
        with mock.patch.object(rh.load_versioning().Git, "is_ancestor", return_value=True):
            self.assertEqual(self.collect(git)["no-tag"]["status"], rh.OK)

    def test_a_failed_read_is_unknown_and_marks_the_run_red(self):
        gh = mock.Mock()
        gh.release_runs.side_effect = RuntimeError("gh run list failed")
        fake = FakeGit(changed=())
        results = rh.collect(rh.load_versioning().Git(runner=lambda args: fake(*args)), gh, "origin/main", {}, NOW)
        self.assertEqual({r["class"]: r["status"] for r in results}["release-failed"], rh.UNKNOWN)
        self.assertTrue(results[1]["detail"].startswith("read failed"))

    def test_tag_date_reads_creatordate(self):
        self.assertEqual(rh.tag_date(FakeGit(created="2026-11-01T02:00:00+02:00"), "ios/v1"),
                         dt.datetime(2026, 11, 1, tzinfo=UTC))
        self.assertIsNone(rh.tag_date(FakeGit(created=""), "ios/v1"))


class MainTests(unittest.TestCase):
    def test_main_end_to_end_dry_run(self):
        results = [failing("no-tag"), rh.state("release-failed", rh.OK, detail="ok"),
                   rh.state("cert-expiry", rh.UNKNOWN, detail="x")]
        with mock.patch.object(rh, "collect", return_value=results), \
                mock.patch.object(rh.GitHub, "open_issues", return_value=[]), \
                mock.patch("builtins.print") as printed:
            code = rh.main(["check", "--repo", "o/r", "--dry-run"])
        self.assertEqual(code, 0)
        text = "\n".join(str(c.args[0]) for c in printed.call_args_list)
        self.assertIn("[dry-run] gh issue create", text)
        self.assertIn("::warning", text)

    def test_main_needs_a_repo_and_reds_on_a_read_failure(self):
        with mock.patch.object(rh.os.environ, "get", return_value=""), mock.patch("sys.stderr"):
            self.assertEqual(rh.main(["check"]), 2)
        bad = [rh.state("no-tag", rh.UNKNOWN, detail="read failed: x")]
        with mock.patch.object(rh, "collect", return_value=bad), \
                mock.patch.object(rh.GitHub, "open_issues", return_value=[]), mock.patch("builtins.print"):
            self.assertEqual(rh.main(["check", "--repo", "o/r"]), 1)

    def test_summary_lists_every_class(self):
        text = rh.summary([failing("no-tag", detail="a|b")], ["no-tag: opened an issue"])
        self.assertIn("| no-tag | failing | a/b |", text)
        self.assertIn("Did: no-tag: opened an issue", text)
        self.assertIn("No issue changed.", rh.summary([], []))


if __name__ == "__main__":
    unittest.main()
