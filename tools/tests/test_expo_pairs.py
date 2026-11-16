"""Tests for ``tools/expo_pairs``: the publication migration, the per-run fixture writes and the harness's own checks.

The harness and its navigation policy are Node modules; their tests live in ``tools/expo_pairs/tests`` and run here
through ``node --test`` (skipped where Node is not installed). Every fixture below is synthetic: no house value.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PAIRS = Path(__file__).resolve().parents[1] / "expo_pairs"
spec = importlib.util.spec_from_file_location("pair_cases", PAIRS / "pair_cases.py")
pair_cases = importlib.util.module_from_spec(spec)
sys.modules["pair_cases"] = pair_cases
spec.loader.exec_module(pair_cases)

GALLERY_SWIFT = """
public struct ComponentGallery {
    public enum Page: String, CaseIterable, Sendable {
        case food
        case mediaRemote = "media-remote"
        /// A documented page.
        case rooms
        case home, vacation // two on a line
    }
}
"""


def synthetic_publication() -> dict:
    """A tiny publication that carries every removed field, nested like the recorded one."""
    config = {"name": "Bed A", **{field: "x" for field in ("tonightScript", "outsideScheduleScript")}}
    environment = {"scheduleEntityId": "sensor.s", "scheduleSetTopic": "t", "hotFlashBrokerScript": "s",
                   "householdAwayScript": "s", "householdAwayEntityId": "e"}
    document = {"id": "doc", "dataSources": [{"id": "src", "inputs": {"beds": [{"configuration": config}],
                                                                       "environment": environment}}]}
    return {"envelopeVersion": 1, "publisherId": "p", "revision": 9, "document": document}


class MigrationTests(unittest.TestCase):
    def test_strips_every_removed_field_at_any_depth_and_reports_the_paths(self):
        migrated, dropped = pair_cases.strip_removed_fields(synthetic_publication())
        self.assertEqual(len(dropped), 5)  # two on the bed, three on the environment
        self.assertEqual({path.rsplit("/", 1)[-1] for path in dropped}, set(pair_cases.REMOVED_BEDROOM_FIELDS))
        self.assertIn("/document/dataSources/0/inputs/beds/0/configuration/tonightScript", dropped)
        text = json.dumps(migrated)
        for field in pair_cases.REMOVED_BEDROOM_FIELDS:
            self.assertNotIn(field, text)
        self.assertEqual(migrated["document"]["dataSources"][0]["inputs"]["beds"][0]["configuration"], {"name": "Bed A"})
        self.assertEqual(migrated["revision"], 9)

    def test_leaves_a_clean_publication_alone(self):
        clean = {"document": {"a": [1, {"b": None}]}}
        migrated, dropped = pair_cases.strip_removed_fields(clean)
        self.assertEqual(migrated, clean)
        self.assertEqual(dropped, [])

    def test_does_not_edit_its_input(self):
        original = synthetic_publication()
        snapshot = json.dumps(original)
        pair_cases.migrate_publication(original)
        self.assertEqual(json.dumps(original), snapshot)

    def test_the_document_hash_is_sorted_compact_json(self):
        document = {"b": 1, "a": ["é"]}
        expected = pair_cases.sha256_hex('{"a":["é"],"b":1}'.encode())
        self.assertEqual(pair_cases.document_sha256(document), expected)
        self.assertEqual(pair_cases.document_sha256({"a": ["é"], "b": 1}), expected)

    def test_reads_the_gallery_pages_from_swift(self):
        self.assertEqual(pair_cases.gallery_pages(GALLERY_SWIFT), ["food", "media-remote", "rooms", "home", "vacation"])
        self.assertEqual(pair_cases.gallery_pages("struct Nothing {}"), [])

    def test_chooses_a_page_that_exists(self):
        pages = ["food", "rooms", "home"]
        self.assertEqual(pair_cases.choose_gallery_page("food", pages), "food")
        self.assertEqual(pair_cases.choose_gallery_page("bedroom", pages), "rooms")
        self.assertEqual(pair_cases.choose_gallery_page("bedroom", ["food", "home"]), "food")
        self.assertEqual(pair_cases.choose_gallery_page("bedroom", pages, preferred="home"), "home")
        with self.assertRaises(ValueError):
            pair_cases.choose_gallery_page("bedroom", [])

    def test_migrates_the_fixture_without_editing_the_original(self):
        fixture = {"id": "f", "variables": {"FENTON_GALLERY": "bedroom", "KEEP": "1"}}
        migrated = pair_cases.migrate_fixture(fixture, ["rooms"])
        self.assertEqual(migrated["variables"], {"FENTON_GALLERY": "rooms", "KEEP": "1"})
        self.assertEqual(fixture["variables"]["FENTON_GALLERY"], "bedroom")


def write_publication_dir(root: Path, gallery: str = "bedroom") -> Path:
    root.mkdir(parents=True)
    (root / "publication.json").write_text(json.dumps(synthetic_publication()), encoding="utf-8")
    (root / "bootstrap.json").write_text(json.dumps({"endpoint": "http://example.invalid", "gallery": {}, "entities": {}}))
    (root / "fixture.json").write_text(json.dumps({"id": "bedroom-default-png", "referenceTime": 1, "pauseContinuousAnimations": True,
                                                  "variables": {"FENTON_GALLERY": gallery, "FENTON_GALLERY_SCENARIO": "default"}}))
    (root / "assets").mkdir()
    (root / "assets" / ("a" * 64 + ".png")).write_bytes(b"png")
    return root


class MigrateDirectoryTests(unittest.TestCase):
    def test_writes_a_publication_the_app_accepts_and_a_summary_without_house_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = write_publication_dir(Path(tmp) / "src")
            summary = pair_cases.migrate_directory(source, Path(tmp) / "out", ["rooms"])
            out = Path(tmp) / "out"
            migrated = json.loads((out / "publication.json").read_text())
            self.assertNotIn("tonightScript", json.dumps(migrated))
            self.assertEqual(summary["galleryPage"], "rooms")
            self.assertEqual(summary["droppedCount"], 5)
            self.assertEqual(summary["documentSha256"], pair_cases.document_sha256(migrated["document"]))
            self.assertEqual(sorted(summary["removedFields"]), sorted(pair_cases.REMOVED_BEDROOM_FIELDS))
            self.assertEqual(json.loads((out / "fixture.json").read_text())["variables"]["FENTON_GALLERY"], "rooms")
            self.assertTrue((out / "assets" / ("a" * 64 + ".png")).exists())
            self.assertIn("tonightScript", (source / "publication.json").read_text(), "the source is not edited")


def recorded_case(side: str, fixture_sha: str) -> dict:
    case = {"contract": "sdui.expo.fixture-case.v1", "side": side, "fixtureSHA256": fixture_sha, "plan": {"steps": []},
            "viewport": {"width": 1, "height": 1}}
    if side == "candidate":
        case["expectedPublication"] = {"publisherId": "p", "revision": 9, "documentSha256": "old", "assets": ["a" * 64]}
    return case


class PrepareTests(unittest.TestCase):
    """``prepare`` writes the fixture for one run, just before that run, into a fake simulator container."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.app = self.tmp / "App.app"
        self.app.mkdir()
        (self.app / "FentonHome.debug.dylib").write_bytes(b"binary")
        self.data = self.tmp / "data"
        self.data.mkdir()
        self.publication = write_publication_dir(self.tmp / "publication")
        self.migrated = self.tmp / "migrated"
        pair_cases.migrate_directory(self.publication, self.migrated, ["rooms"])
        self.recorded = self.tmp / "recorded"
        for run, info in pair_cases.RUNS.items():
            base = json.loads((self.publication / "fixture.json").read_text())
            base["id"] = f"bedroom-{info['scenario']}-png"
            base["variables"]["FENTON_GALLERY_SCENARIO"] = info["scenario"]
            sha = pair_cases.sha256_hex(pair_cases.fixture_bytes(base))
            folder = self.recorded / info["folder"]
            folder.mkdir(parents=True)
            for side in ("reference", "candidate"):
                (folder / f"{side}-case.json").write_text(json.dumps(recorded_case(side, sha)))

    def runner(self, command):
        verb = command[0:2]
        if command[:3] == ["xcrun", "simctl", "get_app_container"]:
            return str(self.app if command[-1] == "app" else self.data)
        if command[0] == "node":
            return "f" * 64
        if command[0] == "plutil":
            return "1.2.3"
        raise AssertionError(f"unexpected command {verb}")

    def prepare(self, run, side, publication=None):
        return pair_cases.prepare(run=run, side=side, recorded_root=self.recorded,
                                  publication_dir=publication or (self.migrated if side == "candidate" else self.publication),
                                  device="UDID", command="/x/agent-device", out=self.tmp / "out", source_sha="abc",
                                  pages=["rooms"], runner=self.runner)

    def bootstrap_sha(self):
        return pair_cases.sha256_hex((self.data / pair_cases.FIXTURE_SUBPATH / "bootstrap.json").read_bytes())

    def test_each_prepare_leaves_its_own_fixture_on_the_device(self):
        waking = json.loads(self.prepare("waking-regression", "candidate").read_text())
        self.assertEqual(waking["fixtureSHA256"], self.bootstrap_sha())
        self.assertIn('"waking"', (self.data / pair_cases.FIXTURE_SUBPATH / "bootstrap.json").read_text())
        scroll = json.loads(self.prepare("editor-scroll", "candidate").read_text())
        self.assertEqual(scroll["fixtureSHA256"], self.bootstrap_sha())
        self.assertNotEqual(waking["fixtureSHA256"], scroll["fixtureSHA256"], "the scenario differs per run")

    def test_candidate_case_names_the_migrated_publication_and_an_existing_gallery_page(self):
        case = json.loads(self.prepare("editor-save", "candidate").read_text())
        migrated = json.loads((self.migrated / "publication.json").read_text())
        self.assertEqual(case["expectedPublication"]["documentSha256"], pair_cases.document_sha256(migrated["document"]))
        self.assertEqual(case["expectedPublication"]["publisherId"], "p")
        fixture = json.loads((self.data / pair_cases.FIXTURE_SUBPATH / "bootstrap.json").read_text())
        self.assertEqual(fixture["variables"]["FENTON_GALLERY"], "rooms")
        self.assertEqual(case["bundleSHA256"], "f" * 64)
        self.assertEqual(case["fixtureDirectory"], f"{self.data}/{pair_cases.FIXTURE_SUBPATH}")
        self.assertEqual(case["output"], str(self.tmp / "out" / "runs" / "editor-save" / "candidate"))
        self.assertEqual(case["sourceSHA"], "abc")
        self.assertFalse(case["uncommittedSources"])
        self.assertTrue(Path(case["output"]).parent.is_dir(), "the harness needs the parent, and makes the leaf itself")
        self.assertFalse(Path(case["output"]).exists())

    def test_candidate_preview_inputs_carry_no_endpoint_and_the_run_scenario(self):
        self.prepare("waking-regression", "candidate")
        preview = self.data / pair_cases.PREVIEW_SUBPATH
        bootstrap = json.loads((preview / "bootstrap.json").read_text())
        self.assertNotIn("endpoint", bootstrap)
        self.assertEqual(bootstrap["gallery"]["bedroomScenario"], "waking")
        self.assertTrue((preview / "assets" / ("a" * 64)).exists(), "the .png suffix is dropped")
        self.assertNotIn("tonightScript", (preview / "publication.json").read_text())

    def test_a_stale_receipt_is_removed_before_the_run(self):
        preview = self.data / pair_cases.PREVIEW_SUBPATH
        preview.mkdir(parents=True)
        (preview / "receipt.json").write_text("{}")
        gallery = self.data / pair_cases.FIXTURE_SUBPATH
        gallery.mkdir(parents=True)
        (gallery / "receipt.json").write_text("{}")
        self.prepare("editor-save", "candidate")
        self.assertFalse((preview / "receipt.json").exists())
        self.assertFalse((gallery / "receipt.json").exists())

    def test_reference_replays_the_recorded_fixture_unmigrated(self):
        case = json.loads(self.prepare("editor-scroll", "reference").read_text())
        fixture = json.loads((self.data / pair_cases.FIXTURE_SUBPATH / "bootstrap.json").read_text())
        self.assertEqual(fixture["variables"]["FENTON_GALLERY"], "bedroom")
        self.assertEqual(case["fixtureSHA256"], self.bootstrap_sha())
        self.assertFalse((self.data / pair_cases.PREVIEW_SUBPATH).exists(), "the reference has no preview publication")
        self.assertNotIn("expectedPublication", case)

    def test_reference_refuses_a_fixture_that_is_not_the_recorded_one(self):
        with self.assertRaises(ValueError):
            self.prepare("editor-scroll", "reference", publication=self.migrated)

    def test_rejects_an_unknown_run_or_side(self):
        with self.assertRaises(ValueError):
            self.prepare("nope", "candidate")
        with self.assertRaises(ValueError):
            self.prepare("editor-save", "middle")


class CommandLineTests(unittest.TestCase):
    def test_migrate_prints_a_summary_and_writes_the_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = write_publication_dir(Path(tmp) / "src")
            gallery = Path(tmp) / "ComponentGallery.swift"
            gallery.write_text(GALLERY_SWIFT)
            out = Path(tmp) / "out"
            import contextlib
            import io
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                status = pair_cases.main(["migrate", "--publication", str(source), "--out", str(out), "--gallery-source", str(gallery)])
            self.assertEqual(status, 0)
            self.assertEqual(json.loads(buffer.getvalue())["galleryPage"], "rooms")
            self.assertTrue((out / "publication.json").exists())


class CommittedFilesTests(unittest.TestCase):
    """The repository is public: nothing under ``tools/expo_pairs`` may carry a home path or a house value."""

    def test_no_home_path_or_owner_name_is_committed(self):
        forbidden = ("/" + "Users/", "/" + "home/", "step" + "henfenton", "step" + "hens-", ".ts" + ".net", "/private" + "/tmp")
        for path in sorted(PAIRS.rglob("*")):
            if not path.is_file() or path.suffix in (".pyc",):
                continue
            text = path.read_text(encoding="utf-8")
            for needle in forbidden:
                self.assertNotIn(needle, text, f"{path.name} contains {needle}")

    def test_the_pin_names_a_complete_build_and_the_dedicated_simulator(self):
        pin = json.loads((PAIRS / "reference-pin.json").read_text())
        self.assertRegex(pin["bundleSHA256"], r"^[0-9a-f]{64}$")
        self.assertRegex(pin["sourceSHA"], r"^[0-9a-f]{40}$")
        self.assertEqual(pin["simulatorName"], "SH-ref-expo-pinned")


@unittest.skipUnless(shutil.which("node"), "node is not installed")
class NodeHarnessTests(unittest.TestCase):
    def test_the_node_tests_pass(self):
        result = subprocess.run(["node", "--test", *map(str, sorted((PAIRS / "tests").glob("*.test.mjs")))], capture_output=True, text=True, timeout=300)
        self.assertEqual(result.returncode, 0, result.stdout[-3000:] + result.stderr[-2000:])


if __name__ == "__main__":
    unittest.main()
