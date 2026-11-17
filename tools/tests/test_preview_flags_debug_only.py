"""The preview state flags are DEBUG only: every flag source file is wrapped in `#if os(iOS) && DEBUG` and the one
process switch they set (`UKMotion.reduceMotionOverride`) is declared inside `#if DEBUG`, so a release build holds none of it."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GALLERY = ROOT / "apple/Sources/HassUI/UIKitPort/Gallery"
FILES = ["UKServerUIPreviewFlags.swift", "UKServerUIPreviewFaults.swift", "UKServerUIPreview.swift",
         "UKServerUIPreviewFixtures.swift", "UKServerUIPreviewFixtureServices.swift"]


class PreviewFlagsDebugOnlyTests(unittest.TestCase):
    def test_every_flag_file_is_one_debug_block(self):
        for name in FILES:
            lines = (GALLERY / name).read_text().rstrip("\n").split("\n")
            self.assertEqual(lines[0], "#if os(iOS) && DEBUG", name)
            self.assertEqual(lines[-1], "#endif", name)
            depth = 0
            for number, line in enumerate(lines):
                if re.match(r"\s*#if\b", line):
                    depth += 1
                elif re.match(r"\s*#endif\b", line):
                    depth -= 1
                    self.assertGreaterEqual(depth, 0, f"{name}:{number + 1}")
                    if depth == 0:
                        self.assertEqual(number, len(lines) - 1, f"{name} closes its DEBUG block before the end")
            self.assertEqual(depth, 0, name)

    def test_only_debug_code_names_a_flag_type(self):
        sources = (ROOT / "apple/Sources").rglob("*.swift")
        for path in sources:
            if path.name in FILES:
                continue
            text = path.read_text()
            self.assertNotIn("UKServerUIPreviewFlags", text, str(path))
            self.assertNotIn("UKServerUIPreviewFault", text, str(path))

    def test_the_reduce_motion_override_is_debug_only(self):
        text = (ROOT / "apple/Sources/HassUI/UIKitPort/Design/UKMotion.swift").read_text()
        match = re.search(r"#if DEBUG\n(.*?)#endif", text, re.S)
        self.assertIsNotNone(match)
        self.assertIn("reduceMotionOverride", match.group(1))
        self.assertEqual(len(re.findall(r"static var reduceMotionOverride", text)), 1)

    def test_no_flag_variable_is_read_outside_the_preview(self):
        for path in (ROOT / "apple/Sources").rglob("*.swift"):
            if path.name == "UKServerUIPreviewFlags.swift":
                continue
            for name in ("PAUSE_CONTINUOUS_ANIMATIONS", "FENTON_GALLERY_REDUCE_MOTION"):
                self.assertNotIn(name, path.read_text(), str(path))


if __name__ == "__main__":
    unittest.main()
