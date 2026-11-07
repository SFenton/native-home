#!/usr/bin/env bash
# Measures what scrolling every page and scrolling sheet costs, with the app's own scroll cost probe
# (apple/Sources/HassUI/Diagnostics/ScrollCostProbe.swift; `.agents/testing/apple/performance.md`, "Scroll cost").
#
# Each surface in tools/scrollcost-surfaces.txt is launched on its own. The app waits for the page to settle, stands still for
# 8 s (the floor), then drives the front scroll view up and down at 900 pt/s for 8 s twice, and reports the CPU instructions
# the process retired, the main thread's CPU time and its run-loop turns longer than 4, 8 and 16 ms (a turn longer than the
# frame budget is a hitch whatever the display says). No test drives the app, so no XCUITest event or accessibility
# snapshot is in the number.
#
# Simulator (default): builds the app optimized (-O, the Release code path with the debug gallery still in), runs every
# surface on one iPhone simulator inside a devcap hold, and prints a table.
#   tools/ios_scrollcost.sh [--section gallery|live|finish|layers|backdrop|flyout|all (or a comma list: flyout,live)] [--only "Living Room,Live Home"] [--env shell|FILE]
#                           [--label NAME] [--compare BASE.tsv] [--no-build] [--app PATH.app] [--disable headerFade,backdrop]
#                           [--delay SECONDS] [--device-name "iPhone 17 Pro"] [--launch-env "KEY=VALUE ..."]
#                           [--ab "base=KEY=VALUE;fix=" --rounds N]
#   --launch-env  Extra launch environment for every surface (space separated).
#   --ab          A/B in one hold, alternating (`.agents/testing/apple/performance.md`, "Measure A/B in one hold, alternating"): the
#                 same app launched per variant, `name=KEY=VALUE KEY=VALUE` separated by `;` (an empty value is the plain app).
#                 Each surface is measured as variant 1, variant 2, ... then the next round, so drift on the Mac hits every
#                 variant alike. Writes apple/.build/scrollcost-LABEL-NAME-rN.tsv per variant and round, and prints each.
#                 With FENTON_SCROLLCOST_RECONNECT=1 (Debug builds) each run ends with a forced network blip, counted.
#   [live] surfaces sign in with the TOKEN from --env (Debug builds only); [gallery] surfaces need nothing.
#
# A phone (the owner runs this; nothing here installs anything): launches the [live] surfaces on the installed app (a
# Release build, signed in already), one `devicectl --console` per surface.
#   tools/ios_scrollcost.sh --device 00008160-00022D8230914036 [--only "Live Living Room"] [--disable headerFade]
#   A/B for what only a GPU shows: run once, then again with `--disable headerFade` (or `backdrop`), and compare the two
#   .tsv files with `tools/scrollcost_report.py B.tsv --compare A.tsv`.
#
# Output: apple/.build/scrollcost-<label>.tsv (raw rows) and -report.tsv (the table).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SECTION="all"
ONLY=""
ENV_FILE=""
LABEL="$(date +%Y%m%d-%H%M%S)"
COMPARE=""
BUILD=1
APP=""
DISABLE=""
DELAY=""
DEVICE=""
DEVICE_NAME="${FENTON_SIM_IPHONE:-iPhone 17 Pro}"
LAUNCH_ENV=""
AB=""
ROUNDS=1
INNER=""
DEVICE_INNER=""
UDID=""
DERIVED="$ROOT/apple/.build/scrollcost-dd"
VARIANT_ENV=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --section) SECTION="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --env) ENV_FILE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --compare) COMPARE="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --app) APP="$2"; shift 2 ;;
    --disable) DISABLE="$2"; shift 2 ;;
    --delay) DELAY="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --device-name) DEVICE_NAME="$2"; shift 2 ;;
    --launch-env) LAUNCH_ENV="$2"; shift 2 ;;
    --ab) AB="$2"; shift 2 ;;
    --rounds) ROUNDS="$2"; shift 2 ;;
    --derived-data) DERIVED="$2"; shift 2 ;;
    --inner) INNER=1; shift ;;
    --device-inner) DEVICE_INNER=1; shift ;;
    --udid) UDID="$2"; shift 2 ;;
    *) echo "unknown argument $1"; exit 2 ;;
  esac
done

# Each --ab variant is `name=ENV...` (the environment may be empty, "fix="); a bare name would be launched as an env word.
if [[ -n "$AB" ]]; then
  IFS=';' read -ra _ab_variants <<< "$AB"
  for _v in "${_ab_variants[@]}"; do
    [[ "$_v" == ?*=* ]] || { echo "--ab variant '$_v' must look like name=KEY=VALUE (or name= for none)"; exit 2; }
  done
fi

TSV="$ROOT/apple/.build/scrollcost-$LABEL.tsv"
SURFACES="$ROOT/tools/scrollcost-surfaces.txt"
BUNDLE="com.sfenton.home"

# Credentials come from the env file without echoing them; only [live] surfaces on a simulator use them.
if [[ -n "$ENV_FILE" ]]; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hass_creds.sh"; hass_use_env_arg "$ENV_FILE" || exit 2  # in-process only (tools/hass_creds.sh)
fi
TOKEN_VALUE="${FENTON_HASS_TOKEN:-}"

# The surfaces to run, one `Name|ENV...` per line.
surface_lines() {
  local want="$SECTION" current=""
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == \[*\] ]]; then current="${line//[\[\]]/}"; continue; fi
    [[ "$want" != all && ",$want," != *",$current,"* ]] && continue
    [[ "$want" == all && ( "$current" == finish || "$current" == layers || "$current" == backdrop || "$current" == flyout ) ]] && continue # The A/B sections run only on request.
    if [[ -n "$ONLY" ]]; then
      local name="${line%%|*}" keep=""
      IFS=',' read -ra picks <<< "$ONLY"
      for pick in "${picks[@]}"; do [[ "$name" == "$pick" ]] && keep=1; done
      [[ -z "$keep" ]] && continue
    fi
    echo "$line"
  done < "$SURFACES"
}

# The launch environment for one surface as `KEY=VALUE` lines (LIVE=1 becomes the sign-in).
launch_words() {
  local envs="$1" kv words=()
  # Split on blanks without globbing (`read -a` does not expand `*`), then one word per line.
  read -ra words <<< "$envs"
  for kv in "${words[@]}"; do
    if [[ "$kv" == LIVE=1 ]]; then echo "FENTON_HASS_TOKEN=$TOKEN_VALUE"; else echo "$kv"; fi
  done
  printf '%s\n' "FENTON_SCROLLCOST=1" "FENTON_SCROLLCOST_SECONDS=8" "FENTON_TELEMETRY=1" "FENTON_SYSTEM_SETTINGS=none"
  read -ra words <<< "$LAUNCH_ENV $VARIANT_ENV"
  for kv in "${words[@]}"; do echo "$kv"; done
  if [[ -n "$DISABLE" ]]; then echo "FENTON_PERF_DISABLE=$DISABLE"; fi
}

if [[ -n "$INNER" ]]; then
  # ---- inside the simulator hold -------------------------------------------------------------------------------
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
  "$ROOT/tools/sim_slim.sh" "$UDID" || true
  # One measurement: a fresh install, the surface launched with the variant's environment, wait for it to finish.
  measure() {
    local NAME="$1" ENVS="$2" OUT="$3"
    local settle="${DELAY:-9}"
    [[ "$ENVS" == *LIVE=1* ]] && settle="${DELAY:-18}"
    # A fresh install each time: the app restores the tab it was last on (SceneStorage), so a page left by the last surface would
    # be this one's starting page.
    xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
    xcrun simctl uninstall "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
    xcrun simctl install "$UDID" "$APP"
    local args=() word
    while IFS= read -r word; do args+=("SIMCTL_CHILD_$word"); done < <(launch_words "$ENVS")
    env "${args[@]}" SIMCTL_CHILD_FENTON_UITEST_RESET=1 SIMCTL_CHILD_FENTON_SCROLLCOST_AUTORUN="$settle" \
      SIMCTL_CHILD_FENTON_SCROLLCOST_FILE="$OUT" SIMCTL_CHILD_FENTON_SCROLLCOST_NAME="$NAME" \
      xcrun simctl launch "$UDID" "$BUNDLE" > /dev/null
    for _ in $(seq 1 $((settle + 100))); do
      grep -q "^SCROLLCOST_DONE.$NAME\$" "$OUT" 2>/dev/null && break
      sleep 1
    done
    echo "measured: $NAME ($OUT)" >&2
  }
  if [[ -n "$AB" ]]; then
    IFS=';' read -ra VARIANTS <<< "$AB"
    for v in "${VARIANTS[@]}"; do rm -f "$ROOT/apple/.build/scrollcost-$LABEL-${v%%=*}"-r*.tsv; done
    for round in $(seq 1 "$ROUNDS"); do
      while IFS='|' read -r NAME ENVS; do
        for v in "${VARIANTS[@]}"; do
          VARIANT_ENV="${v#*=}"
          measure "$NAME" "$ENVS" "$ROOT/apple/.build/scrollcost-$LABEL-${v%%=*}-r$round.tsv"
        done
      done < <(surface_lines)
    done
  else
    rm -f "$TSV"
    while IFS='|' read -r NAME ENVS; do measure "$NAME" "$ENVS" "$TSV"; done < <(surface_lines)
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
  exit 0
fi

mkdir -p "$ROOT/apple/.build"

if [[ -n "$DEVICE" ]]; then
  # ---- a phone: the installed app, one launch per live surface ---------------------------------------------------
  SECTION=live
  # One devcap device hold around the whole loop (FIFO with other users of the phone): the script re-runs itself with
  # --device-inner inside the hold, then prints the report here.
  if [[ -z "$DEVICE_INNER" ]]; then
    python3 "$ROOT/tools/devcap.py" run --device "$DEVICE" --hold 5400 --purpose "scrollcost on the phone ($(basename "$ROOT"))" -- \
      "$ROOT/tools/ios_scrollcost.sh" --device-inner --device "$DEVICE" --label "$LABEL" ${ONLY:+--only "$ONLY"} \
      ${DISABLE:+--disable "$DISABLE"} ${DELAY:+--delay "$DELAY"} ${LAUNCH_ENV:+--launch-env "$LAUNCH_ENV"}
  else
    rm -f "$TSV"
    while IFS='|' read -r NAME ENVS; do
      json="{"
      first=1
      while IFS= read -r word; do
        [[ "$word" == FENTON_HASS_TOKEN=* ]] && continue
        key="${word%%=*}"; value="${word#*=}"
        [[ $first == 1 ]] || json+=","
        json+="\"$key\":\"$value\""
        first=0
      done < <(launch_words "$ENVS")
      json+=",\"FENTON_SCROLLCOST_AUTORUN\":\"${DELAY:-18}\",\"FENTON_SCROLLCOST_EXIT\":\"1\",\"FENTON_SCROLLCOST_NAME\":\"$NAME\"}"
      echo "launching on the phone: $NAME" >&2
      xcrun devicectl device process launch --device "$DEVICE" --terminate-existing --console \
        --environment-variables "$json" "$BUNDLE" < /dev/null 2>/dev/null | grep -E '^SCROLLCOST' >> "$TSV" || true
    done < <(surface_lines)
    exit 0
  fi
else
  # ---- simulator: build, then run every surface inside one hold --------------------------------------------------
  cd "$ROOT/apple"
  xcodegen generate --quiet
  if [[ -z "$APP" ]]; then
    APP="$DERIVED/Build/Products/Debug-iphonesimulator/FentonHome.app"
    if [[ $BUILD == 1 ]]; then
      python3 "$ROOT/tools/devcap.py" run --pool build --purpose "scrollcost build ($(basename "$ROOT"))" -- \
        xcodebuild build -project FentonHome.xcodeproj -scheme FentonHome -destination 'generic/platform=iOS Simulator' \
          -derivedDataPath "$DERIVED" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES SWIFT_OPTIMIZATION_LEVEL=-O \
          > ".build/scrollcost-build-$LABEL.log" 2>&1 || { tail -30 ".build/scrollcost-build-$LABEL.log"; exit 1; }
    fi
  fi
  LAST=".build/scrollcost.udid"
  PREFER=()
  [[ -s "$LAST" ]] && PREFER=(--prefer "$(cat "$LAST")")
  UDID="$(python3 "$ROOT/tools/devcap.py" pick-sim --name "$DEVICE_NAME" --pool "${FENTON_SIM_POOL:-0}" ${PREFER[@]+"${PREFER[@]}"})"
  echo "$UDID" > "$LAST"
  python3 "$ROOT/tools/devcap.py" run --sim "$UDID" --hold 5400 --shutdown-on-timeout --purpose "scrollcost ($(basename "$ROOT"))" -- \
    "$ROOT/tools/ios_scrollcost.sh" --inner --udid "$UDID" --app "$APP" --section "$SECTION" --label "$LABEL" ${ONLY:+--only "$ONLY"} \
    ${ENV_FILE:+--env "$ENV_FILE"} ${DISABLE:+--disable "$DISABLE"} ${DELAY:+--delay "$DELAY"} ${LAUNCH_ENV:+--launch-env "$LAUNCH_ENV"} \
    ${AB:+--ab "$AB" --rounds "$ROUNDS"}
fi
[[ -n "$AB" ]] && exit 0

python3 "$ROOT/tools/scrollcost_report.py" "$TSV" ${COMPARE:+--compare "$COMPARE"} | tee "${TSV%.tsv}-report.tsv"
