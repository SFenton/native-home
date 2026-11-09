#!/usr/bin/env bash
# The steps of the one hosted macOS job in pr-checks (build once, Smoke on three devices, swift test: the affected suites on a PR, the full suite on main), each timed.
# Hosted mode only (FENTON_CI_HOSTED=1 on a GitHub-hosted runner); the journey runner refuses anywhere else.
#
#   tools/ci_macos.sh build                  build the test products once (no simulator booted: a first Duo boot beside a compile killed runners)
#   tools/ci_macos.sh smoke FAMILY           Smoke plan on iphone|duo|ipad (one at a time, each booted, slimmed (simslim) and settled first)
#   tools/ci_macos.sh journeys FAMILY         the journeys the diff reaches (pull requests only; skips when Gate runs none of them)
#   tools/ci_macos.sh swift-test             swift test (the affected suites on a pull request, everything otherwise)
#   tools/ci_macos.sh summary                the timing table and the runner's swap and memory
#
# A phase appends
# "NAME<TAB>SECONDS<TAB>EXIT" to the timings file (CI_MACOS_TIMINGS, default $RUNNER_TEMP/ci-timings.tsv).
# Test seams: CI_MACOS_UITEST, CI_MACOS_AFFECTED, CI_MACOS_SETTLE, CI_MACOS_SLIM, CI_MACOS_HEARTBEAT, CI_MACOS_RELEASE and CI_MACOS_SWIFT replace the scripts they name.
# One VM runs all three devices in turn, and ios_uitest.sh leaves a simulator booted (warm) when its run ends. Left running, the earlier
# devices hold the 3 vCPUs and 7 GB: the second and third boots took 19 to 20 minutes with load 600 to 900 and swap in use (run
# 42520889460), against 6 to 15 on a fresh VM. So each device starts, and swift test runs, with every simulator and any hung
# xcodebuild or xctest of the earlier devices shut down first.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UITEST="${CI_MACOS_UITEST:-$ROOT/tools/ios_uitest.sh}"
AFFECTED=(python3 "$ROOT/tools/affected_tests.py")
[[ -n "${CI_MACOS_AFFECTED:-}" ]] && AFFECTED=("$CI_MACOS_AFFECTED")
SETTLE="${CI_MACOS_SETTLE:-$ROOT/tools/sim_settle.sh}"
SLIM="${CI_MACOS_SLIM:-$ROOT/tools/sim_slim.sh}"
HEARTBEAT="${CI_MACOS_HEARTBEAT:-$ROOT/tools/ci_heartbeat.sh}"
SWIFT=("${CI_MACOS_SWIFT:-swift}")
RELEASE="${CI_MACOS_RELEASE:-$ROOT/tools/ci_release_sims.sh}"
TIMINGS="${CI_MACOS_TIMINGS:-${RUNNER_TEMP:-/tmp}/ci-timings.tsv}"

# phase NAME CMD...: run CMD, record its wall time and exit status, return its status.
phase() {
  local name="$1" start="$SECONDS" rc=0
  shift
  "$@" || rc=$?
  printf '%s\t%s\t%s\n' "$name" "$((SECONDS - start))" "$rc" >> "$TIMINGS"
  return "$rc"
}

check_family() {
  case "$1" in iphone | duo | ipad) ;; *) echo "ci_macos: unknown family '$1'" >&2; exit 2 ;; esac
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
    "$RELEASE" || true
    # Slim the simulator (sim_slim.sh boots it first, then disables the daemons the tests do not need); FENTON_SIM_SLIM=0 skips it.
    # Timed apart from the settle wait so the table shows what slimming costs and what it saves. Failure leaves the simulator stock.
    phase "slim-$target" "$HEARTBEAT" run -- "$SLIM" "$target" || true
    # The first boot of a runtime on a fresh VM holds the runner at a high load for minutes (the Duo above all); wait for it to settle.
    phase "boot-$target" "$HEARTBEAT" run -- "$SETTLE" "$target" || true
    phase "smoke-$target" "$UITEST" --only "$target" --plan Smoke --force
    ;;
  journeys)
    target="${2:-}"; check_family "$target" 1
    jrc=0; journeys_for "$target" || jrc=$?
    case "$jrc" in 0) ;; 10) echo "skipped: no journey the diff reaches runs in the Gate plan on $target"; exit 0 ;; *) exit "$jrc" ;; esac
    phase "journeys-$target" "$UITEST" --only "$target" --changed --force
    ;;
  swift-test)
    "$RELEASE" || true
    # A pull request runs the Swift package suites its diff reaches (as the old swift-test-hosted job did), a push to main and a
    # manual run run everything. A file the selection cannot place runs everything; a diff that reaches no suite runs nothing.
    filters=()
    if [[ -n "${FENTON_AFFECTED_BASE:-}" ]]; then
      rc=0; picked="$("${AFFECTED[@]}" --swift --base "$FENTON_AFFECTED_BASE")" || rc=$?
      if [[ "$rc" != 0 ]]; then
        echo "affected_tests.py could not place every changed file (exit $rc): running the full suite"
      elif [[ -z "$picked" ]]; then
        echo "no Swift package suite is affected by this change: swift test skipped"
        printf 'swift-test\t0\t0\n' >> "$TIMINGS"
        exit 0
      else
        # shellcheck disable=SC2206  # the selection is a list of --filter arguments
        filters=($picked)
      fi
    fi
    echo "swift test ${filters[*]:-}"
    # shellcheck disable=SC2016
    phase swift-test bash -c 'cd "$1/apple" && shift && "$@"' _ "$ROOT" "${SWIFT[@]}" test ${filters[@]+"${filters[@]}"}
    ;;
  summary)
    {
      echo "### Timing by phase"
      echo
      echo "| Phase | Seconds | Exit |"
      echo "|---|---|---|"
      [[ -f "$TIMINGS" ]] && awk -F'\t' '{ printf "| %s | %s | %s |\n", $1, $2, $3 }' "$TIMINGS"
      echo
      echo '```'
      echo "swap: $(sysctl -n vm.swapusage 2> /dev/null || echo unknown)"
      vm_stat 2> /dev/null | head -12
      echo '```'
    } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
    ;;
  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
