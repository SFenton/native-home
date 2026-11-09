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
# simslim missing or failed, or a step hit its wall (callers that only want the best effort ignore it; ci_macos.sh records it),
# 4 slimmed but the post-check could not confirm it (hosted path only).
# Hosted path (FENTON_CI_HOSTED=1): the simulator should be SHUT DOWN (ci_release_sims.sh does it). No verify and no boot of our own:
# a stock first boot is the load storm (load 6 to 556 on the Duo and iPhone), and `simslim on` on a shut-down simulator boots it,
# persists the disables and reboots it slim at once, which cuts the storm short. It runs under SIMSLIM_BOOT_TIMEOUT (8m) and
# SIMSLIM_SPAWN_TIMEOUT (4m), with our wall (FENTON_SLIM_HOSTED_WALL, 600 s) a margin above so simslim fails cleanly first. No
# --preserve-boot-state: the device is left booted and slim (one boot saved; sim_settle.sh treats an already-booted device as fine).
# An already-booted simulator (the journey runner's second call) is only verified. Both flags and env vars exist in simslim 0.14.0.
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
  iphone | duo | ipad)
    # The one family -> UDID lookup (tools/sim_pool.sh), shared with sim_settle.sh and the journey runner: slim, settle and the tests
    # land on the same simulator even when the image has one device of a name per runtime.
    source "$ROOT/tools/sim_pool.sh"
    family="$UDID"; family_name="$(sim_pool_hosted_name "$family")"
    UDID="$(sim_pool_family_udid "$family")"
    [[ -n "$UDID" ]] || { echo "sim_slim: no simulator named $family_name" >&2; exit 1; }
    ;;
esac
command -v simslim > /dev/null || { echo "sim_slim: simslim not installed (brew install mobai-app/tap/simslim); leaving $UDID stock" >&2; exit 3; }

BOOT_WALL="${FENTON_HEALTH_BOOT_WALL:-120}"; SLIM_WALL="${FENTON_SLIM_WALL:-180}"; ON_WALL="${FENTON_SLIM_ON_WALL:-300}"
# wd WALL LABEL CMD...: run CMD under an xc_watch wall, output dropped; a wall hit (124) leaves the simulator stock and exits 3.
wd() {
  local wall="$1" label="$2" rc=0; shift 2
  python3 "$ROOT/tools/xc_watch.py" --wall "$wall" --label "$label" -- "$@" > /dev/null 2>&1 || rc=$?
  [[ $rc == 124 ]] && { echo "sim_slim: $label on $UDID hit the ${wall}s wall; leaving it stock" >&2; exit 3; }
  return $rc
}
if [[ "${FENTON_CI_HOSTED:-}" == 1 ]]; then
  state="$(xcrun simctl list devices -j | jq -r --arg u "$UDID" '[.devices[][] | select(.udid == $u)][0].state // empty')"
  name="$(basename "$PROFILE")"
  if [[ "$state" == Booted ]] && wd "$SLIM_WALL" "simslim verify" simslim verify "$UDID" --profile "$PROFILE"; then
    echo "sim_slim: $UDID already slim ($name)"; exit 0
  fi
  export SIMSLIM_BOOT_TIMEOUT="${SIMSLIM_BOOT_TIMEOUT:-8m}" SIMSLIM_SPAWN_TIMEOUT="${SIMSLIM_SPAWN_TIMEOUT:-4m}"
  echo "sim_slim: slimming $UDID ($name, hosted: simslim on from $state)"
  wd "${FENTON_SLIM_HOSTED_WALL:-600}" "simslim on" simslim on "$UDID" --profile "$PROFILE" || { echo "sim_slim: simslim on failed for $UDID; continuing stock" >&2; exit 3; }
  check_rc=0
  python3 "$ROOT/tools/xc_watch.py" --wall "${FENTON_SLIM_CHECK_WALL:-60}" --label "simslim verify (post-check)" -- simslim verify "$UDID" --profile "$PROFILE" > /dev/null 2>&1 || check_rc=$?
  [[ $check_rc == 0 ]] && exit 0
  echo "sim_slim: $UDID slimmed but the post-check did not confirm it (exit $check_rc)" >&2; exit 4
fi
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
