#!/usr/bin/env python3
"""UIKit-app coverage from the journeys, and the merge with the Mac-host report.

    tools/coverage_ios.py export PROFRAW_DIR --products X.xctestproducts --out ios.json
    tools/coverage_ios.py merge --out merged.json mac.json ios.json
    tools/coverage_ios.py top REPORT [--n 15] [--prefix apple/Sources/HassUI/UIKitPort]
    tools/coverage_ios.py baseline REPORT --json baseline.json --md coverage-baseline.md

Why: `swift test` runs on the Mac host, which cannot compile the iOS-only UIKit port
(`apple/Sources/HassUI/UIKitPort`), so those files have no record there. The UIKit app is exercised by the
XCUITest journeys against the instrumented app (`tools/ios_uitest.sh --impact DIR`, one profile per app launch).

``export`` merges every ``*.profraw`` of DIR (``llvm-profdata merge --input-files``) and runs ``llvm-cov export`` against
the instrumented app binaries inside the products bundle (the ``*_PackageProduct`` frameworks, ``FentonHome.debug.dylib`` and ``FentonHome``).
``merge`` writes one LLVM-format report with a record per source file: where a file is in both reports, the record with the
more covered lines wins (the same file can be compiled twice, for the Mac host and for iOS, with different ``#if`` arms and
line counts; neither can lower the other's number). ``tools/coverage_gate.py`` reads the result unchanged.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sh(*command: str) -> str:
    """Run a command, returning stdout; raise with stderr on failure."""
    done = subprocess.run(command, capture_output=True, text=True)
    if done.returncode != 0:
        raise RuntimeError(f"{' '.join(command[:3])}: {done.stderr.strip()[:600]}")
    return done.stdout


def app_binaries(products: Path) -> list[Path]:
    """The instrumented app executable and its debug dylib inside an .xctestproducts bundle."""
    apps = sorted(products.glob("Binaries/*/*/FentonHome.app"))
    if not apps:
        raise RuntimeError(f"{products}: no FentonHome.app under Binaries/")
    app = apps[0]
    # The package products (HassUI, which holds HassCore, HassDesign and the UIKit port) are dynamic frameworks in the app.
    frameworks = sorted(app.glob("Frameworks/*_PackageProduct.framework/*_PackageProduct"))
    return [path for path in [*frameworks, app / "FentonHome.debug.dylib", app / "FentonHome"] if path.is_file()]


SOURCE_PATH = re.compile(r"^.*?/(apple/(?:Sources|Apps|Tests)/.*)$")


def remap_to_root(payload: dict, root: Path = ROOT) -> dict[str, int]:
    """Rewrite source filenames from another worktree's checkout to `root`, in place.

    The products cache is keyed by content, not by worktree, so a reused bundle's coverage map carries the
    builder's absolute paths, which `coverage_gate` would drop as outside the root. SDK and toolchain paths
    (no `apple/Sources|Apps|Tests/` component) and paths already under `root` are left alone.

    Returns:
        Count of rewritten records per foreign prefix.
    """
    prefix = str(root)
    remapped: dict[str, int] = {}
    for group in payload.get("data", []):
        for item in group.get("files", []):
            name = item.get("filename", "")
            if name.startswith(prefix + "/"):
                continue
            match = SOURCE_PATH.match(name)
            if match:
                foreign = name[: match.start(1) - 1]
                item["filename"] = f"{prefix}/{match.group(1)}"
                remapped[foreign] = remapped.get(foreign, 0) + 1
    return remapped


def export(profraw_dir: Path, products: Path, out: Path, arch: str = "arm64") -> None:
    """Merge the journeys' profiles and export line coverage for the app binaries as one LLVM JSON file."""
    profiles = sorted(p for p in profraw_dir.glob("*.profraw") if p.stat().st_size > 0)
    if not profiles:
        raise RuntimeError(f"{profraw_dir}: no non-empty .profraw files (did the journeys run with --impact?)")
    with tempfile.TemporaryDirectory() as scratch:
        listing = Path(scratch) / "profiles.txt"
        listing.write_text("\n".join(map(str, profiles)) + "\n")
        merged = out.with_suffix(".profdata")
        sh("xcrun", "llvm-profdata", "merge", "-sparse", "--input-files", str(listing), "-o", str(merged))
    usable: list[Path] = []
    for binary in app_binaries(products):
        try:  # a binary without a coverage map (the thin launcher stub) is skipped
            sh("xcrun", "llvm-cov", "report", f"-instr-profile={merged}", f"-arch={arch}", str(binary), "--show-functions=false")
            usable.append(binary)
        except RuntimeError as error:
            print(f"skip {binary.name}: {error}", file=sys.stderr)
    if not usable:
        raise RuntimeError("no app binary has a coverage map; was the app built with CLANG_COVERAGE_MAPPING=YES?")
    objects = [str(usable[0])] + [arg for extra in usable[1:] for arg in ("-object", str(extra))]
    payload = json.loads(sh("xcrun", "llvm-cov", "export", "-format=text", f"-instr-profile={merged}", f"-arch={arch}", *objects))
    for foreign, count in remap_to_root(payload).items():
        print(f"remapped {count} records from {foreign}")
    out.write_text(json.dumps(payload))
    print(f"exported {len(profiles)} profiles from {profraw_dir} -> {out} ({', '.join(b.name for b in usable)})")


def file_records(path: Path) -> dict[str, dict]:
    payload = json.loads(path.read_text())
    records: dict[str, dict] = {}
    for group in payload["data"]:
        for item in group["files"]:
            name = item["filename"]
            lines = item["summary"]["lines"]
            old = records.get(name)
            if old is None or lines["covered"] > old["summary"]["lines"]["covered"]:
                records[name] = item
    return records


def merge(reports: list[Path], out: Path) -> None:
    """One report, one record per file, the record with the most covered lines."""
    best: dict[str, dict] = {}
    for report in reports:
        for name, item in file_records(report).items():
            old = best.get(name)
            if old is None or item["summary"]["lines"]["covered"] > old["summary"]["lines"]["covered"]:
                best[name] = item
    out.write_text(json.dumps({"type": "llvm.coverage.json.export", "version": "2.0.1", "data": [{"files": list(best.values())}]}))
    print(f"merged {len(reports)} reports -> {out} ({len(best)} files)")


def top(report: Path, n: int, prefix: str) -> None:
    """The n files under `prefix` with the most uncovered lines (files with no record are listed from disk, as 0 covered)."""
    rows = []
    for name, item in file_records(report).items():
        if prefix in name:
            lines = item["summary"]["lines"]
            rows.append((lines["count"] - lines["covered"], lines["covered"], lines["count"], name))
    rows.sort(reverse=True)
    for missed, covered, count, name in rows[:n]:
        short = name[name.rfind("apple/Sources/"):] if "apple/Sources/" in name else name
        print(f"{missed:6d} uncovered  {covered}/{count} = {covered * 100 / max(count, 1):5.1f}%  {short}")


def area_of(path: str) -> str:
    """The area folder of a source file: `HassUI/UIKitPort/App/Shell` -> `UIKitPort/App/Shell`; other modules by module and folder."""
    parts = path.split("/")[2:]  # drop apple/Sources
    if "UIKitPort" in parts:
        below = parts[parts.index("UIKitPort") + 1:-1]
        if below[:1] in (["App"], ["Features"]):
            return "UIKitPort/" + "/".join(below[:2])
        return "UIKitPort/" + (below[0] if below else "(root)")
    return "/".join(parts[:2]) if len(parts) > 2 else parts[0]


def is_gallery(path: str) -> bool:
    """Gallery-only code: fixture pages that only tests reach (the UIKit port's Gallery folder and the SwiftUI galleries)."""
    return "/Gallery/" in path or "Gallery" in Path(path).name


def baseline(report: Path, json_out: Path, md_out: Path | None) -> None:
    """The gate's numbers and a per-file table of every file with uncovered lines, grouped by area, from a merged report."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import coverage_gate

    rules = json.loads(coverage_gate.RULES.read_text())
    totals = coverage_gate.llvm_file_totals([report], ROOT)
    categories, _, _ = coverage_gate.classify(ROOT, rules, "swift")
    out: dict = {"report": str(report), "categories": {}}
    for category, files in categories.items():
        threshold = rules["thresholds"][category]
        rows = []
        for name in sorted(files):
            covered, count = totals.get(name, (0, 0))
            rows.append({"file": name, "area": area_of(name), "covered": covered, "lines": count, "uncovered": count - covered,
                         "gallery": is_gallery(name), "has_record": name in totals})
        covered = sum(r["covered"] for r in rows)
        lines = sum(r["lines"] for r in rows)
        need = max(0, -(-threshold * lines // 100) - covered)
        areas: dict[str, dict] = {}
        for r in rows:
            a = areas.setdefault(r["area"], {"area": r["area"], "covered": 0, "lines": 0, "uncovered": 0, "gallery_uncovered": 0, "files": 0})
            a["covered"] += r["covered"]; a["lines"] += r["lines"]; a["uncovered"] += r["uncovered"]; a["files"] += 1
            if r["gallery"]:
                a["gallery_uncovered"] += r["uncovered"]
        gallery_unc = sum(r["uncovered"] for r in rows if r["gallery"])
        gallery_lines = sum(r["lines"] for r in rows if r["gallery"])
        out["categories"][category] = {
            "threshold": threshold, "covered": covered, "lines": lines, "percent": round(covered * 100 / max(lines, 1), 2),
            "lines_needed_for_threshold": need, "files": len(rows), "files_without_record": sum(1 for r in rows if not r["has_record"]),
            "gallery_lines": gallery_lines, "gallery_uncovered": gallery_unc,
            "areas": sorted(areas.values(), key=lambda a: -a["uncovered"]),
            "rows": sorted((r for r in rows if r["uncovered"] > 0), key=lambda r: -r["uncovered"]),
        }
    json_out.write_text(json.dumps(out, indent=1))
    print(f"baseline -> {json_out}")
    if md_out is None:
        return
    lines_md = ["# Coverage baseline", "",
                f"> **What:** measured UX and logic line coverage and the per-file gap to {out['categories']['ux']['threshold']}%, from `tools/coverage_ios.py baseline`. "
                "**Read when:** you pick files to write tests for. Regenerate after a full run (`.agents/testing/apple/coverage.md`).", ""]
    for category in ("ux", "logic"):
        c = out["categories"].get(category)
        if not c:
            continue
        lines_md += [f"## {category.upper()}: {c['percent']:.2f}% ({c['covered']}/{c['lines']}), {c['lines_needed_for_threshold']} more lines to reach {c['threshold']}%", ""]
        if c["gallery_lines"]:
            share = c["gallery_uncovered"] * 100 / max(c["lines"] - c["covered"], 1)
            lines_md += [f"Gallery-only code (fixture pages that only tests reach): {c['gallery_lines']} lines, {c['gallery_uncovered']} uncovered = {share:.1f}% of the uncovered lines.", ""]
        lines_md += ["| Area | Files | Covered / lines | % | Uncovered | of which Gallery |", "|---|---:|---:|---:|---:|---:|"]
        for a in c["areas"]:
            if a["uncovered"]:
                lines_md.append(f"| {a['area']} | {a['files']} | {a['covered']}/{a['lines']} | {a['covered'] * 100 / max(a['lines'], 1):.1f} | {a['uncovered']} | {a['gallery_uncovered']} |")
        lines_md.append("")
        by_area: dict[str, list] = {}
        for r in c["rows"]:
            by_area.setdefault(r["area"], []).append(r)
        for a in c["areas"]:
            rows = by_area.get(a["area"])
            if not rows:
                continue
            lines_md += [f"### {category.upper()} {a['area']} ({a['uncovered']} uncovered)", "", "| File | Covered / lines | % | Uncovered |", "|---|---:|---:|---:|"]
            for r in rows:
                short = r["file"].replace("apple/Sources/", "")
                tag = " (gallery)" if r["gallery"] else ""
                lines_md.append(f"| {short}{tag} | {r['covered']}/{r['lines']} | {r['covered'] * 100 / max(r['lines'], 1):.1f} | {r['uncovered']} |")
            lines_md.append("")
    md_out.write_text("\n".join(lines_md))
    print(f"baseline -> {md_out}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("export")
    e.add_argument("profraw_dir", type=Path)
    e.add_argument("--products", type=Path, required=True)
    e.add_argument("--out", type=Path, required=True)
    m = sub.add_parser("merge")
    m.add_argument("reports", type=Path, nargs="+")
    m.add_argument("--out", type=Path, required=True)
    t = sub.add_parser("top")
    t.add_argument("report", type=Path)
    t.add_argument("--n", type=int, default=15)
    t.add_argument("--prefix", default="apple/Sources/HassUI/UIKitPort")
    b = sub.add_parser("baseline")
    b.add_argument("report", type=Path)
    b.add_argument("--json", type=Path, required=True, dest="json_out")
    b.add_argument("--md", type=Path, dest="md_out")
    args = parser.parse_args()
    try:
        if args.cmd == "export":
            export(args.profraw_dir, args.products, args.out)
        elif args.cmd == "merge":
            merge(args.reports, args.out)
        elif args.cmd == "baseline":
            baseline(args.report, args.json_out, args.md_out)
        else:
            top(args.report, args.n, args.prefix)
    except (RuntimeError, OSError, KeyError, json.JSONDecodeError) as error:
        print(f"coverage_ios: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
