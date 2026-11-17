"""Pure curve and onset maths for motion pairs: no numpy, no video, no device, so it unit-tests on synthetic series.

A *motion series* is ``[(t_ms, change)]``: how much each recorded frame differs from the one before (0 to 255, mean absolute
difference). A *progress series* is ``[(t_ms, p)]`` with ``p`` 0 before the move and 1 once settled. Everything here works on
those two shapes. The recorder paces frames irregularly (62 to 85 fps with near pairs, ``spike.md`` section 1), so nothing
counts frames or assumes a step: fits use the real timestamps.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

Series = Sequence[Tuple[float, float]]

#: A change that settles this fast after its onset (a frame or two at the recorder's pace) is a cut, not a movement.
CUT_MS = 25.0
#: Progress already reached on the first frame that counts as the onset: above this the recorder missed the start of the move
#: (a first-frame hitch while the destination builds, 70 to 570 ms on both sides in the spike), so the take's timing is not used.
LATE_ONSET = 0.3


# MARK: - Events in a motion series

@dataclass
class Event:
    """One burst of motion: ``lead_ms`` the first frame that changed at all, ``onset_ms`` the first that changed more than the
    onset threshold (a button highlight changes less), ``end_ms`` the last frame that still changed more than the settle floor."""
    lead_ms: float
    onset_ms: float
    end_ms: float
    frames: int
    max_gap_ms: float = 0.0


def segment_events(motion: Series, floor: float = 0.05, gap_ms: float = 300.0, min_frames: int = 10,
                   onset_threshold: float = 1.0, settle_floor: float = 0.3) -> List[Event]:
    """Split a motion series into bursts (frames over ``floor``, ended by a ``gap_ms`` quiet spell), keep those of at least
    ``min_frames`` and describe each. A burst that never exceeds ``onset_threshold`` is not an event."""
    bursts: List[List[Tuple[float, float]]] = []
    cur: List[Tuple[float, float]] = []
    for t, d in motion:
        if d <= floor:
            continue
        if cur and t - cur[-1][0] > gap_ms:
            bursts.append(cur)
            cur = []
        cur.append((t, d))
    if cur:
        bursts.append(cur)
    events: List[Event] = []
    for burst in bursts:
        if len(burst) < min_frames:
            continue
        onset = next((t for t, d in burst if d > onset_threshold), None)
        if onset is None:
            continue
        moving = [(t, d) for t, d in burst if t >= onset]
        ends = [t for t, d in moving if d > settle_floor]
        end = ends[-1] if ends else onset
        ts = [t for t, _ in moving if t <= end]
        gaps = [b - a for a, b in zip(ts, ts[1:])]
        events.append(Event(burst[0][0], onset, end, len(ts), max(gaps) if gaps else 0.0))
    return events


# MARK: - Progress series helpers

def interpolate(series: Series, t: float) -> float:
    """Linear interpolation of a series at ``t``; clamped to the first and last value outside it."""
    if not series:
        return 0.0
    if t <= series[0][0]:
        return series[0][1]
    if t >= series[-1][0]:
        return series[-1][1]
    lo, hi = 0, len(series) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if series[mid][0] <= t:
            lo = mid
        else:
            hi = mid
    (t0, p0), (t1, p1) = series[lo], series[hi]
    return p0 if t1 == t0 else p0 + (p1 - p0) * (t - t0) / (t1 - t0)


def onset_of_progress(series: Series, level: float = 0.02) -> Optional[float]:
    """First time progress exceeds ``level`` (interpolated between the two frames around the crossing)."""
    prev = None
    for t, p in series:
        if p > level:
            if prev is None or prev[1] >= p:
                return t
            return prev[0] + (t - prev[0]) * (level - prev[1]) / (p - prev[1])
        prev = (t, p)
    return None


def settle_time(series: Series, band: float = 0.02) -> Optional[float]:
    """The time after which progress stays within ``band`` of 1 (T98 for the default band): the last sample outside the band,
    interpolated up to the band edge, or the first sample when it never leaves it. ``None`` when it never gets there."""
    if not series or abs(series[-1][1] - 1.0) > band:
        return None
    last_out = None
    for i, (t, p) in enumerate(series):
        if abs(p - 1.0) > band:
            last_out = i
    if last_out is None:
        return series[0][0]
    t0, p0 = series[last_out]
    t1, p1 = series[last_out + 1]
    edge = 1.0 - band if p0 < 1.0 else 1.0 + band
    return t1 if p1 == p0 else t0 + (t1 - t0) * (edge - p0) / (p1 - p0)


def overshoot(series: Series) -> float:
    """``max(p) - 1``, never negative: how far a spring went past its rest value."""
    return max(0.0, max((p for _, p in series), default=1.0) - 1.0)


def resample(series: Series, grid: Sequence[float]) -> List[float]:
    return [interpolate(series, t) for t in grid]


def median(values: Sequence[float]) -> float:
    ordered = sorted(values)
    n = len(ordered)
    if n == 0:
        return 0.0
    return ordered[n // 2] if n % 2 else (ordered[n // 2 - 1] + ordered[n // 2]) / 2.0


def median_curve(curves: Sequence[Series], step_ms: float = 10.0) -> List[Tuple[float, float]]:
    """Pointwise median of several takes on a common 0-based time axis (each already aligned at its own onset)."""
    if not curves:
        return []
    end = max(c[-1][0] for c in curves)
    out = []
    t = 0.0
    while t <= end + 1e-9:
        out.append((t, median([interpolate(c, t) for c in curves])))
        t += step_ms
    return out


def curve_distance(a: Series, b: Series, step_ms: float = 10.0) -> Dict[str, float]:
    """RMSE and the largest deviation between two aligned progress curves over their common active window."""
    if not a or not b:
        return {"rmse": 1.0, "maxDev": 1.0}
    end = max(a[-1][0], b[-1][0])
    n = int(end // step_ms) + 1
    diffs = [interpolate(a, i * step_ms) - interpolate(b, i * step_ms) for i in range(n)]
    return {"rmse": math.sqrt(sum(d * d for d in diffs) / len(diffs)), "maxDev": max(abs(d) for d in diffs)}


# MARK: - Curve families

def _bezier_table(x1: float, y1: float, x2: float, y2: float, n: int = 64) -> List[Tuple[float, float]]:
    pts = []
    for i in range(n + 1):
        s = i / n
        m = 1 - s
        x = 3 * m * m * s * x1 + 3 * m * s * s * x2 + s ** 3
        y = 3 * m * m * s * y1 + 3 * m * s * s * y2 + s ** 3
        pts.append((x, y))
    return pts


def bezier(x1: float, y1: float, x2: float, y2: float):
    """A CSS-style ``cubic-bezier`` as ``f(u)`` for ``u`` in 0...1, through a lookup table (x is monotone for x1, x2 in 0...1)."""
    table = _bezier_table(x1, y1, x2, y2)

    def f(u: float) -> float:
        if u <= 0:
            return 0.0
        if u >= 1:
            return 1.0
        lo, hi = 0, len(table) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if table[mid][0] <= u:
                lo = mid
            else:
                hi = mid
        (xa, ya), (xb, yb) = table[lo], table[hi]
        return ya if xb == xa else ya + (yb - ya) * (u - xa) / (xb - xa)
    return f


def spring(duration_s: float, bounce: float):
    """A UIKit/SwiftUI spring of ``duration`` and ``bounce`` as ``f(t_s)``: undamped natural frequency ``2 pi / duration``, damping
    ratio ``1 - bounce`` (``bounce`` 0 is critically damped, 0.2 a gentle overshoot, the app forbids more than 0.15 outside
    the intro). Starts at rest, ends at 1."""
    w = 2 * math.pi / max(duration_s, 1e-3)
    z = 1.0 - bounce

    def f(t: float) -> float:
        if t <= 0:
            return 0.0
        if z >= 0.999:
            return 1 - math.exp(-w * t) * (1 + w * t)
        wd = w * math.sqrt(1 - z * z)
        return 1 - math.exp(-z * w * t) * (math.cos(wd * t) + (z * w / wd) * math.sin(wd * t))
    return f


#: The named easings every fit tries first. Tokens in ``motion.md`` section 7 are SwiftUI ``easeOut``, ``easeInOut`` and
#: ``smooth``/``snappy`` springs; the system push and sheet are springs too.
NAMED_BEZIERS: Dict[str, Tuple[float, float, float, float]] = {
    "linear": (0.0, 0.0, 1.0, 1.0),
    "ease-in": (0.42, 0.0, 1.0, 1.0),
    "ease-out": (0.0, 0.0, 0.58, 1.0),
    "ease-in-out": (0.42, 0.0, 0.58, 1.0),
    "ease": (0.25, 0.1, 0.25, 1.0),
}


@dataclass
class Fit:
    """The best curve for one progress series: ``family`` ("linear", "ease-out", ..., "spring", "bezier"), its ``params``
    (``duration_ms`` always; ``bounce`` for a spring; ``x1 y1 x2 y2`` for a free bezier), the ``delay_ms`` after the onset the
    curve starts, and the ``rmse`` against the samples."""
    family: str
    params: Dict[str, float]
    delay_ms: float
    rmse: float
    candidates: Dict[str, float] = field(default_factory=dict)

    def as_json(self) -> Dict[str, object]:
        return {"family": self.family, "params": {k: round(v, 4) for k, v in self.params.items()}, "delayMs": round(self.delay_ms, 1),
                "rmse": round(self.rmse, 4), "candidates": {k: round(v, 4) for k, v in self.candidates.items()}}


def _rmse(f, ts: Sequence[float], ps: Sequence[float], delay: float, scale_ms: float) -> float:
    total = 0.0
    for t, p in zip(ts, ps):
        total += (f((t - delay) / scale_ms) - p) ** 2
    return math.sqrt(total / len(ts))


def _fit_named_bezier(ts, ps, params, settle_ms):
    f = bezier(*params)
    best = (1e9, 0.0, settle_ms)
    for k in range(25, 76):
        d = settle_ms * k / 50.0
        for delay in (-40.0, -25.0, -10.0, 0.0, 10.0, 25.0):
            e = _rmse(f, ts, ps, delay, d)
            if e < best[0]:
                best = (e, delay, d)
    return best


def _fit_spring(ts, ps, settle_ms):
    best = (1e9, 0.0, 0.3, 0.0)
    for b in [i * 0.05 for i in range(0, 11)]:
        for k in range(8, 60):
            dur = k * 0.025
            f = spring(dur, b)
            for delay in (-40.0, -25.0, -10.0, 0.0, 10.0, 25.0):
                e = _rmse(lambda u: f(u), ts, ps, delay, 1000.0)
                if e < best[0]:
                    best = (e, delay, dur, b)
    return best


def _fit_free_bezier(ts, ps, start, settle_ms):
    """Pattern search over (x1, y1, x2, y2, duration, delay) from the best named easing."""
    x1, y1, x2, y2, dur, delay = start
    lo = (0.0, -0.6, 0.0, -0.6, settle_ms * 0.4, -60.0)
    hi = (1.0, 1.6, 1.0, 1.6, settle_ms * 2.0, 40.0)
    vec = [x1, y1, x2, y2, dur, delay]
    step = [0.1, 0.1, 0.1, 0.1, settle_ms * 0.08, 8.0]

    def cost(v):
        return _rmse(bezier(*v[:4]), ts, ps, v[5], v[4])
    best = cost(vec)
    for _ in range(80):
        improved = False
        for i in range(6):
            for sign in (1, -1):
                trial = list(vec)
                trial[i] = min(hi[i], max(lo[i], trial[i] + sign * step[i]))
                c = cost(trial)
                if c < best - 1e-7:
                    best, vec, improved = c, trial, True
        if not improved:
            step = [s / 2 for s in step]
            if step[0] < 0.004:
                break
    return best, vec


def fit_curve(series: Series, simplicity_margin: float = 1.25, floor_rmse: float = 0.008) -> Optional[Fit]:
    """Fit a progress series whose time zero is the onset. Candidates: the named easings, a spring (duration, bounce), and a free
    cubic-bezier started from the best named one. The simplest family within ``simplicity_margin`` times the best RMSE (plus
    ``floor_rmse``) wins, in the order linear, named easing, spring, free bezier. ``None`` for a series that never settles."""
    settle = settle_time(series)
    if settle is None or settle <= 0 or len(series) < 6:
        return None
    pts = [(t, p) for t, p in series if t <= settle * 1.35 + 30]
    ts = [t for t, _ in pts]
    ps = [p for _, p in pts]
    cands: Dict[str, Tuple[float, str, Dict[str, float], float]] = {}
    for name, params in NAMED_BEZIERS.items():
        e, delay, dur = _fit_named_bezier(ts, ps, params, settle)
        cands[name] = (e, name, {"duration_ms": dur}, delay)
    e, delay, dur, bounce = _fit_spring(ts, ps, settle)
    cands["spring"] = (e, "spring", {"duration_ms": dur * 1000.0, "bounce": bounce}, delay)
    named_best = min((v for k, v in cands.items() if k != "spring"), key=lambda v: v[0])
    start = NAMED_BEZIERS[named_best[1]]
    e, vec = _fit_free_bezier(ts, ps, (*start, named_best[2]["duration_ms"], named_best[3]), settle)
    cands["bezier"] = (e, "bezier", {"x1": vec[0], "y1": vec[1], "x2": vec[2], "y2": vec[3], "duration_ms": vec[4]}, vec[5])
    best_err = min(v[0] for v in cands.values())
    order = ["linear", "ease-out", "ease-in-out", "ease-in", "ease", "spring", "bezier"]
    chosen = next(cands[k] for k in order if cands[k][0] <= best_err * simplicity_margin + floor_rmse)
    return Fit(chosen[1], chosen[2], chosen[3], chosen[0], {k: v[0] for k, v in cands.items()})


def classify_motion(slide_ratio: Optional[float], axis: Optional[str], limit: float = 1.5) -> str:
    """``slide-x`` or ``slide-y`` when a rigid shift along that axis explains the half-way frames better than ``limit`` times a
    cross-fade does (``slide_ratio`` = slide error / cross-fade error), else ``fade`` (a cross-fade, a recolour, a layout change);
    ``none`` when nothing could be measured."""
    if slide_ratio is None:
        return "none"
    return "slide-" + axis if axis and slide_ratio < limit else "fade"
