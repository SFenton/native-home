"""Pins which runner label each CI job asks for (owner, 2026-11-05): Python-only jobs run on any Mac runner."""
import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github" / "workflows"


def runs_on(workflow: str) -> dict:
    """Map each job name in a workflow file to its `runs-on` label list."""
    result, job = {}, None
    for line in (WORKFLOWS / workflow).read_text().splitlines():
        m = re.match(r"^  ([a-z-]+):\s*$", line)
        if m:
            job = m.group(1)
        m = re.match(r"^    runs-on: \[(.*?)\]\s*(#.*)?$", line)
        if m and job:
            result[job] = [x.strip() for x in m.group(1).split(",")]
    return result


HASS = ["self-hosted", "macOS", "hass"]


class RunnerLabelTests(unittest.TestCase):
    def test_aggregate_takes_any_mac_runner_while_private(self):
        # The aggregate is a Mac while the repo is private and Linux once public (hosted CI, ci.md), one job so the check name stays.
        text = (WORKFLOWS / "pr-checks.yml").read_text()
        self.assertIn("""runs-on: ${{ github.event.repository.private && fromJSON('["self-hosted","macOS"]') || 'ubuntu-24.04' }}""", text)

    def test_disk_heavy_jobs_run_on_the_macbook(self):
        """The mini lacks disk (owner, 2026-11-07): every job with the 30 GB pre-flight, and repo-checks, say hass."""
        jobs = runs_on("pr-checks.yml")
        for job in ("scope", "repo-checks", "swift-test", "build-release"):
            self.assertEqual(jobs[job], HASS, job)
        self.assertEqual(runs_on("tool-tests.yml")["tool-tests"], HASS)


if __name__ == "__main__":
    unittest.main()
