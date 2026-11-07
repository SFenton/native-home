#!/usr/bin/env bash
# Builds the official Home Assistant companion app (home-assistant/iOS) from source and installs it on iOS
# simulators, so native pages and modals can be compared with it side by side. It never signs in: the person
# signs in once per simulator in the app.
#
# Usage:
#   tools/ha_companion.sh build                     # clone or update, then build for the simulator
#   tools/ha_companion.sh install [--boot] SIM...   # install and launch on each simulator (name or UDID)
#
# Environment: HA_COMPANION_DIR (default ~/repos/home-assistant-iOS-upstream; never the owner's own checkout,
# ~/repos/home-assistant-iOS, which the case-insensitive disk also matches as -ios).
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DIR="${HA_COMPANION_DIR:-$HOME/repos/home-assistant-iOS-upstream}"
APP="$DIR/build/Build/Products/Debug-iphonesimulator/Home Assistant Δ.app"
BUNDLE_ID="io.robbie.HomeAssistant.dev"

udid_for() {
  # A UDID passes through; a name resolves to the first available simulator with exactly that name.
  if [[ "$1" =~ ^[0-9A-F-]{36}$ ]]; then echo "$1"; return; fi
  xcrun simctl list devices available | NAME="$1" awk '{ line = $0; sub(/^ +/, "", line); if (match(line, / \([0-9A-F-]{36}\)/) && substr(line, 1, RSTART - 1) == ENVIRON["NAME"]) { print substr(line, RSTART + 2, 36); exit } }'
}

build() {
  if [[ -d "$DIR/.git" ]]; then
    git -C "$DIR" pull --ff-only --depth 1
  else
    git clone --depth 1 https://github.com/home-assistant/iOS.git "$DIR"
  fi
  cd "$DIR"
  # The "Run SwiftGen" build phase builds these tool packages itself and can stall inside xcodebuild while it
  # fetches SwiftLint; building them first from the shell avoids that (seen 2026-10-13).
  Tools/build_tool swiftlint --version >/dev/null
  Tools/build_tool swiftgen --version >/dev/null
  Tools/build_tool swiftformat --version >/dev/null
  # Ad-hoc signing, not CODE_SIGNING_ALLOWED=NO: without entitlements the app-group container is missing and
  # the app traps at launch. No team, certificate or profile is needed.
  xcodebuild -project HomeAssistant.xcodeproj -scheme App-Debug -configuration Debug \
    -destination "generic/platform=iOS Simulator" -derivedDataPath "$DIR/build" \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build
  echo "Built $(git -C "$DIR" rev-parse --short HEAD): $APP"
}

install() {
  local boot=0
  [[ "${1:-}" == "--boot" ]] && { boot=1; shift; }
  [[ $# -gt 0 ]] || { echo "install: name at least one simulator" >&2; exit 2; }
  [[ -d "$APP" ]] || { echo "No build at $APP; run '$0 build' first" >&2; exit 1; }
  for sim in "$@"; do
    udid="$(udid_for "$sim")"
    [[ -n "$udid" ]] || { echo "GAP: no available simulator '$sim'"; continue; }
    if ! xcrun simctl list devices | grep -q "($udid) (Booted)"; then
      if [[ $boot == 1 ]]; then xcrun simctl boot "$udid"; xcrun simctl bootstatus "$udid" -b >/dev/null
      else echo "SKIP: '$sim' is not booted (pass --boot to boot it)"; continue; fi
    fi
    xcrun simctl install "$udid" "$APP"
    xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
    echo "Installed on $sim ($udid)"
  done
}

case "${1:-}" in
  build) build ;;
  install) shift; install "$@" ;;
  *) sed -n 2,11p "$0"; exit 2 ;;
esac
