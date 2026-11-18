"""tools/state_space/generate.py: the state space is deterministic, generic and sized per tile kind."""

import json
import tempfile
import unittest
from pathlib import Path

from state_space_loader import ROOT, load

gen = load("state_space_generate", "tools/state_space/generate.py")
KINDS = ROOT / "tools/state_space/kinds.json"
HA = ROOT / "tools/state_space/ha-states-2026.11.0.json"
OBSERVED = ROOT / "tools/state_space/observed-text.json"
OUT = ROOT / "apple/Tests/HassCoreTests/StateGolden/state-space.json"


class DocumentTests(unittest.TestCase):
    def setUp(self):
        self.doc = gen.document(KINDS, HA, OBSERVED)

    def test_the_checked_in_file_is_what_the_inputs_generate(self):
        self.assertEqual(OUT.read_text(encoding="utf-8"), gen.render(self.doc), "run tools/state_space/generate.py")

    def test_check_flag_reports_a_stale_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            stale = Path(tmp) / "space.json"
            stale.write_text("{}", encoding="utf-8")
            self.assertEqual(gen.main(["--check", "--out", str(stale)]), 1)
            self.assertEqual(gen.main(["--check"]), 0)

    def test_row_ids_are_unique_and_named_by_kind_selector_state(self):
        ids = [r["id"] for r in self.doc["rows"]]
        self.assertEqual(len(ids), len(set(ids)))
        for row in self.doc["rows"]:
            self.assertTrue(row["id"].startswith(f"{row['kind']}.{row['selector']}."))

    def test_every_kind_has_rows_and_the_universal_states(self):
        sizes = self.doc["per_kind"]
        kinds = json.loads(KINDS.read_text(encoding="utf-8"))["kinds"]
        self.assertEqual(set(sizes), {k["id"] for k in kinds})
        for kind in kinds:
            for variant in kind["variants"]:
                tokens = {r["id"].rsplit(".", 1)[1] for r in self.doc["rows"] if r["kind"] == kind["id"] and r["selector"] == variant["selector"]}
                self.assertTrue({"unavailable", "unknown", "missing"} <= tokens, kind["id"])

    def test_closed_sets_come_from_the_ha_file(self):
        ha = json.loads(HA.read_text(encoding="utf-8"))
        lock = {r["state"] for r in self.doc["rows"] if r["kind"] == "style-lock" and r["class"] in ("content", "transitional")}
        self.assertEqual(lock, set(ha["sets"]["lock"]["states"]))
        self.assertEqual(len(lock), 7)
        transitional = {r["state"] for r in self.doc["rows"] if r["kind"] == "style-lock" and r["class"] == "transitional"}
        self.assertEqual(transitional, {"opening", "locking", "unlocking"})

    def test_missing_entity_is_a_null_state(self):
        missing = [r for r in self.doc["rows"] if r["class"] == "missing"]
        self.assertTrue(missing)
        self.assertTrue(all(r["state"] is None for r in missing))

    def test_ids_are_demo_ids_only(self):
        for row in self.doc["rows"]:
            self.assertRegex(row["entity_id"], r"^[a-z_]+\.demo_[a-z0-9_]+$")


class FreeTextTests(unittest.TestCase):
    def test_observed_values_become_free_text_rows_and_empty_is_one_too(self):
        doc = gen.document(KINDS, HA, OBSERVED)
        rows = [r for r in doc["rows"] if r["kind"] == "room-power" and r["selector"] == "helper"]
        self.assertEqual({r["class"] for r in rows}, {"free-text", "unavailable", "unknown"})
        self.assertIn("room-power.helper.empty", {r["id"] for r in rows})

    def test_a_real_observed_file_changes_only_the_rows_not_the_repo_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            observed = Path(tmp) / "observed.json"
            observed.write_text(json.dumps({"schema": 1, "helpers": {"demo_power_status": {"values": ["Alpha", "Beta..."], "unreviewed": ["Beta..."]}}}))
            doc = gen.document(KINDS, HA, observed)
        rows = {r["id"]: r for r in doc["rows"]}
        self.assertTrue(rows["room-power.helper.alpha"]["reviewed"])
        self.assertFalse(rows["room-power.helper.beta"]["reviewed"])
        self.assertNotIn("room-power.helper.empty", rows)

    def test_two_values_that_slug_alike_fail_loudly(self):
        with tempfile.TemporaryDirectory() as tmp:
            observed = Path(tmp) / "observed.json"
            observed.write_text(json.dumps({"helpers": {"demo_power_status": {"values": ["a b", "a-b"]}}}))
            with self.assertRaises(SystemExit):
                gen.document(KINDS, HA, observed)

    def test_the_checked_in_observed_file_holds_placeholders_only(self):
        data = json.loads(OBSERVED.read_text(encoding="utf-8"))
        for name, spec in data["helpers"].items():
            self.assertTrue(name.startswith("demo_"), name)
            for value in spec["values"]:
                self.assertIn("demo", value.lower(), value)


class HaDiffTests(unittest.TestCase):
    def test_a_new_state_is_an_unreviewed_row(self):
        old = {"ha_tag": "a", "sets": {"lock": {"states": ["locked"]}}}
        new = {"ha_tag": "b", "sets": {"lock": {"states": ["locked", "tamper"]}, "cover": {"states": ["open"]}}}
        added = gen.ha_diff(old, new)
        self.assertEqual({(a["set"], a["state"]) for a in added}, {("lock", "tamper"), ("cover", "open")})
        self.assertTrue(all(a["reviewed"] is False for a in added))
        self.assertEqual(gen.ha_diff(new, new), [])


if __name__ == "__main__":
    unittest.main()
