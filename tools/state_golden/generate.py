#!/usr/bin/env python3
"""Build the golden answers of the frozen old HassCore over the generic state space.

The old app's state-to-text and glyph functions are the oracle for ``StateGoldenTests``. This tool exports the pinned commit
(``git archive``) into a temporary directory, builds only ``HassTelemetry``, ``FentonActivityModel`` and ``HassCore`` there next
to ``probe/main.swift``, runs the probe over ``apple/Tests/HassCoreTests/StateGolden/state-space.json`` and writes
``state-golden.json`` beside it. Nothing from the old tree is committed and nothing of it enters the app or the tests; the
golden holds generic fixture rows only.

    generate.py              build, probe, write the golden (about a minute cold: the old module builds in about 41 s)
    generate.py --check      verify the checked-in golden records the pin's tree id and only rows of the state space; no build
    generate.py --keep       keep the temporary checkout and print its path

The pin never changes, so the golden is regenerated only when rows are added to the state space.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PIN = "4fe28061"
MODULES = ("HassTelemetry", "FentonActivityModel", "HassCore")
SPACE = ROOT / "apple/Tests/HassCoreTests/StateGolden/state-space.json"
KINDS = ROOT / "tools/state_space/kinds.json"
GOLDEN = ROOT / "apple/Tests/HassCoreTests/StateGolden/state-golden.json"

PACKAGE = """// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StateGoldenOld",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/home-assistant/HAKit", from: "0.4.19"),
        .package(url: "https://github.com/bgoncal/Starscream", from: "4.0.10"),
    ],
    targets: [
        .target(name: "HassTelemetry"),
        .target(name: "FentonActivityModel"),
        .target(name: "HassCore", dependencies: ["HassTelemetry", "FentonActivityModel", .product(name: "HAKit", package: "HAKit")]),
        .executableTarget(name: "StateGoldenProbe", dependencies: ["HassCore"]),
    ]
)
"""


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout.strip()


def tree_id() -> str:
    """The pin's HassCore tree id: changes only if the pin or the path changes."""
    return git("rev-parse", f"{PIN}:apple/Sources/HassCore")


def export(dest: Path) -> None:
    """Export the three modules and the resolved pins of the pinned commit into ``dest``."""
    paths = [f"apple/Sources/{m}" for m in MODULES] + ["apple/Package.resolved"]
    archive = subprocess.run(["git", "-C", str(ROOT), "archive", PIN, *paths], check=True, capture_output=True).stdout
    subprocess.run(["tar", "-x", "-C", str(dest)], input=archive, check=True)
    sources = dest / "Sources"
    sources.mkdir()
    for module in MODULES:
        shutil.move(str(dest / "apple/Sources" / module), str(sources / module))
    shutil.copy(dest / "apple/Package.resolved", dest / "Package.resolved")
    (dest / "Package.swift").write_text(PACKAGE, encoding="utf-8")
    probe = sources / "StateGoldenProbe"
    probe.mkdir()
    shutil.copy(HERE / "probe/main.swift", probe / "main.swift")


def render(rows: dict[str, dict], tree: str) -> str:
    """Deterministic text, one row per line."""
    head = {"schema": 1, "pin": PIN, "hassCoreTree": tree, "rowCount": len(rows)}
    lines = [f"{json.dumps(k)}: {json.dumps(v, ensure_ascii=False, sort_keys=True)}" for k, v in rows.items()]
    return json.dumps(head, sort_keys=True)[:-1] + ',"rows":{\n' + ",\n".join(lines) + "\n}}\n"


def check() -> int:
    golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
    problems = []
    if golden.get("pin") != PIN:
        problems.append(f"pin is {golden.get('pin')}, expected {PIN}")
    try:
        if golden.get("hassCoreTree") != tree_id():
            problems.append("hassCoreTree differs from the pin's tree id")
    except subprocess.CalledProcessError:
        print("generate: the pin is not in this clone; tree id not checked", file=sys.stderr)
    space = {r["id"] for r in json.loads(SPACE.read_text(encoding="utf-8"))["rows"]}
    stray = sorted(set(golden["rows"]) - space)
    if stray:
        problems.append(f"golden rows not in the state space: {stray[:5]}")
    for problem in problems:
        print(f"generate: {problem}", file=sys.stderr)
    return 1 if problems else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--keep", action="store_true")
    args = parser.parse_args(argv)
    if args.check:
        return check()
    work = Path(tempfile.mkdtemp(prefix="state-golden-"))
    try:
        export(work)
        build = subprocess.run(["swift", "build", "--product", "StateGoldenProbe"], cwd=work)
        if build.returncode:
            return build.returncode
        out = work / "golden-rows.json"
        run = subprocess.run([str(work / ".build/debug/StateGoldenProbe"), str(SPACE), str(KINDS), str(out)])
        if run.returncode:
            return run.returncode
        rows = json.loads(out.read_text(encoding="utf-8"))
        GOLDEN.write_text(render(rows, tree_id()), encoding="utf-8")
        print(f"wrote {GOLDEN} ({len(rows)} rows)")
        return 0
    finally:
        if args.keep:
            print(f"kept {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
