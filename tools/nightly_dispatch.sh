#!/usr/bin/env bash
# Starts the nightly full run: launchd runs this at 02:00 local time (tools/nightly_install.sh).
#   1. Stops when the kill file ~/.config/fenton-hass/NO_NIGHTLY exists (the owner's switch; delete it to resume).
#   2. Reaps stale devcap holds and simulators nobody holds.
#   3. `caffeinate -i gh workflow run nightly.yml --ref main`, then keeps the Mac awake until the run ends.
# Waking the Mac for 02:00 needs `sudo pmset repeat wakeorpoweron MTWRFSU 01:55:00` (the owner runs it once).
# Environment: HASS_NIGHTLY_KILL_FILE (default ~/.config/fenton-hass/NO_NIGHTLY), HASS_NIGHTLY_REPO, HASS_NIGHTLY_WATCH=0 to skip the wait.
set -uo pipefail
export PATH="${PATH:-/usr/bin:/bin}:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${HASS_NIGHTLY_REPO:-SFenton/native-home}"
KILL="${HASS_NIGHTLY_KILL_FILE:-$HOME/.config/fenton-hass/NO_NIGHTLY}"

stamp() { date '+%Y-%m-%d %H:%M:%S'; }

if [[ -e "$KILL" ]]; then
  echo "$(stamp) nightly: paused by $KILL; not dispatching"
  exit 0
fi

python3 "$ROOT/tools/devcap.py" reap >/dev/null 2>&1 || true

echo "$(stamp) nightly: dispatching nightly.yml on main in $REPO"
if ! caffeinate -i gh workflow run nightly.yml --repo "$REPO" --ref main; then
  echo "$(stamp) nightly: dispatch failed"
  exit 1
fi

[[ "${HASS_NIGHTLY_WATCH:-1}" == 0 ]] && exit 0
sleep 20
run_id="$(gh run list --repo "$REPO" --workflow nightly.yml --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
if [[ -n "$run_id" ]]; then
  echo "$(stamp) nightly: holding the Mac awake until run $run_id ends"
  caffeinate -i gh run watch "$run_id" --repo "$REPO" --exit-status >/dev/null 2>&1 || true
  echo "$(stamp) nightly: run $run_id ended"
fi
