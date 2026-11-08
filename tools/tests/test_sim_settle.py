"""``tools/sim_settle.sh`` settle rule and ``tools/ci_heartbeat.sh`` wrapper."""

import subprocess
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]


def settled(l1, l5):
    return subprocess.run(["bash", str(TOOLS / "sim_settle.sh"), "--decide", str(l1), str(l5)]).returncode == 0


class SettleRuleTests(unittest.TestCase):
    def test_low_load_is_settled_whatever_the_five_minute_load(self):
        self.assertTrue(settled(5.2, 3.0))
        self.assertTrue(settled(29.9, 1.0))

    def test_mid_load_is_settled_only_when_below_half_the_five_minute_load(self):
        self.assertTrue(settled(40, 120))
        self.assertFalse(settled(40, 70))
        self.assertFalse(settled(40, 80))

    def test_high_load_is_never_settled(self):
        self.assertFalse(settled(60, 500))
        self.assertFalse(settled(300, 600))

    def test_unknown_family_is_a_usage_error(self):
        self.assertEqual(subprocess.run(["bash", str(TOOLS / "sim_settle.sh"), "watch"], capture_output=True).returncode, 2)


class HeartbeatTests(unittest.TestCase):
    def test_run_passes_the_exit_status_through_and_beats_while_it_runs(self):
        out = subprocess.run(["bash", str(TOOLS / "ci_heartbeat.sh"), "run", "-i", "1", "--", "bash", "-c", "sleep 2.5; exit 3"],
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 3)
        self.assertGreaterEqual(out.stdout.count("heartbeat "), 2)

    def test_run_stops_the_loop_when_the_command_ends(self):
        out = subprocess.run(["bash", str(TOOLS / "ci_heartbeat.sh"), "run", "-i", "1", "--", "true"], capture_output=True, text=True, timeout=10)
        self.assertEqual(out.returncode, 0)

    def test_a_line_names_load_memory_swap_disk_and_top_processes(self):
        line = subprocess.run(["bash", str(TOOLS / "ci_heartbeat.sh"), "once"], capture_output=True, text=True).stdout
        for field in ("load[", "memfree[", "swap[", "vm[", "disk[", "top["):
            self.assertIn(field, line)


if __name__ == "__main__":
    unittest.main()
