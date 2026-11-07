#!/usr/bin/env bash
# Screenshots of the app (`FentonHome`, UIKit) on a simulator, same launch environment per surface.
#   tools/uikit_shot.sh --family iphone|duo|ipad --surfaces FILE --out DIR [--apps uikit] [--wait SECONDS]
# (`--apps` is kept so older commands still run; there is only the one app now.)
# FILE holds `name|KEY=VALUE KEY=VALUE ...` lines (like tools/scrollcost-surfaces.txt; `#` comments, blank lines skipped).
# A `LIVE=1` surface signs in to the live server with the token from tools/hass_creds.sh.
# Writes DIR/<name>-uikit.png. One devcap simulator hold for the whole list; the simulator is slimmed.
# The iPhone Duo has two displays and the default one is black: with --family duo each shot is taken from both,
# <name>-<app>.png from the outer screen (`primary`, folded) and <name>-<app>-inner.png from the inner one (`primary-1`, unfolded).
# Pose the Duo before the run (`pose.py`, outside any devcap hold on the same device: it takes the device lock itself).
# Builds are not done here: build first with tools/uikit_build.sh; the app is taken from apple/build/dd-FentonHome
# unless UIKIT_APP is set.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
FAMILY=iphone; SURFACES=""; OUT=""; APPS=both; WAIT=6; INNER=0; UDID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --family) FAMILY="$2"; shift 2 ;;
    --surfaces) SURFACES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --apps) APPS="$2"; shift 2 ;;
    --wait) WAIT="$2"; shift 2 ;;
    --inner) INNER=1; UDID="$2"; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ -n "$SURFACES" && -n "$OUT" ]] || { echo "usage: $0 --family F --surfaces FILE --out DIR" >&2; exit 2; }
UIKIT_APP="${UIKIT_APP:-$ROOT/apple/build/dd-FentonHome/Build/Products/Debug-iphonesimulator/FentonHome.app}"
mkdir -p "$OUT"

if [[ $INNER == 1 ]]; then
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
  "$ROOT/tools/sim_slim.sh" "$UDID" > /dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance dark > /dev/null 2>&1 || true
  shoot() { # name bundle app suffix envs
    local name="$1" bundle="$2" app="$3" suffix="$4" envs="$5" args=() kv
    [[ -d "$app" ]] || { echo "missing $app" >&2; return; }
    xcrun simctl terminate "$UDID" "$bundle" > /dev/null 2>&1 || true
    xcrun simctl install "$UDID" "$app"
    for kv in $envs FENTON_SYSTEM_SETTINGS=none FENTON_SKIP_INTRO=1 FENTON_UITEST_RESET=1; do args+=("SIMCTL_CHILD_$kv"); done
    if [[ " $envs " == *" LIVE=1 "* ]]; then
      # A live surface signs in with the owner's token, loaded in-process (tools/hass_creds.sh); it is never written to a file.
      if [[ -z "${FENTON_HASS_TOKEN:-}" ]]; then source "$ROOT/tools/hass_creds.sh"; hass_load_creds || { echo "no Home Assistant credentials" >&2; return; }; fi
      args+=("SIMCTL_CHILD_FENTON_HASS_TOKEN=$FENTON_HASS_TOKEN")
      [[ -n "${FENTON_HASS_SERVER:-}" ]] && args+=("SIMCTL_CHILD_FENTON_HASS_SERVER=$FENTON_HASS_SERVER")
    fi
    # UK_RECORD=1 records the inner display to DIR/<name>.mov for the length of the wait (frames: see the uikit-port notes).
    local rec=""
    if [[ "${UK_RECORD:-0}" == 1 ]]; then
      xcrun simctl io "$UDID" recordVideo --display=primary-1 --codec=h264 --force "$OUT/$name-$suffix.mov" > /dev/null 2>&1 &
      rec=$!
    fi
    env "${args[@]}" xcrun simctl launch "$UDID" "$bundle" > /dev/null
    sleep "$WAIT"
    if [[ -n "$rec" ]]; then kill -INT "$rec" 2>/dev/null || true; wait "$rec" 2>/dev/null || true; fi
    if [[ $FAMILY == duo ]]; then
      xcrun simctl io "$UDID" screenshot --display=primary "$OUT/$name-$suffix.png" > /dev/null 2>&1 || true
      xcrun simctl io "$UDID" screenshot --display=primary-1 "$OUT/$name-$suffix-inner.png" > /dev/null 2>&1 || true
    else
      xcrun simctl io "$UDID" screenshot "$OUT/$name-$suffix.png" > /dev/null 2>&1
    fi
    xcrun simctl terminate "$UDID" "$bundle" > /dev/null 2>&1 || true
    echo "shot: $name ($suffix)"
  }
  while IFS='|' read -r NAME ENVS; do
    [[ -z "$NAME" || "$NAME" == \#* || "$NAME" == \[* ]] && continue
    SAFE=$(echo "$NAME" | tr -c 'A-Za-z0-9._-' '-')
    shoot "$SAFE" com.sfenton.home "$UIKIT_APP" uikit "$ENVS"
  done < "$SURFACES"
  exit 0
fi

case "$FAMILY" in
  iphone) NAME="${FENTON_SIM_IPHONE:-iPhone 17 Pro}" ;;
  duo) NAME="${FENTON_SIM_DUO:-iPhone Duo (HASS)}" ;;
  ipad) NAME="${FENTON_SIM_IPAD:-iPad Pro 11-inch (M5)}" ;;
  *) echo "family must be iphone, duo or ipad" >&2; exit 2 ;;
esac
SIM="$(python3 "$ROOT/tools/devcap.py" pick-sim --name "$NAME" --pool "${FENTON_SIM_POOL:-0}")"
exec python3 "$ROOT/tools/devcap.py" run --sim "$SIM" --hold 1800 --shutdown-on-timeout --purpose "shots $FAMILY" -- \
  "$0" --inner "$SIM" --family "$FAMILY" --surfaces "$SURFACES" --out "$OUT" --apps "$APPS" --wait "$WAIT"
