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


def node(sha, parents, when, headline="plain commit"):
    return {"sha": sha, "commit": {"message": headline, "committer": {"date": when}},
            "parents": [{"sha": p} for p in parents]}


# Shaped like PR 68: 8 merge commits, 4 inherited through a folded branch (second parents), 2 folds, 2 of main.
PR68 = [node("base", ["root"], "2026-11-10T20:00:00Z"),
        node("s1", ["base"], "2026-11-10T21:00:00Z", "Merge branch 'main' into side"),
        node("s2", ["s1", "q"], "2026-11-10T21:10:00Z", "Merge branch 'main' into side"),
        node("s3", ["s2", "q"], "2026-11-10T21:20:00Z", "Merge branch 'main' into side"),
        node("s4", ["s3", "q"], "2026-11-10T21:30:00Z", "Merge branch 'main' into side"),
        node("s5", ["s4", "q"], "2026-11-10T21:40:00Z", "Merge branch 'main' into side"),
        node("a", ["base"], "2026-11-11T02:00:00Z"),
        node("m1", ["a", "main1"], "2026-11-11T03:00:00Z", "Merge origin/main into claude/hosted-home"),
        node("m2", ["m1", "main2"], "2026-11-11T06:00:00Z", "Merge remote-tracking branch 'origin/main'"),
        node("f1", ["m2", "s5"], "2026-11-11T07:05:00Z", "Merge branch 'agents/hosted-step' into b"),
        node("f2", ["f1", "s5"], "2026-11-11T09:28:00Z", "Merge commit 'abc123' into b")]
def check_run(conclusion, completed, round_=1):
    """One entry of ``gh api commits/<sha>/check-runs?check_name=ai-review`` (fields as GitHub returns them)."""
    return {"id": 1, "name": "ai-review", "status": "completed", "conclusion": conclusion,
            "started_at": completed, "completed_at": completed,
            "output": {"title": "ai-review: %s (round %d)" % ("pass" if conclusion == "success" else "changes", round_)}}


# check runs per commit: a failed round, then passes (the earliest success, a round 1 pass on a at 02:30, is the first pass)
CHECKS = {"base": [check_run("failure", "2026-11-10T20:30:00Z")],
          "a": [check_run("success", "2026-11-11T02:30:00Z")],
          "m2": [check_run("success", "2026-11-11T06:10:00Z", 2)],
          "f1": [check_run("success", "2026-11-11T07:44:48Z", 2)]}
REVIEW_COMMENT = {"createdAt": "2026-11-11T07:41:00Z", "body": "Reviewer: pass on b8b8d3f\n\n<!-- sh:review:T-x:r1 -->"}
# Owner notes: a plain ping, the recipe for a superseded head, then the recipe for the head the PR merged with.
PING = {"createdAt": "2026-11-11T07:00:00Z", "body": "Heads up.\n\n<!-- sh:owner:T-x:s0 -->"}
OLD_RECIPE = {"createdAt": "2026-11-11T07:47:00Z", "body": "Then run `gh pr " + "merge 7 --match-head-commit f1`\n\n"
              "<!-- sh-meta:step=1 round=2 ident=round head=f1 -->\n<!-- sh:owner:T-x:s1 -->"}
OWNER_COMMENT = {"createdAt": "2026-11-11T10:22:00Z", "body": "Then run `gh pr " + "merge 7 --match-head-commit f2`\n\n"
                 "<!-- sh-meta:step=2 round=3 ident=round head=f2 -->\n<!-- sh:owner:T-x:s2 -->"}


def stub68(comments, commits=PR68, head="f2", checks=CHECKS):
    def fake(args):
        if args[0] == "pr":
            return {"headRefName": "b", "headRefOid": head, "body": "", "comments": comments,
                    "createdAt": "2026-11-10T20:00:00Z", "mergedAt": "2026-11-11T16:02:00Z"}
        if args[0] == "api" and "check-runs" in args[1]:
            sha = args[1].split("/commits/")[1].split("/")[0]
            return {"total_count": len(checks.get(sha, [])), "check_runs": checks.get(sha, [])}
        if args[0] == "api":
            return commits
        if args[:2] == ["run", "list"]:
            return []
        return None
    return fake


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

    def test_pr68_counts_first_parent_merges_by_kind(self):
        _, data, _ = self.run_main(stub68([]), ["--since", "2026-11-01T00:00:00Z"])
        self.assertEqual((data["base_merges_main"], data["base_merges_fold"]), (2, 2))
        self.assertEqual(data["base_merges_after_review"], 4)
        self.assertEqual(data["base_merges_inherited_skipped"], 4)

    def test_pr68_counts_every_merge_after_the_earliest_successful_check_run(self):
        _, data, _ = self.run_main(stub68([PING, OLD_RECIPE, OWNER_COMMENT]))
        self.assertEqual(data["review_pass_at"], "2026-11-11T02:30:00+00:00")
        self.assertEqual(data["base_merges_after_review"], 4)
        self.assertEqual((data["base_merges_main"], data["base_merges_fold"]), (2, 2))
        self.assertTrue(any("ai-review check run" in n for n in data["notes"]))

    def test_failed_check_runs_do_not_count_as_a_pass(self):
        with mock.patch.object(rp, "gh_json", stub68([], checks={"base": CHECKS["base"]})):
            self.assertIsNone(rp.check_pass_time([{"sha": "base"}, {"sha": "zz"}, {"nosha": 1}]))

    def test_comment_is_the_fallback_when_no_check_run_is_found(self):
        _, data, _ = self.run_main(stub68([REVIEW_COMMENT], checks={}))
        self.assertTrue(data["review_pass_at"].startswith("2026-11-11T07:41"))
        self.assertEqual(data["base_merges_after_review"], 1)
        self.assertTrue(any("sh:review comment" in n for n in data["notes"]))

    def test_since_overrides_the_check_run(self):
        _, data, _ = self.run_main(stub68([]), ["--since", "2026-11-11T09:00:00Z"])
        self.assertEqual(data["base_merges_after_review"], 1)

    def test_pr68_owner_wait_starts_at_the_recipe_for_the_final_head(self):
        _, data, printed = self.run_main(stub68([PING, OLD_RECIPE, OWNER_COMMENT]))
        self.assertEqual(data["owner_wait_minutes"], 340.0)
        self.assertEqual(data["owner_only_wait_minutes"], 0.0)
        self.assertIn("phase_cost", printed)

    def test_owner_wait_is_zero_for_a_plain_ping(self):
        _, data, printed = self.run_main(stub68([PING], commits=[]))
        self.assertEqual(data["owner_wait_minutes"], 0.0)
        self.assertNotIn("phase_cost", printed)

    def test_a_blocker_note_starts_the_owner_wait(self):
        note = {"createdAt": "2026-11-11T12:02:00Z", "body": "Blocked on the code owner.\n<!-- sh:owner:T-x:s1 -->"}
        _, data, _ = self.run_main(stub68([note], commits=[]))
        self.assertEqual(data["owner_wait_minutes"], 240.0)

    def test_without_a_pass_or_since_every_first_parent_merge_counts(self):
        _, data, _ = self.run_main(stub68([], checks={}))
        self.assertEqual(data["base_merges_after_review"], 4)
        self.assertTrue(any("first review pass not findable" in n for n in data["notes"]))

    def test_a_pass_comment_needs_the_review_marker(self):
        self.assertIsNone(rp.review_pass_time([{"createdAt": "2026-11-11T07:41:00Z", "body": "pass"}]))

    def test_merged_ref_reads_every_headline_form(self):
        forms = {"Merge branch 'main' of https://github.com/x/y into b": "main",
                 "Merge branch 'main' into b": "main",
                 "Merge branch main": "main",
                 "Merge remote-tracking branch 'origin/main'": "origin/main",
                 "Merge remote-tracking branch 'origin/main' into claude/x": "origin/main",
                 "Merge origin/main into claude/hosted-home": "origin/main",
                 "Merge remote-tracking branch 'origin/claude/hosted-green' into b": "origin/claude/hosted-green",
                 "Merge commit 'abc123' into HEAD": "commit",
                 "Merge commit abc123": "commit",
                 "Merge pull request #5 from x/y": "pull",
                 "Merge origin/main into b\n\nbody 'quoted'": "origin/main",
                 "Fix it": "", "": ""}
        for headline, ref in forms.items():
            self.assertEqual(rp.merged_ref(headline), ref, headline)

    def test_main_and_fold_split_by_headline_form(self):
        for headline, kind in [("Merge origin/main into b", "main"), ("Merge branch 'main' of u into b", "main"),
                               ("Merge remote-tracking branch 'origin/main' into b", "main"),
                               ("Merge origin/claude/x into b", "fold"), ("Merge commit 'abc' into b", "fold")]:
            found = rp.base_merges([commit(headline, "2026-11-05T11:00:00Z", 2)], "", None)
            self.assertEqual((found["main"], found["fold"]), (1, 0) if kind == "main" else (0, 1), headline)

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
