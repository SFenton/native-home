"""The runner's TestFlight dispatch after a landing (owner, 2026-11-03). Fake gh: nothing is dispatched for real."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import hass_triage as ht  # noqa: E402
from test_hass_triage import Base, FakeGitHub  # noqa: E402

PR = "https://github.com/SFenton/Fenton-HASS-Native/pull/50"


class TestFlightTests(Base):
    def setUp(self):
        super().setUp()
        self.gh = FakeGitHub()
        self.gh.variables["HASS_TESTFLIGHT_ENABLED"] = "true"
        self.r = self.runner(self.gh)

    def dispatches(self):
        return [c for c in self.gh.calls if c[0] == "dispatch"]

    def test_app_change_on_main_dispatches_once_an_hour(self):
        self.assertTrue(self.r.testflight_after(["apple/HassUI/A.swift"], "main", "lane x"))
        self.assertEqual(self.dispatches(), [("dispatch", "SFenton/Fenton-HASS-Native", "ios-release-build.yml", "main")])
        self.assertFalse(self.r.testflight_after(["apple/B.swift"], "main", "lane y"))
        self.assertEqual(len(self.dispatches()), 1)
        self.r.state.data["testflight"]["last_epoch"] -= ht.TESTFLIGHT_MIN_SECONDS + 1
        self.assertTrue(self.r.testflight_after(["apple/B.swift"], "main", "lane y"))
        self.assertEqual(len(self.dispatches()), 2)

    def test_a_merge_inside_the_window_is_kept_pending_and_dispatched_on_the_next_eligible_tick(self):
        self.assertTrue(self.r.testflight_after(["apple/A.swift"], "main", "lane x"))
        self.assertFalse(self.r.testflight_after(["apple/B.swift"], "main", "lane y"))
        self.assertEqual(self.r.state.data["testflight"]["pending"]["after"], "lane y")
        self.assertFalse(self.r.testflight_pending())  # still inside the window
        self.assertEqual(len(self.dispatches()), 1)
        self.r.state.data["testflight"]["last_epoch"] -= ht.TESTFLIGHT_MIN_SECONDS + 1
        self.assertTrue(self.r.testflight_pending())
        self.assertEqual(len(self.dispatches()), 2)
        self.assertNotIn("pending", self.r.state.data["testflight"])
        self.assertFalse(self.r.testflight_pending())  # nothing left to do
        self.assertEqual(len(self.dispatches()), 2)

    def test_pending_is_dropped_when_uploads_are_disabled(self):
        self.r.testflight_after(["apple/A.swift"], "main", "lane x")
        self.r.testflight_after(["apple/B.swift"], "main", "lane y")
        self.gh.variables["HASS_TESTFLIGHT_ENABLED"] = "false"
        self.r.state.data["testflight"]["last_epoch"] -= ht.TESTFLIGHT_MIN_SECONDS + 1
        self.assertFalse(self.r.testflight_pending())
        self.assertNotIn("pending", self.r.state.data["testflight"])

    def test_the_tick_dispatches_a_pending_upload(self):
        self.r.testflight_after(["apple/A.swift"], "main", "lane x")
        self.r.testflight_after(["apple/B.swift"], "main", "lane y")
        self.r.state.data["testflight"]["last_epoch"] -= ht.TESTFLIGHT_MIN_SECONDS + 1
        with mock.patch.object(self.r, "refresh_clone"), mock.patch.object(self.r, "check_base"), \
                mock.patch.object(self.r, "check_merging"), mock.patch.object(self.r, "check_parked"), \
                mock.patch.object(self.r, "requeue"), mock.patch.object(self.r, "recover"):
            self.r.tick(max_items=0)
        self.assertEqual(len(self.dispatches()), 2)

    def test_recorded_in_state_and_status_report(self):
        self.r.testflight_after(["apple/A.swift"], "main", "lane x")
        saved = ht.State(self.paths.state).data["testflight"]["dispatches"]
        self.assertEqual((saved[0]["after"], saved[0]["ref"]), ("lane x", "main"))
        report = ht.status_report(self.cfg, self.paths, self.gh)
        self.assertEqual(report["testflight"][0]["after"], "lane x")

    def test_skips(self):
        self.assertFalse(self.r.testflight_after(["tools/x.py", "docs/a.md"], "main", "w"))  # no app code
        self.assertFalse(self.r.testflight_after(["apple/A.swift"], "claude/uikit-port", "w"))  # not the product base
        self.gh.variables["HASS_TESTFLIGHT_ENABLED"] = ""
        self.assertFalse(self.r.testflight_after(["apple/A.swift"], "main", "w"))  # workflow gate off
        self.cfg["testflight_autoupload"] = False
        self.gh.variables["HASS_TESTFLIGHT_ENABLED"] = "true"
        self.assertFalse(self.r.testflight_after(["apple/A.swift"], "main", "w"))  # config off
        self.assertEqual(self.dispatches(), [])

    def test_default_is_on(self):
        self.assertTrue(ht.load_config(self.home)["testflight_autoupload"])

    def test_dry_run_dispatches_nothing(self):
        r = self.runner(self.gh, dry_run=True)
        self.assertFalse(r.testflight_after(["apple/A.swift"], "main", "w"))

    def test_dispatch_failure_is_not_fatal_and_not_recorded(self):
        with mock.patch.object(self.gh, "dispatch_workflow", side_effect=ht.TriageError("boom")):
            self.assertFalse(self.r.testflight_after(["apple/A.swift"], "main", "w"))
        self.assertNotIn("last_epoch", self.r.state.data.get("testflight", {}))

    def test_merged_product_pr_dispatches(self):
        self.gh.pull_files[PR] = {"base": "main", "paths": ["apple/HassUI/A.swift"]}
        self.r.testflight_after_pr(PR)
        self.assertEqual(len(self.dispatches()), 1)

    def test_pr_docs_only_does_not(self):
        self.gh.pull_files[PR] = {"base": "main", "paths": [".agents/x.md"]}
        self.r.testflight_after_pr(PR)
        self.assertEqual(self.dispatches(), [])

    def test_pr_listing_failure_is_swallowed(self):
        with mock.patch.object(self.gh, "pull_paths", side_effect=ht.TriageError("x")):
            self.r.testflight_after_pr(PR)
        self.assertEqual(self.dispatches(), [])

    def test_check_merging_triggers_it(self):
        self.gh.issues[7] = {"number": 7, "title": "t", "state": "OPEN", "labels": [{"name": "Merging"}], "author": {"login": "SFenton"},
                             "body": "", "comments": []}
        self.gh.pulls[PR] = {"state": "MERGED", "labels": [], "url": PR}
        self.gh.pull_files[PR] = {"base": "main", "paths": ["apple/A.swift"]}
        self.r.state.data["merging"]["7"] = {"pr": PR, "status": {"summary": "s", "tests_passed": True}, "since": 9e12}
        with mock.patch.object(self.r, "finish_done"):
            self.r.check_merging()
        self.assertEqual(len(self.dispatches()), 1)

    def test_gh_seam_builds_the_commands(self):
        calls = []
        real = ht.GitHub()
        real._gh = lambda args, input_text=None: calls.append(args) or '{"baseRefName":"main","files":[{"path":"apple/a"}]}'
        real._write = lambda args, input_text=None: calls.append(args) or "{}"
        self.assertEqual(real.pull_paths(PR), {"base": "main", "paths": ["apple/a"]})
        real.dispatch_workflow("o/r", "ios-release-build.yml", "main")
        self.assertEqual(calls[-1], ["workflow", "run", "ios-release-build.yml", "-R", "o/r", "--ref", "main"])
        self.assertEqual(real.variable("o/r", "V"), '{"baseRefName":"main","files":[{"path":"apple/a"}]}')

        def boom(args, input_text=None):
            raise ht.TriageError("none")
        real._gh = boom
        self.assertEqual(real.variable("o/r", "V"), "")


if __name__ == "__main__":
    unittest.main()
