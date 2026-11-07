#!/usr/bin/env bash
# Measures what navigation costs on the simulators: tab switches, pushes and pops of a room page, sheets and zooms, with the app's
# own navigation telemetry (apple/Sources/HassTelemetry/NavigationMeasurement.swift, HassUI/Diagnostics/NavigationTelemetry.swift;
# `.agents/design/motion.md` §10, `.agents/testing/apple/performance.md`, "Navigation").
#
# Runs NavigationPerformanceTests on the iPhone, iPhone Duo and iPad simulators, one at a time, each inside a devcap hold
# (tools/devcap.py), and prints the per-surface p50 and p95 (first frame and settled) and the main thread's turn costs. The tests
# assert the simulator CPU budgets: the transition's p95 run-loop turn <= 8 ms, none over 16 ms, a tab tap to its first frame
# <= 50 ms p95. Simulator hitch ratios are false and not asserted.
#
# Usage: tools/ios_navperf.sh [--env shell] [--only iphone|duo|ipad] [--test testName] [--label NAME] [--allow-empty] [extra xcodebuild args]
#   A family whose run wrote no NAVPERF row (every test skipped, or none ran) is EMPTY, not a pass: it prints `EMPTY: …` and the script
#   exits 1. --allow-empty accepts it (and prints an `allow-empty` line so the bg_run digest stays PASS).
#   The live tests (tab cycle, Home revisit, zoom) sign in with the TOKEN or USERNAME/PASSWORD from --env and only navigate and read.
#   The push/pop and sheet tests use the Rooms gallery (fixtures, no house).
# Device tests (testDevice...) skip on a simulator; nothing here installs anything on a phone.
#
# Output: apple/.build/navperf-<label>.tsv (raw NAVPERF rows) and the table on stdout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/sim_pool.sh"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ENV_FILE=""
ONLY=""
TEST=""
LABEL="$(date +%Y%m%d-%H%M%S)"
ALLOW_EMPTY=0
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --test) TEST="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --allow-empty) ALLOW_EMPTY=1; echo "allow-empty: a family with no NAVPERF row is not a failure"; shift ;;
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

if [[ -n "$ENV_FILE" ]]; then
  # Accept KEY=VALUE lines without echoing them; map common names onto the runner variables.
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hass_creds.sh"; hass_use_env_arg "$ENV_FILE" || exit 2  # in-process only (tools/hass_creds.sh)
  export TEST_RUNNER_FENTON_HASS_USERNAME="${FENTON_HASS_USERNAME:-}"
  export TEST_RUNNER_FENTON_HASS_PASSWORD="${FENTON_HASS_PASSWORD:-}"
  [[ "${FENTON_UITEST_NO_TOKEN:-}" == 1 ]] || export TEST_RUNNER_FENTON_HASS_TOKEN="${FENTON_HASS_TOKEN:-}"
  SERVER="${FENTON_HASS_SERVER:-}"
  [[ -n "$SERVER" ]] && export TEST_RUNNER_FENTON_HASS_SERVER="$SERVER"
fi
export TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1

DEVCAP=(python3 "$ROOT/tools/devcap.py" run --hold "${FENTON_DEVCAP_HOLD:-3600}")
LANE="$(basename "$ROOT")"
TSV="$ROOT/apple/.build/navperf-$LABEL.tsv"
ONLY_TESTING="FentonHomeUITests/NavigationPerformanceTests${TEST:+/$TEST}"

cd "$ROOT/apple"
mkdir -p .build
xcodegen generate --quiet
"${DEVCAP[@]}" --pool build --purpose "Fenton navperf build ($LANE)" -- \
  xcodebuild build-for-testing -project FentonHome.xcodeproj -scheme FentonHome -destination 'generic/platform=iOS Simulator' \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES > ".build/navperf-build-$LABEL.log" 2>&1 \
  || { tail -30 ".build/navperf-build-$LABEL.log"; exit 1; }

: > "$TSV"
STATUS=0
for family in iphone duo ipad; do
  [[ -n "$ONLY" && "$ONLY" != "$family" ]] && continue
  name="$(device_name "$family")"
  if ! sim_pool_list | sim_pool_has "$name"; then
    echo "GAP: no available simulator named '$name' for $family (a gap, not a pass)"; STATUS=1; continue
  fi
  last_file=".build/navperf-$family.udid"
  prefer=()
  [[ -s "$last_file" ]] && prefer=(--prefer "$(cat "$last_file")")
  udid="$(python3 "$ROOT/tools/devcap.py" pick-sim --name "$name" --pool "${FENTON_SIM_POOL:-0}" ${prefer[@]+"${prefer[@]}"})"
  echo "$udid" > "$last_file"
  echo "== $family: $name ($udid)" >&2
  log=".build/navperf-$family-$LABEL.log"
  rm -rf ".build/navperf-$family.xcresult"
  rows="$ROOT/apple/.build/navperf-$family-$LABEL.rows"
  : > "$rows"
  export TEST_RUNNER_FENTON_NAVPERF_OUT="$rows"
  "${DEVCAP[@]}" --sim "$udid" --shutdown-on-timeout --purpose "Fenton navperf $family ($LANE)" -- \
    bash -c '"$0/tools/sim_slim.sh" "$1" || true; shift; exec "$@"' "$ROOT" "$udid" \
    xcodebuild test-without-building -project FentonHome.xcodeproj -scheme FentonHome \
      -destination "platform=iOS Simulator,id=$udid" -only-testing:"$ONLY_TESTING" \
      -resultBundlePath ".build/navperf-$family.xcresult" ${EXTRA[@]+"${EXTRA[@]}"} > "$log" 2>&1 || STATUS=1
  # The tests write one NAVPERF row per surface to the file named by TEST_RUNNER_FENTON_NAVPERF_OUT (and attach it).
  if [[ ! -s "$rows" ]] && ! grep -q "^NAVPERF" "$rows" 2>/dev/null; then
    skipped="$(grep -c "Test Case .* skipped" "$log" || true)"
    if [[ $ALLOW_EMPTY == 0 ]]; then
      echo "EMPTY: $family produced no NAVPERF rows (skipped test cases: ${skipped:-0}); see $log (--allow-empty if intended)" >&2
      STATUS=1
    fi
  fi
  cat "$rows" >> "$TSV"
  grep -E "Test Case .* (passed|failed|skipped)|error:" "$log" | sed 's/^/  /' >&2 || true
done

# The table: family, scenario, surface, then p50 and p95 for first frame and settled, and the turn costs.
python3 - "$TSV" <<'PY'
import sys
rows = [line.rstrip("\n").split("\t") for line in open(sys.argv[1]) if line.startswith("NAVPERF")]
if not rows:
    print("No NAVPERF rows: every test skipped or failed (see apple/.build/navperf-*.log).")
    sys.exit(0)
def field(row, key):
    for cell in row[4:]:
        if cell.startswith(key + "="):
            return cell.split("=", 1)[1]
    return "-"
header = ["family", "scenario", "surface", "n", "first p50", "first p95", "settled p50", "settled p95", "turn p95", "turn worst"]
table = [header] + [[r[1], r[2], r[3], field(r, "n"), field(r, "first.p50"), field(r, "first.p95"), field(r, "settled.p50"),
                     field(r, "settled.p95"), field(r, "turn.p95"), field(r, "turn.worst")] for r in rows]
widths = [max(len(row[i]) for row in table) for i in range(len(header))]
for row in table:
    print("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)))
print("\nms. Budgets (simulator CPU): turn p95 <= 8, turn worst <= 16, tab first frame p95 <= 50, push or sheet settled <= 600.")
PY
exit $STATUS
