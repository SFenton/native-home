"""From a decoded clip to per-event progress curves and trajectories (numpy; the maths it hands to is in ``curves.py``).

``video.load_gray`` gives the frames as small luma images. This module finds the events (pushes, sheets, a control changing),
projects every frame of each event onto the line from the picture before it to the picture after it (progress ``p``: 0 before,
1 settled, a fade, a slide and a spring all read the same way), and measures *how* it moved: the share of screen lines
covered by the new picture over time (the leading edge of a slide) and how many lines are half way at once (a slide has
few, a cross-fade has all of them).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence, Tuple

import numpy as np

from . import curves

Roi = Tuple[float, float, float, float]  # x0, y0, x1, y1 as fractions of the frame


@dataclass
class EventConfig:
    """How to find one event in a clip. ``onset_threshold`` is the mean frame-to-frame change (0 to 255) that starts it:
    1.0 for a full-screen move (a button highlight changes less), far lower for a small control, with ``roi`` cropping to it."""
    name: str
    onset_threshold: float = 1.0
    min_frames: int = 10
    roi: Optional[Roi] = None


def crop(frames: np.ndarray, roi: Optional[Roi]) -> np.ndarray:
    if not roi:
        return frames
    n, h, w = frames.shape
    x0, y0, x1, y1 = roi
    return frames[:, int(h * y0):max(int(h * y1), int(h * y0) + 1), int(w * x0):max(int(w * x1), int(w * x0) + 1)]


def motion_series(pts: np.ndarray, frames: np.ndarray, roi: Optional[Roi] = None) -> List[Tuple[float, float]]:
    """Mean absolute change of each frame against the one before it (the spike's ``clip_motion`` series), over ``roi``."""
    f = crop(frames, roi).astype(np.int16)
    if len(f) < 2:
        return []
    d = np.abs(f[1:] - f[:-1]).reshape(len(f) - 1, -1).mean(axis=1)
    return [(float(pts[i + 1]), float(d[i])) for i in range(len(d))]


def _shift_error(frame: np.ndarray, mover: np.ndarray, base: np.ndarray, axis: int, s: int) -> Tuple[float, float]:
    """Error of the hypothesis "this frame shows ``mover`` moved ``s`` pixels along ``axis``" against the plain blend of ``base``
    and ``mover`` over the same region (a cross-fade explains the frame as well as that region allows)."""
    if axis == 1:
        fi, mi, bi = frame[:, s:], mover[:, : mover.shape[1] - s], base[:, s:]
        m0 = mover[:, s:]
    else:
        fi, mi, bi = frame[s:, :], mover[: mover.shape[0] - s, :], base[s:, :]
        m0 = mover[s:, :]
    shifted = float(np.abs(fi - mi).mean())
    dd = (m0 - bi).ravel()
    al = float(((fi - bi).ravel() @ dd) / max(float(dd @ dd), 1e-6))
    blend = float(np.abs(fi - (bi + al * (m0 - bi))).mean())
    return shifted, blend


def shift_analysis(sel: np.ndarray, a: np.ndarray, b: np.ndarray, p: np.ndarray, step: int = 2) -> Dict[str, Any]:
    """Does a rigid slide explain the frames better than a cross-fade? Tries both axes and both movers (the new picture ``b``
    sliding in, or the old one ``a`` sliding out). ``slideRatio`` is the median over the frames half way through of
    (best slide error) / (cross-fade error); under 1 a slide wins, a cross-fade scores above 2 (measured, Reduce Motion pushes
    2.3 to 4.7; sheets 0.3 to 0.6; pushes 0.9 to 1.3). ``edge`` is the best shift per frame as a fraction of the screen extent."""
    mid = [i for i in range(len(sel)) if 0.15 < p[i] < 0.85]
    best: Optional[Dict[str, Any]] = None
    h, w = a.shape
    for axis, name, size in ((1, "x", w), (0, "y", h)):
        for mover_name, mover, base in (("new", b, a), ("old", a, b)):
            ratios, shifts = [], []
            for i in mid:
                top = (1e9, 0)
                for s in range(2, int(size * 0.9), step):
                    sh, bl = _shift_error(sel[i], mover, base, axis, s)
                    if sh < top[0]:
                        top = (sh, s)
                sh, bl = _shift_error(sel[i], mover, base, axis, top[1])
                ratios.append(top[0] / max(bl, 1e-3))
                shifts.append(top[1])
            if ratios:
                ratio = float(np.median(ratios))
                if best is None or ratio < best["slideRatio"]:
                    best = {"slideRatio": ratio, "axis": name, "mover": mover_name, "extent": size,
                            "edge": [(i, s / size) for i, s in zip(mid, shifts)]}
    return best or {}


def event_curves(pts: np.ndarray, frames: np.ndarray, onset_ms: float, end_ms: float, roi: Optional[Roi] = None,
                 tail_ms: float = 160.0) -> Optional[Dict[str, Any]]:
    """Progress and edge coverage for the event from ``onset_ms`` to ``end_ms`` (the clip clock). ``A`` is the last frame before
    the onset, ``B`` the frame about ``tail_ms`` after the last change (settled). Times in the result are relative to the onset."""
    f = crop(frames, roi).astype(np.float32)
    i0 = int(np.searchsorted(pts, onset_ms, side="left"))
    if i0 < 1:
        return None
    a = f[i0 - 1]
    jb = min(int(np.searchsorted(pts, end_ms + tail_ms, side="right")) - 1, len(f) - 1)
    b = f[jb]
    delta = (b - a).ravel()
    den = float((delta * delta).sum())
    if den < 1e-6:
        return None
    jend = int(np.searchsorted(pts, end_ms, side="right"))
    idx = list(range(i0 - 1, min(jb + 1, len(f))))
    sel = f[idx]
    p = ((sel - a).reshape(len(idx), -1) @ delta) / den
    t_rel = (pts[idx] - onset_ms).tolist()
    series = [(float(t), float(v)) for t, v in zip(t_rel, p)]
    out: Dict[str, Any] = {"progress": series, "frames": len(idx)}
    sh = shift_analysis(sel, a, b, p)
    if sh:
        out["slideRatio"], out["axis"], out["mover"] = sh["slideRatio"], sh["axis"], sh["mover"]
        out["edge"] = [(float(t_rel[i]), float(f)) for i, f in sh["edge"]]
    out["kind"] = curves.classify_motion(out.get("slideRatio"), out.get("axis"))
    ts = np.asarray(t_rel)
    out["centroid"] = _centroid(sel, a, ts)
    out["jend"] = jend
    return out


def _centroid(sel: np.ndarray, a: np.ndarray, ts: np.ndarray) -> List[Tuple[float, float, float]]:
    """Centre of change (x, y as fractions of the cropped frame) per frame: where the moving thing is, for a control."""
    h, w = a.shape
    ys, xs = np.mgrid[0:h, 0:w]
    out = []
    for t, fr in zip(ts, sel):
        m = np.abs(fr - a)
        s = float(m.sum())
        out.append((float(t), float((m * xs).sum() / s / w) if s > 1e-6 else 0.0, float((m * ys).sum() / s / h) if s > 1e-6 else 0.0))
    return out


def frame_sequence_diff(pts_a: np.ndarray, fa: np.ndarray, onset_a: float, pts_b: np.ndarray, fb: np.ndarray, onset_b: float,
                        window_ms: float, tol: float = 8.0, step_ms: float = 20.0) -> Dict[str, float]:
    """Share of pixels differing by more than ``tol`` (0 to 255) between the two clips at the same time after each onset, averaged
    over the window; the worst frame too. Needs the clips to have the same frame size."""
    h = min(fa.shape[1], fb.shape[1])
    w = min(fa.shape[2], fb.shape[2])
    shares = []
    t = 0.0
    while t <= window_ms:
        ia = max(int(np.searchsorted(pts_a, onset_a + t, side="right")) - 1, 0)
        ib = max(int(np.searchsorted(pts_b, onset_b + t, side="right")) - 1, 0)
        d = np.abs(fa[ia, :h, :w].astype(np.int16) - fb[ib, :h, :w].astype(np.int16))
        shares.append(float((d > tol).mean()))
        t += step_ms
    if not shares:
        return {"mean": 0.0, "worst": 0.0}
    return {"mean": float(np.mean(shares)), "worst": float(np.max(shares))}


def analyze_events(pts: np.ndarray, frames: np.ndarray, configs: Sequence[EventConfig]) -> List[Dict[str, Any]]:
    """Find the bursts for each config in order and measure each. Returns one dict per config (``found`` False when missing)."""
    results: List[Dict[str, Any]] = []
    cursor_ms = -1.0
    for cfg in configs:
        series = motion_series(pts, frames, cfg.roi)
        events = [e for e in curves.segment_events(series, min_frames=cfg.min_frames, onset_threshold=cfg.onset_threshold, settle_floor=min(0.3, cfg.onset_threshold * 0.3),
                                                    floor=0.05 if cfg.onset_threshold >= 0.5 else cfg.onset_threshold / 10)
                  if e.lead_ms > cursor_ms]
        if not events:
            results.append({"name": cfg.name, "found": False})
            continue
        ev = events[0]
        cursor_ms = ev.end_ms
        res = event_curves(pts, frames, ev.onset_ms, ev.end_ms, cfg.roi)
        row: Dict[str, Any] = {"name": cfg.name, "found": res is not None, "onsetMs": ev.onset_ms, "leadMs": ev.lead_ms,
                               "endMs": ev.end_ms, "maxGapMs": ev.max_gap_ms, "frames": ev.frames}
        if res:
            row.update(res)
            prog = res["progress"]
            settle = curves.settle_time(prog)
            row["settleMs"] = None if settle is None else max(settle, 0.0)
            row["overshoot"] = curves.overshoot(prog)
            if settle is not None and settle <= curves.CUT_MS:
                row["kind"] = "cut"  # the picture changed within a frame or two: a swap, not a movement
            row["leadToOnsetMs"] = ev.onset_ms - ev.lead_ms
            first = next((v for t, v in prog if t >= 0), 0.0)
            row["p0"] = first
            row["lateOnset"] = first > curves.LATE_ONSET  # the first changed frame was already part way: a first-frame hitch
            after = [(t, p) for t, p in prog if t >= 0]
            fit = None if row["kind"] == "cut" else curves.fit_curve(after)
            row["fit"] = fit.as_json() if fit else None
        results.append(row)
    return results
