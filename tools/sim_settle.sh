#!/usr/bin/env bash
# Boots a family's simulator on a hosted runner and waits for the first-boot load storm to settle, before the health check.
# A Duo's first boot holds a 3-vCPU / 7 GB runner at load 300 to 550 for 10 to 20 minutes (build/research/duo-hosted-ci.md).
# Settled: 1-minute load under 30, or under 60 and below half the 5-minute load. Polls every 30 s, caps the wait at 15 min,
# then returns 0 anyway so the existing health check decides. iPhone and iPad are settled on the first poll.
#
#   tools/sim_settle.sh FAMILY            boot the family's simulator and wait (iphone|duo|ipad)
#   tools/sim_settle.sh --decide L1 L5    exit 0 when load L1 (1 min) and L5 (5 min) count as settled, else 1
# Boot and bootstatus run under xc_watch walls (FENTON_HEALTH_BOOT_WALL); no decision before FENTON_SETTLE_DWELL seconds (default 90 Duo, 15
# others) and two settled polls in a row. Env: FENTON_SETTLE_CAP (default 900), FENTON_SETTLE_POLL (default 30), FENTON_SETTLE_UDID (tests).
set -uo pipefail

settled() {  # l1 l5
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < 30 || (a < 60 && a < b / 2)) }'
}

if [[ "${1:-}" == "--decide" ]]; then settled "$2" "$3"; exit $?; fi

family="${1:-}"
case "$family" in
  iphone|duo|ipad) ;;
  *) echo "usage: sim_settle.sh iphone|duo|ipad | --decide L1 L5" >&2; exit 2 ;;
esac
# The same lookup the journey runner uses for the test destination (tools/sim_pool.sh), so the warmed simulator is the tested one even
# when the image has several devices of one name (a first-listed jq pick differed for the Duo: hosted runs 42643045285 and 42654943087).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sim_pool.sh"
name="$(sim_pool_hosted_name "$family")"
udid="${FENTON_SETTLE_UDID:-$(sim_pool_family_udid "$family")}"
[[ -n "$udid" ]] || { echo "settle: no simulator named $name"; sim_pool_list; exit 1; }

cap="${FENTON_SETTLE_CAP:-900}"; poll="${FENTON_SETTLE_POLL:-30}"
# The 1-minute load average lags: right after `simctl boot` it still shows the state before the boot, so no decision is made before a
# minimum dwell (the Duo's storm needs minutes to show; an iPhone or iPad warms in about 90 s and is cheap) and two settled polls in a row.
case "$family" in duo) dwell_default=90 ;; *) dwell_default=15 ;; esac
dwell="${FENTON_SETTLE_DWELL:-$dwell_default}"
wall="${FENTON_HEALTH_BOOT_WALL:-120}"
watch=(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xc_watch.py" --wall "$wall")

echo "settle: booting the $family simulator $udid (wall ${wall}s)"
"${watch[@]}" --label "simctl boot" -- xcrun simctl boot "$udid" 2>&1 | tail -2
# An already-booted simulator makes `boot` fail harmlessly; bootstatus -b decides whether it is usable.
if ! "${watch[@]}" --label "simctl bootstatus" -- xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1; then
  echo "settle: boot failed or timed out after ${wall}s; the health check will retry"; exit 1
fi
start=$SECONDS; good=0
echo "settle: booted; dwelling ${dwell}s before the first decision"
while true; do
  read -r l1 l5 _ < <(sysctl -n vm.loadavg | tr -d '{}')
  mp="$(memory_pressure 2>/dev/null | grep -i 'free percentage' | head -1 | xargs)"
  elapsed=$((SECONDS - start))
  if settled "${l1:-0}" "${l5:-0}"; then good=$((good + 1)); else good=0; fi
  echo "settle: ${elapsed}s load1=$l1 load5=$l5 settled-polls=$good ${mp:-memory_pressure unavailable}"
  if (( elapsed >= dwell && good >= 2 )); then echo "settle: settled after ${elapsed}s"; exit 0; fi
  if (( elapsed >= cap )); then echo "settle: gave up after ${cap}s; the health check decides"; exit 0; fi
  sleep "$poll"
done
