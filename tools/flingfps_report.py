#!/usr/bin/env python3
"""Summarises xctrace exports of displayed-surfaces-per-second and hitches (see tools/ios_flingfps.sh).

Usage: flingfps_report.py SURFACES.xml HITCHES.xml. The fling window is the buckets with at least ACTIVE surface swaps
(a still screen swaps a handful per second)."""
import sys, statistics as st
import xml.etree.ElementTree as ET

ACTIVE = 30

def rows(path):
    try:
        root = ET.parse(path).getroot()
    except Exception as e:
        print(f"   cannot parse {path}: {e}"); return []
    cols = [c.findtext("mnemonic") for c in root.iter("col")]
    refs, out = {}, []
    for row in root.iter("row"):
        vals = []
        for el in row:
            if "id" in el.attrib: refs[el.attrib["id"]] = el
            if "ref" in el.attrib and el.attrib["ref"] in refs: el = refs[el.attrib["ref"]]
            vals.append(el.attrib.get("fmt") or (el.text or ""))
        out.append(dict(zip(cols, vals)))
    return out

def ms(s):
    n, unit = s.split()[:2]
    return float(n) * {"ms": 1, "s": 1000, "us": 0.001, "µs": 0.001}.get(unit, 1)

def pct(xs, p):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(p * len(xs)))]

def main():
    surf = rows(sys.argv[1])
    counts = [(r["start"], int(r["count"])) for r in surf if r.get("duration", "").startswith("1.00 s")]
    active = [c for _, c in counts if c >= ACTIVE]
    print("   per-second surfaces:", " ".join(str(c) for _, c in counts))
    if active:
        print(f"   fling window ({len(active)} s with >= {ACTIVE}): mean {st.mean(active):.1f}  p10 {pct(active, .1)}  max {max(active)}")
    else:
        print("   no active seconds")
    hit = [r for r in rows(sys.argv[2]) if r.get("process")]  # the app's rows; system rows duplicate them
    durs = [ms(r["duration"]) for r in hit]
    print(f"   hitches (app): {len(hit)}", "durations ms: " + ", ".join(f"{d:.2f}" for d in sorted(durs)) if durs else "")
    near = [d for d in durs if 7 <= d <= 9 or 11.5 <= d <= 13.5]
    print(f"   of which ~8.3 ms or ~12.5 ms: {len(near)}")
main()
