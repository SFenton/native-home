#!/usr/bin/env bash
# Commit everything tracked or new (minus .gitignore), push the branch and optionally open the PR.
# Replaces the hand-built trailer, `git add -A`, push and `gh pr create` / assignee sequence.
#
# Usage: tools/ship.sh "Subject line" [--note TEXT] [--body-file FILE | --body TEXT] [--pr] [--draft] [--base main] [--no-push]
#   Before the push it prints the advisory preflight review (tools/preflight_review.py); it never fails the ship.
#   --note TEXT   adds a `Release-Note: TEXT` trailer (what users will notice; `none` = nothing user-facing)
#                  for versioning (.agents/workflow/versioning.md); may be repeated
#   Refuses on main/master and when the change includes env files, keys or provisioning profiles.
#   SHIP_COAUTHOR  trailer identity (default "Claude Sonnet 5.5 <noreply@anthropic.com>")
#   SHIP_ASSIGNEE  PR assignee (default SFenton)
#   SHIP_TASK      task id; after the PR opens runs `tools/pr_note.py init --task $SHIP_TASK` (fail-safe, never blocks)
#   The refusals live in tools/ship_guard.sh (owner-only) and are also enforced on raw git commit/push by tools/hooks/commit_guard.py.
#   --pr always opens a draft (--draft is accepted and implied): review and landing come afterwards, and
#   tools/pr_land.sh marks it ready once checks and the review pass. ship.sh never merges (pr-lifecycle.md).
#   Without --pr only the branch is pushed.
set -euo pipefail

SUBJECT="${1:-}"
[[ -n "$SUBJECT" && "$SUBJECT" != -* ]] || { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift
NOTES=(); BODY=""; PR=0; DRAFT=0; BASE="main"; PUSH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --note) NOTES+=("$2"); shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --body-file) BODY="$(cat "$2")"; shift 2 ;;
    --pr) PR=1; shift ;;
    --draft) DRAFT=1; shift ;;
    --base) BASE="$2"; shift 2 ;;
    --no-push) PUSH=0; shift ;;
    *) echo "ship: unknown option $1" >&2; exit 2 ;;
  esac
done

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
GUARD="$(dirname "$0")/ship_guard.sh"   # owner-only safety checks (branch, secrets)
"$GUARD" branch

git add -A
"$GUARD" staged

COAUTHOR="${SHIP_COAUTHOR:-Claude Sonnet 5.5 <noreply@anthropic.com>}"
if git diff --cached --quiet; then
  echo "ship: nothing to commit"
else
  TRAILERS=""
  for NOTE in ${NOTES[@]+"${NOTES[@]}"}; do TRAILERS+="Release-Note: $NOTE"$'\n'; done
  git commit -q -m "$SUBJECT" -m "${TRAILERS}Co-Authored-By: $COAUTHOR"
  echo "committed $(git rev-parse --short HEAD) on $BRANCH: $SUBJECT"
fi

# Warning only: local-only commits on the workflow base (pr-lifecycle.md). Never changes ship's exit code.
if [[ -f "$(dirname "$0")/base_drift.py" ]]; then
  DRIFT_RC=0
  DRIFT="$(python3 "$(dirname "$0")/base_drift.py" --exclude "$BRANCH" 2>&1)" || DRIFT_RC=$?
  if [[ $DRIFT_RC == 3 ]]; then echo "ship: warning, base drift:" >&2; echo "$DRIFT" >&2
  elif [[ $DRIFT_RC != 0 ]]; then echo "ship: base-drift check failed (exit $DRIFT_RC): $(echo "$DRIFT" | tail -1)" >&2; fi
fi

# Advisory preflight review (pr-lifecycle.md, "Preflight review"). Warning only, like base_drift: a crash or git
# error prints one line and the ship continues. Skipped when origin/$BASE is unknown.
if [[ -f "$(dirname "$0")/preflight_review.py" ]] && git rev-parse -q --verify "origin/$BASE" >/dev/null; then
  PF_RC=0
  PF="$(python3 "$(dirname "$0")/preflight_review.py" --base "$BASE" --note-text "$BODY" 2>&1)" || PF_RC=$?
  if [[ $PF_RC == 0 ]]; then echo "$PF"
  else echo "ship: preflight review failed (exit $PF_RC), continuing: $(echo "$PF" | tail -1)" >&2; fi
fi

[[ $PUSH == 1 ]] || exit 0

# Denylist layer 1 (pr-lifecycle.md, "Denylist"): scan the tree (only hits this change adds against origin/$BASE count; every hit counts in the go-public gate) for the owner's local house terms before anything leaves this
# machine. house_scan reads the list; this prints counts and path:line, never a term. Exit 1 = hit, 3 = list missing while
# `denylist_required` is true in tools/triage/config.json; a missing optional list only warns. Any other failure also stops the push.
HS="$(dirname "$0")/house_scan.py"
if [[ -f "$HS" ]]; then
  HS_RC=0
  python3 "$HS" denylist --root "$(git rev-parse --show-toplevel)" --required-from "$(dirname "$0")/triage/config.json" \
    --base-ref "origin/$BASE" || HS_RC=$?
  case "$HS_RC" in
    0) ;;
    1) echo "ship: denylist hit(s) above; nothing was pushed. Remove the house data and ship again." >&2; exit 1 ;;
    3) echo "ship: the denylist is required but not loaded; nothing was pushed (HOUSE_SCAN_DENYLIST, the config folder's house_denylist.txt or ~/hass-agents/house_denylist.txt)." >&2; exit 1 ;;
    *) echo "ship: the denylist scan failed (exit $HS_RC); nothing was pushed." >&2; exit 1 ;;
  esac
fi

"$GUARD" branch
git push -q -u origin "$BRANCH"
echo "pushed $BRANCH"

if [[ $PR == 1 ]]; then
  FOOTER="🤖 Generated with [Claude Code](https://claude.com/claude-code)"
  ARGS=(pr create --base "$BASE" --head "$BRANCH" --title "$SUBJECT" --body "${BODY:+$BODY

}$FOOTER" --assignee "${SHIP_ASSIGNEE:-SFenton}")
  ARGS+=(--draft)
  gh "${ARGS[@]}"
  # Informational only: can the gated path land this PR? Never changes ship's exit code (pr-lifecycle.md, step 1b).
  PR_NUM="$(gh pr view "$BRANCH" --json number --jq .number 2>/dev/null || true)"
  if [[ -n "$PR_NUM" && -f "$(dirname "$0")/land_preflight.py" ]]; then
    python3 "$(dirname "$0")/land_preflight.py" --pr "$PR_NUM" || echo "ship: preflight exit $? (pr-lifecycle.md step 1b)" >&2
  fi
  [[ -n "${SHIP_TASK:-}" ]] && python3 "$(git rev-parse --show-toplevel)/tools/pr_note.py" init --task "$SHIP_TASK" || true
fi
