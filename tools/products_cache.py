#!/usr/bin/env python3
"""The shared cache of built UI-test products (``~/Library/Caches/fenton/testproducts``).

    products_cache.py key [SETTING …]                         the cache key for this tree
    products_cache.py ensure --key K [--dir D] -- BUILD …      hit, or build once under a lock (``@PARTIAL@`` in BUILD is the output path)

The key is a content hash of what the compile reads: every file under ``apple/`` that git tracks or would add (so a clean
tree, a dirty one and the commit made from it agree, and the staging state does not matter), the build settings (sorted) and
the Xcode version. It never sees the environment, the worktree path, the test filter, the plan or the device family, so every
run on the same code shares one build, and ``--impact`` (``CLANG_*`` settings) gets its own.

``ensure`` prints one ``products: hit KEY …`` or ``products: built KEY …`` line, which ``tools/log_digest.py`` copies into the digest.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional, Sequence

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DIR = Path.home() / "Library" / "Caches" / "fenton" / "testproducts"
SUFFIX = ".xctestproducts"
#: Entries unused for this long go, and the whole cache is trimmed least-recently-used to this size.
MAX_AGE_SECONDS = 2 * 24 * 3600
MAX_BYTES = 8 * 1024**3
#: An entry used this recently is never pruned: a run may be reading it with test-without-building.
IN_USE_SECONDS = 2 * 3600
PARTIAL_AGE_SECONDS = 24 * 3600
ENTRY = re.compile(r"^[0-9a-f]{16}\.xctestproducts$")
STRAY = re.compile(r"^[0-9a-f]{16}\.xctestproducts\.xctestproducts$")


def _git_files(root: Path) -> List[str]:
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-co", "--exclude-standard", "-z", "--", "apple"],
                         capture_output=True, text=True)
    return sorted(name for name in out.stdout.split("\0") if name) if out.returncode == 0 else []


def xcode_version() -> str:
    """``xcodebuild -version`` output (empty when Xcode is missing)."""
    return subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True).stdout


def products_key(settings: Sequence[str], root: Path = ROOT, xcode: Optional[str] = None) -> str:
    """Content hash of the apple/ tree, the build settings and Xcode, as 16 hex digits."""
    digest = hashlib.sha256()
    for name in _git_files(root):
        path = root / name
        if not path.is_file():  # deleted in the working tree, or a submodule
            continue
        digest.update(name.encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    digest.update(b"\0settings\0" + "\0".join(sorted(settings)).encode())
    digest.update(b"\0xcode\0" + (xcode_version() if xcode is None else xcode).encode())
    return digest.hexdigest()[:16]


def valid(path: Path) -> bool:
    """True for a complete bundle: a readable Info.plist, a non-empty Binaries and a Tests directory."""
    try:
        with open(path / "Info.plist", "rb") as handle:
            if not isinstance(plistlib.load(handle), dict):
                return False
        return (path / "Tests").is_dir() and (path / "Binaries").is_dir() and any((path / "Binaries").iterdir())
    except (OSError, ValueError, plistlib.InvalidFileException):
        return False
    except Exception:  # an XML parse error from a truncated file
        return False


def _size(path: Path) -> int:
    total = 0
    for base, _dirs, files in os.walk(path):
        for name in files:
            try:
                total += os.lstat(os.path.join(base, name)).st_size
            except OSError:
                pass
    return total


def prune(directory: Path, keep: str = "", now: Optional[float] = None, max_age: float = MAX_AGE_SECONDS,
          max_bytes: int = MAX_BYTES) -> List[str]:
    """Delete stray, stale-partial and too-old entries, then least-recently-used ones past the size cap. Returns what it removed.

    An entry used within IN_USE_SECONDS, and ``keep``, are never removed by age or size.
    """
    now = time.time() if now is None else now
    removed: List[str] = []

    def drop(path: Path) -> None:
        shutil.rmtree(path, ignore_errors=True) if path.is_dir() else path.unlink(missing_ok=True)
        removed.append(path.name)
        stem = path.name.split(SUFFIX)[0]
        if ENTRY.match(path.name):
            for extra in (directory / f"{stem}.lock", directory / f"{stem}.json"):
                extra.unlink(missing_ok=True)

    if not directory.is_dir():
        return removed
    entries = []
    for path in directory.iterdir():
        name = path.name
        age = now - path.stat().st_mtime
        if STRAY.match(name):
            drop(path)
        elif ".partial." in name:
            if age > PARTIAL_AGE_SECONDS:
                drop(path)
        elif ENTRY.match(name):
            if not valid(path) and age > IN_USE_SECONDS:
                drop(path)
            else:
                entries.append((path, age))
    live = []
    for path, age in entries:
        if age > max_age and path.name != keep + SUFFIX:
            drop(path)
        else:
            live.append((path, age))
    sizes = {path: _size(path) for path, _ in live}
    total = sum(sizes.values())
    for path, age in sorted(live, key=lambda item: -item[1]):  # oldest use first
        if total <= max_bytes:
            break
        if age < IN_USE_SECONDS or path.name == keep + SUFFIX:
            continue
        total -= sizes[path]
        drop(path)
    # Lock files whose entry is gone.
    for lock in directory.glob("*.lock"):
        if not (directory / (lock.stem + SUFFIX)).exists() and now - lock.stat().st_mtime > PARTIAL_AGE_SECONDS:
            lock.unlink(missing_ok=True)
    return removed


def ensure(key: str, command: Sequence[str], directory: Path = DEFAULT_DIR, out=sys.stdout) -> int:
    """Return 0 with a valid bundle at ``directory/key.xctestproducts``: a hit, or one build under a per-key lock.

    A second caller needing the same missing key waits for the lock and then hits. Returns the build's status when it fails.
    """
    directory.mkdir(parents=True, exist_ok=True)
    final = directory / (key + SUFFIX)
    meta = directory / (key + ".json")

    def say(text: str) -> None:
        print(f"products: {text}", file=out, flush=True)

    def hit(waited: float = 0.0) -> int:
        os.utime(final)
        try:
            saved = json.loads(meta.read_text())["build_seconds"]
        except (OSError, ValueError, KeyError):
            saved = None
        extra = f", saved ~{saved:.0f}s of compile" if saved else ""
        wait = f", waited {waited:.0f}s for another run's build" if waited >= 1 else ""
        say(f"hit {key}{extra}{wait}")
        prune(directory, keep=key)
        return 0

    if valid(final):
        return hit()
    asked = time.time()
    with open(directory / (key + ".lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if valid(final):
            return hit(time.time() - asked)
        if final.exists():  # present but not valid: a corrupt entry is never used
            shutil.rmtree(final, ignore_errors=True)
        partial = directory / f"{key}.partial.{os.getpid()}{SUFFIX}"
        shutil.rmtree(partial, ignore_errors=True)
        started = time.time()
        status = subprocess.run([str(partial) if arg == "@PARTIAL@" else arg for arg in command]).returncode
        elapsed = time.time() - started
        if status != 0:
            shutil.rmtree(partial, ignore_errors=True)
            return status
        if not valid(partial):
            shutil.rmtree(partial, ignore_errors=True)
            print(f"ERROR: build succeeded but {partial.name} is not a complete test-products bundle", file=sys.stderr)
            return 1
        os.rename(partial, final)
        meta.write_text(json.dumps({"build_seconds": elapsed, "built_at": time.time()}))
        say(f"built {key} in {elapsed:.0f}s")
        prune(directory, keep=key)
        return 0


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "key":
        print(products_key(argv[1:], Path(os.environ.get("FENTON_ROOT", ROOT))))
        return 0
    if argv[:1] != ["ensure"] or "--" not in argv:
        print(__doc__, file=sys.stderr)
        return 2
    split = argv.index("--")
    parser = argparse.ArgumentParser(prog="products_cache.py ensure")
    parser.add_argument("command")
    parser.add_argument("--key", required=True)
    parser.add_argument("--dir", type=Path, default=DEFAULT_DIR)
    args = parser.parse_args(argv[:split])
    return ensure(args.key, argv[split + 1:], args.dir)


if __name__ == "__main__":
    sys.exit(main())
