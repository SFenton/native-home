"""Tests for tools/house_config_patch.py with a fixture registry and the DemoHouse document (no live server, no real values)."""
from __future__ import annotations

import contextlib
import copy
import io
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import house_config_patch as hcp  # noqa: E402

DOCUMENT_SWIFT = ROOT / "apple/Sources/HassDemoHouse/DemoHouseDocument.swift"


def demo_document() -> dict:
    text = DOCUMENT_SWIFT.read_text()
    return json.loads(re.search(r'"""\n(.*?)\n\s*"""', text, re.S).group(1))


def stripped() -> dict:
    """The demo document as the live server has it: none of the new optional fields."""
    document = demo_document()
    for room in document["climate"]["rooms"]:
        room.pop("occupiedOnlyEntityId", None)
    for purifier in document["roomDevices"]["airPurifiers"]:
        for field in hcp.PURIFIER_FIELDS:
            purifier.pop(field, None)
    return document


def fixture_registry(document: dict) -> tuple:
    """Entity, device and area lists shaped like Home Assistant's registries, with fixture names unlike the demo document's."""
    entities, devices = [], []
    for index, room in enumerate(document["climate"]["rooms"]):
        key = hcp.room_key(room["title"])
        entities.append({"entity_id": f"switch.demo_fixture_hub_{key}_only_when_occupied", "original_name": f"{room['title']} Only When Occupied",
                         "device_id": "hub", "area_id": "hub_area"})
    for index, purifier in enumerate(document["roomDevices"]["airPurifiers"]):
        base = hcp.purifier_base(purifier["pm25EntityId"])
        device = f"dev{index}"
        entities += [
            {"entity_id": purifier["pm25EntityId"], "device_id": device},
            {"entity_id": f"sensor.{base}_air_quality_index", "device_id": device},
            {"entity_id": f"select.{base}_auto_mode", "device_id": device},
            {"entity_id": f"select.{base}_fan_mode", "device_id": device},
            {"entity_id": f"fan.demo_fixture_{index}_unit", "device_id": device},
        ]
    return entities, [{"id": "hub", "area_id": "hub_area"}], [{"area_id": "hub_area", "name": "Fixture Hall"}]


def registry_for(document: dict) -> "hcp.Registry":
    return hcp.Registry(*fixture_registry(document))


class RegistryTests(unittest.TestCase):
    def test_a_fan_is_the_single_fan_on_the_sensors_device(self):
        registry = hcp.Registry([{"entity_id": "sensor.demo_a", "device_id": "d"}, {"entity_id": "fan.demo_x", "device_id": "d"},
                                 {"entity_id": "fan.demo_y", "device_id": "other"}])
        self.assertEqual(registry.fan_on_device_of("sensor.demo_a"), "fan.demo_x")

    def test_two_fans_or_no_device_or_an_unknown_sensor_answer_none(self):
        two = hcp.Registry([{"entity_id": "sensor.demo_a", "device_id": "d"}, {"entity_id": "fan.demo_x", "device_id": "d"},
                            {"entity_id": "fan.demo_y", "device_id": "d"}])
        self.assertIsNone(two.fan_on_device_of("sensor.demo_a"))
        self.assertIsNone(hcp.Registry([{"entity_id": "sensor.demo_a"}]).fan_on_device_of("sensor.demo_a"))
        self.assertIsNone(two.fan_on_device_of("sensor.demo_missing"))

    def test_disabled_entities_are_not_in_the_registry(self):
        registry = hcp.Registry([{"entity_id": "fan.demo_x", "disabled_by": "user"}, {"entity_id": "fan.demo_y"}])
        self.assertEqual(registry.ids, {"fan.demo_y"})

    def test_the_switch_is_matched_by_registry_name_first(self):
        registry = hcp.Registry([
            {"entity_id": "switch.demo_t_a_occupied", "original_name": "Room A Only When Occupied"},
            {"entity_id": "switch.demo_t_b_occupied", "original_name": "Room B Only When Occupied"},
        ])
        self.assertEqual(registry.occupied_switch("Room B", "room_b"), "switch.demo_t_b_occupied")

    def test_the_switch_falls_back_to_the_area_then_the_key(self):
        by_area = hcp.Registry([{"entity_id": "switch.demo_one_occupied", "area_id": "a1"}, {"entity_id": "switch.demo_two_occupied", "area_id": "a2"}],
                               areas=[{"area_id": "a1", "name": "Room A"}, {"area_id": "a2", "name": "Room B"}])
        self.assertEqual(by_area.occupied_switch("Room B", "room_b"), "switch.demo_two_occupied")
        by_key = hcp.Registry([{"entity_id": "switch.demo_room_a_occupied"}, {"entity_id": "switch.demo_room_b_occupied"}])
        self.assertEqual(by_key.occupied_switch("Room B", "room_b"), "switch.demo_room_b_occupied")

    def test_an_ambiguous_or_missing_switch_is_none(self):
        both = hcp.Registry([{"entity_id": "switch.demo_room_x_occupied"}, {"entity_id": "switch.demo_room_x_two_occupied"}])
        self.assertIsNone(both.occupied_switch("Room X", "room_x"))
        self.assertIsNone(both.occupied_switch("Room Q", "room_q"))


class PatchTests(unittest.TestCase):
    def test_every_missing_field_is_filled_from_the_registry(self):
        document = stripped()
        registry = registry_for(document)
        rooms = len(document["climate"]["rooms"])
        purifiers = len(document["roomDevices"]["airPurifiers"])
        counts = hcp.patch(document, registry)
        self.assertEqual(counts, {"rooms": rooms, "rooms_filled": rooms, "purifiers": purifiers,
                                  "purifier_fields_filled": purifiers * 4, "unresolved": 0})
        for room in document["climate"]["rooms"]:
            self.assertIn(room["occupiedOnlyEntityId"], registry.ids)
        for index, purifier in enumerate(document["roomDevices"]["airPurifiers"]):
            self.assertEqual(purifier["fanEntityId"], f"fan.demo_fixture_{index}_unit")
            self.assertTrue(all(purifier[f] in registry.ids for f in hcp.PURIFIER_FIELDS))
        self.assertTrue(hcp.check_passes(hcp.check(document, registry)))

    def test_a_field_already_present_is_never_touched(self):
        document = demo_document()
        before = copy.deepcopy(document)
        counts = hcp.patch(document, registry_for(document))
        self.assertEqual(document, before)
        self.assertEqual((counts["rooms_filled"], counts["purifier_fields_filled"], counts["unresolved"]), (0, 0, 0))

    def test_a_second_run_changes_nothing(self):
        document = stripped()
        registry = registry_for(document)
        hcp.patch(document, registry)
        again = copy.deepcopy(document)
        self.assertEqual(hcp.patch(document, registry)["rooms_filled"], 0)
        self.assertEqual(document, again)

    def test_nothing_else_in_the_document_changes(self):
        original = stripped()
        patched = copy.deepcopy(original)
        hcp.patch(patched, registry_for(original))
        for room in patched["climate"]["rooms"]:
            room.pop("occupiedOnlyEntityId")
        for purifier in patched["roomDevices"]["airPurifiers"]:
            for field in hcp.PURIFIER_FIELDS:
                purifier.pop(field)
        self.assertEqual(patched, original)

    def test_what_the_registry_cannot_answer_is_counted_and_never_guessed(self):
        document = stripped()
        counts = hcp.patch(document, hcp.Registry([]))
        self.assertEqual(counts["rooms_filled"] + counts["purifier_fields_filled"], 0)
        self.assertEqual(counts["unresolved"], counts["rooms"] + counts["purifiers"] * 4)
        self.assertNotIn("occupiedOnlyEntityId", document["climate"]["rooms"][0])

    def test_local_rules_answer_what_the_registry_cannot(self):
        document = {"climate": {"rooms": [{"title": "Demo Room"}]},
                    "roomDevices": {"airPurifiers": [{"pm25EntityId": "sensor.demo_unit_pm2_5"}]}}
        rules = {"occupiedOnlyEntityId": "switch.demo_fixture_{key}", "fanEntityId": "fan.demo_fixture_{base}"}
        counts = hcp.patch(document, hcp.Registry([]), rules)
        self.assertEqual(document["climate"]["rooms"][0]["occupiedOnlyEntityId"], "switch.demo_fixture_demo_room")
        self.assertEqual(document["roomDevices"]["airPurifiers"][0]["fanEntityId"], "fan.demo_fixture_demo_unit")
        self.assertEqual(counts["unresolved"], 3)

    def test_the_tool_carries_no_house_specific_rule(self):
        source = (ROOT / "tools" / "house_config_patch.py").read_text()
        self.assertNotRegex(source, r"\bRULES\b")
        self.assertNotRegex(source, r"(?i)levoit|living_room_")

    def test_malformed_entries_and_missing_sections_are_skipped(self):
        document = {"climate": {"rooms": ["x", {"title": 4}, {"title": "Demo Room"}]},
                    "roomDevices": {"airPurifiers": [None, {"roomTitle": "r"}]}}
        counts = hcp.patch(document, hcp.Registry([]))
        self.assertEqual((counts["rooms"], counts["purifiers"]), (1, 0))
        self.assertEqual(hcp.patch({"schema": 2}, hcp.Registry([]))["rooms"], 0)

    def test_load_local_rules_ignores_a_missing_or_bad_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "rules.json"
            self.assertEqual(hcp.load_local_rules(path), {})
            path.write_text("nope")
            self.assertEqual(hcp.load_local_rules(path), {})
            path.write_text("[1]")
            self.assertEqual(hcp.load_local_rules(path), {})
            path.write_text(json.dumps({"fanEntityId": "fan.demo_x_{base}", "bad": 3}))
            self.assertEqual(hcp.load_local_rules(path), {"fanEntityId": "fan.demo_x_{base}"})

    def test_helpers(self):
        self.assertEqual(hcp.purifier_base("sensor.demo_unit_pm2_5"), "demo_unit")
        self.assertEqual(hcp.purifier_base("demo_unit"), "demo_unit")
        self.assertEqual(hcp.room_key("Guest Room"), "guest_room")
        self.assertEqual(hcp.encode({"b": 1, "a": 2}), '{"a":2,"b":1}')
        with self.assertRaises(hcp.PatchError):
            hcp.encode({"pad": "x" * hcp.BYTE_LIMIT})
        self.assertTrue(hcp.inside_scratch(hcp.DEFAULT_OUT))
        self.assertFalse(hcp.inside_scratch(ROOT / "tools" / "house.json"))


class CheckTests(unittest.TestCase):
    def test_a_complete_document_whose_ids_exist_passes(self):
        document = demo_document()
        counts = hcp.check(document, registry_for(document))
        self.assertTrue(counts["rooms"] > 0 and counts["purifiers"] > 0)
        # The demo document's ids are not the fixture registry's, so only presence passes here.
        self.assertEqual((counts["rooms_with_field"], counts["purifiers_complete"]), (counts["rooms"], counts["purifiers"]))

    def test_a_missing_field_fails(self):
        document = stripped()
        self.assertFalse(hcp.check_passes(hcp.check(document, registry_for(document))))

    def test_an_id_that_is_not_in_the_registry_fails(self):
        document = demo_document()
        registry = hcp.Registry([])
        self.assertFalse(hcp.check_passes(hcp.check(document, registry)))
        patched = stripped()
        reg = registry_for(patched)
        hcp.patch(patched, reg)
        patched["climate"]["rooms"][0]["occupiedOnlyEntityId"] = "switch.demo_fixture_gone"
        self.assertFalse(hcp.check_passes(hcp.check(patched, reg)))


class FakeServer:
    """A fake ssh: answers the document read and the three registry websocket calls; records every call."""

    def __init__(self, document: dict, registry: tuple, fail: bool = False):
        self.document, self.registry, self.fail, self.calls = document, registry, fail, []

    def __call__(self, args, input=None):
        self.calls.append((args, input))
        if self.fail:
            return subprocess.CompletedProcess(args, 255, "", "secret-looking stderr")
        remote = args[-1]
        if remote.startswith("cat "):
            return subprocess.CompletedProcess(args, 0, json.dumps(self.document), "")
        entities, devices, areas = self.registry
        kind = {"entity": entities, "device": devices, "area": areas}[re.search(r"config/(\w+)_registry/list", remote).group(1)]
        return subprocess.CompletedProcess(args, 0, "noise\n" + json.dumps({"success": True, "result": kind, "error": ""}), "")


def run_main(*args, run=None, rules_path=None) -> tuple:
    out, err = io.StringIO(), io.StringIO()
    kwargs = {"run": run} if run else {}
    if rules_path:
        kwargs["rules_path"] = rules_path
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = hcp.main(list(args), **kwargs)
    return code, out.getvalue(), err.getvalue()


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.rules = Path(self.tmp.name) / "none.json"
        self.out_path = hcp.ROOT / "build" / "ha" / "house-test-output.json"
        self.addCleanup(lambda: self.out_path.unlink(missing_ok=True))

    def test_the_default_run_writes_the_patched_document_and_prints_counts_only(self):
        document = stripped()
        server = FakeServer(document, fixture_registry(document))
        code, out, err = run_main("--out", str(self.out_path), run=server, rules_path=self.rules)
        self.assertEqual(code, 0, err)
        written = json.loads(self.out_path.read_text())
        self.assertTrue(all("occupiedOnlyEntityId" in r for r in written["climate"]["rooms"]))
        self.assertIn("unresolved 0", out)
        self.assertNotRegex(out + err, r"\b(switch|sensor|fan|select)\.")
        self.assertTrue(all(args[:3] == ["ssh", "-o", "BatchMode=yes"] for args, _ in server.calls))
        self.assertTrue(any(inp and "SUPERVISOR_TOKEN" in inp for _, inp in server.calls), "the add-on websocket client runs on the host")

    def test_unresolved_fields_exit_one_but_still_write(self):
        document = stripped()
        server = FakeServer(document, ([], [], []))
        code, out, _ = run_main("--out", str(self.out_path), run=server, rules_path=self.rules)
        self.assertEqual(code, 1)
        self.assertIn("unresolved", out)
        self.assertTrue(self.out_path.exists())

    def test_check_against_a_local_document_passes_when_complete(self):
        document = stripped()
        registry = fixture_registry(document)
        hcp.patch(document, hcp.Registry(*registry))
        path = Path(self.tmp.name) / "in.json"
        path.write_text(json.dumps(document))
        code, out, _ = run_main("--check", "--input", str(path), run=FakeServer({}, registry))
        self.assertEqual(code, 0)
        self.assertIn("complete", out)
        self.assertRegex(out, r"rooms 11/11, purifiers 6/6")

    def test_check_of_the_live_document_fails_while_fields_are_missing_and_writes_nothing(self):
        document = stripped()
        code, out, _ = run_main("--check", "--out", str(self.out_path), run=FakeServer(document, fixture_registry(document)))
        self.assertEqual(code, 1)
        self.assertIn("INCOMPLETE", out)
        self.assertFalse(self.out_path.exists())

    def test_an_output_outside_the_scratch_place_is_refused(self):
        document = stripped()
        code, _, err = run_main("--out", str(Path(self.tmp.name) / "out.json"), run=FakeServer(document, fixture_registry(document)),
                                rules_path=self.rules)
        self.assertEqual(code, 1)
        self.assertIn("build/ha", err)

    def test_a_bad_input_file_is_refused_without_naming_content(self):
        bad = Path(self.tmp.name) / "bad.json"
        bad.write_text("not json")
        code, _, err = run_main("--check", "--input", str(bad), run=FakeServer({}, ([], [], [])))
        self.assertEqual(code, 1)
        self.assertNotIn("not json", err)
        bad.write_text("[]")
        self.assertEqual(run_main("--check", "--input", str(bad), run=FakeServer({}, ([], [], [])))[0], 1)
        self.assertEqual(run_main("--check", "--input", str(Path(self.tmp.name) / "missing.json"), run=FakeServer({}, ([], [], [])))[0], 1)

    def test_ssh_failures_name_the_step_and_not_the_output(self):
        code, _, err = run_main("--check", run=FakeServer({}, ([], [], []), fail=True))
        self.assertEqual(code, 1)
        self.assertNotIn("secret-looking", err)

    def test_a_reply_that_is_not_json_or_not_an_object_is_refused(self):
        for body in ("nope", "[1]"):
            run = lambda args, input=None, b=body: subprocess.CompletedProcess(args, 0, b, "")  # noqa: E731
            with self.assertRaises(hcp.PatchError) as raised:
                hcp.fetch_document("hass", run)
            self.assertNotIn(body, str(raised.exception))

    def test_a_failed_or_malformed_websocket_reply_is_refused(self):
        for body in ("", "not json", json.dumps({"success": False, "result": None, "error": "x"}), json.dumps({"success": True, "result": 3})):
            run = lambda args, input=None, b=body: subprocess.CompletedProcess(args, 0, b, "")  # noqa: E731
            with self.assertRaises(hcp.PatchError):
                hcp.ws_list("hass", "config/entity_registry/list", run)

    def test_a_host_that_looks_like_an_option_is_refused(self):
        calls = []
        with self.assertRaises(hcp.PatchError):
            hcp.fetch_document("-oProxyCommand=x", lambda args, input=None: calls.append(args))
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
