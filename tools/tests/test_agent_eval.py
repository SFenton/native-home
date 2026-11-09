"""``tools/agent_eval.py``: tier 0 on the current code, broken code failing the right case (each case in a child process, the
comparison in the parent), a lane that patches the harness still failing an impossible case, tier 1 with a fake Jev
(unmeasurable active questions fail), retired cases as a report, tier 2 with a fake claude, and the lander running the trusted
harness against the lane. No network, no key."""

import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
spec = importlib.util.spec_from_file_location("agent_eval", TOOLS / "agent_eval.py")
ae = importlib.util.module_from_spec(spec)
sys.modules["agent_eval"] = ae
spec.loader.exec_module(ae)

REPLAY = REPO / "evals" / "agents" / "routing-replay"


def make_target(test):
    """A scratch copy of the code under test (tools, Jev questions), the lane a test then breaks on purpose."""
    tmp = Path(tempfile.mkdtemp(prefix="eval-target-"))
    test.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
    ignore = shutil.ignore_patterns("__pycache__", "tests", "fixtures", "*.pyc")
    shutil.copytree(REPO / "tools", tmp / "tools", ignore=ignore)
    (tmp / "contracts" / "jev").mkdir(parents=True)
    shutil.copytree(REPO / "contracts" / "jev" / "questions", tmp / "contracts" / "jev" / "questions")
    return tmp


def patch_file(target, rel, text, append=False):
    """Put ``text`` at the end (``append``) or the start of ``target/rel``."""
    path = target / rel
    old = path.read_text()
    path.write_text(old + text if append else text + old)


def run_main(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = ae.main(list(argv))
    return code, out.getvalue(), err.getvalue()


class Tier0Tests(unittest.TestCase):
    def test_passes_on_the_current_code(self):
        code, out, _ = run_main("--tier", "0")
        self.assertEqual(code, 0, out)
        match = [line for line in out.splitlines() if line.startswith("suite routing-replay:")]
        self.assertEqual(len(match), 1)
        cases, passed = [int(x) for x in match[0].replace(",", "").split() if x.isdigit()]
        self.assertGreaterEqual(cases, 25)
        self.assertEqual(cases, passed)
        self.assertRegex(out, r"(?m)^Ran \d+ tests? in [\d.]+s\s*$")  # lane_land counts these
        self.assertTrue(out.strip().endswith("OK"))

    def test_every_case_cites_its_source_and_matches_its_file_name(self):
        for path in ae.case_files(REPLAY / "cases"):
            case, error = ae.load_case(path)
            self.assertEqual(error, "", path.name)
            self.assertTrue(case["source"].strip(), path.name)

    def test_todays_incidents_are_all_there(self):
        ids = {p.stem for p in ae.case_files(REPLAY / "cases")}
        for want in ("route-workflow-steward-first", "route-feature-researcher-first", "route-camera-grace-timing-not-visible",
                     "gate-missing-plan-exits-2", "brief-lacks-done-check", "stop-nightly-ill-wait",
                     "record-round-3-needs-a-reason", "digest-label-not-found-1957", "digest-slot-wait-3h22m",
                     "lane-agents-and-labels-together-refused", "lane-retire-without-reason-refused"):
            self.assertIn(want, ids)

    def test_a_broken_route_fails_the_right_case(self):
        target = make_target(self)
        patch_file(target, "tools/triage/hass_triage.py", "\n\ndef route_rule(issue, nightly=False):\n    return 'designer'\n"
                   "\n\n_old_route_rule = route_rule\n", append=True)
        ok, problems = ae.run_case(target, REPLAY / "cases" / "route-feature-researcher-first.json")
        other, _ = ae.run_case(target, REPLAY / "cases" / "stop-nightly-ill-wait.json")
        self.assertFalse(ok)
        self.assertIn("route: expected 'researcher', got 'designer'", problems)
        self.assertTrue(other)

    def test_a_broken_gate_table_fails_and_main_exits_1_with_a_lander_readable_id(self):
        target = make_target(self)
        patch_file(target, "tools/jev_gate.py", "\n\ndef route_hint(visible=None, chosen=None, pick=None):\n"
                   "    return 'Coder (L0)'\n", append=True)
        code, out, _ = run_main("--tier", "0", "--target", str(target))
        self.assertEqual(code, 1)
        self.assertRegex(out, r"(?m)^FAIL: gate-route-camera-pick-no-design \(routing-replay\)$")
        self.assertIn("FAILED (failures=", out)

    def test_a_crashing_code_path_is_a_failing_case_not_a_crash(self):
        target = make_target(self)
        patch_file(target, "tools/jev_ask.py", "\n\ndef ask_question(*a, **k):\n    raise RuntimeError('kaput')\n", append=True)
        code, out, _ = run_main("--tier", "0", "--target", str(target))
        self.assertEqual(code, 1)
        self.assertIn("RuntimeError: kaput", out)

    def test_an_unknown_kind_fails_the_case(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c.json"
            path.write_text(json.dumps({"id": "c", "source": "s", "kind": "nonsense", "input": {}, "expect": {"x": 1}}))
            ok, problems = ae.run_case(REPO, path)
        self.assertFalse(ok)
        self.assertIn("unknown kind", problems[0])

    def test_cases_run_without_a_key_or_the_network(self):
        with mock.patch.dict(os.environ, {"TYPESAFE_API_KEY": "must-not-be-used"}), \
                mock.patch("urllib.request.urlopen", side_effect=AssertionError("network")):
            code, out, _ = run_main("--tier", "0")
        self.assertEqual(code, 0, out)


IMPOSSIBLE = {"id": "impossible", "source": "a case no code can satisfy", "kind": "stop_hook", "headless": True,
              "input": {"items": [{"type": "user", "message": {"role": "user", "content": "hi"}}]},
              "expect": {"reason": "this text is never produced"}}


class HarnessIntegrityTests(unittest.TestCase):
    """The code under test cannot reach the comparison: it runs in a child, the verdict is the parent's."""

    def add_case(self, target, case):
        folder = target / "evals" / "agents" / "routing-replay" / "cases"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{case['id']}.json").write_text(json.dumps(case))

    def test_the_impossible_case_fails_on_clean_code(self):
        target = make_target(self)
        self.add_case(target, IMPOSSIBLE)
        code, out, _ = run_main("--tier", "0", "--target", str(target))
        self.assertEqual(code, 1, out)
        self.assertRegex(out, r"(?m)^FAIL: impossible \(routing-replay\)$")
        self.assertIn("Ran 43 tests", out)  # the lane's added case counts on top of the 41 trusted active cases and the 1 retired report case

    def test_a_hook_that_patches_compare_still_fails_the_impossible_case(self):
        target = make_target(self)
        self.add_case(target, IMPOSSIBLE)
        patch_file(target, "tools/hooks/stop_continue_guard.py", (
            "import sys as _s\nfor _name in ('__main__', 'agent_eval'):\n    _m = _s.modules.get(_name)\n"
            "    if _m is not None:\n        _m.compare = lambda observed, expect: []\n        _m.run_case = lambda *a, **k: (True, [])\n"
            "        _m.report = lambda *a, **k: 0\n"), append=True)
        code, out, _ = run_main("--tier", "0", "--target", str(target))
        self.assertEqual(code, 1, out)
        self.assertRegex(out, r"(?m)^FAIL: impossible \(routing-replay\)$")

    def test_code_that_exits_or_forges_nothing_leaves_no_result_and_fails(self):
        target = make_target(self)
        patch_file(target, "tools/hooks/stop_continue_guard.py", "\nimport os\nos._exit(0)\n", append=True)
        code, out, _ = run_main("--tier", "0", "--target", str(target), "--suite", "routing-replay")
        self.assertEqual(code, 1)
        self.assertIn("left no result", out)

    def test_the_lane_cannot_replace_a_trusted_case_with_an_easy_one(self):
        target = make_target(self)
        easy = json.loads((REPLAY / "cases" / "stop-nightly-ill-wait.json").read_text())
        easy["expect"] = {"blocked": {"has": []}}
        self.add_case(target, easy)  # same file name as a trusted case: the trusted copy runs
        patch_file(target, "tools/hooks/stop_continue_guard.py", "def _never():\n    pass\n", append=True)
        code, out, _ = run_main("--tier", "0", "--target", str(target))
        self.assertEqual(code, 0, out)
        self.assertIn("suite routing-replay: 41 cases", out)  # not 42: the lane's namesake is ignored

    def test_a_case_the_lane_retired_runs_as_a_report_and_keeps_the_total(self):
        target = make_target(self)
        folder = target / "evals" / "agents" / "routing-replay" / "retired"
        folder.mkdir(parents=True)
        (folder / "stop-nightly-ill-wait.json").write_text((REPLAY / "cases" / "stop-nightly-ill-wait.json").read_text())
        suites = ae.evaluate(REPO, target=target, tier=0)
        names = {s["name"]: s for s in suites}
        self.assertEqual(names[ae.SUITE]["cases"], 40)
        # the lane's retired copy plus the one trusted retired case (gate-no-jev-stays-silent, retired in 7889cda9)
        self.assertEqual(names[ae.RETIRED_SUITE]["cases"], 2)
        self.assertEqual(names[ae.SUITE]["cases"] + names[ae.RETIRED_SUITE]["cases"], 42)

    def test_code_under_test_cannot_rewrite_a_later_case_after_the_children_start(self):
        root = Path(tempfile.mkdtemp(prefix="eval-root-"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        folder = root / "evals" / "agents" / "routing-replay" / "cases"
        folder.mkdir(parents=True)
        shutil.copy(REPLAY / "cases" / "stop-nightly-ill-wait.json", folder)
        later = dict(IMPOSSIBLE, id="zz-later")
        (folder / "zz-later.json").write_text(json.dumps(later))
        (root / "evals" / "agents" / "routing-replay" / "retired").mkdir()
        target = make_target(self)
        # every child that loads the stop hook rewrites ALL trusted case files so that nothing is expected
        patch_file(target, "tools/hooks/stop_continue_guard.py", (
            "import glob as _g, json as _j, os as _o\nfor _p in _g.glob(" + repr(str(folder / "*.json")) + "):\n"
            "    try:\n        _d = _j.load(open(_p))\n    except ValueError:\n        continue\n"
            "    _d['expect'] = {'a.b': None}\n    _t = _p + '.%d.tmp' % _o.getpid()\n"
            "    _j.dump(_d, open(_t, 'w'))\n    _o.replace(_t, _p)\n"), append=True)  # atomic: parallel children never race
        suites = ae.evaluate(root, target=target, tier=0)
        main = {s["name"]: s for s in suites}[ae.SUITE]
        self.assertEqual(json.loads((folder / "zz-later.json").read_text())["expect"], {"a.b": None})  # the child did write
        self.assertEqual([c for c, _ in main["failures"]], ["zz-later"])  # ...and the parent still held the original expectation

    def test_children_get_the_case_on_stdin_in_a_temp_cwd_and_never_a_case_path(self):
        seen = []
        real = subprocess.run

        def spy(cmd, **kw):
            seen.append((cmd, kw))
            return real(cmd, **kw)
        with mock.patch.object(ae.subprocess, "run", spy):
            ae.run_case(REPO, REPLAY / "cases" / "stop-nightly-ill-wait.json")
        cmd, kw = seen[0]
        self.assertFalse(any("routing-replay" in str(a) or "stop-nightly" in str(a) for a in cmd), cmd)
        self.assertNotEqual(Path(kw["cwd"]).resolve(), REPO)
        self.assertIn("kind", json.loads(kw["input"]))
        self.assertNotIn("expect", json.loads(kw["input"]))

    def test_the_parent_never_imports_the_code_under_test(self):
        source = (TOOLS / "agent_eval.py").read_text()
        for needle in ("spec_from_file_location", "exec_module", "importlib"):
            self.assertNotIn(needle, source)


class MalformedCaseTests(unittest.TestCase):
    def test_bad_cases_fail_with_a_reason(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "a.json").write_text("{nope")
            (d / "b.json").write_text(json.dumps({"id": "other", "source": "s", "kind": "route", "input": {}, "expect": {"x": 1}}))
            (d / "c.json").write_text(json.dumps({"id": "c", "source": "s", "kind": "nonsense", "input": {}, "expect": {"x": 1}}))
            (d / "d.json").write_text(json.dumps({"id": "d", "kind": "route", "input": {}, "expect": {"x": 1}}))
            suite = ae.run_suite(REPO, ae.case_files(d), "x")
        self.assertEqual((suite["cases"], suite["passed"]), (4, 0))
        text = " ".join(" ".join(p) for _, p in suite["failures"])
        for want in ("not valid JSON", "must equal the file name", "unknown kind", "missing source"):
            self.assertIn(want, text)


class CompareTests(unittest.TestCase):
    def test_operators(self):
        observed = {"a": {"b": ["x", "y"]}, "s": "hello world", "n": 3}
        self.assertEqual(ae.compare(observed, {"a.b": {"has": ["x"], "lacks": ["z"]}, "s": {"has": ["world"]}, "n": 3}), [])
        self.assertTrue(ae.compare(observed, {"a.b": {"lacks": ["x"]}}))
        self.assertTrue(ae.compare(observed, {"s": {"has": ["nope"]}}))
        self.assertTrue(ae.compare(observed, {"missing.path": 1}))
        self.assertEqual(ae.compare({"l": []}, {"l": {"eq": []}}), [])


class RetiredTests(unittest.TestCase):
    def make_root(self, passing):
        """A root whose only case is a retired ``record_round`` case; round 3 without a reason IS refused."""
        tmp = Path(tempfile.mkdtemp(prefix="eval-root-"))
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        base = tmp / "evals" / "agents" / "routing-replay"
        (base / "cases").mkdir(parents=True)
        (base / "retired").mkdir()
        for rel in ("tools/review", "tools/triage"):  # the code under test is the repo's, copied
            shutil.copytree(REPO / rel, tmp / rel, ignore=shutil.ignore_patterns("__pycache__", "tests"))
        for name in ("pr_land.py", "redact.py", "gh_app_token.py", "review_verdict.py"):
            shutil.copy(REPO / "tools" / name, tmp / "tools" / name)
        case = {"id": "old-rule", "source": "once", "kind": "record_round", "input": {"round": 3, "reason": None},
                "expect": {"refused": passing}}
        (base / "retired" / "old-rule.json").write_text(json.dumps(case))
        (base / "retired" / "old-rule.json.reason.json").write_text(json.dumps({"kind": "owner_rule"}))
        return tmp

    def test_retired_cases_run_as_a_report_and_never_fail_the_gate(self):
        suites = ae.evaluate(self.make_root(passing=False))
        retired = next(s for s in suites if s["name"] == ae.RETIRED_SUITE)
        self.assertEqual((retired["cases"], retired["passed"]), (1, 0))
        out = io.StringIO()
        code = ae.report(suites, 0.1, out=out)
        self.assertEqual(code, 0)
        self.assertIn("suite routing-replay-retired (report only): 1 cases, 0 passed", out.getvalue())
        self.assertIn("retired case old-rule no longer passes (report only)", out.getvalue())
        self.assertNotIn("FAIL:", out.getvalue())
        self.assertIn("Ran 1 tests", out.getvalue())  # retired cases count, so retiring never lowers the lander's count

    def test_a_passing_retired_case_is_counted_passed(self):
        suites = ae.evaluate(self.make_root(passing=True))
        retired = next(s for s in suites if s["name"] == ae.RETIRED_SUITE)
        self.assertEqual((retired["cases"], retired["passed"]), (1, 1))


class Tier1Tests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="eval-jev-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        derived = self.root / "contracts" / "jev" / "derived"
        (derived / "labels").mkdir(parents=True)
        (derived / "results").mkdir()
        (self.root / "contracts" / "jev" / "questions").mkdir()
        self.question = {"id": "x.q", "version": 2, "type": "noul", "mode": "active", "instructions": "Is it a bug?",
                         "criteria": {"true": "a bug", "false": "not a bug"},
                         "accept": {"yes_above": 0.6, "no_below": 0.3, "min_confidence": 0.5}, "target": {"precision": 0.95}}
        (self.root / "contracts/jev/questions/x.q.json").write_text(json.dumps(self.question))
        (derived / "probes.json").write_text(json.dumps({"probes": [{"id": "x.q.v2", "labels": "labels/x.q.jsonl", "state_fields": ["text"]}]}))
        (derived / "candidates.json").write_text(json.dumps({"candidates": []}))
        (derived / "labels" / "x.q.jsonl").write_text("\n".join(
            json.dumps({"id": str(i), "text": "t", "label": i < 5, "split": "test"}) for i in range(10)))
        self.write_recorded(self.rows([0.95] * 5 + [0.05] * 5))

    def rows(self, probs):
        return [{"id": str(i), "label": i < 5, "probabilities": {"true": p, "false": 1 - p}} for i, p in enumerate(probs)]

    def write_recorded(self, rows):
        (self.root / "contracts/jev/derived/results/x.q.v2.test.jsonl").write_text("\n".join(json.dumps(r) for r in rows))

    def measure(self, rows, code=0):
        calls = []

        def fake(trusted, spec, items):
            calls.append(spec["id"])
            return code, rows
        fake.calls = calls
        return fake

    def test_passes_when_precision_and_auc_hold(self):
        fake = self.measure(self.rows([0.95] * 5 + [0.05] * 5))
        suite = ae.run_jev_suite(self.root, ["x.q"], fake)
        self.assertEqual((suite["cases"], suite["passed"], suite["failures"]), (1, 1, []))
        self.assertEqual(fake.calls, ["x.q.v2"])  # the versioned probe is measured

    def test_fails_when_precision_drops_below_the_target(self):
        rows = self.rows([0.95] * 5 + [0.05] * 5)
        rows[7]["probabilities"]["true"] = 0.9  # a false positive: 5 of 6 flagged
        suite = ae.run_jev_suite(self.root, ["x.q"], self.measure(rows))
        self.assertEqual(suite["passed"], 0)
        self.assertIn("below the target 0.95", suite["failures"][0][1][0])

    def test_fails_when_auc_falls_more_than_the_slack(self):
        rows = self.rows([0.95] * 5 + [0.05] * 5)
        for i in (0, 1, 2):
            rows[i]["probabilities"]["true"] = 0.04  # positives now below negatives, never flagged
        suite = ae.run_jev_suite(self.root, ["x.q"], self.measure(rows))
        self.assertEqual(suite["passed"], 0)
        self.assertTrue(any("AUC" in p for p in suite["failures"][0][1]))

    def lane_with(self, instructions, extra=None):
        """A lane checkout: the same Jev files, the question reworded, and whatever shadow files ``extra`` maps."""
        lane = Path(tempfile.mkdtemp(prefix="eval-lane-"))
        self.addCleanup(shutil.rmtree, lane, ignore_errors=True)
        (lane / "contracts" / "jev" / "questions").mkdir(parents=True)
        (lane / "contracts/jev/questions/x.q.json").write_text(json.dumps({**self.question, "instructions": instructions}))
        for rel, text in (extra or {}).items():
            (lane / rel).parent.mkdir(parents=True, exist_ok=True)
            (lane / rel).write_text(text)
        return lane

    def test_the_lanes_reworded_question_is_what_gets_measured(self):
        seen = []

        def fake(trusted, spec, items):
            seen.append((trusted, spec, len(items)))
            if "REWORDED" in spec["question"]["instructions"]:  # the reworded question performs worse
                return 0, self.rows([0.95] * 3 + [0.2] * 2 + [0.9, 0.9] + [0.05] * 3)
            return 0, self.rows([0.95] * 5 + [0.05] * 5)
        good = ae.run_jev_suite(self.root, ["x.q"], fake, target=self.lane_with("Is it a bug?"))
        self.assertEqual((good["cases"], good["passed"]), (1, 1))
        bad = ae.run_jev_suite(self.root, ["x.q"], fake, target=self.lane_with("REWORDED: is it a bug?"))
        self.assertEqual((bad["cases"], bad["passed"]), (1, 0))
        self.assertIn("below the target", bad["failures"][0][1][0])
        trusted, spec, count = seen[-1]
        self.assertEqual(trusted, self.root)  # trusted measure, the base's held-out items, the lane's wording
        self.assertEqual((spec["question"]["instructions"], spec["field"], count), ("REWORDED: is it a bug?", "text", 10))
        self.assertEqual(spec["question"]["criteria"], {"true": "a bug", "false": "not a bug"})

    def test_the_lane_wording_is_read_from_its_commit_not_its_working_tree(self):
        lane = self.lane_with("committed wording")
        git = ["git", "-C", str(lane), "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
        subprocess.run(["git", "init", "-q", str(lane)], check=True)
        subprocess.run([*git, "add", "-A"], check=True)
        subprocess.run([*git, "commit", "-qm", "lane"], check=True)
        (lane / "contracts/jev/questions/x.q.json").write_text(json.dumps({**self.question, "instructions": "dirty wording"}))
        seen = []
        ae.run_jev_suite(self.root, ["x.q"], lambda t, spec, items: seen.append(spec) or (0, self.rows([0.95] * 5 + [0.05] * 5)),
                         target=lane, head="HEAD")
        self.assertEqual(seen[0]["question"]["instructions"], "committed wording")

    def trusted_with_fake_jev(self):
        """The trusted checkout gets a fake ``tools/jev_ask.py`` (positives answer high; a REWORDED question inverts)."""
        (self.root / "tools").mkdir(exist_ok=True)
        (self.root / "tools" / "jev_ask.py").write_text(
            "class A:\n    def __init__(self, p):\n        self.value = p >= 0.5\n        self.confidence = p\n"
            "        self.probabilities = {'true': p, 'false': 1 - p}\n        self.score = None\n"
            "def ask(q, state, tag=''):\n    p = 0.95 if state['text'] == 'pos' else 0.05\n"
            "    if 'REWORDED' in q['answer']['instructions']:\n        p = 1 - p\n    return {'answer': A(p)}\n")
        (self.root / "contracts/jev/derived/labels/x.q.jsonl").write_text("\n".join(
            json.dumps({"id": str(i), "text": "pos" if i < 5 else "neg", "label": i < 5, "split": "test"}) for i in range(10)))

    def committed_lane(self, hook_code=""):
        """A git lane: the base commit (tag ``base``) has the question as is, the lane commit rewords it (and appends
        ``hook_code`` to a hook tier 0 children load). Returns ``(lane, lane sha)``."""
        lane = make_target(self)
        (lane / "contracts" / "jev" / "questions").mkdir(parents=True, exist_ok=True)
        (lane / "contracts/jev/questions/x.q.json").write_text(json.dumps(self.question))
        git = ["git", "-C", str(lane), "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
        subprocess.run(["git", "init", "-q", str(lane)], check=True)
        subprocess.run([*git, "add", "-A"], check=True)
        subprocess.run([*git, "commit", "-qm", "base"], check=True)
        subprocess.run([*git, "tag", "base"], check=True)
        (lane / "contracts/jev/questions/x.q.json").write_text(json.dumps({**self.question, "instructions": "REWORDED: is it a bug?"}))
        if hook_code:
            patch_file(lane, "tools/hooks/stop_continue_guard.py", hook_code, append=True)
        subprocess.run([*git, "commit", "-qam", "lane"], check=True)
        sha = subprocess.run([*git, "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
        return lane, sha

    def worse_when_reworded(self):
        def fake(trusted, spec, items):
            if "REWORDED" in spec["question"]["instructions"]:
                return 0, self.rows([0.95] * 3 + [0.2] * 2 + [0.9, 0.9] + [0.05] * 3)
            return 0, self.rows([0.95] * 5 + [0.05] * 5)
        return fake

    def trusted_with_a_tier0_case(self):
        folder = self.root / "evals" / "agents" / "routing-replay" / "cases"
        folder.mkdir(parents=True)
        shutil.copy(REPLAY / "cases" / "stop-nightly-ill-wait.json", folder)

    def test_tier_one_inputs_are_captured_before_any_lane_code_runs(self):
        self.trusted_with_a_tier0_case()
        results = self.root / "contracts/jev/derived/results/x.q.v2.test.jsonl"
        labels = self.root / "contracts/jev/derived/labels/x.q.jsonl"
        # the lane's hook, run in a tier 0 child: resets the target's HEAD to the base, deletes the recorded results and
        # empties the held-out labels in the trusted root
        hook = ("\nimport os as _o, subprocess as _s, pathlib as _p\n"
                "_t = _p.Path(__file__).resolve().parents[2]\n"
                "_s.run(['git', '-C', str(_t), 'reset', '-q', '--hard', 'base'])\n"
                f"_o.path.exists({str(results)!r}) and _o.remove({str(results)!r})\n"
                f"open({str(labels)!r}, 'w').write('')\n")
        lane, sha = self.committed_lane(hook)
        suites = ae.evaluate(self.root, target=lane, base="base", measure=self.worse_when_reworded())
        by = {s["name"]: s for s in suites}
        self.assertEqual(by[ae.SUITE]["failures"], [])  # tier 0 itself is fine
        self.assertFalse(results.exists(), "the lane hook did run and delete the trusted results")
        self.assertEqual(subprocess.run(["git", "-C", str(lane), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
                         subprocess.run(["git", "-C", str(lane), "rev-parse", "base"], capture_output=True, text=True).stdout.strip())
        jev = by[ae.JEV_SUITE]
        self.assertIn("changed questions: x.q", jev["notes"][0])
        self.assertEqual((jev["cases"], jev["passed"]), (1, 0), jev)  # still measured, and failed for being worse
        self.assertIn("below the target", jev["failures"][0][1][0])

    def test_a_tier0_child_cannot_tamper_with_the_measurement_it_already_preceded(self):
        self.trusted_with_a_tier0_case()
        self.trusted_with_fake_jev()
        seen = self.root / "jev-home-seen"
        with open(self.root / "tools" / "jev_ask.py", "a") as handle:
            handle.write(f"\nimport os as _o\nopen({str(seen)!r}, 'a').write(_o.environ.get('JEV_HOME', '') + '\\n')\n")
        cache = self.root / "build" / "jev" / "cache"
        # a tier 0 child (the lane's hook) overwrites the trusted measure script and jev_ask so every answer is perfect,
        # and plants cache entries
        hook = ("\nimport pathlib as _p\n"
                f"_t = _p.Path({str(self.root)!r})\n"
                "(_t / 'tools' / 'agent_eval_measure.py').write_text('import sys\\nsys.exit(0)\\n')\n"
                "(_t / 'tools' / 'jev_ask.py').write_text('def ask(q, s, tag=\"\"):\\n    return None\\n')\n"
                f"_c = _p.Path({str(cache)!r})\n_c.mkdir(parents=True, exist_ok=True)\n(_c / 'planted.json').write_text('{{}}')\n")
        lane, _ = self.committed_lane(hook)
        suites = ae.evaluate(self.root, target=lane, base="base")  # the real default_measure: the trusted shim and jev_ask
        by = {s["name"]: s for s in suites}
        self.assertEqual(by[ae.SUITE]["failures"], [])
        self.assertIn("return None", (self.root / "tools" / "jev_ask.py").read_text())  # the child did run and tamper...
        self.assertTrue((cache / "planted.json").exists())
        jev = by[ae.JEV_SUITE]
        self.assertEqual((jev["cases"], jev["passed"]), (1, 0), jev)  # ...but tier 1 had already measured, with the real files
        self.assertIn("below the target", jev["failures"][0][1][0])  # the worse rewording is judged, not "Jev unavailable"
        homes = seen.read_text().split()
        self.assertTrue(homes and all("agent-eval-measure-" in h for h in homes), homes)  # a fresh temp JEV_HOME
        self.assertFalse(any(Path(h).is_relative_to(self.root) for h in homes), homes)

    def test_the_reviewed_sha_is_what_tier_one_reads(self):
        lane, sha = self.committed_lane()
        subprocess.run(["git", "-C", str(lane), "reset", "-q", "--hard", "base"], check=True)  # HEAD no longer the lane commit
        suites = ae.evaluate(self.root, target=lane, tier=1, base="base", target_sha=sha, measure=self.worse_when_reworded())
        self.assertEqual((suites[0]["cases"], suites[0]["passed"]), (1, 0))
        suites = ae.evaluate(self.root, target=lane, tier=1, base="base", measure=self.worse_when_reworded())
        self.assertEqual(suites[0]["cases"], 0)  # without the SHA the (reset) HEAD is the lane: nothing changed

    def test_a_changed_question_whose_id_is_not_its_file_name_fails(self):
        lane = self.lane_with("Is it a bug?")
        (lane / "contracts/jev/questions/x.q.json").write_text(json.dumps({**self.question, "id": "other.q"}))
        fake = self.measure(self.rows([0.95] * 5 + [0.05] * 5))
        suite = ae.run_jev_suite(self.root, ["x.q"], fake, target=lane)
        self.assertEqual((suite["cases"], suite["passed"]), (1, 0))
        self.assertIn("is not its file name", suite["failures"][0][1][0])
        self.assertEqual(fake.calls, [])  # never measured against another question's held-out set

    def test_trusted_code_measures_the_changed_question_and_a_shadowing_lane_module_has_no_effect(self):
        self.trusted_with_fake_jev()
        marker = self.root / "lane-code-ran"
        shadow = f"open({str(marker)!r}, 'w').write('x')\n"
        extra = {f"tools/{name}.py": shadow for name in ("hashlib", "http", "dataclasses", "json", "jev_ask", "agent_eval_measure")}
        extra["contracts/jev/derived/measure.py"] = shadow
        extra["sitecustomize.py"] = shadow
        good = ae.run_jev_suite(self.root, ["x.q"], target=self.lane_with("Is it a bug?", extra))
        self.assertEqual((good["cases"], good["passed"], good["failures"]), (1, 1, []))
        bad = ae.run_jev_suite(self.root, ["x.q"], target=self.lane_with("REWORDED: is it a bug?", extra))
        self.assertEqual((bad["cases"], bad["passed"]), (1, 0), bad)
        self.assertFalse(marker.exists(), "lane code ran in the measuring process")
        results = list((self.root / "contracts/jev/derived/results").glob("*"))
        self.assertEqual([p.name for p in results], ["x.q.v2.test.jsonl"])  # no tracked results file touched
        self.assertEqual(len(ae.read_rows(results[0])), 10)

    def test_jev_unavailable_in_the_measure_process_fails_closed(self):
        self.trusted_with_fake_jev()
        (self.root / "tools" / "jev_ask.py").write_text("def ask(q, state, tag=''):\n    return None\n")
        suite = ae.run_jev_suite(self.root, ["x.q"], target=self.lane_with("Is it a bug?"))
        self.assertIn("Jev is unavailable", suite["failures"][0][1][0])

    def test_unavailable_jev_fails_closed(self):
        suite = ae.run_jev_suite(self.root, ["x.q"], self.measure([], code=ae.EXIT_UNAVAILABLE))
        self.assertEqual(suite["passed"], 0)
        self.assertIn("Jev is unavailable", suite["failures"][0][1][0])

    def test_an_active_question_without_a_label_set_fails_closed(self):
        (self.root / "contracts/jev/questions/y.json").write_text(json.dumps({"id": "y", "version": 1, "type": "noul", "mode": "active"}))
        suite = ae.run_jev_suite(self.root, ["y"], self.measure([]))
        self.assertEqual((suite["cases"], suite["passed"]), (1, 0))
        self.assertEqual(suite["failures"][0][0], "tier1:y")
        self.assertIn("cannot be measured", suite["failures"][0][1][0])
        (self.root / "contracts/jev/questions/z.json").write_text(json.dumps({"id": "z", "version": 1, "type": "noul"}))
        self.assertEqual(ae.run_jev_suite(self.root, ["z"], self.measure([]))["passed"], 0)  # no mode counts as active

    def test_every_kind_of_unmeasurable_active_question_fails(self):
        derived = self.root / "contracts" / "jev" / "derived"
        (derived / "probes.json").write_text(json.dumps({"probes": [
            {"id": "w.v1", "labels": "labels/w.jsonl", "state_fields": ["t"]},
            {"id": "v.v1", "labels": "labels/v.jsonl", "state_fields": ["t"]}]}))
        (derived / "labels" / "w.jsonl").write_text(json.dumps({"id": "1", "label": True, "split": "train"}))  # nothing held out
        (derived / "labels" / "v.jsonl").write_text(json.dumps({"id": "1", "label": True, "split": "test"}))
        for qid, kind in (("w", "noul"), ("v", "choice")):
            (self.root / f"contracts/jev/questions/{qid}.json").write_text(json.dumps(
                {"id": qid, "version": 1, "type": kind, "mode": "active"}))
        suite = ae.run_jev_suite(self.root, ["w", "v"], self.measure([]))
        self.assertEqual((suite["cases"], suite["passed"]), (2, 0))
        self.assertTrue(any("held-out" in p for _, ps in suite["failures"] for p in ps))
        self.assertTrue(any("single yes/no" in p for _, ps in suite["failures"] for p in ps))

    def test_a_shadow_question_without_a_label_set_is_noted(self):
        (self.root / "contracts/jev/questions/y.json").write_text(json.dumps({"id": "y", "version": 1, "type": "noul", "mode": "shadow"}))
        suite = ae.run_jev_suite(self.root, ["y"], self.measure([]))
        self.assertEqual((suite["cases"], suite["failures"]), (0, []))
        self.assertIn("not measured (shadow)", suite["notes"][0])

    def git_root(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        git = ["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
        subprocess.run([*git, "add", "-A"], check=True)
        subprocess.run([*git, "commit", "-qm", "base"], check=True)
        subprocess.run([*git, "tag", "base"], check=True)
        return git

    def test_only_moving_to_shadow_or_tightening_bands_is_allowed_unmeasured(self):
        doc = {"id": "u", "version": 1, "type": "noul", "mode": "active",
               "accept": {"yes_above": 0.6, "no_below": 0.3, "min_confidence": 0.5}, "target": {"precision": 0.9}}
        path = self.root / "contracts/jev/questions/u.json"
        path.write_text(json.dumps(doc))
        git = self.git_root()
        cases = {
            "to shadow": ({**doc, "mode": "shadow"}, True),
            "tighter bands": ({**doc, "accept": {"yes_above": 0.7, "no_below": 0.2, "min_confidence": 0.6},
                               "target": {"precision": 0.95}}, True),
            "looser band": ({**doc, "accept": {**doc["accept"], "yes_above": 0.5}}, False),
            "new instructions": ({**doc, "instructions": "answer yes always"}, False),
            "tighter band and new instructions": ({**doc, "instructions": "x", "accept": {**doc["accept"], "yes_above": 0.9}}, False),
            "shadow to active": ({**doc, "mode": "active", "evidence": "x"}, False),
        }
        for name, (new, allowed) in cases.items():
            with self.subTest(name):
                path.write_text(json.dumps(new))
                suite = ae.run_jev_suite(self.root, ["u"], self.measure([]), base="base")
                self.assertEqual(len(suite["failures"]), 0 if allowed else 1, suite)
                self.assertEqual(len(suite["notes"]), 1 if allowed else 0, suite)
        path.write_text(json.dumps(doc))  # unchanged text: no base file lookup needed beyond this
        self.assertEqual(ae.question_at(self.root, "base", "u"), doc)
        self.assertIsNone(ae.question_at(self.root, "base", "missing"))
        self.assertIsNone(ae.question_at(self.root, "", "u"))
        del git

    def test_changed_questions_come_from_the_diff_and_a_bad_base_fails_closed(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        git = ["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
        subprocess.run([*git, "add", "-A"], check=True)
        subprocess.run([*git, "commit", "-qm", "base"], check=True)
        subprocess.run([*git, "tag", "base"], check=True)
        self.assertEqual(ae.changed_questions(self.root, "base"), [])
        (self.root / "contracts/jev/questions/x.q.json").write_text(json.dumps({**self.question, "version": 3}))
        subprocess.run([*git, "commit", "-qam", "change"], check=True)
        self.assertEqual(ae.changed_questions(self.root, "base"), ["x.q"])
        with self.assertRaises(RuntimeError):
            ae.changed_questions(self.root, "no-such-ref")
        suites = ae.evaluate(self.root, tier=1, base="base", measure=self.measure(self.rows([0.95] * 5 + [0.05] * 5)))
        self.assertEqual([s["name"] for s in suites], [ae.JEV_SUITE])
        self.assertEqual(suites[0]["passed"], 1)
        with self.assertRaises(ValueError):
            ae.evaluate(self.root, tier=1)  # no base: a usage error, never a silent pass
        code, _, err = run_main("--root", str(self.root), "--tier", "1", "--base", "no-such-ref")
        self.assertEqual(code, 2, err)


class Tier2Tests(unittest.TestCase):
    def make_root(self, cases, config=None):
        root = Path(tempfile.mkdtemp(prefix="eval-t2-"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        base = root / "evals" / "agents" / "agent-behaviour"
        (base / "cases").mkdir(parents=True)
        (base / "config.json").write_text(json.dumps(config or {"max_cases": 2, "max_cost_usd": 1.0, "model": "sonnet"}))
        for case in cases:
            (base / "cases" / f"{case['id']}.json").write_text(json.dumps(case))
        return root

    def test_disabled_cases_never_call_claude(self):
        calls = []
        root = self.make_root([{"id": "a", "enabled": False, "prompt": "p", "expect": {}}])
        suite = ae.run_behaviour_suite(root, lambda *a: calls.append(a) or {})
        self.assertEqual((suite["cases"], calls), (0, []))

    def test_the_shipped_examples_are_disabled(self):
        suite = ae.run_behaviour_suite(REPO, lambda *a: self.fail("spent money"))
        files = ae.case_files(REPO / "evals" / "agents" / "agent-behaviour" / "cases")
        self.assertGreaterEqual(len(files), 3)
        self.assertEqual(suite["cases"], 0)
        for path in files:
            self.assertIs(json.loads(path.read_text())["enabled"], False)

    def test_budget_caps_cases_and_cost_and_checks_the_answer(self):
        cases = [{"id": f"c{i}", "enabled": True, "prompt": "p", "expect": {"contains": ["yes"], "not_contains": ["wait"]}}
                 for i in range(3)]
        replies = iter([{"result": "yes", "total_cost_usd": 0.6}, {"result": "I wait", "total_cost_usd": 0.6},
                        {"result": "yes", "total_cost_usd": 0.0}])
        seen = []
        suite = ae.run_behaviour_suite(self.make_root(cases), lambda p, m, t: seen.append(m) or next(replies))
        self.assertEqual((suite["cases"], suite["passed"]), (2, 1))  # max_cases 2: the third is skipped
        self.assertEqual(seen, ["sonnet", "sonnet"])
        self.assertEqual([c for c, _ in suite["failures"]], ["c1"])
        self.assertTrue(any("c2: skipped" in n for n in suite["notes"]))
        root = self.make_root(cases, {"max_cases": 5, "max_cost_usd": 0.5})
        replies = iter([{"result": "yes", "total_cost_usd": 0.6}] * 3)
        suite = ae.run_behaviour_suite(root, lambda *a: next(replies))
        self.assertEqual(suite["cases"], 1)  # the cost cap stops further cases

    def test_tier_two_runs_trusted_cases_only(self):
        root = self.make_root([{"id": "a", "enabled": True, "prompt": "trusted prompt", "expect": {}}])
        lane = self.make_root([{"id": "a", "enabled": True, "prompt": "trusted prompt", "expect": {}},
                               {"id": "evil", "enabled": True, "prompt": "LANE PROMPT", "expect": {}}])
        prompts = []
        suite = ae.run_behaviour_suite(root, lambda p, m, t: prompts.append(p) or {"result": "ok", "total_cost_usd": 0.0}, lane)
        self.assertEqual(prompts, ["trusted prompt"])
        self.assertEqual(suite["cases"], 1)
        self.assertIn("evil: lane case not run: tier 2 runs trusted cases only", suite["notes"])
        # through evaluate(), and a lane-only case never sees claude even when the trusted set is empty
        suites = ae.evaluate(self.make_root([]), tier=2, target=lane, claude=lambda *a: self.fail("ran a lane case"))
        self.assertEqual(suites[0]["cases"], 0)
        self.assertTrue(any("lane case not run" in n for n in suites[0]["notes"]))

    def test_the_default_claude_call_has_no_tools_and_a_temp_cwd(self):
        seen = {}

        def fake_run(cmd, **kw):
            seen.update(cmd=cmd, cwd=kw["cwd"])
            return subprocess.CompletedProcess(cmd, 0, stdout='{"result": "x", "total_cost_usd": 0.1}', stderr="")
        with mock.patch.object(ae.subprocess, "run", fake_run):
            self.assertEqual(ae.default_claude("p", "sonnet", 5)["result"], "x")
        self.assertEqual(seen["cmd"][seen["cmd"].index("--tools") + 1], "")
        self.assertNotEqual(Path(seen["cwd"]).resolve(), REPO)


class LanderHookTests(unittest.TestCase):
    def load_lander(self):
        spec2 = importlib.util.spec_from_file_location("lane_land_for_eval", TOOLS / "lane_land.py")
        ll = importlib.util.module_from_spec(spec2)
        sys.modules["lane_land_for_eval"] = ll
        spec2.loader.exec_module(ll)
        self.addCleanup(sys.modules.pop, "lane_land_for_eval", None)
        return ll

    def stub_trees(self, tmp):
        lane, base = Path(tmp) / "lane", Path(tmp) / "base"
        for tree in (lane, base):
            (tree / "tools").mkdir(parents=True)
            (tree / "tools" / "agent_eval.py").write_text(
                "import os, sys\nprint('base=' + os.environ.get('FENTON_EVAL_BASE', '-'))\n"
                "print('argv=' + ' '.join(sys.argv[1:]))\nprint('\\nRan 1 tests in 0.001s\\n\\nOK')\n")
        return lane, base

    def test_the_lander_runs_the_trusted_harness_against_the_lane_and_gives_only_that_run_the_eval_base(self):
        ll = self.load_lander()
        with tempfile.TemporaryDirectory() as tmp:
            lane, base = self.stub_trees(tmp)
            seen = []
            real = ll._run_fixed

            def spy(tree, command, timeout, extra_env=None):
                code, out = real(tree, command, timeout, extra_env)
                if "agent_eval" in command:
                    seen.append((tree.name, command, out))
                return code, out
            with mock.patch.object(ll, "_run_fixed", spy):
                ll.run_tests(lane, "true", base_clone=base, base_key="k", base_counts={}, eval_base="refs/remotes/origin/main")
        (base_tree, base_command, base_out), (lane_tree, lane_command, lane_out) = seen
        self.assertEqual((base_tree, base_command), ("base", "python3 tools/agent_eval.py"))
        self.assertIn("base=-", base_out)
        self.assertEqual(lane_tree, "base")  # the lane's evaluation runs from the TRUSTED checkout...
        self.assertIn(str(base / "tools" / "agent_eval.py"), lane_command)
        self.assertIn(f"--target {lane}", lane_command)  # ...with the lane as the thing under test
        self.assertIn("base=refs/remotes/origin/main", lane_out)

    def test_the_eval_stage_comes_first_and_runs_in_a_freshly_reset_clone(self):
        ll = self.load_lander()
        with tempfile.TemporaryDirectory() as tmp:
            lane, base = self.stub_trees(tmp)
            env = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
            run = lambda *a: subprocess.run(["git", "-C", str(lane), *a], check=True, capture_output=True,
                                            env={**os.environ, **env})
            run("init", "-q")
            run("add", "-A")
            run("commit", "-qm", "lane")
            committed = run("rev-parse", "HEAD").stdout.decode().strip()
            (lane / "tools" / "agent_eval.py").write_text("tampered after the commit\n")  # a modified tracked file
            (lane / "junk.txt").write_text("untracked\n")
            (lane / "ignored.pyc").write_text("x")
            order = []
            real = ll._run_fixed

            heads = []

            def spy(tree, command, timeout, extra_env=None):
                if "agent_eval" in command and tree.name == "base" and "--target" in command:
                    heads.append((extra_env or {}).get("FENTON_EVAL_HEAD"))
                    order.append(("eval", (lane / "junk.txt").exists(), (lane / "tools" / "agent_eval.py").read_text()[:6]))
                elif command == "true":
                    order.append(("tests",))
                return real(tree, command, timeout, extra_env)
            with mock.patch.object(ll, "_run_fixed", spy):
                ll.run_tests(lane, "true", base_clone=base, base_key="k", base_counts={})
        # the trusted base's tests run first (before any lane code); then the lane's eval, clean; the lane's own tests last
        self.assertEqual(order, [("tests",), ("eval", False, "import"), ("tests",)])
        self.assertEqual(heads, [committed])  # the eval stage is given the SHA it was reset to

    def test_an_unclean_clone_is_refused_for_the_eval_stage(self):
        ll = self.load_lander()
        with tempfile.TemporaryDirectory() as tmp:
            lane, _ = self.stub_trees(tmp)
            with self.assertRaises(ll.Refused):
                ll.fresh_checkout(lane)  # not a git checkout at all: no commit to reset to


if __name__ == "__main__":
    unittest.main()
