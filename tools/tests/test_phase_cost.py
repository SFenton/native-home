"""Phase cost report (``tools/phase_cost.py``) over synthetic transcripts."""

import json
import os
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import phase_cost  # noqa: E402

SECRET = "ghp_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
OPUS = "claude-opus-5"


def usage(write):
    return {"input_tokens": 2, "cache_read_input_tokens": 0, "cache_creation_input_tokens": write, "output_tokens": 10,
            "cache_creation": {"ephemeral_5m_input_tokens": write, "ephemeral_1h_input_tokens": 0}}


def turn(mid, time, write, *blocks):
    return json.dumps({"type": "assistant", "timestamp": time, "uuid": mid,
                       "message": {"id": mid, "model": OPUS, "usage": usage(write), "content": list(blocks) or [{"type": "text", "text": "x"}]}})


def agent(kind, prompt, tool_id="tu1"):
    return {"type": "tool_use", "id": tool_id, "name": "Agent", "input": {"subagent_type": kind, "prompt": prompt}}


def bash(command):
    return {"type": "tool_use", "id": "b", "name": "Bash", "input": {"command": command}}


def agent_result(tool_id, agent_id, **extra):
    return json.dumps({"type": "user", "toolUseResult": dict({"agentId": agent_id}, **extra),
                       "message": {"content": [{"type": "tool_result", "tool_use_id": tool_id, "content": "ok"}]}})


def transcript(directory, subagent_write=0):
    path = Path(directory) / "session.jsonl"
    lines = [turn("a", "2026-11-05T10:00:00Z", 1000),
             turn("b", "2026-11-05T10:05:00Z", 1000, agent("designer", f"Pick a look. token={SECRET} then wait")),
             agent_result("tu1", "ag1"),
             turn("c", "2026-11-05T10:50:00Z", 1000, bash("tools/ship.sh 'x'"))]
    path.write_text("\n".join(lines) + "\n")
    if subagent_write:
        sub = Path(directory) / "session" / "subagents" / "agent-ag1.jsonl"
        sub.parent.mkdir(parents=True)
        sub.write_text(turn("s1", "2026-11-05T10:06:00Z", subagent_write) + "\n")
    return path


class FakeQuestion:
    def __init__(self, qid, kind, per_item=False):
        self.id = qid
        self.data = {"type": kind, "per_item": per_item, "state": {"fields": ["plan"]}}


class FakeDecision:
    def __init__(self, qid, kind, value, accepted=True, per_item=False):
        self.question, self.value, self.accepted = FakeQuestion(qid, kind, per_item), value, accepted


class PhaseCostTests(unittest.TestCase):
    def report(self, **kwargs):
        with TemporaryDirectory() as directory:
            path = transcript(directory, subagent_write=6_000_000)
            report = phase_cost.run(path, "t1", Path(directory) / "out", **kwargs)
            written = json.loads((Path(directory) / "out" / "t1.phases.json").read_text())
        self.assertEqual(report, written)
        return report

    def test_subagent_cost_makes_the_spawn_phase_flag(self):
        phases = self.report()["phases"]
        self.assertEqual([p["kind"] for p in phases], ["work", "design_loop", "ship"])
        self.assertEqual([p["flagged"] for p in phases], [False, True, False])
        self.assertEqual(phases[1]["subagent_source"], "transcript")
        self.assertGreater(phases[1]["subagent_cost"], phase_cost.COST_FLOOR)
        self.assertEqual(phases[1]["minutes"], 45.0)

    def test_without_the_subagent_nothing_flags(self):
        with TemporaryDirectory() as directory:
            path = transcript(directory)
            phases = phase_cost.run(path, "t2", Path(directory) / "out")["phases"]
        self.assertFalse(any(p["flagged"] for p in phases))

    def test_result_usage_is_the_fallback(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "s.jsonl"
            path.write_text("\n".join([turn("a", "2026-11-05T10:00:00Z", 10, agent("coder", "do it")),
                                       agent_result("tu1", "none", usage=usage(6_000_000), resolvedModel=OPUS),
                                       turn("b", "2026-11-05T10:10:00Z", 10, bash("tools/ship.sh"))]) + "\n")
            phases = phase_cost.run(path, "t3", Path(directory) / "out")["phases"]
        self.assertEqual(phases[0]["subagent_source"], "result")
        self.assertTrue(phases[0]["flagged"])

    def test_floor_is_ten_million(self):
        self.assertEqual(phase_cost.COST_FLOOR, 10_000_000.0)
        self.assertFalse(hasattr(phase_cost, "SHARE_LIMIT"))

    def test_a_small_share_over_the_floor_still_flags(self):
        # four large phases: each is under 35 percent of the session, each is over the floor
        turns = [{"model": OPUS, "time": f"2026-11-05T10:0{i}:00Z", "usage": usage(3_000_000),
                  "blocks": [agent("coder", "a", f"t{i}")]} for i in range(4)]
        phases = phase_cost.split(turns)
        self.assertTrue(all(p["share"] < 0.35 for p in phases))
        self.assertTrue(all(p["flagged"] for p in phases))

    def test_under_the_floor_never_flags_whatever_the_share(self):
        turns = [{"model": OPUS, "time": "2026-11-05T10:00:00Z", "usage": usage(100), "blocks": [agent("coder", "a")]},
                 {"model": OPUS, "time": "2026-11-05T10:01:00Z", "usage": usage(10), "blocks": [bash("tools/ship.sh")]}]
        self.assertFalse(any(p["flagged"] for p in phase_cost.split(turns)))

    def test_single_phase_session_never_flags(self):
        turns = [{"model": OPUS, "time": "2026-11-05T10:00:00Z", "blocks": [], "usage": usage(6_000_000)}]
        phases = phase_cost.split(turns)
        self.assertEqual(len(phases), 1)
        self.assertEqual(phases[0]["share"], 1.0)
        self.assertFalse(phases[0]["flagged"])

    def test_kind_without_a_row_is_no_candidates_not_a_flag(self):
        turns = [{"model": OPUS, "time": "2026-11-05T10:00:00Z", "blocks": [agent("", "x")], "usage": usage(6_000_000)},
                 {"model": OPUS, "time": "2026-11-05T10:01:00Z", "blocks": [bash("tools/ship.sh")], "usage": usage(10)}]
        first = phase_cost.split(turns)[0]
        self.assertEqual(first["kind"], "general-purpose")
        self.assertTrue(first["no_candidates"])
        self.assertFalse(first["flagged"])

    def test_every_candidate_kind_has_questions(self):
        self.assertEqual(phase_cost.CANDIDATES["design_loop"], ["design.target_decided", "decision.needs_owner"])
        self.assertEqual(phase_cost.CANDIDATES["coder_rework"],
                         ["review.finding_family", "code.custom_machinery", "context.patterns"])
        for kind in ("coder", "reviewer", "researcher", "verifier"):
            self.assertTrue(phase_cost.CANDIDATES[kind], kind)
        self.assertEqual(phase_cost.kind_of("coder", ["reviewer"]), "coder_rework")
        self.assertEqual(phase_cost.kind_of("coder", ["work"]), "coder")

    def test_parallel_spawns_are_separate_phases(self):
        turns = [{"model": OPUS, "time": "2026-11-05T10:00:00Z", "usage": usage(10),
                  "blocks": [agent("coder", "a", "t1"), agent("reviewer", "b", "t2")]}]
        self.assertEqual([p["kind"] for p in phase_cost.split(turns)], ["coder", "reviewer"])

    def test_snippet_is_redacted(self):
        snippet = self.report()["phases"][1]["snippet"]
        self.assertNotIn(SECRET, snippet)
        self.assertIn("Pick a look", snippet)


class MarkerTests(unittest.TestCase):
    def test_executions_are_markers(self):
        for command, kind in (("tools/ship.sh 'x'", "ship"), ("cd a && python3 tools/tasks.py flip T a1 --evidence e", "flip"),
                              ("python3 tools/review/record.py -", "review_record"), ("FOO=1 python3 tools/jev_gate.py --x", "gate"),
                              ("bash tools/ship.sh", "ship"),
                              ("python3 tools/bg_run.py ship -- tools/ship.sh --note x", "ship"),
                              ("python3 tools/devcap.py run --sim U1 --max-wait 1200 -- python3 tools/jev_gate.py", "gate"),
                              ("tools/bg_run.py rec --timeout 60 -- python3 tools/review/record.py -", "review_record")):
            self.assertEqual(phase_cost.command_kind(command), kind, command)

    def test_reading_a_script_is_not_a_marker(self):
        for command in ("sed -n 1,40p tools/ship.sh", "grep x tools/" + "pr_land.py", "cat tools/review/record.py",
                        "python3 tools/tasks.py list", "echo tools/ship.sh", "git diff -- tools/jev_gate.py",
                        "python3 tools/bg_run.py t -- swift test", "python3 tools/devcap.py run --sim U -- sed -n 1p tools/ship.sh",
                        "tools/bg_run.py t"):
            self.assertIsNone(phase_cost.command_kind(command), command)

    def test_a_read_does_not_open_a_phase(self):
        turns = [{"model": OPUS, "time": "2026-11-05T10:00:00Z", "usage": usage(10), "blocks": [bash("sed -n 1,5p tools/ship.sh")]}]
        self.assertEqual([p["kind"] for p in phase_cost.split(turns)], ["work"])


class VerdictTests(unittest.TestCase):
    def test_boolean(self):
        self.assertEqual(phase_cost.verdict(FakeDecision("a", "noul", True)), "yes")
        self.assertEqual(phase_cost.verdict(FakeDecision("a", "noul", False)), "no")
        self.assertEqual(phase_cost.verdict(FakeDecision("a", "noul", None, accepted=False)), "unsure")

    def test_set(self):
        self.assertEqual(phase_cost.verdict(FakeDecision("a", "noul-set", ["x"])), "yes")
        self.assertEqual(phase_cost.verdict(FakeDecision("a", "noul-set", [])), "no")

    def test_choice(self):
        fires = FakeDecision("review.finding_family", "choice", "pattern_rule")
        quiet = FakeDecision("review.finding_family", "choice", "correctness")
        self.assertEqual(phase_cost.verdict(fires), "yes")
        self.assertEqual(phase_cost.verdict(quiet), "no")
        self.assertEqual(phase_cost.verdict(quiet, happened="correctness"), "same")
        self.assertEqual(phase_cost.verdict(fires, happened="correctness"), "differs")

    def test_per_item_is_unsure(self):
        self.assertEqual(phase_cost.verdict(FakeDecision("t", "noul", True, per_item=True)), "unsure")


class ReplayTests(unittest.TestCase):
    def run_replay(self, **kwargs):
        with TemporaryDirectory() as directory:
            path = transcript(directory, subagent_write=6_000_000)
            return phase_cost.run(path, "t1", Path(directory) / "out", do_replay=True, **kwargs)["phases"][1]["replay"]

    def test_no_key_reports_not_run(self):
        with mock.patch.object(phase_cost, "jev", return_value=({}, None)):
            self.assertEqual(set(self.run_replay().values()), {"not run"})

    def test_replay_sends_redacted_text_and_reports_by_type(self):
        sent = []
        questions = {"design.target_decided": FakeQuestion("design.target_decided", "noul"),
                     "decision.needs_owner": FakeQuestion("decision.needs_owner", "noul")}
        answers = iter([FakeDecision("design.target_decided", "noul", True),
                        FakeDecision("decision.needs_owner", "noul", None, accepted=False)])

        def ask(question, context, subject):
            sent.append(context["plan"])
            return next(answers)

        replay = self.run_replay(questions=questions, ask=ask)
        self.assertEqual(replay, {"design.target_decided": "yes", "decision.needs_owner": "unsure"})
        self.assertTrue(all(SECRET not in text for text in sent))


class SelectionTests(unittest.TestCase):
    def make(self, root, name, first, later="", age=100):
        directory = root / "-Users-x-repos-Fenton-HASS-Native"
        directory.mkdir(exist_ok=True)
        path = directory / f"{name}.jsonl"
        lines = [json.dumps({"type": "user", "message": {"content": first}}),
                 json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": later}]}})]
        path.write_text("\n".join(lines) + "\n")
        stamp = phase_cost.STARTED - age
        os.utime(path, (stamp, stamp))
        return path

    def test_calling_session_is_excluded_by_id_and_by_recent_write(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            built = self.make(root, "builder", "implement T-9", age=500)
            self.make(root, "caller", "run phase_cost --task T-9", age=10)
            self.make(root, "writing-now", "T-9", age=-5)
            found = phase_cost.find_task_session(root, ["*Fenton-HASS-Native*"], "T-9", exclude=["caller"])
        self.assertEqual(found, built)

    def test_first_user_turn_beats_a_later_mention(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            owner = self.make(root, "owner", "work on T-9", age=900)
            self.make(root, "chatter", "something else", later="T-9 was discussed", age=50)
            found = phase_cost.find_task_session(root, ["*Fenton-HASS-Native*"], "T-9")
        self.assertEqual(found, owner)

    def test_default_globs_cover_the_runner_sessions(self):
        self.assertIn("-Users-stephenfenton-hass-agents-worktrees-*", phase_cost.DEFAULT_PROJECTS)
        with TemporaryDirectory() as directory:
            root = Path(directory)
            runner = root / "-Users-stephenfenton-hass-agents-worktrees-3"
            runner.mkdir()
            path = runner / "r.jsonl"
            path.write_text(json.dumps({"type": "user", "message": {"content": "issue T-9"}}) + "\n")
            os.utime(path, (phase_cost.STARTED - 10, phase_cost.STARTED - 10))
            found = phase_cost.find_task_session(root, phase_cost.DEFAULT_PROJECTS, "T-9")
        self.assertEqual(found, path)

    def test_missing_transcript_exits_one(self):
        self.assertEqual(phase_cost.main(["--session", "/nonexistent/x.jsonl"]), 1)


if __name__ == "__main__":
    unittest.main()
