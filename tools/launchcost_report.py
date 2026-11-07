#!/usr/bin/env python3
"""Summarises the launch cost probe's lines and checks them against the budgets.

Reads `LAUNCHCOST<TAB>case<TAB>key=value ...` lines (tools/ios_launchperf.sh writes them; the app's `LaunchCostProbe` makes them)
and prints one row per case: main-thread turn cost (p95, worst, turns over 8 and 16 ms) and the signpost intervals.

Budgets (simulator, main-thread CPU per run-loop turn; hitch ratios from a simulator mean nothing, see
.agents/testing/apple/performance.md): p95 turn <= 8 ms in every case. The intro cases (nothing but the intro runs) also allow no
turn over 16 ms (design/motion.md section 10). The arrival and snapshot cases include Home's own first layout, which has a 150 to
270 ms turn of its own on the simulator (not the motion's: the snapshot case has no motion); it is reported as a miss, not excused.
Intervals: warm launch to the snapshot (SnapshotShown) <= 400 ms; the arrival (Arrival, tokens to the end of the motion) <= 1000 ms;
the intro (Intro) <= 1500 ms.

Usage: launchcost_report.py FILE.tsv [--no-budget]   (exit 1 when a budget is missed)
"""
import sys

P95 = 8.0
WORST = 16.0
# Cases that include Home's own first layout: held to this worst turn until Home's startup is fixed.
HOME_WORST = WORST  # .agents/design/motion.md section 10: no turn over 16 ms in any case
HOME_CASES = ("arrival", "snapshot")
INTERVAL_BUDGETS = {"SnapshotShown_ms": 400.0, "Arrival_ms": 1000.0, "Intro_ms": 1500.0}
COLUMNS = ["p95_ms", "worst_ms", "over8", "over16", "main_ms", "turns", "Launch_ms", "SnapshotShown_ms", "SignIn_ms", "Intro_ms", "Arrival_ms"]


def parse(path):
    rows = []
    for line in open(path):
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 3 or parts[0] != "LAUNCHCOST":
            continue
        values = {}
        for pair in parts[2].split():
            key, _, value = pair.partition("=")
            try:
                values[key] = float(value)
            except ValueError:
                pass
        rows.append((parts[1], values))
    return rows


def failures(case, values):
    problems = []
    if case.endswith("-build"):
        return problems  # the build of Home behind the sign-in layer is reported, not budgeted
    if values.get("p95_ms", 0) > P95:
        problems.append(f"{case}: p95 turn {values['p95_ms']:.2f} ms > {P95} ms")
    limit_worst = HOME_WORST if case in HOME_CASES else WORST
    if values.get("worst_ms", 0) > limit_worst:
        problems.append(f"{case}: a turn over {limit_worst:.0f} ms (worst {values.get('worst_ms', 0):.2f} ms)")
    for key, limit in INTERVAL_BUDGETS.items():
        if key in values and values[key] > limit:
            problems.append(f"{case}: {key[:-3]} {values[key]:.0f} ms > {limit:.0f} ms")
    return problems


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    rows = parse(argv[1])
    check = "--no-budget" not in argv
    if not rows:
        print("no LAUNCHCOST lines in", argv[1])
        return 1
    width = max(len(case) for case, _ in rows)
    print(f"{'case'.ljust(width)}  " + "  ".join(c.replace("_ms", "").rjust(9) for c in COLUMNS))
    problems = []
    for case, values in rows:
        cells = [(f"{values[c]:.1f}" if c in values else "-").rjust(9) for c in COLUMNS]
        print(f"{case.ljust(width)}  " + "  ".join(cells))
        problems += failures(case, values)
    if check:
        print()
        print("budgets: " + ("all met" if not problems else "MISSED"))
        for problem in problems:
            print("  " + problem)
    return 1 if problems and check else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
