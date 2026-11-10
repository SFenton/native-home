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
#   tools/pr_land.py marks it ready and arms auto-merge once the gates pass. ship.sh never merges itself (pr-lifecycle.md).
#   Without --pr only the branch is pushed.
#   Review before push (owner, 2026-11-09; ci.md#merge-gate): on SFenton/native-home nothing is pushed, opened or armed without an independent
#   `pass` for the exact HEAD in the trusted store (tools/review_verdict.py, the reviewer's `record.py --lane`). Commit, get the pass, then ship;
#   a ship that has to commit new changes stops at the push, because the new HEAD has no pass yet. Which guard covers which step: git's own pre-push
#   hook (.githooks/pre-push, tools/prepush_review.py, which sees every sha really pushed) enforces the push, this script only gives the early
#   message, and tools/hooks/push_guard.py stops a command going around the hook.
#   After the PR opens ship.sh runs tools/pr_land.py N on native-home: it runs the gates GitHub cannot (kill switch, app-UI gate, denylist, author and fork,
#   the pass for HEAD, the live ruleset) and arms the squash auto-merge pinned to HEAD. GitHub then merges when the required checks pr-checks and ai-review pass; a CI
#   failure means fix, re-review, push. It then prints the ci_wait.py command for the orchestrator to start in the background. A refusal prints a notice and never changes ship's exit code.
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

# Pre-push checks that need no network (tools/lane_check.py check): the house denylist scan (pr-lifecycle.md, "Denylist"; only hits this change adds
# against origin/$BASE count; it prints counts and path:line, never a term; exit 1 = hit, 3 = list missing while `denylist_required` is true in
# tools/triage/config.json), the revert guard (a squash over a moved base that puts a merged change back) and the advisory one-commit shape.
# Any non-zero exit stops the push; a missing optional denylist only warns.
LC="$(dirname "$0")/lane_check.py"
if [[ -f "$LC" ]]; then
  python3 "$LC" check --base "$BASE" --only scan --only revert --only shape \
    || { echo "ship: lane_check failed (above); nothing was pushed. Fix it and ship again." >&2; exit 1; }
fi

# Review before push. Git's own pre-push hook (.githooks/pre-push -> tools/prepush_review.py) is the enforcement: it sees the url and every
# sha really pushed. This block is the early, friendly message only: for a native-home origin it needs the hook installed (tools/setup.sh) and a
# pass for HEAD in the trusted store; an origin it cannot read is refused here as the hook would refuse it. Other origins are left to the hook.
HEAD_SHA="$(git rev-parse HEAD)"
RV="$(dirname "$0")/review_verdict.py"
ORIGIN_KIND="unknown"
if [[ -f "$RV" ]]; then ORIGIN_KIND="$(python3 "$RV" remote "$(git remote get-url --push origin 2>/dev/null || true)" 2>/dev/null || echo unknown)"; fi
case "$ORIGIN_KIND" in
  other|local) ;;
  native-home)
    python3 "$LC" check --only hooks || { echo "ship: nothing was pushed; core.hooksPath does not lead to this repo's .githooks (relative or absolute), so git's pre-push hook would not run. Run tools/setup.sh." >&2; exit 1; }
    python3 "$RV" pass "$HEAD_SHA" || { echo "ship: nothing was pushed; ${HEAD_SHA:0:12} needs the reviewer's pass first (review before push)." >&2; exit 1; } ;;
  *) echo "ship: origin is not a readable GitHub URL (or review_verdict.py is missing); nothing was pushed." >&2; exit 1 ;;
esac

"$GUARD" branch
git push -q -u origin "$BRANCH"
echo "pushed $BRANCH"

# Server-side backstop: post the `ai-review` check run for the pushed (reviewed) sha as the reviewer App, from its recorded verdict. GitHub cannot take a
# check on a commit it has not received, so this runs after the push. It never fails ship: on error it prints `ai-review check NOT posted: <reason>`.
if [[ "$ORIGIN_KIND" == "native-home" ]]; then
  python3 "$(dirname "$0")/review/record.py" --post-check "$HEAD_SHA" --repo SFenton/native-home || true
fi

if [[ $PR == 1 ]]; then
  FOOTER="🤖 Generated with [Claude Code](https://claude.com/claude-code)"
  ARGS=(pr create --base "$BASE" --head "$BRANCH" --title "$SUBJECT" --body "${BODY:+$BODY

}$FOOTER" --assignee "${SHIP_ASSIGNEE:-SFenton}")
  ARGS+=(--draft)
  gh "${ARGS[@]}"
  PR_NUM="$(gh pr view "$BRANCH" --json number --jq .number 2>/dev/null || true)"
  # native-home: arm through pr_land.py, which runs what GitHub cannot (kill switch, app-UI gate and owner-kept set, denylist, author and fork,
  # the reviewer's pass for the exact head, the live ruleset) and pins the auto-merge to the head. A UI PR may be parked by the app-UI gate
  # here (no design record yet): a notice, armed later with tools/pr_land.sh N. Never changes ship's exit code.
  if [[ -n "$PR_NUM" && -f "$(dirname "$0")/pr_land.py" ]]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
    if [[ "$REPO" == "SFenton/native-home" ]]; then
      python3 "$(dirname "$0")/pr_land.py" "$PR_NUM" || echo "ship: not armed (see above); land it with tools/pr_land.sh $PR_NUM" >&2
      echo "ship: start the waiter: tools/bg_run.py ci-$PR_NUM --timeout 7200 -- python3 tools/ci_wait.py $PR_NUM"
    fi
  fi
  [[ -n "${SHIP_TASK:-}" ]] && python3 "$(git rev-parse --show-toplevel)/tools/pr_note.py" init --task "$SHIP_TASK" || true
fi
