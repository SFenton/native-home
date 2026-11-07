#!/usr/bin/env bash
# Publish a clean snapshot of this repository as a new public repository (owner, 2026-11-07): the one way an agent goes public.
#
# Usage: tools/go_public.sh SNAPSHOT_DIR OWNER/REPO
#
# 1. tools/go_public_gate.py SNAPSHOT_DIR runs first (trusted base config, every file type, one orphan commit, gitleaks, a denylist of
#    20+ terms). Nothing is created or pushed unless it exits 0.
# 2. gh repo create OWNER/REPO --private, push the snapshot, then make it public.
#
# merge_guard refuses `gh repo create --public`, `gh repo edit --visibility`, a visibility change through `gh api` and a `git push` to
# any remote that is not this repository's origin, and pins this script, the gate and house_scan.py to origin/main for agent sessions.
# Documentation: .agents/workflow/pr-lifecycle.md ("Going public").
set -euo pipefail

SNAPSHOT="${1:?usage: tools/go_public.sh SNAPSHOT_DIR OWNER/REPO}"
TARGET="${2:?usage: tools/go_public.sh SNAPSHOT_DIR OWNER/REPO}"
[[ $# -eq 2 ]] || { echo "usage: tools/go_public.sh SNAPSHOT_DIR OWNER/REPO" >&2; exit 2; }
[[ "$TARGET" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "go_public: $TARGET is not OWNER/REPO" >&2; exit 2; }
[[ -d "$SNAPSHOT" ]] || { echo "go_public: $SNAPSHOT is not a directory" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT="$(cd "$SNAPSHOT" && pwd -P)"
case "$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')" in
  sfenton/fenton-hass-native|sfenton/fenton-hass-req*) echo "go_public: $TARGET is a private repository of this project (the product or its request repository), not a new public one" >&2; exit 2 ;;
esac

git -C "$HERE/.." fetch -q origin main  # the gate reads the trusted house_scan config from origin/main
python3 "$HERE/go_public_gate.py" "$SNAPSHOT" --base-ref origin/main

gh repo create "$TARGET" --private
git -C "$SNAPSHOT" -c core.hooksPath=/dev/null push "https://github.com/$TARGET.git" HEAD:refs/heads/main
gh repo edit "$TARGET" --visibility public --accept-visibility-change-consequences
echo "go_public: https://github.com/$TARGET is public"
