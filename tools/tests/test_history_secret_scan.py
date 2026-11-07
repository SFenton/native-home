"""Tests for tools/history_secret_scan.sh with a stub gitleaks on PATH: arguments, exit codes (leaks versus errors), counts by
rule and no secret values. Reports go to a temporary folder (HISTORY_SCAN_OUT), never the real build/secret-scan/."""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "history_secret_scan.sh"
#: Modes: clean (exit 0, empty report), findings (exit 3, three findings), error (exit 1 like a real gitleaks error, no report),
#: crash (exit 2), lying (exit 3 but an empty report), noreport (exit 0 but no report), garbage (exit 0, unparsable report).
STUB = """#!/usr/bin/env python3
import json, sys
args = sys.argv[1:]
open(sys.argv[0] + ".args", "w").write(" ".join(args))
mode = open(sys.argv[0] + ".mode").read()
path = args[args.index("--report-path") + 1]
if mode == "error":
    sys.exit(1)
if mode == "crash":
    sys.exit(2)
if mode == "noreport":
    sys.exit(0)
if mode == "garbage":
    open(path, "w").write("{not json")
    sys.exit(0)
found = [] if mode in ("clean", "lying") else [{"RuleID": "generic-api-key", "Secret": "REDACTED-VALUE-1"},
                                               {"RuleID": "generic-api-key", "Secret": "REDACTED-VALUE-2"},
                                               {"RuleID": "private-key", "Secret": "REDACTED-VALUE-3"}]
json.dump(found, open(path, "w"))
sys.exit(3 if mode in ("findings", "lying") else 0)
"""


class HistorySecretScanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir()
        self.out = Path(self.tmp.name) / "out"

    def stub(self, mode: str):
        path = self.bin / "gitleaks"
        path.write_text(STUB)
        path.chmod(0o755)
        Path(str(path) + ".mode").write_text(mode)

    def run_script(self, path: str):
        env = {**os.environ, "PATH": path, "HISTORY_SCAN_OUT": str(self.out)}
        return subprocess.run(["bash", str(SCRIPT)], capture_output=True, text=True, env=env)

    def with_stub(self):
        return self.run_script(f"{self.bin}:/usr/bin:/bin")

    def test_missing_gitleaks_stops_with_exit_2_and_installs_nothing(self):
        if subprocess.run(["bash", "-c", "PATH=/usr/bin:/bin command -v gitleaks"], capture_output=True).returncode == 0:
            self.skipTest("gitleaks is installed in a system folder")
        proc = self.run_script("/usr/bin:/bin")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("not installed", proc.stderr)

    def test_findings_are_summarised_by_rule_and_values_never_printed(self):
        self.stub("findings")
        proc = self.with_stub()
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("3 finding(s)", proc.stdout)
        self.assertIn("generic-api-key: 2", proc.stdout)
        self.assertIn("private-key: 1", proc.stdout)
        self.assertNotIn("REDACTED-VALUE", proc.stdout + proc.stderr)

    def test_every_branch_with_redaction_and_leaks_asked_to_exit_3(self):
        self.stub("clean")
        proc = self.with_stub()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        args = (self.bin / "gitleaks.args").read_text()
        for part in ("--redact", "--log-opts=--all", "--exit-code 3", str(self.out / "report.json")):
            self.assertIn(part, args)
        self.assertIn("0 finding(s)", proc.stdout)

    def test_the_triaged_ignore_file_is_passed_and_lists_only_fingerprints(self):
        """Fails if: the scan stops honouring the repo-root .gitleaksignore, or the file holds anything but comments and
        fingerprints (a secret value pasted into it)."""
        self.stub("clean")
        self.with_stub()
        self.assertIn("--gitleaks-ignore-path .gitleaksignore", (self.bin / "gitleaks.args").read_text())
        ignore = SCRIPT.parents[1] / ".gitleaksignore"
        lines = [line for line in ignore.read_text().splitlines() if line and not line.startswith("#")]
        self.assertTrue(lines)
        for line in lines:
            self.assertRegex(line, r"^[0-9a-f]{40}:[^:\s]+:[a-z0-9-]+:\d+$")

    def test_the_config_is_passed_and_allowlists_only_existing_files_per_rule(self):
        """Fails if: the scan stops passing .gitleaks.toml, the config drops the default rules, an allowlist has no rule
        (a global allowlist), is not a single file path, or names a file that no longer exists."""
        self.stub("clean")
        self.with_stub()
        self.assertIn("--config .gitleaks.toml", (self.bin / "gitleaks.args").read_text())
        root = SCRIPT.parents[1]
        text = (root / ".gitleaks.toml").read_text()
        self.assertIn("useDefault = true", text)
        self.assertNotRegex(text, r"(?m)^\[allowlist\]", "no global [allowlist]; use per-file [[allowlists]] with targetRules")
        self.assertNotRegex(text, r"(?m)^\s*(regexes|stopwords|commits)\s*=")
        blocks = text.split("[[allowlists]]")[1:]
        self.assertTrue(blocks)
        for block in blocks:
            self.assertRegex(block, r'targetRules = \["[a-z-]+"(, "[a-z-]+")*\]')
            paths = re.findall(r"paths = \[\'\'\'(.+?)\'\'\'\]", block)
            self.assertEqual(len(paths), 1, block)
            self.assertRegex(paths[0], r"^\^[\w./\\-]+\$$")
            path = paths[0][len("^"):-1].replace("\\", "")
            self.assertTrue((root / path).is_file(), path)
            self.assertTrue(re.search(paths[0], path))
            for other in ("foo/" + path, "/abs/" + path, path + ".bak"):
                self.assertIsNone(re.search(paths[0], other), other)

    def test_reports_land_in_the_override_folder_not_the_real_one(self):
        self.stub("findings")
        self.with_stub()
        self.assertTrue((self.out / "report.json").is_file())

    def test_a_gitleaks_error_exit_1_is_a_failed_scan_not_findings(self):
        self.stub("error")
        proc = self.with_stub()
        self.assertEqual(proc.returncode, 2)
        self.assertIn("failed (exit 1)", proc.stderr)
        self.assertNotIn("finding(s)", proc.stdout)

    def test_a_crashing_gitleaks_is_exit_2(self):
        self.stub("crash")
        self.assertEqual(self.with_stub().returncode, 2)

    def test_a_missing_or_unparsable_report_is_a_failed_scan(self):
        for mode in ("noreport", "garbage"):
            self.stub(mode)
            proc = self.with_stub()
            self.assertEqual(proc.returncode, 2, mode)
            self.assertNotIn("0 finding(s)", proc.stdout, mode)

    def test_leaks_reported_with_an_empty_report_is_a_failed_scan(self):
        self.stub("lying")
        proc = self.with_stub()
        self.assertEqual(proc.returncode, 2)
        self.assertIn("treating as failed", proc.stderr)


if __name__ == "__main__":
    unittest.main()
