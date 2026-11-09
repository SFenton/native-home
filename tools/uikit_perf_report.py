#!/usr/bin/env python3
"""Summarises a `tools/uikit_perf.sh` run directory into Markdown tables (SwiftUI app against the UIKit port).

    uikit_perf_report.py build/perf/<label> [--csv FILE]

For every surface, app and kind (idle: 8 s standing still; scroll: two 8 s sweeps at 900 pt/s per round) it reports the
median over rounds of the in-app numbers (`FramePacer`, `MainThreadCostMeter`) and of the host numbers matched to each
run's wall-clock window (`perf_sampler.py`): Mac GPU utilisation and the simulator render server's CPU time.
"""
from __future__ import annotations

import argparse
import csv
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

FILE = re.compile(r"r(\d+)-(swiftui|uikit)-(.+)\.tsv$")


def samples(path: Path):
    rows = []
    if not path.exists():
        return rows
    with open(path) as handle:
        next(handle, None)
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 7:
                continue
            def num(text):
                return float(text) if text not in ("", "-1") else None
            rows.append(dict(t=float(parts[0]), gpu=num(parts[1]), renderer=num(parts[2]), bb=num(parts[4]), app=num(parts[5]), rss=num(parts[6])))
    return rows


def at(rows, key, t):
    """Linear interpolation of a cumulative counter at time t."""
    points = [(r["t"], r[key]) for r in rows if r[key] is not None]
    if not points:
        return None
    if t <= points[0][0]:
        return points[0][1]
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if t0 <= t <= t1:
            return v0 + (v1 - v0) * (t - t0) / max(t1 - t0, 1e-6)
    return points[-1][1]


def window(rows, key, t0, t1):
    values = [r[key] for r in rows if r[key] is not None and t0 <= r["t"] <= t1]
    return statistics.mean(values) if values else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--csv", type=Path)
    args = parser.parse_args()
    runs = defaultdict(list)  # (surface, kind, app) -> [metrics]
    order = []
    for path in sorted(args.directory.glob("r*-*.tsv")):
        if path.name.endswith(".samples.tsv"):
            continue
        match = FILE.match(path.name)
        if not match:
            continue
        app = match.group(2)
        host = samples(path.with_name(path.name[:-4] + ".samples.tsv"))
        for line in path.read_text().splitlines():
            parts = line.split("\t")
            if len(parts) < 4 or parts[0] != "SCROLLCOST":
                continue
            name, kind, summary = parts[1], parts[2], parts[3]
            if name not in order:
                order.append(name)
            values = dict(kv.split("=", 1) for kv in summary.split() if "=" in kv)
            if "t0" not in values:
                runs[(name, kind, app)].append({"error": summary[:80]})
                continue
            t0, t1 = float(values["t0"]), float(values["t1"])
            metrics = {k: float(v) for k, v in values.items() if re.fullmatch(r"-?[\d.]+", v)}
            bb0, bb1 = at(host, "bb", t0), at(host, "bb", t1)
            metrics["render_ms"] = (bb1 - bb0) * 1000 if bb0 is not None and bb1 is not None else float("nan")
            gpu = window(host, "gpu", t0, t1)
            metrics["gpu_pct"] = gpu if gpu is not None else float("nan")
            renderer = window(host, "renderer", t0, t1)
            metrics["gpu_renderer_pct"] = renderer if renderer is not None else float("nan")
            runs[(name, kind, app)].append(metrics)

    columns = [
        ("fps", "fps", "%.1f"), ("dropped", "dropped frames", "%.0f"), ("hitch_ms_per_s", "hitch ms/s", "%.1f"),
        ("p95_ms", "main p95 ms", "%.2f"), ("over8", "turns >8 ms", "%.0f"), ("main_ms", "main CPU ms", "%.0f"),
        ("cpu_ms", "process CPU ms", "%.0f"), ("render_ms", "render server CPU ms", "%.0f"),
        ("gpu_pct", "Mac GPU %", "%.0f"), ("mem_mb", "memory MB", "%.1f"), ("peak_mb", "peak MB", "%.1f"),
    ]
    rows_out = []
    print("| Surface | Kind | App | n | " + " | ".join(c[1] for c in columns) + " |")
    print("|" + "---|" * (4 + len(columns)))
    for name in order:
        for kind in ("idle", "scroll"):
            for app in ("swiftui", "uikit"):
                data = [m for m in runs.get((name, kind, app), []) if "error" not in m]
                errors = [m for m in runs.get((name, kind, app), []) if "error" in m]
                if not data:
                    if errors:
                        print(f"| {name} | {kind} | {app} | 0 | " + errors[0]["error"].replace("|", "/") + " |")
                    continue
                cells = []
                row = {"surface": name, "kind": kind, "app": app, "n": len(data)}
                for key, _, fmt in columns:
                    values = [m[key] for m in data if key in m and m[key] == m[key]]
                    value = statistics.median(values) if values else None
                    row[key] = value
                    cells.append(fmt % value if value is not None else "–")
                rows_out.append(row)
                label = "SwiftUI" if app == "swiftui" else "UIKit"
                print(f"| {name} | {kind} | {label} | {len(data)} | " + " | ".join(cells) + " |")
    if args.csv:
        with open(args.csv, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=["surface", "kind", "app", "n"] + [c[0] for c in columns])
            writer.writeheader()
            writer.writerows(rows_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
