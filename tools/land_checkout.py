#!/usr/bin/env python3
"""Print a clean checkout of ``origin/main`` to land from.

``tools/hooks/merge_guard.py`` lets an agent run ``tools/pr_land.sh N`` only from a checkout whose landing files equal
``origin/<base>``'s. A session checkout that fell behind, or holds other sessions' edits, fails that check, and nothing here repairs it.
This tool keeps one detached worktree of ``origin/main`` at ``build/land-main`` of the checkout it runs from (git-ignored, and inside the main session's working directories, where a
``cd`` persists): it fetches, moves the
tree to ``origin/main`` (recreating it when it is missing, broken or has local edits), and checks it with the guard's own
:func:`merge_guard.pr_land_matches_base`. The last line is ``land from: <path>``, or ``land from: failed`` (exit 1) when the fetch
did not work or the tree still differs. Then, in the main session: ``cd <path>``, ``tools/pr_land.sh N``.

Usage: ``python3 tools/land_checkout.py [--path PATH] [--remote origin] [--branch BASE]``. ``--path`` overrides the tree; ``--branch`` defaults to the guard's first base branch.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, Optional, Sequence, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent / "hooks"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import merge_guard  # noqa: E402  (the byte-check this tree must pass)

DEFAULT_SUBPATH = Path("build") / "land-main"
#: Variables that would point git at another repository.
_SELECTORS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES")


class LandCheckoutError(Exception):
    """The tree could not be prepared; the message is the reason printed with ``failed``."""


def git(where: Path, *args: str, hardened: bool = False) -> subprocess.CompletedProcess:
    """Run git in ``where`` without the repository-selecting variables, never prompting. ``hardened`` also refuses the ``ext`` transport."""
    env = {k: v for k, v in os.environ.items() if k not in _SELECTORS}
    env["GIT_TERMINAL_PROMPT"] = "0"
    prefix = ["-c", "protocol.ext.allow=never"] if hardened else []
    return subprocess.run(["git", "-C", str(where), *prefix, *args], capture_output=True, text=True, timeout=300, env=env)


def need(where: Path, *args: str, hardened: bool = False) -> str:
    """Stdout of a git command that must succeed, else :class:`LandCheckoutError`."""
    try:
        proc = git(where, *args, hardened=hardened)
    except (OSError, subprocess.SubprocessError) as exc:
        raise LandCheckoutError(f"git {args[0]}: {exc}") from exc
    if proc.returncode != 0:
        raise LandCheckoutError(f"git {args[0]} failed: {(proc.stderr or proc.stdout).strip()[:200]}")
    return proc.stdout.strip()


def default_path(top: Path) -> Path:
    """The land tree inside the caller's checkout, under git-ignored ``build/``: the main session's ``cd`` persists only there."""
    return top / DEFAULT_SUBPATH


def registered_worktrees(top: Path) -> Dict[Path, bool]:
    """The linked and main worktrees of this repository as ``{real path: detached HEAD}``, from ``git worktree list --porcelain``."""
    found: Dict[Path, bool] = {}
    path: Optional[Path] = None
    for line in need(top, "worktree", "list", "--porcelain").splitlines() + [""]:
        if line.startswith("worktree "):
            path = Path(line[len("worktree "):]).resolve()
            found[path] = False
        elif line == "detached" and path is not None:
            found[path] = True
    return found


def is_clean_worktree(tree: Path, common: Path) -> bool:
    """Is ``tree`` itself the top of a worktree of this repository, on a detached HEAD, with no tracked change and no untracked file?

    A plain subfolder of another checkout is no worktree: ``git`` answers for the checkout that holds it, so the top must equal ``tree``."""
    if not tree.is_dir():
        return False
    try:
        if Path(need(tree, "rev-parse", "--show-toplevel")).resolve() != tree.resolve():
            return False
        if Path(need(tree, "rev-parse", "--path-format=absolute", "--git-common-dir")).resolve() != common.resolve():
            return False
        if git(tree, "symbolic-ref", "-q", "HEAD").returncode == 0:
            return False
        return need(tree, "status", "--porcelain", "--untracked-files=all") == ""
    except LandCheckoutError:
        return False


def recreate(top: Path, tree: Path, ref: str) -> None:
    """Replace ``tree`` with a fresh detached worktree of ``ref``, deleting only what is safe to delete.

    Deleted: a registered detached worktree of this repository (never the caller's own top or a folder that holds it), or the default
    ``build/land-main`` folder when it is no worktree. Anything else that exists and is not empty is refused, so a wrong ``--path``
    (the caller, ``build``, a branch worktree, an unrelated folder) loses nothing."""
    real = tree.resolve()
    if real == top.resolve() or real in top.resolve().parents:
        raise LandCheckoutError(f"{tree} is or holds the checkout this runs from; refusing to touch it")
    worktrees = registered_worktrees(top)
    if real in worktrees:
        if not worktrees[real]:
            raise LandCheckoutError(f"{tree} is a worktree on a branch, not a detached land tree; refusing to remove it")
        need(top, "worktree", "remove", "--force", str(tree))
    elif tree.exists() and any(tree.iterdir()):
        if real != (top / DEFAULT_SUBPATH).resolve():
            raise LandCheckoutError(f"{tree} exists and is not a land worktree; refusing to delete it")
        shutil.rmtree(tree)
    git(top, "worktree", "prune")
    tree.parent.mkdir(parents=True, exist_ok=True)
    need(top, "worktree", "add", "--detach", "--force", str(tree), ref)


def prepare(top: Path, tree: Path, remote: str, base: str) -> Tuple[Path, str]:
    """Fetch ``remote/base`` and put ``tree`` on it. Returns ``(tree, action)`` with action ``created``, ``recreated`` or ``advanced``;
    raises :class:`LandCheckoutError` when the fetch fails or the tree still differs from the base for the guard."""
    ref = f"refs/remotes/{remote}/{base}"
    need(top, "fetch", "-q", "--no-tags", "--no-recurse-submodules", remote, f"+refs/heads/{base}:{ref}", hardened=True)
    common = Path(need(top, "rev-parse", "--path-format=absolute", "--git-common-dir"))
    if tree.resolve() == top.resolve() or tree.resolve() in top.resolve().parents:
        raise LandCheckoutError(f"{tree} is or holds the checkout this runs from; refusing to touch it")
    existed = tree.exists()
    if is_clean_worktree(tree, common):
        need(tree, "checkout", "-q", "--detach", ref)
        action = "advanced"
    else:
        recreate(top, tree, ref)
        action = "recreated" if existed else "created"
    if need(tree, "rev-parse", "HEAD") != need(top, "rev-parse", f"{ref}^{{commit}}"):
        raise LandCheckoutError(f"{tree} is not at {remote}/{base}")
    if not merge_guard.pr_land_matches_base("tools/pr_land.sh", str(tree / "tools" / "pr_land.sh")):
        raise LandCheckoutError(f"{tree}: the pr_land files merge_guard pins still differ from {remote}/{base}")
    return tree, action


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Print ``land from: <path>`` (exit 0) or ``land from: failed`` after the reason on stderr (exit 1)."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--path", help="the land tree (default: build/land-main in this checkout)")
    parser.add_argument("--remote", default="origin")
    parser.add_argument("--branch", help="the base branch (default: the merge guard's first base)")
    args = parser.parse_args(argv)
    try:
        top = Path(need(Path.cwd(), "rev-parse", "--show-toplevel"))
        base = args.branch or merge_guard.base_refs()[0]
        tree, action = prepare(top, Path(args.path) if args.path else default_path(top), args.remote, base)
    except LandCheckoutError as exc:
        print(f"land_checkout: {exc}", file=sys.stderr)
        print("land from: failed")
        return 1
    print(f"land_checkout: {action} at {args.remote}/{args.branch or base}", file=sys.stderr)
    print(f"land from: {tree}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
