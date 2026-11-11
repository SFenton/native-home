"""``tools/apple_coverage.sh`` is host-only: no instrumented app, no iOS profile merge, no products key, no simulator.

Fails if: the script grows an iOS phase or a products-bundle lookup back (the coverage gate is the logic bar from the Mac host
``swift test``; the hosted tests and journeys are pass or fail under their own plans).
"""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (ROOT / "tools" / "apple_coverage.sh").read_text(encoding="utf-8")


class HostOnlyScriptTests(unittest.TestCase):
    def test_no_ios_phase_or_products_key(self):
        for needle in ("coverage_products_key", "products_cache", "coverage_ios", "ios_uitest", "FENTON_COV_IOS", "--impact", "simctl"):
            self.assertNotIn(needle, SCRIPT, needle)

    def test_help_prints_the_header_and_starts_nothing(self):
        for flag in ("--help", "-h"):
            out = subprocess.run(["bash", str(ROOT / "tools" / "apple_coverage.sh"), flag], capture_output=True, text=True, timeout=60)
            self.assertEqual(out.returncode, 0)
            self.assertIn("Usage: tools/apple_coverage.sh [--changed]", out.stdout)

    def test_the_gate_reads_the_host_report_only(self):
        self.assertIn("xcrun llvm-cov export", SCRIPT)
        self.assertIn("coverage_gate.py", SCRIPT)


if __name__ == "__main__":
    unittest.main()
