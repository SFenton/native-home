"""The registry cannot drift silently: it must name every state-bearing node type and agree with the generated space and the golden."""

import json
import re
import unittest

from state_space_loader import ROOT

KINDS = json.loads((ROOT / "tools/state_space/kinds.json").read_text(encoding="utf-8"))
HA = json.loads((ROOT / "tools/state_space/ha-states-2026.11.0.json").read_text(encoding="utf-8"))
SHAPE = ROOT / "apple/Sources/HassCore/ServerUIComposition/ServerUICompositionShape.swift"
STYLES = ROOT / "apple/Sources/HassCore/TileActions/StateStyle+BuiltIn.swift"
ROOM = ROOT / "apple/Sources/HassCore/Rooms/RoomModel.swift"
GOLDEN = ROOT / "apple/Tests/HassCoreTests/StateGolden/state-golden.json"
SPACE = ROOT / "apple/Tests/HassCoreTests/StateGolden/state-space.json"


def native_node_types() -> set:
    text = SHAPE.read_text(encoding="utf-8")
    return set(re.findall(r'^\s+"([a-z-]+)": node\("\1"', text, re.M))


class RegistryAgainstSchemaTests(unittest.TestCase):
    def test_every_native_node_type_is_registered_or_listed_unregistered(self):
        named = {t for k in KINDS["kinds"] for t in k["node_types"]}
        listed = set(KINDS["node_types_unregistered"])
        self.assertTrue(native_node_types(), "the node list was not found; the pattern in this test needs updating")
        new = native_node_types() - named - listed
        self.assertEqual(new, set(), f"a node type the registry does not name: add a kind or list it in node_types_unregistered: {sorted(new)}")

    def test_the_registry_names_no_node_type_the_schema_lost(self):
        named = {t for k in KINDS["kinds"] for t in k["node_types"]} | set(KINDS["node_types_unregistered"])
        self.assertEqual(named - native_node_types(), set())

    def test_a_node_type_is_not_both_registered_and_unregistered(self):
        named = {t for k in KINDS["kinds"] for t in k["node_types"]}
        self.assertEqual(named & set(KINDS["node_types_unregistered"]), set())

    def test_room_card_kinds_match_the_native_enum(self):
        text = ROOM.read_text(encoding="utf-8")
        enum = re.search(r"enum RoomCardKind.*?\n    case ([^\n]+)\n    case wakeLight = \"wake-light\"", text, re.S)
        native = {c.strip() for c in enum.group(1).split(",")} - {"wakeLight"} | {"wake-light"}
        registry = {k["room_kind"] for k in KINDS["kinds"] if k["family"] == "room-card"}
        self.assertEqual(registry, native)

    def test_state_style_kinds_match_the_built_in_styles(self):
        built_in = set(re.findall(r'StateStyle\(\s*id: "([a-z-]+)"', STYLES.read_text(encoding="utf-8")))
        registry = {k["style"] for k in KINDS["kinds"] if k["family"] == "state-style"}
        self.assertEqual(registry, built_in)


class RegistryAgainstStatesTests(unittest.TestCase):
    def test_every_state_set_named_exists(self):
        for kind in KINDS["kinds"]:
            for name in kind["state_sets"]:
                self.assertIn(name, HA["sets"], f"{kind['id']}: {name}")

    def test_kind_ids_are_unique_and_evaluators_known(self):
        ids = [k["id"] for k in KINDS["kinds"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertLessEqual({k["evaluator"] for k in KINDS["kinds"]}, {"room-text", "style", "remote-device"})

    def test_a_free_text_helper_is_a_demo_name(self):
        for kind in KINDS["kinds"]:
            if kind.get("free_text"):
                self.assertTrue(kind["free_text"].startswith("demo_"))

    def test_the_golden_covers_exactly_the_kinds_with_an_oracle(self):
        golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
        space = json.loads(SPACE.read_text(encoding="utf-8"))
        kind_of = {r["id"]: r["kind"] for r in space["rows"]}
        covered = {kind_of[i] for i in golden["rows"]}
        oracle = {k["id"] for k in KINDS["kinds"] if k["evaluator"] != "style" or k.get("old")}
        self.assertEqual(covered, oracle)
        self.assertEqual(golden["rowCount"], len(golden["rows"]))


if __name__ == "__main__":
    unittest.main()
