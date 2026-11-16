#!/usr/bin/env python3
"""Capture a reference and a candidate surface back to back, then gate the pair.

    run.py --mode gallery|fixture|live --device duo|iphone|ipad --run NAME --surfaces id[,id...]
           --reference-udid U --reference-agent CMD --candidate-udid U --candidate-agent CMD
           [--out build/evidence/parity-loop] [--publication DIR] [--reference-pin tools/expo_pairs/reference-pin.json]

For each surface the harness captures **reference, candidate, reference again**, each from a fresh launch: a PNG with the status
bar normalised, an AX dump and a sidecar (:mod:`parity_loop.sidecar`). A surface whose reach path writes to Home Assistant
(``writes_on_reach``) is reached by deep link, or recorded as skipped; it is never tapped. Everything lands in
``<out>/<run>/<surface>/``. Then ``tools/expo_pair_compare.py`` judges every pair with ``--require-sidecar --drift --require-ax
--status-bar-equal`` and writes ``results.json`` and ``results.md`` in the run folder.

Live mode needs ``PARITY_LIVE_GO=1`` and an output folder that git ignores (the shots hold house data). It never launches the
reference except through the guard proxy (see ``launch.py``); this driver only attaches, so start the apps with ``launch.py``. A live run
also takes ``--proxy-url`` and ``--proxy-cert`` and records, in every sidecar, the hash of the HA user the token resolves to.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, FrozenSet, List, Mapping, Optional, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import expo_pair_compare  # noqa: E402
from parity_loop import launch as launch_mod  # noqa: E402
from parity_loop import sidecar as sidecar_mod  # noqa: E402
from parity_loop.capture import Agent, ReachPlan, capture_shot, perform_reach, plan_reach, write_opening_labels  # noqa: E402
from parity_loop.common import APPS, BUNDLE_ID, CANDIDATE, REFERENCE, REPO, Runner, png_size, read_json, run, write_json  # noqa: E402

SURFACES_FILE = Path(__file__).resolve().parent / "surfaces.json"
DEFAULT_OUT = REPO / "build" / "evidence" / "parity-loop"
DEFAULT_PIN = REPO / "tools" / "expo_pairs" / "reference-pin.json"
MODES = ("gallery", "fixture", "live")

#: Device families: pixel scale, pose, and the screenshot size every capture must have (``None`` when not fixed).
DEVICES: Dict[str, Dict[str, Any]] = {
    "duo": {"scale": 3, "pose": "folded", "size": [1398, 2034]},
    "iphone": {"scale": 3, "pose": "portrait", "size": None},
    "ipad": {"scale": 2, "pose": "portrait", "size": None},
}
#: The order of one triple: ``(file stem, side)``.
SEQUENCE = (("reference", REFERENCE), ("candidate", CANDIDATE), ("reference2", REFERENCE))


# MARK: - Context

@dataclass
class Half:
    """One simulator and the bound ``agent-device`` that drives it."""
    side: str
    udid: str
    agent: Agent


@dataclass
class Context:
    """Everything one run shares."""
    run_dir: Path
    mode: str
    device: str
    halves: Dict[str, Half]
    runner: Runner = run
    appearance: str = "dark"
    tool_sha: str = ""
    bundle_hashes: Dict[str, str] = field(default_factory=dict)
    launcher: Optional[Callable[[Half, Mapping[str, Any], ReachPlan, "Context"], None]] = None
    status_bar_rects: Optional[Path] = None
    #: Labels whose press opens a ``writes_on_reach`` surface; :func:`run_all` always derives them from the full inventory, never
    #: from the surfaces selected for the run.
    guarded: FrozenSet[str] = frozenset()
    #: The TLS write-guard proxy both halves read through (live mode) and the certificate it made.
    proxy_url: Optional[str] = None
    proxy_cert: Optional[Path] = None
    #: Per half, the hash of the HA user id its session resolves to (``auth/current_user`` through the proxy); recorded in its sidecars.
    user_id_hashes: Dict[str, str] = field(default_factory=dict)

    @property
    def family(self) -> Dict[str, Any]:
        return DEVICES[self.device]


def default_launcher(half: Half, surface: Mapping[str, Any], plan: ReachPlan, ctx: Context) -> None:
    """Relaunch the half's app. The reference gets its gallery page in gallery mode; live apps are attached, not relaunched."""
    if ctx.mode == "live":
        half.agent.open_app(BUNDLE_ID, relaunch=False)
        return
    launch_mod.launch_gallery(half.side, half.agent, half.udid, plan.page or None, ctx.runner)


# MARK: - One surface

def mask_rules(surface: Mapping[str, Any]) -> List[Dict[str, str]]:
    return list(surface.get("masks") or [])


def run_surface(surface: Mapping[str, Any], ctx: Context) -> Dict[str, Any]:
    """Capture one triple for ``surface`` and return its manifest entry (``skipped`` set when it was not captured)."""
    sid = surface["id"]
    folder = ctx.run_dir / sid
    entry: Dict[str, Any] = {"id": sid, "capture": sid, "state": ",".join(surface.get("state_tags") or []), "surface": sid,
                             "density": ctx.family["scale"], "pose": ctx.family["pose"], "device": ctx.device}
    plans = {side: plan_reach(surface, side, ctx.mode, ctx.guarded) for side in APPS}
    skipped = [f"{side}: {p.reason}" for side, p in plans.items() if p.method == "skip"]
    if skipped:
        entry["skipped"] = "; ".join(skipped)
        entry.update(reference_png="", candidate_png="")
        write_json(folder / "skipped.json", {"surface": sid, "reason": entry["skipped"]})
        return entry
    launcher = ctx.launcher or default_launcher
    problems: List[str] = []
    for stem, side in SEQUENCE:
        half, plan = ctx.halves[side], plans[side]
        launcher(half, surface, plan, ctx)
        if not perform_reach(half.agent, plan, surface, ctx.guarded):
            problems.append(f"{stem}: reach did not run")
        shot = capture_shot(half.agent, folder, stem, mask_rules(surface), ctx.family["scale"])
        if not shot.ok:
            problems.append(f"{stem}: {shot.problem}")
        size = png_size(shot.png)
        if ctx.family["size"] and size and size != ctx.family["size"]:
            problems.append(f"{stem}: screenshot is {size[0]}x{size[1]}, expected {ctx.family['size'][0]}x{ctx.family['size'][1]}")
        launch_args, env_names = launch_mod.launch_record(ctx.mode, side)
        car = sidecar_mod.collect(
            half.udid, side, png=shot.png, scale=ctx.family["scale"], pose=ctx.family["pose"],  # appearance: measured, not requested
            source="live" if ctx.mode == "live" else "fixture", launch_args=launch_args, env_names=env_names,
            house=ctx.mode == "live", status_bar_normalized=shot.screenshot_ok, bundle_hash=ctx.bundle_hashes.get(side), runner=ctx.runner,
            tool_sha=ctx.tool_sha, extra={"surface": sid, "shot": stem, "reachMethod": plan.method, "userIdHash": ctx.user_id_hashes.get(side)})
        write_json(folder / f"{stem}.sidecar.json", car)
        entry[f"{stem}_png"] = f"{sid}/{stem}.png"
        entry[f"{stem}_sidecar"] = f"{sid}/{stem}.sidecar.json"
        entry[f"{stem}_ax_file"] = f"{sid}/{stem}.ax.json"
    entry["mask_files"] = [f"{sid}/reference.masks.json"] + ([f"{sid}/masks.json"] if (folder / "masks.json").is_file() else [])
    if problems:
        entry["problems"] = problems
    return entry


# MARK: - A run

def verify_pin(ctx: Context, pin_hash: Optional[str]) -> Optional[str]:
    """Hash both installed bundles into the context; an error text when the reference differs from its pin."""
    for side in APPS:
        ctx.bundle_hashes[side] = sidecar_mod.app_facts(ctx.runner, ctx.halves[side].udid)["bundleHash"]
    if pin_hash and ctx.bundle_hashes[REFERENCE] != pin_hash:
        return "the reference bundle does not match its pin"
    return None


def ensure_ignored(path: Path, runner: Runner = run) -> bool:
    """True when git ignores ``path`` (a live run's shots hold house data and must never be committable)."""
    return runner(["git", "-C", str(REPO), "check-ignore", "-q", str(path / "probe")]).code == 0


def select(document: Mapping[str, Any], ids: Optional[Sequence[str]]) -> List[Dict[str, Any]]:
    rows = document["surfaces"]
    if ids:
        known = {r["id"] for r in rows}
        missing = [i for i in ids if i not in known]
        if missing:
            raise ValueError(f"unknown surface id(s): {', '.join(missing)}")
        return [r for r in rows if r["id"] in ids]
    return [r for r in rows if r["in_scope"] and r["presence"] == "both"]


def run_all(ctx: Context, surfaces: Sequence[Mapping[str, Any]], pin_hash: Optional[str] = None,
            env: Optional[Mapping[str, str]] = None, pin_path: Path = DEFAULT_PIN,
            inventory: Optional[Sequence[Mapping[str, Any]]] = None) -> int:
    """Capture every surface, then judge them; the exit status is the compare tool's (0 pass, 1 fail, 2 refused).

    ``inventory`` is the full surface list the write guard is built from (default: the shipped ``surfaces.json``), whatever
    subset ``surfaces`` selects, so a selected bedroom sheet still knows which label opens a write surface.
    """
    environment = env if env is not None else os.environ
    launch_mod.require_hold(environment)
    if ctx.mode == "live":
        launch_mod.require_go(environment)
        if not ensure_ignored(ctx.run_dir, ctx.runner):
            raise launch_mod.Refused("live captures hold house data: the output folder must be ignored by git")
        for side in APPS:  # each half is asked as its own session, so a half signed in as another user is caught
            if side not in ctx.user_id_hashes:
                ctx.user_id_hashes[side] = launch_mod.resolve_identity(ctx.proxy_url, ctx.proxy_cert, ctx.runner, environment, side)
    ctx.guarded = ctx.guarded | write_opening_labels(read_json(SURFACES_FILE)["surfaces"] if inventory is None else inventory)
    ctx.run_dir.mkdir(parents=True, exist_ok=True)
    error = verify_pin(ctx, pin_hash)
    if error:
        raise launch_mod.Refused(error)
    for half in ctx.halves.values():
        if not half.agent.appearance(ctx.appearance).get("success"):
            raise launch_mod.Refused(f"could not set the {half.side} simulator to {ctx.appearance} appearance")
    entries = [run_surface(surface, ctx) for surface in surfaces]
    if pin_hash and sidecar_mod.app_facts(ctx.runner, ctx.halves[REFERENCE].udid)["bundleHash"] != pin_hash:
        raise launch_mod.Refused("the reference bundle changed during the run")
    write_json(ctx.run_dir / "manifest.json", {"pairs": entries})
    flags = ["--manifest", str(ctx.run_dir / "manifest.json"), "--out", str(ctx.run_dir / "compare"),
             "--markdown", str(ctx.run_dir / "results.md"), "--require-sidecar", "--drift", "--require-ax", "--status-bar-equal"]
    if ctx.status_bar_rects:
        flags += ["--status-bar-rects", str(ctx.status_bar_rects)]
    status = expo_pair_compare.main(flags + (["--reference-pin", str(pin_path)] if pin_hash else []))
    results = ctx.run_dir / "compare" / "results.json"
    if results.is_file():
        (ctx.run_dir / "results.json").write_text(results.read_text(encoding="utf-8"), encoding="utf-8")
    return status


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=MODES, default="gallery")
    ap.add_argument("--device", choices=sorted(DEVICES), default="duo")
    ap.add_argument("--run", default=time.strftime("run-%Y%m%d-%H%M%S"))
    ap.add_argument("--surfaces", help="comma-separated surface ids (default: every in-scope surface present in both apps)")
    ap.add_argument("--surfaces-file", type=Path, default=SURFACES_FILE)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--appearance", choices=("light", "dark"), default="dark")
    ap.add_argument("--reference-udid", required=True)
    ap.add_argument("--reference-agent", required=True, help="the bound agent-device command for the reference simulator")
    ap.add_argument("--candidate-udid", required=True)
    ap.add_argument("--candidate-agent", required=True, help="the bound agent-device command for the candidate simulator")
    ap.add_argument("--proxy-url", help="live mode: the TLS write-guard proxy both halves read through (https://127.0.0.1:PORT)")
    ap.add_argument("--proxy-cert", type=Path, help="live mode: the certificate the proxy made")
    ap.add_argument("--status-bar-rects", type=Path, help="calibrated status-bar item rectangles (points) passed to the compare")
    ap.add_argument("--publication", type=Path, help="candidate preview publication directory to feed before the run")
    ap.add_argument("--reference-pin", type=Path, default=DEFAULT_PIN, help="reference-pin.json ('none' to skip the pin check)")
    args = ap.parse_args(argv)
    halves = {REFERENCE: Half(REFERENCE, args.reference_udid, Agent(args.reference_agent)),
              CANDIDATE: Half(CANDIDATE, args.candidate_udid, Agent(args.candidate_agent))}
    sha = run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"]).out.strip()
    ctx = Context(args.out / args.run, args.mode, args.device, halves, appearance=args.appearance, tool_sha=sha,
                  status_bar_rects=args.status_bar_rects, proxy_url=args.proxy_url, proxy_cert=args.proxy_cert)
    try:
        pin = None if str(args.reference_pin) == "none" else read_json(args.reference_pin)["bundleSHA256"]
        document = read_json(args.surfaces_file)
        surfaces = select(document, args.surfaces.split(",") if args.surfaces else None)
        if args.publication:
            launch_mod.feed_preview(launch_mod.container(run, args.candidate_udid, "data"), args.publication)
        return run_all(ctx, surfaces, pin, pin_path=args.reference_pin, inventory=document["surfaces"])
    except (launch_mod.Refused, ValueError, OSError, KeyError) as error:
        print(f"run: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
