#!/usr/bin/env python3
"""Samples the host while a simulator runs a scroll cost surface (`tools/uikit_perf.sh`).

Each tick writes one TSV line: wall time, the Mac GPU's Device / Renderer / Tiler utilisation (IOAccelerator
PerformanceStatistics: the simulator renders with the Mac's GPU, so this is the only GPU signal a simulator has), the
cumulative CPU seconds of that simulator's render server (`backboardd`, the process that composites the app's layer
tree) and of the app's process (by bundle executable name), and the app's resident memory.

    perf_sampler.py --udid UDID --executable FentonHome --out FILE [--interval 0.25]

Runs until killed (SIGTERM).
"""
from __future__ import annotations

import argparse
import re
import signal
import subprocess
import sys
import time

GPU_KEYS = ("Device Utilization %", "Renderer Utilization %", "Tiler Utilization %")


def gpu() -> list:
    out = subprocess.run(["ioreg", "-r", "-d", "1", "-w", "0", "-c", "IOAccelerator"], capture_output=True, text=True).stdout
    values = []
    for key in GPU_KEYS:
        match = re.search(r'"%s"=(\d+)' % re.escape(key), out)
        values.append(int(match.group(1)) if match else -1)
    return values


def processes() -> list:
    out = subprocess.run(["ps", "-axo", "pid=,ppid=,time=,rss=,command="], capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        parts = line.split(None, 4)
        if len(parts) == 5:
            rows.append((int(parts[0]), int(parts[1]), parts[2], int(parts[3]), parts[4]))
    return rows


def seconds(text: str) -> float:
    total = 0.0
    for part in text.split(":"):
        total = total * 60 + float(part)
    return total


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--interval", type=float, default=0.25)
    args = parser.parse_args()
    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    with open(args.out, "w") as handle:
        handle.write("t\tgpu_device\tgpu_renderer\tgpu_tiler\tbackboardd_cpu_s\tapp_cpu_s\tapp_rss_mb\n")
        while running:
            rows = processes()
            launchd = [pid for pid, _, _, _, cmd in rows if "launchd_sim" in cmd and args.udid in cmd]
            backboard = next((r for r in rows if r[1] in launchd and r[4].endswith("/backboardd")), None)
            suffix = "/%s.app/%s" % (args.executable, args.executable)
            app = next((r for r in rows if suffix in r[4] and args.udid in r[4]), None)
            g = gpu()
            handle.write("%.3f\t%d\t%d\t%d\t%s\t%s\t%s\n" % (
                time.time(), g[0], g[1], g[2],
                "%.2f" % seconds(backboard[2]) if backboard else "",
                "%.2f" % seconds(app[2]) if app else "",
                "%.1f" % (app[3] / 1024) if app else ""))
            handle.flush()
            time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    sys.exit(main())
