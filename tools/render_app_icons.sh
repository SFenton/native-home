#!/usr/bin/env bash
# Renders the app icons (default plus seven alternates, each in light, dark and tinted) into the asset catalog.
#
# The art is `AppIconArtwork` (apple/Sources/HassDesign) over the colour table in `AppIconChoice` (apple/Sources/HassCore):
# the same view the Settings -> App Icon picker draws. This compiles them with the renderer in apple/Design/AppIcon and
# writes `<name>.appiconset/{light,dark,tinted}.png` plus `Contents.json` under apple/Apps/iOS/Assets.xcassets.
# Deterministic: rerunning produces identical files. macOS only (SwiftUI `ImageRenderer`), no extra packages.
#
# The PNGs are then recompressed losslessly with Xcode's `pngcrush` (`-rem allb -reduce`: drops ancillary chunks, takes
# the smallest lossless colour type, so the greyscale tinted icons become 8-bit grey; about a third smaller, same
# pixels); skipped with a note when `xcrun --find pngcrush` finds none. Never `-iphone`, which writes Apple's CgBI format.
#
# Usage: tools/render_app_icons.sh [contact-sheet.png]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES="$ROOT/apple/Sources"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/render_app_icons.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT

xcrun swiftc -parse-as-library -O -swift-version 6 \
  -o "$BUILD/render_app_icons" \
  "$ROOT/apple/Design/AppIcon/AppIconRenderer.swift" \
  "$SOURCES/HassCore/Settings/AppIconChoice.swift" \
  "$SOURCES/HassDesign/AppIconArtwork.swift" \
  "$SOURCES/HassDesign/Color+RGB.swift"
"$BUILD/render_app_icons" "$ROOT/apple/Apps/iOS/Assets.xcassets" "$@"

CATALOG="$ROOT/apple/Apps/iOS/Assets.xcassets"
if PNGCRUSH="$(xcrun --find pngcrush 2>/dev/null)"; then
  for png in "$CATALOG"/AppIcon*.appiconset/*.png; do
    "$PNGCRUSH" -q -rem allb -reduce "$png" "$BUILD/crushed.png" && mv "$BUILD/crushed.png" "$png"
  done
  echo "recompressed icon PNGs losslessly with pngcrush"
else
  echo "pngcrush not found: icon PNGs left as rendered"
fi
