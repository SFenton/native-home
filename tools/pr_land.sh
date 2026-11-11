#!/usr/bin/env bash
# Arms auto-merge on a pull request after the gates GitHub cannot run (.agents/workflow/pr-lifecycle.md); GitHub merges when the required checks pr-checks and ai-review pass.
# Usage: tools/pr_land.sh N [--dry-run]
#   Checks the kill switch, Needs Decision, conflicts, author and fork, the base (main), the reviewer's pass for the exact head, the live ruleset,
#   the app-UI gate (a design record + Jev's verdict, tools/lane_land.py gate; there is no override flag: an owner-kept-set or park refusal is cleared when the owner
#   approves this pull request on GitHub (their review of this exact head) and merges it there; a missing design record is the agent's to fix) and the house denylist, then runs gh pr merge N --auto --squash --match-head-commit HEAD.
#   Prints a last line: `armed #N ...`, `merged #N ...`, `would arm #N ...`, `blocked #N: reason` or `failed #N: reason`. Before it, for a PR that
#   touches a CODEOWNERS path and is left only to the owner (code-owner review, a draft, the owner-kept set), it prints the owner's three gh commands.
#   Exit 0 armed or merged (or dry-run would arm), 1 blocked, 2 failed.
exec python3 "$(dirname "$0")/pr_land.py" "$@"
