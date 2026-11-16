#!/usr/bin/env python3
"""Generate the generic ``surfaces.json`` from the research inventory (``build/research/parity-loop-surfaces.json``).

    build_surfaces.py SOURCE.json [--out surfaces.json]

Keeps structure only: ids, kinds, routes, deep links, reach steps, state tags and mask rules. Free text (required state,
notes, gaps) is dropped, and any value shaped like a Home Assistant entity id (``domain.object_id``) is refused, so the
committed file carries no house data. ``live_write_risk`` becomes ``writes_on_reach``: such a surface is reached by deep link
or skipped, never tapped. Source keys ``expo`` and ``native`` become ``reference`` and ``candidate``.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from parity_loop.common import CANDIDATE, REFERENCE, read_json, write_json  # noqa: E402

SCHEMA = "parity-loop-surfaces/1"
APP_KEYS = {"expo": REFERENCE, "native": CANDIDATE}
#: A value shaped like an entity id: ``light.kitchen_main``. Route names such as ``bootstrap.setup`` are not in the kept keys.
ENTITY_ID = re.compile(r"\b(?:light|switch|sensor|binary_sensor|climate|camera|lock|cover|fan|media_player|vacuum|weather|"
                       r"alarm_control_panel|input_boolean|input_select|input_number|input_text|todo|person|script|scene|"
                       r"automation|humidifier|water_heater|device_tracker)\.[a-z0-9_]+\b")
#: Mask rules: an AX label matching ``ax_match`` has its frame masked on both halves.
CLOCK_MASK = {"label": "clock", "ax_match": r"^\d{1,2}:\d{2}(\s?[AP]M)?$"}
RELATIVE_TIME_MASK = {"label": "relative-time", "ax_match": r"\b\d+\s?(s|sec|min|minutes?|h|hours?|d|days?)\s+ago\b|\bnow\b"}
TAG_MASKS = {
    "camera": {"label": "camera-feed", "ax_match": r"(?i)camera|stream|live view"},
    "weather": {"label": "weather", "ax_match": r"(?i)weather|forecast|°"},
}
#: ``Tab bar: Chores`` and ``Tile: Rooms`` name something to press; the part after the colon is its accessibility label.
PRESS_PREFIXES = ("Tab bar:", "Tile:", "Button:", "Row:", "Segment:")


def reach_step(text: str) -> Dict[str, str]:
    """One reach step: ``{"press": label}`` for a plain labelled control, else ``{"manual": text}`` (not automatable)."""
    for prefix in PRESS_PREFIXES:
        if text.startswith(prefix):
            label = text[len(prefix):].strip()
            return {"manual": text} if "<" in label else {"press": label}
    if re.fullmatch(r"[A-Za-z0-9&' +-]{1,28}", text) and "<" not in text:
        return {"press": text}
    return {"manual": text}


def masks_for(surface: Dict[str, Any]) -> List[Dict[str, str]]:
    masks: List[Dict[str, str]] = []
    if surface.get("capture_class") == "dynamic":
        masks += [CLOCK_MASK, RELATIVE_TIME_MASK]
    for tag in surface.get("state_tags") or []:
        rule = TAG_MASKS.get(tag.split(":")[0])
        if rule and rule not in masks:
            masks.append(rule)
    return masks


def convert(source: Dict[str, Any]) -> Dict[str, Any]:
    """The generic document for a research inventory."""
    rows: List[Dict[str, Any]] = []
    for s in source["surfaces"]:
        rows.append({
            "id": s["id"], "kind": s["kind"], "title": s["title"], "area": s["area"], "presence": s["presence"],
            "in_scope": bool(s["in_scope"]), "capture_class": s["capture_class"],
            "native_reachable": bool(s["native_reachable"]),
            "routes": {REFERENCE: s.get("expo_route"), CANDIDATE: s.get("native_route")},
            "deep_link": {APP_KEYS[k]: v for k, v in (s.get("deep_link") or {}).items()},
            "reach": {APP_KEYS[k]: [reach_step(t) for t in steps] for k, steps in (s.get("reach_steps") or {}).items()},
            "gallery_page": s.get("expo_gallery_page"), "state_tags": list(s.get("state_tags") or []),
            "masks": masks_for(s), "writes_on_reach": bool(s["live_write_risk"]),
        })
    document = {"schema": SCHEMA, "surfaces": rows}
    leaks = ENTITY_ID.findall(json.dumps(document))
    if leaks:
        raise ValueError(f"entity-id-shaped values in the output: {sorted(set(leaks))[:5]}")
    return document


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", type=Path)
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent / "surfaces.json")
    args = ap.parse_args(argv)
    try:
        write_json(args.out, convert(read_json(args.source)))
    except (OSError, KeyError, ValueError) as error:
        print(f"build_surfaces: {error}", file=sys.stderr)
        return 2
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
