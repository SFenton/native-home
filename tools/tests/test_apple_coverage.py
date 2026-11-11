"""The products key the coverage export looks up (``coverage_products_key`` in ``tools/apple_coverage.sh``) against the key
``tools/ios_uitest.sh`` builds under. Runs the real shell function; nothing builds or boots.

Fails if: apple_coverage.sh leaves FENTON_HOSTED_BUILD_SETTINGS out of the key on hosted CI (the export then reads a folder
nobody built: "no FentonHome.app under Binaries/"), or adds them locally, where ios_uitest.sh does not.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import products_cache as pc  # noqa: E402

SCRIPT = (ROOT / "tools" / "apple_coverage.sh").read_text(encoding="utf-8")
UITEST = (ROOT / "tools" / "ios_uitest.sh").read_text(encoding="utf-8")
HOSTED = "ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO"
IMPACT = ["CLANG_ENABLE_CODE_COVERAGE=YES", "CLANG_COVERAGE_MAPPING=YES"]


def coverage_key(env: dict) -> str:
    """Run the script's own function and return the key it prints."""
    function = re.search(r"^coverage_products_key\(\) \{.*?^\}$", SCRIPT, re.S | re.M)
    assert function, "coverage_products_key is gone from apple_coverage.sh"
    base = {k: v for k, v in os.environ.items() if not k.startswith(("FENTON_", "RUNNER_"))}
    # Both sides hash the same tree and ask the same installed Xcode.
    code = f'ROOT="{ROOT}"\n{function.group(0)}\ncoverage_products_key'
    out = subprocess.run(["bash", "-c", code], env={**base, **env}, capture_output=True, text=True, check=True)
    return out.stdout.strip()


def build_key(settings: list) -> str:
    """The key ios_uitest.sh derives: products_cache.py over the settings it passes."""
    return pc.products_key(settings, ROOT)


class CoverageProductsKeyTests(unittest.TestCase):
    def test_hosted_ci_key_matches_the_build(self):
        env = {"FENTON_CI_HOSTED": "1", "RUNNER_ENVIRONMENT": "github-hosted", "FENTON_HOSTED_BUILD_SETTINGS": HOSTED}
        self.assertEqual(coverage_key(env), build_key(IMPACT + HOSTED.split()))
        self.assertNotEqual(coverage_key(env), build_key(IMPACT))

    def test_local_key_matches_the_build(self):
        self.assertEqual(coverage_key({}), build_key(IMPACT))

    def test_settings_without_hosted_mode_are_ignored_like_the_build(self):
        # ios_uitest.sh adds them only when CI_HOSTED is 1 (hosted flag AND a github-hosted runner).
        env = {"FENTON_HOSTED_BUILD_SETTINGS": HOSTED}
        self.assertEqual(coverage_key(env), build_key(IMPACT))
        self.assertEqual(coverage_key({**env, "FENTON_CI_HOSTED": "1", "RUNNER_ENVIRONMENT": "self-hosted"}), build_key(IMPACT))

    def test_build_side_still_adds_them_under_the_same_condition(self):
        self.assertIn('[[ "${FENTON_CI_HOSTED:-}" == 1 && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] && CI_HOSTED=1', UITEST)
        self.assertIn('if [[ $CI_HOSTED == 1 && -n "${FENTON_HOSTED_BUILD_SETTINGS:-}" ]]', UITEST)
        self.assertIn("coverage_products_key", SCRIPT.split("PRODUCTS_KEY=", 1)[1].splitlines()[0])


if __name__ == "__main__":
    unittest.main()
