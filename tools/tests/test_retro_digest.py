"""``tools/retro_digest.py``: each trigger from a small fixture, and missing inputs. No network, no LLM."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("retro_digest", TOOLS / "retro_digest.py")
rd = importlib.util.module_from_spec(spec)
sys.modules["retro_digest"] = rd
spec.loader.exec_module(rd)


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
        self.assertEqual(doc["aar"]["why_different"], "")

    def test_blocked_from_status(self):
        status = self.write("status.json", {"state": "blocked", "blocked_reason": "needs a key", "summary": "s"})
        self.assertIn("needs a key", self.fired(self.run_digest("--status", str(status)))["blocked"][0])

    def test_runner_outcomes(self):
        self.assertIn("timeout", self.fired(self.run_digest("--outcome", "blocked:timeout")))
        self.assertIn("retry", self.fired(self.run_digest("--outcome", "retry", "--attempt", "1")))
        self.assertIn("worker_failed", self.fired(self.run_digest("--outcome", "blocked:worker_failed")))

    def test_review_rounds_over_cap(self):
        self.write("build/review/a.json", {"verdict": "changes", "round": 3})
        self.write("build/review/b.json", {"verdict": "pass", "round": 1})
        doc = self.run_digest()
        self.assertIn("review_rounds_over_cap", self.fired(doc))
        self.assertEqual(doc["counts"]["review_rounds"], 3)
        self.write("build/review/a.json", {"verdict": "pass", "round": 2})
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
        self.write("build/jev/gate.jsonl", json.dumps({"question": "design.user_visible@1", "value": False}) + "\n"
                   + "garbage\n" + json.dumps({"question": "decision.needs_owner@1", "value": False}) + "\n")
        doc = self.run_digest()
        self.assertEqual(doc["level"]["gate_hint"], "L0")
        self.assertIn("gate routed to L0", self.fired(doc)["routing_override"][0])

    def test_gate_hint_matching_level_is_quiet(self):
        self.write("build/tasks/R-1.json", {"id": "R-1", "level": "L0"})
        self.write("build/jev/gate.jsonl", json.dumps({"question": "design.user_visible@1", "value": "false"}) + "\n")
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


class ArchiveTests(Base):
    def test_archive_layout_writes_into_the_archive(self):
        self.write("tasks/R-1.json", {"id": "R-1", "level": "L1", "intake": "u", "brief": "b"})
        self.write("status.json", {"state": "blocked", "blocked_reason": "context: budget"})
        self.write("worker.log.tail", assistant("I'll wait for the build.") + "\n" + result())
        self.assertEqual(rd.main(["--task", "R-1", "--archive", str(self.dir)]), 0)
        doc = json.loads((self.dir / "retro" / "R-1.json").read_text())
        self.assertEqual(set(self.fired(doc)), {"blocked", "waiting_ending"})

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
        self.write("build/runs/uitest-1.digest", "RESULT: PASS (exit 0)  uitest-1  34m10s\n")
        self.write("build/runs/uitest-2.digest", "RESULT: FAIL (exit 1)  uitest-2  34m02s\n")
        self.write("build/runs/journeys.digest", "RESULT: EMPTY (exit 0)  journeys  13s\ntests: executed 0, skipped 3, failed 0\n")
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
