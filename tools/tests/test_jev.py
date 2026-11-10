"""``tools/jev_ask.py``, ``tools/jev_hints.py`` and ``tools/jev_measure.py``. No network: every call uses a fake transport."""

import contextlib
import importlib.util
import io
import json
import os
import sys
import unittest
import urllib.error
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent


def load_tool(name):
    # By path: putting tools/ on sys.path would let tools/test_digest.py shadow tools/tests/test_digest.py.
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


jev = load_tool("jev_ask")
hints = load_tool("jev_hints")
measure = load_tool("jev_measure")
guard = load_tool("pattern_guard")


class Isolated(unittest.TestCase):
    """Every test gets its own cache and no key from the environment."""

    def setUp(self):
        self.tmp = TemporaryDirectory()
        patcher = mock.patch.dict(os.environ, {"JEV_HOME": self.tmp.name, "TYPESAFE_API_KEY": "",
                                               "JEV_KEY_FILE": str(Path(self.tmp.name) / "no-such.key")})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)
        self.calls = []

    def transport(self, answers_for):
        """A fake transport; `answers_for(body)` returns the `answers` object."""
        def send(body, key, timeout):
            self.calls.append((body, key))
            return {"model": "jev-test", "answers": answers_for(body), "usage": {"input_tokens": 10}}
        return send


def noul(p):
    return {"type": "noul", "noul": p}


class ClientTests(Isolated):
    def test_parse_answers(self):
        a = jev.parse_answer(noul(0.2))
        self.assertEqual((a.value, round(a.confidence, 2)), (False, 0.8))
        c = jev.parse_answer({"type": "choice", "choice": "a", "confidence": 0.9, "probabilities": {"a": 0.95, "b": 0.05}})
        self.assertEqual((c.value, c.confidence), ("a", 0.9))
        s = jev.parse_answer({"type": "score", "score": 1.2, "confidence": 0.7, "probabilities": {"0": 0.1, "1": 0.8, "2": 0.1}})
        self.assertEqual((s.value, s.score), (1, 1.2))
        with self.assertRaises(ValueError):
            jev.parse_answer({"type": "wat"})

    def test_no_key_means_none_and_no_call(self):
        self.assertIsNone(jev.ask({"q": {"type": "noul", "instructions": "x"}}, "state"))
        self.assertEqual(self.calls, [])

    def test_ask_caches_by_question_and_state_and_logs_without_state(self):
        send = self.transport(lambda body: {"q": noul(0.9)})
        questions = {"q": {"type": "noul", "instructions": "x"}}
        with mock.patch.dict(os.environ, {"TYPESAFE_API_KEY": "secret-key"}):
            first = jev.ask(questions, {"title": "private text"}, tag="t@1", transport=send)
            second = jev.ask(questions, {"title": "private text"}, tag="t@1", transport=send)
        self.assertTrue(first["q"].value and second["q"].value)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0][0]["model"], jev.MODEL)
        log = (Path(self.tmp.name) / "calls.jsonl").read_text()
        self.assertIn('"tag": "t@1"', log)
        self.assertNotIn("private text", log)
        self.assertNotIn("secret-key", log)

    def test_http_errors_retry_once_then_give_up(self):
        attempts = []

        def failing(body, key, timeout):
            attempts.append(1)
            raise urllib.error.HTTPError("u", 503, "boom", {}, None)
        with mock.patch.dict(os.environ, {"TYPESAFE_API_KEY": "k"}), mock.patch.object(jev.time, "sleep"):
            self.assertIsNone(jev.ask({"q": {"type": "noul", "instructions": "x"}}, "s", transport=failing, use_cache=False))
        self.assertEqual(len(attempts), 2)

    def test_client_errors_do_not_retry_and_bad_answers_are_none(self):
        attempts = []

        def unauthorized(body, key, timeout):
            attempts.append(1)
            raise urllib.error.HTTPError("u", 401, "no", {}, None)
        with mock.patch.dict(os.environ, {"TYPESAFE_API_KEY": "k"}):
            q = {"q": {"type": "noul", "instructions": "x"}}
            self.assertIsNone(jev.ask(q, "s", transport=unauthorized, use_cache=False))
            self.assertEqual(len(attempts), 1)
            self.assertIsNone(jev.ask(q, "s2", transport=self.transport(lambda b: {}), use_cache=False))

    def test_http_exceptions_are_unavailable_not_a_crash(self):
        import http.client

        def dropped(body, key, timeout):
            raise http.client.RemoteDisconnected("closed")
        with mock.patch.dict(os.environ, {"TYPESAFE_API_KEY": "k"}), mock.patch.object(jev.time, "sleep"):
            self.assertIsNone(jev.ask({"q": {"type": "noul", "instructions": "x"}}, "s", transport=dropped, use_cache=False))
            out = io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
                code = jev.main(["yesno", "Is it?", "--state", "x", "--no-cache"], transport=dropped)
        self.assertEqual(code, 3)

    def test_key_file_is_used_only_when_owner_only(self):
        keyfile = Path(self.tmp.name) / "typesafe.key"
        keyfile.write_text("file-key\n")
        with mock.patch.dict(os.environ, {"JEV_KEY_FILE": str(keyfile)}):
            keyfile.chmod(0o644)
            self.assertEqual(jev.api_key(), "")
            keyfile.chmod(0o600)
            self.assertEqual(jev.api_key(), "file-key")

    def test_key_file_owned_by_someone_else_is_ignored(self):
        keyfile = Path(self.tmp.name) / "typesafe.key"
        keyfile.write_text("file-key\n")
        keyfile.chmod(0o600)
        real = keyfile.stat()
        other = mock.Mock(st_mode=real.st_mode, st_uid=os.getuid() + 1)
        env = {"JEV_KEY_FILE": str(keyfile), "TYPESAFE_API_KEY": "env-key"}
        with mock.patch.dict(os.environ, env), mock.patch.object(Path, "stat", return_value=other):
            self.assertEqual(jev.api_key(), "env-key")

    def test_key_file_wins_over_environment(self):
        keyfile = Path(self.tmp.name) / "typesafe.key"
        keyfile.write_text("file-key\n")
        keyfile.chmod(0o600)
        with mock.patch.dict(os.environ, {"JEV_KEY_FILE": str(keyfile), "TYPESAFE_API_KEY": "env-key"}):
            self.assertEqual(jev.api_key(), "file-key")

    def test_environment_is_the_fallback(self):
        keyfile = Path(self.tmp.name) / "typesafe.key"
        env = {"JEV_KEY_FILE": str(keyfile), "TYPESAFE_API_KEY": "env-key"}
        with mock.patch.dict(os.environ, env):
            self.assertEqual(jev.api_key(), "env-key")  # file absent
            keyfile.write_text("  \n")
            keyfile.chmod(0o600)
            self.assertEqual(jev.api_key(), "env-key")  # file empty
            keyfile.write_text("file-key\n")
            keyfile.chmod(0o644)
            self.assertEqual(jev.api_key(), "env-key")  # file too open
        with mock.patch.dict(os.environ, {"JEV_KEY_FILE": str(keyfile), "TYPESAFE_API_KEY": ""}):
            keyfile.write_text("")
            keyfile.chmod(0o600)
            self.assertEqual(jev.api_key(), "")  # neither

    def test_model_can_be_overridden(self):
        with mock.patch.dict(os.environ, {"JEV_MODEL": "jev-preview"}):
            self.assertEqual(jev.model(), "jev-preview")
        self.assertEqual(jev.model(), jev.MODEL)


class QuestionTests(Isolated):
    def test_registered_questions_are_valid_and_synced(self):
        questions = jev.load_questions()
        self.assertLessEqual({"context.patterns", "context.precedents", "route.complexity", "check.tests",
                              "review.finding_family"}, set(questions))
        self.assertEqual(jev.sync(check=True, only=["context.patterns"]), 0)

    def test_context_patterns_has_one_criterion_per_registry_pattern(self):
        registry = json.loads((REPO / "contracts/patterns.json").read_text())
        criteria = jev.load_questions()["context.patterns"].data["criteria"]
        self.assertEqual(set(criteria), {p["id"] for p in registry["patterns"]})
        self.assertIn("StatusPill", criteria["status-pill"])

    def test_validate_catches_problems(self):
        good = {"id": "x", "version": 1, "type": "choice", "instructions": "q", "criteria": {"a": "1", "b": "2"}}
        self.assertEqual(jev.validate(good), [])
        self.assertTrue(jev.validate({**good, "criteria": {"a": "1"}}))
        self.assertTrue(jev.validate({**good, "type": "score", "criteria": ["only one"]}))
        self.assertTrue(jev.validate({**good, "mode": "active"}))  # active needs target.precision
        self.assertTrue(jev.validate({**good, "accept": {"min_confidence": 0.2}}))
        self.assertTrue(jev.validate({"id": "x", "version": 1, "type": "noul-set", "instructions": "q",
                                      "criteria": {"a": "1", "b": "2"}}))  # no {option}
        self.assertTrue(jev.validate({"id": "x", "version": 1, "type": "noul", "instructions": "q", "per_item": True}))
        self.assertTrue(jev.validate({**good, "lanes": {"thresholds": [1], "names": ["a"]}}))

    def test_noul_set_expands_and_combines(self):
        question = jev.Question({"id": "context.patterns", "version": 1, "type": "noul-set", "mode": "active",
                                 "instructions": "Pattern {option}?", "criteria": {"a": "A thing", "b": "B thing"},
                                 "accept": {"min_confidence": 0.5}})
        api = question.api_questions()
        self.assertEqual(set(api), {"context_patterns:a", "context_patterns:b"})
        self.assertEqual(api["context_patterns:a"]["instructions"], "Pattern A thing?")
        answers = {"context_patterns:a": jev.parse_answer(noul(0.9)), "context_patterns:b": jev.parse_answer(noul(0.1))}
        decision = question.combine(answers)
        self.assertEqual(decision.value, ["a"])
        self.assertEqual(decision.probabilities, {"a": 0.9, "b": 0.1})

    def test_state_fields_and_limits(self):
        question = jev.Question({"id": "q", "version": 1, "type": "noul", "instructions": "i",
                                 "state": {"fields": ["title", "body"], "max_chars": 5}})
        self.assertEqual(question.state({"title": "abcdefgh", "body": "", "other": "no"}), {"title": "abcde"})

    def test_per_item_and_lane(self):
        precedents = jev.load_questions()["context.precedents"]
        api = precedents.api_questions({"#1": "Fix pills", "#2": "Tune dial"})
        self.assertEqual(set(api), {"context_precedents:#1", "context_precedents:#2"})
        self.assertIn("Fix pills", api["context_precedents:#1"]["instructions"])
        route = jev.load_questions()["route.complexity"]
        self.assertEqual([route.lane(s) for s in (0.0, 1.49, 1.5, 2.99, 3.0, 4.0)],
                         ["haiku", "haiku", "sonnet", "sonnet", "opus", "opus"])

    def test_ask_question_end_to_end_with_fake_transport(self):
        question = jev.load_questions()["route.complexity"]
        send = self.transport(lambda body: {"route_complexity": {
            "type": "score", "score": 2.2, "confidence": 0.8, "probabilities": {"1": 0.3, "2": 0.6, "3": 0.1}}})
        decision = jev.ask_question(question, {"title": "Rework the sheet", "body": "big"}, transport=send)
        self.assertEqual(decision.value, 2)
        self.assertTrue(decision.accepted)
        self.assertEqual(decision.as_dict()["lane"], "sonnet")
        self.assertEqual(self.calls[0][0]["state"], {"title": "Rework the sheet", "body": "big"})
        self.assertIsNone(jev.ask_question(question, {"title": "x"}))  # no key, no transport

    def test_sync_rewrites_stale_criteria(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "contracts/jev/questions").mkdir(parents=True)
            (root / "contracts/patterns.json").write_text(json.dumps({"patterns": [
                {"id": "a", "title": "A", "summary": "Thing a.", "status": "current",
                 "canonical": {"apple": [{"path": "p", "symbol": "ASym"}]}},
                {"id": "old", "title": "Old", "summary": "Gone.", "status": "superseded", "canonical": {"apple": []}}]}))
            (root / "contracts/jev/questions/context.patterns.json").write_text(json.dumps({"criteria": {}}))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(jev.sync(check=True, root=root), 1)
                self.assertEqual(jev.sync(root=root), 0)
                self.assertEqual(jev.sync(check=True, root=root), 0)
            written = json.loads((root / "contracts/jev/questions/context.patterns.json").read_text())
            self.assertEqual(written["criteria"], {"a": "A: Thing a. (components: ASym)"})


class CliTests(Isolated):
    def run_cli(self, *argv, transport=None):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = jev.main(list(argv), transport=transport)
        return code, out.getvalue(), err.getvalue()

    def test_no_key_exits_3_with_a_clear_message(self):
        code, out, err = self.run_cli("yesno", "Is it?", "--state", "text")
        self.assertEqual(code, 3)
        self.assertIn("no key: put it in a mode-600", err)
        self.assertTrue(json.loads(out)["unavailable"])
        code, out, _ = self.run_cli("ask", "context.patterns", "--context", '{"title": "t"}')
        self.assertEqual(code, 3)

    def test_yesno_choose_score_rank_shapes(self):
        send = self.transport(lambda body: {"answer": noul(0.93)})
        code, out, _ = self.run_cli("yesno", "Is it?", "--state", "text", transport=send)
        result = json.loads(out)
        self.assertEqual((code, result["answer"], result["accepted"], result["p_true"]), (0, True, True, 0.93))
        send = self.transport(lambda body: {"answer": {"type": "choice", "choice": "b", "confidence": 0.5,
                                                       "probabilities": {"a": 0.2, "b": 0.8}}})
        _, out, _ = self.run_cli("choose", "Which?", "-o", "a=A", "-o", "b=B", "--state", "t", transport=send)
        self.assertEqual((json.loads(out)["answer"], json.loads(out)["accepted"]), ("b", False))
        send = self.transport(lambda body: {"answer": {"type": "score", "score": 1.0, "confidence": 0.9,
                                                       "probabilities": {"0": 0.0, "1": 1.0}}})
        _, out, _ = self.run_cli("score", "How?", "-l", "low", "-l", "high", "--state", "t", transport=send)
        self.assertEqual(json.loads(out)["score"], 1.0)
        send = self.transport(lambda body: {"item:a": noul(0.2), "item:b": noul(0.7)})
        _, out, _ = self.run_cli("rank", "Is {item} relevant?", "-i", "a=Apple", "-i", "b=Berry", "--state", "t", transport=send)
        self.assertEqual([r["item"] for r in json.loads(out)["ranked"]], ["b", "a"])

    def test_ask_registered_question_and_usage_errors(self):
        send = self.transport(lambda body: {k: noul(0.1) for k in body["questions"]})
        code, out, _ = self.run_cli("ask", "context.patterns", "--context", '{"title": "t"}', transport=send)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["question"], "context.patterns@8")
        self.assertEqual(self.run_cli("ask", "nope.question", "--context", "{}")[0], 2)
        self.assertEqual(self.run_cli("ask", "context.patterns", "--context", "[1]")[0], 2)
        self.assertEqual(self.run_cli("ask", "context.patterns", "--context", "{bad")[0], 2)

    def test_list_validate_sync_check(self):
        self.assertEqual(self.run_cli("validate")[0], 0)
        code, out, _ = self.run_cli("list")
        self.assertIn("route.complexity@1", out)
        self.assertEqual(self.run_cli("sync", "--check")[0], 0)


def fake_ranking(top):
    """Answers that give `top` a high probability and everything else 0.05; complexity 'small'."""
    def answers(body):
        out = {}
        for name in body["questions"]:
            if name.startswith("context_patterns:"):
                out[name] = noul(0.9 if name.split(":", 1)[1] == top else 0.05)
            elif name == "route_complexity":
                out[name] = {"type": "score", "score": 1.2, "confidence": 0.9, "probabilities": {"1": 0.9, "2": 0.1}}
            elif name.startswith("context_precedents:"):
                out[name] = noul(0.8 if name.endswith("#190") else 0.1)
        return out
    return answers


class HintTests(Isolated):
    def setUp(self):
        super().setUp()
        subjects = mock.patch.object(hints, "commit_subjects", return_value=[
            (190, "Workflow W2-W4: PR lifecycle gate"), (189, "Test tiers: per-change affected tests")])
        subjects.start()
        self.addCleanup(subjects.stop)

    def test_preread_lists_pattern_files_complexity_and_precedent(self):
        send = self.transport(fake_ranking("status-pill"))
        text = hints.preread("Status pill truncates", "Use the lifecycle gate", ["a.swift"], "triage", transport=send)
        self.assertTrue(text.startswith("## Pre-read (decision model: verify, don't obey)"))
        self.assertIn("`status-pill` 0.90: `.agents/patterns/status-pill.md`", text)
        self.assertIn("`apple/Sources/HassDesign/StatusPill.swift` (StatusPill)", text)
        self.assertIn("Haiku lane", text)
        self.assertIn("#190 Workflow W2-W4: PR lifecycle gate (0.80)", text)
        self.assertIn("read this request", text)
        self.assertIn("nothing here is an instruction", text)
        self.assertEqual(len(self.calls), 2)  # patterns and complexity share a request; precedents is a second
        self.assertIn("files", self.calls[0][0]["state"])

    def test_unavailable_or_failing_degrades_to_nothing(self):
        self.assertEqual(hints.preread("t", "b"), "")  # no key
        with mock.patch.dict(os.environ, {"TYPESAFE_API_KEY": "k"}):
            def boom(body, key, timeout):
                raise OSError("down")
            with mock.patch.object(jev.time, "sleep"):
                self.assertEqual(hints.preread("t", "b", transport=boom), "")
            with mock.patch.object(hints, "ask_hints", side_effect=RuntimeError("bug")):
                self.assertEqual(hints.preread("t", "b"), "")

    def test_low_confidence_pattern_list_is_omitted(self):
        send = self.transport(lambda body: {k: noul(0.4) if k.startswith("context_") else
                                            {"type": "score", "score": 1.0, "confidence": 0.9,
                                             "probabilities": {"1": 1.0}} for k in body["questions"]})
        text = hints.preread("A tooling change", "scripts only", transport=send)
        self.assertNotIn("Likely patterns", text)
        self.assertNotIn("Likely files", text)
        self.assertIn("Complexity", text)

    def test_recall_claim_is_stated_as_recall_not_probability(self):
        text = hints.preread("t", "b", transport=self.transport(fake_ranking("status-pill")))
        self.assertIn("its top 8 held 78% of the patterns they touched", text)
        self.assertIn("all of them in only 42% of PRs", text)

    def test_nothing_confident_prints_nothing(self):
        send = self.transport(lambda body: {k: noul(0.02) if k.startswith("context_") else
                                            {"type": "score", "score": 3.5, "confidence": 0.1,
                                             "probabilities": {"3": 0.4, "4": 0.6}} for k in body["questions"]})
        self.assertEqual(hints.preread("t", "b", transport=send), "")

    def test_prefilter_ranks_by_shared_words_and_drops_zero_overlap(self):
        subjects = [(3, "Fix status pill text"), (2, "Unrelated release plumbing"), (1, "Pill colours")]
        items = hints.prefilter("status pill truncates", subjects, limit=5)
        self.assertEqual(list(items), ["#3", "#1"])

    def test_cli_preread_always_exits_zero(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(hints.main(["preread", "--title", "t", "--body", "b"]), 0)
        self.assertEqual(out.getvalue(), "")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(hints.main(["preread", "--title", "t", "--body-file", "/nonexistent"],
                                        transport=self.transport(fake_ranking("scroll-fit"))), 0)
        self.assertIn("`scroll-fit` 0.90", out.getvalue())

    def test_review_uses_pr_context_and_tolerates_gh_failure(self):
        out = io.StringIO()
        with mock.patch.object(hints, "pr_context", return_value=("Header fade", "body", ["x.swift"])), \
                contextlib.redirect_stdout(out):
            hints.main(["review", "--pr", "5"], transport=self.transport(fake_ranking("header-edge-fade")))
        self.assertIn("read this pull request", out.getvalue())
        out = io.StringIO()
        with mock.patch.object(hints, "pr_context", return_value=None), contextlib.redirect_stdout(out):
            self.assertEqual(hints.main(["review", "--pr", "5"]), 0)
        self.assertEqual(out.getvalue(), "")


class CommitSubjectTests(unittest.TestCase):
    def test_parses_squash_subjects_and_falls_back_to_head(self):
        calls = []

        def run(cmd, **kwargs):
            calls.append(cmd[2])
            if cmd[2] == "origin/main":
                raise OSError("no such ref")
            return mock.Mock(stdout="Fix a thing (#12)\nNo number here\nOther (#3)\n")
        with mock.patch.object(hints.subprocess, "run", side_effect=run):
            self.assertEqual(hints.commit_subjects(), [(12, "Fix a thing"), (3, "Other")])
        self.assertEqual(calls, ["origin/main", "HEAD"])
        with mock.patch.object(hints.subprocess, "run", side_effect=OSError("no git")):
            self.assertEqual(hints.commit_subjects(), [])


class FindingTests(Isolated):
    def findings(self):
        return [{"severity": "major", "rule": "tests", "file": "a.swift", "detail": "No accessibility test for iPad"},
                {"severity": "minor", "rule": "x", "file": "b.swift", "detail": "typo"},
                {"severity": "blocker", "rule": "?", "file": "c.swift", "detail": "Something odd"}]

    def test_groups_by_family_and_lists_low_confidence_as_other(self):
        def answers(body):
            state = body["state"]
            if "accessibility test" in state["finding"]:
                return {"review_finding_family": {"type": "choice", "choice": "tests_missing_or_weak",
                                                  "confidence": 0.95, "probabilities": {"tests_missing_or_weak": 0.97}}}
            return {"review_finding_family": {"type": "choice", "choice": "correctness", "confidence": 0.3,
                                              "probabilities": {"correctness": 0.4}}}
        text = hints.finding_checklist(self.findings(), transport=self.transport(answers))
        self.assertIn("**Tests** (1)", text)
        self.assertIn("**Other** (1)", text)
        self.assertNotIn("typo", text)  # minors are not grouped
        self.assertEqual(len(self.calls), 2)

    def test_finding_checklist_stops_at_the_first_unavailable_answer(self):
        attempts = []

        def down(body, key, timeout):
            attempts.append(1)
            raise OSError("down")
        with mock.patch.dict(os.environ, {"TYPESAFE_API_KEY": "k"}), mock.patch.object(jev.time, "sleep"):
            self.assertEqual(hints.finding_checklist(self.findings() * 3, transport=down), "")
        self.assertEqual(len(attempts), 2)  # one finding, one retry; not one per finding

    def test_unavailable_or_no_blocking_findings_is_empty(self):
        self.assertEqual(hints.finding_checklist(self.findings()), "")
        self.assertEqual(hints.finding_checklist([{"severity": "minor", "detail": "x"}]), "")

    def test_cli_findings_reads_the_verdict_file(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "verdict.json"
            path.write_text(json.dumps({"verdict": "changes", "findings": self.findings()}))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(hints.main(["findings", str(path)]), 0)
            self.assertEqual(out.getvalue(), "")
            self.assertEqual(hints.main(["findings", str(Path(tmp) / "missing.json")]), 0)


class MeasureTests(unittest.TestCase):
    def test_truth_uses_owned_files_and_docs(self):
        data = {"patterns": [
            {"id": "a", "canonical": {"apple": [{"path": "x/A.swift"}]}, "owns": ["x/a/**"]},
            {"id": "b", "canonical": {"apple": []}, "owns": []}]}
        self.assertEqual(measure.truth(data, ["x/A.swift", "x/a/B.swift", "other.md"]), {"a"})
        self.assertEqual(measure.truth(data, [".agents/patterns/b.md", ".agents/patterns/README.md"]), {"b"})

    def test_sanitize_strips_paths_checklists_and_pattern_docs(self):
        text = "Fix the pill.\n- [x] Pattern reused\nSee apple/Sources/X.swift and status-pill.md here\nCo-Authored-By: x"
        out = measure.sanitize(text, {"status-pill"})
        self.assertIn("Fix the pill.", out)
        for gone in ("Pattern reused", "apple/Sources", "status-pill.md", "Co-Authored"):
            self.assertNotIn(gone, out)

    def test_keyword_rank_and_recall(self):
        data = {"patterns": [{"id": "alpha-thing", "keywords": ["banana"]}, {"id": "beta", "keywords": ["cherry pie"]},
                             {"id": "zeta", "keywords": []}]}
        self.assertEqual(measure.keyword_rank(data, "I like Cherry Pie and banana")[:2], ["alpha-thing", "beta"])
        self.assertEqual(measure.keyword_rank(data, "nothing")[0], "alpha-thing")  # ties by id
        self.assertEqual(measure.recall_at(["a", "b", "c"], {"a", "c"}, 2), 0.5)
        self.assertEqual(measure.recall_at(["a"], set(), 3), 0.0)

    def test_summarize_and_spearman(self):
        rows = [(["a", "b"], {"a"}), (["x", "a"], {"a", "b"})]
        s = measure.summarize(rows)
        self.assertEqual((s["n"], s["recall@1"], s["recall@3"], s["hit@8"], s["full@8"]), (2, 0.5, 0.75, 1.0, 0.5))
        self.assertEqual(measure.spearman([1, 2, 3, 4], [10, 20, 30, 40]), 1.0)
        self.assertEqual(measure.spearman([1, 2, 3], [3, 2, 1]), -1.0)
        self.assertEqual(measure.spearman([1, 1, 1], [1, 2, 3]), 0.0)
        self.assertEqual(measure.spearman([1], [1]), 0.0)

    def test_measure_needs_a_key(self):
        env = {"TYPESAFE_API_KEY": "", "JEV_KEY_FILE": "/nonexistent/typesafe.key"}
        with mock.patch.dict(os.environ, env), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(measure.main(["recall"]), 3)



# MARK: - Bands, items, shadow questions (agent roster)

class BandTests(Isolated):
    def banded(self, kind="noul", **extra):
        return jev.Question({"id": "x.y", "version": 1, "type": kind, "instructions": "Is {option}?" if kind == "noul-set" else "Is it?",
                             "accept": {"min_confidence": 0.5, "yes_above": 0.7, "no_below": 0.3}, **extra})

    def test_min_confidence_half_accepts_every_unbanded_noul(self):
        legacy = jev.Question({"id": "x.y", "version": 1, "type": "noul", "instructions": "q", "accept": {"min_confidence": 0.5}})
        for p in (0.5, 0.55, 0.9):
            self.assertTrue(legacy.combine({"x_y": jev.parse_answer(noul(p))}).accepted)

    def test_banded_noul_is_accepted_only_outside_the_unsure_band(self):
        question = self.banded()
        cases = {0.9: (True, True, "yes"), 0.7: (True, True, "yes"), 0.5: (False, None, "unsure"),
                 0.3: (True, False, "no"), 0.05: (True, False, "no")}
        for p, (accepted, value, band) in cases.items():
            decision = question.combine({"x_y": jev.parse_answer(noul(p))})
            self.assertEqual((decision.accepted, decision.value, decision.as_dict()["band"]), (accepted, value, band), p)

    def test_banded_set_lists_yes_and_unsure_options(self):
        question = self.banded("noul-set", criteria={"a": "A", "b": "B", "c": "C"})
        answers = {f"x_y:{k}": jev.parse_answer(noul(p)) for k, p in {"a": 0.9, "b": 0.5, "c": 0.1}.items()}
        decision = question.combine(answers)
        self.assertEqual((decision.value, decision.unsure, decision.accepted), (["a"], ["b"], False))
        self.assertEqual(decision.as_dict()["unsure"], ["b"])
        answers["x_y:b"] = jev.parse_answer(noul(0.8))
        self.assertTrue(question.combine(answers).accepted)

    def test_validate_checks_bands_and_new_fields(self):
        base = {"id": "x", "version": 1, "type": "noul", "instructions": "q"}
        self.assertEqual(jev.validate({**base, "accept": {"yes_above": 0.7, "no_below": 0.3}}), [])
        for accept in ({"yes_above": 0.7}, {"yes_above": 0.3, "no_below": 0.7}, {"yes_above": 1.0, "no_below": 0.3}):
            self.assertTrue(jev.validate({**base, "accept": accept}), accept)
        self.assertTrue(jev.validate({**base, "type": "choice", "criteria": {"a": 1, "b": 2},
                                      "accept": {"yes_above": 0.7, "no_below": 0.3}}))
        self.assertTrue(jev.validate({**base, "item_state": True}))
        self.assertTrue(jev.validate({**base, "output": " "}))
        self.assertTrue(jev.validate({**base, "companions": {"exists": {}}}))

    def test_warnings_flag_unbanded_half_confidence(self):
        self.assertEqual(len(jev.warnings({"type": "noul", "accept": {"min_confidence": 0.5}})), 1)
        self.assertEqual(jev.warnings({"type": "noul", "accept": {"min_confidence": 0.5, "yes_above": 0.7, "no_below": 0.3}}), [])
        self.assertEqual(jev.warnings({"type": "choice", "accept": {"min_confidence": 0.5}}), [])

    def test_companion_noul_is_asked_with_a_choice_and_lands_in_extras(self):
        question = jev.load_questions()["route.role"]
        api = question.api_questions()
        self.assertEqual(set(api), {"route_role", "route_role__exists"})
        answers = {"route_role": jev.parse_answer({"type": "choice", "choice": "design", "confidence": 0.9,
                                                   "probabilities": {"design": 0.95, "research": 0.05}}),
                   "route_role__exists": jev.parse_answer(noul(0.8))}
        decision = question.combine(answers)
        self.assertEqual((decision.value, decision.extras), ("design", {"exists": 0.8}))
        self.assertEqual(decision.as_dict()["extras"], {"exists": 0.8})

    def test_item_state_api_questions_point_at_state_paths(self):
        question = jev.load_questions()["research.section_relevant"]
        api = question.api_questions({"i0": "", "i1": ""}, {"question": "who approves?"})
        self.assertIn("`items.i1`", api["research_section_relevant:i1"]["instructions"])
        self.assertIn("who approves?", api["research_section_relevant:i1"]["instructions"])


class ShadowTests(Isolated):
    def test_shadow_questions_are_logged_without_state_text_and_active_ones_are_not(self):
        shadow = jev.load_questions()["check.tests"]
        send = self.transport(lambda body: {k: noul(0.8) for k in body["questions"]})
        decision = jev.ask_question(shadow, {"pr_title": "Secret title", "files": "a.swift"}, transport=send, subject="pr:7")
        self.assertTrue(decision.value)
        record = json.loads((Path(self.tmp.name) / "shadow.jsonl").read_text())
        self.assertEqual((record["question"], record["subject"]), ("check.tests@1", "pr:7"))
        self.assertNotIn("Secret title", json.dumps(record))
        path = Path(self.tmp.name) / "shadow.jsonl"
        path.unlink()
        active = jev.load_questions()["route.complexity"]
        jev.ask_question(active, {"title": "t"}, transport=self.transport(lambda body: {
            "route_complexity": {"type": "score", "score": 1.0, "confidence": 0.9, "probabilities": {"1": 1.0}}}))
        self.assertFalse(path.exists())

    def test_review_asks_check_tests_in_shadow_and_prints_nothing_for_it(self):
        send = self.transport(lambda body: {k: noul(0.9) for k in body["questions"]})
        with mock.patch.object(hints, "pr_context", return_value=("Add a sheet", "body", ["a.swift"])), \
                mock.patch.object(hints, "preread", return_value=""):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                hints.main(["review", "--pr", "12"], transport=send)
        self.assertEqual(out.getvalue(), "")
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(set(self.calls[0][0]["questions"]), {"check_tests"})
        self.assertIn("Add a sheet", json.dumps(self.calls[0][0]["state"]))
        self.assertIn("accessibility test", self.calls[0][0]["state"]["test_rules"])
        record = json.loads((Path(self.tmp.name) / "shadow.jsonl").read_text())
        self.assertEqual(record["subject"], "pr:12")

    def test_check_tests_failure_is_silent(self):
        with mock.patch.object(hints.jev, "ask_question", side_effect=RuntimeError("bug")):
            self.assertIsNone(hints.shadow_check_tests("t", ["a"]))
        self.assertIsNone(hints.shadow_check_tests("t", ["a"]))  # no key


class ItemsCliTests(Isolated):
    def run_cli(self, *argv, transport=None):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = jev.main(list(argv), transport=transport)
        return code, out.getvalue(), err.getvalue()

    def items_file(self, data):
        path = Path(self.tmp.name) / "items.json"
        path.write_text(json.dumps(data))
        return str(path)

    def test_rank_items_file_puts_text_in_state_and_breaks_ties_by_file_order(self):
        send = self.transport(lambda body: {k: noul(0.9 if k.endswith(":i2") else 0.4) for k in body["questions"]})
        path = self.items_file({"first": "one", "second": "two", "third": "three"})
        code, out, _ = self.run_cli("rank", "Is this about pills?", "--items-file", path, transport=send)
        self.assertEqual(code, 0)
        ranked = json.loads(out)["ranked"]
        self.assertEqual([r["item"] for r in ranked], ["third", "first", "second"])
        body = self.calls[0][0]
        self.assertEqual(body["state"]["items"], {"i0": "one", "i1": "two", "i2": "three"})
        self.assertTrue(all("Is this about pills?" in q["instructions"] and "one" not in q["instructions"]
                            for q in body["questions"].values()))

    def test_rank_inline_items_also_tie_break_by_order(self):
        send = self.transport(lambda body: {k: noul(0.5) for k in body["questions"]})
        code, out, _ = self.run_cli("rank", "Is {item} relevant?", "-i", "b=Bee", "-i", "a=Ay", "--state", "x", transport=send)
        self.assertEqual([r["item"] for r in json.loads(out)["ranked"]], ["b", "a"])

    def test_rank_needs_items(self):
        code, out, _ = self.run_cli("rank", "q", "--state", "x")
        self.assertEqual(code, 2)

    def test_array_items_file_and_bad_files(self):
        path = self.items_file([{"id": "x", "text": "xx"}, {"name": "y", "text": "yy"}])
        self.assertEqual(jev.read_items(path), {"x": "xx", "y": "yy"})
        for bad in ({}, [], {"a": ""}, {"a": 3}):
            with self.assertRaises(ValueError):
                jev.read_items(self.items_file(bad))
        code, out, _ = self.run_cli("rank", "q", "--items-file", self.items_file({}))
        self.assertEqual(code, 2)

    def test_ask_registered_item_question_with_items_file(self):
        send = self.transport(lambda body: {k: noul(0.9 if "needle" in body["state"]["items"][k.split(":")[1]] else 0.1)
                                            for k in body["questions"]})
        path = self.items_file({"s0": "hay", "s1": "needle"})
        code, out, _ = self.run_cli("ask", "research.section_relevant", "--items-file", path, "--param", "question=where",
                                    transport=send)
        result = json.loads(out)
        self.assertEqual((code, result["value"], result["unsure"]), (0, ["s1"], []))
        self.assertIn('"where"', self.calls[0][0]["questions"]["research_section_relevant:i0"]["instructions"])
        code, out, _ = self.run_cli("ask", "route.complexity", "--items-file", path, transport=send)
        self.assertEqual(code, 2)

    def test_items_without_a_key_exit_3(self):
        code, out, err = self.run_cli("rank", "q", "--items-file", self.items_file({"a": "text"}))
        self.assertEqual(code, 3)
        self.assertTrue(json.loads(out)["unavailable"])


class GeneratedQuestionTests(Isolated):
    PROPOSAL = ("research.section_relevant research.evidence research.contradicts research.injection "
                "research.release_impact research.source_kind change.kind tests.pick code.custom_machinery "
                "design.new_pattern route.role triage.duplicate brief.complete report.complete "
                "transcript.turn_kind owner_msg.kind learning.home").split()

    def test_every_proposal_question_is_a_versioned_unmeasured_shadow_with_an_output(self):
        questions = jev.load_questions()
        for qid in self.PROPOSAL:
            data = questions[qid].data
            # Versioned from 1 (a criteria sync bumps it: `jev_ask.py sync` asks for that), and still a shadow.
            self.assertGreaterEqual(data["version"], 1, qid)
            self.assertEqual(data["mode"], "shadow", qid)
            # Unmeasured, or a recorded shadow measurement that is not yet a promotion.
            self.assertTrue(data["evidence"] == "unmeasured" or data["evidence"].startswith("Shadow."), qid)
            self.assertTrue(data["output"].strip(), qid)
        for qid, q in questions.items():
            self.assertTrue(q.data.get("output"), qid)

    def test_gate_questions_are_active_banded_and_cite_their_measurement(self):
        questions = jev.load_questions()
        self.assertEqual((questions["design.user_visible"].data["version"], questions["decision.needs_owner"].data["version"]),
                         (2, 1))
        for qid, yes in (("design.user_visible", 0.6), ("decision.needs_owner", 0.5)):
            q = questions[qid]
            self.assertEqual((q.mode, q.yes_above, q.no_below), ("active", yes, 0.3), qid)
            self.assertIn("measurements.md", q.data["evidence"], qid)
            self.assertTrue(q.data["output"].strip(), qid)
        self.assertEqual(questions["decision.needs_owner"].data["state"]["fields"], ["plan"])

    def test_noul_questions_of_the_proposal_use_bands(self):
        for qid in self.PROPOSAL:
            q = jev.load_questions()[qid]
            if q.data["type"] in ("noul", "noul-set"):
                self.assertTrue(q.banded, qid)
                self.assertGreater(q.yes_above, q.no_below)

    def test_screening_thresholds_are_the_cookbook_ones(self):
        questions = jev.load_questions()
        self.assertEqual((questions["research.injection"].yes_above, questions["research.contradicts"].yes_above,
                          questions["research.evidence"].yes_above, questions["research.section_relevant"].no_below),
                         (0.7, 0.7, 0.55, 0.45))

    def test_learning_home_names_existing_docs(self):
        criteria = jev.load_questions()["learning.home"].data["criteria"]
        self.assertIn("none", criteria)
        for path in criteria:
            if path != "none":
                self.assertTrue((REPO / path).is_file(), path)
        self.assertNotIn(".agents/design/mockups", " ".join(criteria))
        self.assertIn(".agents/workflow/decision-models.md", criteria)

    def test_release_impact_covers_services_hakit_and_frameworks(self):
        criteria = jev.load_questions()["research.release_impact"].data["criteria"]
        kinds = {key.split(":")[0] for key in criteria}
        self.assertEqual(kinds, {"domain", "service", "hakit", "framework"})
        self.assertIn("service:light.turn_on", criteria)

    def test_surface_extracts_calls_hakit_and_frameworks(self):
        surface = load_tool("jev_surface")
        with TemporaryDirectory() as tmp:
            src = Path(tmp) / "apple" / "Sources" / "HassCore"
            src.mkdir(parents=True)
            (src / "A.swift").write_text('import SwiftUI\nimport HassCore\nimport ActivityKit\n'
                                         'try await caller.callService("todo", "add_item", data: [:])\n'
                                         'let x = ("todo", "remove_item")\nlet y = ("idle", "stop")\n'
                                         'let r: HATypedRequest<HAResponseVoid>; let h = HASH\n'
                                         'perform(domain: "light", service: "turn_on")\nlet z = ("switch", "toggle")\n')
            data = surface.surface(Path(tmp))
            self.assertEqual(data["domains"], ["light", "switch", "todo"])
            self.assertEqual(data["services"], ["light.turn_on", "switch.toggle", "todo.add_item", "todo.remove_item"])
            self.assertEqual(data["hakit"], ["HAResponseVoid", "HATypedRequest"])
            self.assertEqual(data["frameworks"], ["ActivityKit", "SwiftUI"])
            self.assertIn("service:todo.add_item", surface.criteria(Path(tmp)))

    def test_sync_regenerates_learning_home_and_release_impact(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "contracts/jev/questions").mkdir(parents=True)
            (root / ".agents/workflow").mkdir(parents=True)
            (root / ".agents/design/mockups").mkdir(parents=True)
            (root / ".agents/workflow/a.md").write_text("# Doc A\n\n> **What:** does a. **Read when:** touching a.\n")
            (root / ".agents/design/mockups/m.md").write_text("# Mock\n")
            (root / "AGENTS.md").write_text("# Agents\n\n> **What:** the entry point.\n")
            (root / "apple/Sources/X").mkdir(parents=True)
            (root / "apple/Sources/X/B.swift").write_text('import WidgetKit\n')
            for qid in ("learning.home", "research.release_impact"):
                (root / "contracts/jev/questions" / f"{qid}.json").write_text(json.dumps({"criteria": {}}))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(jev.sync(check=True, root=root), 1)
                self.assertEqual(jev.sync(root=root), 0)
                self.assertEqual(jev.sync(check=True, root=root), 0)
            home = json.loads((root / "contracts/jev/questions/learning.home.json").read_text())["criteria"]
            self.assertEqual(set(home), {"AGENTS.md", ".agents/workflow/a.md", "none"})
            self.assertEqual(home[".agents/workflow/a.md"], "Doc A: does a. (read when: touching a.)")
            release = json.loads((root / "contracts/jev/questions/research.release_impact.json").read_text())["criteria"]
            self.assertEqual(list(release), ["framework:WidgetKit"])


if __name__ == "__main__":
    unittest.main()


class SectionsMeasureTests(Isolated):
    def test_ranks_and_summaries(self):
        self.assertEqual(measure.first_hit(["a", "b", "c"], {"c", "b"}), 2)
        self.assertIsNone(measure.first_hit(["a"], {"z"}))
        self.assertEqual(measure.summarize_ranks([1, 3, None, 5]), {"hit@1": 0.25, "hit@3": 0.5, "mrr": 0.383})

    def test_labels_point_at_real_sections(self):
        sec = load_tool("jev_sections")
        labels = json.loads(measure.LABELS.read_text())["pairs"]
        self.assertGreaterEqual(len(labels), 20)
        self.assertEqual([(f["question"], f["reason"]) for f in sec.label_anchor_failures(REPO, labels)], [])

    def test_run_sections_compares_jev_with_bm25_and_stops_at_the_cap(self):
        def send(body, key, timeout):
            items = body["state"]["items"]
            return {"answers": {n: {"type": "noul", "noul": 0.9 if "Apple Distribution" in items[n.split(":")[1]] else 0.1}
                                for n in body["questions"]}, "usage": {"input_tokens": 1000}}
        labels = Path(self.tmp.name) / "labels.json"
        labels.write_text(json.dumps({"pairs": [
            {"file": ".agents/workflow/ci.md", "question": "Who signs the app archive?", "any_of": ["Apple Distribution"]},
            {"file": ".agents/workflow/ci.md", "question": "Who signs the app archive?", "any_of": ["Apple Distribution"]}]}))
        with mock.patch.dict(os.environ, {"TYPESAFE_API_KEY": "k"}):
            result = measure.run_sections(labels, transport=send)
            self.assertEqual((result["pairs"], result["jev"]["hit@1"]), (2, 1.0))
            self.assertEqual(result["input_tokens"], 1000 * result["requests"])
            capped = measure.run_sections(labels, max_usd=0.0, transport=send)
        self.assertEqual(capped["pairs"], 0)
        other = Path(self.tmp.name) / "other.json"
        other.write_text(json.dumps({"pairs": [{"file": ".agents/workflow/ci.md", "question": "An uncached question?",
                                                "any_of": ["x"]}]}))
        self.assertEqual(measure.run_sections(other).get("error"), jev.NO_KEY)
