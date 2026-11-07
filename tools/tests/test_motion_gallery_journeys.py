"""Every Motion gallery component has its per-component journey methods (B15 split).

`MotionJourneyTests` writes one explicit method per component per journey, so a component added to
`UKDesignControlsGallery.cases` (or to `componentIDs`) without them would go untested without any failure. This test is that failure.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GALLERY = ROOT / "apple/Sources/HassUI/UIKitPort/Gallery/UKDesignControlsGallery.swift"
JOURNEYS = ROOT / "apple/Apps/iOSUITests/MotionJourneyTests.swift"


def _cap(identifier: str) -> str:
    return identifier[0].upper() + identifier[1:]


class MotionGalleryJourneysTests(unittest.TestCase):
    def setUp(self):
        self.journeys = JOURNEYS.read_text()
        block = re.search(r"componentIDs = \[(.*?)\]", self.journeys, re.S).group(1)
        self.ids = re.findall(r'"(\w+)"', block)
        self.cases = re.findall(r'Case\(id: "(\w+)"', GALLERY.read_text())

    def test_componentIDs_match_the_gallery_cases(self):
        self.assertEqual(sorted(self.ids), sorted(self.cases))

    def test_every_component_has_its_three_journeys(self):
        methods = set(re.findall(r"func (test\w+)\(", self.journeys))
        for identifier in self.cases:
            name = _cap(identifier)
            for expected in (f"testGalleryHas{name}", f"testEveryComponent{name}TogglesItsState",
                             f"testEveryComponent{name}TogglesItsStateWithReduceMotion"):
                self.assertIn(expected, methods, f"{identifier}: missing {expected}")

    def test_no_journey_for_a_component_the_gallery_lacks(self):
        known = {_cap(i) for i in self.cases}
        for name in re.findall(r"func testGalleryHas(\w+)\(", self.journeys):
            self.assertIn(name, known)


if __name__ == "__main__":
    unittest.main()
