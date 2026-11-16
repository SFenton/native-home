#!/usr/bin/env python3
"""Judge "matches the Expo crawl": compare paired reference and candidate captures against the native-ingest gate.

The gate (``build/decisions/native-ingest.md`` default 2), applied to every pair:

1. both frames have the same size, else the pair fails;
2. a pixel *differs* when any channel differs by more than ``--tolerance`` (default 8 of 255);
3. the status-bar band, the home-indicator band and any region the case declares live are masked (never differing);
4. at most ``--max-diff-percent`` (default 1.0) of the frame may differ;
5. no 8-connected block of differing pixels may exceed ``--max-block-percent`` (default 0.25) of the frame;
6. the accessibility labels a capture's ``postconditions`` record on both sides must be equal (a side with none is skipped).

Two input forms (the second also accepts ``--scan ROOT``)::

    expo_pair_compare.py REFERENCE_DIR CANDIDATE_DIR --out OUT [--markdown FILE]
    expo_pair_compare.py --manifest PAIRS.json --out OUT [--markdown FILE]

``REFERENCE_DIR`` and ``CANDIDATE_DIR`` are Expo Explore capture folders (``case.json`` and ``screen-map.json``, with
``artifacts/`` beside them). Their plan's ``capture`` steps are paired by name and order. A manifest is
``{"pairs": [{"id", "reference", "candidate"}]}`` (two folders) or ``{"id", "reference_png", "candidate_png"}`` with optional
``reference_ax``/``candidate_ax`` label lists, ``live_regions`` and ``status_bar_pt``; relative paths resolve from the manifest.

A case may declare ``liveRegions``: ``[{"label", "x", "y", "width", "height", "unit": "pt"|"px"}]`` (points by default).

Writes ``OUT/<pair>.json`` and ``OUT/<pair>-diff.png`` per pair, plus ``OUT/results.json``. Exits 1 when any pair fails,
2 on unusable input. Python 3 standard library plus Pillow.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from PIL import Image, ImageChops

#: Default gate numbers (``build/decisions/native-ingest.md`` default 2).
TOLERANCE = 8
MAX_DIFF_PERCENT = 1.0
MAX_BLOCK_PERCENT = 0.25
#: Default status-bar band height in points (clock, signal, battery). Declared, not inferred.
STATUS_BAR_PT = 54.0
#: Default home-indicator band height in points, at the bottom edge. System chrome, like the status bar.
HOME_INDICATOR_PT = 34.0

Rect = Tuple[int, int, int, int]  # x0, y0, x1, y1 (exclusive)


# MARK: - Reading a capture folder

def _json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def plan_captures(case: Dict[str, Any]) -> List[Dict[str, str]]:
    """The ordered ``capture`` steps of a case's plan, falling back to its ``postconditions``."""
    steps = [s for s in (case.get("plan") or {}).get("steps", []) if "capture" in s]
    if steps:
        return [{"capture": s["capture"], "state": s.get("state", "")} for s in steps]
    return [{"capture": p["capture"], "state": p.get("state", "")} for p in case.get("postconditions", [])]


def capture_observations(folder: Path, captures: List[Dict[str, str]]) -> Dict[int, Optional[Path]]:
    """Map each plan capture (by index) to its screenshot in ``folder``'s ``screen-map.json``.

    A capture belongs to the screen titled with its name. Observations with a screenshot are walked in time order, runs of
    the same title and image collapse, and the captures are matched from the last backwards, each taking the latest
    observation of its title before the one the next capture took. Arrival shots and action echoes (``Title -> action``)
    are therefore skipped, and a title shared by several captures resolves in plan order.
    """
    mapping = _json(folder / "screen-map.json")
    artifacts = {a["id"]: a for a in mapping.get("artifacts", [])}
    titles = {s["id"]: s.get("title", "") for s in mapping.get("screens", [])}
    seq: List[Tuple[str, Path]] = []
    for obs in sorted(mapping.get("observations", []), key=lambda o: o.get("capturedAt", "")):
        art = artifacts.get(obs.get("screenshotArtifactId", ""))
        if not art:
            continue
        entry = (titles.get(obs["screenId"], ""), folder / art["path"])
        if not seq or seq[-1] != entry:
            seq.append(entry)
    out: Dict[int, Optional[Path]] = {i: None for i in range(len(captures))}
    limit = len(seq)
    for index in range(len(captures) - 1, -1, -1):
        for pos in range(limit - 1, -1, -1):
            if seq[pos][0] == captures[index]["capture"]:
                out[index], limit = seq[pos][1], pos
                break
    return out


def declared_labels(case: Dict[str, Any], capture: str, state: str) -> Optional[List[str]]:
    """The AX nodes a case records for ``capture``/``state`` as sorted ``label|flags`` strings, or ``None`` if unrecorded."""
    for post in case.get("postconditions", []):
        if post.get("capture") == capture and post.get("state", "") == state:
            nodes = post.get("nodes")
            if nodes is None:
                return None
            return sorted(json.dumps(n, sort_keys=True) for n in nodes)
    return None


# MARK: - Masks

def _rect(region: Dict[str, Any], density: float, size: Tuple[int, int]) -> Rect:
    scale = 1.0 if region.get("unit") == "px" else density
    x0 = max(0, int(region["x"] * scale))
    y0 = max(0, int(region["y"] * scale))
    x1 = min(size[0], int((region["x"] + region["width"]) * scale + 0.999))
    y1 = min(size[1], int((region["y"] + region["height"]) * scale + 0.999))
    return (x0, y0, x1, y1)


def mask_rects(size: Tuple[int, int], density: float, status_bar_pt: float,
               live_regions: List[Dict[str, Any]], home_indicator_pt: float = HOME_INDICATOR_PT) -> List[Tuple[str, Rect]]:
    """The status-bar band across the top, the home-indicator band at the bottom, then each declared live region."""
    rects: List[Tuple[str, Rect]] = []
    if home_indicator_pt > 0:
        rects.append(("home-indicator", (0, max(0, size[1] - int(home_indicator_pt * density)), size[0], size[1])))
    if status_bar_pt > 0:
        rects.append(("status-bar", (0, 0, size[0], min(size[1], int(status_bar_pt * density)))))
    for region in live_regions:
        rects.append((region.get("label", "live-region"), _rect(region, density, size)))
    return rects


# MARK: - Pixels

def diff_mask(ref: Image.Image, cand: Image.Image, tolerance: int, masks: List[Tuple[str, Rect]]) -> Tuple[Image.Image, int]:
    """An ``L`` image, 255 where any channel differs by more than ``tolerance`` outside the masks, and the max channel delta."""
    delta = ImageChops.difference(ref.convert("RGB"), cand.convert("RGB"))
    r, g, b = delta.split()
    peak = ImageChops.lighter(ImageChops.lighter(r, g), b)
    maximum = peak.getextrema()[1]
    flagged = peak.point([255 if i > tolerance else 0 for i in range(256)])
    for _, rect in masks:
        flagged.paste(0, rect)
    return flagged, maximum


def _runs(data: bytes, width: int, height: int) -> List[List[Tuple[int, int]]]:
    pattern = re.compile(rb"\xff+")
    return [[m.span() for m in pattern.finditer(data, y * width, (y + 1) * width)] for y in range(height)]


def largest_block(flagged: Image.Image) -> int:
    """Size in pixels of the largest 8-connected block of flagged pixels (run-length union-find, no numpy)."""
    width, height = flagged.size
    data = flagged.tobytes()
    rows = _runs(data, width, height)
    parent: List[int] = []
    size: List[int] = []

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a: int, b: int) -> None:
        a, b = find(a), find(b)
        if a != b:
            parent[b] = a
            size[a] += size[b]

    previous: List[Tuple[int, int, int]] = []
    for y, spans in enumerate(rows):
        current: List[Tuple[int, int, int]] = []
        base = y * width
        for s, e in spans:
            ident = len(parent)
            parent.append(ident)
            size.append(e - s)
            current.append((s - base, e - base, ident))
        j = 0
        for s, e, ident in current:
            while j < len(previous) and previous[j][1] < s:  # previous run ends left of s-1 (8-connectivity)
                j += 1
            k = j
            while k < len(previous) and previous[k][0] <= e:
                union(ident, previous[k][2])
                k += 1
        previous = current
    return max((size[i] for i in range(len(parent)) if find(i) == i), default=0)


def write_diff_png(cand: Image.Image, flagged: Image.Image, masks: List[Tuple[str, Rect]], path: Path) -> None:
    """The candidate dimmed, masked regions tinted blue, differing pixels red."""
    base = Image.blend(cand.convert("RGB"), Image.new("RGB", cand.size, (0, 0, 0)), 0.65)
    for _, rect in masks:
        base.paste(Image.blend(base.crop(rect), Image.new("RGB", (rect[2] - rect[0], rect[3] - rect[1]), (40, 80, 200)), 0.5), rect[:2])
    base.paste(Image.new("RGB", cand.size, (255, 40, 40)), mask=flagged)
    base.save(path)


# MARK: - Comparing a pair

def compare_images(ref_path: Path, cand_path: Path, out_png: Path, *, density: float, status_bar_pt: float,
                   live_regions: List[Dict[str, Any]], home_indicator_pt: float = HOME_INDICATOR_PT, tolerance: int = TOLERANCE,
                   max_diff_percent: float = MAX_DIFF_PERCENT, max_block_percent: float = MAX_BLOCK_PERCENT) -> Dict[str, Any]:
    """Measure one image pair; the result holds the numbers, the gate flags and ``failures`` (empty when it passes)."""
    ref, cand = Image.open(ref_path), Image.open(cand_path)
    result: Dict[str, Any] = {"first": str(ref_path), "second": str(cand_path), "failures": []}
    if ref.size != cand.size:
        result.update(sizeFirst=list(ref.size), sizeSecond=list(cand.size), changedPixels=None, totalPixels=None)
        result["failures"].append(f"size {ref.size[0]}x{ref.size[1]} vs {cand.size[0]}x{cand.size[1]}")
        return result
    masks = mask_rects(ref.size, density, status_bar_pt, live_regions, home_indicator_pt)
    flagged, maximum = diff_mask(ref, cand, tolerance, masks)
    total = ref.size[0] * ref.size[1]
    changed = flagged.histogram()[255]
    block = largest_block(flagged) if changed else 0
    bounds = flagged.getbbox()
    pct, block_pct = 100.0 * changed / total, 100.0 * block / total
    result.update(
        changedPixels=changed, totalPixels=total, changedPercent=round(pct, 4), largestBlockPixels=block,
        largestBlockPercent=round(block_pct, 4), differenceBounds=list(bounds) if bounds else None,
        maximumChannelDifference=maximum, tolerance=tolerance, masks=[{"label": n, "rect": list(r)} for n, r in masks],
        diffImage=str(out_png))
    if pct > max_diff_percent:
        result["failures"].append(f"{pct:.2f}% of pixels differ (limit {max_diff_percent}%)")
    if block_pct > max_block_percent:
        result["failures"].append(f"a {block_pct:.2f}% block differs (limit {max_block_percent}%)")
    out_png.parent.mkdir(parents=True, exist_ok=True)
    write_diff_png(cand, flagged, masks, out_png)
    return result


def compare_ax(ref: Optional[List[str]], cand: Optional[List[str]]) -> Tuple[Optional[bool], List[str]]:
    """``(equal, failures)``; ``equal`` is ``None`` when either side records no labels, which is skipped, not failed."""
    if ref is None or cand is None:
        return None, []
    if ref == cand:
        return True, []
    only_ref, only_cand = sorted(set(ref) - set(cand)), sorted(set(cand) - set(ref))
    return False, [f"AX labels differ: {len(only_ref)} only in reference, {len(only_cand)} only in candidate"]


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "pair"


# MARK: - Pair sources

def pairs_from_folders(ref_dir: Path, cand_dir: Path, name: str) -> List[Dict[str, Any]]:
    """One pair spec per plan capture shared by two capture folders; unresolvable captures become failing specs."""
    rcase, ccase = _json(ref_dir / "case.json"), _json(cand_dir / "case.json")
    rcaps, ccaps = plan_captures(rcase), plan_captures(ccase)
    rshots, cshots = capture_observations(ref_dir, rcaps), capture_observations(cand_dir, ccaps)
    specs: List[Dict[str, Any]] = []
    for i, cap in enumerate(rcaps):
        spec: Dict[str, Any] = {
            "id": f"{name}-{i:02d}-{slug(cap['capture'])}-{slug(cap['state'])}", "capture": cap["capture"],
            "state": cap["state"], "reference_png": rshots.get(i),
            "candidate_png": cshots.get(i) if i < len(ccaps) and ccaps[i] == cap else None,
            "reference_ax": declared_labels(rcase, cap["capture"], cap["state"]),
            "candidate_ax": declared_labels(ccase, cap["capture"], cap["state"]),
            "density": float(rcase.get("pixelDensity", 3)), "pose": rcase.get("pose"),
            "live_regions": rcase.get("liveRegions", []) + ccase.get("liveRegions", []), "problems": []}
        if rcase.get("pose") != ccase.get("pose") or rcase.get("viewport") != ccase.get("viewport"):
            spec["problems"].append("pose or viewport differs between the cases")
        specs.append(spec)
    return specs


def pairs_from_manifest(path: Path) -> List[Dict[str, Any]]:
    """Expand a manifest into pair specs (see the module docstring)."""
    base = path.parent
    specs: List[Dict[str, Any]] = []
    for entry in _json(path).get("pairs", []):
        name = entry.get("id") or slug(entry.get("reference", entry.get("reference_png", "pair")))
        if "reference" in entry:
            sub = pairs_from_folders(base / entry["reference"], base / entry["candidate"], name)
            for spec in sub:
                spec["status_bar_pt"] = entry.get("status_bar_pt")
                spec["live_regions"] = spec["live_regions"] + entry.get("live_regions", [])
            specs.extend(sub)
        else:
            specs.append({
                "id": name, "capture": entry.get("capture", name), "state": entry.get("state", ""),
                "reference_png": base / entry["reference_png"], "candidate_png": base / entry["candidate_png"],
                "reference_ax": entry.get("reference_ax"), "candidate_ax": entry.get("candidate_ax"),
                "density": float(entry.get("density", 3)), "pose": entry.get("pose"),
                "live_regions": entry.get("live_regions", []), "status_bar_pt": entry.get("status_bar_pt"), "problems": []})
    return specs


def scan_pairs(root: Path) -> List[Dict[str, Any]]:
    """Pair every ``<root>/<run>/{reference,candidate}`` that has a ``case.json`` and ``screen-map.json`` on both sides."""
    specs: List[Dict[str, Any]] = []
    for ref in sorted(root.glob("*/reference")):
        cand = ref.parent / "candidate"
        if all((d / f).is_file() for d in (ref, cand) for f in ("case.json", "screen-map.json")):
            specs.extend(pairs_from_folders(ref, cand, ref.parent.name))
    return specs


# MARK: - Running

def judge(spec: Dict[str, Any], out_dir: Path, args: argparse.Namespace) -> Dict[str, Any]:
    """Compare one pair spec, write its JSON and diff PNG, and return the record."""
    record: Dict[str, Any] = {"id": spec["id"], "capture": spec["capture"], "state": spec["state"], "pose": spec.get("pose")}
    failures: List[str] = list(spec["problems"])
    ref_png, cand_png = spec["reference_png"], spec["candidate_png"]
    if not ref_png or not Path(ref_png).is_file():
        failures.append("reference screenshot not found")
    if not cand_png or not Path(cand_png).is_file():
        failures.append("candidate screenshot not found")
    if not failures:
        status = spec.get("status_bar_pt")
        pixel = compare_images(
            Path(ref_png), Path(cand_png), out_dir / f"{spec['id']}-diff.png", density=spec["density"],
            status_bar_pt=args.status_bar_pt if status is None else status, live_regions=spec["live_regions"],
            home_indicator_pt=args.home_indicator_pt, tolerance=args.tolerance, max_diff_percent=args.max_diff_percent, max_block_percent=args.max_block_percent)
        record.update(pixel)
        failures.extend(pixel["failures"])
    equal, ax_failures = compare_ax(spec["reference_ax"], spec["candidate_ax"])
    record["allAXNodesEqual"] = equal
    failures.extend(ax_failures)
    record["failures"] = failures
    record["verdict"] = "fail" if failures else "pass"
    (out_dir / f"{spec['id']}.json").write_text(json.dumps(record, indent=2, default=str) + "\n", encoding="utf-8")
    return record


def markdown(records: List[Dict[str, Any]]) -> str:
    """A table, one row per pair, with a pass count line."""
    lines = ["| Pair | Capture | State | Differs | Largest block | AX | Verdict | Why |", "|---|---|---|---|---|---|---|---|"]
    for r in records:
        pct = "n/a" if r.get("changedPercent") is None else f"{r['changedPercent']:.2f}%"
        blk = "n/a" if r.get("largestBlockPercent") is None else f"{r['largestBlockPercent']:.2f}%"
        ax = {True: "equal", False: "differs", None: "not recorded"}[r.get("allAXNodesEqual")]
        lines.append(f"| {r['id']} | {r['capture']} | {r['state']} | {pct} | {blk} | {ax} | {r['verdict']} | {'; '.join(r['failures'])} |")
    passed = sum(r["verdict"] == "pass" for r in records)
    lines.append("")
    lines.append(f"{passed} of {len(records)} pairs pass.")
    return "\n".join(lines) + "\n"


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", nargs="?", type=Path, help="reference capture folder")
    ap.add_argument("candidate", nargs="?", type=Path, help="candidate capture folder")
    ap.add_argument("--manifest", type=Path, help="pairs manifest JSON")
    ap.add_argument("--scan", type=Path, help="pair every <ROOT>/<run>/{reference,candidate}")
    ap.add_argument("--out", type=Path, required=True, help="directory for the per-pair JSON and diff PNG")
    ap.add_argument("--markdown", type=Path, help="write the markdown table here")
    ap.add_argument("--tolerance", type=int, default=TOLERANCE)
    ap.add_argument("--max-diff-percent", type=float, default=MAX_DIFF_PERCENT)
    ap.add_argument("--max-block-percent", type=float, default=MAX_BLOCK_PERCENT)
    ap.add_argument("--status-bar-pt", type=float, default=STATUS_BAR_PT, help="status-bar band height in points (0 disables)")
    ap.add_argument("--home-indicator-pt", type=float, default=HOME_INDICATOR_PT, help="home-indicator band height in points (0 disables)")
    args = ap.parse_args(argv)
    try:
        if args.manifest:
            specs = pairs_from_manifest(args.manifest)
        elif args.scan:
            specs = scan_pairs(args.scan)
        elif args.reference and args.candidate:
            specs = pairs_from_folders(args.reference, args.candidate, args.reference.parent.name or "pair")
        else:
            ap.error("give REFERENCE CANDIDATE, --manifest or --scan")
    except (OSError, KeyError, ValueError) as error:
        print(f"expo_pair_compare: unusable input: {error}", file=sys.stderr)
        return 2
    if not specs:
        print("expo_pair_compare: no pairs found", file=sys.stderr)
        return 2
    args.out.mkdir(parents=True, exist_ok=True)
    records = [judge(spec, args.out, args) for spec in specs]
    table = markdown(records)
    (args.out / "results.json").write_text(json.dumps(records, indent=2, default=str) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text(table, encoding="utf-8")
    print(table)
    return 1 if any(r["verdict"] == "fail" for r in records) else 0


if __name__ == "__main__":
    sys.exit(main())
