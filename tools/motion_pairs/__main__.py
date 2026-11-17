"""``python3 -m tools.motion_pairs inventory | analyze | record``: see ``README.md``."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import List, Optional

from . import analyze, inventory, pair, record
from .scenarios import NATIVE, REFERENCE, SCENARIOS


def _scenario(name: str):
    from . import calibration  # noqa: F401  (registers the scenarios)
    if name not in SCENARIOS:
        raise SystemExit(f"unknown scenario {name!r}; known: {', '.join(sorted(SCENARIOS))}")
    return SCENARIOS[name]


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="motion_pairs", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    inv = sub.add_parser("inventory", help="write transitions.json from the atlas, motion.md and the pattern records")
    inv.add_argument("--out", type=Path, default=Path(__file__).with_name("transitions.json"))
    an = sub.add_parser("analyze", help="pair recorded clips: rows, GIFs and strips")
    an.add_argument("--scenario", required=True)
    an.add_argument("--reference", nargs="+", type=Path, required=True)
    an.add_argument("--native", nargs="+", type=Path, required=True)
    an.add_argument("--out", type=Path, required=True)
    an.add_argument("--tolerances", type=Path)
    an.add_argument("--title", default="Motion pairs")
    an.add_argument("--fixture-polluted", nargs="*", default=[], help="events whose two sides drew different content (verdict fixture-polluted, never a pass)")
    an.add_argument("--fixture-note", default="", help="what differs between the two sides' content; required with --fixture-polluted")
    rec = sub.add_parser("record", help="record takes on both sides (inside a devcap hold for both simulators), then analyze")
    rec.add_argument("--scenario", required=True)
    rec.add_argument("--reference-udid", required=True)
    rec.add_argument("--native-udid", required=True)
    rec.add_argument("--reference-agent", help="bound agent-device command from device_open (default: a standalone session)")
    rec.add_argument("--native-agent")
    rec.add_argument("--publication", type=Path, required=True, help="native preview publication directory (fixtures)")
    rec.add_argument("--gallery-bootstrap", type=Path, help="a gallery bootstrap.json to stage on native for gallery-mode scenarios")
    rec.add_argument("--takes", type=int, default=5)
    rec.add_argument("--out", type=Path, required=True)
    rec.add_argument("--reduce-motion", action="store_true")
    rec.add_argument("--dry-run", action="store_true", help="resolve paths, selectors, tools and simulators; record nothing, touch no device")
    rec.add_argument("--load-limit", type=float, default=record.LOAD_LIMIT)
    rec.add_argument("--tolerances", type=Path)
    rec.add_argument("--title", default="Motion pairs")
    args = parser.parse_args(argv)

    if args.cmd == "inventory":
        data = inventory.write(args.out)
        print(json.dumps({"out": str(args.out), "count": data["count"], "byKind": data["byKind"]}))
        return 0
    if args.cmd == "analyze" and args.fixture_polluted and not args.fixture_note:
        raise SystemExit("--fixture-polluted needs --fixture-note: say what differs between the two sides' content")
    scenario = _scenario(args.scenario)
    tolerances = pair.Tolerances.load(args.tolerances)
    if args.cmd == "analyze":
        rows = analyze.analyze_pair(scenario, {REFERENCE: args.reference, NATIVE: args.native}, args.out, tolerances,
                                    fixture_polluted=args.fixture_polluted, fixture_note=args.fixture_note)
        analyze.write_index(args.out, rows, args.title)
        print(json.dumps([{"event": r["event"], "verdict": r["verdict"]} for r in rows]))
        return 0
    from tools.parity_loop import simguard
    from tools.parity_loop.capture import Agent
    if not args.dry_run:
        record.guard_simulators([args.reference_udid, args.native_udid], os.environ)
    state = args.out / "agent-state"
    ref_cmd = args.reference_agent or record.standalone_agent(args.reference_udid, "motion-ref", state / "ref")
    nat_cmd = args.native_agent or record.standalone_agent(args.native_udid, "motion-nat", state / "nat")
    if args.dry_run:
        import subprocess
        listing = subprocess.run(["xcrun", "simctl", "list", "devices"], capture_output=True, text=True).stdout
        plan = record.dry_run(scenario, args.publication, args.gallery_bootstrap, args.out,
                              {REFERENCE: args.reference_udid, NATIVE: args.native_udid}, {REFERENCE: ref_cmd, NATIVE: nat_cmd}, listing)
        print(json.dumps(plan, indent=1))
        return 1 if plan["problems"] else 0
    problems = record.validate_publication(args.publication) if scenario.native_mode == "preview" else []
    if problems:
        print(json.dumps({"error": "publication", "problems": problems}))
        return 2
    devices = {
        REFERENCE: record.Device(REFERENCE, args.reference_udid, Agent(ref_cmd)),
        NATIVE: record.Device(NATIVE, args.native_udid, Agent(nat_cmd), args.publication, args.gallery_bootstrap),
    }
    takes = record.record_pair(devices, scenario, args.out / "takes", args.takes, args.reduce_motion, args.load_limit)
    summary = {side: [{"ok": t.ok, "reason": t.reason, "load": t.load, "durationMs": t.duration_ms, "clip": str(t.clip) if t.clip else None}
                      for t in ts] for side, ts in takes.items()}
    (args.out / "takes.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    good = {side: [t.clip for t in ts if t.ok] for side, ts in takes.items()}
    if not all(good.values()):
        print(json.dumps({"error": "no usable takes on a side", "takes": summary}))
        return 3
    rows = analyze.analyze_pair(scenario, good, args.out, tolerances, meta={"takesRecorded": {s: len(v) for s, v in good.items()}})
    analyze.write_index(args.out, rows, args.title)
    print(json.dumps([{"event": r["event"], "verdict": r["verdict"]} for r in rows]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
