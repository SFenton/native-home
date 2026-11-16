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
from typing import Any, Dict, List, Mapping, Optional, Sequence

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
        return self.call("press", f'label="{label}"')

    def settle(self) -> Dict[str, Any]:
        return self.call("wait", "stable", "1000", "15000")

    def appearance(self, mode: str) -> Dict[str, Any]:
        return self.call("settings", "appearance", mode)

    def snapshot(self) -> List[Dict[str, Any]]:
        data = self.call("snapshot").get("data") or {}
        nodes = data.get("nodes", []) if isinstance(data, dict) else []
        return [n for n in nodes if isinstance(n, dict)]

    def screenshot(self, path: Path, density: int = DEFAULT_DENSITY) -> Dict[str, Any]:
        return self.call("screenshot", str(path), "--normalize-status-bar", "--pixel-density", str(density))


# MARK: - Reaching a surface

@dataclass
class ReachPlan:
    """How one app reaches one surface: ``deeplink`` (url), ``steps`` (press labels), ``gallery`` (page) or ``skip`` (reason)."""
    method: str
    url: str = ""
    steps: List[str] = field(default_factory=list)
    page: str = ""
    reason: str = ""


def plan_reach(surface: Mapping[str, Any], app: str, mode: str) -> ReachPlan:
    """Choose the reach for ``app`` (``reference`` or ``candidate``) in ``mode`` (``gallery``, ``fixture`` or ``live``).

    A ``writes_on_reach`` surface is deep-linked or skipped. Otherwise: the reference in gallery mode opens its gallery page;
    live mode prefers a deep link; everything else prefers fully automatable press steps, then a deep link.
    """
    link = (surface.get("deep_link") or {}).get(app)
    steps = (surface.get("reach") or {}).get(app) or []
    pressable = bool(steps) and all("press" in s for s in steps)
    if surface.get("writes_on_reach"):
        if link:
            return ReachPlan("deeplink", url=link)
        return ReachPlan("skip", reason="writes_on_reach and no deep link")
    if mode == "gallery" and app == "reference":
        page = surface.get("gallery_page")
        return ReachPlan("gallery", page=page) if page else ReachPlan("skip", reason="no reference gallery page")
    if mode == "live" and link:
        return ReachPlan("deeplink", url=link)
    if pressable:
        return ReachPlan("steps", steps=[s["press"] for s in steps])
    if link:
        return ReachPlan("deeplink", url=link)
    return ReachPlan("skip", reason="reach steps are not automatable and there is no deep link")


def perform_reach(agent: Agent, plan: ReachPlan, surface: Mapping[str, Any]) -> bool:
    """Carry out ``plan``; ``True`` when it ran. A surface that writes on reach is never pressed, whatever the plan says."""
    if plan.method == "deeplink":
        agent.open_url(plan.url)
    elif plan.method == "steps":
        if surface.get("writes_on_reach"):
            return False
        for label in plan.steps:
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


def normalize_ax(nodes: Sequence[Mapping[str, Any]], mask_rules: Sequence[Mapping[str, str]] = ()) -> List[Dict[str, Any]]:
    """The compared AX sequence: role, label, value class, enabled and selected; status-bar nodes dropped; a label matching a
    mask rule becomes :data:`DYNAMIC_TOKEN`. Order is kept, so a reordered tree differs."""
    patterns = [re.compile(r["ax_match"]) for r in mask_rules]
    out: List[Dict[str, Any]] = []
    for node in nodes:
        if is_status_bar(node):
            continue
        label = _label(node)
        if label and any(p.search(label) for p in patterns):
            label = DYNAMIC_TOKEN
        out.append({"role": _node_role(node), "label": label, "value": value_class(node.get("value")),
                    "enabled": node.get("enabled", True) is not False, "selected": bool(node.get("selected", False))})
    return out


def resolve_masks(nodes: Sequence[Mapping[str, Any]], mask_rules: Sequence[Mapping[str, str]]) -> List[Dict[str, Any]]:
    """Live regions (points) for every node whose label matches a mask rule; compare applies them to both halves."""
    regions: List[Dict[str, Any]] = []
    for rule in mask_rules:
        pattern = re.compile(rule["ax_match"])
        for node in nodes:
            rect = _node_rect(node)
            if rect and _label(node) and pattern.search(_label(node)):
                regions.append({"label": rule["label"], **rect, "unit": "pt"})
    return regions


# MARK: - One shot

@dataclass
class Shot:
    png: Path
    ax: Path
    masks: Path
    ok: bool
    problem: str = ""


def capture_shot(agent: Agent, out_dir: Path, name: str, mask_rules: Sequence[Mapping[str, str]] = (),
                 density: int = DEFAULT_DENSITY) -> Shot:
    """Settle, snapshot, screenshot: writes ``<name>.png``, ``<name>.ax.json`` (raw and normalised nodes) and ``<name>.masks.json``."""
    out_dir.mkdir(parents=True, exist_ok=True)
    png, ax, masks = out_dir / f"{name}.png", out_dir / f"{name}.ax.json", out_dir / f"{name}.masks.json"
    agent.settle()
    nodes = agent.snapshot()
    shot = agent.screenshot(png, density)
    write_json(ax, {"labels": [_label(n) for n in nodes if _label(n)], "nodes": nodes, "normalized": normalize_ax(nodes, mask_rules)})
    write_json(masks, resolve_masks(nodes, mask_rules))
    problem = ""
    if not shot.get("success") or not png.is_file() or png_size(png) is None:
        problem = "screenshot failed"
    elif not nodes:
        problem = "empty AX snapshot"
    return Shot(png, ax, masks, not problem, problem)
