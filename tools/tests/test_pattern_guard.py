"""``tools/pattern_guard.py`` and ``tools/components_index.py``: schema checks, guards, ownership, changed, index."""

import importlib.util
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent


def load_tool(name):
    # By path: putting tools/ on sys.path would let tools/test_digest.py shadow tools/tests/test_digest.py.
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


guard = load_tool("pattern_guard")
components = load_tool("components_index")


def write(root, rel, text):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def fixture(root, guards=None, extra_files=None, internal=None):
    """A tiny repo: pattern `tile` owning Tile.swift and TileParts.swift, plus a README row."""
    write(root, "apple/Sources/HassDesign/Tile.swift", "public struct Tile {}\nextension View {\n    public func tiled() {}\n}\n")
    write(root, "apple/Sources/HassDesign/TileParts.swift", "struct TilePart {}\nprivate struct Hidden {}\n")
    for rel, text in (extra_files or {}).items():
        write(root, rel, text)
    write(root, ".agents/patterns/README.md", "| [tile](tile.md) | x |\n")
    write(root, ".agents/patterns/tile.md", "# Tile\n\n> **What:** a tile.\n\nTilePart lives in TileParts.\n\n## Guards\n- `tile/no-bad`\n- known debt apple/Sources/HassUI/Debt.swift\n")
    registry = {
        "componentScopes": ["apple/Sources/HassDesign/**/*.swift"],
        "internal": internal or [],
        "patterns": [{
            "id": "tile", "title": "Tile", "status": "current", "doc": ".agents/patterns/tile.md",
            "summary": "A tile.", "keywords": ["tile"],
            "canonical": {"apple": [{"path": "apple/Sources/HassDesign/Tile.swift", "symbol": "Tile"}]},
            "owns": ["apple/Sources/HassDesign/TileParts.swift"],
            "guards": guards if guards is not None else [],
            "related": {"patterns": []}, "supersedes": [], "supersededBy": None}]}
    write(root, "contracts/patterns.json", json.dumps(registry))
    return registry


BAD = {"id": "no-bad", "glob": "apple/Sources/**/*.swift", "regex": r"\bBadThing\b", "allow": [], "debt": [],
       "message": "No BadThing."}


class RegistryTests(unittest.TestCase):
    def test_real_registry_passes(self):
        report = guard.check(REPO)
        self.assertEqual(report.errors, [])

    def test_every_pattern_doc_has_a_record_and_the_reverse(self):
        data = guard.load(REPO)
        docs = {p.name for p in (REPO / ".agents/patterns").glob("*.md") if p.name != "README.md"}
        self.assertEqual({Path(p["doc"]).name for p in data["patterns"]}, docs)
        self.assertGreaterEqual(len(data["patterns"]), 39)

    def test_valid_fixture_has_no_errors(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            self.assertEqual(guard.check(root).errors, [])

    def test_missing_symbol_doc_and_router_row_are_errors(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            registry = fixture(root)
            registry["patterns"][0]["canonical"]["apple"][0]["symbol"] = "Nope"
            registry["patterns"][0]["status"] = "weird"
            write(root, "contracts/patterns.json", json.dumps(registry))
            write(root, ".agents/patterns/README.md", "")
            errors = "\n".join(guard.check(root).errors)
            self.assertIn("symbol `Nope` not found", errors)
            self.assertIn("status must be one of", errors)

    def test_non_apple_platform_key_is_rejected(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            registry = fixture(root)
            registry["patterns"][0]["canonical"]["android"] = []
            write(root, "contracts/patterns.json", json.dumps(registry))
            self.assertIn("unknown platform `android`", "\n".join(guard.check(root).errors))

    def test_dangling_relation_is_an_error(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            registry = fixture(root)
            registry["patterns"][0]["related"]["patterns"] = ["ghost"]
            registry["patterns"][0]["supersededBy"] = "ghost2"
            write(root, "contracts/patterns.json", json.dumps(registry))
            errors = "\n".join(guard.check(root).errors)
            self.assertIn("related pattern `ghost`", errors)
            self.assertIn("supersession target `ghost2`", errors)


class OwnershipTests(unittest.TestCase):
    def test_unowned_file_is_an_error_until_owned_or_internal(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, extra_files={"apple/Sources/HassDesign/Stray.swift": "struct Stray {}\n"})
            self.assertIn("Stray.swift: owned by no pattern", "\n".join(guard.check(root).errors))
            fixture(root, extra_files={"apple/Sources/HassDesign/Stray.swift": "struct Stray {}\n"},
                    internal=[{"glob": "apple/Sources/HassDesign/Stray.swift", "reason": "art"}])
            self.assertEqual(guard.check(root).errors, [])

    def test_internal_needs_a_reason_and_a_file(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, internal=[{"glob": "apple/Sources/HassDesign/Missing.swift", "reason": ""}])
            self.assertIn("needs a reason", "\n".join(guard.check(root).errors))

    def test_two_owners_is_an_error(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            registry = fixture(root)
            twin = json.loads(json.dumps(registry["patterns"][0]))
            twin["id"] = "twin"
            twin["doc"] = ".agents/patterns/twin.md"
            registry["patterns"].append(twin)
            write(root, "contracts/patterns.json", json.dumps(registry))
            write(root, ".agents/patterns/twin.md", "# Twin\n")
            write(root, ".agents/patterns/README.md", "(tile.md) (twin.md)")
            self.assertIn("owned by several patterns", "\n".join(guard.check(root).errors))

    def test_which_reports_roles(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, guards=[BAD])
            data = guard.load(root)
            self.assertEqual(guard.owners(data, "apple/Sources/HassDesign/Tile.swift"), [("tile", "canonical")])
            self.assertEqual(guard.owners(data, "apple/Sources/HassDesign/TileParts.swift"), [("tile", "owns")])
            self.assertEqual(guard.owners(data, "apple/Sources/Other/X.swift"), [("tile", "guarded")])
            self.assertEqual(guard.owners(data, "README.md"), [])


class GuardTests(unittest.TestCase):
    def test_hit_is_an_error_comments_are_ignored(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, guards=[BAD], extra_files={
                "apple/Sources/HassUI/Feature.swift": "// BadThing in a comment\nlet x = BadThing()\n"})
            errors = guard.check(root).errors
            self.assertEqual(sum("no-bad" in e and "Feature.swift:2" in e for e in errors), 1)
            self.assertFalse(any("Feature.swift:1" in e for e in errors))

    def test_allow_glob_skips_the_file(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            bad = dict(BAD, allow=["apple/Sources/HassUI/**"])
            fixture(root, guards=[bad], extra_files={"apple/Sources/HassUI/Feature.swift": "BadThing()\n"})
            self.assertEqual(guard.check(root).errors, [])

    def test_debt_is_a_warning_and_stale_debt_is_an_error(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            debt = dict(BAD, debt={"apple/Sources/HassUI/Debt.swift": 1})
            fixture(root, guards=[debt], extra_files={"apple/Sources/HassUI/Debt.swift": "BadThing()\n"})
            report = guard.check(root)
            self.assertEqual(report.errors, [])
            self.assertTrue(any("known debt in 1 file" in w for w in report.warnings))
            write(root, "apple/Sources/HassUI/Debt.swift", "fixed()\n")
            self.assertIn("allows 1 hit(s) but has 0", "\n".join(guard.check(root).errors))

    def test_debt_waives_by_hit_count_so_a_new_violation_fails(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            debt = dict(BAD, debt={"apple/Sources/HassUI/Debt.swift": 1})
            fixture(root, guards=[debt], extra_files={"apple/Sources/HassUI/Debt.swift": "BadThing()\nBadThing()\n"})
            errors = "\n".join(guard.check(root).errors)
            self.assertIn("Debt.swift:2: tile/no-bad", errors)
            self.assertNotIn("Debt.swift:1:", errors)
            debt = dict(BAD, debt={"apple/Sources/HassUI/Debt.swift": 3})
            fixture(root, guards=[debt], extra_files={"apple/Sources/HassUI/Debt.swift": "BadThing()\nBadThing()\n"})
            self.assertIn("allows 3 hit(s) but has 2", "\n".join(guard.check(root).errors))

    def test_real_light_toggle_guard_catches_every_form(self):
        pattern = next(p for p in guard.load(REPO)["patterns"] if p["id"] == "entity-tile")
        regex = __import__("re").compile(next(g for g in pattern["guards"] if g["id"] == "no-light-toggle")["regex"])
        for bad in ('callService("light", "toggle", data: [:])', 'ServiceCall("light", "toggle", target: id)',
                    'Command(domain: "light", service: "toggle", entityId: id)', 'try await conn.toggle("light.kitchen")'):
            self.assertTrue(regex.search(bad), bad)
        for fine in ('Command(domain: "light", service: "turn_on", entityId: id)', 'conn.toggle("switch.fan")',
                     'ServiceCall("media_player", "toggle", target: t)'):
            self.assertFalse(regex.search(fine), fine)

    def test_owned_file_must_be_named_in_its_doc(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            write(root, ".agents/patterns/tile.md", "# Tile\n\n> **What:** a tile.\n\nTile only.\n")
            self.assertIn("never names `TileParts`", "\n".join(guard.check(root).errors))

    def test_guard_must_be_named_in_the_doc(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, guards=[dict(BAD, id="other")])
            self.assertIn("doc must name guard `tile/other`", "\n".join(guard.check(root).errors))

    def test_invalid_regex_is_reported(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, guards=[dict(BAD, regex="(")])
            self.assertIn("invalid regex", "\n".join(guard.check(root).errors))

    def test_real_guards_catch_a_planted_violation(self):
        data = guard.load(REPO)
        report = guard.Report()
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "apple/Sources/HassUI/Features/X/View.swift", "AsyncImage(url: u)\n")
            pattern = next(p for p in data["patterns"] if p["id"] == "image-cache")
            hits = guard.run_guards(pattern, root, report)
        self.assertEqual([(h[0], h[3]) for h in hits], [("image-cache/no-async-image", "error")])


class ChangedAndIndexTests(unittest.TestCase):
    def test_changed_flags_component_without_doc(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            data = guard.load(root)
            text, missing = guard.changed_report(data, ["apple/Sources/HassDesign/TileParts.swift"])
            self.assertTrue(missing)
            self.assertIn("pattern doc/contract not updated", text)
            text, missing = guard.changed_report(
                data, ["apple/Sources/HassDesign/Tile.swift", ".agents/patterns/tile.md"])
            self.assertFalse(missing)
            self.assertIn("updated", text)
            text, missing = guard.changed_report(data, ["README.md"])
            self.assertEqual((text, missing), ("No pattern components changed.", False))

    def test_changed_strict_exit_code_uses_files(self):
        out = subprocess.run([sys.executable, str(TOOLS / "pattern_guard.py"), "changed", "--strict", "--files",
                              "apple/Sources/HassDesign/StatusPill.swift"], capture_output=True, text=True)
        self.assertEqual(out.returncode, 1)
        self.assertIn("status-pill", out.stdout)
        out = subprocess.run([sys.executable, str(TOOLS / "pattern_guard.py"), "changed", "--strict", "--files",
                              "apple/Sources/HassDesign/StatusPill.swift", ".agents/patterns/status-pill.md"],
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0)

    def test_changed_from_git_diff(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            run = lambda *a: subprocess.run(["git", *a], cwd=root, check=True, capture_output=True)
            run("init", "-q", "-b", "main")
            run("-c", "user.name=t", "-c", "user.email=t@t", "add", "-A")
            run("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
            run("checkout", "-qb", "work")
            write(root, "apple/Sources/HassDesign/Tile.swift", "public struct Tile {}\n// edit\n")
            run("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", "edit")
            self.assertEqual(guard.diff_files("main", "work", root), ["apple/Sources/HassDesign/Tile.swift"])

    def test_index_markdown_and_json_skip_superseded(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            registry = fixture(root)
            data = guard.load(root)
            self.assertIn("[tile](.agents/patterns/tile.md)", guard.index(data))
            rows = json.loads(guard.index(data, as_json=True))
            self.assertEqual(rows[0]["canonical"], ["Tile.swift `Tile`"])
            registry["patterns"][0]["status"] = "superseded"
            self.assertEqual(json.loads(guard.index(registry, as_json=True)), [])

    def test_glob_regex(self):
        self.assertTrue(guard.matches("a/b/c.swift", ["a/**/*.swift"]))
        self.assertTrue(guard.matches("a/c.swift", ["a/**/*.swift"]))
        self.assertFalse(guard.matches("a/b/c.swift", ["a/*.swift"]))
        self.assertTrue(guard.matches("a/Tile9.swift", ["a/Tile?.swift"]))

    def test_cli_default_runs_check_and_which(self):
        out = subprocess.run([sys.executable, str(TOOLS / "pattern_guard.py")], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout)
        self.assertIn("0 error(s)", out.stdout)
        out = subprocess.run([sys.executable, str(TOOLS / "pattern_guard.py"), "which",
                              "apple/Sources/HassDesign/StatusPill.swift", "apple/Sources/HassDesign/BindingIsPresent.swift"],
                             capture_output=True, text=True)
        self.assertIn("status-pill (canonical)", out.stdout)
        self.assertIn("internal (", out.stdout)


class ComponentsTests(unittest.TestCase):
    def test_extract_types_and_modifiers_skip_private(self):
        text = ("public struct A: View {}\nfinal class B {}\nprivate struct C {}\nfileprivate enum D {}\n"
                "extension View {\n    public func good() {}\n    private func bad() {}\n}\nenum E {}\n")
        self.assertEqual(components.extract(text), [("struct", "A"), ("class", "B"), ("modifier", "good"), ("enum", "E")])

    def test_build_entry_fields(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, internal=[])
            write(root, "contracts/test-map.json", json.dumps({"rules": [
                {"prefix": "apple/Sources/HassDesign/Tile", "swift": ["TileTests"], "journeys": ["TileJourneyTests"]}]}))
            write(root, ".agents/design/apple/system-api-audit.md",
                  "| Component | Alt | Precedent | Verdict |\n|---|---|---|---|\n"
                  "| `Tile` | 17: Foo | Apple | **Keep, shrink** |\n")
            doc = components.build(root)
            tile = next(c for c in doc["components"] if c["name"] == "Tile")
            self.assertEqual(tile["pattern"], "tile")
            self.assertEqual(tile["tests"], {"swift": ["TileTests"], "journeys": ["TileJourneyTests"]})
            self.assertTrue(tile["systemApi"].startswith("Keep, shrink. System alternative: 17: Foo"))
            self.assertIn("tiled", {c["name"] for c in doc["components"]})
            self.assertNotIn("Hidden", {c["name"] for c in doc["components"]})

    def test_internal_entry_and_stale_check(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, extra_files={"apple/Sources/HassDesign/Art.swift": "struct Art {}\n"},
                    internal=[{"glob": "apple/Sources/HassDesign/Art.swift", "reason": "art"}])
            art = next(c for c in components.build(root)["components"] if c["name"] == "Art")
            self.assertEqual((art["pattern"], art["internal"], art["internalReason"]), (None, True, "art"))

    def test_audit_notes_prefix_matcher_prefers_the_own_name(self):
        notes = [("TintedGlass*", "glass"), ("Other", "other")]
        self.assertEqual(components.system_api("x", "TintedGlassRim", notes), "glass")
        self.assertEqual(components.system_api("Other", "TintedGlassRim", notes), "other")  # own name first
        self.assertIsNone(components.system_api("x", "Unrelated", notes))

    def test_overloads_are_one_component_and_note_has_full_audit_path(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, extra_files={"apple/Sources/HassDesign/Alerts.swift":
                                       "extension View {\n    func alert(_ a: Int) {}\n    func alert(_ b: String) {}\n}\n"},
                    internal=[{"glob": "apple/Sources/HassDesign/Alerts.swift", "reason": "x"}])
            write(root, ".agents/design/apple/system-api-audit.md",
                  "| Component | Alt | Precedent | Verdict |\n|---|---|---|---|\n| `Tile` | 17: `Foo`. | Apple | **Keep** |\n")
            doc = components.build(root)
            self.assertEqual([c["name"] for c in doc["components"]].count("alert"), 1)
            note = next(c for c in doc["components"] if c["name"] == "Tile")["systemApi"]
            self.assertIn(".agents/design/apple/system-api-audit.md", note)
            self.assertNotIn("..", note)


class HouseFacadeGuardTests(unittest.TestCase):
    """The registry's guard for flipped house-config facades: a `static let` that reads one."""

    def entry(self):
        data = guard.load(REPO)
        pattern = next(p for p in data["patterns"] if p["id"] == "weather")
        return next(g for g in pattern["guards"] if g["id"] == "static-let-reads-house-facade")

    def flagged(self, source):
        """First lines of the statements of `source` that the real guard flags."""
        found = self.entry()
        regex = re.compile(guard.facade_regex(found["facades"]))
        return [n for n, text in guard.statements(source.splitlines(), re.compile(found["statement"])) if regex.search(text)]

    def test_flags_one_line_static_lets_across_every_batch(self):
        for line in (
            "    static let chips = HomeConfig.statusChips.filter { $0.sheet == .security }",
            "    public static let weather = HomeConfig.weatherEntityId",
            "    public static let contactSensorsEntityId = SecurityConfig.contactSensorsEntityId",
            "    static let doors: [SecurityConfig.Tile] = SecurityConfig.controlTiles",
            "    public static let securityEntityId = QuickLinks.securityEntityId",
            "    static let weather = WeatherEntities.weather",
            "    static let hub = ClimateConfig.hubEntityId",
            "    static let beds = MasterBedroom.beds",
            "    static let mode = Vacation.modeEntityId",
            "    public static let vacationModeEntityId = Vacation.modeEntityId",
            "    public static let foodSpaceEntityIds = FoodConfig.spaces.map(\\.entityId)",
            "    static let list = ChoresConfig.groceryEntityId",
            "    static let visibility = SprinklersConfig.visibilityEntityId",
            "    static let xbox = MusicRoom.xboxEntityId",
            "    static let source = MediaRemotes.MusicRoom.Source.xbox",
            "    static let remotes = MediaRemotes.all",
            "    static let pages = RoomsConfig.pages",
            "    static let items = RoomNavigation.items",
            "    static let lights = RoomGroups.allLights",
            "    static let vacuums = Vacuums.all",
            "    static let grill = GrillConfig.bearGrills",
            "    static let tiles = Admin.securityTiles",
        ):
            self.assertEqual(self.flagged(line), [1], line)

    def test_flags_a_multi_line_initializer(self):
        source = ("enum A {\n    static let tiles: [Tile] = [\n        .init(title: \"Doors\",\n"
                  "              entityId: SecurityConfig.vehicleLockEntityId),\n    ]\n}\n")
        self.assertEqual(self.flagged(source), [2])
        chained = "    static let ids = FoodConfig.spaces\n        .map(\\.entityId)\n"
        self.assertEqual(self.flagged(chained), [1])
        closure = ("    static let page: RoomPage = {\n        typealias M = Thing\n"
                   "        return RoomPage(M.x, ChoresConfig.groceryEntityId)\n    }()\n")
        self.assertEqual(self.flagged(closure), [1])

    def test_allows_computed_vars_comments_and_other_reads(self):
        for source in (
            "    static var chips: [HomeConfig.StatusChip] { HomeConfig.statusChips }\n",
            "    static let tint = HomeConfig.ChipTone.light\n",
            "    static let title = \"Quick Links\"\n",
            "    static let id = 1 // was Vacation.modeEntityId\n",
            "    /// static let mode = Vacation.modeEntityId\n",
            "    static var mode: String { Vacation.modeEntityId }\n",
            "    static func other() -> String { Vacation.modeEntityId }\n",
        ):
            self.assertEqual(self.flagged(source), [], source)

    def test_statements_stop_at_the_balanced_close(self):
        lines = ["static let a = f(", "    1,", "    2)", "static let b = 2", "var c = 3"]
        self.assertEqual(guard.statements(lines, re.compile(r"\bstatic let\b")),
                         [(1, "static let a = f( 1, 2)"), (4, "static let b = 2")])

    def test_a_statement_guard_reports_the_first_line_and_honours_debt(self):
        rule = {"id": "no-facade", "glob": "apple/Sources/**/*.swift", "statement": r"\bstatic let\b",
                "facades": {"HomeConfig": ["cameras"]}, "allow": [], "debt": {}, "message": "No."}
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, guards=[rule], extra_files={
                "apple/Sources/HassUI/A.swift": "enum A {\n    static let one = f(\n        HomeConfig.cameras)\n}\n"})
            doc = root / ".agents/patterns/tile.md"
            doc.write_text("# Tile\n\n> **What:** a tile.\n\nTilePart.\n\n## Guards\n- `tile/no-facade`\n", encoding="utf-8")
            report = guard.check(root)
            self.assertTrue(any("A.swift:2" in e and "tile/no-facade" in e for e in report.errors), report.errors)

    def test_every_flipped_facade_in_the_sources_is_named_by_the_guard(self):
        named = {n for names in self.entry()["facades"].values() for n in names}
        declaration = re.compile(r"static var (\w+)[^\n]*\{[^\n]*HouseConfigSource\.active\.read")
        missing = set()
        for path in (REPO / "apple/Sources").rglob("*.swift"):
            for name in declaration.findall(path.read_text(encoding="utf-8", errors="replace")):
                if name not in named:
                    missing.add(name)
        self.assertEqual(sorted(missing), [], "add these facade names to the guard's `facades` map")

    def test_every_derived_facade_in_the_sources_is_named_by_the_guard(self):
        found = self.entry()
        named = {n for names in found["facades"].values() for n in names}
        regex = re.compile(guard.facade_regex(found["facades"]))
        missing = set()
        for path in (REPO / "apple/Sources").rglob("*.swift"):
            if "Gallery" in path.parts[-2:-1] or "Gallery" in path.name:
                continue
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            for _, text in guard.statements(lines, re.compile(r"\bstatic var \w+")):
                name = re.search(r"static var (\w+)", text).group(1)
                if name not in named and regex.search(text.split(name, 1)[1]):
                    missing.add(name)
        self.assertEqual(sorted(missing), [], "a computed var over a facade is a facade: add it under its type")

    def test_the_unique_keys_guard_only_scans_files_that_read_a_facade(self):
        registry = guard.load(REPO)
        pattern = next(p for p in registry["patterns"] if p["id"] == "weather")
        rule = next(g for g in pattern["guards"] if g["id"] == "unique-keys-in-facade-files")
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "apple/Sources/HassUI/Reads.swift",
                  "let a = Dictionary(uniqueKeysWithValues: HomeConfig.guestToggles.map { ($0.entityId, 1) })\n")
            write(root, "apple/Sources/HassUI/Quiet.swift", "let a = Dictionary(uniqueKeysWithValues: [(1, 2)])\n")
            report = guard.Report()
            hits = guard.run_guards({"id": "weather", "guards": pattern["guards"]}, root, report)
            flagged = {rel for gid, rel, _, kind in hits if gid.endswith("unique-keys-in-facade-files") and kind == "error"}
            self.assertEqual(flagged, {"apple/Sources/HassUI/Reads.swift"})
        self.assertIn("uniquingKeysWith", rule["message"])


if __name__ == "__main__":
    unittest.main()
