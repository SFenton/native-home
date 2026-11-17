"""Capturing one shot: reach a surface, settle, snapshot the accessibility tree, take the screenshot.

``Agent`` wraps one bound ``agent-device`` command (the dispatching agent supplies the string from ``device_open``). A surface
whose reach path writes to Home Assistant (``writes_on_reach``) is reached by deep link, or skipped and recorded as skipped;
:func:`perform_reach` never presses anything for it.
"""

from __future__ import annotations

import re
import shlex
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, FrozenSet, List, Mapping, Optional, Sequence, Set, Tuple

from .common import DEFAULT_DENSITY, Runner, png_size, run, parse_json, write_json

#: Status-bar nodes dropped from the compared AX sequence: system chrome that the normaliser pins anyway.
STATUS_BAR_TYPES = ("statusbar", "status bar")
STATUS_BAR_BAND_PT = 54.0
DYNAMIC_TOKEN = "<dynamic>"


# MARK: - Driving the device

class Agent:
    """One ``agent-device`` command line bound to a device. Every call asks for ``--json`` and returns the parsed object."""

    def __init__(self, command: str, runner: Runner = run) -> None:
        self.base = shlex.split(command)
        self.runner = runner

    def call(self, *args: str, timeout: float = 150.0) -> Dict[str, Any]:
        result = self.runner([*self.base, *args, "--json"], None, timeout)
        parsed = parse_json(result.out)
        if isinstance(parsed, dict):
            return parsed
        return {"success": False, "raw": (result.out[-300:] + result.err[-300:])}

    def open_app(self, bundle: str, launch_args: Sequence[str] = (), relaunch: bool = True) -> Dict[str, Any]:
        args = ["open", bundle]
        if relaunch:
            args.append("--relaunch")
        if launch_args:
            args.append("--launch-args=" + " ".join(launch_args))
        return self.call(*args)

    def open_url(self, url: str) -> Dict[str, Any]:
        return self.call("open", url)

    def press(self, label: str) -> Dict[str, Any]:
        """Press the button called ``label``. A bare selector fails when two buttons share a name (the Quick Links button is in the
        header and the toolbar) or when the label carries a badge ("Chores, 6 overdue"), so resolve the button in the tree first and
        tap its centre; fall back to the selector when the tree has none."""
        try:
            point = button_centre(self.snapshot(), label, badged=label in NAV_LABELS)
        except AmbiguousLabel as error:
            return {"success": False, "ambiguous": True, "error": str(error)}
        if point:
            return self.call("press", f"{point[0]:g}", f"{point[1]:g}")
        return self.call("press", f'label="{label}"')

    def scroll_bottom(self) -> Dict[str, Any]:
        """Scroll the page's main scroll view to the end of its content (``agent-device scroll bottom``)."""
        return self.call("scroll", "bottom")

    def settle(self) -> Dict[str, Any]:
        return self.call("wait", "stable", "1000", "15000")

    def appearance(self, mode: str) -> Dict[str, Any]:
        return self.call("settings", "appearance", mode)

    def labels(self) -> List[str]:
        return [_label(n) for n in self.snapshot() if _label(n)]

    def snapshot(self) -> List[Dict[str, Any]]:
        data = self.call("snapshot").get("data") or {}
        nodes = data.get("nodes", []) if isinstance(data, dict) else []
        return [n for n in nodes if isinstance(n, dict)]

    def screenshot(self, path: Path, density: int = DEFAULT_DENSITY) -> Dict[str, Any]:
        return self.call("screenshot", str(path), "--normalize-status-bar", "--pixel-density", str(density))


#: The only labels that may match a button carrying a badge suffix ("Chores, 6 overdue"): the tab bar and the Quick Links
#: navigation. Every other label needs an exact match, so a room tile ("Master Bedroom, 3 on") is never found by its bare name.
NAV_LABELS = frozenset({"Home", "Rooms", "Settings", "Quick Links", "Chores", "Security", "Climate", "Vacuums", "Media", "To-Do",
                        "Food & Recipes", "Vacation", "Sprinklers", "Groceries"})


class AmbiguousLabel(Exception):
    """Several badged buttons match one navigation label; none is pressed."""


def button_centre(nodes: Sequence[Mapping[str, Any]], label: str, badged: bool = False) -> Optional[Tuple[float, float]]:
    """Centre (points) of the button named ``label``: an exact label first; with ``badged`` (navigation labels only), a single
    button with a badge suffix after a comma. Several badged matches raise :class:`AmbiguousLabel`: never the first."""
    buttons = [n for n in nodes if _node_role(n).lower() == "button" and _node_rect(n) and _label(n)]
    exact = [n for n in buttons if _label(n) == label]
    near = [n for n in buttons if _label(n).startswith(label + ",")] if badged and not exact else []
    if len(near) > 1:
        raise AmbiguousLabel(f"{len(near)} badged buttons match {label!r}")
    for node in exact or near:
        rect = _node_rect(node)
        if rect and rect["width"] > 0 and rect["height"] > 0:
            return rect["x"] + rect["width"] / 2, rect["y"] + rect["height"] / 2
    return None


# MARK: - Reaching a surface

@dataclass
class ReachPlan:
    """How one app reaches one surface: ``deeplink`` (url), ``steps`` (press labels), ``gallery`` (page) or ``skip`` (reason)."""
    method: str
    url: str = ""
    steps: List[str] = field(default_factory=list)
    page: str = ""
    reason: str = ""


#: The header button that opens the Quick Links sheet; a reach step "manual: ... Quick Links button" means pressing it.
QUICK_LINKS = "Quick Links"


def _as_press(step: Mapping[str, Any]) -> Mapping[str, Any]:
    """A manual step that only names the Quick Links button becomes a press of it; any other step is unchanged."""
    manual = str(step.get("manual", ""))
    return {"press": QUICK_LINKS} if "press" not in step and "Quick Links button" in manual else step


def write_opening_labels(surfaces: Sequence[Mapping[str, Any]]) -> FrozenSet[str]:
    """Every label whose press opens a ``writes_on_reach`` surface: the last press step of each such surface, in either app.
    Pressing one on live (a room tile writes a visit) is never allowed, whichever surface the step belongs to."""
    labels = set()
    for surface in surfaces:
        if surface.get("writes_on_reach"):
            for steps in (surface.get("reach") or {}).values():
                presses = [str(s["press"]) for s in (_as_press(s) for s in steps or []) if "press" in s]
                labels.update(presses[-1:])
    return frozenset(labels)


def plan_reach(surface: Mapping[str, Any], app: str, mode: str, guarded: FrozenSet[str] = frozenset()) -> ReachPlan:
    """Choose the reach for ``app`` (``reference`` or ``candidate``) in ``mode`` (``gallery``, ``fixture`` or ``live``).

    A ``writes_on_reach`` surface is deep-linked or skipped. Otherwise: the reference in gallery mode opens its gallery page;
    fully automatable press steps come next (in every mode, live included; a lone Quick Links step starts from Home); a deep
    link is the fallback when the steps cannot be pressed; a surface with neither is skipped.
    """
    link = (surface.get("deep_link") or {}).get(app)
    steps = [_as_press(s) for s in (surface.get("reach") or {}).get(app) or []]
    pressable = bool(steps) and all("press" in s for s in steps)
    # Any guarded step, pressable plan or not, sends the surface to its deep link (or skips it): press steps never run first.
    if surface.get("writes_on_reach") or guarded.intersection(s["press"] for s in steps if "press" in s):
        if link:
            return ReachPlan("deeplink", url=link)
        reason = "writes_on_reach and no deep link" if surface.get("writes_on_reach") else "a step opens a writes_on_reach surface and there is no deep link"
        return ReachPlan("skip", reason=reason)
    if mode == "gallery" and app == "reference":
        page = surface.get("gallery_page")
        return ReachPlan("gallery", page=page) if page else ReachPlan("skip", reason="no reference gallery page")
    if pressable:
        labels = [s["press"] for s in steps]
        # Quick Links lives on the Home tab: start there, so the previous surface never hides the button.
        return ReachPlan("steps", steps=(["Home"] + labels) if labels[0] == QUICK_LINKS else labels)
    if mode == "live" and link:
        return ReachPlan("deeplink", url=link)
    if link:
        return ReachPlan("deeplink", url=link)
    return ReachPlan("skip", reason="reach steps are not automatable and there is no deep link")


def perform_reach(agent: Agent, plan: ReachPlan, surface: Mapping[str, Any], guarded: FrozenSet[str] = frozenset()) -> bool:
    """Carry out ``plan``; ``True`` when it ran. A surface that writes on reach, or a step that opens one (``guarded``), is never
    pressed, whatever the plan says; an ambiguous badged label stops the reach."""
    if plan.method == "deeplink":
        agent.open_url(plan.url)
        if "Open" in agent.labels():  # the simulator asks before opening an app link; answering it writes nothing
            agent.press("Open")
            agent.settle()
    elif plan.method == "steps":
        if surface.get("writes_on_reach") or guarded.intersection(plan.steps):
            return False
        for label in plan.steps:
            if agent.press(label).get("ambiguous"):
                return False
            agent.settle()
            if label == QUICK_LINKS and "Rooms" not in agent.labels():  # the first press can miss; never press twice blindly
                agent.press(label)
                agent.settle()
    elif plan.method != "gallery":  # the gallery page is chosen at launch; nothing to do here
        return False
    return True


# MARK: - Accessibility tree

def _node_rect(node: Mapping[str, Any]) -> Optional[Dict[str, float]]:
    rect = node.get("rect") or node.get("frame")
    if isinstance(rect, dict) and all(k in rect for k in ("x", "y", "width", "height")):
        return {k: float(rect[k]) for k in ("x", "y", "width", "height")}
    return None


def _node_role(node: Mapping[str, Any]) -> str:
    return str(node.get("type") or node.get("role") or "").strip()


def _label(node: Mapping[str, Any]) -> str:
    return str(node.get("label") or node.get("identifier") or "").strip()


def is_status_bar(node: Mapping[str, Any]) -> bool:
    if _node_role(node).lower().replace("_", "") in STATUS_BAR_TYPES:
        return True
    rect = _node_rect(node)
    return bool(rect and rect["y"] + rect["height"] <= STATUS_BAR_BAND_PT and re.fullmatch(r"\d{1,2}:\d{2}.*", _label(node)))


def value_class(value: Any) -> str:
    text = "" if value is None else str(value).strip()
    if not text:
        return ""
    return "num" if re.fullmatch(r"[-+]?[\d.,%°\s]+\w{0,3}", text) else "text"


#: The system scroll bar's label counts the page's length ("Vertical scroll bar, 2 pages"): content height, not a control.
SCROLL_BAR = re.compile(r"^(vertical|horizontal) scroll bar\b", re.I)


def _text(node: Mapping[str, Any], key: str) -> str:
    return str(node.get(key) or "").strip()


def _ax_label(node: Mapping[str, Any]) -> str:
    """A node's accessibility label only: unlike :func:`_label` there is no fall back to the identifier, which is an engineering
    name (``home.weather``) that the two apps do not share and no user reads."""
    return _text(node, "label")


def is_noise(node: Mapping[str, Any]) -> bool:
    """A node the AX compare never sees: the status bar, a scroll bar (its label holds a page count), and an identifier-only node
    (no label and no value: a container or wrapper that exists for the test harness)."""
    if is_status_bar(node):
        return True
    label = _ax_label(node)
    if SCROLL_BAR.match(label):
        return True
    return not label and not _text(node, "value")


def _frame(node: Mapping[str, Any]) -> Optional[List[float]]:
    rect = _node_rect(node)
    return [round(rect[k], 2) for k in ("x", "y", "width", "height")] if rect else None


def dropped_indexes(nodes: Sequence[Mapping[str, Any]], mask_rules: Sequence[Mapping[str, Any]]) -> Set[int]:
    """Indexes of the nodes a ``drop`` rule removes from the compared AX sequence.

    ``"drop": "within"`` removes each matching node and every node whose frame lies inside its frame (a bar and its buttons: the
    shell chrome a page-region compare leaves out); ``"drop": "node"`` removes only the matching nodes. The frames come from the
    AX tree, never from fixed pixel rows.
    """
    gone: Set[int] = set()
    for rule in mask_rules:
        mode = rule.get("drop")
        if not mode:
            continue
        for index, node in enumerate(nodes):
            if not _matches(rule, node):
                continue
            gone.add(index)
            outer = _node_rect(node)
            if mode == "within" and outer:
                gone.update(j for j, other in enumerate(nodes)
                            if j != index and (inner := _node_rect(other)) is not None and _rect_contains(outer, inner))
    return gone


def normalize_ax(nodes: Sequence[Mapping[str, Any]], mask_rules: Sequence[Mapping[str, str]] = ()) -> List[Dict[str, Any]]:
    """The compared AX sequence: role, label, value class, enabled, selected, traits and frame (points).

    Dropped: status-bar nodes, scroll bars and identifier-only nodes (:func:`is_noise`). Accessibility identifiers are never
    recorded. A label matching a mask rule's ``ax_match`` becomes :data:`DYNAMIC_TOKEN`. Order is kept, so a reordered tree differs;
    frames are compared with a tolerance by ``tools/expo_pair_compare.py``.
    """
    patterns = [re.compile(r["ax_match"]) for r in mask_rules if r.get("ax_match")]
    dropped = dropped_indexes(nodes, mask_rules)
    out: List[Dict[str, Any]] = []
    for index, node in enumerate(nodes):
        if is_noise(node) or index in dropped:
            continue
        label = _ax_label(node)
        if label and any(p.search(label) for p in patterns):
            label = DYNAMIC_TOKEN
        traits = node.get("traits")
        out.append({"role": _node_role(node), "label": label, "value": value_class(node.get("value")),
                    "enabled": node.get("enabled", True) is not False, "selected": bool(node.get("selected", False)),
                    "traits": sorted(str(t) for t in traits) if isinstance(traits, (list, tuple)) else [], "frame": _frame(node)})
    return out


def _matches(rule: Mapping[str, str], node: Mapping[str, Any]) -> bool:
    """Does ``node`` match ``rule``? A rule names any of ``ax_match`` (the label), ``ax_identifier``, ``ax_value`` and ``ax_type`` (the
    node's type, such as ``NavigationBar``); one hit is enough. The identifier, value and type forms let a rule find a node that
    carries no label."""
    for key, field in (("ax_match", "label"), ("ax_identifier", "identifier"), ("ax_value", "value"), ("ax_type", "type")):
        pattern, text = rule.get(key), _text(node, field)
        if pattern and text and re.search(pattern, text):
            return True
    return False


def _rect_contains(outer: Mapping[str, float], inner: Mapping[str, float]) -> bool:
    return (outer["x"] <= inner["x"] + 0.5 and outer["y"] <= inner["y"] + 0.5
            and outer["x"] + outer["width"] >= inner["x"] + inner["width"] - 0.5
            and outer["y"] + outer["height"] >= inner["y"] + inner["height"] - 0.5)


def _has_matching_descendant(nodes: Sequence[Mapping[str, Any]], index: int, matched: Sequence[bool]) -> bool:
    """Is any node below ``nodes[index]`` in the tree a match? Uses ``depth`` (the dump is pre-order: the nodes after a node and
    deeper than it are its descendants); without depths, a matching node whose frame lies inside this one's counts (conservative: it
    errs toward masking less)."""
    depth = nodes[index].get("depth")
    if isinstance(depth, int) and all(isinstance(n.get("depth"), int) for n in nodes):
        for follower in range(index + 1, len(nodes)):
            if nodes[follower]["depth"] <= depth:
                return False
            if matched[follower]:
                return True
        return False
    outer = _node_rect(nodes[index])
    return bool(outer) and any(matched[j] and j != index and (inner := _node_rect(nodes[j])) is not None
                               and _rect_contains(outer, inner) and inner != outer for j in range(len(nodes)))


def resolve_masks(nodes: Sequence[Mapping[str, Any]], mask_rules: Sequence[Mapping[str, str]]) -> List[Dict[str, Any]]:
    """Live regions (points) for the nodes a mask rule matches; compare applies them to both halves.

    Only **leaf** matches count: a node with a matching node below it (a card whose text also matches) is skipped, so a mask
    covers the values that change and never the container around them. The compare's cap then applies to the union of these leaf
    boxes. The same box found twice is kept once.
    """
    regions: List[Dict[str, Any]] = []
    for rule in mask_rules:
        if rule.get("ax_only"):  # a rule that only drops nodes from the AX compare has no pixel region
            continue
        matched = [_matches(rule, n) and _node_rect(n) is not None for n in nodes]
        for index, node in enumerate(nodes):
            if matched[index] and not _has_matching_descendant(nodes, index, matched):
                region = {"label": rule["label"], **(_node_rect(node) or {}), "unit": "pt"}
                if region not in regions:
                    regions.append(region)
    return regions


# MARK: - Floating controls over the content

#: AX types of a scrolling container; the largest one on screen is the page's main scroll view.
SCROLL_TYPES = frozenset({"scrollview", "collectionview", "tableview"})
#: Bars whose buttons are chrome, never a floating control.
CHROME_TYPES = frozenset({"navigationbar", "tabbar", "toolbar", "statusbar"})


def _area(rect: Mapping[str, float]) -> float:
    return rect["width"] * rect["height"]


def _overlap(a: Mapping[str, float], b: Mapping[str, float]) -> float:
    """The area where two rectangles intersect (0 when they do not)."""
    width = min(a["x"] + a["width"], b["x"] + b["width"]) - max(a["x"], b["x"])
    height = min(a["y"] + a["height"], b["y"] + b["height"]) - max(a["y"], b["y"])
    return max(width, 0.0) * max(height, 0.0)


def _ancestors(nodes: Sequence[Mapping[str, Any]], index: int) -> List[int]:
    """Indexes above ``nodes[index]``, nearest first, from ``parentIndex`` (or the ``depth`` order of a pre-order dump)."""
    out: List[int] = []
    node = nodes[index]
    while isinstance(node.get("parentIndex"), int) and 0 <= node["parentIndex"] < len(nodes) and node["parentIndex"] != index:
        index = node["parentIndex"]
        out.append(index)
        node = nodes[index]
    return out


def floating_overlaps(nodes: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    """Does a floating control cover the last content the page can scroll to? Read from the AX tree only.

    * the **scroll view** is the largest scrolling container (:data:`SCROLL_TYPES`) on screen;
    * the **last content element** is the labelled leaf below it with the lowest bottom edge (scroll bars and unlabelled wrappers
      do not count);
    * a **floating control** is a button that is not inside the scroll view or a bar (:data:`CHROME_TYPES`), has a frame, and
      overlaps the scroll view's frame: it floats over the page;
    * ``intersects`` is true when a floating control's frame overlaps the last content element's frame. ``covers`` lists every
      content leaf a floating control overlaps, so a partly hidden list shows up even when the last row is clear.

    Returns ``{"scrollView", "lastContent", "floating", "intersects", "covers"}`` (frames ``[x, y, width, height]`` in points), or
    ``{"scrollView": None, ...}`` when the tree has no scroll view or no content.
    """
    rects = [_node_rect(n) for n in nodes]
    scrolls = [i for i, n in enumerate(nodes) if _node_role(n).lower() in SCROLL_TYPES and rects[i] and _area(rects[i]) > 0]
    empty: Dict[str, Any] = {"scrollView": None, "lastContent": None, "floating": [], "intersects": False, "covers": []}
    if not scrolls:
        return empty
    main = max(scrolls, key=lambda i: _area(rects[i]))
    children = {i for i in range(len(nodes)) if i != main and main in _ancestors(nodes, i)}
    has_child = {nodes[i]["parentIndex"] for i in children if isinstance(nodes[i].get("parentIndex"), int)}
    leaves = [i for i in children if i not in has_child and rects[i] and _area(rects[i]) > 0 and _ax_label(nodes[i])
              and not SCROLL_BAR.match(_ax_label(nodes[i]))]
    if not leaves:
        return {**empty, "scrollView": _frame(nodes[main])}
    last = max(leaves, key=lambda i: (rects[i]["y"] + rects[i]["height"], rects[i]["x"]))
    floating = []
    for i, node in enumerate(nodes):
        if i == main or i in children or rects[i] is None or _area(rects[i]) <= 0 or _node_role(node).lower() != "button":
            continue
        if any(_node_role(nodes[a]).lower() in CHROME_TYPES for a in _ancestors(nodes, i)):
            continue
        if _overlap(rects[i], rects[main]) > 0:
            floating.append(i)
    covers = [{"control": _ax_label(nodes[f]), "label": _ax_label(nodes[i]), "frame": _frame(nodes[i])}
              for f in floating for i in sorted(leaves) if _overlap(rects[f], rects[i]) > 0]
    return {"scrollView": _frame(nodes[main]), "lastContent": {"label": _ax_label(nodes[last]), "frame": _frame(nodes[last])},
            "floating": [{"label": _ax_label(nodes[f]), "frame": _frame(nodes[f])} for f in floating],
            "intersects": any(_overlap(rects[f], rects[last]) > 0 for f in floating), "covers": covers}


# MARK: - One shot

@dataclass
class Shot:
    png: Path
    ax: Path
    masks: Path
    ok: bool
    problem: str = ""
    #: The screenshot itself was taken (so the status bar was normalised); independent of the AX snapshot.
    screenshot_ok: bool = True


def capture_shot(agent: Agent, out_dir: Path, name: str, mask_rules: Sequence[Mapping[str, str]] = (),
                 density: int = DEFAULT_DENSITY) -> Shot:
    """Settle, snapshot, screenshot: writes ``<name>.png``, ``<name>.ax.json`` (raw and normalised nodes) and ``<name>.masks.json``."""
    out_dir.mkdir(parents=True, exist_ok=True)
    png, ax, masks = out_dir / f"{name}.png", out_dir / f"{name}.ax.json", out_dir / f"{name}.masks.json"
    agent.settle()
    nodes = agent.snapshot()
    shot = agent.screenshot(png, density)
    write_json(ax, {"labels": [_ax_label(n) for n in nodes if _ax_label(n)], "nodes": nodes, "normalized": normalize_ax(nodes, mask_rules)})
    write_json(masks, resolve_masks(nodes, mask_rules))
    problem = ""
    taken = bool(shot.get("success")) and png.is_file() and png_size(png) is not None
    if not taken:
        problem = "screenshot failed"
    elif not nodes:
        problem = "empty AX snapshot"
    return Shot(png, ax, masks, not problem, problem, taken)
