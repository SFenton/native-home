#!/usr/bin/env python3
"""Test impact map (spike): which source lines each UI test executed.

    tools/test_impact.py extract DIR --binary EXE [--binary EXE …] --out impact.json
    tools/test_impact.py stats impact.json [--file PATH [--lines A-B]] [--top N]

``extract`` reads the ``<Class>.<test>.<pid>.….profraw`` files that ``tools/ios_uitest.sh --impact DIR`` makes (one app
process, so one profile, per launch), merges each test's profiles with ``llvm-profdata``, exports line coverage with
``llvm-cov`` and keeps only ``apple/Sources/**``, repo-relative, as executed-line ranges per file per test.
``stats`` prints per-test file and line counts and, per file, how many tests cover it (or one line range of it).
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

SOURCE_MARK = "apple/Sources/"
Ranges = List[List[int]]
TestMap = Dict[str, Dict[str, Ranges]]


def compact(lines: Iterable[int]) -> Ranges:
    """Sorted unique line numbers as inclusive ``[start, end]`` runs."""
    out: Ranges = []
    for line in sorted(set(lines)):
        if out and line == out[-1][1] + 1:
            out[-1][1] = line
        else:
            out.append([line, line])
    return out


def expand(ranges: Ranges) -> List[int]:
    return [line for start, end in ranges for line in range(start, end + 1)]


def repo_relative(path: str) -> Optional[str]:
    """``apple/Sources/…`` of an absolute source path, or None for anything else (pods, SDK, tests, generated)."""
    index = path.rfind(SOURCE_MARK)
    return path[index:] if index >= 0 else None


def parse_lcov(text: str) -> Dict[str, Ranges]:
    """Executed lines per ``apple/Sources`` file of an lcov report (``SF:`` starts a file, ``DA:line,count`` a line)."""
    files: Dict[str, set] = {}
    current: Optional[set] = None
    for raw in text.splitlines():
        if raw.startswith("SF:"):
            name = repo_relative(raw[3:].strip())
            current = files.setdefault(name, set()) if name else None
        elif raw.startswith("DA:") and current is not None:
            line, _, rest = raw[3:].partition(",")
            count = rest.split(",")[0]
            if line.isdigit() and count.lstrip("-").isdigit() and int(count) > 0:
                current.add(int(line))
        elif raw == "end_of_record":
            current = None
    return {name: compact(lines) for name, lines in files.items() if lines}


def test_name(profraw: Path) -> str:
    """``Class.testMethod`` of ``Class.testMethod.<pid>.…profraw``."""
    return ".".join(profraw.name.split(".")[:2])


def group_profiles(directory: Path) -> Dict[str, List[Path]]:
    groups: Dict[str, List[Path]] = defaultdict(list)
    for path in sorted(directory.glob("*.profraw")):
        if path.stat().st_size > 0:
            groups[test_name(path)].append(path)
    return dict(groups)


def run(*command: str) -> str:
    return subprocess.run(command, capture_output=True, text=True, check=True).stdout


def extract(directory: Path, binaries: List[str], arch: str = "arm64") -> TestMap:
    result: TestMap = {}
    with tempfile.TemporaryDirectory() as scratch:
        for name, profiles in group_profiles(directory).items():
            merged = Path(scratch) / (name + ".profdata")
            try:
                run("xcrun", "llvm-profdata", "merge", "-sparse", "-o", str(merged), *map(str, profiles))
                objects = [binaries[0]] + [arg for extra in binaries[1:] for arg in ("-object", extra)]
                lcov = run("xcrun", "llvm-cov", "export", "-format=lcov", f"-instr-profile={merged}", f"-arch={arch}", *objects)
            except subprocess.CalledProcessError as error:
                print(f"skip {name}: {(error.stderr or '').strip()[:400]}", file=sys.stderr)
                continue
            result[name] = parse_lcov(lcov)
            merged.unlink(missing_ok=True)
    return result


def line_count(ranges: Ranges) -> int:
    return sum(end - start + 1 for start, end in ranges)


def covering(data: TestMap, path: str, lines: Optional[Tuple[int, int]] = None) -> List[str]:
    """Tests whose recorded run executed ``path`` (any line, or a line in the inclusive range)."""
    hits = []
    for name, files in data.items():
        ranges = files.get(path)
        if not ranges:
            continue
        if lines is None or any(start <= lines[1] and end >= lines[0] for start, end in ranges):
            hits.append(name)
    return sorted(hits)


def stats(data: TestMap) -> dict:
    per_test = {name: (len(files), sum(line_count(r) for r in files.values())) for name, files in data.items()}
    cover: Dict[str, int] = defaultdict(int)
    for files in data.values():
        for path in files:
            cover[path] += 1
    counts = [files for files, _ in per_test.values()]
    return {
        "tests": len(data),
        "files_per_test": {"median": statistics.median(counts) if counts else 0, "max": max(counts, default=0)},
        "per_test": per_test,
        "per_file": dict(sorted(cover.items(), key=lambda item: (-item[1], item[0]))),
    }


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    ex = sub.add_parser("extract")
    ex.add_argument("directory", type=Path)
    ex.add_argument("--binary", action="append", required=True)
    ex.add_argument("--arch", default="arm64", help="slice of fat binaries (default arm64)")
    ex.add_argument("--out", type=Path, required=True)
    st = sub.add_parser("stats")
    st.add_argument("map", type=Path)
    st.add_argument("--file")
    st.add_argument("--lines", help="A-B, with --file")
    st.add_argument("--top", type=int, default=25)
    args = parser.parse_args(argv)
    if args.command == "extract":
        data = extract(args.directory, args.binary, args.arch)
        args.out.write_text(json.dumps(data, separators=(",", ":"), sort_keys=True), encoding="utf-8")
        print(f"{len(data)} tests, {args.out.stat().st_size} bytes -> {args.out}")
        return 0
    data = json.loads(args.map.read_text(encoding="utf-8"))
    if args.file:
        span = tuple(int(n) for n in args.lines.split("-")) if args.lines else None
        hits = covering(data, args.file, span)
        print(f"{len(hits)} of {len(data)} tests cover {args.file}" + (f" lines {args.lines}" if args.lines else ""))
        for name in hits:
            print("  " + name)
        return 0
    summary = stats(data)
    print(f"{summary['tests']} tests; files per test median {summary['files_per_test']['median']}, max {summary['files_per_test']['max']}")
    for name, (files, lines) in sorted(summary["per_test"].items()):
        print(f"  {name}: {files} files, {lines} lines")
    print("source files by number of tests covering them:")
    for path, n in list(summary["per_file"].items())[: args.top]:
        print(f"  {n:4d}  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
