"""The sidecar written beside every capture, and the comparison that refuses a pair whose halves differ.

A sidecar records what a screenshot was taken on and with: the simulator model, runtime build, device size, scale,
appearance, status-bar override, the installed bundle hash and the app build. The halves of a pair must be equal on every
:data:`MUST_MATCH` field; each half's bundle hash must equal its pin when one is given, and the two halves must run
different apps. Launch environment variable *values* are never recorded, only their names.
"""

from __future__ import annotations

import hashlib
import json
import plistlib
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

from .common import BUNDLE_ID, Result, Runner, png_size, run

#: Sidecar format version; a different schema is a mismatch.
SCHEMA = "parity-loop-sidecar/1"
#: Fields that must be equal on both halves of a pair (``device`` group of the research note's table).
MUST_MATCH = ("model", "deviceTypeId", "runtime", "runtimeBuild", "widthPx", "heightPx", "scale", "appearance",
              "statusBarNormalized", "statusBarOverride", "pose", "source")


# MARK: - Collecting

def bundle_identity(app_dir: Path) -> str:
    """The pin's bundle hash: sha256 of the JSON of ``{relative path: sha256}`` over every file, sorted by path.

    The same recipe as ``tools/expo_pairs/bundle-hash.mjs`` (a symlink or an empty bundle is an error).
    """
    root = Path(app_dir)
    entries: Dict[str, str] = {}
    for path in sorted(p for p in root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"unresolved bundle symlink: {path.relative_to(root)}")
        if path.is_file():
            entries[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    if not entries:
        raise ValueError("empty installed app bundle")
    ordered = dict(sorted(entries.items()))
    return hashlib.sha256(json.dumps(ordered, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def _simctl(runner: Runner, *args: str) -> Result:
    return runner(["xcrun", "simctl", *args])


def device_facts(runner: Runner, udid: str) -> Dict[str, Any]:
    """Model, device type, runtime and runtime build for ``udid`` from ``simctl list -j``; empty strings when unknown."""
    facts: Dict[str, Any] = {"udid": udid, "model": "", "deviceTypeId": "", "runtime": "", "runtimeBuild": ""}
    devices = json.loads(_simctl(runner, "list", "-j", "devices").out or "{}").get("devices", {})
    runtimes = json.loads(_simctl(runner, "list", "-j", "runtimes").out or "{}").get("runtimes", [])
    for runtime_id, entries in devices.items():
        for entry in entries:
            if entry.get("udid") == udid:
                facts["name"] = entry.get("name", "")
                facts["deviceTypeId"] = entry.get("deviceTypeIdentifier", "")
                facts["model"] = facts["deviceTypeId"].rsplit(".", 1)[-1]
                facts["runtime"] = runtime_id.rsplit(".", 1)[-1]
                for known in runtimes:
                    if known.get("identifier") == runtime_id:
                        facts["runtimeBuild"] = known.get("buildversion", "")
    return facts


def app_facts(runner: Runner, udid: str, bundle_id: str = BUNDLE_ID) -> Dict[str, Any]:
    """Installed app: bundle hash, version and build from the simulator's app container."""
    facts: Dict[str, Any] = {"bundleId": bundle_id, "bundleHash": "", "appVersion": "", "appBuild": ""}
    where = _simctl(runner, "get_app_container", udid, bundle_id, "app")
    if where.code != 0 or not where.out.strip():
        return facts
    app = Path(where.out.strip())
    try:
        facts["bundleHash"] = bundle_identity(app)
        info = plistlib.loads((app / "Info.plist").read_bytes())
        facts["appVersion"] = str(info.get("CFBundleShortVersionString", ""))
        facts["appBuild"] = str(info.get("CFBundleVersion", ""))
    except (OSError, ValueError, plistlib.InvalidFileException):
        pass
    return facts


def collect(udid: str, side: str, *, png: Optional[Path] = None, scale: int = 3, appearance: Optional[str] = None,
            pose: str = "folded", source: str = "fixture", launch_args: Sequence[str] = (), env_names: Sequence[str] = (),
            house: bool = False, status_bar_normalized: bool = True, bundle_hash: Optional[str] = None, runner: Runner = run, now: Optional[datetime] = None,
            tool_sha: str = "", extra: Optional[Mapping[str, Any]] = None) -> Dict[str, Any]:
    """A sidecar for one capture. ``bundle_hash`` (already measured this run) skips re-hashing the bundle."""
    sidecar: Dict[str, Any] = {"schema": SCHEMA, "side": side}
    sidecar.update(device_facts(runner, udid))
    app = app_facts(runner, udid) if bundle_hash is None else {**app_facts(runner, udid), "bundleHash": bundle_hash}
    sidecar.update(app)
    size = None
    if png is not None:
        size = png_size(png)
    sidecar["widthPx"], sidecar["heightPx"] = (size or [None, None])
    sidecar["scale"] = scale
    shown = appearance if appearance is not None else _simctl(runner, "ui", udid, "appearance").out.strip()
    sidecar["appearance"] = shown
    listing = _simctl(runner, "status_bar", udid, "list")
    sidecar["statusBarNormalized"] = bool(status_bar_normalized)
    sidecar["statusBarOverride"] = re.sub(r"\s+", " ", listing.out).strip() if listing.code == 0 else "unknown"
    sidecar.update(pose=pose, source=source, house=house, launchArguments=list(launch_args),
                   launchEnvNames=sorted(env_names), toolSha=tool_sha)
    sidecar["capturedAt"] = (now or datetime.now(timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ")
    if extra:
        sidecar.update(extra)
    return sidecar


# MARK: - Comparing

def compare(first: Optional[Mapping[str, Any]], second: Optional[Mapping[str, Any]], *, pins: Optional[Mapping[str, str]] = None,
            same_app: bool = False) -> List[str]:
    """Why a pair of sidecars is refused; an empty list means the halves agree.

    ``pins`` maps ``side`` to its pinned bundle hash. ``same_app`` is set when both are shots of one app (the drift pair:
    reference against reference), where the bundle hashes must be equal instead of different.
    """
    if first is None or second is None:
        return ["sidecar missing"]
    problems: List[str] = []
    for sc in (first, second):
        if sc.get("schema") != SCHEMA:
            problems.append(f"sidecar schema {sc.get('schema')!r} is not {SCHEMA}")
    for field in MUST_MATCH:
        if first.get(field) != second.get(field):
            problems.append(f"{field} differs: {first.get(field)!r} vs {second.get(field)!r}")
        elif first.get(field) in (None, ""):
            problems.append(f"{field} is not recorded")
    a, b = first.get("bundleHash"), second.get("bundleHash")
    if not a or not b:
        problems.append("bundle hash is not recorded")
    elif same_app and a != b:
        problems.append("bundle hash differs between two shots of one app")
    elif not same_app and a == b:
        problems.append("both halves run the same app bundle")
    for sc in (first, second):
        pin = (pins or {}).get(str(sc.get("side")))
        if pin and sc.get("bundleHash") != pin:
            problems.append(f"{sc.get('side')} bundle hash does not match its pin")
    return problems


def load(path: Path) -> Optional[Dict[str, Any]]:
    """A sidecar from disk, or ``None`` when the file is missing or not JSON."""
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None
