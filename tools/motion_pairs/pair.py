"""Pairing two sides: medians over takes, the differences, and the verdict against configurable tolerances.

Defaults are the research note's starting values (``build/research/parity-depth.md``, "Starting values to replace after the
first calibration"); the calibration run replaces them with measured ones, so each limit can be overridden (``--tolerances
FILE.json``, a flat object of the names below). ``frameDiff`` is reported but does not gate by default: a fixtures run puts
different content on the two sides (class ``fixture``), which a frame-by-frame pixel diff counts as motion error.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

from . import curves

# MARK: - Tolerances

@dataclass
class Tolerances:
    """Limits for one pair. A duration difference passes when within ``durationMs`` OR within ``durationFraction`` of the larger
    one; the verdict also needs the move *type* to match (a slide against a cross-fade is a fail whatever the numbers)."""
    durationMs: float = 40.0
    durationFraction: float = 0.10
    leadMs: float = 50.0
    #: Tap to first changed frame, difference between the sides (the recorder offset cancels).
    latencyMs: float = 100.0
    curveRmse: float = 0.04
    overshoot: float = 0.02
    frameDiff: float = 0.03
    #: Names of the checks that decide pass or fail; the others are reported only.
    gate: List[str] = field(default_factory=lambda: ["type", "duration", "latency", "lead", "curve", "overshoot"])
    #: Multiplier on each limit when the two sides' own take-to-take spread is wider than the limit (noise floor): a limit is
    #: never tighter than ``noiseK`` times the larger side's median absolute deviation across takes.
    noiseK: float = 2.0

    @classmethod
    def load(cls, path: Optional[Path]) -> "Tolerances":
        base = cls()
        if path:
            for key, value in json.loads(Path(path).read_text(encoding="utf-8")).items():
                if not hasattr(base, key):
                    raise ValueError(f"unknown tolerance {key!r}")
                setattr(base, key, value)
        return base


# MARK: - Medians over takes

def mad(values: Sequence[float]) -> float:
    """Median absolute deviation: the robust spread a few hitchy takes cannot inflate."""
    if not values:
        return 0.0
    m = curves.median(values)
    return curves.median([abs(v - m) for v in values])


def summarize_side(events: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    """One side's takes of one event (each an ``analyze_events`` row with ``progress``) as medians, spreads and a median curve.

    Two bases. *Tap-anchored* (``tapRestMs``: the tap to the settled picture, ``tapOnsetMs``: the tap to the first changed frame):
    every take that has a tap time counts, even one whose first changed frame was already part way (a first-frame hitch only
    lengthens the tap-to-onset latency; the settled time is still true). *Onset-anchored* (``settleMs``, ``leadMs``, the median
    curve, overshoot): only takes whose first changed frame was caught near the start (``lateOnset`` false)."""
    found = [e for e in events if e.get("found") and e.get("progress") and e.get("settleMs") is not None]
    ok = [e for e in found if not e.get("lateOnset")]
    late = sum(1 for e in found if e.get("lateOnset"))
    out: Dict[str, Any] = {"takes": len(events), "usable": len(ok), "lateOnsetTakes": late, "found": len(found)}
    tapped = [e for e in found if e.get("tapToRestMs") is not None]
    if tapped:
        rest = [e["tapToRestMs"] for e in tapped]
        onset = [e["tapToOnsetMs"] for e in tapped]
        out.update({"tapTakes": len(tapped), "tapRestMs": curves.median(rest), "tapRestSpreadMs": mad(rest), "tapRestAll": [round(v) for v in rest],
                    "tapOnsetMs": curves.median(onset), "tapOnsetSpreadMs": mad(onset), "tapOnsetAll": [round(v) for v in onset]})
    if found:
        kinds = [e["kind"] for e in found]
        out["kind"] = max(set(kinds), key=kinds.count)
    if not ok:
        return out
    settle = [e["settleMs"] for e in ok]
    lead = [e["leadToOnsetMs"] for e in ok]
    curve = curves.median_curve([[(t, p) for t, p in e["progress"] if t >= 0] for e in ok])
    fit = curves.fit_curve(curve)
    out.update({
        "settleMs": curves.median(settle), "settleSpreadMs": mad(settle), "settleAll": [round(v) for v in settle],
        "leadMs": curves.median(lead), "leadSpreadMs": mad(lead),
        "overshoot": curves.median([e["overshoot"] for e in ok]),
        "slideRatio": curves.median([e["slideRatio"] for e in ok if e.get("slideRatio") is not None] or [0.0]),
        "curve": [(round(t, 1), round(p, 4)) for t, p in curve],
        "fit": fit.as_json() if fit else None,
    })
    return out


# MARK: - Verdict

def judge(reference: Mapping[str, Any], native: Mapping[str, Any], tol: Tolerances,
          frame_diff: Optional[Mapping[str, float]] = None) -> Dict[str, Any]:
    """Compare two side summaries: every check with its value, its limit, whether it passed and whether it gates.

    ``duration`` compares the tap-to-settled time when both sides have tap times (the robust basis), else the onset-to-settled
    time. ``latency`` compares tap to first changed frame: the recorder's own start offset is the same on both sides, so the
    difference is meaningful and the absolute value is not. The curve, overshoot and lead checks need onset-anchored takes on
    both sides and are left out (not failed) when a side has none."""
    tap = bool(reference.get("tapTakes") and native.get("tapTakes"))
    onset = bool(reference.get("usable") and native.get("usable"))
    if not tap and not onset:
        return {"pass": False, "verdict": "unmeasured", "checks": {}, "class": "infra",
                "reason": f"usable takes: reference {reference.get('usable', 0)}, native {native.get('usable', 0)} "
                          f"(onset caught late: {reference.get('lateOnsetTakes', 0)} / {native.get('lateOnsetTakes', 0)})"}
    checks: Dict[str, Dict[str, Any]] = {}
    kinds = (reference.get("kind"), native.get("kind"))
    checks["type"] = {"value": f"{kinds[0]} / {kinds[1]}", "limit": "equal", "pass": kinds[0] == kinds[1]}
    if tap:
        dur = abs(reference["tapRestMs"] - native["tapRestMs"])
        spread = max(reference["tapRestSpreadMs"], native["tapRestSpreadMs"])
        dur_limit = max(tol.durationMs, tol.durationFraction * max(reference["tapRestMs"], native["tapRestMs"]), tol.noiseK * spread)
        checks["duration"] = {"value": round(dur, 1), "limit": round(dur_limit, 1), "pass": dur <= dur_limit, "basis": "tap to settled"}
        lat = abs(reference["tapOnsetMs"] - native["tapOnsetMs"])
        lat_limit = max(tol.latencyMs, tol.noiseK * max(reference["tapOnsetSpreadMs"], native["tapOnsetSpreadMs"]))
        checks["latency"] = {"value": round(lat, 1), "limit": round(lat_limit, 1), "pass": lat <= lat_limit, "basis": "tap to first changed frame"}
    elif onset:
        dur = abs(reference["settleMs"] - native["settleMs"])
        noise = tol.noiseK * max(reference["settleSpreadMs"], native["settleSpreadMs"])
        dur_limit = max(tol.durationMs, tol.durationFraction * max(reference["settleMs"], native["settleMs"]), noise)
        checks["duration"] = {"value": round(dur, 1), "limit": round(dur_limit, 1), "pass": dur <= dur_limit, "basis": "onset to settled"}
    if onset:
        lead = abs(reference["leadMs"] - native["leadMs"])
        lead_limit = max(tol.leadMs, tol.noiseK * max(reference["leadSpreadMs"], native["leadSpreadMs"]))
        dist = curves.curve_distance([tuple(x) for x in reference["curve"]], [tuple(x) for x in native["curve"]])
        over = abs(reference["overshoot"] - native["overshoot"])
        checks["lead"] = {"value": round(lead, 1), "limit": round(lead_limit, 1), "pass": lead <= lead_limit}
        checks["curve"] = {"value": round(dist["rmse"], 4), "limit": tol.curveRmse, "pass": dist["rmse"] <= tol.curveRmse, "maxDev": round(dist["maxDev"], 4)}
        checks["overshoot"] = {"value": round(over, 4), "limit": tol.overshoot, "pass": over <= tol.overshoot}
    if frame_diff is not None:
        checks["frameDiff"] = {"value": round(frame_diff["mean"], 4), "limit": tol.frameDiff, "pass": frame_diff["mean"] <= tol.frameDiff,
                               "worst": round(frame_diff["worst"], 4)}
    for name, check in checks.items():
        check["gate"] = name in tol.gate
    failed = [n for n, c in checks.items() if c["gate"] and not c["pass"]]
    return {"pass": not failed, "verdict": "pass" if not failed else "fail: " + ", ".join(failed), "checks": checks,
            "class": "ok" if not failed else "motion", "basis": "tap" if tap else "onset", "curveMeasured": onset}


def row_json(row: Mapping[str, Any]) -> str:
    return json.dumps(row, indent=2, sort_keys=True, default=str)
