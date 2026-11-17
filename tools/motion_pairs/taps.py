"""Tap times from the gesture telemetry agent-device writes beside a recording (pure: no numpy, no video)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import List, Optional


def load_taps(clip: Path) -> Optional[List[float]]:
    """Tap times (ms on the recorder's start clock) from ``<clip>.gesture-telemetry.json``. That clock runs a roughly constant 0.5 to
    0.8 s ahead of the clip's own (the recorder starts after its start time is written), so only differences between the two sides'
    tap-anchored times mean anything. ``None`` when the file is missing or unreadable."""
    path = clip.with_name(clip.stem + ".gesture-telemetry.json")
    try:
        events = json.loads(path.read_text(encoding="utf-8")).get("events", [])
    except (OSError, ValueError):
        return None
    return [float(e["tMs"]) for e in events if e.get("kind") == "tap" and "tMs" in e]
