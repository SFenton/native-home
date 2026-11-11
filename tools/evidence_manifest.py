#!/usr/bin/env python3
"""The one reader of an evidence ``manifest.json`` (``build/evidence/<branch>/manifest.json``, written by ``pose-matrix``).

``tools/pr_note.py`` (which picture may be posted) and ``tools/pr_visual.py`` (which poses ran, which screenshots exist) both
read the manifest through this module, so a new manifest shape is taught in one place.

``media_entries(manifest)`` returns one ``{"path", "source", "class", "pose"}`` entry per picture or video, from any of
three shapes, alone or mixed:

a. a top-level ``"media"`` list of ``{"path", "source"}`` objects (``"pose"`` and ``"class"`` optional);
b. a pose's ``"screenshots"``, ``"recordings"`` or ``"videos"`` as path strings, with the pose-level ``"source"``;
c. the same lists as ``{"path", "source"}`` objects (an object's own ``"source"`` wins over the pose's).

``source`` is ``demo``, ``mockup`` or ``live`` as written, ``None`` when nothing gives one. ``class`` is the evidence class
of the pose (``iphone``, ``duo`` for iPhone Duo, ``ipad``), ``all`` for a pose that maps to none. A pose that did not run
(``"result": "not_run"``) yields no entry, so it never yields a picture. Standard library only; nothing is written.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

#: The evidence classes: iPhone, iPhone Duo, iPad.
CLASSES = ("iphone", "duo", "ipad")
#: The class of a pose with no device family in its name, and of a ``media`` entry that names no pose.
ALL = "all"
#: The pose keys that list pictures or videos.
MEDIA_KEYS = ("screenshots", "recordings", "videos")
NOT_RUN = "not_run"


def read(path: Path) -> Dict[str, Any]:
    """The manifest at ``path`` as a dict; ``{}`` when it is missing, unreadable or not a JSON object."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def poses(manifest: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    """``{pose key: entry}`` in manifest order; an entry that is not an object becomes ``{}``."""
    found = manifest.get("poses") if isinstance(manifest, dict) else None
    if not isinstance(found, dict):
        return {}
    return {str(key): (entry if isinstance(entry, dict) else {}) for key, entry in found.items()}


def pose_class(pose: Optional[str]) -> str:
    """The evidence class a pose key belongs to (``duo-partial-fold`` is ``duo``), ``all`` when it names none."""
    name = (pose or "").lower()
    for cls in CLASSES:
        if name == cls or name.startswith((f"{cls}-", f"{cls}_")):
            return cls
    return ALL


def _entry(item: Any, pose: Optional[str], pose_source: Any) -> Optional[Dict[str, Any]]:
    """One normalised entry from a path string or a ``{path, source}`` object, ``None`` when it names no path."""
    if isinstance(item, str):
        item = {"path": item}
    if not isinstance(item, dict) or not isinstance(item.get("path"), str) or not item["path"]:
        return None
    source = item.get("source", None)
    if not isinstance(source, str):
        source = pose_source if isinstance(pose_source, str) else None
    named = item.get("pose") if isinstance(item.get("pose"), str) else None
    pose = pose or named
    cls = item.get("class") if item.get("class") in CLASSES else pose_class(pose)
    return {"path": item["path"], "source": source, "class": cls, "pose": pose}


def media_entries(manifest: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Every picture and video the manifest names, as ``{"path", "source", "class", "pose"}`` (module docstring).

    Order: the top-level ``media`` list, then each pose's ``screenshots``, ``recordings`` and ``videos``. Entries of a pose
    whose result is ``not_run`` are left out, also when a ``media`` entry names that pose."""
    by_pose = poses(manifest)
    skipped = {key for key, entry in by_pose.items() if entry.get("result") == NOT_RUN}
    out: List[Dict[str, Any]] = []
    top = manifest.get("media") if isinstance(manifest, dict) else None
    for item in top if isinstance(top, list) else []:
        entry = _entry(item, None, None)
        if entry and entry["pose"] not in skipped:
            out.append(entry)
    for key, pose in by_pose.items():
        if key in skipped:
            continue
        for name in MEDIA_KEYS:
            listed = pose.get(name)
            for item in listed if isinstance(listed, list) else []:
                entry = _entry(item, key, pose.get("source"))
                if entry:
                    out.append(entry)
    return out
