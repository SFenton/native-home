"""``tools/sim_settle.sh`` settle rule and ``tools/ci_heartbeat.sh`` wrapper."""

import os
import subprocess
import tempfile
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


POOL = """== Devices ==
-- iOS 26.0 --
    iPhone 17 (1111AAAA-0000-0000-0000-000000000001) (Shutdown)
    iPad Pro 11-inch (M5) (3333CCCC-0000-0000-0000-000000000003) (Shutdown)
    iPhone Duo (AAAAAAAA-0000-0000-0000-00000000000A) (Shutdown)
-- iOS 27.0 --
    iPhone 17 (2222BBBB-0000-0000-0000-000000000002) (Shutdown)
    iPad Pro 11-inch (M5) (4444DDDD-0000-0000-0000-000000000004) (Shutdown)
    iPhone Duo (BBBBBBBB-0000-0000-0000-00000000000B) (Shutdown)
"""


class SettlePicksTheTestedSimulatorTests(unittest.TestCase):
    """Settle and the journey runner resolve a family through tools/sim_pool.sh, so a name listed once per runtime picks one device."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.pool = Path(self.tmp.name) / "pool.txt"
        self.pool.write_text(POOL)
        stub = Path(self.tmp.name) / "bin" / "xcrun"
        stub.parent.mkdir()
        stub.write_text("#!/bin/bash\nexit 0\n")
        stub.chmod(0o755)
        self.env = dict(os.environ)
        self.env.update({"PATH": f"{stub.parent}:{self.env['PATH']}", "FENTON_SIM_LIST_FILE": str(self.pool),
                         "FENTON_SETTLE_CAP": "0", "FENTON_SETTLE_DWELL": "0", "FENTON_SETTLE_POLL": "1"})

    def resolver(self, family):
        script = f'source "{TOOLS}/sim_pool.sh"; sim_pool_family_udid {family}'
        return subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=self.env).stdout.strip()

    def settle(self, family):
        return subprocess.run(["bash", str(TOOLS / "sim_settle.sh"), family], capture_output=True, text=True, env=self.env, timeout=60).stdout

    def test_duo_with_two_runtimes_boots_the_resolver_udid(self):
        want = self.resolver("duo")
        self.assertEqual(want, "AAAAAAAA-0000-0000-0000-00000000000A")
        self.assertIn(f"settle: booting the duo simulator {want} (wall", self.settle("duo"))

    def test_iphone_and_ipad_keep_their_first_listed_device(self):
        self.assertEqual(self.resolver("iphone"), "1111AAAA-0000-0000-0000-000000000001")
        self.assertEqual(self.resolver("ipad"), "3333CCCC-0000-0000-0000-000000000003")
        self.assertIn("simulator 1111AAAA-0000-0000-0000-000000000001 (wall", self.settle("iphone"))

    def test_the_test_override_still_wins(self):
        self.env["FENTON_SETTLE_UDID"] = "CAFE"
        self.assertIn("settle: booting the duo simulator CAFE (wall", self.settle("duo"))

    def test_a_pinned_name_that_is_absent_resolves_to_nothing(self):
        self.env["FENTON_SIM_DUO"] = "Missing Duo"
        self.assertEqual(self.resolver("duo"), "")


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
