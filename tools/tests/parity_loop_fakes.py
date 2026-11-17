"""Fakes for the parity-loop tests: PNG writers, a fake ``agent-device`` and ``simctl`` behind one runner. Not a test module."""

from __future__ import annotations

import json
import plistlib
import shlex
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import png_raster  # noqa: E402
from parity_loop.common import Result  # noqa: E402

RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-1"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"
W, H = 120, 200


def solid(path: Path, colour=(20, 20, 20), paint=(), size=(W, H)) -> Path:
    """A ``size`` PNG of one colour with ``((x0, y0, x1, y1), colour)`` boxes painted over it."""
    width, height = size
    rows = [bytearray(bytes(colour) * width) for _ in range(height)]
    for (x0, y0, x1, y1), shade in paint:
        for y in range(y0, y1):
            rows[y][x0 * 3:x1 * 3] = bytes(shade) * (x1 - x0)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    png_raster.write(png_raster.Raster(width, height, b"".join(bytes(r) for r in rows)), Path(path))
    return Path(path)


NODES = [{"type": "StaticText", "label": "9:41", "rect": {"x": 10, "y": 5, "width": 30, "height": 10}},
         {"type": "Button", "label": "Chores", "rect": {"x": 10, "y": 80, "width": 40, "height": 20}, "enabled": True},
         {"type": "StaticText", "label": "Updated 5 min ago", "rect": {"x": 10, "y": 120, "width": 60, "height": 10}}]


class FakeWorld:
    """One runner for ``fake-agent SIDE ...`` and ``xcrun simctl ...``. ``calls`` records every agent command per side."""

    def __init__(self, root: Path) -> None:
        self.root = Path(root)
        self.udid = {"reference": "UDID-REF", "candidate": "UDID-CAND"}
        self.calls: Dict[str, List[List[str]]] = {"reference": [], "candidate": []}
        self.colour = {"reference": (20, 20, 20), "candidate": (20, 20, 20)}
        self.shot_paint: Dict[str, Any] = {"reference": (), "candidate": ()}
        self.nodes = {"reference": list(NODES), "candidate": list(NODES)}
        self.reference2_paint: Any = None  # painted on the second reference shot only
        self.shots = {"reference": 0, "candidate": 0}
        self.appearance = {"reference": "dark", "candidate": "dark"}  # what the simulators report
        self.appearance_works = True
        self.simctl_calls: List[List[str]] = []
        for side, text in (("reference", "ref-binary"), ("candidate", "cand-binary")):
            app = self.root / side / "App.app"
            app.mkdir(parents=True, exist_ok=True)
            (app / "bin").write_text(text)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.0", "CFBundleVersion": "7"}))
            fixture = self.root / side / "data" / "Library" / "Application Support" / "GalleryFixture"
            fixture.mkdir(parents=True, exist_ok=True)
            (fixture / "bootstrap.json").write_text(json.dumps({"id": "demo", "variables": {"FENTON_GALLERY": "home"}}))

    def side_of(self, udid: str) -> str:
        return "reference" if udid == self.udid["reference"] else "candidate"

    def __call__(self, argv, env=None, timeout=150.0) -> Result:
        argv = list(argv)
        if argv[0] == "fake-agent":
            return self.agent(argv[1], argv[2:])
        if argv[:3] == ["xcrun", "simctl", "list"]:
            self.simctl_calls.append(argv)
            if argv[-1] == "runtimes":
                return Result(0, json.dumps({"runtimes": [{"identifier": RUNTIME, "buildversion": "24A94401"}]}))
            devices = [{"udid": u, "name": f"{s} sim", "deviceTypeIdentifier": DEVICE_TYPE} for s, u in self.udid.items()]
            return Result(0, json.dumps({"devices": {RUNTIME: devices}}))
        if argv[:3] == ["xcrun", "simctl", "get_app_container"]:
            side = self.side_of(argv[3])
            return Result(0, str(self.root / side / ("App.app" if argv[5] == "app" else "data")) + "\n")
        if argv[:3] == ["xcrun", "simctl", "ui"]:
            return Result(0, self.appearance[self.side_of(argv[3])] + "\n")
        if argv[:3] == ["xcrun", "simctl", "status_bar"]:
            return Result(0, "Current Status Bar Overrides:\n  none\n")
        if argv[0] == "git":
            return Result(0, "abc1234\n")
        return Result(1, "", f"unexpected command {argv[:3]}")

    def agent(self, side: str, args: List[str]) -> Result:
        self.calls[side].append(args[:-1])  # drop --json
        verb = args[0]
        data: Dict[str, Any] = {}
        if verb == "snapshot":
            data = {"nodes": self.nodes[side]}
        elif verb == "settings":
            return Result(0, json.dumps({"success": self.appearance_works}))
        elif verb == "screenshot":
            self.shots[side] += 1
            paint = self.shot_paint[side]
            if side == "reference" and self.shots[side] == 2 and self.reference2_paint is not None:
                paint = self.reference2_paint
            solid(Path(args[1]), self.colour[side], paint)
        return Result(0, json.dumps({"success": True, "data": data}))

    def pressed(self, side: str) -> List[str]:
        return [c[1] for c in self.calls[side] if c[0] == "press"]
