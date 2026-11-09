#!/usr/bin/env python3
"""Build the clean one-commit snapshot that ``tools/go_public.sh`` publishes (owner, 2026-11-07).

    python3 tools/public_snapshot.py OUT_DIR [--ref origin/main]
    tools/go_public.sh OUT_DIR SFenton/native-home

The blobs of ``--ref``'s tree (``git ls-tree -r`` plus ``git cat-file``, so no archive attributes, ignore rules or filters apply) are written
into an empty ``OUT_DIR``, minus ``PRIVATE_ONLY``; then ``git init -b main`` and one commit authored and committed by
``S+H <noreply@example.com>`` ("Initial public snapshot"). Every git call runs in a scrubbed environment (no ``GIT_*`` variable from the
caller, no system or global config, an empty template, hooks off, fixed dates). The tool then verifies and fails closed: the committed tree must
equal the ref's tree minus ``PRIVATE_ONLY`` (mode, blob id, path), the identity must be exactly neutral, and there must be no remote, tag, other
ref or hook.

``PRIVATE_ONLY`` is the only exclude list and lives in this file: it is never read from the snapshotted tree, so the tree cannot widen it.
Add a path only when it is private by nature, never to hide a scan hit. Prints counts and the left-out paths only.

Standard library only. Documentation: .agents/workflow/pr-lifecycle.md ("Going public").
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path
from typing import Dict, List, Optional, Tuple

REPO = Path(__file__).resolve().parent.parent
IDENTITY_NAME, IDENTITY_EMAIL = "S+H", "noreply@example.com"
IDENTITY = f"{IDENTITY_NAME} <{IDENTITY_EMAIL}>"
MESSAGE = "Initial public snapshot"
DATE = "2026-11-07T00:00:00+0000"

#: Private-only paths (exact file paths) and the reason each stays out of the public snapshot.
PRIVATE_ONLY: Dict[str, str] = {
    ".gitleaksignore": "fingerprints name this repository's private commits, which a single-commit history does not have",
}

Entry = Tuple[str, str, str]  # (mode, blob id, path)


def scrubbed_env(home: Path) -> Dict[str, str]:
    """The only environment git sees: ``PATH``, a throwaway ``HOME``, no system or global config, the neutral identity and fixed dates.
    Nothing else is copied, so no ``GIT_*`` variable (git-dir, index, template, author, committer) can reach it."""
    return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(home), "LC_ALL": "C", "TZ": "UTC",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": IDENTITY_NAME, "GIT_AUTHOR_EMAIL": IDENTITY_EMAIL, "GIT_AUTHOR_DATE": DATE,
            "GIT_COMMITTER_NAME": IDENTITY_NAME, "GIT_COMMITTER_EMAIL": IDENTITY_EMAIL, "GIT_COMMITTER_DATE": DATE}


def run_git(repo: Path, env: Dict[str, str], *args: str, data: Optional[bytes] = None) -> bytes:
    """``git -C repo ...`` in ``env`` with hooks off; fails closed (``SystemExit``) on a non-zero exit."""
    proc = subprocess.run(["git", "-C", str(repo), "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", *args],
                          env=env, input=data, capture_output=True)
    if proc.returncode:
        raise SystemExit(f"public_snapshot: git {args[0]} failed")
    return proc.stdout


def tree_entries(repo: Path, ref: str, env: Dict[str, str]) -> List[Entry]:
    """Every file of ``ref``'s tree as ``(mode, blob id, path)``, sorted by path. Submodules and other non-blobs are refused."""
    entries = []
    for record in run_git(repo, env, "ls-tree", "-r", "-z", "--full-tree", ref).split(b"\0"):
        if not record:
            continue
        meta, _, raw = record.partition(b"\t")
        mode, kind, sha = meta.decode().split()
        if kind != "blob":
            raise SystemExit(f"public_snapshot: {kind} entry in the tree (fails closed)")
        entries.append((mode, sha, raw.decode("utf-8", "surrogateescape")))
    return sorted(entries, key=lambda e: e[2])


def safe_path(out: Path, rel: str) -> Path:
    """``out / rel`` or ``SystemExit``: refuses an absolute path, ``..``, ``.``, a ``.git`` component and a parent that is a symlink."""
    parts = rel.split("/")
    if not rel or rel.startswith("/") or any(p in ("", ".", "..") or p.lower() == ".git" for p in parts):
        raise SystemExit("public_snapshot: unsafe path in the tree (fails closed)")
    cursor = out
    for part in parts[:-1]:
        cursor = cursor / part
        if cursor.is_symlink():
            raise SystemExit("public_snapshot: path goes through a symlink (fails closed)")
    return out / rel


def fold(path: str) -> str:
    """The name a case-insensitive or normalising filesystem would give ``path``: NFD, casefolded, back to NFC."""
    return unicodedata.normalize("NFC", unicodedata.normalize("NFD", path).casefold())


def refuse_collisions(entries: List[Entry]) -> None:
    """``SystemExit`` when two paths (or a file and a directory prefix) are the same name after case-folding or Unicode normalisation,
    so no write can land on an earlier entry (a ``Link`` symlink and a ``link`` file) on a case-insensitive filesystem."""
    files, dirs = {}, set()
    for _, _, rel in entries:
        key = fold(rel)
        if key in files or key in dirs:
            raise SystemExit("public_snapshot: two paths collide after case-folding or normalisation (fails closed)")
        files[key] = rel
        parts = key.split("/")
        for i in range(1, len(parts)):
            prefix = "/".join(parts[:i])
            if prefix in files:
                raise SystemExit("public_snapshot: a path is both a file and a directory after case-folding (fails closed)")
            dirs.add(prefix)


def write_entries(repo: Path, entries: List[Entry], out: Path, env: Dict[str, str]) -> int:
    """Write each entry's blob under ``out`` (regular files, executable bit, symlinks); any other mode is refused. Returns the count."""
    for mode, _, _ in entries:
        if mode not in ("100644", "100755", "120000"):
            raise SystemExit(f"public_snapshot: unsupported mode {mode} (fails closed)")
    for _, _, rel in entries:
        safe_path(out, rel)  # refuse before anything is written
    refuse_collisions(entries)
    # one process for all blobs: `<sha> blob <size>\n<bytes>\n` per object
    batch = run_git(repo, env, "cat-file", "--batch", data="".join(f"{sha}\n" for _, sha, _ in entries).encode()) if entries else b""
    cursor = 0
    for mode, sha, rel in entries:
        header_end = batch.index(b"\n", cursor)
        got, kind, size = batch[cursor:header_end].decode().split()
        if got != sha or kind != "blob":
            raise SystemExit("public_snapshot: unexpected object (fails closed)")
        content = batch[header_end + 1: header_end + 1 + int(size)]
        cursor = header_end + 1 + int(size) + 1
        target = safe_path(out, rel)
        cursor_dir = out
        for part in rel.split("/")[:-1]:
            cursor_dir = cursor_dir / part
            try:
                os.mkdir(cursor_dir)  # never follows a symlink: an existing entry raises
            except FileExistsError:
                if cursor_dir.is_symlink() or not cursor_dir.is_dir():
                    raise SystemExit("public_snapshot: directory is not a plain directory (fails closed)")
        if mode == "120000":
            os.symlink(content.decode("utf-8", "surrogateescape"), target)
        else:
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o755 if mode == "100755" else 0o644)
            os.fchmod(fd, 0o755 if mode == "100755" else 0o644)
            with os.fdopen(fd, "wb") as handle:
                handle.write(content)
    return len(entries)


def verify(out: Path, expected: List[Entry], env: Dict[str, str]) -> None:
    """Fail closed unless the snapshot is exactly ``expected`` with the neutral identity and no remote, tag, extra ref or hook."""
    if tree_entries(out, "HEAD", env) != expected:
        raise SystemExit("public_snapshot: the committed tree differs from the ref's tree (fails closed)")
    who = run_git(out, env, "log", "-1", "--format=%an <%ae>%n%cn <%ce>").decode().split("\n")[:2]
    if who != [IDENTITY, IDENTITY]:
        raise SystemExit("public_snapshot: the commit identity is not the neutral one (fails closed)")
    if run_git(out, env, "rev-list", "--all", "--count").strip() != b"1":
        raise SystemExit("public_snapshot: more than one commit (fails closed)")
    if run_git(out, env, "for-each-ref", "--format=%(refname)").split() != [b"refs/heads/main"] or run_git(out, env, "tag").strip():
        raise SystemExit("public_snapshot: refs other than main (fails closed)")
    remotes = subprocess.run(["git", "-C", str(out), "config", "--local", "--get-regexp", r"^remote\."], env=env, capture_output=True)
    if run_git(out, env, "remote").strip() or remotes.stdout.strip():
        raise SystemExit("public_snapshot: the snapshot has a remote (fails closed)")
    hooks = out / ".git" / "hooks"
    if hooks.is_dir() and [h for h in hooks.iterdir() if not h.name.endswith(".sample")]:
        raise SystemExit("public_snapshot: the snapshot has a hook (fails closed)")


def build(out: Path, ref: str = "origin/main", repo: Path = REPO) -> Dict[str, object]:
    """Write the snapshot of ``ref`` (from ``repo``) into the empty ``out``, commit it and verify it.
    Returns ``{"files": committed count, "left_out": [...]}``."""
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        raise SystemExit(f"public_snapshot: {out} is not empty")
    with tempfile.TemporaryDirectory() as scratch:
        env = scrubbed_env(Path(scratch))
        template = Path(scratch) / "template"
        template.mkdir()
        everything = tree_entries(repo, ref, env)
        expected = [e for e in everything if e[2] not in PRIVATE_ONLY]
        left_out = [e[2] for e in everything if e[2] in PRIVATE_ONLY]
        write_entries(repo, expected, out, env)
        run_git(out, env, "init", "-q", "-b", "main", f"--template={template}")
        run_git(out, env, "-c", "core.excludesFile=/dev/null", "add", "--force", "-A")
        run_git(out, env, "commit", "-q", "--no-verify", "-m", MESSAGE)
        verify(out, expected, env)
    return {"files": len(expected), "left_out": left_out}


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("--ref", default="origin/main")
    args = parser.parse_args(argv)
    result = build(args.out_dir, args.ref)
    print(f"public_snapshot: {result['files']} file(s) committed, {len(result['left_out'])} left out")
    for path in result["left_out"]:
        print(f"public_snapshot: left out {path} ({PRIVATE_ONLY[path]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
