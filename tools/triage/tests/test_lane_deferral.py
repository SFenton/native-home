"""Tests for the lane deferral in ``eligible``: a follow-up naming an unlanded ``agents/`` branch waits for its lane issue.

Run from the repository root: python3 -m unittest discover -s tools/triage/tests -t .
"""
from __future__ import annotations

import io
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import hass_triage as ht  # noqa: E402
from test_hass_triage import Base, FakeGitHub, issue  # noqa: E402

LANE_A = "agents/alpha-ship-261101"
LANE_B = "agents/beta-retry-261101"


def lane(n: int, branch: str, kind: str = "review", created: str = "2026-10-13T12:00:00Z", **extra):
    """A runner-filed lane issue; its own body names its branch."""
    extra.setdefault("body", f"The runner did not merge `{branch}` into main.")
    return issue(n, title=ht.lane_issue_title(branch, kind), created=created, **extra)


def follow_up(n: int, *branches: str, created: str = "2026-10-13T09:00:00Z", **extra):
    return issue(n, title="[Task] Follow-up", body="Pick this up after " + " and ".join(f"`{b}`" for b in branches) + " land.",
                 created=created, **extra)


def numbers(issues, **kw):
    return [i["number"] for i in ht.eligible(issues, ["SFenton"], kw.get("label"), kw.get("agent", ""))]


class LaneTitleTests(unittest.TestCase):
    def test_the_title_round_trips(self):
        self.assertEqual(ht.lane_issue_title(LANE_A, "tests"), f"Workflow: lane {LANE_A} not landed (tests)")
        self.assertEqual(ht.lane_of_title(ht.lane_issue_title(LANE_A, "tests")), LANE_A)

    def test_other_titles_name_no_lane(self):
        for title in ("[Bug] Thing", "Workflow: lane  not landed (x)", f"Workflow: lane {LANE_A} landed (x)", ""):
            self.assertIsNone(ht.lane_of_title(title))


class DeferralTests(unittest.TestCase):
    def test_a_follow_up_waits_while_both_lane_issues_are_open(self):
        issues = [follow_up(35, LANE_A, LANE_B), lane(36, LANE_A), lane(37, LANE_B, "tests")]
        self.assertEqual(numbers(issues), [36, 37])
        self.assertEqual(ht.deferred(issues, ["SFenton"]), {35: [36, 37]})

    def test_it_still_waits_while_one_remains(self):
        self.assertEqual(numbers([follow_up(35, LANE_A, LANE_B), lane(37, LANE_B, "tests")]), [37])

    def test_it_is_picked_once_both_are_closed(self):
        self.assertEqual(numbers([follow_up(35, LANE_A, LANE_B)]), [35])

    def test_a_second_pair_defers_the_same_way(self):
        issues = [follow_up(38, LANE_A), lane(39, LANE_A, "paths")]
        self.assertEqual(numbers(issues), [39])
        self.assertEqual(ht.deferred(issues, ["SFenton"]), {38: [39]})

    def test_a_branch_with_no_open_lane_issue_keeps_oldest_first(self):
        issues = [follow_up(35, LANE_A, created="2026-10-13T09:00:00Z"), issue(5, created="2026-10-13T10:00:00Z")]
        self.assertEqual(numbers(issues), [35, 5])
        self.assertEqual(ht.deferred(issues, ["SFenton"]), {})

    def test_a_longer_branch_name_does_not_match_a_shorter_lane_issue(self):
        short, long_ = "agents/nightly-ship-order-261110", "agents/nightly-ship-order-2-261110"
        self.assertEqual(numbers([follow_up(1, short), lane(2, long_)]), [1, 2])
        self.assertEqual(numbers([follow_up(1, long_), lane(2, short)]), [1, 2])

    def test_trailing_punctuation_and_a_remote_prefix_still_match(self):
        body = f"See origin/{LANE_A}."
        self.assertEqual(numbers([issue(1, body=body), lane(2, LANE_A)]), [2])

    def test_a_lane_issue_is_never_deferred(self):
        self.assertEqual(numbers([lane(2, LANE_A)]), [2])
        # a lane issue whose body names the other lane does not wait either: no deadlock
        a = lane(2, LANE_A, body=f"Needs `{LANE_B}` first.")
        b = lane(3, LANE_B, body=f"Needs `{LANE_A}` first.")
        self.assertEqual(numbers([a, b]), [2, 3])

    def test_a_stop_label_on_the_lane_issue_still_defers(self):
        issues = [follow_up(35, LANE_A), lane(36, LANE_A, labels=["Blocked", "On Hold"])]
        self.assertEqual(numbers(issues), [])
        self.assertEqual(ht.deferred(issues, ["SFenton"]), {35: [36]})

    def test_a_follow_up_with_a_stop_label_is_not_listed_as_deferred(self):
        issues = [follow_up(35, LANE_A, labels=["Blocked"]), lane(36, LANE_A, labels=["On Hold"])]
        self.assertEqual(ht.deferred(issues, ["SFenton"]), {})

    def test_priority_ordering_is_unchanged(self):
        issues = [issue(1, created="2026-10-13T08:00:00Z"), issue(2, labels=["Priority"], created="2026-10-13T11:00:00Z"),
                  follow_up(3, LANE_A, labels=["Priority"]), lane(4, LANE_A)]
        self.assertEqual(numbers(issues), [2, 1, 4])

    def test_the_nightly_intake_is_unchanged(self):
        issues = [follow_up(1, LANE_A, labels=["Nightly Fix"]), lane(2, LANE_A, labels=["Nightly Fix"])]
        self.assertEqual(numbers(issues, label="Nightly Fix"), [1, 2])
        self.assertEqual(ht.deferred(issues, ["SFenton"], "Nightly Fix"), {})

    def test_the_agent_filed_lane_issue_defers_an_owner_follow_up(self):
        issues = [follow_up(35, LANE_A), lane(36, LANE_A, author="sh-agent", labels=["Workflow"])]
        self.assertEqual(numbers(issues, agent="sh-agent"), [36])


class FetchAndStatusTests(Base):
    def test_open_issues_asks_for_the_body(self):
        gh = ht.GitHub()
        with mock.patch.object(gh, "_gh", return_value="[]") as run:
            gh.open_issues("r")
        self.assertIn("body", run.call_args[0][0][-1].split(","))

    def test_status_lists_each_deferred_issue_with_what_it_waits_on(self):
        gh = FakeGitHub([follow_up(35, LANE_A, LANE_B), lane(36, LANE_A), lane(37, LANE_B, "tests")])
        report = ht.status_report(self.cfg, self.paths, gh, True)
        self.assertEqual(report["deferred"], ["deferred: #35 waits on #36, #37"])
        self.assertEqual([q["number"] for q in report["queue"]], [36, 37])

    def test_status_prints_the_deferred_line(self):
        fake = FakeGitHub([follow_up(35, LANE_A), lane(36, LANE_A)])
        with mock.patch.object(ht, "GitHub", return_value=fake), mock.patch.object(ht, "claude_logged_in", return_value=True), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            ht.main(["status"], home=self.home)
            self.assertIn("deferred: #35 waits on #36", out.getvalue())
            out.truncate(0)
            out.seek(0)
            ht.main(["status", "--json"], home=self.home)
            self.assertEqual(json.loads(out.getvalue())["deferred"], ["deferred: #35 waits on #36"])

    def test_the_runner_files_a_lane_issue_with_the_shared_title(self):
        gh = FakeGitHub([])
        runner = ht.Runner(self.cfg, self.paths, gh)
        runner.file_lane_issue(LANE_A, "tick", "refused", "review", False)
        self.assertEqual([i["title"] for i in gh.issues.values()], [ht.lane_issue_title(LANE_A, "review")])
        runner.file_lane_issue(LANE_A, "tick", "refused", "review", False)  # an open one is not filed twice
        self.assertEqual(len(gh.issues), 1)


if __name__ == "__main__":
    unittest.main()
