#!/usr/bin/env python3
"""Bad-simulator list for ``tools/ios_uitest.sh`` (this repo's wrapper over vendored ``devcap``).

A simulator that failed its health check twice (``sim_healthy``: bootstatus and a
screenshot) is recorded in ``apple/.build/sim-bad/<udid>`` with a unix timestamp. For
6 hours (``TTL``) ``pick`` skips it, so a run never re-pins a dead device. When every
pool member is bad, ``pick`` exits 1 with
``INFRA: pool exhausted (<n> bad, disk <pct>% used)`` instead of retrying.

``tools/devcap.py`` is vendored from FestivalNativeApps and not edited here (see
``.agents/platforms/apple/capacity.md``), so the skip lives in this wrapper, which
imports devcap's ``pick_sim`` and pool helpers. Upstream note: ``devcap pick-sim``
should take ``--skip UDID`` (repeatable) and print the same exhausted line itself, and
should not refresh a skipped member's idle timer (today every pick calls ``note_released`` on devcap's own choice, so a
bad member is held off the idle reaper until its record expires). The list is per worktree (``apple/.build``).

Usage::

    sim_bad.py mark UDID          # record UDID as bad now
    sim_bad.py list               # live (unexpired) bad UDIDs, one per line
    sim_bad.py clear [UDID]       # forget UDID (or every record); a pass of sim_healthy does this itself
    sim_bad.py pick --name NAME --pool N [--prefer UDID]

``FENTON_SIM_BAD_DIR`` overrides the directory (tests).
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TTL = 6 * 3600  # seconds a bad record is honoured


def bad_dir() -> Path:
    """The directory holding one file per bad simulator."""
    return Path(os.environ.get("FENTON_SIM_BAD_DIR") or ROOT / "apple" / ".build" / "sim-bad")


def mark(udid: str, now: float | None = None) -> None:
    """Record ``udid`` as bad at ``now``."""
    directory = bad_dir()
    directory.mkdir(parents=True, exist_ok=True)
    (directory / udid.upper()).write_text(f"{now if now is not None else time.time():.0f}\n")


def live(now: float | None = None) -> set[str]:
    """UDIDs recorded bad within ``TTL``; expired or unreadable records are removed or ignored."""
    now = time.time() if now is None else now
    out: set[str] = set()
    directory = bad_dir()
    if not directory.is_dir():
        return out
    for path in directory.iterdir():
        try:
            stamp = float(path.read_text().strip())
        except (OSError, ValueError):
            continue
        if now - stamp > TTL:
            path.unlink(missing_ok=True)
        else:
            out.add(path.name.upper())
    return out


def clear(udid: str | None = None) -> None:
    """Forget ``udid``'s record, or every record when ``udid`` is None."""
    directory = bad_dir()
    if not directory.is_dir():
        return
    for path in directory.iterdir():
        if udid is None or path.name.upper() == udid.upper():
            path.unlink(missing_ok=True)


def disk_percent(path: str = "/") -> int:
    """Percent of the disk holding ``path`` that is used."""
    usage = shutil.disk_usage(path)
    return round(100 * usage.used / usage.total)


def exhausted_line(bad: int, pct: int) -> str:
    """The report when every pool member is bad."""
    return f"INFRA: pool exhausted ({bad} bad, disk {pct}% used)"


def pick(name: str, size: int, prefer: str | None, devcap, bad: set[str] | None = None) -> tuple[str | None, str | None]:
    """Choose a pool member that is not recorded bad.

    Args:
        name: Base simulator name.
        size: Pool size (0 means devcap's configured simulator slots).
        prefer: The lane's last UDID; ignored when bad.
        devcap: The ``devcap`` module (injected for tests).
        bad: Bad UDIDs (default: the live list).

    Returns:
        ``(udid, None)`` or ``(None, message)`` where the message is the failure to print.
    """
    bad = live() if bad is None else bad
    size = size or devcap.configured_slots("simulator")
    if prefer and prefer.upper() in bad:
        prefer = None
    chosen = devcap.pick_sim(name, size, prefer)
    if chosen is None:
        return None, f"devcap pick-sim: no available simulator named {name!r}"
    if chosen.upper() not in bad:
        return chosen, None
    # devcap picked a bad member (it knows nothing of the list): take the first free good one.
    members = [s["udid"] for s in (devcap.list_sims() or []) if s.get("available", True) and
               (s["name"] == name or s["name"] in devcap.pool_names(name, size))]
    good = [m for m in members if m.upper() not in bad]
    if not good:
        return None, exhausted_line(len(members), disk_percent())
    root = devcap.lock_root()

    def free(udid: str) -> bool:
        gate = devcap.Gate(devcap.device_gate(udid), root, 1)
        return not gate.holders() and not gate.waiting()

    chosen = next((m for m in good if free(m)), good[0])
    devcap.note_released([chosen], root)
    return chosen, None


def _load_devcap():
    sys.path.insert(0, str(ROOT))
    from tools import devcap  # noqa: PLC0415

    return devcap


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    sub.add_parser("mark").add_argument("udid")
    sub.add_parser("clear").add_argument("udid", nargs="?")
    p = sub.add_parser("pick")
    p.add_argument("--name", required=True)
    p.add_argument("--pool", type=int, default=0)
    p.add_argument("--prefer")
    args = parser.parse_args(argv)
    if args.cmd == "list":
        print("\n".join(sorted(live())))
        return 0
    if args.cmd == "clear":
        clear(args.udid)
        return 0
    if args.cmd == "mark":
        mark(args.udid)
        return 0
    udid, message = pick(args.name, args.pool, args.prefer, _load_devcap())
    if udid is None:
        print(message, file=sys.stderr)
        return 1
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
