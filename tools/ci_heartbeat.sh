#!/usr/bin/env bash
# Heartbeat for a hosted macOS runner: one line of load, memory pressure, swap, free pages, disk and the top RSS processes,
# so a runner that dies ("lost communication") still leaves its last state in the live step log. The after-failure steps do not
# run on a lost VM; stdout streamed from inside the step is the evidence (build/research/duo-hosted-ci.md).
#
#   tools/ci_heartbeat.sh once                      print one heartbeat
#   tools/ci_heartbeat.sh run [-i SECONDS] -- CMD   run CMD with a heartbeat every SECONDS (default 15) in the background,
#                                                   killed when CMD ends; exits with CMD's status
# Process names only (no arguments), so no paths or values leak into the log.
set -uo pipefail

beat() {
  local load mp swap free top3
  load="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | xargs)"
  mp="$(memory_pressure 2>/dev/null | grep -i 'free percentage' | grep -o '[0-9]*%' | head -1)"
  swap="$(sysctl -n vm.swapusage 2>/dev/null | sed -E 's/  +/ /g' | cut -c1-80)"
  free="$(vm_stat 2>/dev/null | grep -E 'Pages (free|active|inactive|wired|occupied by compressor)' | sed -E 's/Pages //; s/\.$//; s/ +/ /g' | tr '\n' ';')"
  top3="$(ps -Aco rss=,comm= 2>/dev/null | sort -rn | head -3 | awk '{ $1=""; sub(/^ /,""); print }' | tr '\n' ',')"
  echo "heartbeat $(date -u +%H:%M:%S) load[$load] memfree[${mp:-?}] swap[$swap] vm[$free] disk[$(df -h / | awk 'NR==2 {print $4}') free] top[$top3]"
}

case "${1:-}" in
  once) beat ;;
  run)
    shift
    interval=15
    if [[ "${1:-}" == "-i" ]]; then interval="$2"; shift 2; fi
    [[ "${1:-}" == "--" ]] && shift
    [[ $# -gt 0 ]] || { echo "ci_heartbeat: run needs a command" >&2; exit 2; }
    ( while true; do beat; sleep "$interval"; done ) &
    hb=$!
    trap 'kill "$hb" 2>/dev/null' EXIT
    "$@"
    rc=$?
    kill "$hb" 2>/dev/null; wait "$hb" 2>/dev/null
    trap - EXIT
    exit $rc ;;
  *) echo "usage: ci_heartbeat.sh once | run [-i SECONDS] -- CMD" >&2; exit 2 ;;
esac
