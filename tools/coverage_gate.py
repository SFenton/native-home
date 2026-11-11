#!/usr/bin/env python3
"""Fail when actual logic line coverage misses its threshold. Ported from FestivalNativeApps.

Only the categories named in ``thresholds`` of ``contracts/coverage-rules.json`` are gated (today ``logic``). Source
under ``unmeasured`` (the UIKit and SwiftUI UX modules) is classified so a new module still fails
by name, but it is never reported or gated.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
FOREIGN_SOURCE = re.compile(r"/apple/(Sources|Apps|Tests)/")
RULES = ROOT / "contracts" / "coverage-rules.json"
#: The classification-only category: every file is sorted into it, but it has no threshold and no report.
UNMEASURED = "unmeasured"


def source_files(root: Path, patterns: list[str]) -> set[str]:
    """Find source files subject to coverage, independently of report contents.

    Args:
        root: Repository root.
        patterns: Repository-relative glob patterns for one coverage category.

    Returns:
        All matched repository-relative POSIX file paths.
    """
    return {
        path.relative_to(root).as_posix()
        for pattern in patterns
        for path in root.glob(pattern)
        if path.is_file()
    }


def llvm_file_totals(
    reports: list[Path], root: Path, dropped: list[str] | None = None
) -> dict[str, tuple[int, int]]:
    """Extract exact executable and covered line totals from LLVM JSON exports.

    Args:
        reports: One `llvm-cov export --format=text` result per test binary.
        root: Root against which tracked source paths are resolved.
        dropped: Optional list that receives the filename of each skipped record whose path looks like
            product source (`/apple/(Sources|Apps|Tests)/`) under another root, so a gate can tell a
            checkout mismatch from a file with no instrumented code.

    Returns:
        Mapping from repository-relative path to (covered, executable) lines.

    Raises:
        ValueError: On malformed, missing or duplicated per-file coverage.
    """
    totals: dict[str, tuple[int, int]] = {}
    for report in reports:
        try:
            payload = json.loads(report.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError(f"{report}: cannot read LLVM coverage JSON: {error}") from error
        if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
            raise ValueError(f"{report}: missing LLVM data array")
        for group in payload["data"]:
            if not isinstance(group, dict) or not isinstance(group.get("files"), list):
                raise ValueError(f"{report}: missing LLVM files array")
            for item in group["files"]:
                if not isinstance(item, dict) or not isinstance(item.get("filename"), str):
                    raise ValueError(f"{report}: invalid file entry")
                try:
                    name = Path(item["filename"]).resolve().relative_to(root.resolve()).as_posix()
                except ValueError:
                    # Generated compiler or SDK sources are not product code; product source under
                    # another checkout's root is reported through `dropped`.
                    if dropped is not None and FOREIGN_SOURCE.search(item["filename"]):
                        dropped.append(item["filename"])
                    continue
                lines: Any = item.get("summary", {}).get("lines")
                if (
                    not isinstance(lines, dict)
                    or type(lines.get("covered")) is not int
                    or type(lines.get("count")) is not int
                    or not 0 <= lines["covered"] <= lines["count"]
                ):
                    raise ValueError(f"{report}: invalid line totals for {name}")
                if name in totals:
                    raise ValueError(f"{name}: duplicated in coverage exports; merge profiles first")
                totals[name] = (lines["covered"], lines["count"])
    return totals


def foreign_prefix(dropped: list[str]) -> str:
    """Name the directory shared by dropped records, up to the `apple` directory.

    Args:
        dropped: Filenames of records that fall outside the checkout.

    Returns:
        The longest common directory of the paths, or an empty string when there are none.
    """
    if not dropped:
        return ""
    prefix = os.path.commonpath([str(Path(name).parent) for name in dropped])
    return prefix


def module_of(name: str) -> str:
    """Name the module a source file compiles into: the directory under `Sources`.

    Args:
        name: Repository-relative POSIX source path.

    Returns:
        The module directory (for example `apple/Sources/HassCore`), or the file's parent directory
        when the path has no `Sources` component.
    """
    parts = name.split("/")
    if "Sources" in parts[:-2]:
        index = parts.index("Sources")
        return "/".join(parts[: index + 2])
    return "/".join(parts[:-1])


def file_list(files: set[str]) -> str:
    """Format paths one per line, indented, for an error or note."""
    return "".join(f"\n  {name}" for name in sorted(files))


def classify(
    root: Path, rules: dict[str, Any], language: str
) -> tuple[dict[str, set[str]], set[str], list[str]]:
    """Sort every production source file into exactly one coverage category.

    Runs before any coverage is measured, so a new module or file that no pattern matches fails the
    gate by name instead of surfacing later as missing coverage.

    Args:
        root: Repository root.
        rules: Versioned coverage classification and numeric thresholds.
        language: Language section to validate.

    Returns:
        The files in each category (each gated one, plus `unmeasured`), the excluded files and the
        classification errors.
    """
    section = rules.get(language)
    if not isinstance(section, dict):
        return {}, set(), [f"{language}: no configured coverage categories"]
    errors: list[str] = []
    exclude_patterns = section.get("exclude", [])
    if not isinstance(exclude_patterns, list) or not all(
        isinstance(pattern, str) for pattern in exclude_patterns
    ):
        return {}, set(), [f"{language}: invalid coverage exclusion patterns"]
    excluded = source_files(root, exclude_patterns)
    categories: dict[str, set[str]] = {}
    classified: set[str] = set()
    thresholds = rules.get("thresholds", {})
    if not isinstance(thresholds, dict) or not thresholds or UNMEASURED in thresholds:
        return {}, excluded, [f"{language}: thresholds must name the gated categories (and never {UNMEASURED})"]
    for category in (*thresholds, UNMEASURED):
        patterns = section.get(category)
        threshold = thresholds.get(category)
        if (
            not isinstance(patterns, list)
            or not patterns
            or not all(isinstance(pattern, str) for pattern in patterns)
            or (category != UNMEASURED and (type(threshold) is not int or not 0 <= threshold <= 100))
        ):
            errors.append(f"{language}.{category}: invalid patterns or threshold")
            continue
        files = source_files(root, patterns) - excluded
        if not files:
            errors.append(f"{language}.{category}: no matching source files")
            continue
        overlap = classified & files
        if overlap:
            errors.append(f"{language}.{category}: source classified twice:{file_list(overlap)}")
        classified.update(files)
        categories[category] = files
    source_roots = section.get("sourceRoots")
    if (
        not isinstance(source_roots, list)
        or not source_roots
        or not all(isinstance(pattern, str) for pattern in source_roots)
    ):
        errors.append(f"{language}: sourceRoots must list the production source patterns")
        return categories, excluded, errors
    production = source_files(root, source_roots)
    if not production:
        errors.append(f"{language}: sourceRoots matched no production files")
    unclassified = production - classified - excluded
    if unclassified:
        modules = sorted({module_of(name) for name in unclassified})
        errors.append(
            f"{language}: {len(unclassified)} production source file(s) are not classified as"
            f" {', '.join(categories)}. Add a pattern for each (or its module: {', '.join(modules)}) to \"{language}\" in"
            f" {RULES.relative_to(ROOT).as_posix()}:{file_list(unclassified)}"
        )
    outside_roots = classified - production
    if outside_roots:
        errors.append(f"{language}: classified source outside sourceRoots:{file_list(outside_roots)}")
    return categories, excluded, errors


def check_coverage(
    totals: dict[str, tuple[int, int]], root: Path, rules: dict[str, Any], language: str
) -> list[str]:
    """Check source-file completeness and separate threshold ratios.

    A classified file with no LLVM record compiled to no instrumented code: it holds only
    declarations (protocols, stored properties, cases) or is compiled only for iOS. It counts as zero
    lines and is listed. A whole module with no record means its test bundle was not exported, which
    is an error.

    Args:
        totals: Actual per-file (covered, executable) line counts.
        root: Repository root.
        rules: Versioned coverage classification and numeric thresholds.
        language: Language section to validate.

    Returns:
        Errors for unclassified files, unmeasured modules, exclusions and low measured coverage.
    """
    categories, excluded, errors = classify(root, rules, language)
    for name in sorted(excluded):
        if name in totals and totals[name][1] > 0:
            errors.append(f"{language}: executable source cannot be excluded: {name}")
    measured_modules = {module_of(name) for name in totals}
    for category, files in categories.items():
        if category == UNMEASURED:
            continue
        threshold = rules["thresholds"][category]
        missing = files - totals.keys()
        unmeasured = {name for name in missing if module_of(name) not in measured_modules}
        if unmeasured:
            modules = sorted({module_of(name) for name in unmeasured})
            errors.append(
                f"{language}.{category}: no coverage records for module(s) {', '.join(modules)};"
                " export every test bundle that links them"
            )
            continue
        if missing:
            print(
                f"{language}.{category}: {len(missing)} file(s) have no LLVM record (declarations only,"
                f" or compiled only for iOS) and count as 0 lines:{file_list(missing)}"
            )
        covered = sum(totals[name][0] for name in files - missing)
        executable = sum(totals[name][1] for name in files - missing)
        if executable == 0:
            errors.append(f"{language}.{category}: report has zero executable lines")
            continue
        percent = covered * 100 / executable
        print(
            f"{language}.{category}: {covered}/{executable} lines = {percent:.2f}%"
            f" across {len(files)} files (need {threshold}%)"
        )
        if covered * 100 < threshold * executable:
            errors.append(f"{language}.{category}: {percent:.2f}% is below {threshold}%")
    return errors


def check_changed(
    totals: dict[str, tuple[int, int]],
    root: Path,
    rules: dict[str, Any],
    language: str,
    files: list[str],
    baseline: dict[str, float] | None = None,
    dropped: list[str] | None = None,
) -> list[str]:
    """Gate only the changed source files, for a per-PR run of the affected suites.

    Unmeasured files are skipped. Without a baseline each gated category's changed files together must
    meet its threshold. With a baseline (repository-relative path to the percent it had before) a file
    passes when it meets the threshold or does not drop below its baseline, so touching a file that was
    already under the bar does not fail the PR unless it gets worse. Baseline entries for paths that are
    not gated (an old file's `ux` entries) are never read. Files outside every gated category (tests,
    excluded and unmeasured sources, non-Swift) are ignored, and
    a changed file with no LLVM record counts as 0 lines, as in the full gate.

    Args:
        totals: Actual per-file (covered, executable) line counts.
        root: Repository root.
        rules: Versioned coverage classification and numeric thresholds.
        language: Language section to validate.
        files: Changed repository-relative paths.
        baseline: Optional earlier per-file percent.
        dropped: Filenames `llvm_file_totals` skipped as product source under another root. When a
            changed file has no record and this is non-empty, the gate fails loudly instead of
            counting the file as declarations-only.

    Returns:
        Errors for changed files below the bar.
    """
    categories, _, errors = classify(root, rules, language)
    wanted = {Path(name).as_posix() for name in files}
    checked = 0
    for category, members in categories.items():
        if category == UNMEASURED:
            continue
        threshold = rules["thresholds"][category]
        changed = sorted(members & wanted)
        if not changed:
            continue
        covered = sum(totals.get(name, (0, 0))[0] for name in changed)
        executable = sum(totals.get(name, (0, 0))[1] for name in changed)
        checked += len(changed)
        for name in changed:
            if name not in totals:
                if dropped:
                    errors.append(
                        f"{language}.{category}: {name} has no LLVM record, and {len(dropped)} records are"
                        f" under {foreign_prefix(dropped)}, outside this checkout"
                    )
                    continue
                print(f"{language}.{category}: {name} has no LLVM record (declarations only, or compiled only for iOS)")
        if executable == 0:
            print(f"{language}.{category}: {len(changed)} changed file(s), no executable lines")
            continue
        print(
            f"{language}.{category}: changed files {covered}/{executable} lines ="
            f" {covered * 100 / executable:.2f}% across {len(changed)} files (need {threshold}%)"
        )
        if baseline is None:
            if covered * 100 < threshold * executable:
                errors.append(f"{language}.{category}: changed files at {covered * 100 / executable:.2f}% are below {threshold}%")
            continue
        for name in changed:
            done, count = totals.get(name, (0, 0))
            if count == 0 or done * 100 >= threshold * count:
                continue
            before = baseline.get(name)
            percent = done * 100 / count
            if before is None or percent + 0.005 < before:
                errors.append(
                    f"{language}.{category}: {name} is at {percent:.2f}%, below {threshold}%"
                    + (f" and below its baseline {before:.2f}%" if before is not None else "")
                )
    if not checked:
        print(f"{language}: no changed file is subject to coverage; nothing to gate")
    return errors


def main(argv: list[str] | None = None) -> int:
    """Parse LLVM reports and enforce the configured category coverage bars.

    Args:
        argv: Optional command-line arguments.

    Returns:
        Exit status zero only when all measured gates pass.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--language", required=True, choices=("swift",))
    parser.add_argument("--report", type=Path, action="append")
    parser.add_argument(
        "--classify-only",
        action="store_true",
        help="only check that every production source file is classified (no report needed)",
    )
    parser.add_argument(
        "--files",
        nargs="+",
        help="gate only these changed repository-relative files (per-PR run of the affected suites)",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        help='with --files: JSON {"path": percent}; a file under its bar passes if it did not regress',
    )
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--rules", type=Path, default=RULES)
    args = parser.parse_args(argv)
    if not args.classify_only and not args.report:
        parser.error("--report is required unless --classify-only is given")
    try:
        rules = json.loads(args.rules.read_text(encoding="utf-8"))
        if args.classify_only:
            categories, _, errors = classify(args.root, rules, args.language)
            for category, files in categories.items():
                print(f"{args.language}.{category}: {len(files)} source files classified")
        else:
            dropped: list[str] = []
            totals = llvm_file_totals(args.report, args.root, dropped)
            if args.files:
                baseline = json.loads(args.baseline.read_text(encoding="utf-8")) if args.baseline else None
                errors = check_changed(totals, args.root, rules, args.language, args.files, baseline, dropped)
            else:
                errors = check_coverage(totals, args.root, rules, args.language)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"Coverage gate error: {error}", file=sys.stderr)
        return 2
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
