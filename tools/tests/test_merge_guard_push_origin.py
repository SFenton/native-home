"""``tools/hooks/merge_guard.py``: a push to origin from a checkout whose origin is the product repository (SFenton/native-home)."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import merge_guard  # noqa: E402


def checkout(url: str) -> tempfile.TemporaryDirectory:
    """A throwaway git repository whose ``origin`` is ``url``."""
    tmp = tempfile.TemporaryDirectory()
    subprocess.run(["git", "init", "-q", tmp.name], check=True)
    subprocess.run(["git", "-C", tmp.name, "remote", "add", "origin", url], check=True)
    return tmp


class PushOriginTests(unittest.TestCase):
    def test_product_slug_is_native_home(self):
        self.assertEqual(merge_guard.product_slug(), "sfenton/native-home")

    def test_push_origin_from_a_native_home_checkout_is_allowed(self):
        with checkout("https://github.com/SFenton/native-home.git") as top:
            self.assertIsNone(merge_guard.push_remote_reason(["origin", "agents/x"], top))

    def test_push_origin_from_the_old_private_repo_is_refused(self):
        with checkout("https://github.com/SFenton/Fenton-HASS-Native.git") as top:
            self.assertIsNotNone(merge_guard.push_remote_reason(["origin", "agents/x"], top))


if __name__ == "__main__":
    unittest.main()
