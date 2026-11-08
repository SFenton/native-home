#!/usr/bin/env bash
# Boots a family's simulator on a hosted runner and waits for the first-boot load storm to settle, before the health check.
# A Duo's first boot holds a 3-vCPU / 7 GB runner at load 300 to 550 for 10 to 20 minutes (build/research/duo-hosted-ci.md).
# Settled: 1-minute load under 30, or under 60 and below half the 5-minute load. Polls every 30 s, caps the wait at 15 min,
# then returns 0 anyway so the existing health check decides. iPhone and iPad are settled on the first poll.
#
#   tools/sim_settle.sh FAMILY            boot the family's simulator and wait (iphone|duo|ipad)
#   tools/sim_settle.sh --decide L1 L5    exit 0 when load L1 (1 min) and L5 (5 min) count as settled, else 1
# Env: FENTON_SETTLE_CAP (seconds, default 900), FENTON_SETTLE_POLL (seconds, default 30).
set -uo pipefail

settled() {  # l1 l5
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < 30 || (a < 60 && a < b / 2)) }'
}

if [[ "${1:-}" == "--decide" ]]; then settled "$2" "$3"; exit $?; fi

family="${1:-}"
case "$family" in
  iphone) name="${FENTON_SIM_IPHONE:-iPhone 17}" ;;
  duo) name="${FENTON_SIM_DUO:-iPhone Duo}" ;;
  ipad) name="${FENTON_SIM_IPAD:-iPad Pro 11-inch (M5)}" ;;
  *) echo "usage: sim_settle.sh iphone|duo|ipad | --decide L1 L5" >&2; exit 2 ;;
esac
udid="$(xcrun simctl list devices available -j | jq -r --arg n "$name" '[.devices[][] | select(.name == $n)][0].udid // empty')"
[[ -n "$udid" ]] || { echo "settle: no simulator named $name"; xcrun simctl list devices; exit 1; }

cap="${FENTON_SETTLE_CAP:-900}"; poll="${FENTON_SETTLE_POLL:-30}"
echo "settle: booting the $family simulator"
xcrun simctl boot "$udid" 2>&1 | tail -1 || true
start=$SECONDS
while true; do
  read -r l1 l5 _ < <(sysctl -n vm.loadavg | tr -d '{}')
  mp="$(memory_pressure 2>/dev/null | grep -i 'free percentage' | head -1 | xargs)"
  echo "settle: $((SECONDS - start))s load1=$l1 load5=$l5 ${mp:-memory_pressure unavailable}"
  if settled "${l1:-0}" "${l5:-0}"; then echo "settle: settled after $((SECONDS - start))s"; exit 0; fi
  if (( SECONDS - start >= cap )); then echo "settle: gave up after ${cap}s; the health check decides"; exit 0; fi
  sleep "$poll"
done
