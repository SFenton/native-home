#!/usr/bin/env bash
# Removes stale build output, and only build output (.agents/workflow/pr-lifecycle.md).
# Usage: tools/clean.sh [--] PATH...
#   Deletes (rm -rf) each PATH that lies strictly inside one of these roots, built from the main checkout's REAL
#   path plus literal names: build/, apple/.build, apple/.build-*, .claude/worktrees/<name>/build,
#   .claude/worktrees/<name>/apple/.build and .build-*, and the scratchpad /tmp/claude-<uid> (real /tmp path;
#   must be a real directory owned by you). The main checkout is the parent of the git common dir, found from the
#   current directory with GIT_DIR, GIT_COMMON_DIR and GIT_WORK_TREE cleared; no other override exists.
#   A root that is itself a symlink, or that passes through one, is ignored. A path is checked after resolving its
#   PARENT directory only: a symlink argument is unlinked, never followed. The roots themselves are refused.
#   A missing path inside a root is a no-op. Every argument is checked first (and again right before its delete):
#   one refusal exits 1 and deletes nothing more. No globbing here; the shell expands. Arguments that start with
#   `-` are paths (relative to the current directory); `--` as the first argument is skipped.
set -euo pipefail

if [ "${1:-}" = "--" ]; then shift; fi
if [ "$#" -eq 0 ]; then echo "usage: tools/clean.sh [--] PATH..." >&2; exit 2; fi

COMMON="$(env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE git rev-parse --path-format=absolute --git-common-dir)"
REPO="$(dirname "$COMMON")"

HASS_CLEAN_REPO_REAL="$REPO" python3 -I - "$@" <<'PY'
import os, shutil, sys

repo = os.path.realpath(os.environ["HASS_CLEAN_REPO_REAL"])
uid = os.getuid()


def real_dir(path):
    """True when path is a directory reached through no symlink."""
    return os.path.isdir(path) and not os.path.islink(path) and os.path.realpath(path) == path


def build_roots():
    def apple_roots(base):
        out = [os.path.join(base, "build"), os.path.join(base, "apple", ".build")]
        apple = os.path.join(base, "apple")
        if real_dir(apple):
            out += [os.path.join(apple, n) for n in sorted(os.listdir(apple)) if n.startswith(".build-")]
        return out
    roots = apple_roots(repo)
    wts = os.path.join(repo, ".claude", "worktrees")
    if real_dir(wts):
        for name in sorted(os.listdir(wts)):
            roots += apple_roots(os.path.join(wts, name))
    roots = [r for r in roots if real_dir(r)]
    tmp = os.path.join(os.path.realpath("/tmp"), f"claude-{uid}")
    if real_dir(tmp) and os.stat(tmp).st_uid == uid:
        roots.append(tmp)
    return roots


def check(arg):
    """Absolute target (parent resolved, last component literal) or None when not strictly inside a root."""
    path = os.path.abspath(arg)
    name = os.path.basename(path)
    if not name:
        return None
    target = os.path.join(os.path.realpath(os.path.dirname(path)), name)
    for root in build_roots():
        if target.startswith(root + os.sep):
            return target
    return None


targets, bad = [], []
for arg in sys.argv[1:]:
    t = check(arg)
    if t:
        targets.append(t)
    else:
        bad.append(arg)
if bad:
    for arg in bad:
        print(f"clean.sh: refused {arg!r}: not strictly inside an allowed build or scratchpad directory", file=sys.stderr)
    sys.exit(1)
for arg, target in zip(sys.argv[1:], targets):
    if check(arg) != target:
        print(f"clean.sh: refused {arg!r}: changed since it was checked", file=sys.stderr)
        sys.exit(1)
    if os.path.islink(target) or os.path.isfile(target):
        os.unlink(target)
    elif os.path.isdir(target):
        shutil.rmtree(target)
PY
