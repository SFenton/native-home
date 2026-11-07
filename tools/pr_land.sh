#!/usr/bin/env bash
# Lands a pull request: the only sanctioned way for an agent to merge (.agents/workflow/pr-lifecycle.md).
# Usage: tools/pr_land.sh N [--dry-run] [--review FILE] [--owner-ack]
#   Merges (squash) only when checks are green on the head SHA (or none are configured) and the recorded review
#   (build/review/<branch>.json, written by tools/review/record.py) passes. A PR that touches app UI also needs the app-UI gate (a design record + Jev's verdict, tools/lane_land.py pr_gate);
#   --owner-ack skips it and is refused outside the owner's own terminal. Then deletes the remote branch, removes
#   the lane worktree and prints one line: `merged #N ...`, `blocked #N: reason` or `failed #N: reason`.
#   Exit 0 merged (or dry-run would merge), 1 blocked, 2 failed.
exec python3 "$(dirname "$0")/pr_land.py" "$@"
