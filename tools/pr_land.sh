#!/usr/bin/env bash
# Arms auto-merge on a pull request after the gates GitHub cannot run (.agents/workflow/pr-lifecycle.md); GitHub merges when the required checks pr-checks and ai-review pass.
# Usage: tools/pr_land.sh N [--dry-run] [--owner-ack]
#   Checks the kill switch, Needs Decision, conflicts, author and fork, the base (main), the reviewer's pass for the exact head, the live ruleset,
#   the app-UI gate (a design record + Jev's verdict, tools/lane_land.py gate; the owner's flag skips it and is refused outside the owner's own
#   terminal) and the house denylist, then runs gh pr merge N --auto --squash --match-head-commit HEAD.
#   Prints one line: `armed #N ...`, `merged #N ...`, `would arm #N ...`, `blocked #N: reason` or `failed #N: reason`.
#   Exit 0 armed or merged (or dry-run would arm), 1 blocked, 2 failed.
exec python3 "$(dirname "$0")/pr_land.py" "$@"
