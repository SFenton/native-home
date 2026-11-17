"""The transitions inventory: every movement the mockup atlas and ``motion.md`` name, with a trigger path on each side.

    python3 -m tools.motion_pairs inventory [--out tools/motion_pairs/transitions.json]

Sources, all read from this checkout: ``.agents/design/mockups/catalog.json`` (pages, modals, flows, components and their
``presentation`` and ``motionHint`` strings), ``.agents/design/motion.md`` (the per-surface decision table in section 3 and the
token table in section 7), ``.agents/patterns/*.md`` (which pattern records exist), and ``tools/parity_loop/surfaces.json``
(the press paths that reach each surface on the reference and on native). Proposals (``kind: proposal``) have no reference
and are left out; their count is recorded.

Each transition has a ``kind``, an ``expect`` (the atlas or policy text and the tokens and durations found in it) and a
``trigger`` per side: ``steps`` are the press labels of the surface's reach path (the presenter's page, then the control),
``status`` is ``mapped`` when ``surfaces.json`` has a path, ``unmapped`` when it has none, ``calibrated`` when a scenario in
``scenarios.py`` records it.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional

REPO = Path(__file__).resolve().parent.parent.parent
CATALOG = REPO / ".agents" / "design" / "mockups" / "catalog.json"
MOTION_MD = REPO / ".agents" / "design" / "motion.md"
PATTERNS = REPO / ".agents" / "patterns"
SURFACES = REPO / "tools" / "parity_loop" / "surfaces.json"
TOKENS = ("quick", "state", "standard", "emphasized", "segment", "contentFade", "arrivalStagger")
TAB_LABELS = frozenset({"Home", "Rooms", "Settings", "Security", "Climate", "Chores", "Media", "Vacuums", "Food & Recipes", "To-Do"})
#: Transitions a scenario records, by transition id: ``(scenario, event)``. Filled by ``scenarios.py`` consumers.
CALIBRATED = {
    "resident-chores:push": ("chores-calib", "push"),
    "donetick-task-sheet:sheet": ("chores-calib", "sheet"),
}


def expectation(text: str) -> Dict[str, Any]:
    """The motion tokens and durations (seconds) a hint or policy cell mentions."""
    tokens = [t for t in TOKENS if re.search(r"(?<![\w-])`?%s`?(?![\w-])" % t, text)]
    seconds = [float(m) for m in re.findall(r"(\d+(?:\.\d+)?)\s?s\b", text)]
    return {"text": text, "tokens": tokens, "seconds": seconds, "cut": bool(re.search(r"\bcut\b", text, re.I))}


def presentation_kind(presentation: Optional[str]) -> str:
    p = (presentation or "").lower()
    if p.startswith("push inside sheet"):
        return "push-in-sheet"
    if p.startswith("sheet"):
        return "sheet"
    if p.startswith("alert"):
        return "alert"
    if p.startswith("confirmationdialog"):
        return "dialog"
    if p.startswith("fullscreencover"):
        return "full-screen-cover"
    return "sheet"


def _steps(surface: Optional[Mapping[str, Any]], side: str) -> Optional[List[str]]:
    if not surface:
        return None
    raw = (surface.get("reach") or {}).get(side) or []
    out: List[str] = []
    for step in raw:
        if "press" in step:
            out.append(str(step["press"]))
        elif "manual" in step:
            out.append("manual: " + str(step["manual"]))
        elif "deep_link" in step:
            out.append("link: " + str(step["deep_link"]))
    return out


def trigger(item: Mapping[str, Any], surface: Optional[Mapping[str, Any]]) -> Dict[str, Any]:
    """Where each side starts and what it presses; ``status`` says whether ``surfaces.json`` knows the path."""
    ref, nat = _steps(surface, "reference"), _steps(surface, "candidate")
    routes = (surface or {}).get("routes") or {}
    return {
        "from": list(item.get("presentedFrom") or []),
        "reference": {"launch": "--gallery-fixture", "route": routes.get("reference"), "steps": ref or []},
        "native": {"launch": "--server-ui-preview", "route": routes.get("candidate"), "steps": nat or []},
        "status": "mapped" if surface and (ref or nat) else "unmapped",
    }


def page_kind(surface: Optional[Mapping[str, Any]], item: Mapping[str, Any]) -> str:
    steps = _steps(surface, "candidate") or _steps(surface, "reference") or []
    if len(steps) == 1 and steps[0] in TAB_LABELS:
        return "tab-switch"
    return "push" if len(steps) > 1 or item.get("presentedFrom") else "tab-switch"


def policy_rows(text: str) -> List[Dict[str, Any]]:
    """The rows of the section 3 table in ``motion.md``: surface, what happens first time, and again later."""
    match = re.search(r"^## 3\..*?\n(.*?)^### What", text, re.S | re.M)
    rows: List[Dict[str, Any]] = []
    if not match:
        return rows
    for line in match.group(1).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and cells[0].startswith("**"):
            name = cells[0].strip("*")
            slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
            rows.append({"id": "policy:" + slug, "item": None, "itemKind": "policy", "area": "shell", "title": name,
                         "kind": "policy", "expect": expectation(cells[1] + " / " + cells[2]), "firstTime": cells[1], "again": cells[2]})
    return rows


#: Control animations the atlas does not name but both apps draw from the same component (the DEBUG motion gallery page).
GALLERY_CONTROLS = [
    ("calibration:primary-button-enabled", "PrimaryButton, enabled and disabled (motion gallery)", "control-calib", "disable",
     "the primary button's enabled state changes (`state` cross-fade)"),
]


def gallery_controls() -> List[Dict[str, Any]]:
    rows = []
    for tid, title, scenario, event, text in GALLERY_CONTROLS:
        step = ["Toggle Primary"]
        rows.append({"id": tid, "item": None, "itemKind": "component", "area": "design", "title": title, "kind": "control", "expect": expectation(text),
                     "devices": ["iphone", "duo", "ipad"], "patterns": [], "status": "shipped", "scenario": scenario, "event": event,
                     "trigger": {"from": [], "reference": {"launch": "--gallery-fixture", "route": "gallery page motion", "steps": step},
                                 "native": {"launch": "--gallery-fixture", "route": "gallery page motion", "steps": step}, "status": "calibrated"}})
    return rows


def build(catalog: Path = CATALOG, motion_md: Path = MOTION_MD, surfaces: Path = SURFACES, patterns: Path = PATTERNS) -> Dict[str, Any]:
    items = json.loads(catalog.read_text(encoding="utf-8"))["items"]
    by_surface = {s["id"]: s for s in json.loads(surfaces.read_text(encoding="utf-8"))["surfaces"]}
    pattern_ids = {p.stem for p in patterns.glob("*.md")}
    transitions: List[Dict[str, Any]] = []
    skipped = 0
    for item in items:
        if item["kind"] == "proposal":
            skipped += 1
            continue
        surface = by_surface.get(item["id"])
        common = {"item": item["id"], "itemKind": item["kind"], "area": item["area"], "title": item["title"],
                  "devices": item.get("devices") or [], "patterns": [p for p in item.get("patterns") or [] if p in pattern_ids],
                  "status": item.get("status")}
        hints = item.get("motionHint") or []
        if item["kind"] == "page":
            kind = page_kind(surface, item)
            transitions.append({**common, "id": f"{item['id']}:{kind}", "kind": kind, "trigger": trigger(item, surface),
                                "expect": expectation("cut, no content motion" if kind == "tab-switch" else "system push, `standard` 0.3 s")})
        elif item["kind"] == "modal":
            kind = presentation_kind(item.get("presentation"))
            transitions.append({**common, "id": f"{item['id']}:{kind}", "kind": kind, "presentation": item.get("presentation"),
                                "trigger": trigger(item, surface), "expect": expectation("system " + kind)})
        for n, hint in enumerate(hints, 1):
            kind = "flow" if item["kind"] == "flow" else "control"
            transitions.append({**common, "id": f"{item['id']}:{kind}-{n}", "kind": kind, "trigger": trigger(item, surface),
                                "expect": expectation(hint)})
    transitions.extend(policy_rows(motion_md.read_text(encoding="utf-8")))
    transitions.extend(gallery_controls())
    for t in transitions:
        t.setdefault("scenario", None)
        t["reduceMotion"] = "motion.md section 8"
        if t["id"] in CALIBRATED:
            t["scenario"], t["event"] = CALIBRATED[t["id"]]
            t["trigger"]["status"] = "calibrated"
    counts: Dict[str, int] = {}
    for t in transitions:
        counts[t["kind"]] = counts.get(t["kind"], 0) + 1
    return {"schema": "motion-pairs-transitions@1", "sources": [str(CATALOG.relative_to(REPO)), str(MOTION_MD.relative_to(REPO)),
            "tools/parity_loop/surfaces.json", ".agents/patterns/*.md"], "count": len(transitions), "byKind": dict(sorted(counts.items())),
            "proposalsSkipped": skipped, "transitions": transitions}


def write(out: Path) -> Dict[str, Any]:
    data = build()
    out.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return data
