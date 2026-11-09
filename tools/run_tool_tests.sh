#!/usr/bin/env bash
# Runs the Python tool tests, one test directory per interpreter so module names cannot clash (CI runs this in
# pr-checks; run it yourself after touching anything under tools/). Exit 1 when any directory fails.
#
#   tools/run_tool_tests.sh [PART ...]   PART is core (tools/tests), triage (tools/triage/tests) or release (tools/release/tests);
#                                        no PART runs all three, in that order. The hosted workflows run one job per part.
#   tools/run_tool_tests.sh --list       print the part names
set -uo pipefail
cd "$(dirname "$0")/.."

PARTS=(core triage release)

run_part() {
  case "$1" in
    core) python3 -m unittest discover -s tools/tests ;;
    triage) python3 -m unittest discover -s tools/triage/tests ;;
    release) python3 -m unittest tools.release.tests.test_versioning tools.release.tests.test_testflight tools.release.tests.test_testflight_queue tools.release.tests.test_release_workflows ;;
    *) echo "run_tool_tests: unknown part '$1' (core, triage or release)" >&2; return 2 ;;
  esac
}

if [[ "${1:-}" == "--list" ]]; then printf '%s\n' "${PARTS[@]}"; exit 0; fi
STATUS=0
if [[ $# -eq 0 ]]; then set -- "${PARTS[@]}"; fi  # macOS bash 3.2: no "${@:-${ARRAY[@]}}"
for part in "$@"; do
  run_part "$part" || STATUS=1
done
exit $STATUS
