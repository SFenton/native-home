#!/usr/bin/env python3
"""Tabulates the scroll cost TSV that ScrollSurfacesPerformanceTests writes.

Usage: tools/scrollcost_report.py RESULT.tsv [RESULT.tsv ...] [--compare BASE.tsv ...] [--sort net|main|worst]

A row is `SCROLLCOST<TAB>surface<TAB>idle|scroll<TAB>key=value ...` (the probe's summary, see ScrollCostProbe). Per
surface the report gives, for one scroll minus the idle floor of the same length:
  net Minstr   CPU instructions retired (millions) by the scroll beyond the idle run
  main ms      main-thread CPU time beyond idle
  p95 / worst  95th percentile and longest main-thread run-loop turn while scrolling (ms of CPU)
  >8ms         turns that computed longer than 8 ms (a dropped frame at 120 Hz)
  idle chg / chg  entities the live connection handed the main thread while standing still / scrolling
  full         deliveries that carried more than half the house; trans: socket state transitions; cmp: entities the
               main thread compared; boxes: boxes that really changed; deliv ms: main-thread CPU inside the deliveries
A `launch` row (counters from process start to the page settling) and a `reconnect` row (a network blip in an idle
window) are listed after the table when the run carried them.
With --compare the table adds the base's net Minstr and the change.
"""
import sys
from collections import OrderedDict


def parse(paths):
    runs = OrderedDict()
    for path in paths:
        with open(path, errors="replace") as handle:
            for line in handle:
                if not line.startswith("SCROLLCOST\t"):
                    continue
                _, surface, kind, summary = line.rstrip("\n").split("\t", 3)
                values = {}
                for pair in summary.split():
                    if "=" in pair:
                        key, value = pair.split("=", 1)
                        try:
                            values[key] = float(value)
                        except ValueError:
                            pass
                entry = runs.setdefault(surface, {"idle": [], "scroll": [], "launch": [], "reconnect": [], "fits": False})
                if kind in ("launch", "reconnect"):
                    entry[kind].append(values)
                    continue
                if "minstr" not in values:
                    entry["fits"] = entry["fits"] or summary.startswith("no scroll view")
                    continue
                entry[kind].append(values)
    return runs


def mean(runs, key):
    return sum(run.get(key, 0.0) for run in runs) / len(runs) if runs else 0.0


def summarize(runs):
    table = OrderedDict()
    for surface, kinds in runs.items():
        idle, scroll = kinds["idle"], kinds["scroll"]
        if not scroll:
            continue
        table[surface] = {
            "idle": mean(idle, "minstr"),
            "scroll": mean(scroll, "minstr"),
            "net": mean(scroll, "minstr") - mean(idle, "minstr"),
            "main": mean(scroll, "main_ms") - mean(idle, "main_ms"),
            "p95": mean(scroll, "p95_ms"),
            "worst": max((run.get("worst_ms", 0.0) for run in scroll), default=0.0),
            "over8": mean(scroll, "over8"),
            "over4": mean(scroll, "over4"),
            "changed": mean(scroll, "changed"),
            "idle_changed": mean(idle, "changed"),
            "full": mean(scroll, "full") + mean(idle, "full"),
            "trans": mean(scroll, "transitions") + mean(idle, "transitions"),
            "compared": mean(scroll, "compared") + mean(idle, "compared"),
            "boxes": mean(scroll, "boxes") + mean(idle, "boxes"),
            "deliveries": mean(scroll, "deliveries") + mean(idle, "deliveries"),
            "delivery_ms": mean(scroll, "delivery_ms") + mean(idle, "delivery_ms"),
            "update_ms": mean(scroll, "update_ms"),
            "travelled": mean(scroll, "travelled"),
        }
    return table


def main(argv):
    paths, base_paths, sort = [], [], "net"
    target = paths
    iterator = iter(argv)
    for arg in iterator:
        if arg == "--compare":
            target = base_paths
        elif arg == "--sort":
            sort = next(iterator)
        else:
            target.append(arg)
    runs = parse(paths)
    table = summarize(runs)
    base = summarize(parse(base_paths)) if base_paths else {}
    header = ["surface", "idle Minstr", "scroll Minstr", "net Minstr", "per 1000pt", "main ms", "p95 ms", "worst ms", ">4ms", ">8ms", "live upd", "upd ms",
              "idle chg", "full", "trans", "cmp", "boxes", "deliv ms"]
    if base:
        header += ["base net", "change", "base main ms", "base p95", "base worst", "base >8ms", "base upd ms"]
    print("\t".join(header))
    key = {"net": "net", "main": "main", "worst": "worst"}.get(sort, "net")
    for surface, row in sorted(table.items(), key=lambda item: -item[1][key]):
        per = row["net"] / (row["travelled"] / 1000) if row["travelled"] else 0
        cells = [surface, f"{row['idle']:.0f}", f"{row['scroll']:.0f}", f"{row['net']:.0f}", f"{per:.0f}", f"{row['main']:.0f}",
                 f"{row['p95']:.2f}", f"{row['worst']:.1f}", f"{row['over4']:.0f}", f"{row['over8']:.0f}",
                 f"{row['changed']:.0f}", f"{row['update_ms']:.1f}", f"{row['idle_changed']:.0f}", f"{row['full']:.0f}", f"{row['trans']:.0f}",
                 f"{row['compared']:.0f}", f"{row['boxes']:.0f}", f"{row['delivery_ms']:.1f}"]
        if base:
            old = base.get(surface)
            cells += [f"{old['net']:.0f}" if old else "-", f"{(row['net'] / old['net'] - 1) * 100:+.0f}%" if old and old["net"] > 0 else "-"]
            cells += [f"{old['main']:.0f}", f"{old['p95']:.2f}", f"{old['worst']:.1f}", f"{old['over8']:.0f}", f"{old['update_ms']:.1f}"] if old else ["-"] * 5
        print("\t".join(cells))
    print_events(runs)


def print_events(runs):
    """The cold launch and forced reconnect rows, when a run carried them."""
    keys = ["up_s", "firstlive_ms", "deliveries", "received", "full", "fullsets", "subscribes", "transitions", "compared", "boxes", "delivery_ms",
            "main_ms", "over8", "worst_ms"]
    rows = [(surface, kind, entry[kind]) for surface, entry in runs.items() for kind in ("launch", "reconnect") if entry.get(kind)]
    if not rows:
        return
    print()
    print("\t".join(["surface", "event"] + keys))
    for surface, kind, found in rows:
        print("\t".join([surface, kind] + [f"{mean(found, key):.1f}" for key in keys]))


if __name__ == "__main__":
    main(sys.argv[1:])
