"""The vendored ``tools/devcap.py`` must be byte for byte the canonical FestivalNativeApps copy.

``CANONICAL_SHA256`` is the hash of the canonical ``tools/devcap.py`` at ``CANONICAL_VERSION``
(SFenton/FestivalNativeApps PR #846). When the canonical file changes: copy it here, then update both
constants. Set ``DEVCAP_CANONICAL_COPY`` to a FestivalNativeApps checkout's ``tools/devcap.py`` to also
compare the two files directly.
"""

import hashlib
import os
import re
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "devcap.py"
CANONICAL_VERSION = "1.5.0"
CANONICAL_SHA256 = "96123186657a8dee010b85ec69ba8ed937734da2d3b5bf59bddbc12ce8732cca"


class VendoredDevcapTests(unittest.TestCase):
    def test_matches_the_recorded_canonical_hash(self):
        digest = hashlib.sha256(TOOL.read_bytes()).hexdigest()
        self.assertEqual(digest, CANONICAL_SHA256, "tools/devcap.py differs from the canonical copy: change it in "
                         "FestivalNativeApps first, copy it here byte for byte, and update the recorded hash")

    def test_version_matches_the_recorded_version(self):
        match = re.search(r'^VERSION = "([^"]+)"', TOOL.read_text(encoding="utf-8"), re.M)
        self.assertEqual(match and match.group(1), CANONICAL_VERSION)

    def test_matches_a_canonical_checkout_when_given(self):
        path = os.environ.get("DEVCAP_CANONICAL_COPY")
        if not path:
            self.skipTest("DEVCAP_CANONICAL_COPY not set")
        self.assertEqual(TOOL.read_bytes(), Path(path).read_bytes())


if __name__ == "__main__":
    unittest.main()
