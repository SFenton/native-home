#!/usr/bin/env bash
# Slim a simulator (simslim: disables the ~170 background daemons a UI test does not need, ~4x less RAM per
# simulator) so more lanes fit in the devcap `simulator` slots. Run it INSIDE the devcap hold for that UDID,
# before xcodebuild. Idempotent: a simulator already in the profile costs one `simslim verify`.
#
#   tools/sim_slim.sh [--lean] [--profile FILE] UDID
#
#   default   tools/simslim/ui.json: keeps push, Photos, App Intents and widgets / Live Activities
#   --lean    tools/simslim/ui-lean.json: also drops widgets / Live Activities (~675 MB more). Only for runs that
#             touch no LiveActivity, Widget or Push journey; switching back to ui.json later costs one reboot
#
# FENTON_SIM_SLIM=0 skips slimming (stock simulator, for A/B perf runs); FENTON_SIM_LEAN=1 means --lean. A missing
# simslim is a warning, not a failure: the run goes ahead on a stock simulator. The hosted macOS job installs the pinned simslim
# (tools/ci_hosted_setup.sh) and slims each simulator in turn (trial, build/decisions/native-home-ci-simslim.md); FENTON_SIM_SLIM=0 turns it off there too.
# UDID may also be a family (iphone|duo|ipad), resolved to the simulator ios_uitest.sh and sim_settle.sh use.
# Exit codes: 0 slimmed (already or now), 1 hard failure (no such simulator, would not boot), 3 LEFT STOCK on purpose: FENTON_SIM_SLIM=0,
# simslim missing or failed, or a step hit its wall (callers that only want the best effort ignore it; ci_macos.sh records it).
# Walls (xc_watch, seconds): FENTON_HEALTH_BOOT_WALL boots (120), FENTON_SLIM_WALL verify / no-reboot on / doctor (180),
# FENTON_SLIM_ON_WALL the rebooting `simslim on` (300). A wall hit leaves the simulator stock.
# See .agents/platforms/apple/capacity.md.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$ROOT/tools/simslim/ui.json"; UDID=""
[[ "${FENTON_SIM_LEAN:-0}" == 1 ]] && PROFILE="$ROOT/tools/simslim/ui-lean.json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lean) PROFILE="$ROOT/tools/simslim/ui-lean.json" ;;
    --profile) PROFILE="$2"; shift ;;
    *) UDID="$1" ;;
  esac
  shift
done
[[ -n "$UDID" ]] || { echo "usage: sim_slim.sh [--lean] [--profile FILE] UDID" >&2; exit 2; }
[[ "${FENTON_SIM_SLIM:-1}" == 0 ]] && { echo "sim_slim: FENTON_SIM_SLIM=0, leaving $UDID stock"; exit 3; }
case "$UDID" in
  iphone) family_name="${FENTON_SIM_IPHONE:-iPhone 17}" ;;
  duo) family_name="${FENTON_SIM_DUO:-iPhone Duo}" ;;
  ipad) family_name="${FENTON_SIM_IPAD:-iPad Pro 11-inch (M5)}" ;;
  *) family_name="" ;;
esac
if [[ -n "$family_name" ]]; then
  UDID="$(xcrun simctl list devices available -j | jq -r --arg n "$family_name" '[.devices[][] | select(.name == $n)][0].udid // empty')"
  [[ -n "$UDID" ]] || { echo "sim_slim: no simulator named $family_name" >&2; exit 1; }
fi
command -v simslim > /dev/null || { echo "sim_slim: simslim not installed (brew install mobai-app/tap/simslim); leaving $UDID stock" >&2; exit 3; }

BOOT_WALL="${FENTON_HEALTH_BOOT_WALL:-120}"; SLIM_WALL="${FENTON_SLIM_WALL:-180}"; ON_WALL="${FENTON_SLIM_ON_WALL:-300}"
# wd WALL LABEL CMD...: run CMD under an xc_watch wall, output dropped; a wall hit (124) leaves the simulator stock and exits 3.
wd() {
  local wall="$1" label="$2" rc=0; shift 2
  python3 "$ROOT/tools/xc_watch.py" --wall "$wall" --label "$label" -- "$@" > /dev/null 2>&1 || rc=$?
  [[ $rc == 124 ]] && { echo "sim_slim: $label on $UDID hit the ${wall}s wall; leaving it stock" >&2; exit 3; }
  return $rc
}
# The first boot: any failure but the wall is an error (settle and the health check do their own boot handling after a wall).
wd "$BOOT_WALL" "simctl bootstatus" xcrun simctl bootstatus "$UDID" -b || { echo "sim_slim: $UDID would not boot" >&2; exit 1; }
name="$(basename "$PROFILE")"
if wd "$SLIM_WALL" "simslim verify" simslim verify "$UDID" --profile "$PROFILE"; then
  echo "sim_slim: $UDID already slim ($name)"
else
  echo "sim_slim: slimming $UDID ($name)"
  # No-reboot only moves toward more-disabled; a daemon the profile wants back on (ui.json after ui-lean.json) needs `on`.
  wd "$SLIM_WALL" "simslim on --no-reboot" simslim on "$UDID" --no-reboot --profile "$PROFILE" || true
  if ! wd "$SLIM_WALL" "simslim verify" simslim verify "$UDID" --profile "$PROFILE"; then
    wd "$ON_WALL" "simslim on" simslim on "$UDID" --profile "$PROFILE" || { echo "sim_slim: simslim on failed for $UDID; continuing stock" >&2; exit 3; }
    wd "$BOOT_WALL" "simctl bootstatus (after reboot)" xcrun simctl bootstatus "$UDID" -b || true
  fi
fi
wd "$SLIM_WALL" "simslim doctor" simslim doctor "$UDID" --requires push || echo "sim_slim: doctor reports push broken on $UDID" >&2
exit 0
