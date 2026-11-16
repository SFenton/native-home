"""Shared plumbing: a runnable-command seam (so tests substitute fakes), JSON helpers and the app and device names."""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, List, Mapping, Optional, Sequence

#: The two halves of a pair, in the order the harness captures them.
REFERENCE = "reference"
CANDIDATE = "candidate"
APPS = (REFERENCE, CANDIDATE)
#: The one bundle id both apps carry; two simulators of one model hold them side by side.
BUNDLE_ID = "com.sfenton.home"
#: Pixel density of every capture (the Duo is 3x), passed to ``agent-device screenshot``.
DEFAULT_DENSITY = 3
HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent


# MARK: - Running commands

@dataclass
class Result:
    """What a command printed and how it ended."""
    code: int
    out: str = ""
    err: str = ""


#: A command runner: ``(argv, env, timeout) -> Result``. Tests pass a fake; production uses :func:`run`.
Runner = Callable[..., Result]


def run(argv: Sequence[str], env: Optional[Mapping[str, str]] = None, timeout: float = 150.0) -> Result:
    """Run ``argv`` and capture its output. A timeout or a missing program is a non-zero ``Result``, not an exception."""
    try:
        done = subprocess.run(list(argv), capture_output=True, text=True, timeout=timeout, env=None if env is None else dict(env))
    except subprocess.TimeoutExpired:
        return Result(124, "", f"timed out after {timeout:g}s: {argv[0]}")
    except OSError as error:
        return Result(127, "", str(error))
    return Result(done.returncode, done.stdout, done.stderr)


# MARK: - JSON

def read_json(path: Path) -> Any:
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: Any) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8")


def parse_json(text: str) -> Optional[Any]:
    """The JSON value in ``text``, or ``None`` when it is not JSON."""
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        return None


def png_size(path: Path) -> Optional[List[int]]:
    """``[width, height]`` from a PNG's IHDR chunk, or ``None`` when the file is not a PNG."""
    try:
        head = Path(path).read_bytes()[:24]
    except OSError:
        return None
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return [int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")]
