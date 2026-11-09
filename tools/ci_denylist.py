#!/usr/bin/env python3
"""Registers the decoded denylist's terms as log masks for the denylist-scan job (hosted CI, .agents/workflow/ci.md). Prints no term but the
`::add-mask::` commands the runner consumes (they make a logged term show as ***).

    ci_denylist.py mask FILE

The scan itself is `tools/house_scan.py denylist` (house-data-gate.md). Stdlib only.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Optional, Sequence


def terms(text: str) -> list:
    """The denylist terms of a file's text: one per line, blank lines and ``#`` comments dropped."""
    return [line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("#")]


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("mask").add_argument("file")
    args = parser.parse_args(argv)
    for term in terms(Path(args.file).read_text(encoding="utf-8", errors="replace")):
        print("::add-mask::" + term)
    return 0


if __name__ == "__main__":
    sys.exit(main())
