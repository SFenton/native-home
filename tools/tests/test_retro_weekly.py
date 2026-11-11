"""``tools/retro_weekly.py`` on fixture archives. No network, deterministic."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import retro_weekly as rw  # noqa: E402

NOW = datetime(2026, 11, 9, 12, 0, tzinfo=timezone.utc)


class Fixture(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="retro-weekly-"))
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.archive = self.dir / "archive"
        self.repo = self.dir / "repo"
        self.repo.mkdir()

    def put(self, path, data, days_ago=1):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data if isinstance(data, str) else json.dumps(data))
        stamp = (NOW - timedelta(days=days_ago)).timestamp()
        os.utime(path, (stamp, stamp))
        return path

    def flow(self, name, task, triggers=(), tokens=0, minutes=0, replies=0, days_ago=1):
        data = {"task": task, "triggers": [{"id": t, "evidence": ["e"]} for t in triggers],
                "counts": {"owner_replies": replies}, "cost": {"tokens": tokens}, "durations": {"minutes": minutes}}
        self.put(self.archive / name / "retro" / f"{task}.json", data, days_ago)

    def doc(self, **kw):
        return rw.build(rw.collect(self.archive, self.repo, None), NOW, rw.parse_since("7d", NOW))


class WeeklyTests(Fixture):
    def test_flow_metrics(self):
        self.flow("request-1", "R-1", [], tokens=1000, minutes=10)
        self.flow("request-2", "R-2", ["owner_correction", "routing_override"], tokens=3000, minutes=30, replies=2)
        self.flow("nightly-3", "N-3", ["blocked"], tokens=2000, minutes=20)
        self.flow("request-4", "R-4", ["owner_correction"], days_ago=30)  # outside the window
        m = self.doc()["metrics"]
        self.assertEqual((m["flows"], m["flows_without_nudge"]), (3, 2))
        self.assertEqual((m["owner_corrections"], m["corrections_per_task"]), (2, 0.67))
        self.assertEqual(m["routing_overrides"], 1)
        self.assertEqual((m["tokens_per_task"], m["minutes_per_task"]), (2000.0, 20.0))
        self.assertEqual(m["triggers"], {"blocked": 1, "owner_correction": 1, "routing_override": 1})
        self.assertEqual([r["task"] for r in m["tasks"]], ["N-3", "R-1", "R-2"])

    def test_a_t3_flow_with_unknown_tokens_is_unknown_not_zero(self):
        """Fails if: the weekly row turns a T3 flow's null tokens into 0."""
        self.flow("request-1", "R-1", tokens=None, minutes=10)
        self.flow("request-2", "R-2", tokens=3000, minutes=10)
        m = self.doc()["metrics"]
        self.assertEqual([r["tokens"] for r in m["tasks"]], [None, 3000])
        self.assertEqual(m["tokens_per_task"], 3000.0)

    def test_jobs_and_retros_are_not_flows(self):
        self.flow("job-steward-2026-11-08", "job-steward-2026-11-08", ["blocked"])
        self.flow("retro-request-1", "retro-R-1", [])
        self.flow("request-1", "R-1")
        m = self.doc()["metrics"]
        self.assertEqual((m["flows"], m["other_runs"]), (1, 2))

    def test_review_findings_per_pr(self):
        for branch, n in (("a", 3), ("b", 1)):
            self.put(self.archive / "request-1" / "review" / f"{branch}.json",
                     {"branch": branch, "findings": [{"severity": "minor"}] * n})
        self.assertEqual(self.doc()["metrics"]["review_findings_per_pr"], 2.0)

    def test_self_change_merges_and_reverts(self):
        self.put(self.archive / "retro-request-1" / "retro" / "R-1.status.json",
                 {"state": "done", "merged": ["a", "b"], "actions": [{"status": "reverted"}]})
        self.put(self.archive / "retro-request-2" / "retro" / "R-2.status.json",
                 {"actions": [{"status": "merged"}, {"status": "merged"}, {"status": "proposed"}]})
        m = self.doc()["metrics"]
        self.assertEqual((m["self_change_merges"], m["self_change_reverts"]), (4, 1))

    def test_owner_rule_repeats_are_counted_with_a_trend(self):
        self.put(self.archive / "retro-request-1" / "retro" / "R-1.status.json",
                 {"state": "done", "owner_rules_broken": ["no polling", "propose first"]})
        self.put(self.archive / "retro-request-2" / "retro" / "R-2.status.json", {"owner_rules_broken": ["x"]})
        self.put(self.archive / "retro-request-3" / "retro" / "R-3.status.json", {"owner_rules_broken": ["old"]}, days_ago=10)
        self.put(self.archive / "retro-request-4" / "retro" / "R-4.status.json", {"owner_rules_broken": "bad"})
        doc = self.doc()
        self.assertEqual(doc["metrics"]["owner_rule_repeats"], 3)
        self.assertEqual(doc["trend"]["owner_rule_repeats"]["before"], 1)
        self.assertEqual(doc["trend"]["owner_rule_repeats"]["direction"], "worse")
        self.assertIn("Repeats of a rule the owner already gave: 3", rw.render_md(doc))

    def test_retirements_counted_from_retired_folders(self):
        self.put(self.repo / "evals" / "routing" / "retired" / "case1.json", {}, 1)
        self.put(self.repo / "evals" / "routing" / "retired" / "case2.json", {}, 20)
        self.put(self.repo / "evals" / "routing" / "retired" / "README.md", "x", 1)
        self.put(self.repo / "evals" / "routing" / "live" / "case3.json", {}, 1)
        doc = self.doc()
        self.assertEqual((doc["retirements_total"], doc["metrics"]["retirements_in_window"]), (2, 1))

    def test_repo_build_retro_digests_and_dedupe(self):
        self.flow("request-1", "R-1", ["blocked"], days_ago=2)
        self.put(self.repo / "build" / "retro" / "R-1.json", {"task": "R-1", "triggers": []}, 1)  # newer copy wins
        self.put(self.repo / "build" / "retro" / "R-9.json", {"task": "R-9", "triggers": []}, 1)
        self.put(self.repo / "build" / "retro" / "notes.json", {"x": 1}, 1)  # not a digest
        self.put(self.repo / "build" / "retro" / "weekly-2026-11-02.json", {"triggers": []}, 1)  # our own output
        self.assertEqual(self.doc()["metrics"]["flows"], 2)

    def test_trend_against_the_previous_window(self):
        self.flow("request-1", "R-1", ["owner_correction"], tokens=100, replies=1, days_ago=10)
        self.flow("request-2", "R-2", [], tokens=50, days_ago=1)
        t = self.doc()["trend"]
        self.assertEqual(t["corrections_per_task"]["direction"], "better")
        self.assertEqual(t["tokens_per_task"]["direction"], "better")
        self.assertEqual(t["flows_without_nudge"]["direction"], "better")

    def test_empty_and_bad_inputs(self):
        self.put(self.archive / "request-1" / "retro" / "bad.json", "{not json")
        doc = rw.build(rw.collect(self.dir / "missing", None, None), NOW, rw.parse_since("7d", NOW))
        self.assertEqual(doc["metrics"]["flows"], 0)
        self.assertEqual(self.doc()["metrics"]["flows"], 0)

    def test_parse_since(self):
        self.assertEqual(rw.parse_since("48h", NOW), NOW - timedelta(hours=48))
        self.assertEqual(rw.parse_since("2026-11-01", NOW), datetime(2026, 11, 1, tzinfo=timezone.utc))

    def test_cli_writes_md_and_json_deterministically(self):
        self.flow("request-1", "R-1", ["blocked"], tokens=10, minutes=1)
        out = self.dir / "out"
        argv = [sys.executable, str(TOOLS / "retro_weekly.py"), "--archive", str(self.archive), "--repo", str(self.repo),
                "--out", str(out), "--now", NOW.isoformat()]
        subprocess.run(argv, check=True, capture_output=True)
        first = (out / "weekly-2026-11-09.json").read_text()
        subprocess.run(argv, check=True, capture_output=True)
        self.assertEqual(first, (out / "weekly-2026-11-09.json").read_text())
        self.assertIn("| R-1 |", (out / "weekly-2026-11-09.md").read_text())

class OwnerRuleTests(Fixture):
    def broken(self, name, entries, days_ago=1):
        self.put(self.archive / name / "retro" / "x.status.json", {"owner_rules_broken": entries}, days_ago)

    def test_entries_are_listed_with_source_date_and_quote_and_repeats_counted(self):
        rule = {"rule": "Propose first", "source_date": "2026-10-23", "quote": "mockups first", "run": "R-1"}
        self.broken("retro-request-1", [rule, {"rule": "no polling", "source_date": "2026-10-20", "quote": "never poll"}])
        self.broken("retro-request-2", [dict(rule, run="R-2", rule="propose  FIRST")])
        rules = self.doc()["metrics"]["owner_rules"]
        self.assertEqual([(r["rule"], r["count"]) for r in rules], [("Propose first", 2), ("no polling", 1)])
        self.assertEqual([e["run"] for e in rules[0]["entries"]], ["R-1", "R-2"])
        self.assertEqual(rules[0]["entries"][0]["quote"], "mockups first")

    def test_the_digest_leads_with_a_rule_broken_twice(self):
        e = {"rule": "Propose first", "source_date": "2026-10-23", "quote": "mockups first", "run": "R-1"}
        self.broken("retro-request-1", [e, {"rule": "one-off", "source_date": "2026-10-01", "quote": "q"}])
        self.broken("retro-request-2", [e])
        md = rw.render_md(self.doc())
        self.assertLess(md.index("Owner rules broken again"), md.index("| Metric |"))
        self.assertIn("Propose first: broken 2 times", md)
        self.assertIn('2026-10-23: "mockups first"', md)
        self.assertIn("## Owner rules broken once", md)
        self.assertIn("one-off (2026-10-01", md)

    def test_no_section_without_a_repeat_and_bare_strings_count(self):
        self.broken("retro-request-1", ["bare rule", "", {"quote": "no rule"}])
        md = rw.render_md(self.doc())
        self.assertNotIn("broken again", md)
        self.assertIn("bare rule (undated", md)


class RuleSurfaceLineTests(Fixture):
    def test_the_rule_surface_lines_are_report_only_and_optional(self):
        """Fails if: the roll-up drops the rule-surface numbers when present, or needs them to render."""
        self.assertNotIn("Rule surface", rw.render_md(self.doc()))
        doc = self.doc()
        doc["rule_surface"] = {"rule_surface_words": 900, "layers": {"core": {"files": 1, "words": 500}},
                               "role_load": {".claude/agents/coder.md": 3000}}
        md = rw.render_md(doc)
        self.assertIn("Rule surface (report only): 900 words; core 500", md)
        self.assertIn("coder 3000", md)

    def test_no_contract_means_no_numbers(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(rw.rule_surface(Path(tmp)), {})


class RegressionTests(Fixture):
    def at(self, days_ago):
        return NOW - timedelta(days=days_ago)

    def test_windows_take_the_n_flows_each_side_of_a_moment(self):
        for i in range(5):
            self.flow(f"request-{i}", f"R-{i}", ["owner_correction"] if i < 2 else [], replies=1, tokens=100, days_ago=20 - i)
        for i in range(5, 9):
            self.flow(f"request-{i}", f"R-{i}", [], tokens=300, days_ago=20 - i)
        records = rw.collect(self.archive, None, None)
        landed = self.at(20 - 4.5)
        before = rw.flow_window(records, landed, 3, after=False)
        after = rw.flow_window(records, landed, 3, after=True)
        self.assertEqual([r["task"] for r in before["tasks"]], ["R-2", "R-3", "R-4"])
        self.assertEqual([r["task"] for r in after["tasks"]], ["R-5", "R-6", "R-7"])
        self.assertEqual((before["tokens_per_task"], after["tokens_per_task"]), (100.0, 300.0))
        self.assertEqual(rw.flow_window(records, self.at(0), 3, after=True)["flows"], 0)

    def test_two_worse_beyond_the_margin_regress_and_within_it_do_not(self):
        before = {"corrections_per_task": 1.0, "tokens_per_task": 1000.0, "review_findings_per_pr": 2.0,
                  "nudged_flows_rate": 0.0, "routing_overrides_rate": 0.1, "owner_rule_repeats_rate": 0.0}
        after = dict(before, corrections_per_task=1.25, tokens_per_task=1100.0, routing_overrides_rate=0.11,
                     owner_rule_repeats_rate=0.1, review_findings_per_pr=1.0)
        worse = rw.regressions(before, after, 0.2)
        self.assertEqual([w["metric"] for w in worse], ["corrections_per_task", "owner_rule_repeats_rate"])
        self.assertEqual(worse[0]["change_pct"], 25.0)
        self.assertIsNone(worse[1]["change_pct"])  # from zero
        self.assertEqual(rw.regressions(before, before, 0.2), [])

    def test_revert_view_is_per_flow(self):
        self.flow("request-1", "R-1", ["owner_correction", "routing_override"], replies=2, tokens=10)
        self.flow("request-2", "R-2", [], tokens=30)
        view = rw.revert_view(self.doc()["metrics"])
        self.assertEqual((view["nudged_flows_rate"], view["routing_overrides_rate"]), (0.5, 0.5))
        self.assertEqual(view["tokens_per_task"], 20.0)
        self.assertEqual(rw.revert_view(rw.metrics({"digests": [], "reviews": [], "outputs": [], "retired": []}, NOW, NOW))
                         ["corrections_per_task"], 0.0)


if __name__ == "__main__":
    unittest.main()
