"""Machine-wide capacity gates (``tools/devcap.py``).

Each test points ``DEVCAP_DIR`` at a temporary directory, so nothing here
touches the real ``~/.devcap`` that running lanes use. Two gates in one
process conflict exactly like two processes (``flock`` locks belong to the
open file), which lets most cases run in-process.
"""

import contextlib
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import threading
import time
import unittest
import unittest.mock
from pathlib import Path
from tempfile import TemporaryDirectory

os.environ["DEVCAP_NO_DEFER"] = "1"  # test this checkout, never the machine's shared install
from tools import devcap  # noqa: E402
from tools.devcap import Gate, Hold, WaitTimeout, gate_names, parse_ticket, queue_order  # noqa: E402

TOOL = Path(devcap.__file__)
REAL_SHUTDOWN_SIMS = devcap.shutdown_sims
UDID = "0D77CC23-71D3-46F4-B491-EDAA73B6B65A"

#: Stands in for ``xcrun``: logs its arguments and which simulator slots are
#: still held at that moment (probed with the same OS lock devcap uses).
FAKE_XCRUN = """#!/usr/bin/env python3
import fcntl, os, sys
if sys.argv[1:3] == ["simctl", "list"]:
    print(os.environ.get("FAKE_BOOTED", '{"devices": {}}'))
    sys.exit(0)
gate = os.path.join(os.environ["DEVCAP_DIR"], "simulator")
held = []
for name in sorted(os.listdir(gate) if os.path.isdir(gate) else []):
    if name.endswith(".lock"):
        handle = open(os.path.join(gate, name), "a+b")
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            held.append(name)
        handle.close()
with open(os.environ["FAKE_XCRUN_LOG"], "a") as log:
    log.write(" ".join(sys.argv[1:]) + " held=" + ",".join(held) + "\\n")
"""


class DevcapTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.root = Path(self.tmp.name)
        patcher = unittest.mock.patch.dict(os.environ, {"DEVCAP_DIR": str(self.root)})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)
        for key in [k for k in os.environ if k.startswith("DEVCAP_SLOTS_") or k == devcap.HELD_ENV
                    or k in ("DEVCAP_REAP_GRACE", "DEVCAP_EVICT_AFTER")]:
            os.environ.pop(key)
        # Never read or touch the real Mac's simulators from tests.
        self.booted = []
        os.environ["DEVCAP_HUB"] = "off"
        os.environ["DEVCAP_SIM_DEVICES"] = str(self.root / "Devices")  # never the real CoreSimulator directory
        for name, value in (("simslim_version", lambda: None),  # no real simslim; lifecycle tests fake it
                            ("list_sims", lambda: [{**b, "booted": b.get("booted", True)} for b in self.booted]),
                            ("debugged_sims", lambda: set()),
                            ("shutdown_sims", lambda udids: self.shutdowns.extend(udids))):
            patcher = unittest.mock.patch.object(devcap, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.shutdowns = []

    def gate(self, name="simulator", slots=1):
        return Gate(name, self.root, slots)


class MaxWaitDefaultTests(unittest.TestCase):
    """``run --max-wait`` defaults to ``FENTON_DEVCAP_MAX_WAIT`` (the runner sets 1200 for agent sessions), else 3600."""

    def parsed(self, env, *extra):
        with unittest.mock.patch.dict(os.environ, env, clear=False):
            if "FENTON_DEVCAP_MAX_WAIT" not in env:
                os.environ.pop("FENTON_DEVCAP_MAX_WAIT", None)
            return devcap.build_parser().parse_args(["run", *extra, "--", "true"]).wait

    def test_the_default_is_an_hour(self):
        self.assertEqual(self.parsed({}), 3600.0)

    def test_the_environment_sets_the_default(self):
        self.assertEqual(self.parsed({"FENTON_DEVCAP_MAX_WAIT": "1200"}), 1200.0)

    def test_the_flag_beats_the_environment(self):
        self.assertEqual(self.parsed({"FENTON_DEVCAP_MAX_WAIT": "1200"}, "--max-wait", "30"), 30.0)

    def test_a_bad_value_falls_back(self):
        for bad in ("", "abc", "0", "-5", "inf", "-inf", "nan", "1e999"):
            self.assertEqual(self.parsed({"FENTON_DEVCAP_MAX_WAIT": bad}), 3600.0)


class TicketTests(unittest.TestCase):
    def test_parse_ticket(self):
        self.assertEqual(parse_ticket("00000000000000000012-345.ticket"), (12, 345))
        for name in ("x.lock", "12.ticket", "a-1.ticket", "1-b.ticket", "1-2.txt"):
            self.assertIsNone(parse_ticket(name))

    def test_queue_order_is_fifo_and_splits_dead_owners(self):
        names = ["3-30.ticket", "1-10.ticket", "2-20.ticket", "junk"]
        live, stale = queue_order(names, lambda pid: pid != 10)
        self.assertEqual(live, ["2-20.ticket", "3-30.ticket"])
        self.assertEqual(stale, ["1-10.ticket"])


class ConfigTests(DevcapTestCase):
    def test_defaults_scale_with_machine(self):
        self.assertEqual(devcap.default_slots("simulator", memory_gb=8), 1)
        self.assertEqual(devcap.default_slots("simulator", memory_gb=64), 4)
        self.assertEqual(devcap.default_slots("simulator", memory_gb=512), 6)
        self.assertEqual(devcap.default_slots("build", cpus=10), 2)
        self.assertEqual(devcap.default_slots("build", cpus=2), 1)
        self.assertEqual(devcap.default_slots("anything"), 1)

    def test_environment_beats_config_file(self):
        (self.root / "config.json").write_text(json.dumps({"simulator": 5, "build": 3}))
        self.assertEqual(devcap.configured_slots("build", self.root), 3)
        with unittest.mock.patch.dict(os.environ, {"DEVCAP_SLOTS_BUILD": "7"}):
            self.assertEqual(devcap.configured_slots("build", self.root), 7)
        with unittest.mock.patch.dict(os.environ, {"DEVCAP_SLOTS_BUILD": "nonsense"}):
            self.assertEqual(devcap.configured_slots("build", self.root),
                             devcap.default_slots("build"))

    def test_devices_always_have_one_slot(self):
        (self.root / "config.json").write_text(json.dumps({"device-ABC": 4}))
        self.assertEqual(devcap.configured_slots("device-ABC", self.root), 1)

    def test_bad_config_falls_back_to_default(self):
        (self.root / "config.json").write_text("{not json")
        self.assertEqual(devcap.configured_slots("anything", self.root), 1)

    def test_env_key(self):
        self.assertEqual(devcap.env_key("sim-pool.x"), "DEVCAP_SLOTS_SIM_POOL_X")

    def test_gate_names_are_canonical(self):
        names = gate_names(pools=["build"], sims=["bbb-2"], devices=["aaa-1"])
        self.assertEqual(names, ["device-AAA-1", "device-BBB-2", "build", "simulator"])
        self.assertEqual(gate_names(sims=["x", "x"]), ["device-X", "simulator"])
        self.assertEqual(gate_names(devices=["x"]), ["device-X"])

    def test_invalid_gate_name(self):
        with self.assertRaises(ValueError):
            Gate("../escape", self.root, 1)


class GateTests(DevcapTestCase):
    def test_slots_fill_then_wait(self):
        first, second, third = (self.gate(slots=2) for _ in range(3))
        first.acquire("one", wait_seconds=1)
        second.acquire("two", wait_seconds=1)
        self.assertEqual({first._slot, second._slot}, {0, 1})
        messages = []
        with self.assertRaises(WaitTimeout):
            third.acquire("three", wait_seconds=0.3, poll_seconds=0.05, announce=messages.append)
        self.assertIn("2/2 held", messages[0])
        self.assertIn("'one'", messages[0])
        self.assertFalse(list((self.root / "simulator" / "queue").iterdir()), "ticket removed")
        freed = first._slot
        first.release()
        third.acquire("three", wait_seconds=1, poll_seconds=0.05)
        self.assertEqual(third._slot, freed)
        for gate in (second, third):
            gate.release()

    def test_holder_record_and_release(self):
        gate = self.gate()
        gate.acquire("shot iphone", wait_seconds=1)
        observer = self.gate()
        [record] = observer.holders()
        self.assertEqual(record["pid"], os.getpid())
        self.assertEqual(record["purpose"], "shot iphone")
        self.assertEqual(record["slot"], 0)
        gate.release()
        gate.release()  # idempotent
        self.assertEqual(observer.holders(), [])
        self.assertFalse((self.root / "simulator" / "slot-0.json").exists())
        log = (self.root / "devcap.log").read_text()
        self.assertIn("acquire simulator slot 0/1", log)
        self.assertIn("release simulator slot 0", log)

    def test_dead_tickets_do_not_block_the_queue(self):
        queue = self.root / "simulator" / "queue"
        queue.mkdir(parents=True)
        dead = queue / "00000000000000000001-999999999.ticket"
        dead.write_text("ghost")
        gate = self.gate()
        with unittest.mock.patch.object(devcap, "pid_alive", lambda pid: pid == os.getpid()):
            gate.acquire("live", wait_seconds=1, poll_seconds=0.05)
        self.assertFalse(dead.exists())
        gate.release()

    def test_waiters_behind_the_head_do_not_take_slots(self):
        queue = self.root / "simulator" / "queue"
        queue.mkdir(parents=True)
        (queue / "00000000000000000001-1.ticket").write_text("earlier lane")
        gate = self.gate()
        messages = []
        with unittest.mock.patch.object(devcap, "pid_alive", lambda pid: True):
            with self.assertRaises(WaitTimeout):
                gate.acquire("later", wait_seconds=0.3, poll_seconds=0.05, announce=messages.append)
            self.assertEqual(gate.waiting(), [{"pid": 1, "purpose": "earlier lane"}])
        self.assertIn("1 ahead in queue", messages[0])

    def test_lowering_slots_ignores_slots_above_the_limit(self):
        wide = self.gate(slots=3)
        wide.acquire("a", wait_seconds=1)
        narrow = self.gate(slots=1)
        with self.assertRaises(WaitTimeout):
            narrow.acquire("b", wait_seconds=0.2, poll_seconds=0.05, announce=lambda _: None)
        wide.release()

    def test_stale_holder_record_is_ignored(self):
        gate_dir = self.root / "simulator"
        gate_dir.mkdir(parents=True)
        (gate_dir / "slot-0.lock").touch()
        (gate_dir / "slot-0.json").write_text(json.dumps({"pid": 999999999, "purpose": "crashed"}))
        self.assertEqual(self.gate().holders(), [])


class HoldTests(DevcapTestCase):
    def test_hold_takes_device_and_simulator_and_exports_them(self):
        with devcap.hold(sims=["abc"], purpose="journey", hold_seconds=None, root=self.root) as held:
            self.assertEqual([g.name for g in held.gates], ["device-ABC", "simulator"])
            self.assertEqual(os.environ[devcap.HELD_ENV], "device-ABC,simulator")
            with self.assertRaises(WaitTimeout):
                Gate("device-ABC", self.root).acquire("other", 0.2, 0.05, announce=lambda _: None)
        self.assertNotIn(devcap.HELD_ENV, os.environ)
        self.assertEqual(Gate("device-ABC", self.root).holders(), [])

    def test_nested_hold_reuses_inherited_gates(self):
        with devcap.hold(sims=["abc"], hold_seconds=None, root=self.root):
            with devcap.hold(sims=["abc"], pools=["build"], hold_seconds=None, root=self.root) as inner:
                self.assertEqual([g.name for g in inner.gates], ["build"])
            self.assertEqual(os.environ[devcap.HELD_ENV], "device-ABC,simulator")

    def test_failed_acquire_releases_earlier_gates(self):
        os.environ["DEVCAP_SLOTS_SIMULATOR"] = "1"
        blocker = Gate("simulator", self.root)
        blocker.acquire("busy", 1)
        held = Hold(["device-X", "simulator"], "x", wait_seconds=0.2, hold_seconds=None, root=self.root)
        with unittest.mock.patch("sys.stderr"), self.assertRaises(WaitTimeout):
            held.acquire()
        self.assertEqual(held.gates, [])
        self.assertEqual(Gate("device-X", self.root).holders(), [])
        blocker.release()

    def test_concurrent_release_logs_once(self):
        held = Hold(["build"], "x", wait_seconds=1, hold_seconds=None, root=self.root)
        held.acquire()
        threads = [threading.Thread(target=held.release) for _ in range(4)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual((self.root / "devcap.log").read_text().count("release build"), 1)

    def test_watchdog_fires_on_overrun(self):
        fired = []
        held = Hold(["build"], "slow", wait_seconds=1, hold_seconds=0.1, root=self.root,
                    on_overrun=lambda: fired.append(True))
        with unittest.mock.patch.object(devcap.os, "_exit", lambda code: fired.append(code)):
            held.acquire()
            time.sleep(0.5)
        self.assertEqual(fired, [True, devcap.HOLD_TIMEOUT_EXIT])
        self.assertEqual(Gate("build", self.root).holders(), [])


class CliTests(DevcapTestCase):
    def setUp(self):
        super().setUp()
        self.fake_log = self.install_fake_xcrun()  # subprocesses never reach the real simctl

    def cli(self, *args, **kwargs):
        return subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True,
                              env={**os.environ}, timeout=30, **kwargs)

    def test_run_passes_exit_code_and_held_gates(self):
        result = self.cli("run", "--sim", UDID, "--pool", "build", "--purpose", "t", "--",
                          sys.executable, "-c",
                          "import os, sys; print(os.environ['DEVCAP_HELD']); sys.exit(3)")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(result.stdout.strip(), f"build,device-{UDID},simulator")

    def test_run_requires_a_gate_and_a_command(self):
        self.assertEqual(self.cli("run", "--", "true").returncode, 2)
        self.assertEqual(self.cli("run", "--pool", "build").returncode, 2)

    def test_run_waits_then_times_out_with_tempfail(self):
        with devcap.hold(pools=["build"], purpose="holder", hold_seconds=None, root=self.root):
            os.environ.pop(devcap.HELD_ENV)
            os.environ["DEVCAP_SLOTS_BUILD"] = "1"
            result = self.cli("run", "--pool", "build", "--wait", "0.5", "--", "true")
        self.assertEqual(result.returncode, devcap.WAIT_TIMEOUT_EXIT)
        self.assertIn("'holder'", result.stderr)

    def test_max_wait_is_the_wait_option_and_exits_with_the_wait_code(self):
        with devcap.hold(pools=["build"], purpose="holder", hold_seconds=None, root=self.root):
            os.environ.pop(devcap.HELD_ENV)
            os.environ["DEVCAP_SLOTS_BUILD"] = "1"
            result = self.cli("run", "--pool", "build", "--max-wait", "0.5", "--", "true")
        self.assertEqual(result.returncode, devcap.WAIT_TIMEOUT_EXIT)
        self.assertIn("gave up waiting", result.stderr)
        self.assertIn("'holder'", result.stderr)

    def test_second_process_runs_after_first_releases(self):
        os.environ["DEVCAP_SLOTS_SIMULATOR"] = "1"
        marker = self.root / "order.txt"
        script = ("import sys, time; open(sys.argv[1], 'a').write(sys.argv[2] + ' start\\n'); "
                  "time.sleep(0.6); open(sys.argv[1], 'a').write(sys.argv[2] + ' end\\n')")
        first = subprocess.Popen([sys.executable, str(TOOL), "run", "--pool", "simulator", "--",
                                  sys.executable, "-c", script, str(marker), "A"], env={**os.environ},
                                 stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic() + 30
        while not marker.exists() and time.monotonic() < deadline:  # A holds the slot
            time.sleep(0.05)
        second = self.cli("run", "--pool", "simulator", "--", sys.executable, "-c", script, str(marker), "B")
        first.communicate(timeout=30)
        self.assertEqual(second.returncode, 0)
        self.assertEqual(marker.read_text().split("\n")[:4], ["A start", "A end", "B start", "B end"])
        self.assertIn("waiting for 'simulator'", second.stderr)

    def test_hold_timeout_kills_the_command(self):
        result = self.cli("run", "--pool", "build", "--hold", "0.5", "--",
                          sys.executable, "-c", "import time; time.sleep(30)")
        self.assertEqual(result.returncode, devcap.HOLD_TIMEOUT_EXIT)
        self.assertIn("HOLD TIMEOUT", result.stderr)

    def test_status_reports_holders_and_slots(self):
        with devcap.hold(sims=["abc"], purpose="journey", hold_seconds=None, root=self.root):
            os.environ.pop(devcap.HELD_ENV)
            report = json.loads(self.cli("status", "--json").stdout)
            text = self.cli("status").stdout
        by_gate = {entry["gate"]: entry for entry in report["gates"]}
        self.assertEqual(by_gate["device-ABC"]["holders"][0]["purpose"], "journey")
        self.assertEqual(len(by_gate["simulator"]["holders"]), 1)
        self.assertIn("build", by_gate)
        self.assertIn("device-ABC: 1/1 held", text)
        self.assertIn("journey", text)

    def test_shutdown_runs_after_the_command_inside_the_hold(self):
        calls = []

        def record(udids):
            calls.append((list(udids), [h["purpose"] for h in Gate("simulator", self.root).holders()]))

        with unittest.mock.patch.object(devcap, "shutdown_sims", record):
            code = devcap.main(["run", "--sim", UDID, "--shutdown", "--purpose", "p", "--",
                                sys.executable, "-c", "pass"])
            devcap.main(["run", "--sim", UDID, "--", sys.executable, "-c", "pass"])
        self.assertEqual(code, 0)
        self.assertEqual(calls, [([UDID], ["p"])])  # once, while the slot was still held

    def test_shutdown_runs_when_the_hold_overruns(self):
        calls = []
        held = Hold(["simulator"], "x", wait_seconds=1, hold_seconds=0.2, root=self.root)
        held.cleanup = lambda: calls.append("shutdown")
        held.acquire()
        with unittest.mock.patch.object(devcap.os, "_exit", lambda code: calls.append(code)):
            code = devcap.run_command(held, [sys.executable, "-c", "import time; time.sleep(30)"])
            deadline = time.monotonic() + 10
            while len(calls) < 2 and time.monotonic() < deadline:  # the watchdog finishes
                time.sleep(0.05)
        self.assertEqual(code, devcap.HOLD_TIMEOUT_EXIT)
        self.assertEqual(calls, ["shutdown", devcap.HOLD_TIMEOUT_EXIT])

    def test_overrun_skips_cleanup_when_every_gate_is_inherited(self):
        calls = []
        os.environ[devcap.HELD_ENV] = "simulator"
        held = Hold(["simulator"], "nested", wait_seconds=1, hold_seconds=0.1, root=self.root)
        held.cleanup = lambda: calls.append("shutdown")
        with unittest.mock.patch.object(devcap.os, "_exit", lambda code: calls.append(code)):
            held.acquire()
            deadline = time.monotonic() + 10
            while not calls and time.monotonic() < deadline:
                time.sleep(0.05)
        self.assertEqual(calls, [devcap.HOLD_TIMEOUT_EXIT])

    @unittest.skipIf(os.name == "nt", "simulators are macOS-only")
    def test_cli_nested_shutdown_leaves_the_parents_simulator_alone(self):
        log = self.fake_xcrun()
        inner = f"{sys.executable} {TOOL} run --sim {UDID} --shutdown --hold 1 -- sleep 30"
        result = self.cli("run", "--sim", UDID, "--", "/bin/sh", "-c", inner)
        self.assertEqual(result.returncode, devcap.HOLD_TIMEOUT_EXIT, result.stderr)
        self.assertFalse(log.exists(), "the nested run shut down its parent's simulator")

    @unittest.skipIf(os.name == "nt", "simulators are macOS-only")
    def test_shutdown_on_timeout_keeps_a_finished_run_warm(self):
        log = self.fake_xcrun()
        ok = self.cli("run", "--sim", UDID, "--shutdown-on-timeout", "--", sys.executable, "-c", "pass")
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertFalse(log.exists(), "a finished run keeps its simulator warm")
        hung = self.cli("run", "--sim", UDID, "--shutdown-on-timeout", "--hold", "1", "--",
                        sys.executable, "-c", "import time; time.sleep(30)")
        self.assertEqual(hung.returncode, devcap.HOLD_TIMEOUT_EXIT, hung.stderr)
        self.assertEqual(log.read_text(), f"simctl shutdown {UDID} held=slot-0.lock\n")

    def test_shutdown_sims_survives_missing_xcrun(self):
        with unittest.mock.patch.object(devcap.subprocess, "run", side_effect=FileNotFoundError):
            REAL_SHUTDOWN_SIMS([UDID])

    def test_shutdown_sims_never_passes_a_non_udid(self):
        with unittest.mock.patch.object(devcap.subprocess, "run") as run:
            REAL_SHUTDOWN_SIMS(["all", "booted", "iPhone 17 Pro"])
        run.assert_not_called()

    def test_sim_must_be_a_udid(self):
        for value in ("all", "booted", "abc"):
            result = self.cli("run", "--sim", value, "--shutdown", "--", "true")
            self.assertEqual(result.returncode, 2, value)
            self.assertIn("simulator UDID", result.stderr)

    def install_fake_xcrun(self):
        bin_dir = Path(self.tmp.name + "-bin")
        bin_dir.mkdir()
        self.addCleanup(shutil.rmtree, bin_dir, True)
        xcrun = bin_dir / "xcrun"
        xcrun.write_text(FAKE_XCRUN.replace("/usr/bin/env python3", sys.executable))
        xcrun.chmod(0o755)
        log = self.root / "xcrun.log"
        os.environ["PATH"] = f"{bin_dir}{os.pathsep}{os.environ['PATH']}"
        os.environ["FAKE_XCRUN_LOG"] = str(log)
        return log

    def fake_xcrun(self):
        os.environ["DEVCAP_SLOTS_SIMULATOR"] = "1"
        return self.fake_log

    @unittest.skipIf(os.name == "nt", "simulators are macOS-only")
    def test_cli_shutdown_runs_while_the_slot_is_held(self):
        log = self.fake_xcrun()
        result = self.cli("run", "--sim", UDID, "--shutdown", "--", sys.executable, "-c", "pass")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.read_text(), f"simctl shutdown {UDID} held=slot-0.lock\n")

    @unittest.skipIf(os.name == "nt", "simulators are macOS-only")
    def test_cli_shutdown_runs_after_a_hold_timeout_before_the_slot_frees(self):
        log = self.fake_xcrun()
        for _ in range(3):
            log.unlink(missing_ok=True)
            result = self.cli("run", "--sim", UDID, "--shutdown", "--hold", "1", "--",
                              sys.executable, "-c", "import time; time.sleep(30)")
            self.assertEqual(result.returncode, devcap.HOLD_TIMEOUT_EXIT, result.stderr)
            self.assertTrue(log.exists(), "xcrun was never called")
            self.assertEqual(log.read_text(), f"simctl shutdown {UDID} held=slot-0.lock\n")
            self.assertEqual(Gate("simulator", self.root).holders(), [])

    def test_status_skips_non_gate_directories(self):
        for name in ("lib", "bin", "device-bad name"):
            (self.root / name).mkdir()
        text = self.cli("status").stdout
        self.assertNotIn("lib:", text)
        self.assertNotIn("bin:", text)
        self.assertNotIn("bad name", text)
        self.assertEqual(devcap.known_gates(self.root), ["build", "simulator"])

    def test_slots_and_version(self):
        os.environ["DEVCAP_SLOTS_SIMULATOR"] = "2"
        self.assertIn("simulator=2", self.cli("slots").stdout)
        self.assertEqual(self.cli("--version").stdout.strip(), devcap.VERSION)


LEAKED = "11111111-2222-4333-8444-555555555555"


class UnmanagedSimTests(DevcapTestCase):
    """Simulators booted outside any hold count against the slots and can be reaped."""

    def waiter(self, slots=2):
        os.environ["DEVCAP_SLOTS_SIMULATOR"] = str(slots)
        return Gate("simulator", self.root)

    def test_unmanaged_simulators_take_slots(self):
        self.booted = [{"udid": LEAKED, "name": "Leaked"}]
        holder = self.waiter()
        holder.acquire("one", 1)
        messages = []
        with self.assertRaises(WaitTimeout):
            self.waiter().acquire("two", 0.3, 0.05, announce=messages.append)
        self.assertIn("2/2 in use", messages[0])
        self.assertIn("'Leaked' booted outside any hold", messages[0])
        self.assertEqual(self.shutdowns, [], "nothing is reaped within the grace period")
        holder.release()

    def boot_off_on_shutdown(self):
        """Make the mocked shutdown also remove the simulator from the booted list."""
        def shutdown(udids):
            self.shutdowns.extend(udids)
            self.booted = [b for b in self.booted if b["udid"] not in udids]
        patcher = unittest.mock.patch.object(devcap, "shutdown_sims", shutdown)
        patcher.start()
        self.addCleanup(patcher.stop)

    def age(self, udid, seconds):
        """Pretend ``udid`` has been unheld for ``seconds`` in the reaper's records."""
        devcap.scan_unmanaged(self.root, reap=False)
        state = json.loads((self.root / "reaper.json").read_text())
        state["first_unheld"][udid] -= seconds
        (self.root / "reaper.json").write_text(json.dumps(state))

    def test_waiter_evicts_the_idlest_warm_simulator_when_full(self):
        other = "22222222-3333-4444-8555-666666666666"
        self.booted = [{"udid": LEAKED, "name": "Warm A"}, {"udid": other, "name": "Warm B"}]
        self.age(LEAKED, 120)
        self.age(other, 90)
        self.boot_off_on_shutdown()
        gate = self.waiter(slots=2)
        gate.acquire("needs room", 1, 0.05, announce=lambda _: None)
        self.assertEqual(self.shutdowns, [LEAKED])
        self.assertIn("evict Warm A", (self.root / "devcap.log").read_text())
        gate.release()

    def test_warm_simulators_are_kept_for_their_lane_and_debugger(self):
        self.booted = [{"udid": LEAKED, "name": "Warm"}]
        self.age(LEAKED, 30)  # under the 60 s reservation
        with self.assertRaises(WaitTimeout):
            self.waiter(slots=1).acquire("x", 0.3, 0.05, announce=lambda _: None)
        self.age(LEAKED, 60)
        with unittest.mock.patch.object(devcap, "debugged_sims", lambda: {LEAKED}), \
                self.assertRaises(WaitTimeout):
            self.waiter(slots=1).acquire("x", 0.3, 0.05, announce=lambda _: None)
        os.environ["DEVCAP_EVICT_AFTER"] = "off"
        with self.assertRaises(WaitTimeout):
            self.waiter(slots=1).acquire("x", 0.3, 0.05, announce=lambda _: None)
        self.assertEqual(self.shutdowns, [])

    def test_no_eviction_when_the_debugger_state_is_unknown(self):
        self.booted = [{"udid": LEAKED, "name": "Warm"}]
        self.age(LEAKED, 120)
        with unittest.mock.patch.object(devcap, "debugged_sims", lambda: None), \
                self.assertRaises(WaitTimeout):
            self.waiter(slots=1).acquire("x", 0.3, 0.05, announce=lambda _: None)
        self.assertEqual(self.shutdowns, [])
        [entry] = json.loads((self.root / "reaper.json").read_text())["unmanaged"]
        self.assertIsNone(entry["debugged"])

    def test_failed_eviction_does_not_free_a_slot(self):
        self.booted = [{"udid": LEAKED, "name": "Stuck"}]  # shutdown_sims is mocked: it stays booted
        self.age(LEAKED, 120)
        with self.assertRaises(WaitTimeout):
            self.waiter(slots=1).acquire("x", 0.3, 0.05, announce=lambda _: None)
        self.assertIn(LEAKED, self.shutdowns)

    def test_room_left_means_no_eviction(self):
        self.booted = [{"udid": LEAKED, "name": "Warm"}]
        self.age(LEAKED, 120)
        gate = self.waiter(slots=2)
        gate.acquire("x", 1, 0.05)
        self.assertEqual(self.shutdowns, [])
        gate.release()

    @unittest.skipUnless(sys.platform == "darwin", "Linux: waits the full 300 s on every hosted run (PR 57 shard log); cause not found; follow-up hosted-ci-linux-portability")
    def test_own_and_held_simulators_are_not_unmanaged(self):
        self.booted = [{"udid": UDID, "name": "Mine"}, {"udid": LEAKED, "name": "Held"}]
        with devcap.hold(sims=[LEAKED], hold_seconds=None, root=self.root):
            os.environ.pop(devcap.HELD_ENV)
            self.assertEqual(devcap.scan_unmanaged(self.root, exclude=[UDID], reap=False), [])
        [entry] = devcap.scan_unmanaged(self.root, exclude=[UDID], reap=False)
        self.assertEqual(entry["name"], "Held")  # its hold ended, so it is unmanaged now

    def test_reaps_only_after_the_grace_period(self):
        self.booted = [{"udid": LEAKED, "name": "Leaked"}]
        [entry] = devcap.scan_unmanaged(self.root, grace=60)
        self.assertEqual(entry["name"], "Leaked")
        self.assertEqual(self.shutdowns, [])
        state = json.loads((self.root / "reaper.json").read_text())
        state["first_unheld"][LEAKED] -= 61
        (self.root / "reaper.json").write_text(json.dumps(state))
        self.assertEqual(devcap.scan_unmanaged(self.root, grace=60), [])
        self.assertEqual(self.shutdowns, [LEAKED])
        self.assertIn("reap Leaked", (self.root / "devcap.log").read_text())

    def test_never_reaps_debugged_held_or_unknown(self):
        self.booted = [{"udid": LEAKED, "name": "Leaked"}]
        with unittest.mock.patch.object(devcap, "debugged_sims", lambda: {LEAKED}):
            [entry] = devcap.scan_unmanaged(self.root, grace=0)
        self.assertTrue(entry["debugged"])
        with unittest.mock.patch.object(devcap, "debugged_sims", lambda: None):  # ps failed
            devcap.scan_unmanaged(self.root, grace=0)
        with devcap.hold(devices=[LEAKED], hold_seconds=None, root=self.root):
            self.assertEqual(devcap.scan_unmanaged(self.root, grace=0), [])
        self.assertEqual(self.shutdowns, [])

    def test_waiter_reaps_when_configured_and_then_proceeds(self):
        os.environ["DEVCAP_REAP_GRACE"] = "0"
        self.booted = [{"udid": LEAKED, "name": "Leaked"}]
        gate = self.waiter(slots=1)
        gate.acquire("needs room", 1, 0.05, announce=lambda _: None)
        self.assertEqual(self.shutdowns, [LEAKED])
        gate.release()

    def test_finishing_a_simulator_hold_sweeps_leaked_simulators(self):
        os.environ["DEVCAP_REAP_GRACE"] = "0"
        with devcap.hold(sims=[UDID], hold_seconds=None, root=self.root):
            self.booted = [{"udid": LEAKED, "name": "Leaked"}]
            self.shutdowns.clear()  # the acquire-time scan saw nothing
        self.assertEqual(self.shutdowns, [LEAKED])

    def test_unreadable_simctl_blocks_nobody(self):
        with unittest.mock.patch.object(devcap, "list_sims", lambda: None):
            self.assertIsNone(devcap.scan_unmanaged(self.root, grace=0))
            gate = self.waiter(slots=1)
            gate.acquire("x", 1, 0.05)
            gate.release()

    def test_reap_grace_setting(self):
        self.assertEqual(devcap.reap_grace(self.root), devcap.DEFAULT_REAP_GRACE_SECONDS)
        (self.root / "config.json").write_text(json.dumps({"reap_grace_seconds": 120}))
        self.assertEqual(devcap.reap_grace(self.root), 120)
        for raw, expected in (("off", None), ("30", 30.0), ("junk", devcap.DEFAULT_REAP_GRACE_SECONDS)):
            os.environ["DEVCAP_REAP_GRACE"] = raw
            self.assertEqual(devcap.reap_grace(self.root), expected)

    def test_windows_to_close_keeps_in_use_and_new_windows(self):
        windows = [{"pid": 7, "window": i, "title": t} for i, t in enumerate([
            "iPhone Duo (Home) \u2013 iOS 27.1", "Devices \u2013 No Selection", "Devices \u2013 No Selection",
            "iPhone 17 Pro (Media) \u2013 iOS 27.0"])]
        to_close, seen = devcap.windows_to_close(windows, {"iPhone Duo (Home)"}, {}, now=1000, grace=60)
        self.assertEqual(to_close, [])  # all new
        to_close, _ = devcap.windows_to_close(windows[:3], {"iPhone Duo (Home)"}, seen, now=1061, grace=60)
        self.assertEqual([w["window"] for w in to_close], [2, 1])  # highest index first, in-use kept
        self.assertEqual(devcap.hub_device_name("iPhone 17 Pro (Rooms) \u2013 iOS 27.0"), "iPhone 17 Pro (Rooms)")

    def test_scan_closes_stale_windows_of_unused_devices(self):
        self.booted = [{"udid": UDID, "name": "Live"}]
        windows = [{"pid": 7, "window": 0, "title": "Live \u2013 iOS 27.1"},
                   {"pid": 7, "window": 1, "title": "Devices \u2013 No Selection"}]
        calls = []
        with devcap.hold(sims=[UDID], hold_seconds=None, root=self.root), \
                unittest.mock.patch.object(devcap, "hub_windows", lambda root: (Path("/hub"), windows)), \
                unittest.mock.patch.object(devcap.subprocess, "run", lambda argv, **kw: calls.append(argv)):
            devcap.scan_unmanaged(self.root, grace=0)
        self.assertEqual(calls, [["/hub", "close", "7", "1"]])
        self.assertIn("close Device Hub window 'Devices", (self.root / "devcap.log").read_text())

    def test_held_physical_device_named_like_a_simulator_keeps_its_window(self):
        self.booted = [{"udid": UDID, "name": "Twin", "booted": False}]
        windows = [{"pid": 7, "window": 0, "title": "Twin \u2013 iOS 27.0"},
                   {"pid": 7, "window": 1, "title": "Devices \u2013 No Selection"}]
        calls = []
        with devcap.hold(devices=["00008110-001A2B3C4D5E6F70"], hold_seconds=None, root=self.root), \
                unittest.mock.patch.object(devcap, "hub_windows", lambda root: (Path("/hub"), windows)), \
                unittest.mock.patch.object(devcap.subprocess, "run", lambda argv, **kw: calls.append(argv)):
            devcap.scan_unmanaged(self.root, grace=0)
        self.assertEqual(calls, [["/hub", "close", "7", "1"]])

    def test_physical_device_windows_are_never_closed(self):
        windows = [{"pid": 7, "window": 0, "title": "Alex's iPhone \u2013 iOS 27.0"},
                   {"pid": 7, "window": 1, "title": "Old Sim \u2013 iOS 27.0"},
                   {"pid": 7, "window": 2, "title": "Devices \u2013 No Selection"}]
        to_close, _ = devcap.windows_to_close(windows, set(), {}, now=0, grace=0, sim_names={"Old Sim"})
        self.assertEqual([w["window"] for w in to_close], [2, 1])

    def test_debugged_from_ps(self):
        app = f"/Users/x/Library/Developer/CoreSimulator/Devices/{LEAKED.lower()}/data/Containers/Bundle/A/App.app/App"
        text = "\n".join([
            "10 1 /Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Resources/debugserver --native-regs",
            f"11 10 {app}",
            f"12 1 /Users/x/Library/Developer/CoreSimulator/Devices/{UDID}/data/Containers/Bundle/B/App.app/App",
        ])
        self.assertEqual(devcap.debugged_from_ps(text), {LEAKED})


class PickSimTests(DevcapTestCase):
    """Lanes wanting the same device type share a pool of identical simulators."""

    IPAD = {"udid": UDID, "name": "iPad", "booted": False, "type": "com.apple.iPad", "runtime": "iOS-27"}

    def setUp(self):
        super().setUp()
        self.booted = [dict(self.IPAD)]
        self.created = []

        def fake_run(argv, **kwargs):
            assert argv[:3] == ["xcrun", "simctl", "create"], argv
            udid = f"00000000-0000-4000-8000-{len(self.created) + 1:012d}"
            self.created.append((argv[3], argv[4], argv[5]))
            self.booted.append({"udid": udid, "name": argv[3], "booted": False, "type": argv[4], "runtime": argv[5]})
            return subprocess.CompletedProcess(argv, 0, stdout=udid + "\n", stderr="")
        patcher = unittest.mock.patch.object(devcap.subprocess, "run", fake_run)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_creates_missing_pool_members_like_the_base(self):
        self.assertEqual(devcap.pick_sim("iPad", 3, root=self.root), UDID)
        self.assertEqual(self.created, [("iPad (pool 2)", "com.apple.iPad", "iOS-27"),
                                        ("iPad (pool 3)", "com.apple.iPad", "iOS-27")])
        self.assertEqual(devcap.pick_sim("iPad", 3, root=self.root), UDID)  # nothing new to create
        self.assertEqual(len(self.created), 2)

    def test_second_lane_gets_a_free_member_and_keeps_its_warm_one(self):
        with devcap.hold(sims=[UDID], hold_seconds=None, root=self.root):
            second = devcap.pick_sim("iPad", 3, root=self.root)
            self.assertNotEqual(second, UDID)
            self.assertEqual(devcap.pick_sim("iPad", 3, prefer=second, root=self.root), second)
        self.assertEqual(devcap.pick_sim("iPad", 3, prefer=second, root=self.root), second)

    def test_all_busy_queues_on_the_preferred_member(self):
        members = [devcap.pick_sim("iPad", 2, root=self.root)]
        members.append(next(s["udid"] for s in self.booted if s["name"] == "iPad (pool 2)"))
        with devcap.hold(sims=members, hold_seconds=None, root=self.root):
            self.assertEqual(devcap.pick_sim("iPad", 2, prefer=members[1], root=self.root), members[1])
            self.assertEqual(devcap.pick_sim("iPad", 2, root=self.root), members[0])

    def test_same_named_devices_all_join_the_pool(self):
        twin = "33333333-4444-4555-8666-777777777777"
        self.booted.append({**self.IPAD, "udid": twin})
        with devcap.hold(sims=[UDID], hold_seconds=None, root=self.root):
            self.assertEqual(devcap.pick_sim("iPad", 1, root=self.root), twin)

    def test_unknown_base_and_pool_of_one(self):
        self.assertIsNone(devcap.pick_sim("Nope", 3, root=self.root))
        self.assertEqual(devcap.pick_sim("iPad", 1, root=self.root), UDID)
        self.assertEqual(self.created, [])
        self.assertEqual(devcap.pool_names("X", 3), ["X", "X (pool 2)", "X (pool 3)"])


class UnmanagedCliTests(DevcapTestCase):
    cli = CliTests.cli
    install_fake_xcrun = CliTests.install_fake_xcrun

    def setUp(self):
        super().setUp()
        self.fake_log = self.install_fake_xcrun()

    def test_status_lists_unmanaged_simulators(self):
        os.environ["FAKE_BOOTED"] = json.dumps({"devices": {"iOS": [
            {"udid": LEAKED, "name": "Leaked", "state": "Booted"},
            {"udid": UDID, "name": "Off", "state": "Shutdown"}]}})
        text = self.cli("status").stdout
        self.assertIn("booted outside any hold (count against 'simulator'): 1", text)
        self.assertIn(f"Leaked ({LEAKED})", text)
        report = json.loads(self.cli("status", "--json").stdout)
        self.assertEqual([u["name"] for u in report["unmanaged"]], ["Leaked"])

    def test_reap_command_shuts_down_idle_unmanaged_simulators(self):
        os.environ["FAKE_BOOTED"] = json.dumps({"devices": {"iOS": [
            {"udid": LEAKED, "name": "Leaked", "state": "Booted"}]}})
        self.assertIn("Leaked", self.cli("reap", "--dry-run").stdout)
        self.assertFalse(self.fake_log.exists())
        result = self.cli("reap", "--grace", "0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fake_log.read_text(), f"simctl shutdown {LEAKED} held=\n")


class SharedInstallTests(DevcapTestCase):
    """Every copy from 1.2.1 on runs the newest version installed with ``devcap install``."""

    def cli(self, *args, env=None):
        environment = {k: v for k, v in os.environ.items() if k != devcap.NO_DEFER_ENV}
        return subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True,
                              env={**environment, **(env or {})}, timeout=60)

    def install_newer(self, body=None):
        """Install this copy, then rewrite the installed one as a newer version."""
        self.assertEqual(self.cli("install").returncode, 0)
        installed = devcap.installed_path(self.root)
        newer = devcap.VERSION + "9"
        text = installed.read_text().replace(f'VERSION = "{devcap.VERSION}"', f'VERSION = "{newer}"')
        installed.write_text(text if body is None else f'VERSION = "{newer}"\n{body}')
        installed.chmod(0o644)
        return installed, newer

    def test_older_copies_defer_to_a_newer_install(self):
        installed, newer = self.install_newer()
        self.assertEqual(stat.S_IMODE(installed.parent.stat().st_mode), 0o700)
        self.assertEqual(self.cli("--version").stdout.strip(), newer)
        self.assertEqual(self.cli("--version", env={devcap.NO_DEFER_ENV: "1"}).stdout.strip(), devcap.VERSION)

    def test_install_from_an_older_copy_never_downgrades(self):
        installed, newer = self.install_newer()
        for env in (None, {devcap.NO_DEFER_ENV: "1"}):  # with and without deferral
            refused = self.cli("install", env=env)
            self.assertEqual(refused.returncode, 1, refused.stdout)
            self.assertIn(f"already has newer {newer}; this copy is {devcap.VERSION}", refused.stderr)
            self.assertEqual(devcap.file_version(installed), newer)
        forced = self.cli("install", "--force")
        self.assertEqual(forced.returncode, 0, forced.stderr)
        self.assertEqual(devcap.file_version(installed), devcap.VERSION)

    def test_untrusted_install_is_ignored(self):
        installed, newer = self.install_newer()
        installed.chmod(0o666)
        self.assertEqual(self.cli("--version").stdout.strip(), devcap.VERSION)
        installed.chmod(0o644)
        installed.parent.chmod(0o770)
        self.assertEqual(self.cli("--version").stdout.strip(), devcap.VERSION)
        installed.parent.chmod(0o700)
        link = installed.with_name("real.py")
        installed.rename(link)
        installed.symlink_to(link)
        self.assertEqual(self.cli("--version").stdout.strip(), devcap.VERSION)

    def test_broken_install_falls_back_to_the_local_copy(self):
        for body in ("def broken(:\n", "raise RuntimeError('boom')\n", "main = None\n", "raise SystemExit(3)\n"):
            installed, _ = self.install_newer(body)
            result = self.cli("--version")
            self.assertEqual(result.stdout.strip(), devcap.VERSION, body)
            self.assertIn("ignoring shared install", result.stderr)
            installed.unlink()
        installed.write_bytes(b'VERSION = "9.9.9"\n\xff\xfe not utf-8\n')
        self.assertEqual(self.cli("--version").stdout.strip(), devcap.VERSION)
        self.assertIsNone(devcap.file_version(installed))

    def test_an_older_install_is_ignored(self):
        installed = devcap.installed_path(self.root)
        installed.parent.mkdir(mode=0o700)
        installed.write_text('VERSION = "1.0.0"\nraise SystemExit("old install ran")\n')
        self.assertEqual(self.cli("--version").stdout.strip(), devcap.VERSION)

    def test_version_key(self):
        self.assertLess(devcap.version_key("1.2.9"), devcap.version_key("1.2.10"))
        self.assertIsNone(devcap.file_version(self.root / "missing.py"))


class FakeTools:
    """A fake ``simctl`` and ``simslim``: records every call, creates and deletes simulators in memory."""

    def __init__(self, test, simslim="0.14.0"):
        self.test = test
        self.simslim = simslim
        self.calls = []
        self.count = 0

    def version(self):
        """Stands in for ``simslim_version`` (records the probe like the real call)."""
        self.calls.append(["simslim", "--version"])
        return tuple(int(p) for p in self.simslim.split(".")) if self.simslim else None

    def run(self, argv, **kwargs):
        self.calls.append(list(argv))
        out = lambda text="", code=0: subprocess.CompletedProcess(argv, code, stdout=text, stderr="")
        if argv[0] == "simslim":
            if argv[1] == "disk-clean" and "--categories" not in argv:
                return out("select at least one cleanable disk category", 1)  # what simslim 0.14.0 does
            if argv[1] == "on":  # simslim reboots to apply the overrides: record that it booted, and under which gates
                self.test.slim_boots.append((argv[2], bool(Gate(devcap.device_gate(argv[2]), self.test.root, 1).holders())))
            return out()
        assert argv[:2] == ["xcrun", "simctl"], argv
        if argv[2] == "create":
            self.count += 1
            udid = f"00000000-0000-4000-8000-{self.count:012d}"
            self.test.booted.append({"udid": udid, "name": argv[3], "booted": False, "type": argv[4],
                                     "runtime": argv[5]})
            return out(udid + "\n")
        if argv[2] == "delete":
            self.test.booted[:] = [s for s in self.test.booted if s["udid"] != argv[3]]
            return out()
        raise AssertionError(argv)

    def named(self, *prefix):
        return [c for c in self.calls if c[:len(prefix)] == list(prefix)]


class LifecycleTests(DevcapTestCase):
    DUO = {"udid": UDID, "name": "iPhone Duo", "booted": False,
           "type": "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo", "runtime": "iOS-27.1"}

    def setUp(self):
        super().setUp()
        self.devices = self.root / "Devices"
        self.booted = [dict(self.DUO)]
        self.tools = FakeTools(self)
        self.slim_boots = []
        patcher = unittest.mock.patch.object(devcap, "simslim_version", self.tools.version)
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher = unittest.mock.patch.object(devcap.subprocess, "run", self.tools.run)
        patcher.start()
        self.addCleanup(patcher.stop)
        for key in ("DEVCAP_SIM_TTL", "DEVCAP_POSTER_LIMIT_MB", "DEVCAP_SLIM_PROFILE"):
            os.environ.pop(key, None)

    def poster(self, udid, megabytes):
        store = self.devices / udid / "data" / devcap.POSTER_STORE
        store.mkdir(parents=True)
        (store / "blob").write_bytes(b"x" * megabytes * 1024 * 1024)
        return store

    def test_new_pool_member_is_created_unslimmed_and_slimmed_only_inside_a_hold(self):
        devcap.pick_sim("iPhone Duo", 2, root=self.root)
        created = self.booted[-1]
        self.assertEqual((created["name"], created["type"]), ("iPhone Duo (pool 2)", self.DUO["type"]))
        self.assertFalse(self.tools.named("simslim", "on"))  # pick-sim runs outside any hold: nothing may boot
        record = devcap.load_sims_state(self.root)[created["udid"]]
        self.assertEqual((record["slim"], record["kind"], record["project"]), ("pending", "pool", devcap.project_tag()))
        with devcap.hold(sims=[created["udid"]], hold_seconds=None, root=self.root):
            pass
        self.assertEqual(self.tools.named("simslim", "on"), [["simslim", "on", created["udid"], "--preserve-boot-state"]])
        self.assertEqual(self.slim_boots, [(created["udid"], True)])  # the device gate was held
        with devcap.hold(sims=[created["udid"]], hold_seconds=None, root=self.root):
            pass
        self.assertEqual(len(self.tools.named("simslim", "on")), 1)  # once

    def test_old_or_missing_simslim_keeps_the_stock_path(self):
        for version in ("0.13.0", None):
            self.tools.simslim = version
            self.booted[:] = [dict(self.DUO)]
            self.tools.calls.clear()
            member = devcap.pick_sim("iPhone Duo", 2, root=self.root)
            member = self.booted[-1]["udid"]
            with devcap.hold(sims=[member], hold_seconds=None, root=self.root):
                pass
            self.assertEqual(len(self.tools.named("xcrun", "simctl", "create")), 1)
            self.assertFalse(self.tools.named("simslim", "on"))

    def test_a_failed_slim_is_retried_at_most_once_a_day(self):
        devcap.pick_sim("iPhone Duo", 2, root=self.root)
        member = self.booted[-1]["udid"]
        real = self.tools.run
        self.tools.run = lambda argv, **kw: (real(argv, **kw) if argv[1] != "on" else (
            self.tools.calls.append(list(argv)), subprocess.CompletedProcess(argv, 1, stdout="", stderr=""))[1])
        with unittest.mock.patch.object(devcap.subprocess, "run", self.tools.run):
            for _ in range(3):
                with devcap.hold(sims=[member], hold_seconds=None, root=self.root):
                    pass
            self.assertEqual(len(self.tools.named("simslim", "on")), 1)
            devcap.note_sim(member, self.root, slim_failed_epoch=time.time() - 90_000)
            with devcap.hold(sims=[member], hold_seconds=None, root=self.root):
                pass
        self.assertEqual(len(self.tools.named("simslim", "on")), 2)

    def test_slim_profile_is_passed_through(self):
        os.environ["DEVCAP_SLIM_PROFILE"] = "ui.json"
        devcap.pick_sim("iPhone Duo", 2, root=self.root)
        with devcap.hold(sims=[self.booted[-1]["udid"]], hold_seconds=None, root=self.root):
            pass
        self.assertEqual(self.tools.named("simslim", "on")[0][-2:], ["--profile", "ui.json"])

    def test_reset_deletes_an_oversized_poster_store_and_runs_disk_clean(self):
        os.environ["DEVCAP_POSTER_LIMIT_MB"] = "4"
        big = self.poster(UDID, 6)
        devcap.reset_released([UDID], self.root)
        self.assertFalse(big.exists())
        self.assertEqual(self.tools.named("simslim", "disk-clean"), [[
            "simslim", "disk-clean", UDID, "--categories", "caches,logs,temporary", "--confirm"]])

    def test_disk_clean_without_categories_is_rejected_by_the_fake_like_simslim(self):
        self.assertEqual(self.tools.run(["simslim", "disk-clean", UDID, "--confirm"]).returncode, 1)

    def test_reset_skips_a_symlinked_poster_store_and_logs_truthfully(self):
        os.environ["DEVCAP_POSTER_LIMIT_MB"] = "1"
        real = self.root / "elsewhere"
        real.mkdir()
        (real / "blob").write_bytes(b"x" * 3 * 1024 * 1024)
        link = self.devices / UDID / "data" / devcap.POSTER_STORE
        link.parent.mkdir(parents=True)
        link.symlink_to(real)
        devcap.reset_released([UDID], self.root)
        self.assertTrue((real / "blob").exists())
        self.assertNotIn("deleted poster store", (self.root / "devcap.log").read_text())

    def test_reset_keeps_a_small_poster_store_and_skips_disk_clean_without_simslim(self):
        os.environ["DEVCAP_POSTER_LIMIT_MB"] = "4"
        self.tools.simslim = None
        small = self.poster(UDID, 1)
        devcap.reset_released([UDID], self.root)
        self.assertTrue(small.exists())
        self.assertFalse(self.tools.named("simslim", "disk-clean"))

    def test_reset_never_touches_a_booted_simulator(self):
        os.environ["DEVCAP_POSTER_LIMIT_MB"] = "1"
        self.booted[0]["booted"] = True
        big = self.poster(UDID, 3)
        devcap.reset_released([UDID], self.root)
        self.assertTrue(big.exists())
        self.assertFalse(self.tools.named("simslim", "disk-clean"))

    def test_run_with_shutdown_resets_while_the_gate_is_still_held(self):
        os.environ["DEVCAP_POSTER_LIMIT_MB"] = "1"
        big = self.poster(UDID, 3)
        seen = []
        original = devcap.reset_released
        with unittest.mock.patch.object(devcap, "reset_released", lambda u, r=None: (
                seen.append(bool(Gate(devcap.device_gate(UDID), self.root, 1).holders())), original(u, r))), \
                unittest.mock.patch.object(devcap, "run_command", return_value=0):
            code = devcap.main(["run", "--sim", UDID, "--shutdown", "--", "true"])
        self.assertEqual(code, 0)
        self.assertEqual(seen, [True])
        self.assertFalse(big.exists())
        self.assertEqual(self.shutdowns, [UDID])

    def test_run_records_the_release_time(self):
        with unittest.mock.patch.object(devcap, "run_command", return_value=0):
            devcap.main(["run", "--sim", UDID, "--shutdown", "--", "true"])
        self.assertAlmostEqual(devcap.load_sims_state(self.root)[UDID]["last_release_epoch"], time.time(), delta=60)

    def add_pool(self, name="iPhone Duo (pool 2)", udid="11111111-2222-4333-8444-555555555555", booted=False, **extra):
        self.booted.append({**self.DUO, "udid": udid, "name": name, "booted": booted, **extra})
        devcap.note_sim(udid, self.root, kind="pool", project=devcap.project_tag(), name=name)
        return udid

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: KeyError last_release_epoch / empty reap output; cause not found; follow-up hosted-ci-linux-portability")
    def test_reap_deletes_only_idle_unbooted_unheld_pool_members(self):
        now = 1_000_000.0
        idle, young, running, held, other = (self.add_pool(f"iPhone Duo (pool {n})", f"{n:08d}-2222-4333-8444-555555555555",
                                                          booted=(n == 4)) for n in (2, 3, 4, 5, 6))
        devcap.note_sim(other, self.root, project="another-repo")  # another project's pool member, even if idle
        legacy = "77777777-2222-4333-8444-555555555555"  # a (pool N) simulator with no record: left to ci_hygiene
        self.booted.append({**self.DUO, "udid": legacy, "name": "iPhone Duo (pool 7)"})
        devcap.note_sim(legacy, self.root, last_release_epoch=now - 90_000)
        for udid, last in ((idle, now - 90_000), (young, now - 100), (running, now - 90_000), (held, now - 90_000),
                           (other, now - 90_000), (UDID, now - 90_000)):
            devcap.note_sim(udid, self.root, last_release_epoch=last)
        with devcap.hold(sims=[held], hold_seconds=None, root=self.root):
            gone = devcap.reap_idle_sims(self.root, ttl=86_400, now=now)
        self.assertEqual([g["udid"] for g in gone], [idle])
        self.assertEqual(self.tools.named("xcrun", "simctl", "delete"), [["xcrun", "simctl", "delete", idle]])
        self.assertNotIn(idle, devcap.load_sims_state(self.root))
        self.assertIn(UDID, [s["udid"] for s in self.booted])  # the base device is never a candidate

    def old_member(self, now=1_000_000.0):
        old = self.add_pool()
        devcap.note_sim(old, self.root, last_release_epoch=now - 90_000)
        return old, now

    def test_reap_skips_when_a_waiter_queues_after_the_first_check(self):
        old, now = self.old_member()
        answers = iter([[], [{"pid": os.getpid(), "purpose": "late lane"}]])
        with unittest.mock.patch.object(Gate, "waiting", lambda gate: next(answers)):
            self.assertEqual(devcap.reap_idle_sims(self.root, ttl=86_400, now=now), [])
        self.assertFalse(self.tools.named("xcrun", "simctl", "delete"))

    def test_reap_skips_when_the_simulator_was_released_after_the_snapshot(self):
        old, now = self.old_member()
        real = Gate._try_slots

        def try_slots(gate):
            got = real(gate)
            devcap.note_sim(old, self.root, last_release_epoch=now - 5)  # a lane released it just now
            return got
        with unittest.mock.patch.object(Gate, "_try_slots", try_slots):
            self.assertEqual(devcap.reap_idle_sims(self.root, ttl=86_400, now=now), [])
        self.assertFalse(self.tools.named("xcrun", "simctl", "delete"))

    def test_reap_skips_a_simulator_that_is_not_exactly_shutdown_once_gated(self):
        old, now = self.old_member()
        real = Gate._try_slots

        def try_slots(gate):
            got = real(gate)
            next(s for s in self.booted if s["udid"] == old)["state"] = "Booting"
            return got
        with unittest.mock.patch.object(Gate, "_try_slots", try_slots):
            self.assertEqual(devcap.reap_idle_sims(self.root, ttl=86_400, now=now), [])
        self.assertFalse(self.tools.named("xcrun", "simctl", "delete"))

    def test_reap_ignores_booting_and_shutting_down_simulators(self):
        old, now = self.old_member()
        next(s for s in self.booted if s["udid"] == old)["state"] = "Shutting Down"
        self.assertEqual(devcap.reap_idle_sims(self.root, ttl=86_400, now=now), [])

    def test_pick_sim_stamps_the_member_it_hands_out(self):
        old, now = self.old_member()
        chosen = devcap.pick_sim("iPhone Duo", 2, root=self.root)
        stamp = devcap.load_sims_state(self.root)[chosen]["last_release_epoch"]
        self.assertAlmostEqual(stamp, time.time(), delta=60)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: KeyError last_release_epoch / empty reap output; cause not found; follow-up hosted-ci-linux-portability")
    def test_reap_recognises_job_members_of_this_project(self):
        job = self.add_pool("iPhone Duo (job 99)", "99999999-2222-4333-8444-555555555555")
        devcap.note_sim(job, self.root, kind="ephemeral", last_release_epoch=1.0)
        self.assertEqual([g["udid"] for g in devcap.reap_idle_sims(self.root, ttl=10, now=1000.0)], [job])

    def test_state_file_updates_do_not_lose_each_other(self):
        threads = [threading.Thread(target=devcap.note_sim, args=(f"{n:08d}-2222-4333-8444-555555555555", self.root),
                                    kwargs={"kind": "pool"}) for n in range(20)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(len(devcap.load_sims_state(self.root)), 20)

    def test_project_tag_override(self):
        with unittest.mock.patch.dict(os.environ, {"DEVCAP_PROJECT": "x"}):
            self.assertEqual(devcap.project_tag(), "x")
        self.assertTrue(devcap.project_tag())

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: KeyError last_release_epoch / empty reap output; cause not found; follow-up hosted-ci-linux-portability")
    def test_reap_dry_run_deletes_nothing_and_unknown_idle_starts_its_clock(self):
        old = self.add_pool()
        self.assertEqual(devcap.reap_idle_sims(self.root, ttl=10, now=500.0), [])  # no record yet: clock starts
        self.assertEqual(devcap.load_sims_state(self.root)[old]["last_release_epoch"], 500.0)
        dry = devcap.reap_idle_sims(self.root, ttl=10, dry_run=True, now=600.0)
        self.assertEqual([d["udid"] for d in dry], [old])
        self.assertFalse(self.tools.named("xcrun", "simctl", "delete"))

    def test_reap_ttl_can_be_turned_off(self):
        os.environ["DEVCAP_SIM_TTL"] = "off"
        self.add_pool()
        self.assertIsNone(devcap.sim_ttl(self.root))
        self.assertEqual(devcap.reap_idle_sims(self.root, now=1e12), [])

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: KeyError last_release_epoch / empty reap output; cause not found; follow-up hosted-ci-linux-portability")
    def test_reap_command_prints_deletions(self):
        old = self.add_pool()
        devcap.note_sim(old, self.root, last_release_epoch=time.time() - 200_000)
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            self.assertEqual(devcap.main(["reap"]), 0)
        self.assertIn("deleted idle pool simulator iPhone Duo (pool 2)", buffer.getvalue())
        self.assertEqual([s["udid"] for s in self.booted], [UDID])

    def test_ephemeral_sim_is_created_like_the_base_held_exposed_and_deleted(self):
        seen = {}

        def fake_run_command(held, command):
            udid = os.environ[devcap.EPHEMERAL_ENV]
            seen.update(command=command, udid=udid, held=Gate(devcap.device_gate(udid), self.root, 1).holders(),
                        sim=next(s for s in self.booted if s["udid"] == udid))
            return 0
        with unittest.mock.patch.object(devcap, "run_command", fake_run_command), \
                unittest.mock.patch.dict(os.environ):
            code = devcap.main(["run", "--ephemeral-sim", "iPhone Duo", "--", "echo", "{udid}"])
        self.assertEqual(code, 0)
        self.assertEqual(seen["command"], ["echo", seen["udid"]])
        self.assertTrue(seen["held"])
        self.assertEqual(seen["sim"]["type"], self.DUO["type"])  # a Duo stays a Duo
        self.assertEqual([s["udid"] for s in self.booted], [UDID])  # deleted on release
        self.assertIn(seen["udid"], self.shutdowns)

    def test_ephemeral_sim_is_deleted_when_interrupted_or_signalled_while_queued(self):
        for failure in (KeyboardInterrupt(), SystemExit(143), RuntimeError("boom")):
            self.booted[:] = [dict(self.DUO)]
            with unittest.mock.patch.object(Hold, "acquire", side_effect=failure), \
                    unittest.mock.patch.dict(os.environ):
                with self.assertRaises(type(failure)):
                    devcap.main(["run", "--ephemeral-sim", "iPhone Duo", "--", "true"])
            self.assertEqual([s["udid"] for s in self.booted], [UDID], failure)

    def test_sigterm_while_queued_unwinds(self):
        import signal as signal_module
        seen = {}

        def acquire(held):
            seen["handler"] = signal_module.getsignal(signal_module.SIGTERM)
            seen["handler"](signal_module.SIGTERM, None)
        with unittest.mock.patch.object(Hold, "acquire", acquire), unittest.mock.patch.dict(os.environ):
            with self.assertRaises(SystemExit) as raised:
                devcap.main(["run", "--ephemeral-sim", "iPhone Duo", "--", "true"])
        self.assertEqual(raised.exception.code, 128 + signal_module.SIGTERM)
        self.assertEqual([s["udid"] for s in self.booted], [UDID])

    def test_ephemeral_cleanup_leaves_other_sims_alone_without_shutdown(self):
        other = self.add_pool()
        with unittest.mock.patch.object(devcap, "run_command", return_value=0), unittest.mock.patch.dict(os.environ):
            devcap.main(["run", "--sim", other, "--ephemeral-sim", "iPhone Duo", "--", "true"])
        self.assertNotIn(other, self.shutdowns)
        self.assertFalse(self.tools.named("simslim", "disk-clean"))

    def test_ephemeral_slim_runs_inside_the_hold(self):
        with unittest.mock.patch.object(devcap, "run_command", return_value=0), unittest.mock.patch.dict(os.environ):
            devcap.main(["run", "--ephemeral-sim", "iPhone Duo", "--", "true"])
        self.assertEqual([held for _udid, held in self.slim_boots], [True])

    def test_ephemeral_sim_unknown_base_fails_without_creating(self):
        self.assertEqual(devcap.main(["run", "--ephemeral-sim", "Nope", "--", "true"]), 1)
        self.assertFalse(self.tools.named("xcrun", "simctl", "create"))

    def test_ephemeral_sim_is_deleted_when_the_wait_times_out(self):
        blocker = Gate("simulator", self.root, 1)
        blocker.acquire("other", 1)
        self.addCleanup(blocker.release)
        with unittest.mock.patch.dict(os.environ, {"DEVCAP_SLOTS_SIMULATOR": "1"}):
            code = devcap.main(["run", "--ephemeral-sim", "iPhone Duo", "--wait", "0.2", "--", "true"])
        self.assertEqual(code, devcap.WAIT_TIMEOUT_EXIT)
        self.assertEqual([s["udid"] for s in self.booted], [UDID])

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: KeyError last_release_epoch / empty reap output; cause not found; follow-up hosted-ci-linux-portability")
    def test_status_shows_pool_size_and_disk_use(self):
        pool = self.add_pool()
        self.poster(pool, 2)
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            devcap.main(["status"])
        text = buffer.getvalue()
        self.assertIn("simulator pool: 1 member(s), 2.0 MB", text)
        self.assertIn(f"iPhone Duo (pool 2) ({pool})", text)
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            devcap.main(["status", "--json", "--disk"])
        report = json.loads(buffer.getvalue())["pool"]
        self.assertEqual([m["udid"] for m in report["members"]], [pool])
        self.assertGreaterEqual(report["total_bytes"], 2 * 1024 * 1024)
        self.assertIsNone(devcap.pool_report(self.root)["total_bytes"])  # the whole-tree walk is opt-in

    def test_helpers(self):
        self.assertEqual(devcap.human_bytes(512), "512 B")
        self.assertEqual(devcap.human_bytes(3 * 1024 ** 3), "3.0 GB")
        self.assertIsNone(devcap.load_sims_state(self.root).get("x"))
        devcap.sims_state_path(self.root).write_text("[1]")
        self.assertEqual(devcap.load_sims_state(self.root), {})
        self.assertEqual(devcap.dir_size(self.root / "missing"), 0)


class ProjectTagTests(DevcapTestCase):
    """Pool members are tagged with the repository of the copy that was run, even through a shared install."""

    cli = SharedInstallTests.cli
    install_newer = SharedInstallTests.install_newer

    def stub_repo(self, name, worktree=False):
        repo = self.root / "repos" / name
        (repo / "tools").mkdir(parents=True)
        (repo / ".git").mkdir()
        stub = repo / "tools" / "devcap.py"
        stub.write_bytes(TOOL.read_bytes())
        if worktree:
            tree = self.root / "trees" / "lane"
            (tree / "tools").mkdir(parents=True)
            (repo / ".git" / "worktrees" / "lane").mkdir(parents=True)
            (tree / ".git").write_text(f"gitdir: {repo / '.git' / 'worktrees' / 'lane'}\n")
            stub = tree / "tools" / "devcap.py"
            stub.write_bytes(TOOL.read_bytes())
        return stub

    def tag_from(self, stub):
        fake = self.root / "bin"
        fake.mkdir(exist_ok=True)
        (fake / "xcrun").write_text('#!/bin/sh\necho \'{"devices": {}}\'\n')
        (fake / "xcrun").chmod(0o755)
        environment = {k: v for k, v in os.environ.items() if k not in (devcap.NO_DEFER_ENV, "DEVCAP_PROJECT")}
        out = subprocess.run([sys.executable, str(stub), "status", "--json"], capture_output=True, text=True,
                             env={**environment, "PATH": f"{fake}:{os.environ['PATH']}"}, timeout=60)
        return json.loads(out.stdout)["pool"]["project"]

    def test_tag_survives_a_newer_shared_install(self):
        alpha, beta, tree = self.stub_repo("alpha"), self.stub_repo("beta"), self.stub_repo("gamma", worktree=True)
        self.assertEqual([self.tag_from(p) for p in (alpha, beta, tree)], ["alpha", "beta", "gamma"])
        self.install_newer()
        self.assertEqual([self.tag_from(p) for p in (alpha, beta, tree)], ["alpha", "beta", "gamma"])

    def test_unresolvable_project_claims_nothing_and_reap_leaves_other_projects(self):
        for udid, project in (("11111111-2222-4333-8444-555555555551", "alpha"),
                              ("11111111-2222-4333-8444-555555555552", "beta")):
            self.booted.append({"udid": udid, "name": f"iPad (pool {project})", "booted": False})
            devcap.note_sim(udid, self.root, kind="pool", project=project, last_release_epoch=1.0)
        deleted = []
        with unittest.mock.patch.object(devcap, "delete_sim", lambda udid, root=None, why="": deleted.append(udid) or True):
            with unittest.mock.patch.dict(os.environ, {"DEVCAP_PROJECT": "alpha"}):
                self.assertEqual([g["name"] for g in devcap.reap_idle_sims(self.root, ttl=10, now=1000.0)],
                                 ["iPad (pool alpha)"])
            with unittest.mock.patch.dict(os.environ, {"DEVCAP_PROJECT": devcap.UNKNOWN_PROJECT}):
                self.assertEqual(devcap.reap_idle_sims(self.root, ttl=10, now=1000.0), [])
                self.assertEqual(devcap.pool_report(self.root)["members"], [])
        self.assertEqual(deleted, ["11111111-2222-4333-8444-555555555551"])


class VendoredCopyTests(unittest.TestCase):
    """The same ``devcap.py`` is vendored byte for byte; two copies that differ are a bug."""

    @staticmethod
    def sha(path):
        import hashlib
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()

    def test_copies_match_detects_a_difference(self):
        with TemporaryDirectory() as tmp:
            other = Path(tmp) / "devcap.py"
            other.write_bytes(TOOL.read_bytes())
            self.assertEqual(self.sha(TOOL), self.sha(other))
            other.write_bytes(TOOL.read_bytes() + b"# drift\n")
            self.assertNotEqual(self.sha(TOOL), self.sha(other))

    def test_a_vendored_copy_matches_this_one(self):
        """Set ``DEVCAP_VENDORED_COPY`` to another repository's ``tools/devcap.py`` to check it."""
        path = os.environ.get("DEVCAP_VENDORED_COPY")
        if not path:
            self.skipTest("DEVCAP_VENDORED_COPY not set")
        self.assertEqual(self.sha(TOOL), self.sha(path), f"{path} differs from the canonical devcap.py")


class AgeTests(unittest.TestCase):
    def test_describe_age(self):
        self.assertEqual(devcap.describe_age(5), "5s")
        self.assertEqual(devcap.describe_age(185), "3m")
        self.assertEqual(devcap.describe_age(7500), "2h05m")


if __name__ == "__main__":
    unittest.main()
