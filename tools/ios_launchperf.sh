#!/usr/bin/env bash
# Measures what the launch intro, a signed-in relaunch and the sign-in arrival cost the main thread, with the app's own launch
# cost probe (apple/Sources/HassUI/Diagnostics/LaunchCostProbe.swift; `.agents/testing/apple/performance.md`, "Launch and
# sign-in"). Simulator only: it never touches a phone. A simulator's hitch ratios mean nothing, so the number is the main thread's
# CPU time per run-loop turn (a turn longer than the frame budget is a hitch whatever the display says) plus the signpost intervals
# the run recorded (Launch, SnapshotShown, SignIn, Intro, Arrival).
#
# Cases, each on a fresh install and launched with nothing driving the app (no XCUITest event, no accessibility snapshot):
#   intro          signed out, the intro plays (1.2 s); measured for 2 s from the first frame
#   intro-reduced  the same with Reduce Motion on (cross-fades only)
#   arrival        signs in by itself (needs --env), Home arrives; measured from the tokens to the end of the arrival
#   snapshot       a warm relaunch of the signed-in app: the launch ground fading onto the disk snapshot
#   (arrival and snapshot need credentials: --env shell with FENTON_HASS_USERNAME / FENTON_HASS_PASSWORD.)
#
# Usage: tools/ios_launchperf.sh [--env shell] [--label NAME] [--no-build] [--app PATH.app] [--device-name "iPhone 17 Pro"]
#                                [--only intro,arrival] [--no-budget]
# Output: apple/.build/launchperf-<label>.tsv (raw lines) and the table from tools/launchcost_report.py, which exits 1 when a
# budget is missed (p95 turn <= 8 ms; worst turn 16 ms for the intro and 300 ms for the arrival and snapshot, which include
# Home's own first layout; SnapshotShown <= 500 ms, Arrival <= 1600 ms, Intro <= 1500 ms).
# The "arrival-build" row (tokens to Home built, behind the sign-in layer) is reported, not budgeted.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ENV_FILE=""
LABEL="$(date +%Y%m%d-%H%M%S)"
BUILD=1
APP=""
ONLY=""
BUDGET=1
DEVICE_NAME="${FENTON_SIM_IPHONE:-iPhone 17 Pro}"
INNER=""
UDID=""
DERIVED="$ROOT/apple/.build/launchperf-dd"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --app) APP="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --no-budget) BUDGET=0; shift ;;
    --device-name) DEVICE_NAME="$2"; shift 2 ;;
    --derived-data) DERIVED="$2"; shift 2 ;;
    --inner) INNER=1; shift ;;
    --udid) UDID="$2"; shift 2 ;;
    *) echo "unknown argument $1"; exit 2 ;;
  esac
done

TSV="$ROOT/apple/.build/launchperf-$LABEL.tsv"
BUNDLE="com.sfenton.home"

# Credentials come from the env file without echoing them.
if [[ -n "$ENV_FILE" ]]; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hass_creds.sh"; hass_use_env_arg "$ENV_FILE" || exit 2  # in-process only (tools/hass_creds.sh)
fi
USER_VALUE="${FENTON_HASS_USERNAME:-}"
PASS_VALUE="${FENTON_HASS_PASSWORD:-}"
SERVER_VALUE="${FENTON_HASS_SERVER:-}"

wants() { [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]]; }

if [[ -n "$INNER" ]]; then
  # ---- inside the simulator hold -------------------------------------------------------------------------------
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
  "$ROOT/tools/sim_slim.sh" "$UDID" || true
  rm -f "$TSV"

  # launch CASE PHASE [KEY=VALUE ...]: launches with the probe on and waits for PHASE's line.
  launch() {
    local name="$1" phase="$2"; shift 2
    local args=("SIMCTL_CHILD_FENTON_LAUNCHCOST=1" "SIMCTL_CHILD_FENTON_TELEMETRY=1" "SIMCTL_CHILD_FENTON_LAUNCHCOST_FILE=$TSV.$name")
    for kv in "$@"; do args+=("SIMCTL_CHILD_$kv"); done
    rm -f "$TSV.$name"
    local began=$SECONDS
    env "${args[@]}" xcrun simctl launch "$UDID" "$BUNDLE" > /dev/null
    for _ in $(seq 1 120); do
      grep -q "^LAUNCHCOST_DONE.$phase\$" "$TSV.$name" 2>/dev/null && break
      sleep 1
    done
    # The phase's line, and the "<phase>-build" line (building Home behind the sign-in layer) when there is one.
    awk -F'\t' -v OFS='\t' -v phase="$phase" -v name="$name" '
      $1 == "LAUNCHCOST" && $2 == phase { $2 = name; print }
      $1 == "LAUNCHCOST" && $2 == phase "-build" { $2 = name "-build"; print }' "$TSV.$name" >> "$TSV" 2>/dev/null || echo "no line for $name" >&2
    rm -f "$TSV.$name"
    echo "measured: $name (waited $((SECONDS - began)) s for its line)" >&2
  }
  fresh() { # a clean install: no saved sign-in, no snapshot, default settings
    xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
    xcrun simctl uninstall "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
    xcrun simctl install "$UDID" "$APP"
  }

  if wants intro; then
    fresh
    launch intro intro FENTON_UITEST_RESET=1 FENTON_SYSTEM_SETTINGS=none
  fi
  if wants intro-reduced; then
    fresh
    launch intro-reduced intro FENTON_UITEST_RESET=1 FENTON_SYSTEM_SETTINGS=reduceMotion
  fi
  if [[ -n "$USER_VALUE" && -n "$PASS_VALUE" ]] && { wants arrival || wants snapshot; }; then
    fresh
    server=(); [[ -n "$SERVER_VALUE" ]] && server=("FENTON_HASS_SERVER=$SERVER_VALUE")
    launch arrival arrival FENTON_UITEST_RESET=1 FENTON_SKIP_INTRO=1 FENTON_AUTOSIGNIN=1 FENTON_SYSTEM_SETTINGS=none \
      "FENTON_HASS_USERNAME=$USER_VALUE" "FENTON_HASS_PASSWORD=$PASS_VALUE" ${server[@]+"${server[@]}"}
    # The snapshot is written 10 s after the last change (HassConnection.snapshotDebounce); killing the app sooner loses it.
    sleep 14
    xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
    sleep 2
    # Relaunch without the reset: the Keychain keeps the sign-in and the disk keeps the snapshot written meanwhile.
    wants snapshot && launch snapshot snapshot FENTON_SYSTEM_SETTINGS=none
  else
    echo "skipping arrival and snapshot: no credentials (pass --env shell)" >&2
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
  exit 0
fi

mkdir -p "$ROOT/apple/.build"
cd "$ROOT/apple"
xcodegen generate --quiet
if [[ -z "$APP" ]]; then
  APP="$DERIVED/Build/Products/Debug-iphonesimulator/FentonHome.app"
  if [[ $BUILD == 1 ]]; then
    python3 "$ROOT/tools/devcap.py" run --pool build --purpose "launchperf build ($(basename "$ROOT"))" -- \
      xcodebuild build -project FentonHome.xcodeproj -scheme FentonHome -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES SWIFT_OPTIMIZATION_LEVEL=-O \
        > ".build/launchperf-build-$LABEL.log" 2>&1 || { grep -E "error:" ".build/launchperf-build-$LABEL.log" | cut -c1-300 | head -20; exit 1; }
  fi
fi
LAST=".build/launchperf.udid"
PREFER=()
[[ -s "$LAST" ]] && PREFER=(--prefer "$(cat "$LAST")")
UDID="$(python3 "$ROOT/tools/devcap.py" pick-sim --name "$DEVICE_NAME" --pool "${FENTON_SIM_POOL:-0}" ${PREFER[@]+"${PREFER[@]}"})"
echo "$UDID" > "$LAST"
python3 "$ROOT/tools/devcap.py" run --sim "$UDID" --hold 1800 --shutdown-on-timeout --purpose "launchperf ($(basename "$ROOT"))" -- \
  "$ROOT/tools/ios_launchperf.sh" --inner --udid "$UDID" --app "$APP" --label "$LABEL" ${ONLY:+--only "$ONLY"} ${ENV_FILE:+--env "$ENV_FILE"}

python3 "$ROOT/tools/launchcost_report.py" "$TSV" $([[ $BUDGET == 1 ]] || echo --no-budget) | tee "${TSV%.tsv}-report.txt"
