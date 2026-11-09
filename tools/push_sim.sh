#!/usr/bin/env bash
# Host side of PushJourneyTests: answers the journey's requests in a capture folder until stopped.
#   send-<fixture>.ready  ->  xcrun simctl push <udid> com.sfenton.home tools/push_fixtures/<fixture>.apns, then send-<fixture>.done
#   <name>.ready          ->  xcrun simctl io <udid> screenshot <folder>/<name>.png, then <name>.done
# Run it next to tools/ios_uitest.sh with the same folder in TEST_RUNNER_FENTON_CAPTURE_DIR, and only on a
# simulator your own devcap hold owns. Usage: tools/push_sim.sh <udid> <folder>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="$1"; DIR="$2"
mkdir -p "$DIR"
while true; do
  for ready in "$DIR"/*.ready; do
    [[ -e "$ready" ]] || continue
    name="$(basename "$ready" .ready)"
    [[ -e "$DIR/$name.done" ]] && continue
    if [[ "$name" == send-* ]]; then
      xcrun simctl push "$UDID" com.sfenton.home "$ROOT/tools/push_fixtures/${name#send-}.apns" >/dev/null 2>>"$DIR/push_sim.log" || true
    else
      xcrun simctl io "$UDID" screenshot "$DIR/$name.png" >/dev/null 2>>"$DIR/push_sim.log" || true
    fi
    touch "$DIR/$name.done"
  done
  sleep 0.3
done
