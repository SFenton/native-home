#!/usr/bin/env bash
# Owner-only safety checks for committing and pushing (owner approved the split 2026-11-04). Used by tools/ship.sh and by
# tools/hooks/commit_guard.py, so bypassing ship.sh does not bypass the guard.
#
# Usage: tools/ship_guard.sh [branch|staged|all]      (default: all; run inside the checkout to check)
#   branch  refuse on main, master or a detached HEAD
#   staged  refuse when staged files (git diff --cached) are env files, .p12, .p8 or .mobileprovision (.env.example is fine);
#           resets the index first, like ship.sh always did, unless SHIP_GUARD_NO_RESET=1;
#           SHIP_GUARD_INCLUDE_WORKTREE=1 also checks modified tracked files (for `git commit -a`)
# Exit 0 when clean; exit 1 with the message on stderr.
# Edits to this file need the owner's CODEOWNERS approval (.github/CODEOWNERS; it is not in tools/lane_land.py DEFAULT_PROTECTED; tools/tests/test_ship_guard_wiring.py pins the patterns).
set -euo pipefail

check_branch() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  case "$branch" in
    main|master|HEAD) echo "ship: refusing to commit on '$branch'; make a lane first (tools/lane_new.sh)" >&2; return 1 ;;
  esac
}

check_staged() {
  local files bad
  files="$(git diff --cached --name-only)"
  if [[ "${SHIP_GUARD_INCLUDE_WORKTREE:-}" == 1 ]]; then files+=$'\n'"$(git diff --name-only)"; fi
  if bad="$(printf '%s\n' "$files" | grep -E '(^|/)(\.env[^/]*|[^/]*\.env|[^/]*\.p12|[^/]*\.p8|[^/]*\.mobileprovision)$' | grep -v '\.env\.example$' || true)" && [[ -n "$bad" ]]; then
    [[ "${SHIP_GUARD_NO_RESET:-}" == 1 ]] || git reset -q
    echo "ship: refusing, these must never be committed:" >&2; echo "$bad" >&2
    return 1
  fi
}

case "${1:-all}" in
  branch) check_branch ;;
  staged) check_staged ;;
  all) check_branch && check_staged ;;
  *) echo "usage: ship_guard.sh [branch|staged|all]" >&2; exit 2 ;;
esac
