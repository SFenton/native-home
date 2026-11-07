#!/usr/bin/env bash
# Measures what the animated layout changes cost on the simulators: a row or section a person (or a live update) inserts or removes
# with the `standard` or `quick` token (custom lights' manual control, the vacation dates, the bedside alarm, the remote keyboard,
# the profile badge). `.agents/design/motion.md` §10, `.agents/testing/apple/performance.md`, "Layout changes".
#
# Runs LayoutChangePerformanceTests on the iPhone, iPhone Duo and iPad simulators, one at a time, each inside devcap holds
# (tools/devcap.py): five iterations of five switch flips on Custom Lights, with XCTCPUMetric, the app's own `LayoutChange` signpost
# and, on iOS 26+, XCTHitchMetric (simulator hitch ratios are false; the budgets that matter are CPU), with Reduce Motion off and on.
#
# Usage: tools/ios_motionperf.sh [--only iphone|duo|ipad] [--label NAME] [extra xcodebuild args]
# Output: apple/.build/motionperf-<family>-<label>.log and the xcresult bundles beside it.
# Nothing here installs anything on a phone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/sim_pool.sh"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ONLY=""
LABEL="$(date +%Y%m%d-%H%M%S)"
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

device_name() {
  case "$1" in
    iphone) echo "${FENTON_SIM_IPHONE:-iPhone 17 Pro}" ;;
    duo) echo "${FENTON_SIM_DUO:-iPhone Duo (HASS)}" ;;
    ipad) echo "${FENTON_SIM_IPAD:-iPad Pro 11-inch (M5)}" ;;
  esac
}

export TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1
DEVCAP=(python3 "$ROOT/tools/devcap.py" run --hold "${FENTON_DEVCAP_HOLD:-3600}")
LANE="$(basename "$ROOT")"
cd "$ROOT/apple"
mkdir -p .build
xcodegen generate --quiet
"${DEVCAP[@]}" --pool build --purpose "Fenton motionperf build ($LANE)" -- \
  xcodebuild build-for-testing -project FentonHome.xcodeproj -scheme FentonHome -destination 'generic/platform=iOS Simulator' \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES > ".build/motionperf-build-$LABEL.log" 2>&1 \
  || { tail -30 ".build/motionperf-build-$LABEL.log"; exit 1; }

STATUS=0
for family in iphone duo ipad; do
  [[ -n "$ONLY" && "$ONLY" != "$family" ]] && continue
  name="$(device_name "$family")"
  if ! sim_pool_list | sim_pool_has "$name"; then
    echo "GAP: no available simulator named '$name' for $family (a gap, not a pass)"; STATUS=1; continue
  fi
  last_file=".build/motionperf-$family.udid"
  prefer=()
  [[ -s "$last_file" ]] && prefer=(--prefer "$(cat "$last_file")")
  udid="$(python3 "$ROOT/tools/devcap.py" pick-sim --name "$name" --pool "${FENTON_SIM_POOL:-0}" ${prefer[@]+"${prefer[@]}"})"
  echo "$udid" > "$last_file"
  echo "== $family: $name ($udid)" >&2
  log=".build/motionperf-$family-$LABEL.log"
  rm -rf ".build/motionperf-$family.xcresult"
  "${DEVCAP[@]}" --sim "$udid" --shutdown-on-timeout --purpose "Fenton motionperf $family ($LANE)" -- \
    xcodebuild test-without-building -project FentonHome.xcodeproj -scheme FentonHome \
      -destination "platform=iOS Simulator,id=$udid" -only-testing:"FentonHomeUITests/LayoutChangePerformanceTests" -only-testing:"FentonHomeUITests/HouseLayoutRevealPerformanceTests" \
      -resultBundlePath ".build/motionperf-$family.xcresult" ${EXTRA[@]+"${EXTRA[@]}"} > "$log" 2>&1 || STATUS=1
  # The metrics' averages print as "Test Case ... measured [CPU Time, s] average: ..." lines.
  grep -E "Test Case .* (passed|failed|skipped)|error:|measured \[|average:" "$log" | sed 's/^/  /' >&2 || true
done

echo "Budgets: a flip costs the main thread no turn over 16 ms; the LayoutChange interval is the token length (0.3 s) plus a frame; hitch ratio under 5 ms/s on a device." >&2
exit $STATUS
