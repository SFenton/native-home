#!/usr/bin/env bash
# Measures what the Home weather card's label ticker costs on the simulators (`.agents/design/motion.md` §9 ticker exception,
# `.agents/testing/apple/performance.md`, "Weather card ticker").
#
# Two measurements, each inside devcap holds (tools/devcap.py):
#   1. WeatherTickerPerformanceTests on the iPhone, iPhone Duo and iPad simulators, one at a time: ten seconds of a ticking card
#      against ten seconds of a still one, with XCTCPUMetric, the app's own TickerRun signpost, and XCTHitchMetric on iOS 26+
#      (simulator hitch ratios are false; the budgets that matter are CPU).
#   2. tools/ios_scrollcost.sh on the "Weather card" surfaces: the page scrolled and standing still with a ticking label and with a
#      short one (the ticker pauses while the page scrolls, so the scroll numbers should match the short label's).
#
# Usage: tools/ios_tickerperf.sh [--only iphone|duo|ipad] [--skip-scrollcost] [--label NAME] [extra xcodebuild args]
# Output: apple/.build/tickerperf-<family>-<label>.log, the xcresult bundles beside it, and the scroll cost table on stdout.
# Nothing here installs anything on a phone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/sim_pool.sh"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ONLY=""
SKIP_SCROLL=0
LABEL="$(date +%Y%m%d-%H%M%S)"
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --skip-scrollcost) SKIP_SCROLL=1; shift ;;
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
"${DEVCAP[@]}" --pool build --purpose "Fenton tickerperf build ($LANE)" -- \
  xcodebuild build-for-testing -project FentonHome.xcodeproj -scheme FentonHome -destination 'generic/platform=iOS Simulator' \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES > ".build/tickerperf-build-$LABEL.log" 2>&1 \
  || { tail -30 ".build/tickerperf-build-$LABEL.log"; exit 1; }

STATUS=0
for family in iphone duo ipad; do
  [[ -n "$ONLY" && "$ONLY" != "$family" ]] && continue
  name="$(device_name "$family")"
  if ! sim_pool_list | sim_pool_has "$name"; then
    echo "GAP: no available simulator named '$name' for $family (a gap, not a pass)"; STATUS=1; continue
  fi
  last_file=".build/tickerperf-$family.udid"
  prefer=()
  [[ -s "$last_file" ]] && prefer=(--prefer "$(cat "$last_file")")
  udid="$(python3 "$ROOT/tools/devcap.py" pick-sim --name "$name" --pool "${FENTON_SIM_POOL:-0}" ${prefer[@]+"${prefer[@]}"})"
  echo "$udid" > "$last_file"
  echo "== $family: $name ($udid)" >&2
  log=".build/tickerperf-$family-$LABEL.log"
  rm -rf ".build/tickerperf-$family.xcresult"
  "${DEVCAP[@]}" --sim "$udid" --shutdown-on-timeout --purpose "Fenton tickerperf $family ($LANE)" -- \
    xcodebuild test-without-building -project FentonHome.xcodeproj -scheme FentonHome \
      -destination "platform=iOS Simulator,id=$udid" -only-testing:"FentonHomeUITests/WeatherTickerPerformanceTests" \
      -resultBundlePath ".build/tickerperf-$family.xcresult" ${EXTRA[@]+"${EXTRA[@]}"} > "$log" 2>&1 || STATUS=1
  # The metrics' averages print as "Test Case ... measured [CPU Time, s] average: ..." lines.
  grep -E "Test Case .* (passed|failed|skipped)|error:|measured \[|average:" "$log" | sed 's/^/  /' >&2 || true
done

if [[ "$SKIP_SCROLL" != 1 ]]; then
  "$ROOT/tools/ios_scrollcost.sh" --only "Weather card short label,Weather card ticking label" || STATUS=1
fi
echo "Budgets: ticking card at most 10% of one core above the still card over 10 s; hitch ratio under 5 ms/s on a device." >&2
exit $STATUS
