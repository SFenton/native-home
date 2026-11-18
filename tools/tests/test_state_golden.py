"""tools/state_golden/generate.py: the pin, the temp checkout and the golden's recorded identity (no Swift build here)."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from state_space_loader import ROOT, load

golden = load("state_golden_generate", "tools/state_golden/generate.py")


class PinTests(unittest.TestCase):
    def test_check_passes_for_the_checked_in_golden(self):
        self.assertEqual(golden.check(), 0)

    def test_the_golden_records_the_pins_tree_id_when_the_pin_is_reachable(self):
        data = json.loads(golden.GOLDEN.read_text(encoding="utf-8"))
        self.assertEqual(data["pin"], "4fe28061")
        try:
            tree = golden.tree_id()
        except subprocess.CalledProcessError:
            self.skipTest("the pin is not in this clone")
        self.assertEqual(data["hassCoreTree"], tree)

    def test_render_is_one_row_per_line_and_valid_json(self):
        text = golden.render({"a.b.c": {"line": "On"}, "a.b.d": {"line": "Off"}}, "t" * 40)
        self.assertEqual(json.loads(text)["rowCount"], 2)
        self.assertEqual(sum(1 for l in text.splitlines() if l.startswith('"a.b.')), 2)


class ExportTests(unittest.TestCase):
    def test_the_export_holds_only_the_three_modules_and_the_probe(self):
        try:
            golden.tree_id()
        except subprocess.CalledProcessError:
            self.skipTest("the pin is not in this clone")
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp)
            golden.export(dest)
            names = sorted(p.name for p in (dest / "Sources").iterdir())
            self.assertEqual(names, ["FentonActivityModel", "HassCore", "HassTelemetry", "StateGoldenProbe"])
            self.assertTrue((dest / "Package.swift").read_text().count(".executableTarget"))

    def test_the_probe_reads_no_house_files(self):
        source = (ROOT / "tools/state_golden/probe/main.swift").read_text(encoding="utf-8")
        for needle in ("HouseConfig", "Keychain", "URLSession"):
            self.assertNotIn(needle, source)


if __name__ == "__main__":
    unittest.main()
