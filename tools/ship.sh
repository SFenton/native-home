#!/usr/bin/env bash
# Commit everything tracked or new (minus .gitignore), push the branch and optionally open the PR.
# Replaces the hand-built trailer, `git add -A`, push and `gh pr create` / assignee sequence.
#
# Usage: tools/ship.sh "Subject line" [--note TEXT] [--body-file FILE | --body TEXT] [--pr] [--draft] [--base main] [--no-push] [--update]
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
#   --update  for a lane branch you amended or rebased after it was pushed: pushes with `--force-with-lease=refs/heads/BRANCH:SHA`,
#             where SHA is what `git ls-remote` reports for origin/BRANCH, and only when this checkout knows it (an ancestor of HEAD, or in the local
#             branch's reflog because this checkout pushed it): a commit someone else pushed is refused, never overwritten. Then it posts the
#             `ai-review` check for the new head only if that head already has a pass (otherwise nothing) and, when the branch has a PR on native-home, re-arms it (a new head loses the old pin).
#             Only `agents/*` and `port/*` branches; anything else is refused before it commits. A branch not on origin yet needs a plain ship.
#             The new head still needs its own reviewer pass before it is armed: `record.py --post-check` reads the trusted store, so --update
#             cannot produce a check the reviewer did not earn. ship.sh posts the check as a child process of this script, the same way a plain ship does;
#             that is not the agent's own `record.py` command which tools/hooks/review_guard.py reserves for the reviewer, and the check is only as green
#             as the recorded verdict.
#   The Jev question list must be current before any push: `python3 tools/jev_ask.py sync --check` (CI runs it too) blocks the push when stale.
#   Push, then review (owner, 2026-11-10; ci.md#merge-gate): the branch is pushed and the draft PR opened without a reviewer pass, so CI runs while the
#   Reviewer reads the exact head. On `changes` fix and push again (`--update` after an amend); on `pass` the orchestrator arms the PR (tools/pr_land.sh N).
#   Git's pre-push hook (.githooks/pre-push) still runs the house denylist on every push; this file only checks that the hook is installed.
#   After the PR opens ship.sh runs tools/pr_land.py N on native-home: it runs the gates GitHub cannot (kill switch, app-UI gate, denylist, author and fork,
#   the pass for HEAD, the live ruleset) and arms the squash auto-merge pinned to HEAD. With no pass yet it prints `not armed`, which is expected; the
#   the reviewer posts `ai-review` after its pass and the orchestrator then arms with tools/pr_land.sh N. GitHub then merges when the required checks pr-checks and ai-review pass; a CI
#   failure means fix, push again, and the new head needs its own review. It then prints the ci_wait.py command for the orchestrator to start in the background. A refusal prints a notice and never changes ship's exit code.
set -euo pipefail

SUBJECT="${1:-}"
[[ -n "$SUBJECT" && "$SUBJECT" != -* ]] || { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift
NOTES=(); BODY=""; PR=0; DRAFT=0; BASE="main"; PUSH=1; UPDATE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --note) NOTES+=("$2"); shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --body-file) BODY="$(cat "$2")"; shift 2 ;;
    --pr) PR=1; shift ;;
    --draft) DRAFT=1; shift ;;
    --base) BASE="$2"; shift 2 ;;
    --no-push) PUSH=0; shift ;;
    --update) UPDATE=1; shift ;;
    *) echo "ship: unknown option $1" >&2; exit 2 ;;
  esac
done

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
GUARD="$(dirname "$0")/ship_guard.sh"   # owner-only safety checks (branch, secrets)
"$GUARD" branch
if [[ $UPDATE == 1 ]]; then
  case "$BRANCH" in
    agents/*|port/*) ;;
    *) echo "ship: --update force-pushes only a lane's own agents/* or port/* branch; '$BRANCH' is neither. Use a plain ship, or ask the owner." >&2; exit 1 ;;
  esac
fi

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
JA="$(dirname "$0")/jev_ask.py"
if [[ -f "$JA" ]]; then
  python3 "$JA" sync --check \
    || { echo "ship: the Jev question list check failed or is stale (CI would fail it); nothing was pushed. Run 'python3 tools/jev_ask.py sync', bump the question's version, commit, and ship again." >&2; exit 1; }
fi
LC="$(dirname "$0")/lane_check.py"
if [[ -f "$LC" ]]; then
  python3 "$LC" check --base "$BASE" --only scan --only revert --only shape \
    || { echo "ship: lane_check failed (above); nothing was pushed. Fix it and ship again." >&2; exit 1; }
fi

# Push, then review. No reviewer pass is needed to push (owner, 2026-11-10); git's pre-push hook (.githooks/pre-push) still runs the house denylist on every
# push, so for a native-home origin it must be installed (tools/setup.sh). An origin this file cannot read is refused here, as before.
HEAD_SHA="$(git rev-parse HEAD)"
RV="$(dirname "$0")/review_verdict.py"
ORIGIN_KIND="unknown"
if [[ -f "$RV" ]]; then ORIGIN_KIND="$(python3 "$RV" remote "$(git remote get-url --push origin 2>/dev/null || true)" 2>/dev/null || echo unknown)"; fi
case "$ORIGIN_KIND" in
  other|local) ;;
  native-home)
    python3 "$LC" check --only hooks || { echo "ship: nothing was pushed; core.hooksPath does not lead to this repo's .githooks (relative or absolute), so git's pre-push hook (the house denylist) would not run. Run tools/setup.sh." >&2; exit 1; } ;;
  *) echo "ship: origin is not a readable GitHub URL (or review_verdict.py is missing); nothing was pushed." >&2; exit 1 ;;
esac

PUSH_ARGS=(-q -u)
LEASE=""
if [[ $UPDATE == 1 ]]; then
  # The lease is the sha origin has right now (ls-remote), but only if this checkout knows it: an ancestor of HEAD (already integrated) or a sha the
  # local branch once pointed at (its reflog: this checkout pushed it, then amended). Anything else is someone else's commit; never overwrite it.
  LS_RC=0
  LS="$(git ls-remote origin "refs/heads/$BRANCH")" || LS_RC=$?
  [[ $LS_RC == 0 ]] || { echo "ship: --update could not read origin (git ls-remote failed, exit $LS_RC); check the network and credentials. Nothing was pushed." >&2; exit 1; }
  LEASE="${LS%%[[:space:]]*}"
  [[ -n "$LEASE" ]] || { echo "ship: --update found no '$BRANCH' on origin to update; ship it plainly first." >&2; exit 1; }
  KNOWN="$(git reflog show --format=%H "$BRANCH" 2>/dev/null || true)"   # a variable, not a pipe: grep -q would SIGPIPE git under pipefail
  if ! git merge-base --is-ancestor "$LEASE" HEAD 2>/dev/null && ! grep -qx "$LEASE" <<<"$KNOWN"; then
    echo "ship: origin/$BRANCH is at ${LEASE:0:12}, which this checkout never had (not an ancestor of HEAD, not in the branch's reflog): someone else pushed it. Fetch it, rebase onto it, review again, and ship. Nothing was pushed." >&2
    exit 1
  fi
  PUSH_ARGS+=("--force-with-lease=refs/heads/$BRANCH:$LEASE")
fi
"$GUARD" branch
git push "${PUSH_ARGS[@]}" origin "refs/heads/$BRANCH:refs/heads/$BRANCH" \
  || { echo "ship: the push was refused (with --update: origin/$BRANCH is no longer ${LEASE:-the leased sha}; the pre-push hook may also have said no). Nothing was overwritten." >&2; exit 1; }
echo "pushed $BRANCH${LEASE:+ (forced over ${LEASE:0:12})}"

# Server-side backstop: post the `ai-review` check run for the pushed sha when its recorded pass already exists (a re-ship of a reviewed head). With no pass
# (the usual case: ship runs before the review) this is a silent no-op; the Reviewer posts the check itself right after recording its pass
# (`record.py --post-check SHA --repo SFenton/native-home`, which tools/hooks/review_guard.py allows only for the reviewer). It never fails ship.
if [[ "$ORIGIN_KIND" == "native-home" ]] && python3 "$RV" pass "$HEAD_SHA" >/dev/null 2>&1; then
  python3 "$(dirname "$0")/review/record.py" --post-check "$HEAD_SHA" --repo SFenton/native-home || true
fi

if [[ $UPDATE == 1 ]]; then
  # The PR already exists: no create. Re-arm it (the new head dropped the old pin); a refusal is a notice, like a plain ship.
  PR_NUM="$(gh pr view "$BRANCH" --json number --jq .number 2>/dev/null || true)"
  if [[ -n "$PR_NUM" && "$ORIGIN_KIND" == "native-home" && -f "$(dirname "$0")/pr_land.py" ]]; then
    python3 "$(dirname "$0")/pr_land.py" "$PR_NUM" || echo "ship: not armed (see above); land it with tools/pr_land.sh $PR_NUM" >&2
  fi
elif [[ $PR == 1 ]]; then
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
      python3 "$(dirname "$0")/pr_land.py" "$PR_NUM" || echo "ship: not armed (see above); expected until the reviewer passes this head, then land it with tools/pr_land.sh $PR_NUM" >&2
      echo "ship: start the waiter: tools/bg_run.py ci-$PR_NUM --timeout 7200 -- python3 tools/ci_wait.py $PR_NUM"
    fi
  fi
  [[ -n "${SHIP_TASK:-}" ]] && python3 "$(git rev-parse --show-toplevel)/tools/pr_note.py" init --task "$SHIP_TASK" || true
fi
