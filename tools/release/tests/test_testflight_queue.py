"""The TestFlight upload queue: order, ledger, catch-up after a dropped run, build-number monotonicity, failure stop."""

import datetime as dt
import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.release import testflight_queue as q
from tools.release.tests.test_versioning import Repo

UTC = dt.timezone.utc
NOW = dt.datetime(2026, 10, 29, 12, 30, tzinfo=UTC)
STAMP = 202610291230
SRC = "apple/Sources/HassUI/"


class PureTests(unittest.TestCase):
    def test_empty_ledger_takes_only_the_newest_or_the_given_start(self):
        versions = ["2610.28.01", "2610.29.01", "2610.29.02"]
        self.assertEqual(q.pending_versions(versions, []), ["2610.29.02"])
        self.assertEqual(q.pending_versions(versions, [], "2610.29.01"), ["2610.29.01", "2610.29.02"])
        self.assertEqual(q.pending_versions([], []), [])

    def test_ledger_floor_is_the_newest_uploaded_and_ignores_older_history(self):
        versions = ["2610.28.01", "2610.29.01", "2610.29.02", "2611.01.01"]
        self.assertEqual(q.pending_versions(versions, ["2610.29.01"]), ["2610.29.02", "2611.01.01"])
        # the start only bootstraps an empty ledger: it can never skip a version that is behind the ledger floor
        self.assertEqual(q.pending_versions(versions, ["2610.28.01"]), ["2610.29.01", "2610.29.02", "2611.01.01"])
        self.assertEqual(q.pending_versions(versions, ["2611.01.01"]), [])

    def test_order_is_numeric_across_months_and_counters(self):
        versions = ["2611.01.01", "2610.31.02", "2610.31.10", "2610.31.09"]
        self.assertEqual(q.pending_versions(versions, ["2610.30.01"]),
                         ["2610.31.02", "2610.31.09", "2610.31.10", "2611.01.01"])

    def test_build_numbers_strictly_increase_even_with_a_slow_or_wrong_clock(self):
        self.assertEqual(q.next_build([], NOW), STAMP)
        self.assertEqual(q.next_build([STAMP], NOW), STAMP + 1)  # the same minute twice
        self.assertEqual(q.next_build([STAMP + 500], NOW), STAMP + 501)  # clock behind the ledger
        self.assertEqual(q.next_build([202601010000], NOW), STAMP)
        builds, last = [], 0
        for _ in range(5):
            build = q.next_build(builds, NOW)
            self.assertGreater(build, last)
            builds.append(build)
            last = build


class QueueRepo:
    """A bare ``origin`` plus a clone with app commits on ``main`` and a stand-in upload script."""

    def __init__(self, test: unittest.TestCase) -> None:
        tmp = tempfile.TemporaryDirectory()
        test.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.origin = self.tmp / "origin.git"
        subprocess.run(["git", "init", "-q", "--bare", str(self.origin)], check=True)
        (self.tmp / "work").mkdir()
        self.repo = Repo(self.tmp / "work")
        self.repo.run("remote", "add", "origin", str(self.origin))
        self.git = q.v.Git(self.repo.root)
        self.log = self.tmp / "uploads.log"
        self.upload = self.tmp / "upload.sh"
        self.upload.write_text(
            "#!/bin/bash\n"
            "# stand-in for testflight_upload.sh: logs tag, build and the source tree's version, then optionally fails\n"
            "tag=''; build=''; src=''; dry=''\n"
            "while [ $# -gt 0 ]; do case \"$1\" in --tag) tag=$2; shift 2;; --build) build=$2; shift 2;;"
            " --source) src=$2; shift 2;; --dry-run) dry=1; shift;; *) shift;; esac; done\n"
            "echo \"$tag $build ${dry:+dry} $(git -C \"${src:-.}\" rev-parse HEAD 2>/dev/null)\" >> \"$UPLOAD_LOG\"\n"
            "[ -z \"$dry\" ] || exit 0\n"
            "[ \"$tag\" != \"${FAIL_TAG:-}\" ] || exit 7\n"
            "[ -z \"${HOOK:-}\" ] || bash -c \"$HOOK\"\n")
        self.upload.chmod(self.upload.stat().st_mode | stat.S_IXUSR)
        os.environ["UPLOAD_LOG"] = str(self.log)
        test.addCleanup(lambda: [os.environ.pop(k, None) for k in ("UPLOAD_LOG", "FAIL_TAG", "HOOK")])

    def release(self, version: str) -> str:
        """Commit an app change on main, tag it ``ios/v<version>`` and publish both."""
        sha = self.repo.commit("change " + version, SRC + "a.swift")
        self.repo.tag("ios/v" + version, sha)
        self.repo.run("push", "-q", "origin", "main", "ios/v" + version)
        return sha

    def uploads(self):
        if not self.log.exists():
            return []
        return [line.split() for line in self.log.read_text().splitlines()]

    def run(self, **kw) -> int:
        args = dict(extra=[], main_ref="origin/main", start=None, limit=10, dry_run=False, push=True, fetch=True,
                    now=NOW)
        args.update(kw)
        return q.run_queue(self.git, str(self.upload), **args)

    def remote_ledger(self):
        out = subprocess.run(["git", "-C", str(self.origin), "tag", "--list", "ios/tf/*"], capture_output=True,
                             text=True, check=True).stdout
        return out.split()


class QueueTests(unittest.TestCase):
    def setUp(self):
        self.r = QueueRepo(self)
        self.r.repo.commit("root", "README.md")
        self.r.repo.run("branch", "-M", "main")

    def test_several_bumps_at_once_upload_oldest_first_with_rising_builds(self):
        shas = [self.r.release(x) for x in ("2610.29.01", "2610.29.02", "2610.29.03")]
        self.assertEqual(self.r.run(start="ios/v2610.29.01"), 0)
        rows = self.r.uploads()
        self.assertEqual([row[0] for row in rows], ["ios/v2610.29.01", "ios/v2610.29.02", "ios/v2610.29.03"])
        builds = [int(row[1]) for row in rows]
        self.assertEqual(builds, sorted(set(builds)))  # strictly increasing though the clock never moved
        self.assertEqual(builds[0], STAMP)
        self.assertEqual([row[2] for row in rows], shas)  # each built from its own tag's tree
        self.assertEqual(self.r.remote_ledger(), ["ios/tf/2610.29.01", "ios/tf/2610.29.02", "ios/tf/2610.29.03"])
        self.assertIn("build=%d" % builds[1], self.r.repo.run("tag", "-l", "ios/tf/2610.29.02", "-n1"))

    def test_a_dropped_run_is_caught_up_by_the_next_one(self):
        self.r.release("2610.29.01")
        self.assertEqual(self.r.run(), 0)  # empty ledger: the newest tag only
        self.r.release("2610.29.02")  # its run was dropped (never started)
        self.r.release("2610.29.03")  # the surviving run for this tag uploads both, in order
        self.assertEqual(self.r.run(), 0)
        self.assertEqual([row[0] for row in self.r.uploads()],
                         ["ios/v2610.29.01", "ios/v2610.29.02", "ios/v2610.29.03"])
        self.assertEqual(self.r.run(), 0)  # nothing pending: nothing uploaded twice
        self.assertEqual(len(self.r.uploads()), 3)

    def test_a_failed_upload_stops_the_queue_and_is_retried_first(self):
        for x in ("2610.29.01", "2610.29.02", "2610.29.03"):
            self.r.release(x)
        os.environ["FAIL_TAG"] = "ios/v2610.29.02"
        self.assertEqual(self.r.run(start="ios/v2610.29.01"), 7)
        self.assertEqual([row[0] for row in self.r.uploads()], ["ios/v2610.29.01", "ios/v2610.29.02"])
        self.assertEqual(self.r.remote_ledger(), ["ios/tf/2610.29.01"])  # .03 never jumped the queue
        del os.environ["FAIL_TAG"]
        self.assertEqual(self.r.run(), 0)
        self.assertEqual([row[0] for row in self.r.uploads()][2:], ["ios/v2610.29.02", "ios/v2610.29.03"])
        builds = [int(row[1]) for row in self.r.uploads() if row[2] != "dry"]
        self.assertEqual(builds, sorted(builds))

    def test_a_version_that_lands_during_an_upload_joins_the_same_run(self):
        self.r.release("2610.29.01")
        sha = self.r.repo.commit("late", SRC + "b.swift")
        hook = ("git -C %s rev-parse -q --verify refs/tags/ios/v2610.29.02 || "
                "(git -C %s tag -a ios/v2610.29.02 %s -m late && git -C %s push -q origin ios/v2610.29.02)"
                % (self.r.repo.root, self.r.repo.root, sha, self.r.repo.root))
        self.r.repo.run("push", "-q", "origin", "main")
        os.environ["HOOK"] = hook
        # the stand-in creates the next tag while uploading the first; the loop re-reads the queue and takes it
        self.assertEqual(self.r.run(limit=2), 0)
        os.environ.pop("HOOK")
        self.assertEqual([row[0] for row in self.r.uploads()], ["ios/v2610.29.01", "ios/v2610.29.02"])

    def test_tags_not_on_main_are_never_built(self):
        self.r.release("2610.29.01")
        self.r.repo.run("checkout", "-q", "-b", "stray")
        sha = self.r.repo.commit("stray", SRC + "c.swift")
        self.r.repo.tag("ios/v2610.29.05", sha)
        self.r.repo.run("push", "-q", "origin", "stray", "ios/v2610.29.05")
        self.r.repo.run("checkout", "-q", "main")
        self.assertEqual(self.r.run(), 0)
        self.assertEqual([row[0] for row in self.r.uploads()], ["ios/v2610.29.01"])

    def test_a_dry_run_changes_nothing_and_predicts_rising_builds(self):
        for x in ("2610.29.01", "2610.29.02"):
            self.r.release(x)
        self.assertEqual(self.r.run(dry_run=True, start="ios/v2610.29.01"), 0)
        rows = self.r.uploads()
        self.assertEqual([(row[0], row[2]) for row in rows], [("ios/v2610.29.01", "dry"), ("ios/v2610.29.02", "dry")])
        self.assertEqual([int(row[1]) for row in rows], [STAMP, STAMP + 1])
        self.assertEqual(self.r.remote_ledger(), [])

    def test_max_limits_one_run_and_the_next_continues(self):
        for x in ("2610.29.01", "2610.29.02", "2610.29.03"):
            self.r.release(x)
        self.assertEqual(self.r.run(start="ios/v2610.29.01", limit=2), 0)
        self.assertEqual(len(self.r.uploads()), 2)
        self.assertEqual(self.r.run(limit=2), 0)
        self.assertEqual(len(self.r.uploads()), 3)

    def test_cli_pending_reports_the_queue(self):
        self.r.release("2610.29.01")
        out = subprocess.run(["python3", str(q.Path(q.__file__)), "--repo", str(self.r.repo.root), "pending",
                              "--main-ref", "main"], capture_output=True, text=True, check=True).stdout
        self.assertEqual(json.loads(out), {"pending": ["ios/v2610.29.01"], "ledger": {}})


if __name__ == "__main__":
    unittest.main()
