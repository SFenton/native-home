"""From recorded takes to a verdict row, a paired GIF and a strip per event, and an index.

``analyze_pair`` takes the clips of both sides (any number of takes each) for one scenario and writes, per event of the
scenario, ``<event>.json`` (the row), ``<event>-pair.gif`` and ``<event>-strip.png`` into ``out_dir``.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

from . import curves, pair, progress, report, video
from .taps import load_taps
from .scenarios import NATIVE, REFERENCE, SIDES, Scenario


def analyze_clip(clip: Path, scenario: Scenario) -> Dict[str, Any]:
    """Decode a clip and measure the scenario's events in it."""
    pts, frames = video.load_gray(clip)
    events = progress.analyze_events(pts, frames, scenario.events())
    taps = load_taps(Path(clip))
    steps = scenario.event_steps()
    if taps is not None and len(taps) == len(scenario.steps):
        for event, step in zip(events, steps):
            if event.get("found") and event.get("settleMs") is not None:
                tap = taps[step]
                event["tapToOnsetMs"] = event["onsetMs"] - tap
                event["tapToRestMs"] = event["onsetMs"] + event["settleMs"] - tap
    return {"clip": str(clip), "pts": pts, "frames": frames, "events": events, "pace": video.pts_stats(clip), "taps": taps}


def representative(takes: Sequence[Dict[str, Any]], index: int) -> Optional[Dict[str, Any]]:
    """The take whose settle time for event ``index`` is the median of its side (a push has first-frame hitches on both sides)."""
    usable = [t for t in takes if t["events"][index].get("found") and t["events"][index].get("settleMs") is not None]
    if not usable:
        return None
    middle = curves.median([t["events"][index]["settleMs"] for t in usable])
    return min(usable, key=lambda t: abs(t["events"][index]["settleMs"] - middle))


def analyze_pair(scenario: Scenario, clips: Dict[str, Sequence[Path]], out_dir: Path, tolerances: pair.Tolerances,
                 meta: Optional[Dict[str, Any]] = None, images: bool = True, fixture_polluted: Sequence[str] = (),
                 fixture_note: str = "") -> List[Dict[str, Any]]:
    """Measure every take, pair the sides event by event and write the evidence. Returns the rows."""
    out_dir.mkdir(parents=True, exist_ok=True)
    takes = {side: [analyze_clip(Path(c), scenario) for c in clips[side]] for side in SIDES}
    rows: List[Dict[str, Any]] = []
    for index, cfg in enumerate(scenario.events()):
        summaries = {side: pair.summarize_side([t["events"][index] for t in takes[side]]) for side in SIDES}
        rep = {side: representative(takes[side], index) for side in SIDES}
        frame_diff = None
        if rep[REFERENCE] and rep[NATIVE]:
            er, en = rep[REFERENCE]["events"][index], rep[NATIVE]["events"][index]
            window = max(er["settleMs"] or 0, en["settleMs"] or 0, 300.0)
            frame_diff = progress.frame_sequence_diff(rep[REFERENCE]["pts"], rep[REFERENCE]["frames"], er["onsetMs"],
                                                      rep[NATIVE]["pts"], rep[NATIVE]["frames"], en["onsetMs"], window)
        verdict = pair.judge(summaries[REFERENCE], summaries[NATIVE], tolerances, frame_diff, scenario.expects_cut(cfg.name))
        row: Dict[str, Any] = {"event": cfg.name, "scenario": scenario.id, **(meta or {}),
                               "reference": summaries[REFERENCE], "native": summaries[NATIVE],
                               "trajectory": {side: _trajectory(rep[side], index) for side in SIDES},
                               "tolerances": {k: v for k, v in vars(tolerances).items()}, **verdict}
        if cfg.name in fixture_polluted:
            pair.mark_polluted(row, fixture_note)
        row["pace"] = {side: [t["pace"].get("gapMaxMs") for t in takes[side]] for side in SIDES}
        if images and rep[REFERENCE] and rep[NATIVE]:
            er, en = rep[REFERENCE]["events"][index], rep[NATIVE]["events"][index]
            report.make_pair_gif(out_dir / f"{cfg.name}-pair.gif", {"clip": rep[REFERENCE]["clip"], "onsetMs": er["onsetMs"]},
                                 {"clip": rep[NATIVE]["clip"], "onsetMs": en["onsetMs"]})
            report.make_strip(out_dir / f"{cfg.name}-strip.png", [
                {"label": "reference", "clip": rep[REFERENCE]["clip"], "onsetMs": er["onsetMs"], "colour": report.REF_COLOUR},
                {"label": "native", "clip": rep[NATIVE]["clip"], "onsetMs": en["onsetMs"], "colour": report.NAT_COLOUR}])
            row["media"] = {"gif": f"{cfg.name}-pair.gif", "strip": f"{cfg.name}-strip.png",
                            "referenceClip": Path(rep[REFERENCE]["clip"]).name, "nativeClip": Path(rep[NATIVE]["clip"]).name}
        (out_dir / f"{cfg.name}.json").write_text(json.dumps(row, indent=2, sort_keys=True, default=_plain) + "\n", encoding="utf-8")
        rows.append(row)
    return rows


def _trajectory(take: Optional[Dict[str, Any]], index: int) -> Optional[Dict[str, Any]]:
    """The moving element of the representative take: leading-edge shift (slides) and centre of change (controls)."""
    if not take:
        return None
    event = take["events"][index]
    return {"kind": event.get("kind"), "axis": event.get("axis"), "mover": event.get("mover"), "slideRatio": event.get("slideRatio"),
            "edge": [(round(t, 1), round(v, 4)) for t, v in event.get("edge", [])],
            "centroid": [(round(t, 1), round(x, 4), round(y, 4)) for t, x, y in event.get("centroid", [])]}


def _plain(value: Any) -> Any:
    import numpy as np

    if isinstance(value, (np.floating, np.integer)):
        return value.item()
    if isinstance(value, np.ndarray):
        return value.tolist()
    return str(value)


def write_index(out_dir: Path, rows: Sequence[Dict[str, Any]], title: str, notes: str = "") -> Path:
    """``motion.json`` (all rows) and ``index.md`` (one table, the media beside it) for a run."""
    (out_dir / "motion.json").write_text(json.dumps(list(rows), indent=2, sort_keys=True, default=_plain) + "\n", encoding="utf-8")
    lines = [f"# {title}", "", notes, "",
             "| Event | Verdict | Class | Type | Tap to settled ms (ref / native) | Tap to first change ms (ref / native) | Onset to settled ms (ref / native) | Curve RMSE | Fit (ref / native) |",
             "|---|---|---|---|---|---|---|---|---|"]
    num = lambda side, key: "n/a" if side.get(key) is None else str(round(side[key]))
    fit = lambda side: (side.get("fit") or {}).get("family", "n/a")
    for r in rows:
        ref, nat, checks = r.get("reference", {}), r.get("native", {}), r.get("checks", {})
        lines.append("| {event} | {verdict} | {cls} | {type} | {a} / {b} | {c} / {d} | {e} / {f} | {curve} | {rf} / {nf} |".format(
            event=r["event"], verdict=r["verdict"], cls=r.get("class", ""), type=checks.get("type", {}).get("value", "n/a"),
            a=num(ref, "tapRestMs"), b=num(nat, "tapRestMs"), c=num(ref, "tapOnsetMs"), d=num(nat, "tapOnsetMs"),
            e=num(ref, "settleMs"), f=num(nat, "settleMs"), curve=checks.get("curve", {}).get("value", "n/a"), rf=fit(ref), nf=fit(nat)))
    for r in rows:
        media = r.get("media")
        if media:
            lines += ["", f"## {r['event']}", "", f"![{r['event']} pair]({media['gif']})", "", f"![{r['event']} strip]({media['strip']})"]
    path = out_dir / "index.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path
