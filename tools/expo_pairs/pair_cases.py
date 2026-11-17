#!/usr/bin/env python3
"""Build and run the paired Expo cases: migrate a recorded publication, write each fixture just before its run.

A paired case replays one recorded journey on the reference (the pinned Expo build) or the candidate (the native app) on a
simulator, through ``paired-expo-crawl.mjs``. The cases were recorded against an older candidate; this tool derives fresh
ones from the recorded ``<side>-case.json`` files and the recorded publication directory.

Subcommands::

    pair_cases.py migrate  --publication DIR --out DIR [--gallery-source FILE] [--gallery-page NAME]
    pair_cases.py prepare  --run NAME --side reference|candidate --recorded DIR --publication DIR
                           --device UDID --command AGENT_DEVICE --out DIR [--sha SHA]
    pair_cases.py run      (the same, then replays the case through the harness)

``migrate`` is the step the recorded candidate publication needs: the app removed five bedroom fields on purpose, so the
publication drops them, and the recorded gallery fixture names a page that no longer exists, so it names one that does.
``prepare`` and ``run`` write the run's gallery fixture and publication into the simulator immediately before that run, one
run at a time: every run shares one ``bootstrap.json`` on the device, so preparing all of them up front leaves only the last.

The migrated publication holds house values. Keep ``--out`` under ``build/`` (git-ignored); never commit it.
Python 3 standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Tuple

HERE = Path(__file__).resolve().parent

#: The fields the app removed from the bedroom configuration on purpose; a publication that still carries one is refused
#: with ``unknown_field`` (the list is ``ServerUIBedroomControlTests.authoredBedroom``'s ``removed`` set).
REMOVED_BEDROOM_FIELDS: Tuple[str, ...] = (
    "tonightScript", "outsideScheduleScript", "scheduleSetTopic", "hotFlashBrokerScript", "householdAwayScript",
)
#: The gallery page the migrated fixture names when the recorded one is gone. The server-UI preview route ignores it.
DEFAULT_GALLERY_PAGE = "rooms"
#: The recorded run folders under the evidence root, and the fixture scenario each uses.
RUNS: Dict[str, Dict[str, str]] = {
    "waking-regression": {"folder": "bedroom-waking-regression-r9", "scenario": "waking"},
    "editor-scroll": {"folder": "bedroom-wake-editor-scroll-r9", "scenario": "default"},
    "editor-save": {"folder": "bedroom-wake-editor-save-r9", "scenario": "default"},
}
APP_ID = "com.sfenton.home"
FIXTURE_SUBPATH = "Library/Application Support/GalleryFixture"
PREVIEW_SUBPATH = "Library/Application Support/ServerUIPreview"

Runner = Callable[[Sequence[str]], str]


# MARK: - Hashing

def sha256_hex(data: bytes) -> str:
    """The hex SHA-256 of ``data``."""
    return hashlib.sha256(data).hexdigest()


def fixture_bytes(fixture: Dict[str, Any]) -> bytes:
    """A gallery fixture as the harness hashes it: compact JSON, non-ASCII kept."""
    return json.dumps(fixture, separators=(",", ":"), ensure_ascii=False).encode()


def document_sha256(document: Any) -> str:
    """The hash the app's publication receipt reports: SHA-256 of the document as sorted-key compact JSON."""
    return sha256_hex(json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())


# MARK: - Migration

def strip_removed_fields(node: Any, removed: Iterable[str] = REMOVED_BEDROOM_FIELDS, path: str = "") -> Tuple[Any, List[str]]:
    """``node`` without any removed key at any depth, plus the JSON-pointer paths dropped (in document order)."""
    gone = set(removed)
    dropped: List[str] = []

    def walk(value: Any, where: str) -> Any:
        if isinstance(value, dict):
            kept: Dict[str, Any] = {}
            for key, child in value.items():
                if key in gone:
                    dropped.append(f"{where}/{key}")
                    continue
                kept[key] = walk(child, f"{where}/{key}")
            return kept
        if isinstance(value, list):
            return [walk(child, f"{where}/{index}") for index, child in enumerate(value)]
        return value

    return walk(node, path), dropped


def migrate_publication(publication: Dict[str, Any]) -> Tuple[Dict[str, Any], List[str]]:
    """The publication without the removed bedroom fields, and the paths dropped. The envelope is otherwise unchanged."""
    migrated, dropped = strip_removed_fields(publication)
    return migrated, dropped


def gallery_pages(swift_source: str) -> List[str]:
    """The raw values of ``ComponentGallery.Page``, read from its Swift source (``case x`` and ``case y = "z"``)."""
    block = re.search(r"enum\s+Page\s*:[^{]*\{(.*?)\n    \}", swift_source, re.S)
    if not block:
        return []
    pages: List[str] = []
    for line in block.group(1).splitlines():
        line = line.split("//", 1)[0].strip()
        match = re.match(r"case\s+(.*)$", line)
        if not match:
            continue
        for item in match.group(1).split(","):
            name, _, raw = item.partition("=")
            raw = raw.strip().strip('"')
            pages.append(raw if raw else name.strip())
    return pages


def choose_gallery_page(current: Optional[str], pages: Sequence[str], preferred: str = DEFAULT_GALLERY_PAGE) -> str:
    """``current`` when it still exists; else ``preferred`` when it exists; else the first page. Raises when there are none."""
    if current in pages:
        return str(current)
    if preferred in pages:
        return preferred
    if not pages:
        raise ValueError("no gallery pages to choose from")
    return pages[0]


def migrate_fixture(fixture: Dict[str, Any], pages: Sequence[str], preferred: str = DEFAULT_GALLERY_PAGE) -> Dict[str, Any]:
    """A copy of the gallery fixture whose ``FENTON_GALLERY`` names an existing page."""
    migrated = json.loads(json.dumps(fixture))
    variables = migrated.setdefault("variables", {})
    variables["FENTON_GALLERY"] = choose_gallery_page(variables.get("FENTON_GALLERY"), pages, preferred)
    return migrated


def migrate_directory(publication_dir: Path, out_dir: Path, pages: Sequence[str], preferred: str = DEFAULT_GALLERY_PAGE) -> Dict[str, Any]:
    """Write the migrated publication, preview bootstrap, gallery fixture and assets to ``out_dir``; return a summary.

    The summary holds counts and field names only, no house values, so it is safe to print.
    """
    publication = json.loads((publication_dir / "publication.json").read_text(encoding="utf-8"))
    migrated, dropped = migrate_publication(publication)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "publication.json").write_text(json.dumps(migrated, ensure_ascii=False), encoding="utf-8")
    shutil.copyfile(publication_dir / "bootstrap.json", out_dir / "bootstrap.json")
    fixture = json.loads((publication_dir / "fixture.json").read_text(encoding="utf-8"))
    migrated_fixture = migrate_fixture(fixture, pages, preferred)
    (out_dir / "fixture.json").write_text(json.dumps(migrated_fixture, ensure_ascii=False), encoding="utf-8")
    assets = publication_dir / "assets"
    if assets.is_dir():
        shutil.copytree(assets, out_dir / "assets", dirs_exist_ok=True)
    return {
        "removedFields": sorted({path.rsplit("/", 1)[-1] for path in dropped}),
        "droppedCount": len(dropped),
        "documentSha256": document_sha256(migrated["document"]),
        "galleryPage": migrated_fixture["variables"]["FENTON_GALLERY"],
    }


# MARK: - Cases

def _run(command: Sequence[str]) -> str:
    return subprocess.check_output(list(command), text=True).strip()


def app_container(runner: Runner, device: str, kind: str) -> str:
    """The simulator's installed ``app`` or ``data`` container path for the S+H bundle id."""
    return runner(["xcrun", "simctl", "get_app_container", device, APP_ID, kind])


def bundle_sha256(runner: Runner, app: str) -> str:
    """The bundle hash of an installed app, measured by the harness's own ``bundleIdentity``."""
    return runner(["node", str(HERE / "bundle-hash.mjs"), app])


def load_recorded_case(recorded_root: Path, run: str, side: str) -> Dict[str, Any]:
    """The recorded case for ``run`` on ``side``, from ``<recorded_root>/<run folder>/<side>-case.json``."""
    path = recorded_root / RUNS[run]["folder"] / f"{side}-case.json"
    return json.loads(path.read_text(encoding="utf-8"))


def scenario_fixture(base: Dict[str, Any], scenario: str) -> Dict[str, Any]:
    """The recorded gallery fixture for one run: its id and scenario variable follow the run."""
    fixture = json.loads(json.dumps(base))
    fixture["id"] = f"bedroom-{scenario}-png"
    fixture["variables"]["FENTON_GALLERY_SCENARIO"] = scenario
    return fixture


def build_case(*, run: str, side: str, recorded: Dict[str, Any], fixture_sha: str, device: str, command: str,
               app: str, data: str, bundle: str, binary_sha: str, version: str, out: Path, source_sha: str,
               migrated_document_sha: Optional[str] = None) -> Dict[str, Any]:
    """A case for ``run`` on ``side``: the recorded case with this machine's device, build and fixture facts filled in."""
    case = json.loads(json.dumps(recorded))
    case.update(
        fixtureSHA256=fixture_sha, deviceId=device, command=command,
        fixtureDirectory=f"{data}/{FIXTURE_SUBPATH}", binaryPath=f"{app}/FentonHome.debug.dylib",
        binarySHA256=binary_sha, bundleSHA256=bundle, version=version, output=str(out / "runs" / run / side),
        sourceSHA=source_sha, uncommittedSources=False, renderCachePolicy="fresh-render",
    )
    if side == "candidate":
        case["cachePreparation"] = "installed-fresh-before-run"
        if migrated_document_sha is not None:
            case["expectedPublication"] = {**case["expectedPublication"], "documentSha256": migrated_document_sha}
    return case


def write_device_inputs(*, side: str, scenario: str, data: Path, fixture: Dict[str, Any], publication_dir: Optional[Path]) -> None:
    """Write this run's gallery fixture (and, for the candidate, the preview publication) into the simulator's data container.

    Called once per run, immediately before it, so a later run never inherits the previous one's ``bootstrap.json``.
    """
    gallery = data / FIXTURE_SUBPATH
    gallery.mkdir(parents=True, exist_ok=True)
    (gallery / "bootstrap.json").write_bytes(fixture_bytes(fixture))
    (gallery / "receipt.json").unlink(missing_ok=True)
    if side != "candidate" or publication_dir is None:
        return
    preview = data / PREVIEW_SUBPATH
    (preview / "assets").mkdir(parents=True, exist_ok=True)
    bootstrap = json.loads((publication_dir / "bootstrap.json").read_text(encoding="utf-8"))
    bootstrap.pop("endpoint", None)  # no server: the preview must not reach one
    bootstrap.setdefault("gallery", {})["bedroomScenario"] = scenario
    (preview / "bootstrap.json").write_text(json.dumps(bootstrap, separators=(",", ":")), encoding="utf-8")
    shutil.copyfile(publication_dir / "publication.json", preview / "publication.json")
    for asset in sorted((publication_dir / "assets").iterdir()):
        name = asset.name[:-4] if asset.name.endswith(".png") else asset.name
        shutil.copyfile(asset, preview / "assets" / name)
    (preview / "receipt.json").unlink(missing_ok=True)


def prepare(*, run: str, side: str, recorded_root: Path, publication_dir: Path, device: str, command: str, out: Path,
            source_sha: str, pages: Sequence[str] = (), runner: Runner = _run, preferred: str = DEFAULT_GALLERY_PAGE) -> Path:
    """Write one run's fixture to the simulator and its case to ``<out>/cases/<run>-<side>.json``; return the case path."""
    if run not in RUNS:
        raise ValueError(f"unknown run {run!r}; known: {', '.join(RUNS)}")
    if side not in ("reference", "candidate"):
        raise ValueError("side must be reference or candidate")
    scenario = RUNS[run]["scenario"]
    recorded = load_recorded_case(recorded_root, run, side)
    base = json.loads((publication_dir / "fixture.json").read_text(encoding="utf-8"))
    fixture = scenario_fixture(base, scenario)
    if side == "reference" and sha256_hex(fixture_bytes(fixture)) != recorded["fixtureSHA256"]:
        # The reference replays exactly what was recorded; a fixture that hashes differently is not the recorded one.
        raise ValueError(f"{run}: the reference fixture does not match the recorded fixture hash")
    if side == "candidate":
        fixture = migrate_fixture(fixture, pages, preferred)
    app, data = app_container(runner, device, "app"), app_container(runner, device, "data")
    migrated_document = None
    if side == "candidate":
        migrated_document = document_sha256(json.loads((publication_dir / "publication.json").read_text(encoding="utf-8"))["document"])
    binary = Path(app) / "FentonHome.debug.dylib"
    case = build_case(
        run=run, side=side, recorded=recorded, fixture_sha=sha256_hex(fixture_bytes(fixture)), device=device,
        command=command, app=app, data=data, bundle=bundle_sha256(runner, app), binary_sha=sha256_hex(binary.read_bytes()),
        version=runner(["plutil", "-extract", "CFBundleShortVersionString", "raw", "-o", "-", f"{app}/Info.plist"]),
        out=out, source_sha=source_sha, migrated_document_sha=migrated_document)
    write_device_inputs(side=side, scenario=scenario, data=Path(data), fixture=fixture,
                        publication_dir=publication_dir if side == "candidate" else None)
    # The harness creates the capture folder itself and refuses to reuse one, so only its parent is made here.
    Path(case["output"]).parent.mkdir(parents=True, exist_ok=True)
    case_path = out / "cases" / f"{run}-{side}.json"
    case_path.parent.mkdir(parents=True, exist_ok=True)
    case_path.write_text(json.dumps(case, indent=2), encoding="utf-8")
    return case_path


# MARK: - Command line

def _add_case_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--run", required=True, choices=sorted(RUNS))
    parser.add_argument("--side", required=True, choices=("reference", "candidate"))
    parser.add_argument("--recorded", type=Path, required=True, help="the folder holding the recorded run folders")
    parser.add_argument("--publication", type=Path, required=True, help="the (migrated, for the candidate) publication directory")
    parser.add_argument("--device", required=True, help="simulator UDID")
    parser.add_argument("--command", required=True, help="absolute path of the bound agent-device command")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--sha", help="the source commit under test (the reference defaults to the pin's)")
    parser.add_argument("--gallery-source", type=Path, help="ComponentGallery.swift, to validate the gallery page")


def main(argv: Optional[List[str]] = None) -> int:
    """Entry point; returns the process exit status."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="verb", required=True)
    migrate = sub.add_parser("migrate", help="drop the removed bedroom fields and name an existing gallery page")
    migrate.add_argument("--publication", type=Path, required=True)
    migrate.add_argument("--out", type=Path, required=True)
    migrate.add_argument("--gallery-source", type=Path, required=True, help="ComponentGallery.swift")
    migrate.add_argument("--gallery-page", default=DEFAULT_GALLERY_PAGE)
    _add_case_arguments(sub.add_parser("prepare", help="write one run's fixture and case"))
    _add_case_arguments(sub.add_parser("run", help="prepare, then replay the case through the harness"))
    args = parser.parse_args(argv)
    if args.verb == "migrate":
        pages = gallery_pages(args.gallery_source.read_text(encoding="utf-8"))
        print(json.dumps(migrate_directory(args.publication, args.out, pages, args.gallery_page), indent=2))
        return 0
    pages = gallery_pages(args.gallery_source.read_text(encoding="utf-8")) if args.gallery_source else []
    if args.sha is None:
        args.sha = json.loads((HERE / "reference-pin.json").read_text())["sourceSHA"] if args.side == "reference" else "unknown"
    case = prepare(run=args.run, side=args.side, recorded_root=args.recorded, publication_dir=args.publication,
                   device=args.device, command=args.command, out=args.out, source_sha=args.sha, pages=pages)
    print(case)
    if args.verb == "prepare":
        return 0
    return subprocess.call(["node", str(HERE / "paired-expo-crawl.mjs"), str(case)])


if __name__ == "__main__":
    sys.exit(main())
