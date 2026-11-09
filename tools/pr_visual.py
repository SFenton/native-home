#!/usr/bin/env python3
"""pr_visual: which pictures and clips a visual PR shows, per device class, and the comment bodies that carry them.

    python3 tools/pr_visual.py select --branch B [--task T] [--round N] [--base-pack DIR --after-pack DIR]
                                      [--request-file F] [--plan-file F] [--previous SELECTION.json]
                                      [--files PATH ...] [--diff-base REF] [--no-jev]
    python3 tools/pr_visual.py render --class iphone|duo|ipad --round N --selection F [--task T] [--summary TEXT]
    python3 tools/pr_visual.py devices --selection F [--covered-by CLASS=TEXT ...]

``select`` compares the before and after evidence packs (``build/evidence/<branch>/{before,after}/``, shape in
``.agents/skills/pose-matrix/SKILL.md``) pose by pose from the accessibility trees (``*.ax.txt``, or the manifest's
``ax_tree`` path), never from pixels, and writes ``build/evidence/<branch>/selection.json``. Each device class
(``iphone``, ``duo``, ``ipad``) is judged on its own (spec ``build/research/visual-prs.md`` K.6 rules 1 and 2):

* A pose is ``changed`` when its element list or frames differ beyond ``FRAME_TOLERANCE`` points, ``same`` when the
  trees match, and ``unknown`` ("not compared") when either pack has no tree for it (today the Duo inner panel has
  none) or ``not_run`` when it was not run. Labels and values are ignored, so a clock, the weather or a camera feed
  never counts; ``StaticText`` compares position only.
* ``needs_evidence`` is ``true`` when a pose changed, code that runs during that class's transitions changed
  (``TRANSITION_CODE_PATHS``, test files excluded), or the request names the class. It is ``"unknown"`` (with
  ``route: "verifier"``) when no trigger fired but a pose could not be compared and the diff could affect the class:
  the Verifier looks at the screenshots and decides, so nothing is silently "no comment". Otherwise ``false`` with
  a reason for the device table.
* Candidate transitions are the edges that touch a changed pose, plus the edges the request names; transition code
  widens to every edge only when neither exists. A still pair is the default; an edge becomes a clip only when
  transition code changed or the request names its motion. Every clip candidate is keyed on (kind, the layout class
  it lands in); equivalent edges collapse to the likeliest one. One round-trip clip per edge (two when the request
  says "going back"); sheet variants only when sheet code changed; at most ``MAX_CLIPS`` clips and ``MAX_PAIRS``
  pairs per class; the rest go to ``checked_not_shown``.
* ``--previous`` marks a class whose pairs and clips are unchanged from the previous round ``repost: false``.
* The Jev questions run in **shadow** only: answers (and ``jev_disagrees``) are recorded under ``jev_shadow`` and
  nothing else reads them: not the selection, not the device rows.

``render`` prints one class's comment body (layout in K.6) ending in the marker
``<!-- sh:evidence:<task>:<class>:<round> -->``. ``devices`` prints the device-table rows for the description's
``sh-devices`` block. Standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# MARK: - Constants

CLASSES = ("iphone", "duo", "ipad")
CLASS_NAMES = {"iphone": "iPhone", "duo": "iPhone Duo", "ipad": "iPad"}
CLASS_SHORT = {"iphone": "iPhone", "duo": "Duo", "ipad": "iPad"}
MAX_CLIPS = 3
MAX_PAIRS = 4
#: Points an element's origin or size may move before a pose counts as changed.
FRAME_TOLERANCE = 2.0
DEFAULT_CLIP_LENGTH = "about 10 s"

#: Pose id -> (class, plain name, layout class). The layout class is the SplitPolicy result plus hinge state:
#: ``one`` (single page), ``two`` (may split), ``two-book`` (split on the hinge).
POSES: dict[str, tuple[str, str, str]] = {
    "iphone": ("iphone", "Upright", "one"),
    "duo-folded": ("duo", "Folded", "one"),
    "duo-unfolded-portrait": ("duo", "Open upright", "one"),
    "duo-unfolded-landscape": ("duo", "Lying flat", "two"),
    "duo-partial-fold": ("duo", "Half open", "two-book"),
    "ipad-portrait": ("ipad", "Upright", "one"),
    "ipad-landscape": ("ipad", "On its side", "two"),
}
POSE_ALIASES = {"ipad-portrait-unrotated": "ipad-portrait", "ipad-landscape-rotated": "ipad-landscape"}
LAYOUT_RANK = {"one": 0, "two": 1, "two-book": 2}

#: Edges per class, likeliest first: (pose a, pose b, kind). ``kind`` is open_close, half or rotate.
EDGES: dict[str, tuple[tuple[str, str, str], ...]] = {
    "duo": (
        ("duo-unfolded-landscape", "duo-partial-fold", "half"),
        ("duo-folded", "duo-unfolded-landscape", "open_close"),
        ("duo-folded", "duo-partial-fold", "half"),
        ("duo-unfolded-portrait", "duo-unfolded-landscape", "rotate"),
        ("duo-folded", "duo-folded", "rotate"),
    ),
    "ipad": (("ipad-portrait", "ipad-landscape", "rotate"),),
    "iphone": (),
}

#: Code that runs *during* a transition (K.2 rule 3): path regex -> the classes it affects. iPhone is locked upright,
#: so none of it widens iPhone. Edit this constant, nowhere else, when a new transition file appears.
TRANSITION_CODE_PATHS: dict[str, tuple[str, ...]] = {
    r"Hinge|WindowFold|FoldColumns|HingedPanes|PoseObserver|HingeState|DuoPose|DuoSheetPolicy": ("duo",),
    r"SplitPolicy|SheetFit|UKSelfSizing|viewWillTransition|TraitChange|SizeChange|Rotation|Orientation": ("duo", "ipad"),
}
#: Code that presents or re-fits a sheet: sheet variants of an edge are filmed only when one of these changed.
SHEET_CODE_PATHS = r"Sheet|Modal|HassModal"
#: Code for movement inside one screen (a sheet opening, scrolling, an animation): the only iPhone clips.
IN_SCREEN_CODE_PATHS = r"Animat|Transition|Scroll|Motion|Present"
#: Code that touches only one pose of a class (the hinge band exists only half open).
POSE_CODE_HINTS = {"duo-partial-fold": r"Hinge|HingedPanes|FoldColumns|WindowFold|PoseObserver|HingeState"}
#: Request words that name a pose.
POSE_WORDS = {
    "duo-partial-fold": r"half[- ]?(open|clos|fold)\w*|\bhinge\b|\bbook\b|partial",
    "duo-unfolded-landscape": r"lying flat|\bflat\b|unfolded landscape",
    "duo-unfolded-portrait": r"open upright|unfolded portrait",
    "duo-folded": r"\bfolded\b|outer panel",
    "ipad-landscape": r"on its side|ipad landscape",
}
#: Files named for one class do not count for the others.
CLASS_SPECIFIC_PATHS = {"duo": r"Duo|Hinge|Fold", "ipad": r"iPad|Ipad"}
TEST_PATHS = r"(^|/)(Tests?|tests?|[A-Za-z]*Tests)/|Tests?\.swift$"
APP_PATHS = r"^apple/.*\.swift$"

#: Request words that name a class or a motion (case-insensitive). Motion words name a move only with a device or
#: pose word beside them, so "turn the light off" and "open the garage" name nothing.
CLASS_WORDS = {
    "iphone": r"\biphone\b(?!\s+duo)",
    "duo": r"\bduo\b|\bhinge\b|half[- ]open|\bunfold|\bfolded\b|\bbook pose\b",
    "ipad": r"\bipad\b",
}
KIND_WORDS = {
    "open_close": r"\bunfold\w*|\bfolding\b|\bfold the (duo|phone)\b|\b(open|clos)\w*\s+(up\s+)?the\s+duo\b|\bduo\s+(open|clos)\w*",
    "half": r"half[- ]?(open|clos|fold)\w*|\bbook (pose|mode)\b|partial(ly)?[- ](fold|open)\w*|\bhinge\b|\bflatten\w*",
    "rotate": r"\brotat\w*|\bturn(ing|s|ed)?\s+(the\s+)?(ipad|duo|device|phone)\b|\b(ipad|duo)\s+(is\s+)?turn\w*|\bsideways\b|\blandscape\b",
}
SHEET_WORDS = r"\bsheets?\b|\bpopups?\b|\bmodals?\b"
MOTION_WORDS = r"\banimat\w*|\bscroll\w*|\btransitions?\b|\bjank\w*|\bjump\w*|\bflash\w*|\bsmooth\w*"
BACK_WORDS = r"going back|way back|coming back|reverse|back again"

# MARK: - Accessibility trees

_ELEMENT = re.compile(r"^\s*([A-Za-z]+),.*?\{\{(-?[\d.]+), (-?[\d.]+)\}, \{(-?[\d.]+), (-?[\d.]+)\}\}")


def parse_tree(text: str) -> list[tuple[str, float, float, float, float]]:
    """Elements of an XCUITest ``debugDescription`` dump as ``(type, x, y, w, h)``, in document order.

    Only the element type and its frame are kept; every label, value and identifier is dropped on purpose.
    """
    out = []
    for line in text.splitlines():
        match = _ELEMENT.match(line)
        if match:
            out.append((match.group(1), *[float(match.group(i)) for i in range(2, 6)]))
    return out


def tree_diff(before: list[tuple], after: list[tuple], tolerance: float = FRAME_TOLERANCE) -> int:
    """How many elements differ between two trees (0 means unchanged).

    The count gap between the trees plus every paired element whose type or frame differs. ``StaticText`` compares
    position only. Frames within ``tolerance`` points are the same.
    """
    changed = abs(len(before) - len(after))
    for old, new in zip(before, after):
        if old[0] != new[0]:
            changed += 1
            continue
        pairs = zip(old[1:3], new[1:3]) if old[0] == "StaticText" else zip(old[1:], new[1:])
        if any(abs(a - b) > tolerance for a, b in pairs):
            changed += 1
    return changed


def pose_id(name: str) -> str | None:
    """The canonical pose id for a manifest pose key, or None for a key that is not a pose of the graph."""
    name = POSE_ALIASES.get(name, name)
    return name if name in POSES else None


def read_pack(pack: Path) -> dict[str, dict[str, Any]]:
    """One evidence pack as ``{pose id: {"result", "unchanged", "trees": {surface: elements}, "shots": {stem: path}}}``.

    Trees are the ``*.ax.txt`` files under ``<pack>/<pose>/`` (surface = file name without ``.ax.txt``) plus the
    manifest's ``ax_tree`` path when it names a file. Screenshots are the ``*.png`` files there, keyed by the full
    file stem (``home--scrolled--uikit-inner``), so a scrolled shot never pairs with an unscrolled one. A pose absent from the manifest and the folders is missing from the result.
    """
    manifest: dict[str, Any] = {}
    try:
        manifest = json.loads((pack / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    out: dict[str, dict[str, Any]] = {}
    for key, entry in (manifest.get("poses") or {}).items():
        pid = pose_id(key)
        if not pid:
            continue
        info = out.setdefault(pid, {"result": (entry or {}).get("result", "pass"), "trees": {}, "shots": {},
                                    "unchanged": (entry or {}).get("changed") is False or (entry or {}).get("unchanged") is True})
        named = (entry or {}).get("ax_tree")
        if isinstance(named, str):
            for candidate in (Path(named), pack / named, ROOT / named):
                if candidate.is_file():
                    info["trees"].setdefault(candidate.name.removesuffix(".ax.txt").removesuffix(".txt"),
                                             parse_tree(candidate.read_text(encoding="utf-8", errors="replace")))
                    break
    folders = sorted(p.name for p in pack.iterdir() if p.is_dir()) if pack.is_dir() else []
    for key in folders:
        pid = pose_id(key)
        if not pid:
            continue
        info = out.setdefault(pid, {"result": "pass", "trees": {}, "shots": {}, "unchanged": False})
        for path in sorted((pack / key).rglob("*.ax.txt")):
            info["trees"][path.name[:-len(".ax.txt")]] = parse_tree(path.read_text(encoding="utf-8", errors="replace"))
        for path in sorted((pack / key).rglob("*.png")):
            info["shots"].setdefault(path.stem, str(path))
    return out


def compare_packs(before: dict[str, dict[str, Any]], after: dict[str, dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """Per pose id: ``{"status": changed|same|unknown|not_run, "surfaces": [(surface, n)], "shots", "note"}``.

    ``unknown`` means the pose ran in both packs but no tree exists in both ("not compared"); its screenshot
    surfaces still come back as ``shot_surfaces`` so the Verifier has pairs to look at.
    """
    out: dict[str, dict[str, Any]] = {}
    for pid in POSES:
        b, a = before.get(pid), after.get(pid)
        shots = {"before_shots": (b or {}).get("shots", {}), "after_shots": (a or {}).get("shots", {})}
        if not b or not a or b["result"] == "not_run" or a["result"] == "not_run":
            where = "both packs" if not b and not a else "the before pack" if not b or b["result"] == "not_run" else "the after pack"
            out[pid] = {"status": "not_run", "surfaces": [], "note": f"pose not run in {where}", **shots}
            continue
        common = sorted(set(b["trees"]) & set(a["trees"]))
        if not common:
            out[pid] = {"status": "unknown", "surfaces": [], "note": "no accessibility tree in both packs: not compared",
                        "shot_surfaces": sorted(set(b["shots"]) & set(a["shots"])),
                        "unchanged": b.get("unchanged") or a.get("unchanged"), **shots}
            continue
        changed = [(s, n) for s in common if (n := tree_diff(b["trees"][s], a["trees"][s]))]
        out[pid] = {"status": "changed" if changed else "same", "surfaces": changed, "compared": len(common),
                    "note": "", **shots}
    return out


# MARK: - Diff and request signals

def changed_files(base: str, files: list[str] | None) -> list[str]:
    """The diff's file list: ``files`` when given, else ``git diff --name-only BASE...HEAD`` (empty on failure)."""
    if files is not None:
        return files
    try:
        proc = subprocess.run(["git", "-C", str(ROOT), "diff", "--name-only", f"{base}...HEAD"], capture_output=True,
                              text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    return proc.stdout.split() if proc.returncode == 0 else []


def _relevant(files: list[str], cls: str) -> list[str]:
    """Non-test files that are not named for another class."""
    others = [rx for c, rx in CLASS_SPECIFIC_PATHS.items() if c != cls]
    return [f for f in files if not re.search(TEST_PATHS, f) and not any(re.search(rx, f) for rx in others)]


def transition_files(files: list[str], cls: str) -> list[str]:
    """Non-test files of the diff that run during a transition of ``cls`` (``TRANSITION_CODE_PATHS``)."""
    return [f for f in _relevant(files, cls)
            if any(cls in classes and re.search(rx, f) for rx, classes in TRANSITION_CODE_PATHS.items())]


def sheet_files(files: list[str], cls: str) -> list[str]:
    """Non-test files of the diff that present or re-fit a sheet and are not named for another class."""
    return [f for f in _relevant(files, cls) if re.search(SHEET_CODE_PATHS, f)]


def in_screen_files(files: list[str]) -> list[str]:
    """Non-test files for movement inside a screen that are not named for the Duo or the iPad (iPhone clips)."""
    return [f for f in _relevant(files, "iphone") if re.search(IN_SCREEN_CODE_PATHS, f)]


def affecting_files(files: list[str], cls: str) -> list[str]:
    """App files of the diff that could change what ``cls`` shows (empty diff: unknown, so a placeholder)."""
    if not files:
        return ["(diff unknown)"]
    return [f for f in _relevant(files, cls) if re.search(APP_PATHS, f)]


def request_names_class(text: str, cls: str) -> bool:
    """Whether the request text names the device class."""
    return bool(re.search(CLASS_WORDS[cls], text, re.I))


def request_names_any_class(text: str) -> bool:
    """Whether the request names at least one device class."""
    return any(request_names_class(text, c) for c in CLASSES)


def request_names_kind(text: str, cls: str, kind: str) -> bool:
    """Whether the request names a motion of ``kind`` for ``cls`` (a request naming no class applies to all)."""
    if request_names_any_class(text) and not request_names_class(text, cls):
        return False
    return bool(re.search(KIND_WORDS[kind], text, re.I))


# MARK: - Selection

def edge_id(a: str, b: str) -> str:
    """Stable id of an edge: ``a<->b``."""
    return f"{a}<->{b}"


def edge_label(a: str, b: str, sheet: bool = False, direction: str = "round trip") -> str:
    """Plain label: "Lying flat → Half open → Lying flat" (a round trip), with a sheet note when asked."""
    pa, pb = POSES[a][1], POSES[b][1]
    if a == b:
        text = f"{pa}: upright → on its side → upright"
    elif direction == "forward":
        text = f"{pa} → {pb}"
    elif direction == "reverse":
        text = f"{pb} → {pa}"
    else:
        text = f"{pa} → {pb} → {pa}"
    return text + (", with a sheet open" if sheet else "")


def edge_text(a: str, b: str) -> str:
    """Lower-case prose for the checked list: "lying flat to half open", "turning the folded Duo"."""
    if a == b:
        return f"turning the {POSES[a][1].lower()} Duo"
    return f"{POSES[a][1].lower()} to {POSES[b][1].lower()}"


def _crosses(a: str, b: str) -> bool:
    return (POSES[a][2] == "one") != (POSES[b][2] == "one")


def edge_signature(a: str, b: str, kind: str) -> tuple:
    """Edges with the same signature show the same thing: the same kind of move landing in the same layout class
    (the more complex end: ``two-book`` over ``two`` over ``one``). Ends that differ never merge: turning the
    folded Duo (``one``) is not turning the open Duo (``two``)."""
    landing = max((POSES[a][2], POSES[b][2]), key=LAYOUT_RANK.__getitem__)
    return (kind, landing)


def _pose_summary(compare: dict[str, dict[str, Any]], cls: str) -> dict[str, str]:
    return {POSES[p][1]: compare[p]["status"] for p in POSES if POSES[p][0] == cls}


def surface_label(stem: str) -> str:
    """Plain label of a screenshot stem: ``admin-settings--scrolled--uikit-inner`` -> ``admin-settings scrolled``."""
    parts = [x for x in stem.split("--") if not x.startswith("uikit")]
    return " ".join(parts) or stem


def _shot_pair(info: dict[str, Any], surface: str) -> tuple[str | None, str | None, str]:
    """(before path, after path, stem) for a tree surface: the same full file stem in both packs, inner panel first."""
    both = sorted(set(info["before_shots"]) & set(info["after_shots"]))
    stems = [t for t in both if t == surface or t.startswith(surface + "--")]
    stems.sort(key=lambda t: (not t.endswith("-inner"), t))
    if not stems:
        return None, None, surface
    return info["before_shots"][stems[0]], info["after_shots"][stems[0]], stems[0]


def _file_hash(path: str | None) -> str | None:
    try:
        return hashlib.sha1(Path(path).read_bytes()).hexdigest() if path else None
    except OSError:
        return None


def _pose_relevance(pid: str, files: list[str], request: str, result: str) -> int:
    """Rank of an uncompared pose: 0 the request names it, 1 the diff touches it or its result is a fail, 2 the rest."""
    if re.search(POSE_WORDS.get(pid, r"(?!x)x"), request, re.I):
        return 0
    hint = POSE_CODE_HINTS.get(pid)
    if (hint and any(re.search(hint, f) for f in files if not re.search(TEST_PATHS, f))) or result == "fail":
        return 1
    return 2


def _pairs(compare: dict[str, dict[str, Any]], cls: str, files: list[str] | None = None,
           request: str = "") -> tuple[list[dict], list[dict]]:
    """The class's before/after pairs, in this order: poses the tree marks changed (biggest change first); then
    uncompared poses the request names or the diff touches; then the other uncompared poses. A pose the manifest
    marks unchanged is never picked. Within a pose, surfaces the request names come first. Uncompared rows carry
    ``compared: false``. Returns (up to MAX_PAIRS, the rest).
    """
    rows = []
    for pid, info in compare.items():
        if POSES[pid][0] != cls or info.get("unchanged"):
            continue
        if info["status"] == "changed":
            entries = [(surface, n, *_shot_pair(info, surface)) for surface, n in info["surfaces"]]
            rank = 0
        elif info["status"] == "unknown":
            stems = info.get("shot_surfaces", [])
            inner = [t for t in stems if t.endswith("-inner")]
            entries = [(t, 0, info["before_shots"][t], info["after_shots"][t], t) for t in (inner or stems)]
            rank = 1 + _pose_relevance(pid, files or [], request, info.get("result", ""))
        else:
            continue
        for surface, count, before, after, stem in entries:
            label = surface_label(stem if info["status"] == "unknown" else surface)
            named = 0 if re.search(r"\b" + re.escape(label.split()[0].replace("-", " ")) + r"\b", request, re.I) else 1
            rows.append((rank, -count, named, list(POSES).index(pid), stem, {
                "pose": POSES[pid][1], "pose_id": pid, "surface": label, "stem": stem,
                "compared": info["status"] == "changed", "before": before, "after": after,
                "before_hash": _file_hash(before), "after_hash": _file_hash(after)}))
    rows.sort(key=lambda r: r[:5])
    pairs = [r[5] for r in rows]
    return pairs[:MAX_PAIRS], pairs[MAX_PAIRS:]


def _candidate_edges(cls: str, touch: set[str], widen: bool, request: str) -> list[dict]:
    """Edges worth a look: those touching a changed pose or named by the request; every edge when widening."""
    cands = []
    for index, (a, b, kind) in enumerate(EDGES[cls]):
        touches = [p for p in (a, b) if p in touch]
        named = request_names_kind(request, cls, kind)
        if touches or named or widen:
            cands.append({"a": a, "b": b, "kind": kind, "order": index, "named": named, "touches": touches,
                          "crosses": _crosses(a, b)})
    return cands


def _why(edge: dict, code: bool) -> str:
    if edge["named"]:
        return "the request describes this move."
    if edge["crosses"]:
        return "it switches between one page and two."
    if edge["touches"]:
        return f"it moves into the changed pose ({POSES[edge['touches'][0]][1]})."
    return "code that runs during the move changed." if code else "the request names it."


def _edge_cover(a: str, b: str, status: dict[str, str]) -> str:
    """What covered an edge that is not filmed."""
    ends = {status[a], status[b]}
    if "changed" in ends:
        return "the before and after pictures of the changed pose (only the end state changed)"
    if ends == {"same"}:
        return "tree check, no change"
    return "; ".join(
        ("not run: " if status[p] == "not_run" else "not compared: no accessibility tree for ") + POSES[p][1].lower()
        for p in dict.fromkeys((a, b)) if status[p] != "same")


def _uncompared_checked(uncompared: list[str], status: dict[str, str], pairs: list[dict]) -> list[dict]:
    """Checked-list entries for poses that were not compared: "not run" or "not compared", skipping poses shown."""
    shown = {p["pose_id"] for p in pairs}
    out = []
    for pid in uncompared:
        if pid in shown:
            continue
        out.append({"what": POSES[pid][1], "covered_by": "not run" if status[pid] == "not_run" else
                    "not compared: no accessibility tree; Verifier to check the pictures"})
    return out


def select_class(cls: str, compare: dict[str, dict[str, Any]], files: list[str], request: str) -> dict[str, Any]:
    """Selection for one device class (see the module docstring for the rules)."""
    poses = _pose_summary(compare, cls)
    pose_ids = [p for p in POSES if POSES[p][0] == cls]
    status = {p: compare[p]["status"] for p in pose_ids}
    changed = {p for p in pose_ids if status[p] == "changed"}
    uncompared = [p for p in pose_ids if status[p] in ("unknown", "not_run")]
    code_files = transition_files(files, cls)
    sheets = bool(sheet_files(files, cls))
    named_class = request_names_class(request, cls)
    triggers = {"changed": bool(changed), "code": bool(code_files), "named": named_class}
    if cls == "iphone":
        shared = in_screen_files(files)
        words = re.search(MOTION_WORDS + "|" + SHEET_WORDS, request, re.I)
        triggers["in_screen"] = bool(shared) or bool(words and (named_class or (not request_names_any_class(request) and shared)))
    needs: Any = any(triggers.values())
    out: dict[str, Any] = {"needs_evidence": needs, "reason": "", "poses": poses, "pairs": [], "clips": [],
                           "checked_not_shown": [], "more_pairs": [], "transition_files": code_files, "repost": True}
    if not needs:
        if uncompared and affecting_files(files, cls):
            names = ", ".join(POSES[p][1] for p in uncompared)
            out.update(needs_evidence="unknown", route="verifier",
                       reason=f"Not compared: no accessibility tree for {names}; Verifier to check.")
            out["pairs"], out["more_pairs"] = _pairs(compare, cls, files, request)
            out["checked_not_shown"] = _uncompared_checked(uncompared, status, out["pairs"])
            return out
        n_same = list(status.values()).count("same")
        out["reason"] = (f"Unchanged: the accessibility trees of {n_same} pose{'s' if n_same != 1 else ''} match and no "
                         "transition code changed." if n_same and not uncompared else
                         "Unchanged: no code that this device runs changed and the request does not name it.")
        return out
    why = [text for text, key in (("a pose changed", "changed"), ("transition code changed", "code"),
                                  ("the request names it", "named"), ("movement inside the screen", "in_screen"))
           if triggers.get(key)]
    out["reason"] = "; ".join(why).capitalize() + "."
    out["pairs"], out["more_pairs"] = _pairs(compare, cls, files, request)
    if out["more_pairs"]:
        out["checked_not_shown"].append({"what": f"{len(out['more_pairs'])} more screens",
                                         "covered_by": "the technical record below lists them"})
    out["checked_not_shown"] += _uncompared_checked(uncompared, status, out["pairs"])
    if cls == "iphone":
        if triggers.get("in_screen"):
            out["clips"].append({"edge": "iphone-in-screen", "direction": "round trip", "sheet": False,
                                 "label": "Upright: the motion inside the screen",
                                 "why": "iPhone is locked upright, so only movement inside a screen is filmed.",
                                 "path": None})
        out["checked_not_shown"].append({"what": "turning, folding", "covered_by": "iPhone is locked upright: no pose transitions"})
        return out
    widen = bool(code_files) and not _candidate_edges(cls, changed, False, request)
    cands = _candidate_edges(cls, changed, widen, request)
    worthy = [e for e in cands if code_files or e["named"]]
    kept: dict[tuple, dict] = {}
    listed: set[str] = set()
    for edge in sorted(worthy, key=lambda e: e["order"]):
        sig = edge_signature(edge["a"], edge["b"], edge["kind"])
        if sig in kept:
            first = kept[sig]
            listed.add(edge_id(edge["a"], edge["b"]))
            out["checked_not_shown"].append({"what": edge_text(edge["a"], edge["b"]),
                                             "covered_by": f"same end layout as {edge_text(first['a'], first['b'])}"})
        else:
            kept[sig] = edge
    plan = list(kept.values())
    if sheets:
        plan += [dict(e, sheet=True, order=e["order"] + 100) for e in plan]
    request_back = bool(re.search(BACK_WORDS, request, re.I))
    ranked = sorted(plan, key=lambda e: (not e["named"], not e["crosses"], not e["touches"], e["order"]))
    clips = []
    for edge in ranked:
        for direction in (("forward", "reverse") if request_back and edge["a"] != edge["b"] else ("round trip",)):
            clips.append({"edge": edge_id(edge["a"], edge["b"]), "direction": direction, "sheet": bool(edge.get("sheet")),
                          "label": edge_label(edge["a"], edge["b"], bool(edge.get("sheet")), direction),
                          "why": _why(edge, bool(code_files)), "path": None})
    out["clips"] = clips[:MAX_CLIPS]
    for clip in clips[MAX_CLIPS:]:
        out["checked_not_shown"].append({"what": clip["label"], "covered_by": "over the 3-clip budget"})
    filmed = {c["edge"] for c in clips}
    for a, b, _kind in EDGES[cls]:
        eid = edge_id(a, b)
        if eid not in filmed and eid not in listed:
            out["checked_not_shown"].append({"what": edge_text(a, b), "covered_by": _edge_cover(a, b, status)})
    if not sheets:
        out["checked_not_shown"].append({"what": "sheets", "covered_by": "no sheet code changed"})
    return out


def mark_reposts(selection: dict[str, Any], previous: dict[str, Any]) -> None:
    """K.6 rule 7: a class whose pairs and clips match the previous round's is ``repost: false``.

    Pairs compare by (pose, surface) and the content hash of both pictures, never by path, so a pack moved to a new
    folder (``after-r2/``) with the same pictures does not force a repost.
    """
    def key(info: dict[str, Any]) -> Any:
        return (info["needs_evidence"],
                [(p["pose_id"], p["surface"], p.get("before_hash"), p.get("after_hash")) for p in info["pairs"]],
                [(c["edge"], c["direction"], c["sheet"]) for c in info["clips"]])
    for cls, info in selection["classes"].items():
        before = (previous.get("classes") or {}).get(cls)
        info["repost"] = not (before is not None and info["needs_evidence"] is True and key(before) == key(info))


# MARK: - Jev (shadow)

def default_asker() -> Callable[[str, dict[str, Any]], Any]:
    """Asks a registered question through ``tools/jev_ask.py`` (shadow questions log themselves; None when unavailable)."""
    spec = importlib.util.spec_from_file_location("jev_ask", HERE / "jev_ask.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["jev_ask"] = module
    spec.loader.exec_module(module)
    questions = module.load_questions()

    def ask(question_id: str, context: dict[str, Any]) -> Any:
        return module.ask_question(questions[question_id], context, subject="pr_visual")
    return ask


def jev_shadow(context: dict[str, Any], selection: dict[str, Any], asker: Callable | None) -> dict[str, Any]:
    """Ask the shadow questions and return what to record under ``jev_shadow``.

    Records ``unavailable`` (never raises) when Jev cannot answer. Nothing reads this record back: not the
    selection, not the device rows (shadow means logged, not shown). ``jev_disagrees`` lists the classes Jev marked
    changed that the selection did not, for a later measurement and for the Verifier's own look.
    """
    if asker is None:
        return {"status": "skipped"}
    record: dict[str, Any] = {"status": "ok"}
    try:
        def put(key: str, qid: str, ctx: dict[str, Any]) -> Any:
            decision = asker(qid, ctx)
            record[key] = decision.as_dict() if decision is not None else "unavailable"
            return decision
        base = dict(context)
        needs = put("pr.class_needs_evidence", "pr.class_needs_evidence",
                    dict(base, changed_poses=json.dumps({c: v["poses"] for c, v in selection["classes"].items()})))
        put("pr.needs_stills", "pr.needs_stills", base)
        put("pr.needs_motion", "pr.needs_motion", base)
        for cls, info in selection["classes"].items():
            ctx = dict(base, device_class=CLASS_NAMES[cls])
            if cls != "iphone":
                put(f"pr.motion_named:{cls}", "pr.motion_named", ctx)
            for clip in info["clips"]:
                edge_ctx = dict(ctx, edge=clip["edge"], changed_poses=json.dumps(info["poses"]),
                                transition_files="\n".join(info.get("transition_files", [])))
                put(f"pr.motion_is_point:{cls}:{clip['edge']}", "pr.motion_is_point", edge_ctx)
                put(f"pr.motion_direction:{cls}:{clip['edge']}", "pr.motion_direction", edge_ctx)
        if needs is not None and isinstance(needs.value, list):
            record["jev_disagrees"] = [c for c in needs.value if selection["classes"][c]["needs_evidence"] is False]
    except Exception as exc:  # shadow mode: any failure is "unavailable", never an error
        record = {"status": "unavailable", "error": type(exc).__name__}
    answers = [v for k, v in record.items() if k.startswith("pr.")]
    if answers and all(v == "unavailable" for v in answers):
        record["status"] = "unavailable"
    return record


def build_selection(args: argparse.Namespace, asker: Callable | None = None) -> dict[str, Any]:
    """The whole ``selection.json`` content for the arguments of ``select``."""
    slug = args.branch.replace("/", "-")
    pack_root = ROOT / "build" / "evidence" / slug
    base_pack = Path(args.base_pack) if args.base_pack else pack_root / "before"
    after_pack = Path(args.after_pack) if args.after_pack else pack_root / "after"
    request = Path(args.request_file).read_text(encoding="utf-8") if args.request_file else ""
    plan = Path(args.plan_file).read_text(encoding="utf-8") if getattr(args, "plan_file", None) else ""
    files = changed_files(args.diff_base, args.files)
    compare = compare_packs(read_pack(base_pack), read_pack(after_pack))
    selection: dict[str, Any] = {
        "branch": args.branch, "task": args.task or "", "round": args.round, "base_pack": str(base_pack),
        "after_pack": str(after_pack), "files": files,
        "pose_notes": {p: c["note"] for p, c in compare.items() if c["note"]},
        "classes": {cls: select_class(cls, compare, files, request) for cls in CLASSES}}
    previous = getattr(args, "previous", None)
    if previous:
        mark_reposts(selection, json.loads(Path(previous).read_text(encoding="utf-8")))
    context = {"request": request, "title": args.branch, "body": request, "what_changed": request,
               "files": "\n".join(files)}
    if plan:
        context["plan"] = plan
    selection["jev_shadow"] = jev_shadow(context, selection, asker)
    return selection


# MARK: - Rendering

def _length(clip: dict[str, Any]) -> str:
    seconds = clip.get("seconds")
    return f"{round(float(seconds))} s" if seconds else DEFAULT_CLIP_LENGTH


def render_class(selection: dict[str, Any], cls: str, rnd: int, task: str | None = None, summary: str | None = None) -> str | None:
    """The class comment body (K.6), or None when the class needs no comment (``false``) or goes to the Verifier."""
    info = selection["classes"][cls]
    if info["needs_evidence"] is not True:
        return None
    task = task or selection.get("task") or "T-unknown"
    changed = [p for p, s in info["poses"].items() if s == "changed"]
    lines = [f"**Verifier** (agent) · {CLASS_NAMES[cls]} · round {rnd}", ""]
    sentence = summary or info.get("summary") or (
        f"On the {CLASS_SHORT[cls]}, " + (", ".join(changed) + (" looks" if len(changed) == 1 else " look") + " different."
                                           if changed else "the movement is what to look at."))
    lines += [sentence.strip(), ""]
    order = sorted(info["poses"].items(), key=lambda kv: kv[1] != "changed")
    labels = {"unknown": "not compared", "not_run": "not run"}
    lines += ["Poses: " + " · ".join(f"{name} — {labels.get(status, status)}" for name, status in order), ""]
    if info["pairs"]:
        lines += ["| | Before | After |", "|---|---|---|"]
        for pair in info["pairs"]:
            note = "" if pair.get("compared", True) else " (not compared)"
            lines.append(f"| {pair['pose']}: {pair['surface']}{note} | " + " | ".join(
                f'<img src="{pair[side]}" width="240" alt="{side.title()}: {pair["pose"]}, {pair["surface"]}">' if pair.get(side)
                else "_not captured_" for side in ("before", "after")) + " |")
        lines.append("")
    if info["clips"]:
        lines += ["**Clips**", ""]
        for clip in info["clips"]:
            lines += [clip["path"] if clip.get("path") else "_Clip not recorded yet._", "",
                      f"{clip['label']}, {_length(clip)}. Why this one: {clip['why']}", ""]
    if info["checked_not_shown"]:
        lines += ["**Checked, not shown:** " + "; ".join(f"{c['what']} ({c['covered_by']})" for c in info["checked_not_shown"]), ""]
    record = [f"- Packs: before `{selection.get('base_pack')}`, after `{selection.get('after_pack')}`",
              f"- Why this class: {info['reason']}"]
    prefix = cls if cls != "iphone" else "iphone"
    record += [f"- Pose not compared: {p}: {note}" for p, note in selection.get("pose_notes", {}).items() if p.startswith(prefix)]
    record += [f"- More pair: {p['pose']}: {p['surface']}: before `{p.get('before')}`, after `{p.get('after')}`" for p in info.get("more_pairs", [])]
    record += [f"- Transition code: `{f}`" for f in info.get("transition_files", [])]
    lines += ["<details><summary>Technical record</summary>", ""] + record + ["", "</details>", "",
                                                                             f"<!-- sh:evidence:{task}:{cls}:{rnd} -->"]
    return "\n".join(lines) + "\n"


def device_rows(selection: dict[str, Any], covered_by: dict[str, str] | None = None) -> list[str]:
    """Grouped device-table rows: a link to the class comment, the Verifier hand-off, or why there is none.

    Reads only the selection's class entries, never ``jev_shadow``.
    """
    covered_by = covered_by or {}
    rows = []
    for cls in CLASSES:
        info = selection["classes"][cls]
        if info["needs_evidence"] == "unknown":
            text = info["reason"]
        elif info["needs_evidence"]:
            changed = [p for p, s in info["poses"].items() if s == "changed"]
            text = f"See the {CLASS_SHORT[cls]} pictures below" + (f" ({', '.join(changed)})" if changed else "")
        else:
            text = f"Unchanged, checked by {covered_by[cls]}" if covered_by.get(cls) else info["reason"]
        rows.append(f"| {CLASS_NAMES[cls]} | {text} |")
    return rows


# MARK: - CLI

def main(argv: list[str] | None = None, asker: Callable | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sel = sub.add_parser("select", help="write build/evidence/<branch>/selection.json")
    sel.add_argument("--branch", required=True)
    sel.add_argument("--task", default="")
    sel.add_argument("--round", type=int, default=1)
    sel.add_argument("--base-pack")
    sel.add_argument("--after-pack")
    sel.add_argument("--request-file")
    sel.add_argument("--plan-file")
    sel.add_argument("--previous", help="the previous round's selection.json (marks unchanged classes repost: false)")
    sel.add_argument("--files", nargs="*", default=None, help="the diff's files (default: diff against --diff-base)")
    sel.add_argument("--diff-base", default="origin/main")
    sel.add_argument("--out")
    sel.add_argument("--no-jev", action="store_true", help="skip the shadow Jev questions")
    ren = sub.add_parser("render", help="print one class comment body")
    ren.add_argument("--class", dest="cls", required=True, choices=CLASSES)
    ren.add_argument("--round", type=int, required=True)
    ren.add_argument("--selection", required=True)
    ren.add_argument("--task")
    ren.add_argument("--summary")
    dev = sub.add_parser("devices", help="print the device-table rows")
    dev.add_argument("--selection", required=True)
    dev.add_argument("--covered-by", action="append", default=[], metavar="CLASS=TEXT")
    args = parser.parse_args(argv)
    if args.cmd == "select":
        if asker is None and not args.no_jev:
            try:
                asker = default_asker()
            except Exception:
                asker = None
        selection = build_selection(args, None if args.no_jev else (asker or (lambda q, c: None)))
        out = Path(args.out) if args.out else ROOT / "build" / "evidence" / args.branch.replace("/", "-") / "selection.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(selection, indent=2) + "\n", encoding="utf-8")
        for cls in CLASSES:
            info = selection["classes"][cls]
            ne = info["needs_evidence"]
            line = (f"{len(info['clips'])} clips, {len(info['pairs'])} pairs" if ne is True
                    else "NOT COMPARED, route: verifier" if ne == "unknown" else "no comment")
            print(f"{CLASS_NAMES[cls]}: {line} ({info['reason']})")
            if ne == "unknown":
                print(f"warning: {CLASS_NAMES[cls]} has poses without a tree; the Verifier must look", file=sys.stderr)
        print(f"wrote {out}")
        return 0
    selection = json.loads(Path(args.selection).read_text(encoding="utf-8"))
    if args.cmd == "render":
        body = render_class(selection, args.cls, args.round, args.task, args.summary)
        if body is None:
            info = selection["classes"][args.cls]
            route = " (route: verifier)" if info["needs_evidence"] == "unknown" else ""
            print(f"no comment for {CLASS_NAMES[args.cls]}{route}: {info['reason']}", file=sys.stderr)
            return 3
        sys.stdout.write(body)
        return 0
    covered = dict(item.split("=", 1) for item in args.covered_by if "=" in item)
    print("\n".join(device_rows(selection, covered)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
