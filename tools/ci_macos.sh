#!/usr/bin/env bash
# The steps of the one hosted macOS job in pr-checks (build once, Smoke on three devices, full swift test), each timed.
# Hosted mode only (FENTON_CI_HOSTED=1 on a GitHub-hosted runner); the journey runner refuses anywhere else.
#
#   tools/ci_macos.sh build                  build the test products once (no simulator booted: a first Duo boot beside a compile killed runners)
#   tools/ci_macos.sh smoke FAMILY|all       Smoke plan on iphone|duo|ipad (one at a time, each booted and settled first), or all three at once
#   tools/ci_macos.sh journeys FAMILY|all    the journeys the diff reaches (pull requests only; skips when Gate runs none of them)
#   tools/ci_macos.sh swift-test             the full swift test
#   tools/ci_macos.sh summary                the timing table and, when simslim is installed, its memory and swap figures
#
# `all` is the parallel layout: one ios_uitest.sh run with --parallel-families on slimmed simulators. A phase appends
# "NAME<TAB>SECONDS<TAB>EXIT" to the timings file (CI_MACOS_TIMINGS, default $RUNNER_TEMP/ci-timings.tsv).
# Test seams: CI_MACOS_UITEST, CI_MACOS_AFFECTED, CI_MACOS_SETTLE and CI_MACOS_HEARTBEAT replace the scripts they name.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UITEST="${CI_MACOS_UITEST:-$ROOT/tools/ios_uitest.sh}"
AFFECTED=(python3 "$ROOT/tools/affected_tests.py")
[[ -n "${CI_MACOS_AFFECTED:-}" ]] && AFFECTED=("$CI_MACOS_AFFECTED")
SETTLE="${CI_MACOS_SETTLE:-$ROOT/tools/sim_settle.sh}"
HEARTBEAT="${CI_MACOS_HEARTBEAT:-$ROOT/tools/ci_heartbeat.sh}"
TIMINGS="${CI_MACOS_TIMINGS:-${RUNNER_TEMP:-/tmp}/ci-timings.tsv}"
FAMILIES=(iphone duo ipad)

# phase NAME CMD...: run CMD, record its wall time and exit status, return its status.
phase() {
  local name="$1" start="$SECONDS" rc=0
  shift
  "$@" || rc=$?
  printf '%s\t%s\t%s\n' "$name" "$((SECONDS - start))" "$rc" >> "$TIMINGS"
  return "$rc"
}

# scope_args FAMILY|all: the ios_uitest.sh arguments that pick the devices.
scope_args() {
  if [[ "$1" == all ]]; then echo "--parallel-families"; else echo "--only $1"; fi
}

check_family() {
  case "$1" in iphone | duo | ipad) ;; all) [[ "$2" == 1 ]] || { echo "ci_macos: 'all' is not valid here" >&2; exit 2; } ;; *) echo "ci_macos: unknown family '$1'" >&2; exit 2 ;; esac
}

# runnable FAMILY: the Gate-plan journeys the diff reaches on a family, and whether Gate runs any of them.
# --changed runs the Gate plan. A class Gate skips whole (the Live-plan shell journeys need the real house) matches nothing there,
# and xcodebuild reports EMPTY, a failure. Skip when Gate runs none of the journeys the diff reaches, which includes a diff that reaches none. A crash of the
# selection tool fails the step; exit 3 (a file needing a pick) falls through to the runner, which fails on it.
journeys_for() {
  local family="$1" rc=0 runnable all
  runnable="$("${AFFECTED[@]}" --journeys --device "$family" --plan Gate)" || rc=$?
  case "$rc" in 0 | 3) ;; *) echo "affected_tests.py failed (exit $rc)" >&2; return "$rc" ;; esac
  all="$("${AFFECTED[@]}" --journeys --device "$family")" || true
  # Exit 3: a changed file needs a pick; the runner fails on it, CI never guesses.
  [[ "$rc" == 3 ]] && return 0
  if [[ -z "$runnable" ]]; then
    echo "no journey the diff reaches runs in the Gate plan on $family (selected: ${all:-none})"
    return 10
  fi
  return 0
}

cmd="${1:-}"
case "$cmd" in
  build)
    phase build "$HEARTBEAT" run -- "$UITEST" --only iphone --plan Smoke --force --build-only
    ;;
  smoke)
    target="${2:-}"; check_family "$target" 1
    if [[ "$target" == all ]]; then
      phase smoke-all "$UITEST" --plan Smoke --force --parallel-families
    else
      # The first boot of a runtime on a fresh VM holds the runner at a high load for minutes (the Duo above all); wait for it to settle.
      phase "boot-$target" "$HEARTBEAT" run -- "$SETTLE" "$target" || true
      phase "smoke-$target" "$UITEST" --only "$target" --plan Smoke --force
    fi
    ;;
  journeys)
    target="${2:-}"; check_family "$target" 1
    if [[ "$target" == all ]]; then list=("${FAMILIES[@]}"); else list=("$target"); fi
    reach=0
    for family in "${list[@]}"; do
      jrc=0; journeys_for "$family" || jrc=$?
      case "$jrc" in 0) reach=1 ;; 10) ;; *) exit "$jrc" ;; esac
    done
    if [[ "$reach" == 0 ]]; then
      echo "skipped: no journey the diff reaches runs in the Gate plan on $target"
      exit 0
    fi
    # shellcheck disable=SC2046
    phase "journeys-$target" "$UITEST" $(scope_args "$target") --changed --force
    ;;
  swift-test)
    # shellcheck disable=SC2016
    phase swift-test bash -c 'cd "$1/apple" && swift test' _ "$ROOT"
    ;;
  summary)
    {
      echo "### Timing by phase"
      echo
      echo "| Phase | Seconds | Exit |"
      echo "|---|---|---|"
      [[ -f "$TIMINGS" ]] && awk -F'\t' '{ printf "| %s | %s | %s |\n", $1, $2, $3 }' "$TIMINGS"
      echo
      echo "Layout: \`${FENTON_SMOKE_LAYOUT:-sequential}\`"
      echo
      echo '```'
      echo "swap: $(sysctl -n vm.swapusage 2> /dev/null || echo unknown)"
      vm_stat 2> /dev/null | head -12
      if command -v simslim > /dev/null; then
        echo
        simslim measure 2>&1 | head -40 || true
      fi
      echo '```'
    } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
    ;;
  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
