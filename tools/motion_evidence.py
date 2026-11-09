#!/usr/bin/env python3
"""Contact sheets of the moves a motion journey marked (SinglePageMotionJourneyTests.testRecordSinglePageMotion).

    tools/motion_evidence.py --dir DIR --marks MARKS_FILE --out OUT_DIR [--family iphone] [--fps 20] [--pad 0.6] [--lag 0.8]

DIR holds <family>.mov and <family>.start from `FENTON_UITEST_RECORD_DIR=DIR tools/ios_uitest.sh ...`. MARKS_FILE has lines
`<move>.start <unix seconds>` and `<move>.end <unix seconds>`. Each move becomes OUT_DIR/<family>-<move>.png: the frames from
`start - pad` to `start + span + pad` of the recording, shifted by `lag` (the recorder starts a little after its start time is written).
"""
import argparse
import subprocess
import sys
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--marks", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--family", default="iphone")
    ap.add_argument("--fps", type=float, default=20)
    ap.add_argument("--pad", type=float, default=0.6)
    ap.add_argument("--lag", type=float, default=0.8)
    ap.add_argument("--span", type=float, default=2.0, help="seconds after the start mark (the move happens right after it; the end mark can come much later because a tap waits for idle)")
    ap.add_argument("--anchor", choices=["start", "end"], default="start", help="end: the window is the span before the end mark (moves that scroll or search before they tap)")
    ap.add_argument("--columns", type=int, default=7)
    ap.add_argument("--width", type=int, default=170)
    a = ap.parse_args()
    d = Path(a.dir)
    mov = d / f"{a.family}.mov"
    began = float((d / f"{a.family}.start").read_text().strip())
    marks: dict[str, float] = {}
    for line in Path(a.marks).read_text().splitlines():
        name, _, value = line.rpartition(" ")
        marks[name] = float(value)
    Path(a.out).mkdir(parents=True, exist_ok=True)
    status = 0
    for key in sorted(marks):
        if not key.endswith(".start"):
            continue
        move = key[: -len(".start")]
        end = marks.get(f"{move}.end")
        if end is None:
            continue
        if a.anchor == "end":
            t0 = end - a.span - began - a.lag
            t1 = end - began - a.lag + a.pad
        else:
            t0 = marks[key] - began - a.lag - a.pad
            t1 = min(end, marks[key] + a.span) - began - a.lag + a.pad
        out = Path(a.out) / f"{a.family}-{move}.png"
        r = subprocess.run(["xcrun", "swift", str(Path(__file__).with_name("video_frames.swift")), str(mov), str(out),
                            f"{max(t0, 0):.3f}", f"{t1:.3f}", str(a.fps), str(a.columns), str(a.width)],
                           capture_output=True, text=True)
        print(move, r.stdout.strip() or r.stderr.strip())
        status |= r.returncode
    return status


if __name__ == "__main__":
    sys.exit(main())
