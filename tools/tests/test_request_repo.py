"""``tools/request_repo.py``: the request repository's name comes from local configuration, never the repository."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import request_repo  # noqa: E402

NEUTRAL = "example/private-requests"


class ResolveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)

    def write_local(self, text: str) -> None:
        path = request_repo.local_file(self.home)
        path.parent.mkdir(parents=True)
        path.write_text(text)

    def test_nothing_set_is_not_configured(self):
        self.assertIsNone(request_repo.resolve(None, self.home, {}))
        self.assertIsNone(request_repo.resolve("", self.home, {}))
        with self.assertRaises(request_repo.NotConfigured) as caught:
            request_repo.require("", self.home, {})
        self.assertIn(request_repo.ENV_VAR, str(caught.exception))
        self.assertIn(str(request_repo.local_file(self.home)), str(caught.exception))

    def test_require_returns_what_resolve_finds(self):
        self.assertEqual(request_repo.require("", self.home, {request_repo.ENV_VAR: NEUTRAL}), NEUTRAL)

    def test_the_environment_wins_over_the_file_and_the_config(self):
        self.write_local("file/name\n")
        self.assertEqual(request_repo.resolve("config/name", self.home, {request_repo.ENV_VAR: NEUTRAL}), NEUTRAL)

    def test_the_local_file_wins_over_the_config_and_only_its_first_line_counts(self):
        self.write_local(f" {NEUTRAL} \nignored/second\n")
        self.assertEqual(request_repo.resolve("config/name", self.home, {}), NEUTRAL)

    def test_a_configured_value_is_used_when_nothing_local_is_set(self):
        self.assertEqual(request_repo.resolve(NEUTRAL, self.home, {}), NEUTRAL)

    def test_malformed_sources_are_skipped(self):
        self.write_local("not a repo\n")
        self.assertIsNone(request_repo.resolve("also bad", self.home, {request_repo.ENV_VAR: "nope"}))
        self.assertIsNone(request_repo.resolve(["list"], self.home, {}))

    def test_valid_needs_owner_slash_name(self):
        self.assertTrue(request_repo.valid(NEUTRAL))
        for bad in ("", "name", "a/b/c", "a b/c", None, 3):
            self.assertFalse(request_repo.valid(bad), bad)


if __name__ == "__main__":
    unittest.main()
