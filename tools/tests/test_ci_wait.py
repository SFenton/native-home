"""tools/ci_wait.py against a scripted fake ``gh``, plus the greps that keep the rule and the retired preflight honest."""

import subprocess
import sys
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import ci_wait  # noqa: E402
import pr_blockers  # noqa: E402

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

    def __call__(self, args, timeout=None):
        self.calls.append(list(args))
        self.timeouts = getattr(self, "timeouts", []) + [timeout]
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


class FakeClock:
    """A monotonic clock and matching sleep for bounded-wait tests."""

    def __init__(self):
        self.now = 0.0
        self.sleeps = []

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


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

    def test_a_cancelled_run_with_a_moved_head_follows_the_new_run_and_prints_superseded_once(self):
        """Fails if: a push that cancels the run ends the wait with exit 4, or `superseded` is missing or repeated."""
        new = "b" * 40
        cancelled = run(conclusion="cancelled", jobs=[{"name": "pr-checks", "conclusion": "cancelled"}])
        fake = FakeGh(prs=[pr(), pr(sha=new), pr(sha=new), pr("MERGED", sha=new)], runs=[[{"databaseId": 9, "headSha": SHA}], [{"databaseId": 10, "headSha": new}]],
                      views=[cancelled, cancelled, run(), run()])
        code, lines = go(fake, merge_wait=60, poll=30)
        self.assertEqual(code, 0, lines)
        self.assertEqual([x for x in lines if x.startswith("superseded")], ["superseded: aaaaaaaa -> bbbbbbbb"])
        self.assertIn("run 10", lines)
        self.assertIn("on bbbbbbbb", lines[-1])

    def test_a_cancelled_run_with_an_unchanged_head_still_exits_four_with_no_superseded_line(self):
        """Fails if: an unchanged head is treated as superseded, or exit 4 is lost."""
        cancelled = run(conclusion="cancelled", jobs=[{"name": "pr-checks", "conclusion": "cancelled"}])
        code, lines = go(FakeGh(prs=[pr(), pr()], views=[cancelled]))
        self.assertEqual(code, 4)
        self.assertFalse([x for x in lines if x.startswith("superseded")])
        self.assertIn("head is unchanged", lines[-1])

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


class OptInControlTests(unittest.TestCase):
    @staticmethod
    def live_run(conclusion, status="COMPLETED", attempt=1):
        return run(
            status="in_progress",
            conclusion=None,
            attempt=attempt,
            jobs=[{"name": "repo-checks", "status": status, "conclusion": conclusion}],
        )

    def test_a2_1_first_red_returns_on_the_first_failed_job_without_sleep(self):
        fake = FakeGh(prs=[pr(), pr()], views=[self.live_run("failure")])
        code, lines = go(fake, first_red=True)
        self.assertEqual(code, 1, lines)
        self.assertEqual(fake.sleeps, [])
        self.assertEqual(lines[-1], "RESULT: ci red early #7: repo-checks; run 9 still in_progress")
        self.assertIn("job repo-checks: failure", lines)

    def test_a2_2_first_red_accepts_timed_out_jobs(self):
        fake = FakeGh(prs=[pr(), pr()], views=[self.live_run("timed_out")])
        code, lines = go(fake, first_red=True)
        self.assertEqual(code, 1, lines)
        self.assertIn("ci red early #7: repo-checks", lines[-1])
        self.assertIn("job repo-checks: timed_out", lines)

    def test_a2_3_non_red_job_conclusions_do_not_return_early(self):
        for conclusion in ("skipped", "cancelled", "neutral", "success", None):
            with self.subTest(conclusion=conclusion):
                unfinished = "IN_PROGRESS" if conclusion is None else "COMPLETED"
                live = self.live_run(conclusion, unfinished)
                green = run(status="completed", conclusion="success", jobs=[{"name": "repo-checks", "conclusion": "success"}])
                fake = FakeGh(prs=[pr(armed=False, merge_state="CLEAN")], views=[live, green, green])
                code, lines = go(fake, first_red=True)
                self.assertEqual(code, 0, lines)
                self.assertFalse(any("ci red early" in line for line in lines))

    def test_a2_4_first_red_result_is_last_after_the_job_table(self):
        fake = FakeGh(prs=[pr(), pr()], views=[self.live_run("failure")])
        code, lines = go(fake, first_red=True)
        self.assertEqual(code, 1)
        self.assertEqual(lines[-2:], [
            "job repo-checks: failure",
            "RESULT: ci red early #7: repo-checks; run 9 still in_progress",
        ])

    def test_a2_5_head_change_invalidates_an_observed_red_job(self):
        new = "b" * 40
        fake = FakeGh(
            prs=[pr(), pr(sha=new), pr(sha=new), pr("MERGED", sha=new)],
            runs=[[{"databaseId": 9, "headSha": SHA}], [{"databaseId": 10, "headSha": new}]],
            views=[self.live_run("failure"), run(conclusion="success"), run(conclusion="success")],
        )
        code, lines = go(fake, first_red=True, merge_wait=60, poll=30)
        self.assertEqual(code, 0, lines)
        self.assertFalse(any("ci red early" in line for line in lines), lines)
        self.assertIn("superseded: aaaaaaaa -> bbbbbbbb", lines)

    def test_a2_6_new_attempt_invalidates_an_observed_red_job(self):
        views = [
            self.live_run("failure", attempt=1),
            self.live_run("success", attempt=2),
            run(conclusion="success", attempt=2, updated="t2"),
            run(conclusion="success", attempt=2, updated="t2"),
        ]
        fake = FakeGh(prs=[pr(armed=False, merge_state="CLEAN"), pr(armed=False, merge_state="CLEAN")], views=views)
        code, lines = go(fake, first_red=True)
        self.assertEqual(code, 0, lines)
        self.assertFalse(any("ci red early" in line for line in lines), lines)
        self.assertIn("attempt 2", lines[-1])

    def test_a2_7_pending_expiry_prints_the_latest_job_table_and_exit_five(self):
        for has_run in (False, True):
            with self.subTest(has_run=has_run):
                clock = FakeClock()
                fake = FakeGh(prs=[pr()], runs=[[]] if has_run is False else None,
                              views=[self.live_run(None, "IN_PROGRESS")])
                code, lines = go(fake, max_wait=7, clock=clock.monotonic, sleep=clock.sleep)
                self.assertEqual(code, 5, lines)
                if has_run:
                    self.assertIn("job repo-checks: None", lines)
                    self.assertNotIn("jobs: none observed", lines)
                else:
                    self.assertIn("jobs: none observed", lines)
                self.assertEqual(lines[-1], "RESULT: ci pending #7")
                self.assertLessEqual(sum(clock.sleeps), 7)

    def test_a2_8_one_deadline_covers_appearance_poll_settle_and_merge_wait(self):
        clock = FakeClock()
        pending_review = pr(rollup=[check("pr-checks"), check("ai-review", None, "IN_PROGRESS")])
        views = [
            run(status="in_progress", conclusion=None, attempt=1, updated="live"),
            run(status="completed", conclusion="success", attempt=1, updated="done"),
            run(status="completed", conclusion="success", attempt=1, updated="done"),
        ]
        fake = FakeGh(
            prs=[pr(), pr(), pending_review, pending_review, pending_review, pending_review],
            runs=[[], [{"databaseId": 9, "headSha": SHA}]],
            views=views,
        )
        code, lines = go(
            fake,
            max_wait=25,
            clock=clock.monotonic,
            sleep=clock.sleep,
            poll=5,
            settle=5,
            merge_wait=300,
        )
        self.assertEqual(code, 5, lines)
        self.assertEqual(lines[-1], "RESULT: ci pending #7")
        self.assertEqual(clock.now, 25)

    def test_a2_9_superseding_head_does_not_reset_the_deadline(self):
        clock = FakeClock()
        new = "b" * 40
        cancelled = run(conclusion="cancelled", jobs=[{"name": "pr-checks", "conclusion": "cancelled"}])
        fake = FakeGh(
            prs=[pr(), pr(sha=new), pr(sha=new)],
            runs=[[{"databaseId": 9, "headSha": SHA}], []],
            views=[cancelled, cancelled],
        )
        code, lines = go(fake, max_wait=15, clock=clock.monotonic, sleep=clock.sleep, poll=5, settle=5)
        self.assertEqual(code, 5, lines)
        self.assertEqual(clock.now, 15)
        self.assertIn("superseded: aaaaaaaa -> bbbbbbbb", lines)

    def test_a2_10_sleeps_and_gh_calls_are_clipped_to_the_budget(self):
        clock = FakeClock()
        fake = FakeGh(prs=[pr()], runs=[[]])
        code, lines = go(fake, max_wait=7, clock=clock.monotonic, sleep=clock.sleep, poll=30)
        self.assertEqual(code, 5, lines)
        self.assertEqual(clock.sleeps, [7])
        self.assertTrue(fake.timeouts)
        self.assertTrue(all(timeout is not None and timeout <= 7 for timeout in fake.timeouts), fake.timeouts)

    def test_a2_11_terminal_and_shorter_existing_timeouts_keep_their_codes(self):
        cases = [
            ("completed_failure", FakeGh(prs=[pr()], views=[run(conclusion="failure")]), {}, 1),
            ("service_error", FakeGh(error="HTTP 502"), {}, 2),
            ("appear_timeout", FakeGh(prs=[pr()], runs=[[]]), {"appear_timeout": 2, "poll": 1}, 2),
            ("closed", FakeGh(prs=[pr("CLOSED")]), {}, 1),
            ("conflict", FakeGh(prs=[{**pr(), "mergeable": "CONFLICTING"}]), {}, 3),
            ("cancelled", FakeGh(prs=[pr(), pr()], views=[run(conclusion="cancelled"), run(conclusion="cancelled")]), {}, 4),
        ]
        for name, fake, options, expected in cases:
            with self.subTest(name=name):
                clock = FakeClock()
                code, lines = go(
                    fake,
                    max_wait=100,
                    clock=clock.monotonic,
                    sleep=clock.sleep,
                    **options,
                )
                self.assertEqual(code, expected, lines)

    def test_a2_12_no_flags_preserve_legacy_stdout_and_exit_codes_byte_for_byte(self):
        scenarios = {}
        views = [
            run(conclusion="failure", attempt=1, updated="t1"),
            run(status="in_progress", conclusion=None, attempt=2, updated="t2"),
            run(status="in_progress", conclusion=None, attempt=2, updated="t2"),
            run(conclusion="success", attempt=2, updated="t3"),
            run(conclusion="success", attempt=2, updated="t3"),
        ]
        scenarios["settled_rerun"] = go(FakeGh(prs=[pr(armed=False, merge_state="CLEAN")], views=views))

        cancelled = run(conclusion="cancelled", jobs=[{"name": "pr-checks", "conclusion": "cancelled"}])
        scenarios["cancelled"] = go(FakeGh(prs=[pr(), pr()], views=[cancelled]))

        new = "b" * 40
        scenarios["superseded"] = go(
            FakeGh(
                prs=[pr(), pr(sha=new), pr(sha=new), pr("MERGED", sha=new)],
                runs=[[{"databaseId": 9, "headSha": SHA}], [{"databaseId": 10, "headSha": new}]],
                views=[cancelled, cancelled, run(), run()],
            ),
            merge_wait=60,
            poll=30,
        )

        rendered = {name: (code, "\n".join(lines) + "\n") for name, (code, lines) in scenarios.items()}
        self.assertEqual(rendered["settled_rerun"], (0,
            "PR 7 head aaaaaaaa branch agents/x\n"
            "run 9\n"
            "job pr-checks: success\n"
            "RESULT: pr-checks success on aaaaaaaa (run 9, attempt 2); CI green and CLEAN, not armed\n"))
        self.assertEqual(rendered["cancelled"], (4,
            "PR 7 head aaaaaaaa branch agents/x\n"
            "run 9\n"
            "job pr-checks: cancelled\n"
            "RESULT: cancelled #7: pr-checks cancelled on aaaaaaaa (run 9, attempt 1); "
            "the head is unchanged, re-run the workflow or push\n"))
        self.assertEqual(rendered["superseded"], (0,
            "PR 7 head aaaaaaaa branch agents/x\n"
            "run 9\n"
            "job pr-checks: cancelled\n"
            "superseded: aaaaaaaa -> bbbbbbbb\n"
            "run 10\n"
            "job pr-checks: success\n"
            "RESULT: pr-checks success on bbbbbbbb (run 10, attempt 1); merged\n"))

    def test_a2_13_nonpositive_or_nonfinite_max_wait_is_rejected_by_option_parsing(self):
        for value in ("0", "-1", "nan", "inf", "-inf"):
            with self.subTest(value=value):
                stderr = StringIO()
                with redirect_stderr(stderr), self.assertRaises(SystemExit):
                    ci_wait.main(["7", f"--max-wait={value}"])
                self.assertIn("positive finite", stderr.getvalue())

    def test_a2_14_rule_sentence_names_first_red_and_preserves_background_bounded_waiting(self):
        line = next(line for line in (ROOT / ".agents" / "workflow" / "ci.md").read_text().splitlines()
                    if "Start `tools/ci_wait.py N`" in line)
        self.assertIn("through `tools/bg_run.py` in the background and end the turn", line)
        self.assertIn("add `--first-red` to stop at the first failed job", line)


class BlockerTests(unittest.TestCase):
    """``pr_blockers.blockers`` and where ``wait`` uses it; CODEOWNERS is passed in so the tests do not follow the live file."""

    OWNED = pr_blockers.parse("/tools/pr_land.py @SFenton\n")

    def test_a_conflicting_pr_exits_three_on_the_first_poll(self):
        """Fails if: a CONFLICTING PR is polled for a run that GitHub never queues (more than the one `pr view`), or does not exit 3 naming the conflict."""
        fake = FakeGh(prs=[{**pr(), "mergeable": "CONFLICTING"}], runs=[[]])
        code, lines = go(fake)
        self.assertEqual(code, 3)
        self.assertIn("conflicts with main", lines[-1])
        self.assertIn("merge main and push", lines[-1])
        self.assertEqual([c[:2] for c in fake.calls], [["pr", "view"]])
        self.assertEqual(fake.sleeps, [])

    def test_an_unknown_mergeable_does_not_exit_three_and_keeps_waiting(self):
        """Fails if: mergeable UNKNOWN (GitHub still computing it) is treated as a conflict, so a fresh PR exits 3 instead of waiting for its run."""
        fake = FakeGh(prs=[{**pr(), "mergeable": "UNKNOWN"}, {**pr(), "mergeable": "UNKNOWN"}, pr("MERGED")], runs=[[], [{"databaseId": 9, "headSha": SHA}]],
                      views=[run()])
        code, lines = go(fake, merge_wait=60, poll=30)
        self.assertEqual(code, 0, lines)
        self.assertGreaterEqual(len(fake.sleeps), 1)
        self.assertEqual(pr_blockers.blockers({"mergeable": "UNKNOWN"}), [])

    def test_draft_and_review_required_are_named(self):
        """Fails if: a draft or a missing code-owner review is not named, or a PR with neither gets a blocker."""
        state = {"isDraft": True, "reviewDecision": "REVIEW_REQUIRED", "mergeable": "MERGEABLE", "files": [{"path": "tools/pr_land.py"}]}
        found = pr_blockers.blockers(state, self.OWNED)
        self.assertEqual(len(found), 2, found)
        self.assertIn("draft", found[0])
        self.assertIn("code-owner review required (REVIEW_REQUIRED) for tools/pr_land.py", found[1])
        self.assertEqual(pr_blockers.blockers({**state, "isDraft": False, "reviewDecision": "APPROVED"}, self.OWNED), [])
        self.assertEqual(pr_blockers.blockers({**state, "files": [{"path": "apple/X.swift"}]}, self.OWNED)[1:], [])

    def test_a_blocked_pr_names_its_reason_at_the_end(self):
        """Fails if: a green run on a PR left BLOCKED by a draft or a missing code-owner review ends with only `armed but BLOCKED`."""
        blocked = {**pr(armed=False), "isDraft": True, "reviewDecision": "REVIEW_REQUIRED", "files": [{"path": ".github/workflows/x.yml"}]}
        fake = FakeGh(prs=[blocked], views=[run()])
        code, lines = go(fake, merge_wait=0)
        self.assertEqual(code, 3)
        self.assertIn("BLOCKED", lines[-1])
        self.assertIn("also draft", lines[-1])
        self.assertIn("code-owner review required (REVIEW_REQUIRED)", lines[-1])

    def test_the_live_codeowners_file_matches_what_the_gate_owns(self):
        """Fails if: the matcher stops reading .github/CODEOWNERS, or stops matching a directory and a glob pattern in it."""
        patterns = pr_blockers.load_rules()
        self.assertIn("/tools/pr_land.py", [pattern for pattern, _ in patterns])
        for path in ("tools/pr_land.py", "tools/lane_land.py", ".github/workflows/pr-checks.yml", ".agents/workflow/ci.md"):
            self.assertEqual(pr_blockers.owned_files({"files": [{"path": path}]}, patterns), [path], path)
        self.assertEqual(pr_blockers.owned_files({"files": [{"path": "apple/HassCore/EntityStore.swift"}, {"path": "tools/ci_wait.py"}]}, patterns), [])


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
