#!/usr/bin/env python3
"""Print the exact lane verdict path a reviewer must write.

Usage: ``tools/review/lane_verdict_path.py LANE [--sha SHA] [--root ROOT]``. The path is ``lane_land.review_path``
under ``<root>/reviews`` (``~/hass-agents`` by default), so it cannot drift from the file ``lane_land`` reads.
Without ``--sha`` the full sha is ``git rev-parse`` of ``refs/remotes/origin/<lane>`` after ``git fetch origin
<lane>``, because ``lane_land`` lands origin's lane, never the local branch. A short or non-hex sha is rejected.
It prints only and writes nothing.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lane_land  # noqa: E402

# lane_land keeps this default inline in its ``--root`` option (no constant to import), so it is repeated here.
DEFAULT_ROOT = os.path.expanduser("~/hass-agents")
REVIEWS_DIR = Path(DEFAULT_ROOT) / "reviews"
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")


def verdict_path(lane: str, sha: str, reviews_dir: Path = REVIEWS_DIR) -> Path:
    """The verdict file for ``(lane, sha)``; raises ``ValueError`` unless ``sha`` is a full 40-character hex sha."""
    if not FULL_SHA.match(sha):
        raise ValueError(f"need the full 40-character sha, got {sha!r}")
    return lane_land.review_path(reviews_dir, lane, sha)


def origin_sha(lane: str) -> str:
    """The head of ``origin/<lane>`` after a fetch; raises ``RuntimeError`` when it cannot be resolved."""
    fetch = subprocess.run(["git", "fetch", "-q", "origin", lane], capture_output=True, text=True)
    if fetch.returncode:
        raise RuntimeError(f"cannot fetch origin {lane!r}: {fetch.stderr.strip()}")
    proc = subprocess.run(["git", "rev-parse", "--verify", "-q", f"refs/remotes/origin/{lane}"],
                          capture_output=True, text=True)
    if proc.returncode:
        raise RuntimeError(f"cannot resolve origin/{lane}")
    return proc.stdout.strip()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("lane")
    parser.add_argument("--sha")
    parser.add_argument("--root", default=DEFAULT_ROOT, help="agent root; verdicts live in <root>/reviews")
    args = parser.parse_args(argv)
    try:
        sha = args.sha if args.sha is not None else origin_sha(args.lane)
        print(verdict_path(args.lane, sha, Path(args.root) / "reviews"))
    except (ValueError, RuntimeError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
