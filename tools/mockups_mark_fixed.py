#!/usr/bin/env python3
"""Flip mockup review entries from fix to pass. Input lines: `mockup-id|rule substring|note`."""
import glob, re, sys

root = ".agents/design/mockups"
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    mid, rule, note = line.split("|", 2)
    paths = glob.glob(f"{root}/*/*/{mid}/{mid}.html") + glob.glob(f"{root}/*/{mid}/{mid}.html")
    if not paths:
        print("no mockup", mid); continue
    done = 0
    for p in paths:
        out = []
        for l in open(p).read().split("\n"):
            m = re.search(r"verdict: (['\"])fix\1, note: (['\"])(?:\\.|(?!\2).)*\2", l)
            if m and rule in l:
                q = m.group(2)
                text = note.replace("\\", "\\\\").replace(q, "\\" + q)
                l = l[:m.start()] + f"verdict: {m.group(1)}pass{m.group(1)}, note: {q}{text}{q}" + l[m.end():]
                done += 1
            out.append(l)
        open(p, "w").write("\n".join(out))
    if not done:
        print("no match", mid, rule)
