#!/usr/bin/env python3
"""Tabulates an alternating A/B scroll cost run (`tools/ios_scrollcost.sh --ab`) as Markdown.

Usage: tools/scrollcost_ab.py LABEL [--dir apple/.build] [--variants base,fix]

Reads apple/.build/scrollcost-LABEL-VARIANT-rN.tsv for every round and prints, per surface and variant, the mean over the
rounds with the lowest and highest round in brackets: idle and scroll runs (changed, deliveries, full deliveries, transitions,
entities compared on the main thread, update_ms, main_ms, turns over 8 ms, worst turn), then the cold-launch and forced-reconnect
rows. A surface that fits one screen has no scroll row.
"""
import glob
import os
import re
import sys
from collections import OrderedDict


def parse(path):
    rows = []
    with open(path, errors="replace") as handle:
        for line in handle:
            if not line.startswith("SCROLLCOST\t"):
                continue
            _, surface, kind, summary = line.rstrip("\n").split("\t", 3)
            values = {k: float(v) for k, v in (p.split("=", 1) for p in summary.split() if "=" in p) if re.fullmatch(r"-?[\d.]+", v)}
            if values and ("minstr" in values or kind in ("launch", "reconnect")):
                rows.append((surface, kind, values))
    return rows


def cell(runs, key, fmt="{:.0f}"):
    vals = [r.get(key, 0.0) for r in runs]
    if not vals:
        return "-"
    mean = sum(vals) / len(vals)
    if len(vals) == 1:
        return fmt.format(mean)
    return f"{fmt.format(mean)} [{fmt.format(min(vals))}-{fmt.format(max(vals))}]"


def main(argv):
    label = argv[0]
    directory = "apple/.build"
    variants = ["base", "fix"]
    if "--dir" in argv:
        directory = argv[argv.index("--dir") + 1]
    if "--variants" in argv:
        variants = argv[argv.index("--variants") + 1].split(",")
    data = OrderedDict()  # surface -> kind -> variant -> [values]
    for variant in variants:
        for path in sorted(glob.glob(os.path.join(directory, f"scrollcost-{label}-{variant}-r*.tsv"))):
            for surface, kind, values in parse(path):
                data.setdefault(surface, {}).setdefault(kind, {}).setdefault(variant, []).append(values)

    if "--compact" in argv:
        # One row per surface and variant for the scrolling runs: what the large-title experiments compare.
        print("\n### Scrolling 8 s, large-title view (mean over runs, [min-max])\n")
        print("| surface | variant | runs | main_ms | over8 | over16 | worst ms | p95 ms | inset_changes | inset_kvo |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for surface, kinds in data.items():
            for variant in variants:
                runs = kinds.get("scroll", {}).get(variant)
                if runs:
                    print(f"| {surface} | {variant} | {len(runs)} | {cell(runs, 'main_ms')} | {cell(runs, 'over8')} | {cell(runs, 'over16')} | "
                          f"{cell(runs, 'worst_ms', '{:.1f}')} | {cell(runs, 'p95_ms', '{:.1f}')} | {cell(runs, 'inset_changes')} | {cell(runs, 'inset_kvo')} |")
        return

    for kind, title in (("idle", "Standing still 8 s"), ("scroll", "Scrolling 8 s")):
        print(f"\n### {title} (mean over rounds, [min-max])\n")
        print("| surface | variant | changed | deliveries | full | transitions | compared on main | boxes changed | update_ms | delivery_ms | main_ms | over4 | over8 | over16 | worst ms | p95 ms |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for surface, kinds in data.items():
            for variant in variants:
                runs = kinds.get(kind, {}).get(variant)
                if not runs:
                    continue
                print(f"| {surface} | {variant} | {cell(runs, 'changed')} | {cell(runs, 'deliveries')} | {cell(runs, 'full')} | {cell(runs, 'transitions')} | "
                      f"{cell(runs, 'compared')} | {cell(runs, 'boxes')} | {cell(runs, 'update_ms', '{:.1f}')} | {cell(runs, 'delivery_ms', '{:.1f}')} | "
                      f"{cell(runs, 'main_ms')} | {cell(runs, 'over4')} | {cell(runs, 'over8')} | {cell(runs, 'over16')} | "
                      f"{cell(runs, 'worst_ms', '{:.1f}')} | {cell(runs, 'p95_ms', '{:.1f}')} |")

    for kind, title in (("launch", "Cold launch to the page settling (counters since process start)"),
                        ("reconnect", "Forced reconnect (network blip 1 s into an 8 s idle window)")):
        print(f"\n### {title}\n")
        print("| surface | variant | open cpu_ms | open instr_m | first live ms | deliveries | received | full | subscribes | full sets | transitions | compared | boxes | delivery_ms | main_ms | over8 | worst ms |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for surface, kinds in data.items():
            for variant in variants:
                runs = kinds.get(kind, {}).get(variant)
                if not runs:
                    continue
                print(f"| {surface} | {variant} | {cell(runs, 'cpu_ms')} | {cell(runs, 'instr_m')} | {cell(runs, 'firstlive_ms')} | {cell(runs, 'deliveries')} | {cell(runs, 'received')} | {cell(runs, 'full')} | "
                      f"{cell(runs, 'subscribes')} | {cell(runs, 'fullsets')} | {cell(runs, 'transitions')} | {cell(runs, 'compared')} | {cell(runs, 'boxes')} | "
                      f"{cell(runs, 'delivery_ms', '{:.1f}')} | {cell(runs, 'main_ms')} | {cell(runs, 'over8')} | {cell(runs, 'worst_ms', '{:.1f}')} |")


if __name__ == "__main__":
    main(sys.argv[1:])
