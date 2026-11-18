"""tools/state_space/lint.py over generic fixtures: empty and partial maps, reachable fallbacks, unread helpers; counts-only reports."""

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from state_space_loader import load

lint = load("state_space_lint", "tools/state_space/lint.py")


def device(node_id, states, fallback="Unknown", kind="device", extra=None):
    props = {"kind": kind, "states": [{"value": v, "label": v.title()} for v in states], "fallbackText": fallback}
    props.update(extra or {})
    return {"id": node_id, "type": "remote-control", "props": props}


def publication(components, sources=None, extra=None):
    document = {"pages": [{"id": "p", "components": components}], "dataSources": sources or []}
    document.update(extra or {})
    return {"envelopeVersion": 2, "document": document}


def rules(findings):
    return sorted(f["rule"] for f in findings)


class SlotRuleTests(unittest.TestCase):
    def test_an_empty_map_with_a_constant_fallback_is_high(self):
        found = lint.lint(publication([device("d1", [])]))
        self.assertEqual(rules(found), ["empty-map"])
        self.assertEqual(found[0]["severity"], "high")

    def test_a_partial_device_map_is_flagged_with_what_is_missing(self):
        found = lint.lint(publication([device("d1", ["on"], fallback="Player")]))
        self.assertEqual(rules(found), ["partial-map"])
        self.assertIn("off", found[0]["detail"])

    def test_a_complete_device_map_with_a_plain_fallback_is_clean(self):
        self.assertEqual(lint.lint(publication([device("d1", ["on", "off"], fallback="Player")])), [])

    def test_a_failure_word_fallback_on_a_complete_map_is_a_low_finding(self):
        found = lint.lint(publication([device("d1", ["on", "off"], fallback="Unavailable")]))
        self.assertEqual(rules(found), ["reachable-fallback"])
        self.assertEqual(found[0]["severity"], "low")

    def test_a_card_is_treated_like_a_device(self):
        self.assertEqual(rules(lint.lint(publication([device("c1", [], kind="card")]))), ["empty-map"])

    def test_a_projection_slot_takes_its_text_from_native_and_is_skipped(self):
        node = {"id": "s", "type": "status-pill", "props": {"status": {"projection": "recommendation", "states": [], "fallbackText": "Unknown"}}}
        self.assertEqual(lint.lint(publication([node])), [])

    def test_an_empty_fallback_is_not_a_constant_word(self):
        self.assertEqual(lint.lint(publication([device("d1", [], fallback="")])), [])

    def test_nested_children_are_walked(self):
        parent = {"id": "g", "type": "tile-grid", "props": {}, "children": [device("d1", [])]}
        self.assertEqual(rules(lint.lint(publication([parent]))), ["empty-map"])

    def test_a_non_device_slot_with_states_is_not_partial(self):
        node = {"id": "x", "type": "info-box", "props": {"kind": "text", "slot": {"states": [{"value": "a", "label": "A"}], "fallbackText": "Other"}}}
        self.assertEqual(lint.lint(publication([node])), [])


class HelperRuleTests(unittest.TestCase):
    def test_a_data_source_nothing_reads_is_unread(self):
        sources = [{"id": "used", "kind": "model"}, {"id": "orphan", "kind": "model"}]
        node = {"id": "n", "type": "text", "binding": {"sourceId": "used"}, "props": {}}
        found = lint.lint(publication([node], sources))
        self.assertEqual([f["rule"] for f in found], ["unread-helper"])
        self.assertEqual(found[0]["path"], "/dataSources/1")

    def test_a_source_read_by_another_source_counts_as_read(self):
        sources = [{"id": "a", "kind": "model", "inputs": {"from": "b"}}, {"id": "b", "kind": "model"}]
        node = {"id": "n", "type": "text", "binding": {"sourceId": "a"}, "props": {}}
        self.assertEqual(lint.lint(publication([node], sources)), [])

    def test_a_helper_the_old_layout_read_but_the_publication_never_mentions(self):
        node = device("d1", ["on", "off"], fallback="Player", extra={"entity": "input_boolean.demo_power"})
        found = lint.lint(publication([node]), helpers=["input_text.demo_power_state", "input_boolean.demo_power"])
        self.assertEqual(rules(found), ["unread-helper"])
        self.assertIn("input_text.demo_power_state", found[0]["detail"])


class ReportTests(unittest.TestCase):
    def test_the_report_names_no_node_page_or_entity(self):
        node = device("secret-node-id", [], extra={"title": "Private Title"})
        data = publication([node], [{"id": "orphan-source", "kind": "model"}])
        text = lint.report(lint.lint(data, helpers=["input_text.private_helper"]), lint.count_nodes(data))
        for private in ("secret-node-id", "Private Title", "orphan-source", "private_helper"):
            self.assertNotIn(private, text)
        self.assertIn("| empty-map | high | 1 |", text)
        self.assertIn("| empty-map | remote-control | device | 1 |", text)

    def test_counts_and_exit_status_through_main(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "pub.json"
            path.write_text(json.dumps(publication([device("d1", []), device("d2", ["on"])])))
            out = Path(tmp) / "report.md"
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(lint.main([str(path), "--report", str(out), "--json"]), 1)
            self.assertIn("partial-map", out.read_text())
            clean = Path(tmp) / "clean.json"
            clean.write_text(json.dumps(publication([device("d1", ["on", "off"], fallback="Player")])))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(lint.main([str(clean), "--json"]), 0)

    def test_a_bare_document_is_accepted(self):
        document = publication([device("d1", [])])["document"]
        self.assertEqual(rules(lint.lint(document)), ["empty-map"])

    def test_the_corpus_fixture_with_a_listed_device_is_clean_of_empty_maps(self):
        fixture = Path(__file__).resolve().parents[2] / "apple/Tests/HassCoreTests/ContractCorpus/accept/fixture-remote-composition.json"
        found = lint.lint(json.loads(fixture.read_text(encoding="utf-8")))
        self.assertNotIn("empty-map", rules(found))


if __name__ == "__main__":
    unittest.main()
