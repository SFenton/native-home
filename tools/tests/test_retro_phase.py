"""``tools/retro_phase.py``: fires, does not fire, and missing data. ``gh`` is stubbed; nothing touches the network."""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("retro_phase", TOOLS / "retro_phase.py")
rp = importlib.util.module_from_spec(spec)
sys.modules["retro_phase"] = rp
spec.loader.exec_module(rp)



def commit(headline, when, parents=1):
    return {"commit": {"message": headline, "committer": {"date": when}}, "parents": [{"sha": "p"}] * parents}


def job_detail(start="2026-11-05T11:05:00Z"):
    return {"jobs": [{"startedAt": start}, {"startedAt": "2026-11-05T11:30:00Z"}]}


def stub(commits, runs, issues=None, detail=None, body=""):
    pr_view = {"headRefName": "b", "body": body, "comments": [], "createdAt": "2026-11-05T09:00:00Z",
               "mergedAt": "2026-11-05T13:00:00Z"}

    def fake(args):
        if args[0] == "pr":
            return pr_view
        if args[0] == "api":
            return commits
        if args[:2] == ["run", "list"]:
            return runs
        if args[:2] == ["run", "view"]:
            return job_detail() if detail is None else detail
        return issues
    return fake


def run(conclusion="failure", created="2026-11-05T11:00:00Z", i=1):
    return {"databaseId": i, "conclusion": conclusion, "createdAt": created}


# Real shapes from PR 289: one parent for ordinary commits, two for base merges, whatever the headline says.
PR289 = [commit("Profile badge follows the text size", "2026-11-04T16:46:06Z"),
         commit("Merge remote-tracking branch 'origin/claude/uikit-port'", "2026-11-04T21:42:22Z", 2),
         commit("Merge branch 'claude/uikit-port' of https://github.com/x/y into b", "2026-11-04T23:21:42Z", 2),
         commit("Merge commit '392f0366b1447a2a25d8d0947f' into HEAD", "2026-11-05T14:45:52Z", 2)]


class RetroPhaseTests(unittest.TestCase):
    def run_main(self, fake, extra=()):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(rp, "gh_json", fake):
            out = Path(d) / "retro"
            argv = ["--pr", "7", "--out", str(out), *extra]
            with mock.patch("builtins.print") as pr:
                code = rp.main(argv)
            data = json.loads((out / "phase-7.json").read_text())
            printed = [c.args[0] for c in pr.call_args_list]
        return code, data, printed

    def test_counts_merges_by_parents_not_headline(self):
        _, data, printed = self.run_main(stub(PR289, []))
        self.assertEqual(data["base_merges_after_review"], 3)
        self.assertIn("phase_cost", printed)

    def test_headline_without_second_parent_is_not_a_merge(self):
        _, data, _ = self.run_main(stub([commit("Merge branch 'x' into b", "2026-11-05T11:00:00Z")], []))
        self.assertEqual(data["base_merges_after_review"], 0)

    def test_fires_on_red_runs_and_queue_from_jobs(self):
        _, data, printed = self.run_main(stub([], [run(i=i) for i in range(3)]))
        self.assertEqual(data["ci_red_runs"], 3)
        self.assertEqual(data["ci_queue_minutes"], 15.0)
        self.assertIsNone(data["review_restamps"])
        self.assertIn("phase_cost", printed)

    def test_queue_not_derivable_without_jobs(self):
        _, data, _ = self.run_main(stub([], [run()], detail={"jobs": []}))
        self.assertIsNone(data["ci_queue_minutes"])
        self.assertTrue(any("ci_queue_minutes not derivable" in n for n in data["notes"]))

    def test_fires_on_owner_wait(self):
        issue = [{"number": 9, "labels": [{"name": "Workflow"}, {"name": "On Hold"}],
                  "createdAt": "2026-11-05T09:30:00Z", "closedAt": None}]
        _, data, printed = self.run_main(stub([], [], issue, body="waits on #9"))
        self.assertEqual(data["owner_only_wait_minutes"], 210.0)
        self.assertIn("phase_cost", printed)
        self.assertTrue(any("product-repo issues only" in n for n in data["notes"]))

    def test_does_not_fire(self):
        runs = [{"conclusion": "failure", "createdAt": "2026-11-05T11:00:00Z", "startedAt": "2026-11-05T11:01:00Z"},
                {"conclusion": "success", "createdAt": "2026-11-05T11:00:00Z", "startedAt": "2026-11-05T11:01:00Z"}]
        code, data, printed = self.run_main(stub([commit("Merge branch x", "2026-11-05T11:00:00Z", 2)], runs))
        self.assertEqual(code, 0)
        self.assertFalse(data["phase_cost"])
        self.assertNotIn("phase_cost", printed)

    def test_since_filters_old_runs(self):
        runs = [{"conclusion": "failure", "createdAt": "2026-11-05T08:00:00Z", "startedAt": "2026-11-05T08:00:00Z"}] * 3
        _, data, _ = self.run_main(stub([], runs), ["--since", "2026-11-05T09:00:00Z"])
        self.assertEqual(data["ci_red_runs"], 0)

    def test_missing_data_does_not_crash(self):
        code, data, _ = self.run_main(lambda args: None)
        self.assertEqual(code, 0)
        self.assertFalse(data["phase_cost"])
        self.assertIn("gh pr view unavailable", data["notes"])

    def test_garbage_data_does_not_crash(self):
        code, _, _ = self.run_main(lambda args: {"comments": [None], "body": 5})
        self.assertEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
