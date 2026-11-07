#!/usr/bin/env bash
# Creates a lane: a git worktree on its own branch from origin/main, and prints what to run in it.
# Replaces the fetch / worktree / branch / env-path boilerplate every lane retyped.
#
# Usage: tools/lane_new.sh NAME [--base origin/main] [--branch claude/NAME]
#   Worktree: <repo>/.claude/worktrees/NAME. Safe to rerun: an existing worktree is reported, not recreated.
#   The simulators come from the shared pool (tools/ios_uitest.sh picks one per run), so a lane needs no names.
set -euo pipefail

NAME="${1:-}"
[[ -n "$NAME" && "$NAME" != -* ]] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift
BASE="origin/main"
BASE_GIVEN=0
BRANCH="claude/$NAME"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; BASE_GIVEN=1; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    *) echo "lane_new: unknown option $1" >&2; exit 2 ;;
  esac
done

MAIN="$(cd "$(dirname "$0")/.." && git rev-parse --show-toplevel)"
# From inside a worktree, resolve the main checkout so lanes never nest.
COMMON="$(git -C "$MAIN" rev-parse --git-common-dir)"
[[ "$COMMON" = /* ]] || COMMON="$MAIN/$COMMON"
MAIN="$(cd "$COMMON/.." && pwd)"
DIR="$MAIN/.claude/worktrees/$NAME"

if [[ -e "$DIR/.git" ]]; then
  echo "lane exists: $DIR ($(git -C "$DIR" rev-parse --abbrev-ref HEAD))"
else
  git -C "$MAIN" fetch -q origin
  if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$MAIN" worktree add -q "$DIR" "$BRANCH"
    # An existing branch keeps its recorded parent unless --base says otherwise.
    [[ $BASE_GIVEN == 1 ]] && git -C "$MAIN" config "branch.$BRANCH.sh-base" "$BASE"
  else
    git -C "$MAIN" worktree add -q -b "$BRANCH" "$DIR" "$BASE"
    # Record the parent so the test tier (tools/lane_base.py) diffs against it. A worktree made another way records it with:
    #   git config branch.<branch>.sh-base <parent ref>
    git -C "$MAIN" config "branch.$BRANCH.sh-base" "$BASE"
  fi
  echo "lane created: $DIR on $BRANCH from $BASE ($(git -C "$DIR" rev-parse --short HEAD))"
fi
ENV_FILE="shell"  # the script loads the credentials in-process from ~/.config/fenton-hass/env (tools/hass_creds.sh)
cat <<TEXT
cd $DIR
tools/bg_run.py swift-$NAME -- bash -c 'cd apple && swift test --filter <Suite>'          # run_in_background, then end the turn
tools/bg_run.py uitest-$NAME -- tools/ios_uitest.sh --quick --env $ENV_FILE --only iphone -only-testing:FentonHomeUITests/<Class>/<test>
tools/ship.sh "<subject>" --pr --body-file <file>                                            # commit, push, draft PR; then reviewer + tools/pr_land.sh N
TEXT
( source "$(dirname "${BASH_SOURCE[0]}")/hass_creds.sh" && hass_load_creds && [[ -n "${FENTON_HASS_TOKEN:-}${FENTON_HASS_PASSWORD:-}" ]] ) 2>/dev/null || echo "note: no live-server credentials found (see tools/hass_creds.sh); signed-in journeys will skip"
