"""``tools/retro_digest.py``: each trigger from a small fixture, and missing inputs. No network, no LLM."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import timedelta
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("retro_digest", TOOLS / "retro_digest.py")
rd = importlib.util.module_from_spec(spec)
sys.modules["retro_digest"] = rd
spec.loader.exec_module(rd)
import retro_weekly as rw  # noqa: E402


def assistant(text):
    return json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}})


def result(**kw):
    base = {"type": "result", "total_cost_usd": 1.5, "num_turns": 42, "duration_ms": 600000,
            "usage": {"input_tokens": 100, "output_tokens": 200, "cache_creation_input_tokens": 300,
                      "cache_read_input_tokens": 9_000_000},
            "modelUsage": {"claude-opus": {"costUSD": 1.5}}}
    base.update(kw)
    return json.dumps(base)


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="retro-digest-test-"))
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.build = self.dir / "build"

    def write(self, rel, content):
        path = self.dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content if isinstance(content, str) else json.dumps(content))
        return path

    def run_digest(self, *extra, task="R-1", worktree=True):
        argv = ["--task", task] + (["--worktree", str(self.dir)] if worktree else []) + list(extra)
        self.assertEqual(rd.main(argv), 0)
        return json.loads((self.build / "retro" / f"{task}.json").read_text()) if worktree else None

    def fired(self, doc):
        return {t["id"]: t["evidence"] for t in doc["triggers"]}


class TriggerTests(Base):
    def test_no_inputs_never_crashes(self):
        doc = self.run_digest()
        self.assertEqual(doc["triggers"], [])
        self.assertEqual(doc["counts"]["turns"], 0)
        self.assertEqual(doc["counts"]["waits"], 0)
        self.assertEqual(doc["aar"]["why_different"], "")

    def test_a_task_digest_ignores_another_tasks_empty_run(self):
        """Fails if: an EMPTY run stamped for another task fires empty_runs for this one, or stops firing for its own task."""
        self.write("build/runs/journeys.digest", "RESULT: EMPTY (exit 0)  journeys  13s  task=sdui-review\ntests: executed 0, skipped 3, failed 0\n")
        self.write("build/runs/unit.digest", "RESULT: PASS (exit 0)  unit  45s  task=parity-loop\ntests: executed 40, skipped 0, failed 0\n")
        other = self.run_digest(task="parity-loop")
        self.assertNotIn("empty_runs", self.fired(other))
        self.assertEqual(other["counts"]["skipped_runs"], 1)
        own = self.run_digest(task="sdui-review")
        self.assertIn("empty_runs", self.fired(own))
        self.assertEqual(own["counts"]["skipped_runs"], 1)

    def test_an_unstamped_digest_is_skipped_and_counted_in_task_mode(self):
        """Fails if: a digest with no task stamp fires a trigger for a ledger task, or is not counted as skipped."""
        self.write("build/runs/journeys.digest", "RESULT: EMPTY (exit 0)  journeys  13s  sha=abc lane=wt\ntests: executed 0, skipped 3, failed 0\n")
        doc = self.run_digest()
        self.assertEqual(doc["triggers"], [])
        self.assertEqual(doc["counts"]["skipped_runs"], 1)

    def test_a_review_of_a_branch_outside_the_ledger_is_skipped(self):
        """Fails if: a round-5 review of a branch the ledger does not list fires review_rounds_over_cap."""
        self.write("build/tasks/R-1.json", {"branches": ["lane/mine"]})
        self.write("build/review/other.json", {"branch": "lane/other", "verdict": "changes", "round": 5})
        self.write("build/review/mine.json", {"branch": "lane/mine", "verdict": "pass", "round": 1})
        doc = self.run_digest()
        self.assertNotIn("review_rounds_over_cap", self.fired(doc))
        self.assertEqual((doc["counts"]["review_rounds"], doc["counts"]["skipped_reviews"]), (1, 1))

    def test_status_defaults_to_the_worktree_status_file(self):
        self.write("build/status/T.json", {"status": "blocked", "blocked_reason": "owner_review"})
        doc = self.run_digest(task="T")
        self.assertEqual(doc["outcome"], "blocked")
        self.assertNotIn("no status", doc["aar"]["happened"])
        self.assertIn("owner_review", self.fired(doc)["blocked"][0])

    def test_a_missing_worktree_status_file_is_fine(self):
        doc = self.run_digest(task="T")
        self.assertEqual(doc["triggers"], [])
        self.assertIsNone(doc["outcome"])

    def test_blocked_from_status(self):
        status = self.write("status.json", {"state": "blocked", "blocked_reason": "needs a key", "summary": "s"})
        self.assertIn("needs a key", self.fired(self.run_digest("--status", str(status)))["blocked"][0])

    def test_runner_outcomes(self):
        self.assertIn("timeout", self.fired(self.run_digest("--outcome", "blocked:timeout")))
        self.assertIn("retry", self.fired(self.run_digest("--outcome", "retry", "--attempt", "1")))
        self.assertIn("worker_failed", self.fired(self.run_digest("--outcome", "blocked:worker_failed")))

    def test_review_rounds_over_cap(self):
        self.write("build/tasks/R-1.json", {"branches": ["lane/a", "lane/b"]})
        self.write("build/review/a.json", {"branch": "lane/a", "verdict": "changes", "round": 3})
        self.write("build/review/b.json", {"branch": "lane/b", "verdict": "pass", "round": 1})
        doc = self.run_digest()
        self.assertIn("review_rounds_over_cap", self.fired(doc))
        self.assertEqual(doc["counts"]["review_rounds"], 3)
        self.write("build/review/a.json", {"branch": "lane/a", "verdict": "pass", "round": 2})
        self.assertNotIn("review_rounds_over_cap", self.fired(self.run_digest()))

    def test_owner_correction_after_start(self):
        status = self.write("status.json", {"state": "done", "started": "2026-11-02T10:00:00Z"})
        comments = self.write("replies.json", [{"createdAt": "2026-11-02T09:00:00Z", "body": "old"},
                                               {"createdAt": "2026-11-02T11:00:00Z", "body": "no, the other tile"}])
        fired = self.fired(self.run_digest("--status", str(status), "--comments", str(comments)))
        self.assertEqual(len(fired["owner_correction"]), 1)
        self.assertIn("other tile", fired["owner_correction"][0])

    def test_routing_override_level_raised(self):
        self.write("build/tasks/R-1.json", {"id": "R-1", "level": "L2", "intake": "u", "brief": "b",
                                            "level_history": [{"from": "L0", "to": "L2", "reason": "visible"}]})
        self.assertIn("L0 -> L2", self.fired(self.run_digest())["routing_override"][0])

    def test_routing_override_gate_hint_differs(self):
        self.write("build/tasks/R-1.json", {"id": "R-1", "level": "L1"})
        self.write("build/jev/gate.jsonl", json.dumps({"subject": "R-1", "question": "design.user_visible@1",
                                                        "value": False}) + "\n"
                   + "garbage\n" + json.dumps({"subject": "R-1", "question": "decision.needs_owner@1",
                                                "value": False}) + "\n")
        doc = self.run_digest()
        self.assertEqual(doc["level"]["gate_hint"], "L0")
        self.assertIn("gate routed to L0", self.fired(doc)["routing_override"][0])

    def test_gate_hint_matching_level_is_quiet(self):
        self.write("build/tasks/R-1.json", {"id": "R-1", "level": "L0"})
        self.write("build/jev/gate.jsonl", json.dumps({"subject": "R-1", "question": "design.user_visible@1",
                                                        "value": "false"}) + "\n")
        self.assertNotIn("routing_override", self.fired(self.run_digest()))

    def test_waiting_ending(self):
        log = self.write("w.log", "stderr noise\n" + assistant("Started the suite. I'll wait for it to finish.") + "\n" + result())
        self.assertIn("waiting_ending", self.fired(self.run_digest("--log", str(log))))
        log = self.write("w.log", assistant("Done. PR is open.") + "\n" + result())
        self.assertNotIn("waiting_ending", self.fired(self.run_digest("--log", str(log))))

    def test_cost_counts_and_over_budget(self):
        log = self.write("c.log", assistant("ok") + "\n" + result(duration_ms=150 * 60000))
        doc = self.run_digest("--log", str(log))
        self.assertEqual(doc["cost"]["total_cost_usd"], 1.5)
        self.assertEqual(doc["cost"]["tokens"], 600)  # cache reads are not counted
        self.assertEqual(doc["counts"]["turns"], 42)
        self.assertEqual(doc["durations"]["minutes"], 150.0)
        self.assertIn("minutes", self.fired(doc)["over_budget"][0])
        doc = self.run_digest("--log", str(log), "--max-tokens", "500", "--max-minutes", "999")
        self.assertIn("600 fresh tokens", self.fired(doc)["over_budget"][0])

    def test_slot_wait(self):
        log = self.write("s.log", "devcap: still waiting (5m) for 'sim'\ndevcap: still waiting (1h05m) for 'sim' ...\n")
        fired = self.fired(self.run_digest("--log", str(log)))
        self.assertEqual(fired["slot_wait"][1], "65 minutes")
        log = self.write("s.log", "devcap: still waiting (19m) for 'sim'\n")
        self.assertNotIn("slot_wait", self.fired(self.run_digest("--log", str(log))))

    def t3_log(self, tool_output="", text="finished the lane"):
        """A T3 launch's log: ``t3_launch``, then one ``t3_thread`` line (no ``result`` event: T3 reports no cost)."""
        thread = {"messages": [{"role": "user", "text": "go"}, {"role": "assistant", "text": "working"},
                               {"role": "assistant", "text": text}],
                  "toolCalls": [{"name": "Bash", "output": tool_output}]}
        return self.write("t3.log", json.dumps({"type": "t3_launch", "thread": "t"}) + "\n"
                          + json.dumps({"type": "t3_thread", "thread": "t", "data": {"thread": thread}}) + "\n")

    def test_a_t3_log_gives_the_last_assistant_text_and_tool_outputs_and_no_cost(self):
        info = rd.parse_log(self.t3_log("line one\ndevcap: still waiting (40m) for 'sim'"))
        self.assertEqual((info["last_text"], info["launcher"], info["result"]), ("finished the lane", "t3code", None))
        self.assertIn("\ndevcap: still waiting (40m)", info["raw"])
        self.assertEqual(rd.parse_log(self.write("c.log", assistant("hi") + "\n" + result()))["launcher"], "claude")
        doc = self.run_digest("--log", str(self.t3_log("devcap: still waiting (40m) for 'sim'")))
        self.assertEqual(self.fired(doc)["slot_wait"][1], "40 minutes")
        self.assertIsNone(doc["cost"]["total_cost_usd"])  # unknown, never zero
        self.assertIsNone(doc["cost"]["tokens"])
        self.assertEqual(doc["counts"]["turns"], 0)

    def test_a_launch_that_never_started_is_a_t3_log_too(self):
        log = self.write("f.log", json.dumps({"type": "t3_launch_failed", "reason": "guard files differ"}) + "\n")
        self.assertEqual(rd.parse_log(log)["launcher"], "t3code")

    def test_a_claude_log_still_reports_its_cost(self):
        doc = self.run_digest("--log", str(self.write("c.log", assistant("hi") + "\n" + result())))
        self.assertEqual(doc["cost"]["total_cost_usd"], 1.5)
        self.assertEqual(doc["cost"]["tokens"], 600)

    def test_stopped_with_live_children(self):
        self.write("build/runs/job.running", {"pid": os.getpid(), "label": "job"})
        self.write("build/runs/dead.running", {"pid": 2 ** 22 + 12345, "label": "dead"})
        evidence = self.fired(self.run_digest())["stopped_with_live_children"]
        self.assertEqual(len(evidence), 1)
        self.assertIn("job", evidence[0])

    def test_a_ci_wait_is_not_a_stray_job_but_a_build_job_is(self):
        """Fails if: a live ci-81.running fires stopped_with_live_children, or a live build-9.running does not."""
        self.write("build/runs/ci-81.running", {"pid": os.getpid(), "label": "ci-81"})
        self.assertNotIn("stopped_with_live_children", self.fired(self.run_digest()))
        self.write("build/runs/build-9.running", {"pid": os.getpid(), "label": "build-9"})
        evidence = self.fired(self.run_digest())["stopped_with_live_children"]
        self.assertEqual(len(evidence), 2)
        self.assertIn("build-9", evidence[0])
        self.assertIn("1 ci wait", evidence[-1])  # Fails if: the skipped ci wait is not noted beside a stray job

    def test_a_recorded_raise_to_the_gate_hint_is_not_an_override(self):
        """Fails if: a raise to the gate's own hint with a reason fires routing_override."""
        self.write("build/tasks/R-1.json", {"id": "R-1", "level": "L2",
                                            "level_history": [{"from": "L0", "to": "L2", "reason": "new visible line"}]})
        self.write("build/jev/gate.jsonl", json.dumps({"subject": "R-1", "question": "design.user_visible@1",
                                                        "value": True}) + "\n"
                   + json.dumps({"subject": "R-1", "question": "design.target_decided@1",
                                 "value": False}) + "\n")
        doc = self.run_digest()
        self.assertEqual(doc["level"]["gate_hint"], "L2")
        self.assertNotIn("routing_override", self.fired(doc))

    def test_a_raise_to_the_hint_with_no_reason_still_fires(self):
        """Fails if: a raise onto the hint with an empty reason is waved through."""
        self.write("build/tasks/R-1.json", {"id": "R-1", "level": "L2", "level_history": [{"from": "L0", "to": "L2"}]})
        self.write("build/jev/gate.jsonl", json.dumps({"subject": "R-1", "question": "design.user_visible@1",
                                                        "value": True}) + "\n"
                   + json.dumps({"subject": "R-1", "question": "design.target_decided@1",
                                 "value": False}) + "\n")
        self.assertIn("routing_override", self.fired(self.run_digest()))

    def test_a_lowering_with_no_history_is_flagged(self):
        """Fails if: an L2 hint with a final L0 and no history does not fire, or its text lacks "no reason recorded"."""
        self.write("build/tasks/R-1.json", {"id": "R-1", "level": "L0"})
        self.write("build/jev/gate.jsonl", json.dumps({"subject": "R-1", "question": "design.user_visible@1",
                                                        "value": True}) + "\n"
                   + json.dumps({"subject": "R-1", "question": "design.target_decided@1",
                                 "value": False}) + "\n")
        doc = self.run_digest()
        self.assertEqual(doc["level"]["gate_hint"], "L2")
        self.assertIn("no reason recorded", self.fired(doc)["routing_override"][0])

    def test_tool_errors_counted_and_redacted(self):
        log = self.write("e.log", "error: HTTP 401: Requires authentication\nHTTP 401 again\nNot logged in · Please run /login\n"
                                  "ENOSPC: no space\n'In Progress' not found\nAuthorization: Bearer ghp_" + "x" * 30 + " HTTP 401\n")
        doc = self.run_digest("--log", str(log))
        self.assertEqual(doc["counts"]["tool_errors"], {"enospc": 1, "gh_401": 3, "label_not_found": 1, "not_logged_in": 1})
        text = json.dumps(doc)
        self.assertNotIn("ghp_" + "x" * 30, text)

    def test_aar_and_checks(self):
        self.write("build/tasks/R-1.json", {"id": "R-1", "level": "L1", "intake": "https://x/1", "brief": "fix tile",
                                            "acceptance": [{"id": "c1", "passes": True}, {"id": "c2", "passes": False}]})
        status = self.write("status.json", {"state": "done", "summary": "Fixed the tile."})
        doc = self.run_digest("--status", str(status))
        self.assertIn("fix tile", doc["aar"]["intended"])
        self.assertIn("Fixed the tile.", doc["aar"]["happened"])
        self.assertEqual((doc["counts"]["checks"], doc["counts"]["checks_passing"]), (2, 1))

    def test_bad_json_inputs_are_skipped(self):
        self.write("build/tasks/R-1.json", "{not json")
        self.write("build/review/x.json", "[1]")
        status = self.write("status.json", "nope")
        self.assertEqual(self.run_digest("--status", str(status))["triggers"], [])


class NamedWaitTests(Base):
    OWNER_WAIT = "owner_wait: PR 211 head ea49c6d7"

    def set_wait(self, reason=OWNER_WAIT, *, check_passes=False, observed="not_run",
                 observed_check="digest-wait", status_task="R-1", write_ledger=True):
        if write_ledger:
            self.write("build/tasks/R-1.json", {
                "id": "R-1",
                "acceptance": [
                    {"id": "factory-impl", "passes": True},
                    {"id": "unit-tests", "passes": True},
                    {"id": "digest-wait", "passes": check_passes},
                    {"id": "digest-wait-rev", "passes": False},
                ],
            })
        else:
            (self.build / "tasks" / "R-1.json").unlink(missing_ok=True)
        self.write("build/status/R-1.json", {
            "task": status_task, "status": "blocked", "blocked_reason": reason,
            "acceptance": {observed_check: observed},
        })

    def test_owner_wait_with_open_not_run_check_is_counted(self):
        """Fails if: owner_wait on an open check reported not_run fires blocked or is not counted."""
        self.set_wait(self.OWNER_WAIT)
        doc = self.run_digest()
        self.assertNotIn("blocked", self.fired(doc))
        self.assertEqual(doc["counts"]["waits"], 1)

    def test_lane_wait_with_open_failed_status_is_counted(self):
        """Fails if: lane_wait on an open check reported fail fires blocked or is not counted."""
        self.set_wait(self.OWNER_WAIT.replace("owner_wait:", "lane_wait:"),
                      observed="fail", observed_check="digest-wait-rev")
        doc = self.run_digest()
        self.assertNotIn("blocked", self.fired(doc))
        self.assertEqual(doc["counts"]["waits"], 1)

    def test_same_wait_text_without_prefix_fires_blocked(self):
        """Fails if: removing the owner_wait prefix stops an ordinary blocked status from firing."""
        reason = self.OWNER_WAIT.removeprefix("owner_wait: ")
        self.set_wait(reason)
        doc = self.run_digest()
        self.assertIn("blocked", self.fired(doc))
        self.assertEqual(doc["counts"]["waits"], 0)

    def test_owner_wait_with_pass_against_open_check_fires_blocked(self):
        """Fails if: stale pass against an open ledger check does not cancel the named wait."""
        self.set_wait(observed="pass")
        doc = self.run_digest()
        self.assertEqual(doc["status_stale"], ["digest-wait"])
        self.assertIn("blocked", self.fired(doc))
        self.assertEqual(doc["counts"]["waits"], 0)

    def test_owner_wait_with_fail_against_passing_check_fires_blocked(self):
        """Fails if: stale fail against a passing ledger check does not cancel the named wait."""
        self.set_wait(check_passes=True, observed="fail")
        doc = self.run_digest()
        self.assertEqual(doc["status_stale"], ["digest-wait"])
        self.assertIn("blocked", self.fired(doc))
        self.assertEqual(doc["counts"]["waits"], 0)

    def test_owner_wait_for_another_task_fires_blocked(self):
        """Fails if: a wait-prefixed status for another task is treated as this task's wait."""
        self.set_wait(status_task="R-2")
        doc = self.run_digest()
        self.assertEqual(doc["status_stale"], [])
        self.assertIn("blocked", self.fired(doc))
        self.assertEqual(doc["counts"]["waits"], 0)

    def test_owner_wait_without_ledger_fires_and_names_ledger(self):
        """Fails if: a missing ledger permits the wait or blocked evidence omits the ledger."""
        self.set_wait(write_ledger=False)
        doc = self.run_digest()
        evidence = self.fired(doc)["blocked"]
        self.assertIn("ledger", evidence[0])
        self.assertIn("R-1.json", evidence[0])
        self.assertEqual(doc["counts"]["waits"], 0)

    def test_owner_wait_with_malformed_ledger_fires_blocked(self):
        """Fails if: either a non-Boolean passes value or a duplicated check id permits the wait."""
        malformed = [
            [{"id": "digest-wait", "passes": "false"}],
            [{"id": "digest-wait", "passes": False}, {"id": "digest-wait", "passes": False}],
        ]
        for checks in malformed:
            with self.subTest(checks=checks):
                self.set_wait()
                self.write("build/tasks/R-1.json", {"id": "R-1", "acceptance": checks})
                doc = self.run_digest()
                self.assertIn("blocked", self.fired(doc))
                self.assertEqual(doc["counts"]["waits"], 0)

    def test_owner_wait_with_empty_text_fires_blocked(self):
        """Fails if: a wait prefix without non-whitespace text suppresses blocked."""
        for reason in ("owner_wait:", "owner_wait:   "):
            with self.subTest(reason=reason):
                self.set_wait(reason)
                doc = self.run_digest()
                self.assertIn("blocked", self.fired(doc))
                self.assertEqual(doc["counts"]["waits"], 0)

    def test_runner_reported_block_is_not_suppressed_by_wait_prefix(self):
        """Fails if: a runner blocked outcome with a wait-prefixed reason omits blocked or timeout."""
        self.set_wait(self.OWNER_WAIT)
        doc = self.run_digest("--outcome", "blocked:timeout")
        self.assertIn("blocked", self.fired(doc))
        self.assertIn("timeout", self.fired(doc))

    def test_named_wait_keeps_base_outcome_and_happened_values(self):
        """Fails if: a named wait changes the base state outcome or uses a wait happened line."""
        self.set_wait()
        doc = self.run_digest()
        self.assertEqual(doc["outcome"], "blocked")
        self.assertEqual(doc["aar"]["happened"], f"blocked: {self.OWNER_WAIT}")

    def test_weekly_reader_parses_digest_with_wait_count(self):
        """Fails if: the weekly reader rejects or drops a digest carrying counts.waits."""
        self.set_wait(self.OWNER_WAIT)
        digest = self.run_digest()
        self.assertEqual(digest["counts"]["waits"], 1)
        records = rw.collect(None, self.dir, None)
        self.assertEqual(len(records["digests"]), 1)
        at = records["digests"][0]["at"]
        metrics = rw.metrics(records, at, at + timedelta(seconds=1))
        self.assertEqual(metrics["tasks"][0]["task"], "R-1")


class S3ProofTests(Base):
    TASK = "request-s3"
    MISSING = object()

    def check(self, check_id, passes):
        return {"id": check_id, "check": f"{check_id} is complete", "passes": passes}

    def set_flow(self, checks, observed=MISSING, *, reason=None, summary=None, status_task=TASK,
                 state_key="status", ledger_task=TASK, write_ledger=True):
        if write_ledger:
            self.write(f"build/tasks/{self.TASK}.json", {
                "id": ledger_task, "level": "L0", "intake": "fix retro digest", "brief": "prove stale status handling",
                "acceptance": checks,
            })
        status = {state_key: "blocked"}
        if status_task is not self.MISSING:
            status["task"] = status_task
        if observed is not self.MISSING:
            status["acceptance"] = observed
        if reason is not None:
            status["blocked_reason"] = reason
        if summary is not None:
            status["summary"] = summary
        self.write(f"build/status/{self.TASK}.json", status)

    def set_gate(self, records):
        self.write("build/jev/gate.jsonl", "".join(json.dumps(record) + "\n" for record in records))

    def test_s3_1_c_resolved_check_only_block_is_suppressed(self):
        """Fails if: a newer check-only blocked snapshot retains the status trigger."""
        self.set_flow([self.check("x", True)], {"x": "fail"})
        os.utime(self.build / "tasks" / f"{self.TASK}.json", (100, 100))
        os.utime(self.build / "status" / f"{self.TASK}.json", (200, 200))
        doc = self.run_digest(task=self.TASK)
        self.assertNotIn("blocked", self.fired(doc))
        self.assertEqual(doc["status_stale"], ["x"])

    def test_s3_2_a_c_open_check_agrees_and_blocks(self):
        """Fails if: an open ledger check contradicts the compatible fail snapshot."""
        self.set_flow([self.check("x", False)], {"x": "fail"}, reason="x")
        doc = self.run_digest(task=self.TASK)
        self.assertIn("blocked", self.fired(doc))
        self.assertEqual(doc["status_stale"], [])

    def test_s3_2_b_c_not_run_has_no_comparable_result(self):
        """Fails if: status not_run is treated as pass or fail."""
        self.set_flow([self.check("x", False)], {"x": "not_run"}, reason="x")
        doc = self.run_digest(task=self.TASK)
        self.assertIn("blocked", self.fired(doc))
        self.assertEqual(doc["status_stale"], [])

    def test_s3_2_c_reverse_contradiction_still_blocks(self):
        """Fails if: pass against an open check clears the blocked snapshot."""
        self.set_flow([self.check("x", False)], {"x": "pass"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], [])

    def test_s3_2_d_agreeing_all_pass_still_blocks(self):
        """Fails if: an agreeing all-pass ledger alone clears a blocked snapshot."""
        self.set_flow([self.check("x", True)], {"x": "pass"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], [])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_3_a_missing_acceptance_preserves_status(self):
        """Fails if: a missing acceptance map is treated as resolved evidence."""
        self.set_flow([self.check("x", True)])
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], [])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], [])

    def test_s3_3_b_empty_acceptance_preserves_status(self):
        """Fails if: an empty acceptance map is treated as resolved evidence."""
        self.set_flow([self.check("x", True)], {})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], [])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], [])

    def test_s3_4_a_unknown_status_id_does_not_resolve_block(self):
        """Fails if: an unknown status id is compared as a passing ledger check."""
        self.set_flow([self.check("x", True)], {"unknown": "fail"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], [])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_4_b_known_stale_id_survives_unknown_peer(self):
        """Fails if: an unknown peer is discarded and the remaining map clears the block."""
        self.set_flow([self.check("x", True)], {"x": "fail", "y": "fail"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_5_a_matching_task_before_foreign_rows_keeps_its_hint(self):
        """Fails if: a foreign task after this task supplies the routing hint."""
        self.write(f"build/tasks/{self.TASK}.json", {"id": self.TASK, "level": "L0", "acceptance": []})
        self.set_gate([
            {"subject": self.TASK, "question": "design.user_visible", "value": False},
            {"subject": "request-other", "question": "design.user_visible", "value": True},
            {"subject": "request-other", "question": "design.target_decided", "value": False},
        ])
        self.assertEqual(self.run_digest(task=self.TASK)["level"]["gate_hint"], "L0")

    def test_s3_5_b_matching_task_after_foreign_rows_keeps_its_hint(self):
        """Fails if: the globally first foreign answer supplies the routing hint."""
        self.write(f"build/tasks/{self.TASK}.json", {"id": self.TASK, "level": "L0", "acceptance": []})
        self.set_gate([
            {"subject": "request-other", "question": "design.user_visible", "value": True},
            {"subject": "request-other", "question": "design.target_decided", "value": False},
            {"subject": self.TASK, "question": "design.user_visible", "value": False},
        ])
        self.assertEqual(self.run_digest(task=self.TASK)["level"]["gate_hint"], "L0")

    def test_s3_5_c_last_matching_answer_wins(self):
        """Fails if: the first matching answer is frozen after a later answer changes the hint."""
        self.write(f"build/tasks/{self.TASK}.json", {"id": self.TASK, "level": "L0", "acceptance": []})
        self.set_gate([
            {"subject": self.TASK, "question": "design.user_visible", "value": True},
            {"subject": self.TASK, "question": "design.target_decided", "value": False},
            {"subject": self.TASK, "question": "design.user_visible", "value": False},
        ])
        self.assertEqual(self.run_digest(task=self.TASK)["level"]["gate_hint"], "L0")

    def test_s3_6_a_unscoped_rows_leave_hint_null(self):
        """Fails if: legacy rows without subject are attributed to this task."""
        self.set_gate([{"question": "design.user_visible", "value": False}])
        doc = self.run_digest(task=self.TASK)
        self.assertIsNone(doc["level"]["gate_hint"])
        self.assertNotIn("routing_override", self.fired(doc))

    def test_s3_6_b_non_string_subject_returns_digest_without_hint(self):
        """Fails if: a list-valued subject crashes the digest instead of being ignored."""
        self.set_gate([{"subject": ["request-s3"], "question": "design.user_visible", "value": False}])
        output = self.build / "retro" / f"{self.TASK}.json"
        self.assertEqual(rd.main(["--task", self.TASK, "--worktree", str(self.dir)]), 0)
        self.assertTrue(output.is_file(), "digest JSON was not written")
        self.assertIsNone(json.loads(output.read_text())["level"]["gate_hint"])

    def test_s3_6_c_empty_subject_leaves_hint_null(self):
        """Fails if: an empty subject is assigned to this worktree."""
        self.set_gate([{"subject": "", "question": "design.user_visible", "value": False}])
        self.assertIsNone(self.run_digest(task=self.TASK)["level"]["gate_hint"])

    def test_s3_7_weekly_collector_keeps_digest_and_trigger_metrics(self):
        """Fails if: the weekly collector silently drops a digest with status_stale."""
        self.set_flow([self.check("x", True)], {"x": "fail"})
        self.write(f"build/tasks/{self.TASK}.json", {
            "id": self.TASK, "level": "L2", "acceptance": [self.check("x", True)],
            "level_history": [{"from": "L0", "to": "L2", "reason": "visible"}],
        })
        digest = self.run_digest(task=self.TASK)
        self.assertEqual(digest["status_stale"], ["x"])
        records = rw.collect(None, self.dir, None)
        self.assertEqual(len(records["digests"]), 1)
        at = records["digests"][0]["at"]
        metrics = rw.metrics(records, at, at + timedelta(seconds=1))
        self.assertEqual(metrics["tasks"][0]["task"], self.TASK)
        self.assertEqual(metrics["triggers"]["routing_override"], 1)

    def test_s3_8_one_stale_failure_does_not_hide_open_peer(self):
        """Fails if: any stale failure clears a block with another open check."""
        self.set_flow([self.check("x", True), self.check("y", False)], {"x": "fail", "y": "fail"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_9_absent_open_ledger_check_still_blocks(self):
        """Fails if: suppression inspects only ledger ids present in the status map."""
        self.set_flow([self.check("x", True), self.check("y", False)], {"x": "fail"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_10_runner_blocked_outcome_survives_stale_status(self):
        """Fails if: stale status freshness suppresses the runner's blocked timeout evidence."""
        self.set_flow([self.check("x", True)], {"x": "fail"})
        doc = self.run_digest("--outcome", "blocked:timeout", task=self.TASK)
        self.assertEqual(doc["outcome"], "blocked:timeout")
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], ["blocked:timeout"])
        self.assertIn("timeout", fired)

    def test_s3_11_owner_wait_remains_an_independent_block(self):
        """Fails if: an all-pass ledger erases a separate owner-wait reason."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="owner: awaiting approval")
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertIn("owner", fired["blocked"][0])

    def test_s3_12_suppressed_status_uses_ledger_aar_and_null_outcome(self):
        """Fails if: suppressed status leaves its old AAR or inferred blocked outcome."""
        self.set_flow([self.check("x", True)], {"x": "fail"})
        doc = self.run_digest(task=self.TASK)
        self.assertNotIn("blocked", self.fired(doc))
        self.assertEqual(doc["aar"]["happened"], "ledger: 1/1 checks pass")
        self.assertIsNone(doc["outcome"])

    def test_s3_13_runner_done_leads_without_stale_status_summary(self):
        """Fails if: a runner done outcome repeats the superseded status summary."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="checks:x", summary="old blocked summary")
        doc = self.run_digest("--outcome", "done", task=self.TASK)
        self.assertEqual(doc["outcome"], "done")
        self.assertNotIn("old blocked", doc["aar"]["happened"])
        self.assertEqual(doc["aar"]["happened"], "done")

    def test_s3_14_not_run_does_not_supply_stale_failure(self):
        """Fails if: not_run is rewritten to a stale fail for a passing check."""
        self.set_flow([self.check("x", True)], {"x": "not_run"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], [])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_15_non_boolean_ledger_value_prevents_suppression(self):
        """Fails if: a string ledger value is accepted by truthiness."""
        self.set_flow([self.check("x", True), self.check("y", "false")], {"x": "fail"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_16_absent_ledger_preserves_blocked_snapshot(self):
        """Fails if: no ledger is treated as an all-pass ledger."""
        self.set_flow([], {"x": "fail"}, write_ledger=False)
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], [])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], [])

    def test_s3_17_duplicate_ledger_id_is_not_compared(self):
        """Fails if: a duplicate ledger id becomes an ambiguous last-wins comparison."""
        self.set_flow([self.check("x", False), self.check("x", True)], {"x": "fail"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], [])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_18_foreign_status_task_has_no_stale_comparison(self):
        """Fails if: matching-looking check ids join a foreign status task."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, status_task="request-foreign")
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], [])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_19_headless_blocked_without_acceptance_is_unchanged(self):
        """Fails if: only the interactive status key is read for a headless block."""
        self.set_flow([], reason="worker wait", state_key="state", status_task=self.MISSING,
                      write_ledger=False)
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], [])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], ["worker wait"])

    def test_s3_20_foreign_gate_rows_keep_raw_sources_and_counts(self):
        """Fails if: subject filtering removes foreign rows from raw telemetry."""
        self.set_gate([
            {"subject": "request-other", "question": "design.user_visible", "value": False},
            {"subject": "request-another", "question": "decision.needs_owner", "value": False},
        ])
        doc = self.run_digest(task=self.TASK)
        self.assertIsNone(doc["level"]["gate_hint"])
        self.assertIn("gate", doc["sources"])
        self.assertEqual(doc["counts"]["gate_answers"], 2)

    def test_s3_21_level_history_override_survives_null_hint(self):
        """Fails if: a null hint disables a recorded level-history override."""
        self.write(f"build/tasks/{self.TASK}.json", {
            "id": self.TASK, "level": "L2", "acceptance": [],
            "level_history": [{"from": "L0", "to": "L2", "reason": "visible user surface"}],
        })
        self.set_gate([{"subject": "request-other", "question": "design.user_visible", "value": False}])
        doc = self.run_digest(task=self.TASK)
        self.assertIsNone(doc["level"]["gate_hint"])
        fired = self.fired(doc)
        self.assertIn("routing_override", fired)
        self.assertIn("L0 -> L2", fired["routing_override"][0])

    def test_s3_22_stale_ids_are_sorted_deterministically(self):
        """Fails if: stale ids preserve status-map insertion order."""
        self.set_flow([self.check("x", True), self.check("z", True)],
                      {"z": "fail", "x": "fail"}, reason="owner wait")
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x", "z"])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_23_open_retro_check_is_not_exempt(self):
        """Fails if: an open check named retro is ignored during suppression."""
        self.set_flow([self.check("x", True), self.check("retro", False)], {"x": "fail"})
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        self.assertIn("blocked", self.fired(doc))

    def test_s3_24_checks_only_reason_and_old_summary_are_superseded(self):
        """Fails if: a canonical checks-only reason is treated as an independent blocker."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="checks:x", summary="old blocked summary")
        doc = self.run_digest(task=self.TASK)
        self.assertNotIn("blocked", self.fired(doc))
        self.assertEqual(doc["aar"]["happened"], "ledger: 1/1 checks pass")
        self.assertIsNone(doc["outcome"])

    def test_s3_25_owner_only_wait_survives_checks_reason(self):
        """Fails if: owner-only decision metadata is discharged by passing checks."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="checks:x")
        status_path = self.build / "status" / f"{self.TASK}.json"
        status = json.loads(status_path.read_text())
        status["decision"] = {"owner_only": "fixed_set"}
        status_path.write_text(json.dumps(status))
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], ["checks:x"])
        self.assertEqual(doc["outcome"], "blocked")

    def test_s3_26_decision_question_survives_checks_reason(self):
        """Fails if: a decision question is discharged by passing checks."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="checks:x")
        status_path = self.build / "status" / f"{self.TASK}.json"
        status = json.loads(status_path.read_text())
        status["decision"] = {"question": "Which option?"}
        status_path.write_text(json.dumps(status))
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], ["checks:x"])
        self.assertEqual(doc["outcome"], "blocked")

    def test_s3_27_top_level_question_survives_checks_reason(self):
        """Fails if: an interactive status question is discharged by passing checks."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="checks:x")
        status_path = self.build / "status" / f"{self.TASK}.json"
        status = json.loads(status_path.read_text())
        status["question"] = "Which option?"
        status_path.write_text(json.dumps(status))
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], ["checks:x"])
        self.assertEqual(doc["outcome"], "blocked")

    def test_s3_28_checks_reason_without_independent_wait_is_suppressed(self):
        """Green twin: checks-only evidence is still superseded when the ledger passes."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="checks:x",
                      summary="old blocked summary")
        doc = self.run_digest(task=self.TASK)
        self.assertNotIn("blocked", self.fired(doc))
        self.assertEqual(doc["aar"]["happened"], "ledger: 1/1 checks pass")
        self.assertIsNone(doc["outcome"])

    def test_s3_29_needs_decision_state_remains_an_independent_wait(self):
        """Fails if: a reported decision state is rewritten as a stale blocked status."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="checks:x",
                      state_key="state")
        status_path = self.build / "status" / f"{self.TASK}.json"
        status = json.loads(status_path.read_text())
        status["state"] = "needs_decision"
        status_path.write_text(json.dumps(status))
        doc = self.run_digest(task=self.TASK)
        self.assertNotIn("blocked", self.fired(doc))
        self.assertEqual(doc["status_stale"], ["x"])
        self.assertEqual(doc["outcome"], "needs_decision")

    def test_s3_30_needs_decision_status_preserves_blocked_snapshot(self):
        """Fails if: a decision status lets an all-pass ledger suppress a blocked state."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="checks:x",
                      state_key="state")
        status_path = self.build / "status" / f"{self.TASK}.json"
        status = json.loads(status_path.read_text())
        status["status"] = "needs_decision"
        status_path.write_text(json.dumps(status))
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], ["checks:x"])
        self.assertEqual(doc["outcome"], "blocked")

        status["status"] = "blocked"
        status_path.write_text(json.dumps(status))
        green = self.run_digest(task=self.TASK)
        self.assertNotIn("blocked", self.fired(green))
        self.assertEqual(green["status_stale"], ["x"])
        self.assertIsNone(green["outcome"])

    def test_s3_31_needs_research_status_preserves_blocked_snapshot(self):
        """Fails if: a research status lets an all-pass ledger suppress a blocked state."""
        self.set_flow([self.check("x", True)], {"x": "fail"}, reason="checks:x",
                      state_key="state")
        status_path = self.build / "status" / f"{self.TASK}.json"
        status = json.loads(status_path.read_text())
        status["status"] = "needs_research"
        status_path.write_text(json.dumps(status))
        doc = self.run_digest(task=self.TASK)
        self.assertEqual(doc["status_stale"], ["x"])
        fired = self.fired(doc)
        self.assertIn("blocked", fired)
        self.assertEqual(fired["blocked"], ["checks:x"])
        self.assertEqual(doc["outcome"], "blocked")

        status["status"] = "blocked"
        status_path.write_text(json.dumps(status))
        green = self.run_digest(task=self.TASK)
        self.assertNotIn("blocked", self.fired(green))
        self.assertEqual(green["status_stale"], ["x"])
        self.assertIsNone(green["outcome"])

    def test_s3_32_blocked_without_reason_matches_main_evidence(self):
        """Fails if: absent reason and summary evidence differs from main."""
        for state_key in ("state", "status"):
            for outcome, expected in ((None, []), ("done", ["done"])):
                with self.subTest(state_key=state_key, outcome=outcome):
                    self.set_flow([self.check("x", True)], {"x": "pass"},
                                  state_key=state_key)
                    extra = ("--outcome", outcome) if outcome else ()
                    doc = self.run_digest(*extra, task=self.TASK)
                    fired = self.fired(doc)
                    self.assertIn("blocked", fired)
                    self.assertEqual(fired["blocked"], expected)


class ArchiveTests(Base):
    def test_archive_layout_writes_into_the_archive(self):
        self.write("tasks/R-1.json", {"id": "R-1", "level": "L1", "intake": "u", "brief": "b"})
        self.write("status.json", {"state": "blocked", "blocked_reason": "context: budget"})
        self.write("worker.log.tail", assistant("I'll wait for the build.") + "\n" + result())
        self.assertEqual(rd.main(["--task", "R-1", "--archive", str(self.dir)]), 0)
        doc = json.loads((self.dir / "retro" / "R-1.json").read_text())
        self.assertEqual(set(self.fired(doc)), {"blocked", "waiting_ending"})

    def test_archive_runner_blocked_preserves_status_reason(self):
        """Fails if: a runner blocked outcome replaces the worker's archived reason."""
        self.write("tasks/R-1.json", {"id": "R-1"})
        self.write("status.json", {"state": "blocked", "blocked_reason": "needs a key"})
        self.assertEqual(rd.main(["--task", "R-1", "--archive", str(self.dir),
                                  "--outcome", "blocked"]), 0)
        doc = json.loads((self.dir / "retro" / "R-1.json").read_text())
        self.assertEqual(self.fired(doc)["blocked"], ["needs a key"])
        self.assertEqual(doc["outcome"], "blocked")
        self.assertEqual(doc["aar"]["happened"], "blocked: needs a key")

    def test_json_flag_and_cli(self):
        out = self.dir / "o" / "x.json"
        proc = subprocess.run([sys.executable, str(TOOLS / "retro_digest.py"), "--task", "T", "--worktree", str(self.dir),
                               "--json", str(out)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0)
        self.assertTrue(out.is_file())

    def test_unwritable_output_still_exits_zero(self):
        blocker = self.write("blocker", "file")
        self.assertEqual(rd.main(["--task", "T", "--json", str(blocker / "sub" / "x.json")]), 0)


class InstrumentTests(Base):
    def test_a_recording_for_a_timing_issue_fires_wrong_instrument(self):
        status = self.write("status.json", {"state": "done", "repro": {"class": "timing", "instrument": "recording"}})
        self.assertIn("wrong_instrument", self.fired(self.run_digest("--status", str(status))))

    def test_the_status_block_in_the_log_is_read_too(self):
        block = '```status\n{"status": "done", "repro": {"class": "timing", "instrument": "screenshot"}}\n```'
        log = self.write("w.log", assistant(block) + "\n" + result())
        self.assertIn("wrong_instrument", self.fired(self.run_digest("--log", str(log))))

    def test_matching_instruments_do_not_fire(self):
        for repro in ({"class": "timing", "instrument": "trace"}, {"class": "visual", "instrument": "recording"},
                      {"class": "state", "instrument": "unit"}, "junk"):
            status = self.write("status.json", {"state": "done", "repro": repro})
            self.assertNotIn("wrong_instrument", self.fired(self.run_digest("--status", str(status))))


class StoreTests(Base):
    """A ledger's ``branches`` make the digest read the trusted verdict store (a temp home, never the real one)."""

    BRANCH = "agents/merge-guard-fixes-20261109"

    def setUp(self):
        super().setUp()
        self.home = self.dir / "home"
        self.store = self.home / "hass-agents" / "reviews"
        self.store.mkdir(parents=True)
        original = rd.review_verdict.reviews_dir
        rd.review_verdict.reviews_dir = lambda: self.store
        self.addCleanup(setattr, rd.review_verdict, "reviews_dir", original)

    def ledger(self, *branches, review=0):
        self.write("build/tasks/R-1.json", {"id": "R-1", "rounds": {"design": 0, "review": review}, "branches": list(branches)})

    def record(self, branch, sha, rnd, stamped=None, head=None):
        name = f"{branch.replace('/', '__')}-{sha[:12]}.json"
        (self.store / name).write_text(json.dumps({"branch": stamped or branch, "head": head or sha, "round": rnd, "verdict": "changes"}))

    def test_a_lane_with_records_over_the_cap_fires_review_rounds_over_cap(self):
        """Fails if: three store records (rounds 1, 2, 3) on two ledger branches do not give review_verdicts 3 and the trigger."""
        other = "agents/second-20261109"
        self.ledger(self.BRANCH, other)
        for i, rnd in enumerate((1, 2)):
            self.record(self.BRANCH, f"{i}" * 40, rnd)
        self.record(other, "a" * 40, 3)
        doc = self.run_digest()
        self.assertEqual(doc["counts"]["review_verdicts"], 3)
        self.assertEqual(doc["counts"]["review_rounds"], 3)
        self.assertEqual(self.fired(doc)["review_rounds_over_cap"], ["3 review rounds (cap 2)"])

    def test_stray_records_for_another_branch_or_sha_are_not_counted(self):
        """Fails if: a record stamped main, one whose head differs from its file sha, or a prefix-sharing branch name adds to the count."""
        self.ledger(self.BRANCH)
        self.record(self.BRANCH, "1" * 40, 1)
        self.record(self.BRANCH, "2" * 40, 9, stamped="main")
        self.record(self.BRANCH, "3" * 40, 9, head="4" * 40)
        self.record(self.BRANCH + "-2", "5" * 40, 9)
        (self.store / (self.BRANCH.replace("/", "__") + "-6" * 12 + ".json")).write_text("{not json")
        doc = self.run_digest()
        self.assertEqual(doc["counts"]["review_verdicts"], 1)
        self.assertEqual(doc["counts"]["review_rounds"], 1)
        self.assertEqual(doc["triggers"], [])

    def test_an_empty_or_missing_store_and_no_branches_are_unchanged(self):
        """Fails if: an empty store, a missing store or a ledger with no branches changes the digest."""
        self.ledger(self.BRANCH)
        self.assertEqual(self.run_digest()["counts"]["review_verdicts"], 0)
        self.store.rmdir()
        self.assertEqual(self.run_digest()["triggers"], [])
        self.write("build/tasks/R-1.json", {"id": "R-1", "rounds": {"design": 0, "review": 0}})
        self.assertEqual(self.run_digest()["counts"]["review_rounds"], 0)

    def test_a_verdict_in_both_the_local_copy_and_the_store_counts_once(self):
        """Fails if: the copy in build/review and the store copy of the same (branch, head, round) count twice, or a bad branch name reads the store."""
        sha = "8" * 40
        self.ledger(self.BRANCH, "../escape")
        self.record(self.BRANCH, sha, 2)
        self.write("build/review/local.json", {"branch": self.BRANCH, "head": sha, "round": 2, "verdict": "changes"})
        self.assertEqual(self.run_digest()["counts"]["review_verdicts"], 1)
        self.assertEqual(rd.store_records("../escape", self.store), [])

    def test_add_branch_records_once_and_the_digest_reads_it(self):
        """Fails if: tasks.py add-branch writes a duplicate, accepts a bad name, or the digest cannot read what it wrote."""
        tasks = importlib.util.spec_from_file_location("tasks_cli", TOOLS / "tasks.py")
        module = importlib.util.module_from_spec(tasks)
        tasks.loader.exec_module(module)
        self.write("build/tasks/R-1.json", {"id": "R-1", "rounds": {"design": 0, "review": 0}})
        os.environ["TASKS_DIR"] = str(self.build / "tasks")
        self.addCleanup(os.environ.pop, "TASKS_DIR", None)
        for _ in range(2):
            self.assertEqual(module.main(["add-branch", "R-1", self.BRANCH]), 0)
        with self.assertRaises(SystemExit):
            module.main(["add-branch", "R-1", "bad branch;"])
        self.assertEqual(json.loads((self.build / "tasks" / "R-1.json").read_text())["branches"], [self.BRANCH])
        self.record(self.BRANCH, "7" * 40, 4)
        self.assertEqual(self.run_digest()["counts"]["review_rounds"], 4)


class LaneTests(Base):
    """``--lane``: a digest from what a lane leaves behind (bg_run digests, review file, commits), no ledger task."""

    def setUp(self):
        super().setUp()
        self.git("init", "-q", "-b", "claude/lane-x")
        self.commit("base", 1_000_000_000)
        self.git("branch", "base")

    def git(self, *args, **env):
        done = subprocess.run(["git", "-C", str(self.dir), "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
                              capture_output=True, text=True, env={**os.environ, **env})
        self.assertEqual(done.returncode, 0, done.stderr)
        return done.stdout

    def commit(self, name, when):
        self.write(f"f-{name}.txt", name)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", name, GIT_COMMITTER_DATE=f"{when} +0000", GIT_AUTHOR_DATE=f"{when} +0000")

    def run_record(self, label, head, body=""):
        self.write(f"build/runs/{label}.digest", head + "\n" + body)

    def lane(self, *extra, name="lane-x"):
        self.assertEqual(rd.main(["--lane", name, "--worktree", str(self.dir), "--base", "base", *extra]), 0)
        return json.loads((self.build / "retro" / f"lane-{name.split('/')[-1]}.json").read_text())

    def test_a_quiet_lane_fires_nothing_and_counts_commits(self):
        self.commit("one", 1_000_000_600)
        self.commit("two", 1_000_001_800)
        self.run_record("unit", "RESULT: PASS (exit 0)  unit  45s", "tests: executed 40, skipped 0, failed 0")
        doc = self.lane()
        self.assertEqual(doc["task"], "lane-lane-x")
        self.assertEqual(doc["triggers"], [])
        self.assertEqual((doc["counts"]["commits"], doc["counts"]["runs"]), (2, 1))
        self.assertEqual(doc["durations"]["minutes"], 20.0)

    def test_repeated_long_device_rounds_fire(self):
        self.run_record("uitest-1", "RESULT: PASS (exit 0)  uitest-1  34m10s", "tests: executed 12, skipped 0, failed 0")
        self.run_record("uitest-2", "RESULT: FAIL (exit 1)  uitest-2  34m02s", "tests: executed 12, skipped 0, failed 1")
        self.run_record("build", "RESULT: PASS (exit 0)  build  45m00s")
        evidence = self.fired(self.lane())["repeated_long_device_rounds"]
        self.assertTrue(any("uitest-1: 34m10s" in line for line in evidence))
        self.assertFalse(any("build" in line for line in evidence))

    def test_task_flows_get_the_run_triggers_too(self):
        self.write("build/runs/uitest-1.digest", "RESULT: PASS (exit 0)  uitest-1  34m10s  task=R-1\n")
        self.write("build/runs/uitest-2.digest", "RESULT: FAIL (exit 1)  uitest-2  34m02s  task=R-1\n")
        self.write("build/runs/journeys.digest", "RESULT: EMPTY (exit 0)  journeys  13s  task=R-1\ntests: executed 0, skipped 3, failed 0\n")
        fired = self.fired(self.run_digest())
        self.assertIn("repeated_long_device_rounds", fired)
        self.assertIn("empty_runs", fired)

    def test_a_single_long_round_is_not_repeated(self):
        self.run_record("uitest-1", "RESULT: PASS (exit 0)  uitest-1  34m10s")
        self.assertNotIn("repeated_long_device_rounds", self.fired(self.lane()))

    def test_empty_runs_fire_for_empty_verdicts_and_old_zero_second_device_passes(self):
        self.run_record("journeys", "RESULT: EMPTY (exit 0)  journeys  13s", "tests: executed 0, skipped 3, failed 0")
        self.run_record("uitest-zero", "RESULT: PASS (exit 0)  uitest-zero  0s")
        self.run_record("chore", "RESULT: PASS (exit 0)  chore  0s")  # not a device run
        evidence = self.fired(self.lane())["empty_runs"]
        self.assertEqual(len(evidence), 2)
        self.assertTrue(any(line.startswith("journeys: EMPTY, executed 0, skipped 3") for line in evidence))

    def test_superseded_empty_does_not_fire(self):
        self.run_record("journeys", "RESULT: EMPTY (exit 0)  journeys  13s  sha=abc", "products: hit aa11\ntests: executed 0, skipped 3, failed 0")
        self.run_record("journeys-2", "RESULT: PASS (exit 0)  journeys-2  3m05s  sha=abc", "products: hit aa11\ntests: executed 5, skipped 0, failed 0")
        self.stamp("journeys", 100)
        self.stamp("journeys-2", 200)
        doc = self.lane()
        self.assertNotIn("empty_runs", self.fired(doc))
        self.assertEqual(doc["counts"]["runs"], 2)

    def test_a_lone_empty_still_fires(self):
        self.run_record("journeys", "RESULT: EMPTY (exit 0)  journeys  13s  sha=abc", "products: hit aa11\ntests: executed 0, skipped 3, failed 0")
        self.assertIn("empty_runs", self.fired(self.lane()))

    def test_empty_then_pass_on_other_products_still_fires(self):
        self.run_record("journeys", "RESULT: EMPTY (exit 0)  journeys  13s  sha=abc", "products: hit aa11\ntests: executed 0, skipped 3, failed 0")
        self.run_record("journeys-2", "RESULT: PASS (exit 0)  journeys-2  3m05s  sha=abc", "products: built bb22\ntests: executed 5, skipped 0, failed 0")
        self.stamp("journeys", 100)
        self.stamp("journeys-2", 200)
        self.assertIn("empty_runs", self.fired(self.lane()))

    def test_empty_then_pass_that_executed_nothing_still_fires(self):
        self.run_record("journeys", "RESULT: EMPTY (exit 0)  journeys  13s  sha=abc", "products: hit aa11\ntests: executed 0, skipped 3, failed 0")
        self.run_record("journeys-2", "RESULT: PASS (exit 0)  journeys-2  3m05s  sha=abc", "products: hit aa11\ntests: executed 0, skipped 3, failed 0")
        self.stamp("journeys", 100)
        self.stamp("journeys-2", 200)
        evidence = self.fired(self.lane())["empty_runs"]
        self.assertTrue(any(line.startswith("journeys: EMPTY") for line in evidence))

    def test_a_built_empty_is_cleared_by_a_later_hit_on_the_same_key(self):
        self.run_record("journeys", "RESULT: EMPTY (exit 0)  journeys  13s  sha=abc", "products: built aa11 in 247s\ntests: executed 0, skipped 3, failed 0")
        self.run_record("journeys-2", "RESULT: PASS (exit 0)  journeys-2  3m05s  sha=abc", "products: hit aa11, saved ~247s of compile\ntests: executed 5, skipped 0, failed 0")
        self.stamp("journeys", 100)
        self.stamp("journeys-2", 200)
        self.assertNotIn("empty_runs", self.fired(self.lane()))

    def stamp(self, label, when):
        os.utime(self.dir / "build" / "runs" / f"{label}.digest", (when, when))

    def test_the_credential_skip_case_digests_as_empty_and_fires(self):
        from importlib import import_module  # noqa: F401
        sys.path.insert(0, str(TOOLS))
        import log_digest
        log = "Test Case '-[LiveJourneyTests testA]' skipped (0.1 seconds).\n\t Executed 1 test, with 1 test skipped and 0 failures\nEMPTY: no tests ran (x)\n"
        head = log_digest.digest_text(log, exit_code=1, elapsed=13, label="uitest-live")
        self.write("build/runs/uitest-live.digest", head)
        self.assertIn("uitest-live: EMPTY", self.fired(self.lane())["empty_runs"][0])

    def test_a_deliberate_identical_rerun_skip_is_not_an_empty_run(self):
        self.run_record("uitest-again", "RESULT: PASS (exit 0)  uitest-again  0s")
        self.write("build/runs/uitest-again.log", "== iphone: already passed on this tree with this filter (build/testruns); --force reruns\n== nothing to run\n")
        self.assertNotIn("empty_runs", self.fired(self.lane()))

    def test_device_label_matches_whole_words_only(self):
        for label in ("recover", "discover", "purpose", "compose"):
            self.run_record(label, f"RESULT: PASS (exit 0)  {label}  0s")
        self.assertNotIn("empty_runs", self.fired(self.lane()))
        self.run_record("tt-cov", "RESULT: PASS (exit 0)  tt-cov  0s")
        self.assertIn("empty_runs", self.fired(self.lane()))

    def test_review_rounds_over_the_cap_come_from_the_branch_file(self):
        self.write("build/review/claude__lane-x.json", {"branch": "claude/lane-x", "round": 3, "verdict": "pass"})
        self.write("build/review/claude__other.json", {"branch": "claude/other", "round": 9, "verdict": "pass"})
        doc = self.lane()
        self.assertEqual(self.fired(doc)["review_rounds_over_cap"], ["3 review rounds (cap 2)"])
        self.assertEqual(doc["counts"]["review_verdicts"], 1)

    def test_a_marker_with_a_live_process_fires_stopped_with_live_children(self):
        self.write("build/runs/hold.running", {"pid": os.getpid(), "label": "hold", "started": 0, "cwd": "."})
        self.assertIn("stopped_with_live_children", self.fired(self.lane()))

    def test_over_budget_wall_clock_from_the_commits(self):
        self.commit("one", 1_000_000_100)
        self.commit("two", 1_000_000_100 + 150 * 60)
        self.assertIn("over_budget", self.fired(self.lane()))

    def test_branch_name_and_unknown_lane_are_accepted(self):
        self.commit("one", 1_000_000_100)
        doc = self.lane(name="claude/lane-x")
        self.assertEqual(doc["counts"]["branch"], "claude/lane-x")
        ghost = subprocess.run([sys.executable, str(TOOLS / "retro_digest.py"), "--lane", "no-such-lane", "--worktree",
                                str(self.dir / "missing")], capture_output=True, text=True)
        self.assertEqual(ghost.returncode, 2)
        self.assertFalse((self.dir / "missing").exists())

    def test_task_or_lane_is_required(self):
        with self.assertRaises(SystemExit):
            rd.main([])


if __name__ == "__main__":
    unittest.main()
