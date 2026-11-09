"""``tools/hooks/merge_guard.py``: a push to origin from a checkout whose origin is the product repository (SFenton/native-home)."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import merge_guard  # noqa: E402

#: Keeps the user's and the system's git config (``url.*.insteadOf``, ``safe.directory``) out of the throwaway repository.
ISOLATED = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}


def checkout(url: str) -> tempfile.TemporaryDirectory:
    """A throwaway git repository whose ``origin`` is ``url``."""
    tmp = tempfile.TemporaryDirectory()
    subprocess.run(["git", "init", "-q", tmp.name], check=True)
    subprocess.run(["git", "-C", tmp.name, "remote", "add", "origin", url], check=True)
    return tmp


class PushOriginTests(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.dict("os.environ", ISOLATED)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_product_slug_is_native_home(self):
        """The product repository the guard compares origin with is SFenton/native-home.

        Fails if: ``product_repo`` in ``tools/triage/config.json`` (or the fallback in ``merge_guard.product_slug``) goes back to another slug.
        """
        self.assertEqual(merge_guard.product_slug(), "sfenton/native-home")

    def test_push_origin_from_a_native_home_checkout_is_allowed(self):
        """A push to origin from a checkout whose origin is native-home is not refused.

        Fails if: ``product_slug()`` stops returning ``sfenton/native-home``, or ``push_remote_reason`` compares origin with anything else.
        """
        with checkout("https://github.com/SFenton/native-home.git") as top:
            self.assertIsNone(merge_guard.push_remote_reason(["origin", "agents/x"], top))

    def test_push_origin_from_the_old_private_repo_is_refused(self):
        """A push to origin from a checkout of the old private repository is still refused.

        Fails if: ``push_remote_reason`` stops comparing origin's push URL with the product slug (for example it allows any origin).
        """
        with checkout("https://github.com/SFenton/Fenton-HASS-Native.git") as top:
            self.assertIsNotNone(merge_guard.push_remote_reason(["origin", "agents/x"], top))


if __name__ == "__main__":
    unittest.main()
