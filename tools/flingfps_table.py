#!/usr/bin/env python3
"""Turns the FLINGFPS-STATS lines in tools/ios_flingfps.sh's summary into one table per page and variant.

Usage: flingfps_table.py SUMMARY.txt. Variant labels come from the `-- test [variant.rN]` headers."""
import re, sys

def main():
    rows, header = [], None
    for line in open(sys.argv[1], errors="replace"):
        m = re.match(r"-- (\w+) \[(.+?)\.r(\d+)\]", line)
        if m:
            header = (m.group(2), int(m.group(3)))
        s = re.search(r"FLINGFPS-STATS (.*)", line)
        if s and header and "page=" in s.group(1):
            kv = dict(p.split("=", 1) for p in s.group(1).split() if "=" in p)
            rows.append((kv.get("page", "?"), header[0], header[1], kv))
    if not rows:
        print("no FLINGFPS-STATS lines"); return
    cols = ["frames", "meanFps", "p5Fps", "p50ms", "p95ms", "p99ms", "worstMs", "pct95fps", "pctUnder70fps", "hitches", "hitchMs", "lowPower", "thermal"]
    print("page | variant | run | " + " | ".join(cols))
    for page, variant, run, kv in sorted(rows):
        print(f"{page} | {variant} | {run} | " + " | ".join(kv.get(c, "") for c in cols))
main()
