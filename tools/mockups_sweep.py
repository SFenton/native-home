#!/usr/bin/env python3
"""Load every mockup in headless Edge or Chrome and report render failures.

    python3 tools/mockups_sweep.py [--port 8077] [--jobs 6] [--device KEY [--posture open|part]] [path-substring ...]

`--device` opens every page on that device (the hash `#d=KEY[&p=part]`), which renders the stage and the whole States gallery there; a page that does not
offer the device is skipped. Run it once per device key and per hinge posture (iphone, duo-folded, duo-unfolded-portrait, duo-unfolded-landscape with p=open
and p=part, ipad-portrait, ipad-landscape) to prove a layout renders everywhere.

Serves .agents/design/mockups, dumps each page's DOM after a virtual-time budget, and flags: the lint banner (`k-warnbox`), "render() threw",
a console error line, a missing `<h1>`/Mock root, or a browser crash. Exit 1 when anything is flagged. Needs a Chromium browser (Edge, Chrome or
Chromium; set BROWSER to override). Stdlib only.
"""
import concurrent.futures
import os
import subprocess
import sys
import threading
import functools
import http.server
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / ".agents/design/mockups"
CANDIDATES = [
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
]


def browser():
    path = os.environ.get("BROWSER") or next((c for c in CANDIDATES if Path(c).exists()), None)
    if not path:
        sys.exit("mockups_sweep: no Chromium browser found (set BROWSER)")
    return path


def check(binary, port, rel, device=None, posture=None):
    url = "http://localhost:%d/%s" % (port, rel)
    if device:
        url += "#d=%s&p=%s" % (device, posture or "open")
    try:
        run = subprocess.run(
            [binary, "--headless=new", "--disable-gpu", "--enable-logging=stderr", "--v=0", "--virtual-time-budget=5000", "--dump-dom", url],
            capture_output=True, text=True, timeout=90)
    except subprocess.TimeoutExpired:
        return rel, ["timeout"]
    dom, err, problems = run.stdout, run.stderr, []
    if device and ('value="%s"' % device) not in dom:
        return rel, []   # the page does not offer this device
    if "k-warnbox" in dom:
        problems.append("lint banner")
    if "render() threw" in dom:
        problems.append("render() threw")
    if "<h1" not in dom:
        problems.append("no page title rendered")
    for line in err.splitlines():
        if "CONSOLE" in line and ("ERROR" in line or "Uncaught" in line) and "Unchecked runtime.lastError" not in line:
            problems.append(line.split("CONSOLE", 1)[1][:160].strip())
    return rel, sorted(set(problems))


def main():
    args = sys.argv[1:]
    port = int(args[args.index("--port") + 1]) if "--port" in args else 8077
    jobs = int(args[args.index("--jobs") + 1]) if "--jobs" in args else 6
    device = args[args.index("--device") + 1] if "--device" in args else None
    posture = args[args.index("--posture") + 1] if "--posture" in args else None
    filters = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] not in ("--port", "--jobs", "--device", "--posture"))]
    pages = sorted(str(p.relative_to(ROOT)) for p in ROOT.rglob("*.html") if "_kit/" not in str(p) and "proposals/" not in str(p))
    if filters:
        pages = [p for p in pages if any(f in p for f in filters)]
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a, **k):
            pass

    handler = functools.partial(Quiet, directory=str(ROOT))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    binary, bad = browser(), 0
    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        first = list(pool.map(lambda p: check(binary, port, p, device, posture), pages))
    for rel, problems in first:
        if problems:  # a failure under parallel load is re-run alone before it counts
            rel, problems = check(binary, port, rel, device, posture)
        if problems:
            bad += 1
            print("FAIL", rel, "|", "; ".join(problems))
    print("swept %d pages, %d flagged" % (len(pages), bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
