"""Reading screen recordings without ffprobe or ffmpeg (neither is installed): small Swift tools, built on first use.

``swift/clip_pts.swift`` lists the sample timestamps (no decode), ``swift/clip_gray.swift`` decodes every frame to a small luma
image, ``swift/clip_frames.swift`` writes the full-resolution frame on screen at chosen times. All three decode sequentially
(``AVAssetImageGenerator`` returns stale key frames). Binaries are cached in ``MOTION_TOOLS_DIR`` (default ``build/motion-tools``,
git-ignored) and rebuilt when their source is newer.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple


HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent


def tools_dir() -> Path:
    return Path(os.environ.get("MOTION_TOOLS_DIR") or REPO / "build" / "motion-tools")


def tool(name: str) -> Path:
    """Path of the compiled ``name`` (``clip_pts``, ``clip_gray``, ``clip_frames``), building it with ``swiftc`` if missing or stale."""
    src = HERE / "swift" / f"{name}.swift"
    out = tools_dir() / name
    if not out.exists() or out.stat().st_mtime < src.stat().st_mtime:
        out.parent.mkdir(parents=True, exist_ok=True)
        done = subprocess.run(["swiftc", "-O", str(src), "-o", str(out)], capture_output=True, text=True)
        if done.returncode != 0:
            raise RuntimeError(f"swiftc {name} failed: {done.stderr[-400:]}")
    return out


def load_gray(clip: Path, width: int = 120, scratch: Path = None) -> Tuple["np.ndarray", "np.ndarray"]:
    """``(pts_ms, frames)``: ``pts_ms`` shape (n,), ``frames`` uint8 (n, h, w), pts 0 at the first sample."""
    import numpy as np

    binary = Path(scratch or tools_dir()) / (Path(clip).stem + ".gray.bin")
    binary.parent.mkdir(parents=True, exist_ok=True)
    done = subprocess.run([str(tool("clip_gray")), str(clip), str(binary), str(width)], capture_output=True, text=True)
    if done.returncode != 0:
        raise RuntimeError(f"clip_gray failed: {done.stderr[-300:]}")
    raw = np.fromfile(binary, dtype=np.uint8)
    binary.unlink(missing_ok=True)
    n, w, h = (int(v) for v in np.frombuffer(raw[:12], dtype="<u4"))
    body = raw[12:].reshape(n, 8 + w * h)
    pts = np.frombuffer(np.ascontiguousarray(body[:, :8]).tobytes(), dtype="<f8")
    return pts, body[:, 8:].reshape(n, h, w)


def pts_stats(clip: Path) -> Dict[str, Any]:
    """Container facts for the PTS gate (no decode): sample count, span and gap statistics; the sample list is dropped."""
    done = subprocess.run([str(tool("clip_pts")), str(clip)], capture_output=True, text=True)
    data = json.loads(done.stdout)
    data.pop("ptsMs", None)
    return data


def frames_at(clip: Path, out_dir: Path, times_ms: Sequence[float], width: int = 220) -> Dict[int, Path]:
    """Write the frame on screen at each time (ms on the clip clock) as ``out_dir/f<ms>.png``; returns time -> path."""
    out_dir.mkdir(parents=True, exist_ok=True)
    times = [max(int(t), 0) for t in times_ms]
    subprocess.run([str(tool("clip_frames")), str(clip), str(out_dir), "--width", str(width)] + [str(t) for t in times],
                   capture_output=True, text=True)
    return {t: out_dir / f"f{t}.png" for t in times if (out_dir / f"f{t}.png").exists()}
