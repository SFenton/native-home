#!/usr/bin/env bash
# Runs the device-only performance suites on a physical iPhone or iPad, where hitch numbers mean something.
# Simulators report false data; the measured tests skip there.
#
# Usage:
#   tools/ios_perf.sh --device <udid|name> [--suite scroll|nav|launch|motion|ticker|all] [--live] [--env shell|FILE]
#                     [--only testName] [--hold SECONDS] [extra xcodebuild args]
#
#   --device   A connected device (`xcrun xctrace list devices`). Signing uses the team in project.yml.
#   --suite    Which tests (default scroll):
#                scroll  FastScrollPerformanceTests (the whole class; --live adds testFlickLiveTabs)
#                nav     NavigationPerformanceTests: testDeviceNavigationTransitionMetrics, testDeviceZoomTransitionMetrics
#                launch  LaunchPerformanceTests: testColdLaunchSignedOut, testColdLaunchSignedOutWithoutIntro,
#                        testWarmLaunchSignedInMeasuresTheSnapshot (credentials), testIntroHitchRatioOnADevice,
#                        testArrivalHitchRatioOnADevice (credentials). The *WithinBudget tests assert simulator budgets: not run.
#                motion  LayoutChangePerformanceTests
#                ticker  WeatherTickerPerformanceTests
#                all     every one of these, one after the other
#   --live     Also flick the live tab pages (scroll suite; needs sign-in credentials from --env).
#   --only     One test method instead of the suite's tests (resolved against the suite's class; with `all`, applied to
#              the suites whose class has it).
#   --env      shell (credentials already exported) or an env file. Needed by launch (warm/arrival) and --live.
#   --hold     Seconds each suite may hold the device (default 3600).
#
# Each suite runs inside a devcap device hold (`tools/devcap.py run --device`, FIFO with other users of the phone).
# Results: apple/.build/perf-<suite>-<timestamp>.xcresult, one per suite. Open it in Xcode (Report navigator -> the test ->
# Metrics) to see hitch ratios, signposts, clock and CPU, and set baselines.
# The app's own measurements are on the device too: Settings -> Performance -> Export Telemetry.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DEVICE=""
ENV_FILE=""
LIVE=""
ONLY=""
SUITE="scroll"
HOLD=3600
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --env) ENV_FILE="$2"; shift 2 ;;
    --live) LIVE=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --suite) SUITE="$2"; shift 2 ;;
    --hold) HOLD="$2"; shift 2 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done
[[ -n "$DEVICE" ]] || { echo "usage: tools/ios_perf.sh --device <udid|name> [--suite scroll|nav|launch|motion|ticker|all] [--live] [--env shell|file] [--only testName] [--hold SECONDS]"; exit 2; }
case "$SUITE" in scroll|nav|launch|motion|ticker|all) ;; *) echo "unknown --suite $SUITE (scroll|nav|launch|motion|ticker|all)"; exit 2 ;; esac

if [[ -n "$ENV_FILE" ]]; then
  # Credentials are mapped onto runner variables without echoing them.
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hass_creds.sh"; hass_use_env_arg "$ENV_FILE" || exit 2  # in-process only (tools/hass_creds.sh)
  export TEST_RUNNER_FENTON_HASS_USERNAME="${FENTON_HASS_USERNAME:-}"
  export TEST_RUNNER_FENTON_HASS_PASSWORD="${FENTON_HASS_PASSWORD:-}"
  export TEST_RUNNER_FENTON_HASS_TOKEN="${FENTON_HASS_TOKEN:-}"
  SERVER="${FENTON_HASS_SERVER:-}"
  [[ -n "$SERVER" ]] && export TEST_RUNNER_FENTON_HASS_SERVER="$SERVER"
fi
[[ -n "$LIVE" ]] && export TEST_RUNNER_FENTON_PERF_LIVE=1

# A name resolves to its UDID.
if [[ ! "$DEVICE" =~ ^[0-9A-Fa-f-]{20,}$ ]]; then
  DEVICE="$(xcrun xctrace list devices 2>/dev/null | grep -v Simulator | grep -F "$DEVICE" | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{20,})\)$/\1/')"
  [[ -n "$DEVICE" ]] || { echo "No connected device matches that name"; exit 2; }
fi

# The tests of a suite as `Class` or `Class/test` lines; --only picks one method of the suite's class.
suite_targets() {
  local class tests
  case "$1" in
    scroll) class=FastScrollPerformanceTests; tests="" ;;
    nav) class=NavigationPerformanceTests; tests="testDeviceNavigationTransitionMetrics testDeviceZoomTransitionMetrics" ;;
    launch) class=LaunchPerformanceTests
      tests="testColdLaunchSignedOut testColdLaunchSignedOutWithoutIntro testWarmLaunchSignedInMeasuresTheSnapshot testIntroHitchRatioOnADevice testArrivalHitchRatioOnADevice" ;;
    motion) class=LayoutChangePerformanceTests; tests="" ;;
    ticker) class=WeatherTickerPerformanceTests; tests="" ;;
  esac
  if [[ -n "$ONLY" ]]; then
    # With `all`, a method that belongs to another suite's class is skipped here.
    if [[ "$SUITE" != all || -z "$tests" || " $tests " == *" $ONLY "* ]] && grep -q "func $ONLY(" "$ROOT/apple/Apps/iOSUITests/$class.swift"; then
      echo "FentonHomeUITests/$class/$ONLY"
    fi
  elif [[ -z "$tests" ]]; then
    echo "FentonHomeUITests/$class"
  else
    for t in $tests; do echo "FentonHomeUITests/$class/$t"; done
  fi
}

if [[ "$SUITE" == launch || "$SUITE" == all ]] && [[ -z "${TEST_RUNNER_FENTON_HASS_USERNAME:-}" ]]; then
  echo "note: no credentials (--env shell): the launch suite's warm-launch and arrival tests will skip" >&2
fi
if [[ -n "$LIVE" && -z "${TEST_RUNNER_FENTON_HASS_USERNAME:-}" ]]; then
  echo "note: --live without credentials (--env shell): testFlickLiveTabs cannot sign in" >&2
fi

cd "$ROOT/apple"
xcodegen generate --quiet
STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ "$SUITE" == all ]]; then SUITES=(scroll nav launch motion ticker); else SUITES=("$SUITE"); fi
FAILED=0
# Build once under a build slot, so the phone is held only while tests run on it.
DERIVED="$ROOT/apple/.build/perf-dd"
BUILD_LOG="$ROOT/apple/.build/perf-build-$STAMP.log"
echo "== building for the device -> $BUILD_LOG" >&2
python3 "$ROOT/tools/devcap.py" run --pool build --purpose "ios_perf build ($(basename "$ROOT"))" -- \
  xcodebuild build-for-testing -project FentonHome.xcodeproj -scheme FentonHome \
    -destination "platform=iOS,id=$DEVICE" -allowProvisioningUpdates -derivedDataPath "$DERIVED" \
    ${EXTRA[@]+"${EXTRA[@]}"} > "$BUILD_LOG" 2>&1 || { tail -30 "$BUILD_LOG"; exit 1; }
for s in "${SUITES[@]}"; do
  ONLY_ARGS=()
  while IFS= read -r t; do [[ -n "$t" ]] && ONLY_ARGS+=("-only-testing:$t"); done < <(suite_targets "$s")
  if [[ ${#ONLY_ARGS[@]} -eq 0 ]]; then echo "suite $s: no test named $ONLY, skipped" >&2; continue; fi
  RESULT="$ROOT/apple/.build/perf-$s-$STAMP.xcresult"
  echo "== suite $s -> $RESULT" >&2
  python3 "$ROOT/tools/devcap.py" run --device "$DEVICE" --hold "$HOLD" --purpose "ios_perf $s on $DEVICE ($(basename "$ROOT"))" -- \
    xcodebuild test-without-building -project FentonHome.xcodeproj -scheme FentonHome \
      -destination "platform=iOS,id=$DEVICE" -derivedDataPath "$DERIVED" \
      "${ONLY_ARGS[@]}" -resultBundlePath "$RESULT" \
      ${EXTRA[@]+"${EXTRA[@]}"} || FAILED=1
  echo "Results ($s): $RESULT"
done
exit $FAILED
