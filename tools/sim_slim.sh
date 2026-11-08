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
# simslim is a warning, not a failure: the run goes ahead on a stock simulator. FENTON_REQUIRE_SIMSLIM=1 (the hosted parallel-slim
# layout, tools/ci_hosted_setup.sh) turns every one of those quiet fallbacks into a failure with simslim's own output printed: a
# measurement of the slim layout on stock simulators would be a wrong number.
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
REQUIRE=0; [[ "${FENTON_REQUIRE_SIMSLIM:-0}" == 1 ]] && REQUIRE=1
# fallback MESSAGE: stock-simulator fallback, or a failure when simslim is required.
fallback() {
  if [[ $REQUIRE == 1 ]]; then echo "sim_slim: $1 (FENTON_REQUIRE_SIMSLIM=1: failing)" >&2; exit 1; fi
  echo "sim_slim: $1; continuing stock" >&2; exit 0
}
[[ -n "$UDID" ]] || { echo "usage: sim_slim.sh [--lean] [--profile FILE] UDID" >&2; exit 2; }
[[ "${FENTON_SIM_SLIM:-1}" == 0 ]] && { echo "sim_slim: FENTON_SIM_SLIM=0, leaving $UDID stock"; exit 0; }
command -v simslim > /dev/null || fallback "simslim not installed (brew install mobai-app/tap/simslim) for $UDID"

xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || { echo "sim_slim: $UDID would not boot" >&2; exit 1; }
name="$(basename "$PROFILE")"
if simslim verify "$UDID" --profile "$PROFILE" > /dev/null 2>&1; then
  echo "sim_slim: $UDID already slim ($name)"
else
  echo "sim_slim: slimming $UDID ($name)"
  # No-reboot only moves toward more-disabled; a daemon the profile wants back on (ui.json after ui-lean.json) needs `on`.
  simslim on "$UDID" --no-reboot --profile "$PROFILE" > /dev/null 2>&1 || true
  if ! simslim verify "$UDID" --profile "$PROFILE" > /dev/null 2>&1; then
    on_out="$(simslim on "$UDID" --profile "$PROFILE" 2>&1)" || { [[ $REQUIRE == 1 ]] && echo "$on_out" | tail -20 >&2; fallback "simslim on failed for $UDID"; }
    xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
    if [[ $REQUIRE == 1 ]] && ! simslim verify "$UDID" --profile "$PROFILE" > /dev/null 2>&1; then
      simslim verify "$UDID" --profile "$PROFILE" 2>&1 | tail -20 >&2
      fallback "$UDID is not slim after simslim on"
    fi
  fi
fi
simslim doctor "$UDID" --requires push > /dev/null || { [[ $REQUIRE == 1 ]] && fallback "doctor reports push broken on $UDID"; echo "sim_slim: doctor reports push broken on $UDID" >&2; }
exit 0
