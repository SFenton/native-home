"""tools/ci_wait.py against a scripted fake ``gh``, plus the greps that keep the rule and the retired preflight honest."""

import subprocess
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import ci_wait  # noqa: E402

SHA = "a" * 40


class FakeGh:
    """Answers ``pr view``, ``run list`` and ``run view`` from queues (the last item repeats); records every call."""

    def __init__(self, prs=None, runs=None, views=None, error=None):
        self.prs = list(prs or [])
        self.runs = list(runs if runs is not None else [[{"databaseId": 9, "headSha": SHA}]])
        self.views = list(views or [])
        self.error = error
        self.calls = []
        self.sleeps = []

    @staticmethod
    def pop(queue):
        return queue.pop(0) if len(queue) > 1 else queue[0]

    def __call__(self, args):
        self.calls.append(list(args))
        if self.error:
            raise ci_wait.GhError(self.error)
        if args[:2] == ["pr", "view"]:
            return self.pop(self.prs)
        if args[:2] == ["run", "list"]:
            return self.pop(self.runs)
        return self.pop(self.views)


def check(name, conclusion="SUCCESS", status="COMPLETED"):
    return {"__typename": "CheckRun", "name": name, "status": status, "conclusion": conclusion}


def pr(state="OPEN", sha=SHA, armed=True, merge_state="BLOCKED", rollup=None):
    """A `gh pr view` answer; the rollup defaults to both required checks green."""
    rollup = [check("pr-checks"), check("ai-review")] if rollup is None else rollup
    return {"state": state, "headRefOid": sha, "headRefName": "agents/x", "autoMergeRequest": {"enabled": True} if armed else None,
            "mergeStateStatus": merge_state, "statusCheckRollup": rollup}


def run(status="completed", conclusion="success", attempt=1, updated="t1", jobs=None):
    return {"status": status, "conclusion": conclusion, "attempt": attempt, "updatedAt": updated,
            "jobs": jobs if jobs is not None else [{"name": "pr-checks", "conclusion": conclusion}]}


def go(fake, **kw):
    kw.setdefault("sleep", fake.sleeps.append)
    return ci_wait.wait("7", gh=fake, **kw)


class WaitTests(unittest.TestCase):
    def test_green_run_of_an_armed_pr_that_merged_prints_merged_and_exits_zero(self):
        """Fails if: a green run and a merged PR is not reported as `merged`, or exits non-zero."""
        fake = FakeGh(prs=[pr(), pr(), pr("MERGED")], views=[run()])
        code, lines = go(fake, merge_wait=60, poll=30)
        self.assertEqual(code, 0)
        self.assertIn("job pr-checks: success", lines)
        self.assertTrue(lines[-1].startswith("RESULT: pr-checks success on aaaaaaaa"), lines)
        self.assertTrue(lines[-1].endswith("; merged"), lines)

    def test_an_armed_pr_still_blocked_after_the_wait_exits_three_never_zero(self):
        """Fails if: an armed PR that GitHub still holds BLOCKED (both checks green) exits 0."""
        code, lines = go(FakeGh(prs=[pr(merge_state="BLOCKED")], views=[run()]), merge_wait=60, poll=30)
        self.assertEqual(code, 3)
        self.assertIn("blocked: armed but BLOCKED", lines[-1])

    def test_an_armed_pr_that_merges_a_little_later_exits_zero(self):
        """Fails if: the waiter judges the PR on its first read, before GitHub has merged an armed PR whose checks just finished."""
        code, lines = go(FakeGh(prs=[pr(), pr(), pr("MERGED")], views=[run()]), merge_wait=60, poll=30)
        self.assertEqual((code, lines[-1].endswith("; merged")), (0, True))

    def test_green_and_clean_but_not_armed_exits_zero(self):
        """Fails if: a green CLEAN PR nobody armed is reported as blocked or waited on forever."""
        code, lines = go(FakeGh(prs=[pr(armed=False, merge_state="CLEAN")], views=[run()]))
        self.assertEqual(code, 0)
        self.assertTrue(lines[-1].endswith("; CI green and CLEAN, not armed"), lines)

    def test_not_armed_and_not_clean_exits_three(self):
        """Fails if: an unarmed PR with a BLOCKED merge state exits 0."""
        code, lines = go(FakeGh(prs=[pr(armed=False, merge_state="BLOCKED")], views=[run()]), merge_wait=30, poll=30)
        self.assertEqual(code, 3)
        self.assertIn("not armed but BLOCKED", lines[-1])

    def test_ai_review_missing_on_an_armed_blocked_pr_exits_three_with_the_post_check_command(self):
        """Fails if: a PR blocked only because ai-review was never posted exits 0, or the line omits the record.py --post-check command."""
        fake = FakeGh(prs=[pr(rollup=[check("pr-checks")])], views=[run()])
        code, lines = go(fake, merge_wait=60, poll=30)
        self.assertEqual(code, 3)
        self.assertIn("blocked: ai-review missing on aaaaaaaa", lines[-1])
        self.assertIn(f"record.py --post-check {SHA} --repo SFenton/native-home", lines[-1])

    def test_ai_review_failure_exits_three_at_once(self):
        """Fails if: a failing ai-review is waited out or reported as success."""
        fake = FakeGh(prs=[pr(rollup=[check("pr-checks"), check("ai-review", "FAILURE")])], views=[run()])
        code, lines = go(fake)
        self.assertEqual(code, 3)
        self.assertIn("ai-review failure on aaaaaaaa", lines[-1])
        self.assertEqual(fake.sleeps, [20])

    def test_ai_review_pending_is_waited_for_then_blocked(self):
        """Fails if: an ai-review check still running is read as missing or as success."""
        pending = pr(rollup=[check("pr-checks"), check("ai-review", None, "IN_PROGRESS")])
        code, lines = go(FakeGh(prs=[pending], views=[run()]), merge_wait=30, poll=30)
        self.assertEqual(code, 3)
        self.assertIn("ai-review still pending", lines[-1])

    def test_a_status_context_ai_review_is_read_too(self):
        """Fails if: only CheckRun entries are understood, so a commit-status ai-review reads as missing."""
        state = pr(rollup=[{"__typename": "StatusContext", "context": "ai-review", "state": "SUCCESS"}], armed=False, merge_state="CLEAN")
        code, _ = go(FakeGh(prs=[state], views=[run()]))
        self.assertEqual(code, 0)

    def test_a_head_that_moved_after_the_green_run_exits_three(self):
        """Fails if: a green run for an old head is reported as success after someone pushed a new head."""
        code, lines = go(FakeGh(prs=[pr(), pr(sha="c" * 40)], views=[run()]))
        self.assertEqual(code, 3)
        self.assertIn("head moved", lines[-1])

    def test_a_cancelled_run_exits_four_not_a_ci_failure(self):
        """Fails if: a cancelled run is reported as `ci failed` or shares the failure exit code."""
        jobs = [{"name": "pr-checks", "conclusion": "cancelled"}]
        code, lines = go(FakeGh(prs=[pr()], views=[run(conclusion="cancelled", jobs=jobs)]))
        self.assertEqual(code, 4)
        self.assertIn("cancelled #7", lines[-1])
        self.assertNotIn("ci failed", lines[-1])

    def test_a_failed_job_names_the_failing_checks_and_exits_one(self):
        """Fails if: a red run exits 0, or the line does not name the failing job."""
        jobs = [{"name": "repo-checks", "conclusion": "failure"}, {"name": "tests", "conclusion": "success"}]
        code, lines = go(FakeGh(prs=[pr()], views=[run(conclusion="failure", jobs=jobs)]))
        self.assertEqual(code, 1)
        self.assertTrue(lines[-1].startswith("RESULT: ci failed #7: repo-checks;"), lines)

    def test_a_pr_merged_before_a_run_is_found_is_merged(self):
        """Fails if: an already merged PR waits for a run that may never appear."""
        code, lines = go(FakeGh(prs=[pr("MERGED")]))
        self.assertEqual((code, lines[-1]), (0, "RESULT: merged #7"))

    def test_a_closed_pr_exits_one(self):
        """Fails if: a PR closed without merging is waited on or reported as success."""
        code, lines = go(FakeGh(prs=[pr("CLOSED")]))
        self.assertEqual(code, 1)
        self.assertIn("closed #7", lines[-1])

    def test_no_run_for_the_head_exits_two_after_the_appear_timeout(self):
        """Fails if: a run for an older head satisfies the wait, or the wait never gives up."""
        fake = FakeGh(prs=[pr()], runs=[[{"databaseId": 3, "headSha": "b" * 40}]])
        code, lines = go(fake, appear_timeout=90, poll=30)
        self.assertEqual(code, 2)
        self.assertIn("no pr-checks run appeared for aaaaaaaa", lines[-1])
        self.assertEqual(len(fake.sleeps), 3)

    def test_a_run_that_appears_late_is_picked_up(self):
        """Fails if: the first empty `run list` ends the wait."""
        fake = FakeGh(prs=[pr(), pr("MERGED")], runs=[[], [{"databaseId": 9, "headSha": SHA}]], views=[run()])
        code, _ = go(fake)
        self.assertEqual(code, 0)

    def test_a_moved_head_while_waiting_exits_two(self):
        """Fails if: the waiter keeps waiting for a run of a head that is no longer the PR's."""
        fake = FakeGh(prs=[pr(), pr(sha="c" * 40)], runs=[[]])
        code, lines = go(fake)
        self.assertEqual(code, 3)
        self.assertIn("head moved", lines[-1])

    def test_a_rerun_after_a_completed_read_is_waited_for(self):
        """Fails if: a completed read that a rerun then resets (attempt 1 -> 2) is reported instead of the rerun's result."""
        views = [run(conclusion="failure", attempt=1, updated="t1"),
                 run(status="in_progress", conclusion=None, attempt=2, updated="t2"),
                 run(status="in_progress", conclusion=None, attempt=2, updated="t2"),
                 run(conclusion="success", attempt=2, updated="t3"), run(conclusion="success", attempt=2, updated="t3")]
        code, lines = go(FakeGh(prs=[pr(armed=False, merge_state="CLEAN")], views=views))
        self.assertEqual(code, 0, lines)
        self.assertIn("attempt 2", lines[-1])

    def test_a_changed_updated_at_with_the_same_attempt_is_not_settled(self):
        """Fails if: only the attempt is compared, so a rerun not yet bumping it is read as complete."""
        views = [run(updated="t1"), run(updated="t2"), run(updated="t2")]
        fake = FakeGh(prs=[pr(armed=False, merge_state="CLEAN")], views=views)
        go(fake)
        self.assertEqual(sum(1 for c in fake.calls if c[:2] == ["run", "view"]), 4)

    def test_a_gh_error_prints_failed_and_exits_two(self):
        """Fails if: a gh failure raises a traceback or exits 0."""
        code, lines = go(FakeGh(error="HTTP 502"))
        self.assertEqual((code, lines), (2, ["RESULT: failed #7: HTTP 502"]))

    def test_the_run_is_looked_up_by_workflow_branch_and_the_pr_head(self):
        """Fails if: the waiter reads a run of another workflow or branch instead of pr-checks for this PR."""
        fake = FakeGh(prs=[pr(armed=False)], views=[run()])
        go(fake)
        listing = next(c for c in fake.calls if c[:2] == ["run", "list"])
        self.assertIn("pr-checks", listing)
        self.assertIn("agents/x", listing)
        self.assertIn("SFenton/native-home", listing)

    def test_the_command_line_documents_its_options(self):
        """Fails if: the script does not start as a command or loses its --appear-timeout option."""
        proc = subprocess.run([sys.executable, str(TOOLS / "ci_wait.py"), "--help"], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0)
        self.assertIn("--appear-timeout", proc.stdout)


class RuleGrepTests(unittest.TestCase):
    def test_the_orchestrator_names_the_waiter(self):
        """Fails if: .claude/agents/orchestrator.md loses the CI waits rule (owner, 2026-11-09: "Why didn't you watch and react?")."""
        text = (ROOT / ".claude" / "agents" / "orchestrator.md").read_text()
        self.assertIn("tools/ci_wait.py", text)
        self.assertIn("bg_run", text)

    def test_no_file_names_the_retired_preflight(self):
        """Fails if: tools, .claude, .agents or AGENTS.md mention the deleted preflight script again."""
        needle = "land" + "_preflight"
        hits = []
        for base in ("tools", ".claude", ".agents"):
            for path in (ROOT / base).rglob("*"):
                if path.is_file() and path.suffix in {".py", ".md", ".sh", ".json", ".yml", ".yaml", ".txt"} and "__pycache__" not in path.parts:
                    if needle in path.read_text(errors="ignore"):
                        hits.append(str(path.relative_to(ROOT)))
        if needle in (ROOT / "AGENTS.md").read_text():
            hits.append("AGENTS.md")
        self.assertEqual(hits, [])


if __name__ == "__main__":
    unittest.main()
