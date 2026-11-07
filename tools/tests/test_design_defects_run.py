"""Selection, briefs, scoring and infra handling of evals/agents/design-defects/run.py (no git, no simulator)."""
import contextlib
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock
from pathlib import Path

HERE = Path(__file__).resolve()
SPEC = importlib.util.spec_from_file_location("dd_run", HERE.parents[2] / "evals/agents/design-defects/run.py")
run = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(run)


def case(cid, category="layout", app="swiftui", conf="high", pre="aaa", fix="bbb", poses=("iphone",)):
    return {"id": cid, "date": "2026-10-01", "source": "deadbeef", "owner_report": f"SECRET-REPORT-{cid}",
            "surface": None, "poses": list(poses), "app": app, "category": category, "pre_fix_ref": pre,
            "fix_ref": fix, "fix_confidence": conf, "expected": f"SECRET-EXPECTED-{cid}"}


CASES = [case(f"dd-l{i}") for i in range(5)] + [case(f"dd-s{i}", "sizing") for i in range(3)] + \
        [case("dd-n0", "navigation", "uikit", "medium"), case("dd-p0", "perf"), case("dd-x0", "motion", pre=None, fix=None, conf=None)]


class SelectTests(unittest.TestCase):
    def test_stratified_across_categories(self):
        picked = run.select_cases(CASES, limit=3, seed=1)
        self.assertEqual({c["category"] for c in picked}, {"layout", "sizing", "navigation"})

    def test_skips_null_refs_and_perf_by_default(self):
        ids = {c["id"] for c in run.select_cases(CASES)}
        self.assertNotIn("dd-x0", ids)
        self.assertNotIn("dd-p0", ids)

    def test_perf_when_asked(self):
        self.assertEqual([c["id"] for c in run.select_cases(CASES, category="perf")], ["dd-p0"])

    def test_filters(self):
        self.assertEqual([c["id"] for c in run.select_cases(CASES, app="uikit")], ["dd-n0"])
        self.assertEqual([c["id"] for c in run.select_cases(CASES, confidence="medium")], ["dd-n0"])

    def test_seed_is_deterministic(self):
        a = [c["id"] for c in run.select_cases(CASES, limit=4, seed=7)]
        self.assertEqual(a, [c["id"] for c in run.select_cases(CASES, limit=4, seed=7)])

    def test_real_cases_load(self):
        self.assertGreater(len(run.select_cases(run.load_cases(), confidence="high", app="swiftui", limit=4)), 0)


class BriefTests(unittest.TestCase):
    def test_designer_brief_never_leaks(self):
        c = case("dd-camera-live-badge", conf="high")
        c["fix_ref"], c["pre_fix_ref"] = "cc156f47", "e57d3182"
        with tempfile.TemporaryDirectory() as tmp:
            text = run.designer_brief(c, "pre", "run1", Path(tmp))
        for secret in (c["owner_report"], c["expected"], c["fix_ref"], c["pre_fix_ref"], c["id"], "category"):
            self.assertNotIn(secret, text)

    def test_case_dir_is_neutral(self):
        self.assertNotIn("camera", str(run.case_dir("r", "dd-camera-live-badge")))

    def test_grade_brief_has_report_expected_and_schema(self):
        c = case("dd-a")
        text = run.grade_brief(c, "pre", "run1")
        for need in (c["owner_report"], c["expected"], "flagged", "false_pass", "evidence_cited"):
            self.assertIn(need, text)
        self.assertNotIn(c["fix_ref"], text)


class LaneNameTests(unittest.TestCase):
    def test_worktree_name_does_not_name_the_defect(self):
        name = run.lane_name("dd-security-chips-left-align", "pre")
        self.assertTrue(name.startswith("dd-") and name.endswith("-pre"))
        self.assertNotIn("security", name)
        self.assertNotEqual(name, run.lane_name("dd-climate-chip-colour", "pre"))


class PathLeakTests(unittest.TestCase):
    """The Designer can reach the worktree, the pack-<ref> symlink target, the capture dirs and the manifest path
    `prepare` prints for the Verifier: none may carry the case slug."""

    def test_prepare_and_brief_paths_never_carry_the_slug(self):
        c = next(c for c in run.load_cases() if c["pre_fix_ref"] and c["fix_ref"] and c["poses"])
        slug = c["id"][3:]
        self.assertGreater(len(slug), 6)
        with tempfile.TemporaryDirectory() as tmp:
            repo, out = Path(tmp) / "repo", Path(tmp) / "out"
            repo.mkdir()
            real_case_dir = run.case_dir

            def fake_git(args, **kw):
                if "add" in args and "worktree" in args:
                    dest = Path(args[-2])
                    (dest / ".git").mkdir(parents=True, exist_ok=True)
                return subprocess.CompletedProcess(args, 0, "", "")

            args = SimpleNamespace(run="r1", case=c["id"], ref="pre")
            buf = io.StringIO()
            with mock.patch.object(run, "main_checkout", return_value=repo), \
                    mock.patch.object(run, "ref_exists", return_value=True), \
                    mock.patch.object(run.subprocess, "run", side_effect=fake_git), \
                    mock.patch.object(run, "OUT_ROOT", out), \
                    mock.patch.object(run, "case_dir", lambda r, cid, root=out: real_case_dir(r, cid, root)), \
                    contextlib.redirect_stdout(buf):
                run.cmd_prepare(args)
                run.cmd_brief(args)
                run.cmd_grade_brief(args)
                worktree = run.ensure_worktree(c, "pre", repo)
                commands = run.pose_commands(c, "pre", worktree)
            cdir = real_case_dir("r1", c["id"], out)
            texts = [buf.getvalue(), "\n".join(commands), str(worktree), (cdir / "prepare-pre.json").read_text(),
                     os.readlink(cdir / "pack-pre"), (cdir / "designer-brief-pre.md").read_text(),
                     str(cdir)] + [str(p) for p in out.rglob("*")]
            self.assertIn("manifest.json", os.readlink(cdir / "pack-pre") + buf.getvalue())
            gdir = run.grader_dir("r1", out)
            gdir.mkdir(parents=True, exist_ok=True)
            (gdir / "plan.json").write_text(json.dumps({"cases": [run.plan_entry(c)]}))
            self.assertTrue((run.grader_case_dir("r1", c["id"], out) / "grader-brief-pre.md").exists())
            self.assertFalse((run.run_dir("r1", out) / "plan.json").exists())
            visible = [p for p in run.run_dir("r1", out).rglob("*") if p.is_file() and not p.is_symlink()]
            self.assertTrue(visible)
            for f in visible:
                texts.append(f.read_text())
            for text in texts:
                for secret in (c["id"], slug, c["owner_report"], c["expected"], c["fix_ref"]):
                    self.assertNotIn(secret, text)
        for text in texts:
            self.assertNotIn(slug, text)
            self.assertNotIn(c["id"], text)
            self.assertNotIn(c["owner_report"], text)
            self.assertNotIn(c["expected"], text)
            self.assertNotIn(c["fix_ref"], text)


class ScoreTests(unittest.TestCase):
    def setUp(self):
        self.plan = [
            {"id": "dd-a", "category": "layout", "poses": ["iphone"], "app": "swiftui"},
            {"id": "dd-b", "category": "layout", "poses": ["iphone", "ipad-landscape"], "app": "uikit"},
            {"id": "dd-c", "category": "sizing", "poses": ["duo-folded"], "app": "uikit"},
            {"id": "dd-d", "category": "sizing", "poses": ["duo-folded"], "app": "uikit"},
            {"id": "dd-e", "category": "motion", "poses": ["iphone"], "app": "uikit"},
        ]

    def test_math_and_exclusions(self):
        grades = {"dd-a": {"label": "flagged"}, "dd-b": {"label": "partial"},
                  "dd-c": {"label": "false_pass"}, "dd-d": {"label": "infra", "infra_class": "devcap-timeout"}}
        agg = run.aggregate(self.plan, grades)
        self.assertEqual(agg["scored_cases"], 3)
        self.assertAlmostEqual(agg["headline"], 0.5)  # (1 + 0.5 + 0) / 3
        self.assertEqual(agg["false_pass"], 1)
        self.assertEqual(agg["infra"], [{"case": "dd-d", "infra_class": "devcap-timeout"}])
        self.assertEqual(agg["by_category"]["layout"], {"cases": 2, "score": 0.75})
        self.assertEqual(agg["by_pose"]["iphone"]["cases"], 2)
        self.assertEqual(agg["by_app"]["uikit"]["cases"], 2)

    def test_no_scored_cases(self):
        self.assertIsNone(run.aggregate(self.plan, {"dd-a": {"label": "infra"}})["headline"])

    def test_build_score_reads_grades_and_lists_ungraded(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            run.grader_dir("r1", out).mkdir()
            (run.grader_dir("r1", out) / "plan.json").write_text(json.dumps({"cases": self.plan}))
            g = run.grader_case_dir("r1", "dd-a", out) / "pre"
            g.mkdir(parents=True)
            (g / "grade.json").write_text(json.dumps({"case": "dd-a", "label": "flagged", "score": 1.0}))
            f = run.grader_case_dir("r1", "dd-a", out) / "fix"
            f.mkdir()
            (f / "grade.json").write_text(json.dumps({"case": "dd-a", "label": "false_alarm"}))
            result, md = run.build_score("r1", out)
        self.assertEqual(result["headline"], 1.0)
        self.assertEqual(len(result["ungraded"]), 4)
        self.assertEqual(result["fix_ref"]["false_alarm"], 1)
        self.assertIn("Not yet graded", md)


if __name__ == "__main__":
    unittest.main()
