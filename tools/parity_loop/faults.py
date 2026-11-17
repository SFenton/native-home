#!/usr/bin/env python3
"""Stage an error, unavailable, offline, reconnecting, loading or empty state on both apps, then pair them through ``run.py``.

    faults.py matrix [--markdown FILE]
    faults.py run --device iphone --run NAME --surfaces chores --faults empty [run.py's device options]
    faults.py publish --run-dir DIR --out build/evidence/screens/parity-states-SHA

**Fixtures only.** A state is staged by what the apps read at launch, never by a write or a fault on a live connection (owner answer,
``build/decisions/parity-depth.md``: "No, fixtures only"):

* the reference reads ``variables`` (``FENTON_GALLERY_*``) and ``pauseContinuousAnimations`` from its gallery fixture
  ``bootstrap.json``;
* the candidate reads ``flags`` (the same names, in the preview's ``bootstrap.json``; the mapping lives in
  ``apple/Sources/HassUI/UIKitPort/ServerUI/README.md``, "Preview state flags") and the fixture ``entities``.

``run`` and ``publish`` both refuse live mode; the guard proxy's fault modes (drop, delay, refuse-read) are deliberately not built.
A reference gallery page honours a variable only on the pages named in :attr:`Fault.reference_pages` (read in the reference source);
elsewhere the reference has no mechanism and the row is ``no-reference`` (the Studio sim is the reference for it).

The pair itself is :func:`parity_loop.run.run_all`: reference, candidate, reference again, then the compare. Each fault is a derived
surface row ``<surface>.<fault>`` with a ``fault`` key that the launcher reads before every launch.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, FrozenSet, List, Mapping, Optional, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import png_raster  # noqa: E402
from parity_loop import launch as launch_mod  # noqa: E402
from parity_loop import run as run_mod  # noqa: E402
from parity_loop.capture import Agent, ReachPlan  # noqa: E402
from parity_loop.common import BUNDLE_ID, CANDIDATE, REFERENCE, REPO, read_json, run  # noqa: E402

PAIRED, NO_REFERENCE = "paired", "no-reference"
#: The most a gate delay may be on the candidate (``UKServerUIPreviewFlags.maximumGateDelayMs``).
MAX_GATE_DELAY_MS = 60_000


# MARK: - The fault table

@dataclass(frozen=True)
class Fault:
    """One staged state: how each side is told, and where the reference honours it."""
    id: str
    state_class: str
    reference_vars: Mapping[str, str]
    #: The candidate's ``flags`` object (``UKServerUIPreviewFlags`` keys).
    native_flags: Mapping[str, Any]
    #: Reference gallery pages (``gallery_page`` in ``surfaces.json``) that read ``reference_vars``.
    reference_pages: FrozenSet[str]
    reference_pause: bool = False
    #: Set every fixture entity's state to this on the candidate (``entities`` bootstrap), or ``None``.
    native_entity_state: Optional[str] = None
    note: str = ""


FAULTS: Dict[str, Fault] = {f.id: f for f in (
    Fault("offline", "offline", {"FENTON_GALLERY_OFFLINE": "1"}, {"connection": "offline"},
          frozenset({"shell-header", "media-remote"}), note="Profile offline badge; the reference reads it on the shell header and media remote galleries"),
    Fault("reconnecting", "offline", {"FENTON_GALLERY_RECONNECTING": "1"}, {"connection": "reconnecting", "animationsPaused": True},
          frozenset({"shell-header"}), reference_pause=True, note="lit arc beside Quick Links, arc held still on both sides"),
    Fault("unavailable", "unavailable", {"FENTON_GALLERY_SCENARIO": "unavailable"}, {}, frozenset({"security"}),
          native_entity_state="unavailable", note="alarm, locks and doors unavailable (dimmed tiles)"),
    Fault("error", "error", {"FENTON_GALLERY_FAIL": "1"}, {"failCalls": True}, frozenset({"security"}),
          note="every service call answers with an error; the capture shows the idle page, the failure shows after a control press"),
    Fault("error-complete", "error", {"FENTON_GALLERY_FAIL_COMPLETE": "1"}, {"failCalls": True}, frozenset({"chores"}),
          note="every check-off fails"),
    Fault("empty", "empty", {"FENTON_GALLERY_EMPTY": "1"}, {"empty": True}, frozenset({"chores", "vacation"}),
          note="every list holds no item"),
    Fault("loading", "loading", {"FENTON_GALLERY_GATE_DELAY_MS": "20000"}, {"gateDelayMs": 20000, "animationsPaused": True},
          frozenset({"performance"}), reference_pause=True, note="data arrives after 20 s; the shot is taken while the gate waits"),
)}
#: Every ``variables`` name a fault may set; a launch clears these before it sets the fault's own.
MANAGED_VARIABLES = frozenset(name for f in FAULTS.values() for name in f.reference_vars)
MANAGED_FLAGS = frozenset(key for f in FAULTS.values() for key in f.native_flags)


class Refused(launch_mod.Refused):
    """A staging the harness will not do."""


def check_fault(fault: Fault) -> None:
    """A gate delay beyond the candidate's maximum would be clamped on one side only; refuse it at definition use."""
    delay = fault.native_flags.get("gateDelayMs")
    if delay is not None and not 0 <= int(delay) <= MAX_GATE_DELAY_MS:
        raise Refused(f"fault {fault.id}: gateDelayMs must be 0 to {MAX_GATE_DELAY_MS}")
    reference = fault.reference_vars.get("FENTON_GALLERY_GATE_DELAY_MS")
    if reference is not None and delay is not None and int(reference) != int(delay):
        raise Refused(f"fault {fault.id}: the two sides must use one delay")


# MARK: - The matrix

def status_for(surface: Mapping[str, Any], fault: Fault) -> str:
    """``paired`` when the reference honours ``fault`` on this surface's gallery page, else ``no-reference``."""
    return PAIRED if surface.get("gallery_page") in fault.reference_pages else NO_REFERENCE


def matrix(surfaces: Sequence[Mapping[str, Any]]) -> List[Dict[str, Any]]:
    """One row per in-scope surface present in both apps and fault: its pairing status."""
    rows = []
    for surface in surfaces:
        if not surface.get("in_scope") or surface.get("presence") != "both" or surface.get("writes_on_reach"):
            continue
        for fault in FAULTS.values():
            rows.append({"surface": surface["id"], "gallery_page": surface.get("gallery_page"), "fault": fault.id,
                         "class": fault.state_class, "status": status_for(surface, fault)})
    return rows


def paired_rows(surfaces: Sequence[Mapping[str, Any]]) -> List[Dict[str, Any]]:
    return [row for row in matrix(surfaces) if row["status"] == PAIRED]


def matrix_markdown(surfaces: Sequence[Mapping[str, Any]]) -> str:
    """The fault table (mechanisms) and the pairs it yields over ``surfaces``."""
    lines = ["| Fault | Class | Reference variables | Candidate flags | Reference pages | Paired surfaces |", "|---|---|---|---|---|---|"]
    pairs = paired_rows(surfaces)
    for fault in FAULTS.values():
        ref = ", ".join(f"{k}={v}" for k, v in fault.reference_vars.items()) + (" + pauseContinuousAnimations" if fault.reference_pause else "")
        nat = json.dumps(dict(fault.native_flags), sort_keys=True) + (f" + entities {fault.native_entity_state}" if fault.native_entity_state else "")
        sids = sorted(p["surface"] for p in pairs if p["fault"] == fault.id)
        lines.append(f"| {fault.id} | {fault.state_class} | `{ref}` | `{nat}` | {', '.join(sorted(fault.reference_pages))} | {', '.join(sids) or 'none'} |")
    return "\n".join(lines) + "\n"


# MARK: - Staging

def stage_reference(data_dir: Path, page: str, fault: Optional[Fault]) -> None:
    """Rewrite the reference's gallery fixture: the page, every managed variable cleared, then ``fault``'s set (none: a clean state)."""
    folder = Path(data_dir) / launch_mod.FIXTURE_SUBPATH
    path = folder / "bootstrap.json"
    if not path.is_file():
        raise Refused("the reference has no gallery fixture bootstrap on this simulator")
    config = json.loads(path.read_text(encoding="utf-8"))
    variables = {k: v for k, v in (config.get("variables") or {}).items() if k not in MANAGED_VARIABLES}
    variables["FENTON_GALLERY"] = page
    config.pop("pauseContinuousAnimations", None)
    if fault:
        check_fault(fault)
        variables.update(fault.reference_vars)
        if fault.reference_pause:
            config["pauseContinuousAnimations"] = True
    config["variables"] = variables
    path.write_text(json.dumps(config, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    (folder / "receipt.json").unlink(missing_ok=True)


def stage_candidate(data_dir: Path, fault: Optional[Fault]) -> None:
    """Rewrite the preview ``bootstrap.json``: managed flags cleared, then ``fault``'s set; entities forced when the fault says so."""
    folder = Path(data_dir) / launch_mod.PREVIEW_SUBPATH
    path = folder / "bootstrap.json"
    if not path.is_file():
        raise Refused("the candidate has no preview bootstrap on this simulator (feed a publication first)")
    config = json.loads(path.read_text(encoding="utf-8"))
    original = config.pop("_pristine_entities", None)
    if original is not None:
        config["entities"] = original  # an earlier fault's entity change is undone before this one
    flags = {k: v for k, v in (config.get("flags") or {}).items() if k not in MANAGED_FLAGS}
    if fault:
        check_fault(fault)
        flags.update(fault.native_flags)
        if fault.native_entity_state and isinstance(config.get("entities"), dict):
            config["_pristine_entities"] = json.loads(json.dumps(config["entities"]))
            config["entities"] = {key: {**value, "state": fault.native_entity_state} if isinstance(value, dict) else value
                                  for key, value in config["entities"].items()}
    if flags:
        config["flags"] = flags
    else:
        config.pop("flags", None)
    path.write_text(json.dumps(config, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    (folder / "receipt.json").unlink(missing_ok=True)


def fault_launcher(faults: Mapping[str, Fault] = FAULTS):
    """A ``run.Context.launcher`` that stages the surface's ``fault`` on its half, then relaunches it in gallery mode."""
    def launcher(half: run_mod.Half, surface: Mapping[str, Any], plan: ReachPlan, ctx: run_mod.Context) -> None:
        if ctx.mode == "live":
            raise Refused("fault staging is fixtures only: live mode is refused")
        fault = faults[surface["fault"]]
        data = launch_mod.container(ctx.runner, half.udid, "data")
        if half.side == REFERENCE:
            stage_reference(data, plan.page or surface.get("gallery_page") or "", fault)
        else:
            stage_candidate(data, fault)
        half.agent.open_app(BUNDLE_ID, launch_mod.GALLERY_ARGS[half.side], relaunch=True)
    return launcher


def derive(surface: Mapping[str, Any], fault: Fault) -> Dict[str, Any]:
    """The surface row a fault run captures: id ``<surface>.<fault>``, the fault in its ``fault`` key and state tags."""
    row = dict(surface)
    row.update(id=f"{surface['id']}.{fault.id}", fault=fault.id, base_surface=surface["id"],
               state_tags=list(surface.get("state_tags") or []) + [f"fault:{fault.id}"])
    return row


def run_faults(ctx: run_mod.Context, surfaces: Sequence[Mapping[str, Any]], fault_ids: Sequence[str],
               pin_hash: Optional[str] = None, env: Optional[Mapping[str, str]] = None, pin_path: Path = run_mod.DEFAULT_PIN,
               inventory: Optional[Sequence[Mapping[str, Any]]] = None) -> int:
    """Pair every ``surface`` x ``fault`` the reference supports. Returns the compare's exit status (2 when nothing is paired)."""
    if ctx.mode == "live":
        raise Refused("fault staging is fixtures only: live mode is refused")
    unknown = [f for f in fault_ids if f not in FAULTS]
    if unknown:
        raise Refused(f"unknown fault(s): {', '.join(unknown)}")
    derived = [derive(s, FAULTS[f]) for s in surfaces for f in fault_ids if status_for(s, FAULTS[f]) == PAIRED]
    if not derived:
        raise Refused("no surface and fault pair: the reference has no mechanism for any of them (see `faults.py matrix`)")
    ctx.launcher = fault_launcher()
    try:
        return run_mod.run_all(ctx, derived, pin_hash, env, pin_path, inventory)
    finally:
        for side in (REFERENCE, CANDIDATE):  # leave both simulators in a clean state
            half = ctx.halves.get(side)
            if half is None:
                continue
            try:
                data = launch_mod.container(ctx.runner, half.udid, "data")
                if side == REFERENCE:
                    page = (surfaces[0].get("gallery_page") if surfaces else None) or "home"
                    stage_reference(data, page, None)
                else:
                    stage_candidate(data, None)
            except (launch_mod.Refused, OSError, ValueError):
                pass


# MARK: - Evidence

def side_by_side(reference: Path, candidate: Path, out: Path, gap: int = 12) -> Path:
    """Write ``reference | candidate`` as one PNG (the shorter half padded with black below)."""
    a, b = png_raster.read(reference), png_raster.read(candidate)
    height = max(a.height, b.height)
    width = a.width + gap + b.width
    rows = []
    for y in range(height):
        left = a.row(y) if y < a.height else bytes(a.width * 3)
        right = b.row(y) if y < b.height else bytes(b.width * 3)
        rows.append(left + bytes([40, 40, 40]) * gap + right)
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    png_raster.write(png_raster.Raster(width, height, b"".join(rows)), Path(out))
    return Path(out)


def publish(run_dir: Path, out_dir: Path, family: str, sha: str) -> List[Dict[str, str]]:
    """One side-by-side image per captured state under ``run_dir``, and ``index.md`` in ``out_dir``. Returns the index rows."""
    manifest = read_json(Path(run_dir) / "manifest.json")
    results: Dict[str, str] = {}
    results_file = Path(run_dir) / "results.json"
    if results_file.is_file():
        for record in read_json(results_file):
            results[str(record.get("id", ""))] = str(record.get("verdict", ""))
    rows = []
    for entry in manifest["pairs"]:
        sid = entry["id"]
        if entry.get("skipped") or not entry.get("reference_png"):
            rows.append({"id": sid, "image": "", "verdict": "skipped", "note": str(entry.get("skipped", ""))})
            continue
        name = f"{sid}-{family}.png".replace("/", "-")
        side_by_side(Path(run_dir) / entry["reference_png"], Path(run_dir) / entry["candidate_png"], Path(out_dir) / name)
        rows.append({"id": sid, "image": name, "verdict": results.get(sid, "unjudged"), "note": "; ".join(entry.get("problems") or [])})
    lines = [f"# Parity states: {family}, tool sha {sha}", "",
             "> **What:** one side-by-side per staged state, reference on the left, candidate on the right. Fixtures only; no live write, no live fault.", "",
             "| State | Verdict | Image | Note |", "|---|---|---|---|"]
    for row in rows:
        image = f"![{row['id']}]({row['image']})" if row["image"] else ""
        lines.append(f"| {row['id']} | {row['verdict']} | {image} | {row['note']} |")
    (Path(out_dir) / "index.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return rows


# MARK: - Command line

def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="verb", required=True)
    mx = sub.add_parser("matrix")
    mx.add_argument("--surfaces-file", type=Path, default=run_mod.SURFACES_FILE)
    mx.add_argument("--markdown", type=Path)
    rn = sub.add_parser("run")
    rn.add_argument("--device", choices=sorted(run_mod.DEVICES), default="iphone")
    rn.add_argument("--run", default=time.strftime("faults-%Y%m%d-%H%M%S"))
    rn.add_argument("--surfaces", required=True)
    rn.add_argument("--faults", required=True)
    rn.add_argument("--surfaces-file", type=Path, default=run_mod.SURFACES_FILE)
    rn.add_argument("--out", type=Path, default=run_mod.DEFAULT_OUT)
    rn.add_argument("--appearance", choices=("light", "dark"), default="dark")
    rn.add_argument("--reference-udid", required=True)
    rn.add_argument("--reference-agent", required=True)
    rn.add_argument("--candidate-udid", required=True)
    rn.add_argument("--candidate-agent", required=True)
    rn.add_argument("--publication", type=Path, help="candidate preview publication directory to feed before the run")
    rn.add_argument("--reference-pin", type=Path, default=run_mod.DEFAULT_PIN)
    pb = sub.add_parser("publish")
    pb.add_argument("--run-dir", type=Path, required=True)
    pb.add_argument("--out", type=Path, required=True)
    pb.add_argument("--family", choices=sorted(run_mod.DEVICES), default="iphone")
    args = ap.parse_args(argv)
    try:
        if args.verb == "matrix":
            text = matrix_markdown(read_json(args.surfaces_file)["surfaces"])
            if args.markdown:
                Path(args.markdown).write_text(text, encoding="utf-8")
            else:
                sys.stdout.write(text)
            return 0
        if args.verb == "publish":
            sha = run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"]).out.strip()
            publish(args.run_dir, args.out, args.family, sha)
            return 0
        halves = {REFERENCE: run_mod.Half(REFERENCE, args.reference_udid, Agent(args.reference_agent)),
                  CANDIDATE: run_mod.Half(CANDIDATE, args.candidate_udid, Agent(args.candidate_agent))}
        sha = run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"]).out.strip()
        ctx = run_mod.Context(args.out / args.run, "gallery", args.device, halves, appearance=args.appearance, tool_sha=sha)
        pin = None if str(args.reference_pin) == "none" else read_json(args.reference_pin)["bundleSHA256"]
        document = read_json(args.surfaces_file)
        surfaces = run_mod.select(document, args.surfaces.split(","))
        if args.publication:
            launch_mod.feed_preview(launch_mod.container(run, args.candidate_udid, "data"), args.publication)
        return run_faults(ctx, surfaces, args.faults.split(","), pin, pin_path=args.reference_pin, inventory=document["surfaces"])
    except (launch_mod.Refused, ValueError, OSError, KeyError) as error:
        print(f"faults: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
