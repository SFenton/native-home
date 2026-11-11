"""``tools/jev_gate.py``. No network: ``ask_question`` is faked."""

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]


def load_tool(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


gate = load_tool("jev_gate")


class Fake:
    """Stands in for jev_ask.ask_question: p per question id, None (or an absent id) for unavailable."""

    def __init__(self, visible, owner, target=None, **more):
        self.p = {"design.user_visible": visible, "decision.needs_owner": owner, "design.target_decided": target,
                  **{k.replace("_", ".", 1): v for k, v in more.items()}}
        self.calls = []

    def __call__(self, question, context, **kw):
        self.calls.append((question.id, context, kw))
        p = self.p[question.id]
        if p is None:
            return None
        return gate.jev.Decision(question, p >= question.yes_above, max(p, 1 - p), {"true": p, "false": 1 - p})


def without_target(real):
    """The real questions minus design.target_decided, simulating its file being absent."""
    def load():
        questions = dict(real())
        questions.pop("design.target_decided", None)
        return questions
    return load


class GateTests(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(gate, "route", return_value="session")  # ambient FENTON_HEADLESS, HASS_TRIAGE_ISSUE and the registry must not leak in
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_gate(self, visible, owner, *extra, target=None, target_file=False):
        """target_file=True keeps the repo's design.target_decided question; otherwise it is simulated absent."""
        fake = Fake(visible, owner, target)
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict("os.environ", {"JEV_HOME": tmp + "/jev"}):
            self.log = Path(tmp) / "jev" / "gate.jsonl"
            plan = Path(tmp) / "plan.md"
            plan.write_text("the plan")
            out, err = io.StringIO(), io.StringIO()
            real = gate.jev.load_questions
            with mock.patch.object(gate.jev, "ask_question", fake), \
                    mock.patch.object(gate.jev, "load_questions", real if target_file else without_target(real)), \
                    contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = gate.main(["--plan-file", str(plan), *extra])
            self.records = [json.loads(l) for l in self.log.read_text().splitlines()] if self.log.exists() else []
        text = out.getvalue()
        self.gate_lines = [l for l in text.splitlines() if l.startswith(("Jev gate", "gate:"))]
        text = "".join(l + "\n" for l in text.splitlines() if not l.startswith(("Jev gate", "gate:")))
        return code, text, fake

    GATE_ONLY = ("Jev gate", "gate:")

    def test_every_answer_is_logged_without_the_plan_text(self):
        self.run_gate(0.82, 0.3, "--subject", "R-9")
        self.assertEqual([(r["question"], r["subject"], r["value"], r["p"], r["printed"]) for r in self.records],
                         [(self.records[0]["question"], "R-9", True, 0.82, True),
                          (self.records[1]["question"], "R-9", False, 0.3, False)])
        self.assertTrue(self.records[0]["question"].startswith("design.user_visible@"))
        self.assertTrue(self.records[1]["question"].startswith("decision.needs_owner@"))
        self.assertIn("at", self.records[0])
        self.assertNotIn("the plan", json.dumps(self.records))

    def test_unavailable_logs_nothing(self):
        self.run_gate(None, None)
        self.assertEqual(self.records, [])

    def test_yes_prints_both_raise_lines_then_the_route_hint(self):
        code, out, _ = self.run_gate(0.82, 0.91)
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines(), ["Jev: reads as visible (p=0.82): send it to the Designer",
                                            "Jev: the owner's pick looks needed (p=0.91): L2",
                                            "Jev: no route hint (unsure)"])  # no target file yet

    def test_only_the_yes_line_prints(self):
        self.assertEqual(self.run_gate(0.7, 0.1)[1].splitlines()[0],
                         "Jev: reads as visible (p=0.70): send it to the Designer")
        self.assertEqual(self.run_gate(0.1, 0.6)[1].splitlines()[0],
                         "Jev: the owner's pick looks needed (p=0.60): L2")

    def route(self, visible, owner, target=None):
        _, out, _ = self.run_gate(visible, owner, target=target, target_file=True)
        return out.splitlines()[-1]

    def test_route_table_rows(self):
        hint = "Jev route (hint, the orchestrator decides): "
        rows = [
            ((0.1, 0.1, None), "Coder (L0)"),
            ((0.1, 0.9, None), "decision note, then Coder (L2 policy)"),
            ((0.9, 0.1, 0.9), "Designer spec within the existing pattern, then Coder (L1)"),
            ((0.9, 0.9, 0.9), "decision note for the remaining choice plus a Designer spec"),
            ((0.9, 0.1, 0.1), "Designer options and mockups (L2 design)"),
            ((0.9, 0.9, 0.1), "Designer options and mockups (L2 design)"),
        ]
        for (visible, owner, target), expected in rows:
            self.assertEqual(self.route(visible, owner, target), hint + expected, (visible, owner, target))

    def test_unsure_prints_no_route_hint(self):
        unsure = "Jev: no route hint (unsure)"
        for args in ((0.45, 0.1, None),   # visible in its band
                     (0.1, 0.4, None),    # pick in its band
                     (0.9, 0.1, 0.4),     # visible, target in its band
                     (0.9, 0.1, None)):   # visible, target unavailable
            self.assertEqual(self.route(*args), unsure, args)

    def test_target_decided_only_for_a_visible_plan(self):
        _, _, fake = self.run_gate(0.1, 0.1, target=0.9, target_file=True)
        self.assertNotIn("design.target_decided", [c[0] for c in fake.calls])
        _, _, fake = self.run_gate(0.45, 0.1, target=0.9, target_file=True)
        self.assertNotIn("design.target_decided", [c[0] for c in fake.calls])
        _, _, fake = self.run_gate(0.9, 0.1, target=0.9, target_file=True)
        self.assertEqual([c[0] for c in fake.calls][2], "design.target_decided")
        self.assertEqual(fake.calls[2][1], {"plan": "the plan"})
        self.assertEqual(len(self.records), 3)  # the target answer is logged like the others

    def test_missing_question_file_is_skipped_silently(self):
        _, out, fake = self.run_gate(0.9, 0.1)
        self.assertNotIn("design.target_decided", [c[0] for c in fake.calls])
        self.assertEqual(out.splitlines()[-1], "Jev: no route hint (unsure)")

    def test_unavailable_prints_nothing_and_exits_0(self):
        self.assertEqual(self.run_gate(None, None)[:2], (0, ""))

    def test_errors_print_no_hints_only_the_failsafe_gate_and_exit_0(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = Path(tmp) / "plan.md"
            plan.write_text("x")
            out = io.StringIO()
            with mock.patch.object(gate.jev, "ask_question", side_effect=RuntimeError("boom")), \
                    contextlib.redirect_stdout(out):
                code = gate.main(["--plan-file", str(plan)])
            self.assertEqual(code, 0)
            self.assertEqual(out.getvalue().splitlines()[-1], "gate: park basis=agent answer=unavailable route=session")

    def test_missing_or_empty_plan_file_is_a_usage_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp) / "empty.md"
            empty.write_text("  \n")
            for path in (Path(tmp) / "missing.md", empty):
                out, err = io.StringIO(), io.StringIO()
                with mock.patch.object(gate.jev, "ask_question", side_effect=AssertionError("asked")), \
                        contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    code = gate.main(["--plan-file", str(path)])
                self.assertEqual((code, out.getvalue(), err.getvalue()),
                                 (2, "", f"jev_gate: cannot read {path}\n"))

    def test_state_sent(self):
        _, _, fake = self.run_gate(0.9, 0.9, "--title", "T", "--subject", "R-1")
        (qa, ctx_a, kw_a), (qb, ctx_b, kw_b) = fake.calls[:2]
        self.assertEqual((qa, ctx_a), ("design.user_visible", {"title": "T", "body": "the plan", "files": ""}))
        self.assertEqual((qb, ctx_b), ("decision.needs_owner", {"plan": "the plan"}))
        self.assertEqual((kw_a["subject"], kw_b["subject"]), ("R-1", "R-1"))


class AppUIGateTests(unittest.TestCase):
    """The app-UI gate (owner, 2026-11-03): matches_request for request-driven work, app_wide for agent-initiated work."""

    def setUp(self):
        patcher = mock.patch.object(gate, "route", return_value="session")  # the route itself is pinned in RouteTests
        patcher.start()
        self.addCleanup(patcher.stop)

    REQUEST = "Owner's request: make the chips bigger\n\nPlan: chips grow to 44 pt."
    AGENT = "Plan: tidy the chip spacing."

    def run_it(self, plan, answers, present=("design.matches_request", "design.app_wide")):
        """answers: id -> P(yes) or None (unavailable). A missing question file is simulated by leaving the id out of present."""
        fake = Fake(0.9, 0.1, **{k.replace(".", "_", 1): v for k, v in answers.items()})
        base = json.loads((TOOLS.parent / "contracts/jev/questions/design.user_visible.json").read_text())
        questions = {q: gate.jev.Question({**base, "id": q}) for q in present}
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict("os.environ", {"JEV_HOME": tmp + "/jev"}):
            real = gate.jev.load_questions
            def load():
                merged = {k: v for k, v in real().items() if k not in ("design.matches_request", "design.app_wide")}
                return {**merged, **questions}
            with mock.patch.object(gate.jev, "ask_question", fake), mock.patch.object(gate.jev, "load_questions", load):
                return gate.all_lines(plan), fake

    def last(self, plan, answers, **kw):
        lines, fake = self.run_it(plan, answers, **kw)
        return lines[-1], [c[0] for c in fake.calls]

    def test_the_request_section_is_found(self):
        self.assertEqual(gate.owner_request(self.REQUEST), "make the chips bigger")
        self.assertEqual(gate.owner_request("Owner's request:\nline one\nline two\n\nPlan"), "line one\nline two")
        self.assertIsNone(gate.owner_request(self.AGENT))

    def test_request_driven_yes_is_autonomous(self):
        last, asked = self.last(self.REQUEST, {"design.matches_request": 0.9})
        self.assertEqual(last, "gate: autonomous basis=request answer=yes")
        self.assertIn("design.matches_request", asked)
        self.assertNotIn("design.app_wide", asked)

    def test_request_driven_no_or_unsure_or_unavailable_parks(self):
        for p, word in ((0.1, "no"), (0.45, "unsure"), (None, "unavailable")):
            last, _ = self.last(self.REQUEST, {"design.matches_request": p})
            self.assertEqual(last, f"gate: park basis=request answer={word} route=session", p)

    def test_agent_initiated_no_is_autonomous_yes_or_unsure_parks(self):
        self.assertEqual(self.last(self.AGENT, {"design.app_wide": 0.1})[0], "gate: autonomous basis=agent answer=no")
        for p, word in ((0.9, "yes"), (0.45, "unsure"), (None, "unavailable")):
            self.assertEqual(self.last(self.AGENT, {"design.app_wide": p})[0], f"gate: park basis=agent answer={word} route=session", p)

    def test_the_request_question_is_sent_the_owners_words_and_the_plan(self):
        _, fake = self.run_it(self.REQUEST, {"design.matches_request": 0.9})
        ctx = [c[1] for c in fake.calls if c[0] == "design.matches_request"][0]
        self.assertEqual(ctx, {"pair": f"Request: make the chips bigger\nChange: {self.REQUEST}"})
        _, fake = self.run_it(self.AGENT, {"design.app_wide": 0.1})
        self.assertEqual([c[1] for c in fake.calls if c[0] == "design.app_wide"][0], {"change": self.AGENT})

    def test_a_missing_question_file_parks_without_asking(self):
        for plan, basis in ((self.REQUEST, "request"), (self.AGENT, "agent")):
            last, asked = self.last(plan, {}, present=())
            self.assertEqual(last, f"gate: park basis={basis} answer=unavailable route=session")
            self.assertNotIn("design.matches_request", asked)
            self.assertNotIn("design.app_wide", asked)

    def test_an_invisible_plan_has_no_gate(self):
        fake = Fake(0.1, 0.1)
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict("os.environ", {"JEV_HOME": tmp + "/jev"}), \
                mock.patch.object(gate.jev, "ask_question", fake):
            lines = gate.all_lines(self.AGENT)
        self.assertFalse([l for l in lines if "gate" in l.lower()])

    def test_jev_down_entirely_still_prints_the_failsafe(self):
        with mock.patch.object(gate.jev, "load_questions", side_effect=RuntimeError("x")):
            self.assertEqual(gate.all_lines(self.AGENT)[-1], "gate: park basis=agent answer=unavailable route=session")

    def test_an_exception_in_the_gate_still_prints_gate_park(self):
        with tempfile.TemporaryDirectory() as d:
            plan = Path(d) / "plan.md"
            for text, basis in ((self.AGENT, "agent"), ("Owner's request: bigger chips\n\n" + self.AGENT, "request")):
                plan.write_text(text)
                out = io.StringIO()
                with mock.patch.object(gate, "all_lines", side_effect=RuntimeError("boom")), contextlib.redirect_stdout(out):
                    self.assertEqual(gate.main(["--plan-file", str(plan)]), 0)
                self.assertEqual(out.getvalue().strip(), f"gate: park basis={basis} answer=unavailable route=session")


class RouteTests(unittest.TestCase):
    """``route=session|pr`` on a park line: a headless session asks on the pull request, an interactive one in the session."""

    def route(self, markers=None, registered=False):
        with mock.patch.object(gate, "registered_session", return_value=registered):
            return gate.route(markers or {})

    def gate_line(self, answer, markers, registered=False):
        base = json.loads((TOOLS.parent / "contracts/jev/questions/design.user_visible.json").read_text())
        questions = {"design.app_wide": gate.jev.Question({**base, "id": "design.app_wide"})}
        real = gate.route
        with mock.patch.object(gate, "_safe_ask", return_value=(answer, 0.5)), \
                mock.patch.object(gate, "registered_session", return_value=registered), \
                mock.patch.object(gate, "route", lambda: real(markers)):
            return gate.gate("Change chips everywhere.", "t", questions)

    def test_interactive_is_session(self):
        self.assertEqual(self.route(), "session")
        self.assertEqual(self.route({"FENTON_HEADLESS": "0"}), "session")

    def test_each_headless_marker_is_pr(self):
        self.assertEqual(self.route({"FENTON_HEADLESS": "1"}), "pr")
        self.assertEqual(self.route({"HASS_TRIAGE_ISSUE": "12"}), "pr")
        self.assertEqual(self.route(registered=True), "pr")

    def test_a_failed_registry_lookup_is_pr(self):
        broken = mock.Mock(registered=mock.Mock(side_effect=OSError("x")))
        with mock.patch.dict(sys.modules, {"triage_session": broken}):
            self.assertTrue(gate.registered_session())

    def test_park_carries_the_route_and_the_old_fields_still_parse(self):
        for markers, registered, route in (({}, False, "session"), ({"FENTON_HEADLESS": "1"}, False, "pr"),
                                           ({"HASS_TRIAGE_ISSUE": "9"}, False, "pr"), ({}, True, "pr")):
            outcome, lines = self.gate_line(True, markers, registered)
            self.assertEqual(outcome, "park")
            self.assertEqual(lines[-1], f"gate: park basis=agent answer=yes route={route}")
            fields = dict(part.split("=") for part in lines[-1].split()[2:])
            self.assertEqual((fields["basis"], fields["answer"]), ("agent", "yes"))

    def test_autonomous_has_no_route(self):
        outcome, lines = self.gate_line(False, {"FENTON_HEADLESS": "1"})
        self.assertEqual((outcome, lines[-1]), ("autonomous", "gate: autonomous basis=agent answer=no"))


if __name__ == "__main__":
    unittest.main()
