#!/usr/bin/env python3
"""The coverage table: every atlas surface against what ``surfaces.json`` captures, one row per surface and device family.

    states.py [--catalog FILE] [--surfaces-file FILE] [--json OUT.json] [--markdown OUT.md]

The atlas (``.agents/design/mockups/catalog.json``) lists pages, modals (sheets and alerts are modals), flows, components and
proposals. ``surfaces.json`` is what :mod:`parity_loop.run` captures. This module joins them by id and writes:

* a row per surface and family (iPhone, Duo, iPad; the atlas item's own ``devices`` decide which families exist),
* the **source of each side**: the candidate is always the native app; the reference is the Expo app where ``surfaces.json`` has a
  row present in Expo, and the Studio sim where Expo has none (components, native-only surfaces, proposals are left out),
* **how to reach** the surface on each side (gallery page, deep link or press path; for an uncovered surface, the surfaces that
  present it),
* the state hints the atlas lists and which of them :mod:`parity_loop.faults` can stage.

Python 3 standard library only; reads two JSON files and runs nothing on a device.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from parity_loop.common import REPO, read_json, write_json  # noqa: E402

CATALOG_FILE = REPO / ".agents" / "design" / "mockups" / "catalog.json"
SURFACES_FILE = Path(__file__).resolve().parent / "surfaces.json"
#: The atlas kinds that count as surfaces. Proposals are designs not yet shipped: they have no native surface to capture.
KINDS = ("page", "modal", "flow", "component")
#: The device families the harness captures (``run.DEVICES``); the atlas names them the same way. ``watch`` is not captured here.
FAMILIES = ("iphone", "duo", "ipad")
#: Keyword classes in an atlas ``statesHint`` string, matched case-insensitively. A hint may fall in several classes.
STATE_CLASSES = {
    "offline": ("offline", "reconnecting"),
    "unavailable": ("unavailable",),
    "error": ("error", "fail", "refused", "denied"),
    "loading": ("loading", "pending", "placeholder"),
    "empty": ("empty", "no items", "none yet"),
}
COVERED, MISSING, SKIPPED = "covered", "missing", "skipped"


# MARK: - Join

def state_classes(hints: Sequence[str]) -> List[str]:
    """The error and edge classes (:data:`STATE_CLASSES`) the hint strings mention, sorted."""
    text = " | ".join(hints).lower()
    return sorted(name for name, words in STATE_CLASSES.items() if any(word in text for word in words))


def reach_text(surface: Optional[Mapping[str, Any]], item: Mapping[str, Any]) -> Dict[str, str]:
    """How to reach the surface on each side, as short text."""
    if surface is None:
        presented = ", ".join(item.get("presentedFrom") or []) or "none listed"
        return {"reference": f"Studio sim story for {item.get('mockup') or item['id']}",
                "candidate": f"native preview; atlas presentedFrom: {presented}"}
    out: Dict[str, str] = {}
    for side in ("reference", "candidate"):
        steps = (surface.get("reach") or {}).get(side) or []
        parts = []
        if side == "reference" and surface.get("gallery_page"):
            parts.append(f"gallery page {surface['gallery_page']}")
        if steps:
            parts.append("press " + " > ".join(str(s.get("press") or s) for s in steps))
        if (surface.get("deep_link") or {}).get(side):
            parts.append("deep link")
        out[side] = "; ".join(parts) or "route only"
    return out


def classify(surface: Optional[Mapping[str, Any]]) -> Dict[str, str]:
    """``status`` and ``reference_source`` for one atlas item, given its ``surfaces.json`` row (``None`` when it has none)."""
    if surface is None:
        return {"status": MISSING, "reference_source": "studio", "why": "no surfaces.json row"}
    if not surface.get("in_scope"):
        return {"status": SKIPPED, "reference_source": "expo", "why": "out of scope"}
    presence = surface.get("presence")
    if presence == "both":
        return {"status": COVERED, "reference_source": "expo", "why": ""}
    if presence == "native-only":
        return {"status": MISSING, "reference_source": "studio", "why": "native only: Expo has none, Studio side not wired"}
    return {"status": SKIPPED, "reference_source": "expo", "why": f"presence {presence}"}


def build(catalog: Mapping[str, Any], surfaces: Mapping[str, Any]) -> Dict[str, Any]:
    """The coverage document: ``rows`` (surface x family) and ``counts``."""
    by_id = {row["id"]: row for row in surfaces["surfaces"]}
    items = [i for i in catalog["items"] if i["kind"] in KINDS]
    rows: List[Dict[str, Any]] = []
    for item in items:
        surface = by_id.get(item["id"])
        verdict = classify(surface)
        hints = list(item.get("statesHint") or [])
        reach = reach_text(surface, item)
        for family in FAMILIES:
            if family not in (item.get("devices") or []):
                continue
            rows.append({
                "id": item["id"], "kind": item["kind"], "area": item.get("area", ""), "family": family,
                "status": verdict["status"], "why": verdict["why"], "reference_source": verdict["reference_source"],
                "candidate_source": "native", "reach_reference": reach["reference"], "reach_candidate": reach["candidate"],
                "writes_on_reach": bool(surface and surface.get("writes_on_reach")),
                "states_hinted": len(hints), "state_classes": state_classes(hints),
            })
    return {"schema": "parity-states-coverage/1", "rows": rows, "counts": count(rows),
            "unmatched_surfaces": sorted(set(by_id) - {i["id"] for i in catalog["items"]})}


def count(rows: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    """Surfaces x families covered and missing, in total, per kind and per family."""
    def tally(key: Optional[str]) -> Dict[str, Dict[str, int]]:
        table: Dict[str, Counter] = {}
        for row in rows:
            table.setdefault(row[key] if key else "all", Counter())[row["status"]] += 1
        return {name: {s: c.get(s, 0) for s in (COVERED, MISSING, SKIPPED)} | {"total": sum(c.values())} for name, c in sorted(table.items())}
    return {"total": tally(None)["all"] if rows else {COVERED: 0, MISSING: 0, SKIPPED: 0, "total": 0},
            "by_kind": tally("kind"), "by_family": tally("family")}


# MARK: - Report

def markdown(document: Mapping[str, Any], only: Optional[str] = None) -> str:
    """A Markdown rendering: the counts, then (with ``only`` set to a status) the rows of that status."""
    counts = document["counts"]
    lines = ["| Group | Covered | Missing | Skipped | Rows |", "|---|---|---|---|---|"]
    lines.append("| all | {covered} | {missing} | {skipped} | {total} |".format(**counts["total"]))
    for title, key in (("kind", "by_kind"), ("family", "by_family")):
        for name, c in counts[key].items():
            lines.append(f"| {title} {name} | {c[COVERED]} | {c[MISSING]} | {c[SKIPPED]} | {c['total']} |")
    if only:
        lines += ["", f"| Surface | Kind | Family | Reference | Reach (reference) | Reach (candidate) |", "|---|---|---|---|---|---|"]
        for row in document["rows"]:
            if row["status"] == only:
                lines.append(f"| {row['id']} | {row['kind']} | {row['family']} | {row['reference_source']} | "
                             f"{row['reach_reference']} | {row['reach_candidate']} |")
    return "\n".join(lines) + "\n"


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", type=Path, default=CATALOG_FILE)
    ap.add_argument("--surfaces-file", type=Path, default=SURFACES_FILE)
    ap.add_argument("--json", type=Path, help="write the full document here")
    ap.add_argument("--markdown", type=Path, help="write the counts table here")
    ap.add_argument("--rows", choices=(COVERED, MISSING, SKIPPED), help="also list the rows of this status in the Markdown")
    args = ap.parse_args(argv)
    try:
        document = build(read_json(args.catalog), read_json(args.surfaces_file))
    except (OSError, KeyError, ValueError) as error:
        print(f"states: {error}", file=sys.stderr)
        return 2
    text = markdown(document, args.rows)
    if args.json:
        write_json(args.json, document)
    if args.markdown:
        Path(args.markdown).parent.mkdir(parents=True, exist_ok=True)
        Path(args.markdown).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
