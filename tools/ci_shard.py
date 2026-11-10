#!/usr/bin/env python3
"""Deterministic, balanced shards of the core Python tool tests (``tools/tests``) for the pr-checks matrix.

    python3 tools/ci_shard.py --shard I --of N      the test modules of shard I (0-based), one per line

Every ``tools/tests/test*.py`` module lands in exactly one of the N shards, so the shards together run what
``unittest discover -s tools/tests`` runs. Modules are placed longest-first onto the lightest shard (ties go to the lowest
shard index, then the module name), so the split depends only on the module names and ``tools/ci_shard_weights.json``
(seconds per module, measured once; refresh it when a shard drifts far from the others). A module with no recorded weight
gets the median of the recorded ones, so a new test file is still run, and run once.

``tools/run_tool_tests.sh core`` uses this when ``FENTON_TOOL_SHARD=I/N`` is set (the hosted workflow sets it per matrix leg).

Stdlib only (Linux and macOS system Python 3.9).
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path
from typing import Dict, List, Mapping, Optional, Sequence

HERE = Path(__file__).resolve().parent
TESTS_DIR = HERE / "tests"
WEIGHTS_FILE = HERE / "ci_shard_weights.json"


def discover_modules(tests_dir: Path = TESTS_DIR) -> List[str]:
    """Sorted module names of the ``test*.py`` files directly under ``tests_dir`` (the files ``unittest discover`` imports)."""
    return sorted(path.stem for path in tests_dir.glob("test*.py") if path.is_file())


def load_weights(path: Path = WEIGHTS_FILE) -> Dict[str, float]:
    """``{module: seconds}`` from the weights file; empty when the file is missing."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    return {str(name): float(seconds) for name, seconds in data.items() if not str(name).startswith("_")}


def assign(modules: Sequence[str], weights: Mapping[str, float], count: int) -> List[List[str]]:
    """Split ``modules`` into ``count`` shards of similar total weight; each shard's modules are sorted by name."""
    if count < 1:
        raise ValueError("shard count must be at least 1")
    known = [weights[name] for name in modules if name in weights]
    fallback = statistics.median(known) if known else 1.0
    ordered = sorted(set(modules), key=lambda name: (-weights.get(name, fallback), name))
    shards: List[List[str]] = [[] for _ in range(count)]
    totals = [0.0] * count
    for name in ordered:
        lightest = min(range(count), key=lambda index: (totals[index], index))
        shards[lightest].append(name)
        totals[lightest] += weights.get(name, fallback)
    return [sorted(shard) for shard in shards]


def shard_modules(index: int, count: int, tests_dir: Path = TESTS_DIR, weights_file: Path = WEIGHTS_FILE) -> List[str]:
    """The modules of shard ``index`` (0-based) of ``count``."""
    if not 0 <= index < count:
        raise ValueError("shard %d is outside 0..%d" % (index, count - 1))
    return assign(discover_modules(tests_dir), load_weights(weights_file), count)[index]


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Print the modules of one shard; exit 2 on a bad shard number."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--shard", type=int, required=True, help="0-based shard index")
    parser.add_argument("--of", type=int, required=True, help="number of shards")
    args = parser.parse_args(argv)
    try:
        modules = shard_modules(args.shard, args.of)
    except ValueError as error:
        print("ci_shard: %s" % error, file=sys.stderr)
        return 2
    for name in modules:
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
