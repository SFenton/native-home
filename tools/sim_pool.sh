#!/usr/bin/env bash
# Shared simulator-pool lookups for the tools/*.sh wrappers (source it; it defines functions only).
#   sim_pool_list      the available devices (`xcrun simctl list devices available`); FENTON_SIM_LIST_FILE replaces it (tool tests).
#                      Returns non-zero, with the error on stderr, when the list command itself fails.
#   sim_pool_has NAME  (list on stdin) 0 when a device is named exactly NAME followed by its UDID. "NAME (pool 2)" clones and
#                      siblings such as "NAME (Rooms)" do not count: they only exist because the base does.
#   sim_pool_udid NAME (list on stdin) the UDID of the first device named exactly NAME.
sim_pool_list() {
  if [[ -n "${FENTON_SIM_LIST_FILE:-}" ]]; then cat "$FENTON_SIM_LIST_FILE"; else xcrun simctl list devices available; fi
}
sim_pool_udid() {
  NAME="$1" awk '{ line = $0; sub(/^ +/, "", line); if (match(line, / \([0-9A-F-]{36}\)/) && substr(line, 1, RSTART - 1) == ENVIRON["NAME"]) { print substr(line, RSTART + 2, 36); exit } }'
}
sim_pool_has() {
  [[ -n "$(sim_pool_udid "$1")" ]]
}
