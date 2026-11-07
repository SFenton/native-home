#!/usr/bin/env bash
# Fast pre-check for a feature lane: typechecks the lane's own UIKit port folders against the last merged build of HassUI
# (`@testable import`), in seconds, without waiting for a devcap build slot. It is a light single-process typecheck, not a
# build: always confirm with tools/uikit_build.sh before shots or journeys. Symbols added to shared files on your branch
# after the merged build (a Design component you extended) can show as false errors; the real build is the judge.
#   tools/uikit_typecheck.sh DIR [DIR ...]     (dirs relative to apple/Sources/HassUI/UIKitPort, e.g. Features/Chores Gallery/UKChoresGallery.swift)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
PORT=/Users/stephenfenton/repos/Fenton-HASS-Native/.claude/worktrees/uikit-port
P="$PORT/apple/build/dd-FentonHome/Build/Products/Debug-iphonesimulator"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/uikit-tc.XXXXXX")
i=0
for d in "$@"; do
  while IFS= read -r f; do
    i=$((i+1))
    { echo '@testable import HassUI'; echo 'import HassCore'; echo 'import HassDesign'; cat "$f"; } > "$OUT/$(printf %03d $i)_$(basename "$f")"
  done < <(find "$ROOT/apple/Sources/HassUI/UIKitPort/$d" -name '*.swift' | sort)
done
cd "$OUT"
xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios17.0-simulator -I "$P" -F "$P" -DDEBUG -Onone -swift-version 6 ./*.swift 2>&1 \
  | grep -E "error:|warning:" | sed "s|$OUT/[0-9]*_||" | sort -u | head -80
rm -rf "$OUT"
