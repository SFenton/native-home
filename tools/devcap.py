#!/usr/bin/env python3
"""Machine-wide device capacity: wait for a simulator, device or build slot.

Every repository and lane on one Mac shares the same simulator, device and
compile capacity. ``devcap`` hands out that capacity FIFO, so parallel lanes
wait their turn instead of booting more simulators (or compiling more apps)
than the machine can carry. It is the one capacity mechanism for
SFenton/FestivalNativeApps and SFenton/Fenton-HASS-Native; the canonical copy
lives in FestivalNativeApps at ``tools/devcap.py`` and other repositories
vendor it byte for byte (see ``VERSION``).

Gates
-----
A *gate* is a named resource with a number of slots:

* **pools** share capacity: ``simulator`` (booted simulators, default from
  RAM), ``build`` (heavy ``xcodebuild``/``swift build`` compiles, default from
  cores), or any other name (default 1 slot);
* **devices** are exclusive: ``device-<UDID>`` has one slot, so two lanes never
  drive the same simulator or physical device.

``--sim UDID`` takes the device gate *and* a ``simulator`` slot; ``--device
UDID`` (a physical device) takes only the device gate.

How waiting works
-----------------
Each gate lives in ``~/.devcap/<gate>/`` (``DEVCAP_DIR`` overrides the root):

1. ``slot-<n>.lock`` files carry an OS lock (``fcntl.flock``, ``msvcrt`` on
   Windows). The OS drops it when the holder exits or crashes, so a dead
   process never keeps a slot.
2. ``queue/<ns>-<pid>.ticket`` files order the waiters. Only the oldest ticket
   whose process is alive may try the slots (first come, first served);
   tickets of dead processes are deleted by whoever looks next.
3. ``slot-<n>.json`` names the holder (pid, purpose, cwd, start time) for the
   waiting message and ``status``. It is informational; the OS lock is the
   truth.

Simulators booted outside any hold
----------------------------------
A booted simulator whose device gate nobody holds is *unmanaged*: a thread
booted it without devcap, or left it booted after its hold. Unmanaged
simulators count against the ``simulator`` slots, so the limit holds no
matter who boots a simulator. A lane may leave its simulator booted between
runs on purpose (warm, so the next run skips the boot); when every slot is in
use, the waiter at the head shuts down the simulator idle longest once it has
been idle for 60 seconds (``DEVCAP_EVICT_AFTER`` / ``evict_after_seconds``).
Once one has stayed unmanaged for 5 minutes
(``DEVCAP_REAP_GRACE`` / ``config.json`` ``reap_grace_seconds``; ``off``
disables), the next waiter or finished simulator hold shuts it down and closes
Device Hub windows of devices nobody is using. Simulators running an app under
Xcode's debugger are never shut down. ``devcap reap`` does the same on demand.

Gates are always taken in one order (devices by UDID, then pools by name) so
two holders never deadlock. A child started by ``devcap run`` inherits
``DEVCAP_HELD``, and any nested ``devcap`` call skips gates its parent already
holds. Every acquire, wait and release is appended to ``~/.devcap/devcap.log``.

Capacity
--------
Slot counts come from, in order: ``DEVCAP_SLOTS_<POOL>`` (e.g.
``DEVCAP_SLOTS_SIMULATOR=2``), ``~/.devcap/config.json`` (``{"simulator": 2}``),
then the defaults in ``default_slots``. Lowering a count takes effect for new
holders; current holders finish normally.

Usage
-----
::

    # Run a command while holding a simulator (device + simulator slot), and
    # shut the simulator down before the slot is released.
    python3 tools/devcap.py run --sim "$UDID" --shutdown --purpose "uitest iphone" -- \\
        xcodebuild test-without-building ...

    # Compile under a build slot.
    python3 tools/devcap.py run --pool build -- xcodebuild build-for-testing ...

    # Who holds what, and who is waiting.
    python3 tools/devcap.py status

From Python::

    from tools import devcap
    with devcap.hold(sims=[udid], purpose="shot iphone", hold_seconds=None):
        ...
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import threading
import time
import types
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Iterator, Sequence

# region Configuration

#: Bump when the on-disk layout or the CLI changes; vendored copies must match.
VERSION = "1.5.0"

#: Exit code when a wait gives up (``EX_TEMPFAIL``).
WAIT_TIMEOUT_EXIT = 75

#: Exit code when a hold overruns its limit (matches coreutils ``timeout``).
HOLD_TIMEOUT_EXIT = 124

#: Default seconds a waiter queues before giving up.
DEFAULT_WAIT_SECONDS = 3600.0
#: Environment default for ``run --max-wait`` when the flag is absent. The triage runner sets it to 1200 for headless agent
#: sessions so a coder yields a slot queue after 20 minutes instead of 60.
WAIT_ENV = "FENTON_DEVCAP_MAX_WAIT"


def default_wait() -> float:
    """``FENTON_DEVCAP_MAX_WAIT`` seconds when it is a positive number, else :data:`DEFAULT_WAIT_SECONDS`."""
    try:
        value = float(os.environ.get(WAIT_ENV, ""))
    except ValueError:
        return DEFAULT_WAIT_SECONDS
    return value if math.isfinite(value) and value > 0 else DEFAULT_WAIT_SECONDS

#: Default seconds ``run`` may hold its gates.
DEFAULT_HOLD_SECONDS = 1800.0

#: Longest hold ``run`` accepts.
MAX_HOLD_SECONDS = 7200.0

#: Environment variable listing gates held by an ancestor process.
HELD_ENV = "DEVCAP_HELD"

#: Set for the command of ``run --ephemeral-sim`` to the job's simulator UDID.
EPHEMERAL_ENV = "DEVCAP_EPHEMERAL_SIM"

#: Log size that triggers rotation to ``devcap.log.1``.
LOG_ROTATE_BYTES = 1_000_000

#: Seconds between repeated "still waiting" messages.
REANNOUNCE_SECONDS = 60.0


def lock_root() -> Path:
    """Return the machine-wide state directory (``DEVCAP_DIR`` or ``~/.devcap``)."""
    return Path(os.environ.get("DEVCAP_DIR") or Path.home() / ".devcap")


def _memory_gb() -> float:
    """Physical memory in GB, or 16 when it cannot be read."""
    try:
        return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 2**30
    except (AttributeError, ValueError, OSError):
        pass
    try:
        out = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True,
                             text=True, check=True, timeout=5).stdout
        return int(out.strip()) / 2**30
    except (OSError, ValueError, subprocess.SubprocessError):
        return 16.0


def default_slots(pool: str, memory_gb: float | None = None, cpus: int | None = None) -> int:
    """Default slot count for a pool on this machine.

    Args:
        pool: Pool name.
        memory_gb: Physical memory override (tests).
        cpus: Core count override (tests).

    Returns:
        ``simulator``: one per 16 GB of RAM, 1–6 (4 on a 64 GB Mac; owner
        request for more parallel lanes, 2026-10-15). ``build``: one per 4 cores,
        1–4. Anything else: 1.
    """
    if pool == "simulator":
        memory_gb = _memory_gb() if memory_gb is None else memory_gb
        return max(1, min(6, int(memory_gb // 16)))
    if pool == "build":
        cpus = (os.cpu_count() or 4) if cpus is None else cpus
        return max(1, min(4, cpus // 4))
    return 1


def env_key(pool: str) -> str:
    """Environment variable overriding a pool's slot count."""
    return "DEVCAP_SLOTS_" + re.sub(r"[^A-Za-z0-9]", "_", pool).upper()


def configured_slots(pool: str, root: Path | None = None) -> int:
    """Slot count for a pool: environment, then ``config.json``, then default.

    Args:
        pool: Pool name. Device gates always have one slot.
        root: State directory (defaults to ``lock_root()``).

    Returns:
        At least 1.
    """
    if pool.startswith("device-"):
        return 1
    raw = os.environ.get(env_key(pool))
    if raw is None:
        try:
            config = json.loads(((root or lock_root()) / "config.json").read_text(encoding="utf-8"))
            raw = config.get(pool)
        except (OSError, ValueError, AttributeError):
            raw = None
    try:
        return max(1, int(raw)) if raw is not None else default_slots(pool)
    except (TypeError, ValueError):
        return default_slots(pool)

# endregion

# region Process helpers


def pid_alive(pid: int) -> bool:
    """Report whether a process id refers to a running process.

    Args:
        pid: Process id to test.

    Returns:
        True if the process exists and has not exited.
    """
    if pid <= 0:
        return False
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.restype = wintypes.HANDLE
        handle = kernel32.OpenProcess(0x1000, False, pid)
        if not handle:
            return ctypes.get_last_error() == 5  # access denied: it exists
        try:
            code = wintypes.DWORD()
            return bool(kernel32.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def describe_age(seconds: float) -> str:
    """Format a duration as ``45s``, ``3m`` or ``2h05m``."""
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    return f"{seconds // 3600}h{seconds % 3600 // 60:02d}m"


def log_event(message: str, root: Path | None = None) -> None:
    """Append one line to ``devcap.log``, rotating it past ``LOG_ROTATE_BYTES``."""
    path = (root or lock_root()) / "devcap.log"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.stat().st_size > LOG_ROTATE_BYTES:
            path.replace(path.with_name("devcap.log.1"))
        with open(path, "a", encoding="utf-8") as log:
            log.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} pid {os.getpid()} {message}\n")
    except OSError:
        pass

# endregion

# region Ticket queue


def parse_ticket(name: str) -> tuple[int, int] | None:
    """Split a ticket file name into its ordering key and owner pid.

    Args:
        name: File name such as ``"00000001234567890000-4321.ticket"``.

    Returns:
        ``(order, pid)``, or None if the name is not a ticket.
    """
    if not name.endswith(".ticket"):
        return None
    order, sep, pid = name[: -len(".ticket")].partition("-")
    if not sep or not order.isdigit() or not pid.isdigit():
        return None
    return int(order), int(pid)


def queue_order(names: Iterable[str], alive: Callable[[int], bool]) -> tuple[list[str], list[str]]:
    """Order live tickets and list tickets whose owners have exited.

    Args:
        names: File names found in a queue directory.
        alive: Predicate telling whether a pid is still running.

    Returns:
        ``(live, stale)``: live ticket names oldest first, and dead ones.
    """
    parsed = sorted((key, name) for name in names if (key := parse_ticket(name)))
    live, stale = [], []
    for (_, pid), name in parsed:
        (live if alive(pid) else stale).append(name)
    return live, stale

# endregion

# region Gate


@dataclass
class Gate:
    """One named resource with ``slots`` OS-locked slot files and a FIFO queue.

    Attributes:
        name: Gate name (``simulator``, ``build`` or ``device-<UDID>``).
        root: State directory.
        slots: Slot count; read from configuration when None.
    """

    name: str
    root: Path = field(default_factory=lock_root)
    slots: int | None = None
    _handle: object = field(default=None, init=False, repr=False)
    _slot: int | None = field(default=None, init=False, repr=False)
    _unmanaged: list = field(default_factory=list, init=False, repr=False)
    _next_scan: float = field(default=0.0, init=False, repr=False)

    def __post_init__(self) -> None:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", self.name):
            raise ValueError(f"invalid gate name {self.name!r}")
        if self.slots is None:
            self.slots = configured_slots(self.name, self.root)

    # MARK: paths

    @property
    def dir(self) -> Path:
        """Directory holding this gate's slots, holders and queue."""
        return self.root / self.name

    @property
    def queue_dir(self) -> Path:
        """Directory of waiter tickets."""
        return self.dir / "queue"

    def slot_lock(self, index: int) -> Path:
        """Path of slot ``index``'s OS-locked file."""
        return self.dir / f"slot-{index}.lock"

    def slot_holder(self, index: int) -> Path:
        """Path of slot ``index``'s informational holder record."""
        return self.dir / f"slot-{index}.json"

    # MARK: OS lock primitives

    @staticmethod
    def _lock(path: Path):
        """Take a non-blocking exclusive OS lock on ``path``.

        Returns:
            The open handle holding the lock, or None if someone else holds it.
        """
        handle = open(path, "a+b")
        try:
            if os.name == "nt":
                import msvcrt

                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            handle.close()
            return None
        return handle

    @staticmethod
    def _unlock(handle) -> None:
        """Release and close a handle returned by ``_lock``."""
        try:
            if os.name == "nt":
                import msvcrt

                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(handle, fcntl.LOCK_UN)
        except OSError:
            pass
        handle.close()

    def _try_slots(self) -> bool:
        """Try every slot once; keep the first free one."""
        self.dir.mkdir(parents=True, exist_ok=True)
        for index in range(self.slots):
            handle = self._lock(self.slot_lock(index))
            if handle is not None:
                self._handle, self._slot = handle, index
                return True
        return False

    # MARK: inspection

    def holders(self) -> list[dict]:
        """List current holders by probing every slot file in the gate.

        Returns:
            One record per held slot (``slot``, ``pid``, ``purpose``, ``cwd``,
            ``acquired``…); ``pid`` is None when the record is missing.
        """
        held = []
        if not self.dir.exists():
            return held
        indices = sorted(int(m.group(1)) for p in self.dir.iterdir()
                         if (m := re.fullmatch(r"slot-(\d+)\.lock", p.name)))
        for index in indices:
            if index == self._slot:
                continue
            probe = self._lock(self.slot_lock(index))
            if probe is not None:
                self._unlock(probe)
                continue
            try:
                record = json.loads(self.slot_holder(index).read_text(encoding="utf-8"))
            except (OSError, ValueError):
                record = {"pid": None}
            held.append({**record, "slot": index})
        return held

    def waiting(self) -> list[dict]:
        """List live waiters oldest first, each with ``pid`` and ``purpose``."""
        if not self.queue_dir.exists():
            return []
        live, _ = queue_order((p.name for p in self.queue_dir.iterdir()), pid_alive)
        result = []
        for name in live:
            try:
                purpose = (self.queue_dir / name).read_text(encoding="utf-8")
            except OSError:
                purpose = ""
            result.append({"pid": parse_ticket(name)[1], "purpose": purpose})
        return result

    def summary(self) -> str:
        """One line naming who holds this gate, for waiting messages."""
        now = time.time()
        held = self.holders()
        parts = [f"pid {h.get('pid', '?')} '{h.get('purpose', '?')}' in {h.get('cwd', '?')} "
                 f"for {describe_age(now - h.get('acquired_epoch', now))}" for h in held]
        parts += [f"'{u['name']}' booted outside any hold for {describe_age(u['unheld_for'])}"
                  + (" (Xcode debugger)" if u["debugged"] else "") for u in self._unmanaged]
        used = f"{len(held) + len(self._unmanaged)}/{self.slots} in use" if self._unmanaged else \
            f"{len(held)}/{self.slots} held"
        return used + (": " + "; ".join(parts) if parts else "")

    def _has_room(self, own_sims: Sequence[str]) -> bool:
        """Whether held slots plus unmanaged booted simulators leave a slot free.

        Only the ``simulator`` pool counts unmanaged simulators; the scan (which
        also reaps idle ones) runs at most every ``SCAN_INTERVAL_SECONDS``.
        Simulators a lane left warm between runs count too, but when every
        slot is in use the waiter at the head evicts the one idle longest, once
        it has been idle for ``evict_after`` (never one under the debugger).
        """
        if self.name != "simulator":
            return True
        if time.monotonic() >= self._next_scan:
            self._unmanaged = scan_unmanaged(self.root, exclude=own_sims) or []
            self._next_scan = time.monotonic() + SCAN_INTERVAL_SECONDS
        if len(self.holders()) + len(self._unmanaged) < self.slots:
            return True
        limit = evict_after(self.root)
        idle = [u for u in self._unmanaged
                if u["debugged"] is False and limit is not None and u["unheld_for"] >= limit]
        if idle:
            coldest = max(idle, key=lambda u: u["unheld_for"])
            if shut_down_unheld(self.root, coldest, "evict"):
                # Count what is really booted now; a failed shutdown must not free a slot.
                rescanned = scan_unmanaged(self.root, exclude=own_sims)
                if rescanned is None:
                    return False
                self._unmanaged = rescanned
                self._next_scan = time.monotonic() + SCAN_INTERVAL_SECONDS
                return len(self.holders()) + len(self._unmanaged) < self.slots
        return False

    # MARK: acquire / release

    def acquire(self, purpose: str, wait_seconds: float, poll_seconds: float = 0.5,
                announce: Callable[[str], None] | None = None, own_sims: Sequence[str] = ()) -> None:
        """Queue FIFO for a free slot.

        For the ``simulator`` pool, simulators booted outside any hold count
        against the slots too (``unmanaged_sims``), so a lane waits instead of
        booting one more on a Mac that is already full; idle ones are reaped.

        Args:
            purpose: Short description recorded for status and logs.
            wait_seconds: How long to queue before raising ``WaitTimeout``.
            poll_seconds: Polling interval while at the head of the queue;
                waiters further back back off up to 4 s.
            announce: Receives human-readable waiting messages (stderr default).
            own_sims: UDIDs this waiter is about to use; never counted or reaped.

        Raises:
            WaitTimeout: No slot freed up within ``wait_seconds``.
        """
        announce = announce or (lambda line: print(line, file=sys.stderr, flush=True))
        self.queue_dir.mkdir(parents=True, exist_ok=True)
        ticket = self.queue_dir / f"{time.time_ns():020d}-{os.getpid()}.ticket"
        ticket.write_text(purpose, encoding="utf-8")
        started = time.monotonic()
        next_announce = started
        try:
            while True:
                live, stale = queue_order((p.name for p in self.queue_dir.iterdir()), pid_alive)
                for name in stale:
                    (self.queue_dir / name).unlink(missing_ok=True)
                position = live.index(ticket.name) if ticket.name in live else 0
                if position == 0 and self._has_room(own_sims) and self._try_slots():
                    break
                waited = time.monotonic() - started
                if waited >= wait_seconds:
                    log_event(f"gave up {self.name} after {describe_age(waited)} purpose={purpose!r}", self.root)
                    raise WaitTimeout(f"gave up waiting {describe_age(waited)} for '{self.name}' "
                                      f"({self.summary()})")
                if time.monotonic() >= next_announce:
                    ahead = f", {position} ahead in queue" if position else ""
                    verb = "waiting" if next_announce == started else f"still waiting ({describe_age(waited)})"
                    announce(f"devcap: {verb} for '{self.name}' ({self.summary()}{ahead}) ...")
                    if next_announce == started:
                        log_event(f"wait {self.name} {self.summary()} purpose={purpose!r}", self.root)
                    next_announce = time.monotonic() + REANNOUNCE_SECONDS
                time.sleep(poll_seconds if position == 0 else min(4.0, poll_seconds * (1 + position)))
        finally:
            ticket.unlink(missing_ok=True)
        waited = time.monotonic() - started
        self.slot_holder(self._slot).write_text(json.dumps({
            "pid": os.getpid(),
            "purpose": purpose,
            "cwd": os.getcwd(),
            "acquired": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "acquired_epoch": time.time(),
        }), encoding="utf-8")
        log_event(f"acquire {self.name} slot {self._slot}/{self.slots} after {describe_age(waited)} "
                  f"purpose={purpose!r} cwd={os.getcwd()}", self.root)
        if waited >= 1:
            announce(f"devcap: got '{self.name}' slot {self._slot} after {describe_age(waited)}")

    def release(self) -> None:
        """Release the held slot, if any."""
        handle, slot = self._handle, self._slot
        if handle is None:
            return
        self._handle, self._slot = None, None
        try:
            self.slot_holder(slot).unlink(missing_ok=True)
        except OSError:
            pass
        log_event(f"release {self.name} slot {slot}", self.root)
        self._unlock(handle)

    @property
    def held(self) -> bool:
        """Whether this process currently holds a slot of this gate."""
        return self._handle is not None


class WaitTimeout(RuntimeError):
    """Raised when a waiter's queue time exceeds its wait limit."""

# endregion

# region Holding several gates


def device_gate(udid: str) -> str:
    """Gate name for a simulator or physical device UDID."""
    return "device-" + re.sub(r"[^A-Za-z0-9._-]", "_", udid.strip()).upper()


def gate_names(pools: Sequence[str] = (), sims: Sequence[str] = (), devices: Sequence[str] = ()) -> list[str]:
    """Canonical acquisition order: device gates by UDID, then pools by name.

    Args:
        pools: Pool names, e.g. ``["build"]``.
        sims: Simulator UDIDs; each adds its device gate and the ``simulator`` pool.
        devices: Physical device UDIDs; each adds only its device gate.

    Returns:
        Deduplicated gate names in the one order every caller uses.
    """
    device_names = {device_gate(u) for u in [*sims, *devices]}
    pool_names = set(pools) | ({"simulator"} if sims else set())
    return sorted(device_names) + sorted(pool_names)


def inherited() -> set[str]:
    """Gates an ancestor ``devcap`` process holds for this process."""
    return {name for name in os.environ.get(HELD_ENV, "").split(",") if name}


@dataclass
class Hold:
    """Holds several gates for one block, with an optional hold watchdog.

    Attributes:
        names: Gate names, already in canonical order (``gate_names``).
        purpose: Short description for status and logs.
        wait_seconds: Queue limit per gate.
        hold_seconds: Hard hold limit; None disables the watchdog.
        root: State directory.
        on_overrun: Called first when the hold overruns, e.g. to stop the command.
        cleanup: Runs once before the gates are released (``finish`` or an
            overrun), e.g. to shut a simulator down while its slot is held.
        cleanup_on_finish: False runs ``cleanup`` only after an overrun.
    """

    names: list[str]
    purpose: str = ""
    wait_seconds: float = DEFAULT_WAIT_SECONDS
    hold_seconds: float | None = DEFAULT_HOLD_SECONDS
    root: Path = field(default_factory=lock_root)
    on_overrun: Callable[[], None] | None = None
    cleanup: Callable[[], None] | None = None
    cleanup_on_finish: bool = True
    gates: list[Gate] = field(default_factory=list, init=False)
    overran: bool = field(default=False, init=False)
    _release_lock: threading.Lock = field(default_factory=threading.Lock, init=False, repr=False)
    _finish_lock: threading.Lock = field(default_factory=threading.Lock, init=False, repr=False)
    _done: threading.Event = field(default_factory=threading.Event, init=False, repr=False)

    def acquire(self) -> None:
        """Take every gate not already held by an ancestor, in order.

        Raises:
            WaitTimeout: A gate stayed full past ``wait_seconds``; nothing stays held.
        """
        skip = inherited()
        try:
            for name in self.names:
                if name in skip:
                    continue
                gate = Gate(name, self.root)
                gate.acquire(self.purpose, self.wait_seconds, own_sims=self.sim_udids)
                self.gates.append(gate)
        except BaseException:
            self.release()
            raise
        try:
            for udid in self.sim_udids:  # gates are held: the one place a new simulator may be booted to slim it
                if device_gate(udid) in {g.name for g in self.gates}:
                    slim_new_sim(udid, self.root)
        except BaseException:
            self.release()
            raise
        if self.hold_seconds is not None:
            self._done.clear()
            threading.Thread(target=self._watchdog, daemon=True).start()

    @property
    def sim_udids(self) -> list[str]:
        """Simulator UDIDs this hold covers (from its device gates)."""
        return [name[len("device-"):] for name in self.names
                if name.startswith("device-") and SIM_UDID.fullmatch(name[len("device-"):])]

    def release(self) -> None:
        """Release every held gate, newest first (safe from the watchdog and the caller at once)."""
        self._done.set()
        with self._release_lock:
            if self.gates:
                held = {g.name for g in self.gates}
                note_released([u for u in self.sim_udids if device_gate(u) in held], self.root)
            for gate in reversed(self.gates):
                gate.release()
            self.gates.clear()

    def finish(self) -> None:
        """Run ``cleanup`` and release, unless the watchdog is already doing so.

        Serialized with the watchdog: after an overrun only the watchdog runs
        ``cleanup`` and releases, and this call blocks until it has (the
        watchdog then exits the process), so a slot is never freed before its
        cleanup finishes.
        """
        with self._finish_lock:
            if not self.overran:
                had_simulator = any(g.name == "simulator" for g in self.gates)
                try:
                    if self.cleanup and self.cleanup_on_finish and self.gates:
                        self.cleanup()
                finally:
                    self.release()
                if had_simulator:  # a freed slot is a good moment to sweep leaked simulators
                    try:
                        scan_unmanaged(self.root)
                    except Exception:  # never fail a finished hold over a sweep
                        pass

    def environment(self) -> dict[str, str]:
        """Environment for children: ``DEVCAP_HELD`` lists every held gate."""
        held = inherited() | {g.name for g in self.gates}
        return {**os.environ, HELD_ENV: ",".join(sorted(held))}

    def _watchdog(self) -> None:
        if self._done.wait(self.hold_seconds):
            return
        with self._finish_lock:
            if self._done.is_set():
                return  # finished normally while this thread woke up
            print(f"\ndevcap: HOLD TIMEOUT: held {','.join(self.names)} longer than "
                  f"{describe_age(self.hold_seconds)}; releasing.", file=sys.stderr, flush=True)
            log_event(f"hold timeout {','.join(self.names)} purpose={self.purpose!r}", self.root)
            self.overran = True
            try:
                if self.on_overrun:
                    self.on_overrun()
                if self.cleanup and self.gates:  # never clean up a parent's inherited gates
                    self.cleanup()
            finally:
                self.release()
            os._exit(HOLD_TIMEOUT_EXIT)

    def __enter__(self) -> "Hold":
        self.acquire()
        return self

    def __exit__(self, *exc) -> None:
        self.finish()


@contextmanager
def hold(pools: Sequence[str] = (), sims: Sequence[str] = (), devices: Sequence[str] = (),
         purpose: str = "", wait_seconds: float = DEFAULT_WAIT_SECONDS,
         hold_seconds: float | None = DEFAULT_HOLD_SECONDS, root: Path | None = None) -> Iterator[Hold]:
    """Hold capacity for a block; see ``gate_names`` for the arguments.

    While the block runs, ``os.environ[DEVCAP_HELD]`` names the held gates so
    child processes (including other tools that call ``devcap``) reuse them.
    """
    held = Hold(gate_names(pools, sims, devices), purpose, wait_seconds, hold_seconds,
                root or lock_root())
    previous = os.environ.get(HELD_ENV)
    held.acquire()
    try:
        os.environ[HELD_ENV] = held.environment()[HELD_ENV]
        yield held
    finally:
        if previous is None:
            os.environ.pop(HELD_ENV, None)
        else:
            os.environ[HELD_ENV] = previous
        held.finish()

# endregion

# region Unmanaged simulators

#: Seconds a simulator may stay booted outside any hold before waiters shut
#: it down (owner decision, 2026-10-13).
DEFAULT_REAP_GRACE_SECONDS = 300.0

#: Seconds between scans of booted simulators while waiting at the head of the queue.
SCAN_INTERVAL_SECONDS = 10.0


#: Seconds a warm simulator stays reserved for its lane's next run before a
#: waiting lane may evict it when every slot is in use.
DEFAULT_EVICT_AFTER_SECONDS = 60.0


def _seconds_setting(env: str, key: str, default: float, root: Path | None) -> float | None:
    """A seconds setting from ``env``, then ``config.json`` ``key``, then ``default``; ``off`` is None."""
    raw = os.environ.get(env)
    if raw is None:
        try:
            raw = json.loads(((root or lock_root()) / "config.json").read_text(encoding="utf-8")).get(key)
        except (OSError, ValueError, AttributeError):
            raw = None
    if raw is None:
        return default
    if str(raw).strip().lower() in ("off", "never", "none"):
        return None
    try:
        return max(0.0, float(raw))
    except (TypeError, ValueError):
        return default


def evict_after(root: Path | None = None) -> float | None:
    """How long a warm simulator is kept for its lane while others wait (``DEVCAP_EVICT_AFTER``)."""
    return _seconds_setting("DEVCAP_EVICT_AFTER", "evict_after_seconds", DEFAULT_EVICT_AFTER_SECONDS, root)


def shut_down_unheld(root: Path, entry: dict, reason: str) -> bool:
    """Shut an unheld simulator down while holding its device gate, so no lane takes it meanwhile.

    Returns:
        False when someone took the device gate first (the simulator is left alone).
    """
    gate = Gate(device_gate(entry["udid"]), root, 1)
    if not gate._try_slots():
        return False
    try:
        shutdown_sims([entry["udid"]])
        log_event(f"{reason} {entry['name']} ({entry['udid']}) booted outside any hold for "
                  f"{describe_age(entry['unheld_for'])}", root)
    finally:
        gate._unlock(gate._handle)
        gate._handle = gate._slot = None
    return True


def reap_grace(root: Path | None = None) -> float | None:
    """Grace before idle unmanaged simulators are shut down automatically.

    ``DEVCAP_REAP_GRACE``, then ``config.json``'s ``reap_grace_seconds``, then
    300 s. ``off`` disables automatic reaping; unmanaged simulators still
    count against the slots.
    """
    raw = os.environ.get("DEVCAP_REAP_GRACE")
    if raw is None:
        try:
            raw = json.loads(((root or lock_root()) / "config.json").read_text(encoding="utf-8")).get(
                "reap_grace_seconds")
        except (OSError, ValueError, AttributeError):
            raw = None
    if raw is None:
        return DEFAULT_REAP_GRACE_SECONDS
    if str(raw).strip().lower() in ("off", "never", "none"):
        return None
    try:
        return max(0.0, float(raw))
    except (TypeError, ValueError):
        return DEFAULT_REAP_GRACE_SECONDS


def list_sims() -> list[dict] | None:
    """Every simulator as ``{"udid", "name", "booted", "type", "runtime", "available"}``.

    Returns [] without Xcode and None when ``simctl`` fails.
    """
    try:
        out = subprocess.run(["xcrun", "simctl", "list", "devices", "-j"],
                             capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        return []
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    try:
        devices = json.loads(out.stdout).get("devices", {})
    except (TypeError, ValueError, AttributeError):
        return None
    return [{"udid": d["udid"].upper(), "name": d.get("name", d["udid"]), "booted": d.get("state") == "Booted",
             "state": d.get("state", ""), "type": d.get("deviceTypeIdentifier", ""), "runtime": runtime,
             "available": d.get("isAvailable", True)}
            for runtime, items in devices.items() for d in items if "udid" in d]


def pool_names(name: str, size: int) -> list[str]:
    """Names of a simulator pool: the base device, then ``"<name> (pool 2)"`` and up."""
    return [name] + [f"{name} (pool {index})" for index in range(2, max(1, size) + 1)]


def pick_sim(name: str, size: int, prefer: str | None = None, root: Path | None = None) -> str | None:
    """Pick a simulator for a run from the pool of identical devices named after ``name``.

    Lanes that want the same device type would otherwise queue on one
    device gate while simulator slots sit free. Missing pool members are
    created with the base device's type and runtime (never booted here).
    The choice is ``prefer`` (the lane's last device, still warm) if nobody
    holds or waits for it, else the first free member, else ``prefer`` or
    the base to queue on. A lane that races another for the same free member
    simply waits on its device gate.

    Args:
        name: Base simulator name, e.g. ``"iPad Pro 11-inch (M5)"``.
        size: Pool size (the base counts as one).
        prefer: UDID this lane used last.
        root: State directory.

    Returns:
        A UDID, or None when no available simulator has the base name.
    """
    root = root or lock_root()
    sims = [s for s in (list_sims() or []) if s.get("available", True)]
    base = next((s for s in sims if s["name"] == name), None)
    if base is None:
        return None
    members = [s["udid"] for s in sims if s["name"] == name]  # every same-named device joins the pool
    for member in pool_names(name, size)[1:]:
        found = next((s for s in sims if s["name"] == member), None)
        if found is None and base.get("type") and base.get("runtime"):
            udid = create_sim(member, base["type"], base["runtime"], root, kind="pool")
            if udid is None:
                continue
            found = {"udid": udid, "name": member}
        if found is not None:
            members.append(found["udid"])

    def free(udid: str) -> bool:
        gate = Gate(device_gate(udid), root, 1)
        return not gate.holders() and not gate.waiting()

    prefer = prefer.upper() if prefer else None
    if prefer in members and free(prefer):
        chosen = prefer
    else:
        chosen = next((udid for udid in members if free(udid)), None) or (prefer if prefer in members else members[0])
    note_released([chosen], root)  # picking counts as use: the idle reaper must not take it before the run holds it
    return chosen


def debugged_from_ps(text: str) -> set[str]:
    """UDIDs of simulators running an app under ``debugserver`` (Xcode's Run).

    Args:
        text: ``ps -axo pid=,ppid=,command=`` output.
    """
    procs = {}
    for line in text.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3:
            procs[parts[0]] = (parts[1], parts[2])
    found = set()
    for _pid, (ppid, command) in procs.items():
        match = re.search(r"/CoreSimulator/Devices/([0-9A-Fa-f-]{36})/data/Containers/Bundle/", command)
        parent = procs.get(ppid, ("", ""))[1].split(" ")[0]
        if match and parent.endswith("debugserver"):
            found.add(match.group(1).upper())
    return found


def debugged_sims() -> set[str] | None:
    """``debugged_from_ps`` for this Mac; None when ``ps`` fails (then nothing is reaped)."""
    try:
        out = subprocess.run(["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    return debugged_from_ps(out.stdout or "") if out.returncode == 0 else None


#: Swift source of the Device Hub window helper. System Events cannot see
#: Device Hub's windows on macOS 27, so devcap compiles this once per source
#: hash into ``~/.devcap/bin`` with ``swiftc`` and calls it by pid.
HUB_HELPER_SOURCE = r"""
import ApplicationServices
import Foundation

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func windows(_ pid: pid_t) -> [AXUIElement] {
    (attribute(AXUIElementCreateApplication(pid), "AXWindows") as? [AXUIElement]) ?? []
}

func emit(_ object: Any, _ code: Int32 = 0) -> Never {
    FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: object))
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard AXIsProcessTrusted() else { emit(["error": "not-trusted"], 4) }
switch arguments.first {
case "windows":
    var list: [[String: Any]] = []
    for raw in arguments.dropFirst() {
        guard let pid = pid_t(raw) else { continue }
        for (index, window) in windows(pid).enumerated() {
            list.append(["pid": Int(pid), "window": index, "title": (attribute(window, "AXTitle") as? String) ?? ""])
        }
    }
    emit(["windows": list])
case "close":
    guard arguments.count == 3, let pid = pid_t(arguments[1]), let index = Int(arguments[2]) else {
        emit(["error": "usage: close <pid> <window>"], 2)
    }
    let list = windows(pid)
    guard list.indices.contains(index), let button = attribute(list[index], "AXCloseButton") else {
        emit(["error": "no close button"], 3)
    }
    let result = AXUIElementPerformAction(button as! AXUIElement, "AXPress" as CFString)
    emit(result == .success ? ["closed": index] : ["error": "AXPress failed"], result == .success ? 0 : 3)
default:
    emit(["error": "usage: windows <pid>... | close <pid> <window>"], 2)
}
"""

#: Device Hub's executable inside Xcode (``pgrep -f`` pattern).
HUB_PROCESS = "DeviceHub.app/Contents/MacOS/DeviceHub"


def hub_helper(root: Path) -> Path | None:
    """The compiled Device Hub helper, built on first use; None if it cannot be built."""
    digest = hashlib.sha256(HUB_HELPER_SOURCE.encode()).hexdigest()[:12]
    binary = root / "bin" / f"hub_ax-{digest}"
    failed = binary.with_suffix(".failed")
    if binary.exists():
        return binary
    if failed.exists():
        return None
    binary.parent.mkdir(parents=True, exist_ok=True)
    source = binary.with_suffix(".swift")
    source.write_text(HUB_HELPER_SOURCE, encoding="utf-8")
    try:
        built = subprocess.run(["xcrun", "swiftc", "-O", "-o", str(binary), str(source)],
                               capture_output=True, text=True, timeout=600)
    except (OSError, subprocess.SubprocessError):
        return None
    if built.returncode != 0 or not binary.exists():
        failed.write_text(built.stderr[-2000:], encoding="utf-8")
        return None
    return binary


def hub_windows(root: Path) -> tuple[Path, list[dict]] | None:
    """The helper and Device Hub's windows (``pid``, ``window``, ``title``), or None when unavailable.

    ``DEVCAP_HUB=off`` turns Device Hub handling off.
    """
    if os.environ.get("DEVCAP_HUB", "").lower() == "off" or sys.platform != "darwin":
        return None
    try:
        pids = subprocess.run(["pgrep", "-f", HUB_PROCESS], capture_output=True, text=True,
                              timeout=30).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return None
    helper = hub_helper(root) if pids else None
    if helper is None:
        return None
    try:
        out = subprocess.run([str(helper), "windows", *pids], capture_output=True, text=True, timeout=60)
        return helper, json.loads(out.stdout).get("windows", [])
    except (OSError, subprocess.SubprocessError, TypeError, ValueError, AttributeError):
        return None


def hub_device_name(title: str) -> str:
    """Device name from a Device Hub window title (``"iPhone 17 Pro (Rooms) – iOS 27.0"``)."""
    return title.rsplit(" \u2013 ", 1)[0] if " \u2013 " in title else title


def windows_to_close(windows: list[dict], keep_names: set[str], first_seen: dict[str, float],
                     now: float, grace: float, sim_names: set[str] | None = None) -> tuple[list[dict], dict[str, float]]:
    """Pick Device Hub windows to close.

    A window stays open while its device is in use (held, about to be used,
    or under Xcode's debugger). Every other window, including empty "Devices –
    No Selection" ones, closes once it has been open for ``grace`` seconds,
    so a window a lane is still setting up is never closed. Only windows of
    known simulators (``sim_names``) and empty "Devices" windows are ever
    closed, never a physical device's. Windows are keyed by pid, title and
    occurrence, since indices shift as others close.

    Returns:
        ``(to_close, first_seen)``: windows to close, highest index first, and
        the updated first-seen times.
    """
    seen: dict[str, float] = {}
    counts: dict[str, int] = {}
    to_close = []
    for window in sorted(windows, key=lambda w: (w["pid"], w["window"])):
        title = window.get("title", "")
        name = hub_device_name(title)
        if name in keep_names or (sim_names is not None and name not in sim_names and name != "Devices"):
            continue
        counts[title] = counts.get(title, 0) + 1
        key = f"{window['pid']}:{title}#{counts[title]}"
        seen[key] = first_seen.get(key, now)
        if now - seen[key] >= grace:
            to_close.append(window)
    return sorted(to_close, key=lambda w: (w["pid"], w["window"]), reverse=True), seen


def scan_unmanaged(root: Path | None = None, exclude: Sequence[str] = (), reap: bool = True,
                   grace: float | None = -1.0) -> list[dict] | None:
    """Find simulators booted outside any hold; shut down idle ones and their windows.

    A booted simulator is *unmanaged* when nobody holds its device gate. The
    first time a scan sees it unmanaged is recorded in ``reaper.json``; once
    it has stayed unmanaged for the grace period (``reap_grace``) it is shut
    down under its own device gate, so a lane that takes it meanwhile is never
    hit. Simulators running an app under Xcode's debugger are never reaped.
    The same pass closes Device Hub windows of devices nobody is using
    (``windows_to_close``). Only one process scans at a time
    (``reaper.lock``); others reuse its last result.

    Args:
        root: State directory.
        exclude: UDIDs the caller is about to use; never reaped or returned.
        reap: False only reports (``status``).
        grace: Override for ``reap_grace`` (None disables reaping).

    Returns:
        Remaining unmanaged simulators (``udid``, ``name``, ``unheld_for``,
        ``debugged``), or None when ``simctl`` could not be read.
    """
    root = root or lock_root()
    grace = reap_grace(root) if grace == -1.0 else grace
    excluded = {u.upper() for u in exclude}
    root.mkdir(parents=True, exist_ok=True)
    state_path = root / "reaper.json"
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        state = {}
    lock = Gate._lock(root / "reaper.lock")
    if lock is None:  # another process is scanning; reuse its result
        return [u for u in state.get("unmanaged", []) if u["udid"].upper() not in excluded]
    try:
        sims = list_sims()
        if sims is None:
            return None
        debugged = debugged_sims()
        now = time.time()
        first_seen = state.get("first_unheld", {})
        unmanaged, in_use = [], set()
        for sim in sims:
            udid = sim["udid"].upper()
            if udid in excluded or Gate(device_gate(udid), root).holders():
                in_use.add(sim["name"])
                first_seen.pop(udid, None)
                continue
            if not sim["booted"]:
                first_seen.pop(udid, None)
                continue
            since = first_seen.setdefault(udid, now)
            entry = {"udid": udid, "name": sim["name"], "unheld_for": now - since,
                     # None when ps failed: unknown is treated like "under the debugger".
                     "debugged": (udid in debugged) if debugged is not None else None}
            if entry["debugged"] is not False:
                in_use.add(sim["name"])
            idle = grace is not None and entry["unheld_for"] >= grace
            if reap and idle and entry["debugged"] is False:
                if shut_down_unheld(root, entry, "reap"):
                    first_seen.pop(udid, None)
                    continue
            unmanaged.append(entry)
        window_seen = state.get("windows", {})
        if reap and grace is not None and debugged is not None and (hub := hub_windows(root)):
            helper, windows = hub
            sim_udids = {sim["udid"].upper() for sim in sims}
            physical_in_use = any(name.startswith("device-") and name[7:] not in sim_udids
                                  and Gate(name, root).holders() for name in known_gates(root))
            # A held physical device's name could match a simulator's: then close only empty windows.
            closable = set() if physical_in_use else {sim["name"] for sim in sims}
            to_close, window_seen = windows_to_close(windows, in_use, window_seen, now, grace, closable)
            for window in to_close:
                try:
                    subprocess.run([str(helper), "close", str(window["pid"]), str(window["window"])],
                                   capture_output=True, timeout=30)
                    log_event(f"close Device Hub window {window['title']!r}", root)
                except (OSError, subprocess.SubprocessError):
                    pass
        state = {"first_unheld": first_seen, "windows": window_seen, "unmanaged": unmanaged,
                 "scanned_epoch": now}
        state_path.write_text(json.dumps(state), encoding="utf-8")
        return unmanaged
    finally:
        Gate._unlock(lock)

# endregion

# region Simulator lifecycle

#: Smallest simslim that can slim a simulator between ``create`` and its first boot (``on --preserve-boot-state``).
SIMSLIM_PREBOOT = (0, 14)

#: A pool simulator unused this long (and shut down, unheld) is deleted by ``reap``.
DEFAULT_SIM_TTL_SECONDS = 24 * 3600.0

#: ``PRBPosterExtensionDataStore`` larger than this is deleted when a simulator is released.
DEFAULT_POSTER_LIMIT_BYTES = 4 * 1024 ** 3

#: Categories ``simslim disk-clean`` deletes on release (ids from ``simslim disk-categories``, all "lower risk").
DISK_CLEAN_CATEGORIES = "caches,logs,temporary"

#: Where a poster store lives, relative to a simulator's ``data`` directory.
POSTER_STORE = Path("Library/Application Support/PRBPosterExtensionDataStore")

#: Names of pool members made by ``pick_sim``: ``"<base> (pool 2)"`` and up.
POOL_MEMBER = re.compile(r".+ \(pool \d+\)$")


def devices_dir() -> Path:
    """CoreSimulator's device directory (``DEVCAP_SIM_DEVICES`` overrides it, for tests)."""
    return Path(os.environ.get("DEVCAP_SIM_DEVICES") or Path.home() / "Library/Developer/CoreSimulator/Devices")


def sims_state_path(root: Path | None = None) -> Path:
    """The small state file of simulators devcap made: created time, last release, kind."""
    return (root or lock_root()) / "sims.json"


def load_sims_state(root: Path | None = None) -> dict[str, dict]:
    """Read ``sims.json`` (UDID to record); a missing or unreadable file is empty."""
    try:
        data = json.loads(sims_state_path(root).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return {k: v for k, v in data.items() if isinstance(v, dict)} if isinstance(data, dict) else {}


def save_sims_state(state: dict[str, dict], root: Path | None = None) -> None:
    """Write ``sims.json`` atomically (best effort)."""
    path = sims_state_path(root)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(f".{os.getpid()}.tmp")
        tmp.write_text(json.dumps(state, indent=1, sort_keys=True), encoding="utf-8")
        os.replace(tmp, path)
    except OSError:
        pass


#: Tag of an unresolvable project; fails closed (``reap`` and ``status`` skip every member).
UNKNOWN_PROJECT = "unknown"

#: One retry per member per day for a failed pre-use slim (``simslim on`` can boot for minutes).
SLIM_RETRY_SECONDS = 24 * 3600.0


@contextmanager
def sims_state_lock(root: Path | None = None) -> Iterator[None]:
    """Serialize read-modify-write of ``sims.json`` across processes (same OS lock as the gates).

    Waits up to 10 s, then goes ahead unlocked rather than block a hold on a bookkeeping file.
    """
    base = root or lock_root()
    handle = None
    try:
        base.mkdir(parents=True, exist_ok=True)
        deadline = time.monotonic() + 10
        while handle is None and time.monotonic() < deadline:
            handle = Gate._lock(base / "sims.lock")
            if handle is None:
                time.sleep(0.02)
    except OSError:
        handle = None
    try:
        yield
    finally:
        if handle is not None:
            Gate._unlock(handle)


def project_tag() -> str:
    """Name of the repository this devcap copy belongs to (``DEVCAP_PROJECT`` overrides).

    Both repositories share ``~/.devcap``, so each simulator devcap creates is tagged with its
    project and ``reap`` deletes only its own project's. Worktrees resolve to their main repository.
    The path is the copy that was run (``CALLER_FILE``), not the shared install that may have taken
    over. ``UNKNOWN_PROJECT`` means it could not be resolved: ``is_pool_sim`` then claims nothing.
    """
    if env := os.environ.get("DEVCAP_PROJECT"):
        return env
    here = Path(CALLER_FILE or __file__).resolve().parent
    for folder in (here, *here.parents):
        marker = folder / ".git"
        if marker.is_dir():
            return folder.name
        if marker.is_file():
            try:
                gitdir = Path(marker.read_text(encoding="utf-8").split("gitdir:", 1)[1].strip())
                return gitdir.parents[1].parent.name if gitdir.parent.name == "worktrees" else folder.name
            except (OSError, IndexError):
                return folder.name
    return UNKNOWN_PROJECT


def note_sim(udid: str, root: Path | None = None, **fields) -> None:
    """Merge ``fields`` into one simulator's record in ``sims.json``."""
    with sims_state_lock(root):
        state = load_sims_state(root)
        state.setdefault(udid.upper(), {}).update(fields)
        save_sims_state(state, root)


def note_released(udids: Iterable[str], root: Path | None = None, now: float | None = None) -> None:
    """Record the time a hold on, or a pick of, these simulators ended or began (the idle TTL counts from it)."""
    udids = [u.upper() for u in udids]
    if not udids:
        return
    stamp = time.time() if now is None else now
    with sims_state_lock(root):
        state = load_sims_state(root)
        for udid in udids:
            state.setdefault(udid, {})["last_release_epoch"] = stamp
        save_sims_state(state, root)


def simslim_version() -> tuple[int, ...] | None:
    """Installed simslim's version as a tuple, or None when it is missing or unreadable."""
    try:
        out = subprocess.run(["simslim", "--version"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", (out.stdout or "") + (out.stderr or ""))
    if out.returncode != 0 or not match:
        return None
    return tuple(int(part) for part in match.groups(default="0"))


def create_sim(name: str, device_type: str, runtime: str, root: Path | None = None, kind: str = "pool") -> str | None:
    """Create a simulator of an exact device type and runtime; it is never booted here.

    The type comes from the base device, so an iPhone Duo pool member is a Duo
    (never a plain iPhone). The record in ``sims.json`` is tagged with the project
    and ``slim: pending``: the first hold on the device slims it before its first
    boot (``slim_new_sim``), because ``simslim on`` boots the simulator.

    Args:
        name: New simulator name.
        device_type: ``com.apple.CoreSimulator.SimDeviceType...`` identifier.
        runtime: Runtime identifier.
        root: State directory.
        kind: ``"pool"`` or ``"ephemeral"``, recorded for the reaper.

    Returns:
        The new UDID, or None when ``simctl create`` failed.
    """
    try:
        created = subprocess.run(["xcrun", "simctl", "create", name, device_type, runtime],
                                 capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError):
        return None
    udid = created.stdout.strip().upper()
    if created.returncode != 0 or not SIM_UDID.fullmatch(udid):
        return None
    log_event(f"create {kind} simulator {name} ({udid})", root)
    note_sim(udid, root, name=name, kind=kind, type=device_type, runtime=runtime, created_epoch=time.time(),
             last_release_epoch=time.time(), project=project_tag(), slim="pending")
    return udid


def slim_new_sim(udid: str, root: Path | None = None) -> None:
    """Slim a freshly created simulator before its first boot, once; the caller holds its gates.

    ``simslim on --preserve-boot-state`` writes the overrides and *does boot the simulator*
    (it reboots to apply them, then returns an initially shut-down device to shutdown), so it
    must run inside the hold: ``Hold.acquire`` calls this right after the device and
    ``simulator`` gates are taken. Needs simslim 0.14 or later; older or missing simslim leaves
    the device stock for ``sim_slim.sh``. A failed run is logged and retried at most once a day.
    """
    root = root or lock_root()
    record = load_sims_state(root).get(udid.upper())
    if not record or record.get("slim") != "pending":
        return
    version = simslim_version()
    if version is None or version < SIMSLIM_PREBOOT:
        return
    if time.time() - float(record.get("slim_failed_epoch", 0)) < SLIM_RETRY_SECONDS:
        return  # failed recently: at most one retry per member per day
    command = ["simslim", "on", udid.upper(), "--preserve-boot-state"]
    if profile := os.environ.get("DEVCAP_SLIM_PROFILE"):
        command += ["--profile", profile]
    try:
        slimmed = subprocess.run(command, capture_output=True, text=True, timeout=600)
        ok = slimmed.returncode == 0
        log_event(f"slim {udid} before first use (held): exit {slimmed.returncode}", root)
    except (OSError, subprocess.SubprocessError):
        ok = False
        log_event(f"slim {udid} before first use (held): failed to run simslim", root)
    if ok:
        note_sim(udid, root, slim="done")
    else:
        note_sim(udid, root, slim_failed_epoch=time.time())


def dir_size(path: Path) -> int:
    """Bytes under ``path`` (allocated blocks, symlinks not followed); 0 when it does not exist."""
    total = 0
    for base, dirs, files in os.walk(path, onerror=lambda _e: None):
        for name in files:
            try:
                total += os.lstat(os.path.join(base, name)).st_blocks * 512
            except OSError:
                pass
    return total


def poster_limit(root: Path | None = None) -> float | None:
    """Poster store size (bytes) past which a release deletes it (``DEVCAP_POSTER_LIMIT_MB``; ``off`` disables)."""
    megabytes = _seconds_setting("DEVCAP_POSTER_LIMIT_MB", "poster_limit_mb", DEFAULT_POSTER_LIMIT_BYTES / 1024 ** 2, root)
    return None if megabytes is None else megabytes * 1024 ** 2


def reset_sim(udid: str, root: Path | None = None) -> None:
    """Reset a shut-down simulator while the caller still holds its device gate.

    Deletes ``PRBPosterExtensionDataStore`` when it exceeds ``poster_limit``
    (it grows without bound on a used simulator), then runs ``simslim
    disk-clean`` when simslim is installed. Never touches a booted simulator
    (the caller guarantees it is shut down) and keeps the slim overrides,
    which live outside ``data/Library``.
    """
    root = root or lock_root()
    if not SIM_UDID.fullmatch(udid):
        return
    limit = poster_limit(root)
    store = devices_dir() / udid.upper() / "data" / POSTER_STORE
    if limit is not None and store.is_dir() and not store.is_symlink():
        size = dir_size(store)
        if size > limit:
            shutil.rmtree(store, ignore_errors=True)
            if store.exists():
                log_event(f"reset {udid}: WARNING could not delete the poster store ({size // 1024 ** 2} MB)", root)
            else:
                log_event(f"reset {udid}: deleted poster store ({size // 1024 ** 2} MB)", root)
    if simslim_version() is not None:
        try:
            cleaned = subprocess.run(["simslim", "disk-clean", udid.upper(), "--categories", DISK_CLEAN_CATEGORIES,
                                      "--confirm"], capture_output=True, text=True, timeout=300)
            note = "" if cleaned.returncode == 0 else "WARNING "
            log_event(f"reset {udid}: {note}simslim disk-clean exit {cleaned.returncode}", root)
        except (OSError, subprocess.SubprocessError):
            log_event(f"reset {udid}: WARNING simslim disk-clean could not run", root)


def reset_released(udids: Sequence[str], root: Path | None = None) -> None:
    """Reset the ones of ``udids`` that are shut down now (a warm, booted simulator is left alone)."""
    sims = {s["udid"]: s for s in list_sims() or []}
    for udid in udids:
        info = sims.get(udid.upper())
        if info is not None and not info["booted"]:
            reset_sim(udid, root)


def delete_sim(udid: str, root: Path | None = None, why: str = "") -> bool:
    """Delete a simulator and forget its record. The caller holds its device gate and has shut it down."""
    if not SIM_UDID.fullmatch(udid):
        return False
    try:
        out = subprocess.run(["xcrun", "simctl", "delete", udid.upper()], capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.SubprocessError):
        return False
    if out.returncode != 0:
        return False
    log_event(f"delete simulator {udid} {why}".strip(), root)
    with sims_state_lock(root):
        state = load_sims_state(root)
        if state.pop(udid.upper(), None) is not None:
            save_sims_state(state, root)
    return True


def sim_ttl(root: Path | None = None) -> float | None:
    """Idle time after which ``reap`` deletes a pool simulator (``DEVCAP_SIM_TTL``; ``off`` disables)."""
    return _seconds_setting("DEVCAP_SIM_TTL", "sim_ttl_seconds", DEFAULT_SIM_TTL_SECONDS, root)


def is_pool_sim(info: dict, state: dict[str, dict]) -> bool:
    """True for a simulator this project's devcap made (pool or ephemeral, in ``sims.json``).

    ``~/.devcap`` is shared by every repository, so records are tagged with ``project_tag()``
    and only the tag's owner counts them. A base device, another project's member and an
    untagged legacy ``(pool N)`` simulator (``ci_hygiene`` handles those) are not candidates.
    """
    record = state.get(info["udid"], {})
    mine = project_tag()
    return (mine != UNKNOWN_PROJECT and record.get("kind") in ("pool", "ephemeral")
            and record.get("project") == mine)


def sim_state(info: dict) -> str:
    """CoreSimulator's state name for a ``list_sims`` entry (``Shutdown``, ``Booted``, ``Booting`` ...)."""
    return info.get("state") or ("Booted" if info["booted"] else "Shutdown")


def reap_idle_sims(root: Path | None = None, ttl: float | None = None, dry_run: bool = False,
                   now: float | None = None) -> list[dict]:
    """Delete this project's pool simulators idle longer than ``ttl`` that are shut down and unheld.

    Only simulators devcap made for this project (``is_pool_sim``) are candidates; a base
    device or another project's device is never touched. The decision uses a snapshot, so
    after the device gate is taken it is re-checked: nobody queued behind it, the simulator
    is exactly ``Shutdown`` and its release time has not moved. Any change skips it.

    Returns:
        The simulators deleted (or that would be, with ``dry_run``), as ``{"udid", "name", "idle"}``.
    """
    root = root or lock_root()
    ttl = sim_ttl(root) if ttl is None else ttl
    sims = list_sims()
    if ttl is None or sims is None:
        return []
    stamp = time.time() if now is None else now
    state = load_sims_state(root)
    removed = []
    for info in sims:
        if sim_state(info) != "Shutdown" or not is_pool_sim(info, state):
            continue
        last = state[info["udid"]].get("last_release_epoch")
        if last is None:
            note_sim(info["udid"], root, last_release_epoch=stamp)  # pre-existing record: the clock starts now
            continue
        idle = stamp - float(last)
        if idle <= ttl:
            continue
        entry = {"udid": info["udid"], "name": info["name"], "idle": idle}
        if dry_run:
            removed.append(entry)
            continue
        gate = Gate(device_gate(info["udid"]), root, 1)
        if gate.waiting() or not gate._try_slots():
            continue
        try:
            fresh = next((s for s in list_sims() or [] if s["udid"] == info["udid"]), None)
            again = load_sims_state(root).get(info["udid"], {}).get("last_release_epoch")
            if (fresh is None or sim_state(fresh) != "Shutdown" or gate.waiting() or again != last):
                continue
            if delete_sim(info["udid"], root, f"({info['name']}) idle {describe_age(idle)}"):
                removed.append(entry)
        finally:
            gate._unlock(gate._handle)
            gate._handle = gate._slot = None
    return removed


def pool_report(root: Path | None = None, total: bool = False) -> dict:
    """This project's pool simulators with their disk use, for ``status``.

    Args:
        root: State directory.
        total: Also walk the whole CoreSimulator directory (tens of GB: slow, so only on ``status --disk``).
    """
    root = root or lock_root()
    state = load_sims_state(root)
    members = []
    for info in list_sims() or []:
        if not is_pool_sim(info, state):
            continue
        last = state.get(info["udid"], {}).get("last_release_epoch")
        members.append({"udid": info["udid"], "name": info["name"], "booted": info["booted"],
                        "size_bytes": dir_size(devices_dir() / info["udid"]),
                        "idle_seconds": None if last is None else max(0.0, time.time() - float(last))})
    return {"project": project_tag(), "members": members, "total_bytes": dir_size(devices_dir()) if total else None}


def human_bytes(count: float) -> str:
    """``count`` bytes as ``"1.5 GB"`` style text."""
    for unit in ("B", "KB", "MB", "GB"):
        if count < 1024 or unit == "GB":
            return f"{count:.0f} {unit}" if unit == "B" else f"{count:.1f} {unit}"
        count /= 1024
    return f"{count:.1f} GB"


def make_ephemeral(base_name: str, root: Path | None = None) -> str | None:
    """Create a job-scoped simulator of the same type and runtime as the one named ``base_name``.

    The type is read from the base device, so an iPhone Duo base gives a Duo.

    Returns:
        The new UDID, or None when the base does not exist or creation failed.
    """
    sims = [s for s in list_sims() or [] if s.get("available", True)]
    base = next((s for s in sims if s["name"] == base_name), None)
    if base is None or not base.get("type") or not base.get("runtime"):
        return None
    return create_sim(f"{base_name} (job {os.getpid()})", base["type"], base["runtime"], root, kind="ephemeral")

# endregion

# region CLI


#: A simulator UDID; ``--sim`` accepts nothing else, so ``--shutdown`` can never
#: become ``simctl shutdown all`` or hit a device by name.
SIM_UDID = re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")


def shutdown_sims(udids: Sequence[str]) -> None:
    """Shut simulators down (best effort), so they stop using memory once a hold ends.

    Args:
        udids: Simulator UDIDs; anything that is not a UDID is skipped.
    """
    for udid in udids:
        if not SIM_UDID.fullmatch(udid):
            continue
        try:
            subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True, timeout=120)
        except (OSError, subprocess.SubprocessError):
            pass


def run_command(held: Hold, command: list[str]) -> int:
    """Run ``command`` in its own process group while ``held`` is held.

    SIGINT, SIGTERM and SIGHUP are forwarded to the whole group; a hold overrun
    terminates it (the watchdog then runs ``held.cleanup`` and releases).

    Returns:
        The command's exit code: 128 + signal number when it was signalled,
        or ``HOLD_TIMEOUT_EXIT`` when the hold overran.
    """
    proc = subprocess.Popen(command, env=held.environment(), start_new_session=os.name != "nt")

    def stop_group(sig=signal.SIGTERM) -> None:
        if proc.poll() is not None:
            return
        try:
            if os.name == "nt":
                proc.kill()
            else:
                os.killpg(proc.pid, sig)
        except OSError:
            pass

    def kill_after_grace() -> None:
        stop_group(signal.SIGTERM)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            stop_group(getattr(signal, "SIGKILL", signal.SIGTERM))

    held.on_overrun = kill_after_grace
    forwarded = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP) if os.name != "nt" else ()
    previous = {sig: signal.signal(sig, lambda signum, _frame: stop_group(signum)) for sig in forwarded}
    try:
        code = proc.wait()
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    if held.overran:
        return HOLD_TIMEOUT_EXIT
    return 128 - code if code < 0 else code


def cmd_run(args: argparse.Namespace) -> int:
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        print("devcap run: missing command after --", file=sys.stderr)
        return 2
    if bad := [udid for udid in args.sim if not SIM_UDID.fullmatch(udid)]:
        print(f"devcap run: --sim takes a simulator UDID, not {', '.join(map(repr, bad))}", file=sys.stderr)
        return 2
    names_given = gate_names(args.pool, args.sim, args.device)
    if not names_given and not args.ephemeral_sim:
        print("devcap run: name at least one --pool, --sim or --device", file=sys.stderr)
        return 2
    hold_seconds = None if args.hold <= 0 else min(args.hold, MAX_HOLD_SECONDS)
    ephemeral = None
    acquired = False
    previous = {}
    if os.name != "nt":  # a signal while queued must unwind (and delete the ephemeral simulator), not just kill us

        def unwind(signum, _frame):
            raise SystemExit(128 + signum)
        previous = {sig: signal.signal(sig, unwind) for sig in (signal.SIGTERM, signal.SIGHUP)}
    try:
        if args.ephemeral_sim:
            ephemeral = make_ephemeral(args.ephemeral_sim)
            if ephemeral is None:
                print(f"devcap run: could not create a simulator like {args.ephemeral_sim!r}", file=sys.stderr)
                return 1
            args.sim = [*args.sim, ephemeral]
            command = [part.replace("{udid}", ephemeral) for part in command]
            os.environ[EPHEMERAL_ENV] = ephemeral
        names = gate_names(args.pool, args.sim, args.device)
        held = Hold(names, args.purpose or " ".join(command)[:120], args.wait, hold_seconds)
        if (args.shutdown or args.shutdown_on_timeout or ephemeral) and args.sim:  # before acquire() starts the watchdog
            others = [udid for udid in args.sim if udid != ephemeral]

            def cleanup() -> None:
                if ephemeral:  # job-scoped: gone with the job, under its device gate
                    shutdown_sims([ephemeral])
                    delete_sim(ephemeral, why="(ephemeral, job finished)")
                if others and (args.shutdown or held.overran):
                    shutdown_sims(others)
                    if not args.no_reset:
                        reset_released(others)
            held.cleanup = cleanup
            held.cleanup_on_finish = args.shutdown or bool(ephemeral)
        try:
            held.acquire()
            acquired = True
        except WaitTimeout as error:
            print(f"devcap: {error}", file=sys.stderr)
            return WAIT_TIMEOUT_EXIT
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)
        try:
            return run_command(held, command)
        finally:
            held.finish()  # after an overrun, blocks until the watchdog has cleaned up and exited
    finally:
        if ephemeral and not acquired:  # never held, so nothing else can be using it
            shutdown_sims([ephemeral])
            delete_sim(ephemeral, why="(ephemeral, never held)")
        for sig, handler in previous.items():
            signal.signal(sig, handler)


#: Directories under the state root that are not gates.
NOT_GATES = {"lib", "bin"}


def known_gates(root: Path) -> list[str]:
    """Gate directories present under ``root`` plus the two standard pools.

    Skips ``lib``/``bin`` (the shared install and the Device Hub helper) and
    any directory whose name is not a valid gate name.
    """
    found = {p.name for p in root.iterdir() if p.is_dir() and p.name not in NOT_GATES
             and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", p.name)} if root.exists() else set()
    return sorted(found | {"simulator", "build"})


def cmd_status(args: argparse.Namespace) -> int:
    root = lock_root()
    now = time.time()
    unmanaged = scan_unmanaged(root, reap=False) or []
    report = []
    for name in known_gates(root):
        gate = Gate(name, root)
        report.append({"gate": name, "slots": gate.slots, "holders": gate.holders(),
                       "waiting": gate.waiting()})
    pool = pool_report(root, total=args.disk)
    if args.json:
        print(json.dumps({"gates": report, "unmanaged": unmanaged, "pool": pool}, indent=2))
        return 0
    for entry in report:
        if entry["gate"].startswith("device-") and not entry["holders"] and not entry["waiting"]:
            continue
        print(f"{entry['gate']}: {len(entry['holders'])}/{entry['slots']} held, "
              f"{len(entry['waiting'])} waiting")
        for h in entry["holders"]:
            age = describe_age(now - h.get("acquired_epoch", now))
            print(f"  slot {h['slot']}: pid {h.get('pid')} for {age}  {h.get('purpose', '')}  ({h.get('cwd', '?')})")
        for index, w in enumerate(entry["waiting"], 1):
            print(f"  queue {index}: pid {w['pid']}  {w['purpose']}")
    print(f"simulator pool: {len(pool['members'])} member(s), "
          f"{human_bytes(sum(m['size_bytes'] for m in pool['members']))}"
          + (f"; all simulators {human_bytes(pool['total_bytes'])}" if pool["total_bytes"] is not None else "")
          + f" (project {pool['project']})")
    for m in pool["members"]:
        idle = "" if m["idle_seconds"] is None else f", idle {describe_age(m['idle_seconds'])}"
        print(f"  {m['name']} ({m['udid']}) {human_bytes(m['size_bytes'])}{'  booted' if m['booted'] else ''}{idle}")
    if unmanaged:
        print(f"booted outside any hold (count against 'simulator'): {len(unmanaged)}")
        for u in unmanaged:
            note = ("Xcode debugger, never reaped" if u["debugged"] else
                    "debugger state unknown, not reaped" if u["debugged"] is None else
                    "reaped when idle past the grace period")
            print(f"  {u['name']} ({u['udid']}) for {describe_age(u['unheld_for'])}  [{note}]")
    return 0


def cmd_reap(args: argparse.Namespace) -> int:
    configured = reap_grace(lock_root())
    grace = args.grace if args.grace is not None else (
        configured if configured is not None else DEFAULT_REAP_GRACE_SECONDS)
    if args.dry_run:
        grace = None
    left = scan_unmanaged(lock_root(), reap=not args.dry_run, grace=grace)
    if left is None:
        print("devcap reap: could not list booted simulators", file=sys.stderr)
        return 1
    for u in left:
        print(f"{u['name']} ({u['udid']}) booted outside any hold for {describe_age(u['unheld_for'])}"
              + (" (Xcode debugger)" if u["debugged"] else ""))
    for gone in reap_idle_sims(lock_root(), ttl=args.sim_ttl, dry_run=args.dry_run):
        print(f"{'would delete' if args.dry_run else 'deleted'} idle pool simulator {gone['name']} "
              f"({gone['udid']}) idle {describe_age(gone['idle'])}")
    return 0


def cmd_pick_sim(args: argparse.Namespace) -> int:
    udid = pick_sim(args.name, args.pool if args.pool else configured_slots("simulator"), args.prefer)
    if udid is None:
        print(f"devcap pick-sim: no available simulator named {args.name!r}", file=sys.stderr)
        return 1
    print(udid)
    return 0


def cmd_slots(args: argparse.Namespace) -> int:
    for pool in args.pool or ["simulator", "build"]:
        print(f"{pool}={configured_slots(pool)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="devcap", description=__doc__.split("\n\n")[0])
    parser.add_argument("--version", action="version", version=VERSION)
    sub = parser.add_subparsers(dest="cmd", required=True)

    run = sub.add_parser("run", help="wait for capacity, then run a command holding it")
    run.add_argument("--pool", action="append", default=[], help="pool to take a slot in (repeatable)")
    run.add_argument("--sim", action="append", default=[], metavar="UDID",
                     help="simulator: its device gate plus a 'simulator' slot (repeatable)")
    run.add_argument("--device", action="append", default=[], metavar="UDID",
                     help="physical device: its device gate only (repeatable)")
    run.add_argument("--shutdown", action="store_true",
                     help="shut the --sim simulators down before releasing, even after a hold timeout")
    run.add_argument("--shutdown-on-timeout", action="store_true",
                     help="keep the --sim simulators warm after the command, but shut them down if the hold "
                          "times out (a hung run)")
    run.add_argument("--ephemeral-sim", metavar="NAME", default=None,
                     help="create a job-scoped simulator like the one named NAME (same device type, so a Duo stays a "
                          f"Duo), hold it, put its UDID in ${EPHEMERAL_ENV} and in '{{udid}}' arguments, and delete it "
                          "when the job ends")
    run.add_argument("--no-reset", action="store_true",
                     help="skip the reset of a --sim simulator on release (poster store, simslim disk-clean)")
    run.add_argument("--purpose", default="", help="what this hold is for (shown to waiters)")
    run.add_argument("--wait", "--max-wait", dest="wait", type=float, metavar="SECONDS", default=default_wait(),
                     help=f"max seconds to queue for a slot; past it, exit {WAIT_TIMEOUT_EXIT} with a message "
                          f"(--max-wait is the same option; default %(default)s: {WAIT_ENV} or {DEFAULT_WAIT_SECONDS:.0f})")
    run.add_argument("--hold", type=float, default=DEFAULT_HOLD_SECONDS,
                     help=f"max seconds to hold, ≤{MAX_HOLD_SECONDS:.0f}; 0 = no limit (default %(default)s)")
    run.add_argument("command", nargs=argparse.REMAINDER, help="-- command [args...]")
    run.set_defaults(func=cmd_run)

    status = sub.add_parser("status", help="show holders and waiters for every gate")
    status.add_argument("--json", action="store_true")
    status.add_argument("--disk", action="store_true", help="also size every simulator on the Mac (slow)")
    status.set_defaults(func=cmd_status)

    reap = sub.add_parser("reap", help="shut down simulators booted outside any hold past the grace period")
    reap.add_argument("--grace", type=float, default=None,
                      help=f"seconds unheld before reaping (default: config, else {DEFAULT_REAP_GRACE_SECONDS:.0f})")
    reap.add_argument("--sim-ttl", type=float, default=None, metavar="SECONDS",
                      help="delete pool simulators idle this long that are shut down and unheld "
                           f"(default: DEVCAP_SIM_TTL or config, else {DEFAULT_SIM_TTL_SECONDS:.0f}; 'off' there disables)")
    reap.add_argument("--dry-run", action="store_true", help="only list them")
    reap.set_defaults(func=cmd_reap)

    install = sub.add_parser("install", help="make this copy the machine-wide one every newer copy defers to")
    install.add_argument("--force", action="store_true", help="replace even a newer installed copy")
    install.set_defaults(func=cmd_install)

    pick = sub.add_parser("pick-sim", help="print a free simulator from the pool named after --name")
    pick.add_argument("--name", required=True, help="base simulator name, e.g. 'iPad Pro 11-inch (M5)'")
    pick.add_argument("--pool", type=int, default=0, help="pool size (default: the simulator slot count)")
    pick.add_argument("--prefer", default=None, metavar="UDID", help="the lane's last simulator, kept if free")
    pick.set_defaults(func=cmd_pick_sim)

    slots = sub.add_parser("slots", help="print configured slot counts")
    slots.add_argument("pool", nargs="*")
    slots.set_defaults(func=cmd_slots)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)

# endregion

# region Shared install

#: Set to skip deferring to the shared install (tests, or debugging an old copy).
NO_DEFER_ENV = "DEVCAP_NO_DEFER"

#: The copy that was actually run, when a newer shared install took over its definitions.
CALLER_FILE: str | None = None


def installed_path(root: Path | None = None) -> Path:
    """The machine-wide copy every repository's devcap defers to when it is newer."""
    return (root or lock_root()) / "lib" / "devcap.py"


def version_key(version: str) -> tuple[int, ...]:
    """Comparable form of ``"1.2.10"``."""
    return tuple(int(part) for part in re.findall(r"\d+", version)[:3])


def file_version(path: Path) -> str | None:
    """``VERSION`` of a devcap file, or None if it is missing or unreadable."""
    try:
        match = re.search(r'^VERSION = "([0-9.]+)"', path.read_text(encoding="utf-8"), re.M)
    except (OSError, UnicodeDecodeError, ValueError):
        return None
    return match.group(1) if match else None


def trusted_file(path: Path) -> bool:
    """Whether ``path`` and its directory are this user's and writable by nobody else.

    The shared install is executed by every devcap copy, so it must be a
    regular file (not a symlink) owned by the current user, in a directory
    owned by the current user, neither group- nor world-writable.
    """
    if os.name == "nt":
        return False
    try:
        for entry in (path, path.parent):
            info = os.lstat(entry)
            kind_ok = stat.S_ISREG(info.st_mode) if entry == path else stat.S_ISDIR(info.st_mode)
            if not kind_ok or info.st_uid != os.getuid() or info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
                return False
    except OSError:
        return False
    return True


def defer_to_installed(namespace: dict) -> bool:
    """Replace this module's definitions with the shared install's when it is newer.

    Repositories and worktrees carry their own copies, and an old worktree
    must not bypass newer rules. Every copy from 1.2.1 on runs the newest
    version installed with ``devcap install``. The install must pass
    ``trusted_file``; it runs in its own namespace first, and only a clean
    run replaces this module's definitions, so a broken install falls back
    to the local copy.

    Returns:
        True when the shared install took over.
    """
    path = installed_path()
    try:
        if os.environ.get(NO_DEFER_ENV) or Path(__file__).resolve() == path.resolve():
            return False
    except OSError:
        return False
    installed = file_version(path)
    if not installed or version_key(installed) <= version_key(VERSION) or not trusted_file(path):
        return False
    name = f"{namespace.get('__name__', 'devcap')}_installed"
    module = types.ModuleType(name)
    module.__file__ = str(path)
    sys.modules[name] = module  # dataclasses look their module up here
    try:
        code = compile(path.read_text(encoding="utf-8"), str(path), "exec")
        exec(code, module.__dict__)
        if not callable(getattr(module, "main", None)) or getattr(module, "VERSION", None) != installed:
            raise ImportError("shared install did not define devcap")
        module.CALLER_FILE = namespace.get("__file__")
    except (Exception, SystemExit) as error:  # a broken install must never break every copy on the Mac
        sys.modules.pop(name, None)
        print(f"devcap: ignoring shared install {path} ({error.__class__.__name__}: {error}); "
              f"running {VERSION}", file=sys.stderr)
        return False
    namespace.update({key: value for key, value in module.__dict__.items()
                      if key not in ("__name__", "__file__", "__builtins__", "__doc__", "__spec__",
                                     "__loader__", "__package__")})
    return True


def cmd_install(args: argparse.Namespace) -> int:
    path = installed_path()
    source = Path(CALLER_FILE or __file__)  # the copy that was run, even when a newer install took over
    mine = file_version(source)
    current = file_version(path)
    if not mine:
        print(f"devcap install: cannot read VERSION from {source}", file=sys.stderr)
        return 1
    if current and version_key(current) > version_key(mine) and not args.force:
        print(f"devcap install: {path} already has newer {current}; this copy is {mine}", file=sys.stderr)
        return 1
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
    os.chmod(temporary, 0o644)
    temporary.replace(path)
    print(f"devcap install: {path} is now {mine} (was {current or 'not installed'})")
    return 0

# endregion


#: Whether a newer shared install replaced this copy's definitions at import.
DEFERRED = defer_to_installed(globals())

if __name__ == "__main__":
    sys.exit(main())
