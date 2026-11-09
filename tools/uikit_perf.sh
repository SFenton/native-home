#!/usr/bin/env bash
# Performance of the app (UIKit) on one simulator: frame rate, memory, CPU and GPU. The SwiftUI app is gone from this branch;
# for an A/B against the old one pass `--apps swiftui,uikit` with SWIFTUI_APP=<a .app built from main>.
#   tools/uikit_perf.sh --surfaces FILE [--family iphone|ipad] [--rounds 3] [--label NAME] [--only "A,B"] [--apps swiftui,uikit]
# FILE uses tools/scrollcost-surfaces.txt's format (`name|ENV ...`; only [gallery] sections are run).
# Per surface, per round, per app (the order alternates each round): a fresh install, the scroll cost autorun (8 s idle, two
# 8 s scrolls at 900 pt/s; `ScrollCostProbe` and `FramePacer`, the same code in both apps) and a host sampler
# (`tools/perf_sampler.py`: Mac GPU utilisation, the simulator's render server CPU). Results: build/perf/<label>/,
# report from tools/uikit_perf_report.py. Apps: optimized builds (tools/uikit_build.sh --optimized [--scheme FentonHome]).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SURFACES=""; FAMILY=iphone; ROUNDS=3; LABEL="perf-$(date +%Y%m%d-%H%M)"; ONLY=""; INNER=0; UDID=""; SETTLE=9; APPS="uikit"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --surfaces) SURFACES="$2"; shift 2 ;;
    --family) FAMILY="$2"; shift 2 ;;
    --rounds) ROUNDS="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --settle) SETTLE="$2"; shift 2 ;;
    --apps) APPS="$2"; shift 2 ;;
    --inner) INNER=1; UDID="$2"; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ -n "$SURFACES" ]] || { echo "usage: $0 --surfaces FILE" >&2; exit 2; }
OUT="$ROOT/build/perf/$LABEL"
UIKIT_APP="${UIKIT_APP:-$ROOT/apple/build/dd-FentonHome-O/Build/Products/Debug-iphonesimulator/FentonHome.app}"
SWIFTUI_APP="${SWIFTUI_APP:-}"

surface_lines() {
  local section="" line
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == \[*\] ]]; then section="$line"; continue; fi
    [[ -n "$section" && "$section" != "[gallery]" ]] && continue
    if [[ -n "$ONLY" ]]; then
      local name="${line%%|*}" keep=""
      IFS=',' read -ra wanted <<< "$ONLY"
      for w in "${wanted[@]}"; do [[ "$name" == "$w" ]] && keep=1; done
      [[ -z "$keep" ]] && continue
    fi
    echo "$line"
  done < "$SURFACES"
}

if [[ $INNER == 1 ]]; then
  mkdir -p "$OUT"
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
  "$ROOT/tools/sim_slim.sh" "$UDID" > /dev/null 2>&1 || true
  run_one() { # round app name envs
    local round="$1" app="$2" name="$3" envs="$4" bundle path exe args=() kv tsv samples sampler
    if [[ $app == swiftui ]]; then bundle=com.sfenton.home; path="$SWIFTUI_APP"; exe=FentonHome
    else bundle=com.sfenton.home; path="$UIKIT_APP"; exe=FentonHome; fi
    local safe; safe=$(echo "$name" | tr -c 'A-Za-z0-9._-' '-')
    tsv="$OUT/r$round-$app-$safe.tsv"; samples="$OUT/r$round-$app-$safe.samples.tsv"
    rm -f "$tsv"
    xcrun simctl terminate "$UDID" "$bundle" > /dev/null 2>&1 || true
    xcrun simctl uninstall "$UDID" "$bundle" > /dev/null 2>&1 || true
    xcrun simctl install "$UDID" "$path"
    for kv in $envs FENTON_SCROLLCOST=1 FENTON_SCROLLCOST_SECONDS=8 FENTON_TELEMETRY=1 FENTON_SYSTEM_SETTINGS=none \
              FENTON_SKIP_INTRO=1 FENTON_UITEST_RESET=1 FENTON_SCROLLCOST_AUTORUN=$SETTLE; do args+=("SIMCTL_CHILD_$kv"); done
    python3 "$ROOT/tools/perf_sampler.py" --udid "$UDID" --executable "$exe" --out "$samples" &
    sampler=$!
    env "${args[@]}" SIMCTL_CHILD_FENTON_SCROLLCOST_FILE="$tsv" SIMCTL_CHILD_FENTON_SCROLLCOST_NAME="$name" \
      xcrun simctl launch "$UDID" "$bundle" > /dev/null
    for _ in $(seq 1 $((SETTLE + 75))); do
      grep -q "^SCROLLCOST_DONE" "$tsv" 2>/dev/null && break
      sleep 1
    done
    kill "$sampler" 2>/dev/null || true; wait "$sampler" 2>/dev/null || true
    xcrun simctl terminate "$UDID" "$bundle" > /dev/null 2>&1 || true
    echo "measured: round $round $app $name" >&2
  }
  for round in $(seq 1 "$ROUNDS"); do
    while IFS='|' read -r NAME ENVS; do
      if [[ "$APPS" != *swiftui* ]]; then run_one "$round" uikit "$NAME" "$ENVS"
      elif [[ "$APPS" != *uikit* ]]; then run_one "$round" swiftui "$NAME" "$ENVS"
      elif (( round % 2 == 1 )); then run_one "$round" swiftui "$NAME" "$ENVS"; run_one "$round" uikit "$NAME" "$ENVS"
      else run_one "$round" uikit "$NAME" "$ENVS"; run_one "$round" swiftui "$NAME" "$ENVS"; fi
    done < <(surface_lines)
  done
  exit 0
fi

case "$FAMILY" in
  iphone) NAME="${FENTON_SIM_IPHONE:-iPhone 17 Pro}" ;;
  ipad) NAME="${FENTON_SIM_IPAD:-iPad Pro 11-inch (M5)}" ;;
  duo) NAME="${FENTON_SIM_DUO:-iPhone Duo (HASS)}" ;;
esac
SIM="$(python3 "$ROOT/tools/devcap.py" pick-sim --name "$NAME" --pool "${FENTON_SIM_POOL:-0}")"
python3 "$ROOT/tools/devcap.py" run --sim "$SIM" --hold 7200 --shutdown-on-timeout --purpose "uikit-port perf $FAMILY" -- \
  "$0" --inner "$SIM" --surfaces "$SURFACES" --rounds "$ROUNDS" --label "$LABEL" --settle "$SETTLE" --apps "$APPS" ${ONLY:+--only "$ONLY"}
python3 "$ROOT/tools/uikit_perf_report.py" "$OUT" | tee "$OUT/report.md"
