"""``tools/sim_bad.py``: the bad-simulator list and the pool pick that skips it."""

import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

os.environ["DEVCAP_NO_DEFER"] = "1"
from tools import sim_bad  # noqa: E402

A, B = "AAAAAAAA-0000-0000-0000-000000000001", "BBBBBBBB-0000-0000-0000-000000000002"
NAME = "iPad Pro 11-inch (M5)"
SCRIPT = Path(sim_bad.__file__).resolve()
UITEST = SCRIPT.with_name("ios_uitest.sh")


class FakeGate:
    held: set = set()

    def __init__(self, name, root, slots):
        self.name = name

    def holders(self):
        return [1] if self.name in FakeGate.held else []

    def waiting(self):
        return []


class FakeDevcap:
    """Stands in for the devcap module: devcap's own pick ignores the bad list."""

    Gate = FakeGate

    def __init__(self, sims, devcap_pick):
        self.sims, self.devcap_pick, self.asked_prefer = sims, devcap_pick, "unset"

    def configured_slots(self, pool):
        return 2

    def pick_sim(self, name, size, prefer=None):
        self.asked_prefer = prefer
        return self.devcap_pick

    def list_sims(self):
        return self.sims

    def pool_names(self, name, size):
        return [name] + [f"{name} (pool {i})" for i in range(2, size + 1)]

    def lock_root(self):
        return Path("/nonexistent")

    def device_gate(self, udid):
        return f"device-{udid}"

    def note_released(self, udids, root):
        pass


def two_sims(devcap_pick):
    return FakeDevcap([{"udid": A, "name": NAME}, {"udid": B, "name": f"{NAME} (pool 2)"}], devcap_pick)


class BadListTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.saved = os.environ.get("FENTON_SIM_BAD_DIR")
        os.environ["FENTON_SIM_BAD_DIR"] = self.tmp.name
        self.addCleanup(self.restore)
        FakeGate.held = set()

    def restore(self):
        if self.saved is None:
            os.environ.pop("FENTON_SIM_BAD_DIR", None)
        else:
            os.environ["FENTON_SIM_BAD_DIR"] = self.saved

    def test_marked_is_live_then_expires_after_six_hours(self):
        sim_bad.mark(A.lower(), now=1000)
        self.assertEqual(sim_bad.live(now=1000 + sim_bad.TTL - 1), {A})
        self.assertEqual(sim_bad.live(now=1000 + sim_bad.TTL + 1), set())
        self.assertFalse((Path(self.tmp.name) / A).exists())  # the expired record is removed

    def test_garbage_record_is_ignored(self):
        (Path(self.tmp.name) / B).write_text("not a time")
        self.assertEqual(sim_bad.live(), set())

    def test_pick_passes_good_choice_through(self):
        self.assertEqual(sim_bad.pick(NAME, 2, A, two_sims(A)), (A, None))

    def test_bad_prefer_is_dropped_and_other_member_taken(self):
        sim_bad.mark(A)
        fake = two_sims(A)  # devcap would still hand back the bad base
        self.assertEqual(sim_bad.pick(NAME, 2, A, fake), (B, None))
        self.assertIsNone(fake.asked_prefer)

    def test_busy_good_member_is_still_better_than_a_bad_one(self):
        sim_bad.mark(A)
        FakeGate.held = {f"device-{B}"}
        self.assertEqual(sim_bad.pick(NAME, 2, None, two_sims(A))[0], B)

    def test_all_bad_reports_exhausted_with_disk(self):
        sim_bad.mark(A)
        sim_bad.mark(B)
        udid, msg = sim_bad.pick(NAME, 2, None, two_sims(A))
        self.assertIsNone(udid)
        self.assertRegex(msg, r"^INFRA: pool exhausted \(2 bad, disk \d+% used\)$")

    def test_none_available_is_reported(self):
        udid, msg = sim_bad.pick(NAME, 2, None, FakeDevcap([], None))
        self.assertIsNone(udid)
        self.assertIn("no available simulator", msg)

    def test_cli_mark_and_list(self):
        env = {"PATH": "/usr/bin:/bin", "FENTON_SIM_BAD_DIR": self.tmp.name}
        subprocess.run([sys.executable, str(SCRIPT), "mark", B], env=env, check=True)
        out = subprocess.run([sys.executable, str(SCRIPT), "list"], env=env, capture_output=True, text=True, check=True)
        self.assertEqual(out.stdout.split(), [B])


FAKE_DEVCAP = """
from pathlib import Path
UDIDS = ["AAAAAAAA-0000-0000-0000-000000000001", "BBBBBBBB-0000-0000-0000-000000000002"]
def configured_slots(pool): return 2
def pick_sim(name, size, prefer=None): return UDIDS[0]
def list_sims(): return [{"udid": u, "name": n} for u, n in zip(UDIDS, ["iPad", "iPad (pool 2)"])]
def pool_names(name, size): return [name, name + " (pool 2)"]
def lock_root(): return Path("/nonexistent")
def device_gate(udid): return "device-" + udid
def note_released(udids, root): pass
class Gate:
    def __init__(self, *a): pass
    def holders(self): return []
    def waiting(self): return []
"""


class UitestBehaviourTests(unittest.TestCase):
    """ios_uitest.sh's run_family, pick_udid and process_family, extracted and run against stubs (the run_health pattern)."""

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.tmp = Path(self.tmpdir.name)
        (self.tmp / "tools").mkdir()
        (self.tmp / "bin").mkdir()
        (self.tmp / "tools" / "sim_bad.py").write_text(SCRIPT.read_text())
        (self.tmp / "tools" / "sim_slim.sh").write_text("exit 0\n")
        (self.tmp / "tools" / "sim_slim.sh").chmod(0o755)
        (self.tmp / "tools" / "xc_watch.py").write_text("import sys\nsys.exit(0)\n")
        (self.tmp / "bin" / "xcrun").write_text("#!/bin/sh\nexit 0\n")
        (self.tmp / "bin" / "xcrun").chmod(0o755)
        self.bad = self.tmp / "bad"
        self.last = self.tmp / "apple" / ".build" / "uitest-ipad.udid"

    def body(self, *names):
        text = UITEST.read_text()
        out = []
        for name in names:
            start = text.index(f"\n{name}() {{") + 1
            out.append(text[start:text.index("\n}\n", start) + 3])
        return "\n".join(out)

    def bash(self, script):
        env = {"PATH": f"{self.tmp / 'bin'}:/usr/bin:/bin:{Path(sys.executable).parent}", "FENTON_SIM_BAD_DIR": str(self.bad)}
        return subprocess.run(["bash", "-c", f'ROOT="{self.tmp}"; CI_HOSTED=0; EXTRA=()\n{script}'], env=env,
                              capture_output=True, text=True, timeout=60)

    def run_family(self, healthy, preexisting_last=None):
        if preexisting_last:
            self.last.parent.mkdir(parents=True, exist_ok=True)
            self.last.write_text(preexisting_last + "\n")
        fn = "return 0" if healthy else "return 1"
        return self.bash(f"{self.body('run_family')}\nsim_healthy() {{ {fn}; }}\nrun_family ipad {A}")

    def test_unhealthy_twice_is_126_marks_bad_and_drops_the_warm_pick(self):
        run = self.run_family(healthy=False, preexisting_last=A)
        self.assertEqual(run.returncode, 126, run.stderr)
        self.assertIn("INFRA: simulator unhealthy", run.stdout)
        self.assertEqual([p.name for p in self.bad.iterdir()], [A])
        self.assertFalse(self.last.exists())

    def test_unhealthy_leaves_another_members_warm_pick_alone(self):
        self.run_family(healthy=False, preexisting_last=B)
        self.assertEqual(self.last.read_text().strip(), B)

    def test_healthy_writes_the_warm_pick_and_clears_an_old_mark(self):
        self.bad.mkdir()
        (self.bad / A).write_text("1\n")
        run = self.run_family(healthy=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual(self.last.read_text().strip(), A)
        self.assertEqual(list(self.bad.iterdir()), [])

    def test_every_member_bad_prints_exhausted_and_process_family_is_126(self):
        (self.tmp / "tools" / "devcap.py").write_text(FAKE_DEVCAP)
        self.bad.mkdir()
        for udid in (A, B):
            (self.bad / udid).write_text(f"{int(time.time())}\n")
        stubs = "pinned_name() { :; }\nsim_pool_list() { echo x; }\nsim_pool_has() { cat >/dev/null; }\ndevice_name() { echo iPad; }\n"
        run = self.bash(stubs + self.body("pick_udid", "process_family") + "\nLANE=t; process_family ipad")
        self.assertEqual(run.returncode, 126, run.stdout + run.stderr)
        self.assertRegex(run.stderr, r"INFRA: pool exhausted \(2 bad, disk \d+% used\)")

    def test_one_good_member_is_picked(self):
        (self.tmp / "tools" / "devcap.py").write_text(FAKE_DEVCAP)
        self.bad.mkdir()
        (self.bad / A).write_text(f"{int(time.time())}\n")
        run = self.bash("pinned_name() { :; }\n" + self.body("pick_udid") + "\npick_udid ipad iPad /nonexistent")
        self.assertEqual((run.returncode, run.stdout.strip()), (0, B), run.stderr)

    def test_syntax(self):
        subprocess.run(["bash", "-n", str(UITEST)], check=True)


class ClearTests(BadListTests):
    def test_clear_one_then_all(self):
        sim_bad.mark(A)
        sim_bad.mark(B)
        sim_bad.clear(A.lower())
        self.assertEqual(sim_bad.live(), {B})
        sim_bad.clear()
        self.assertEqual(sim_bad.live(), set())

    def test_cli_clear(self):
        sim_bad.mark(A)
        env = {"PATH": "/usr/bin:/bin", "FENTON_SIM_BAD_DIR": self.tmp.name}
        subprocess.run([sys.executable, str(SCRIPT), "clear", A], env=env, check=True)
        self.assertEqual(sim_bad.live(), set())


if __name__ == "__main__":
    unittest.main()
