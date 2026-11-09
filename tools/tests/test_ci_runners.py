"""Pins which runner label each CI job asks for: the aggregate and the Linux jobs are GitHub-hosted (ci.md)."""
import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github" / "workflows"


class RunnerLabelTests(unittest.TestCase):
    def test_the_aggregate_runs_on_hosted_linux(self):
        text = (WORKFLOWS / "pr-checks.yml").read_text()
        job = text.split("\n  pr-checks:\n", 1)[1]
        self.assertRegex(job, r"(?m)^    runs-on: ubuntu-24\.04$")

    def test_pr_checks_names_no_self_hosted_runner(self):
        self.assertNotIn("self-hosted", re.sub(r"(?m)^\s*#.*$", "", (WORKFLOWS / "pr-checks.yml").read_text()))


if __name__ == "__main__":
    unittest.main()
