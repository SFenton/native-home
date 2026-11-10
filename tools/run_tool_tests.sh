#!/usr/bin/env bash
# Runs the Python tool tests, one test directory per interpreter so module names cannot clash (CI runs this in
# pr-checks; run it yourself after touching anything under tools/). Exit 1 when any directory fails.
#
#   tools/run_tool_tests.sh [PART ...]   PART is core (tools/tests), triage (tools/triage/tests) or release (tools/release/tests);
#                                        no PART runs all three, in that order. The hosted workflows run one job per part.
#   tools/run_tool_tests.sh --list       print the part names
#   FENTON_TOOL_SHARD=I/N tools/run_tool_tests.sh core   run shard I (0-based) of N of the core modules (tools/ci_shard.py); the pr-checks matrix
#                                        sets it. Ignored by the other parts. Unset, core runs every module.
set -uo pipefail
cd "$(dirname "$0")/.."

PARTS=(core triage release)

# core: every tools/tests module, or one shard of them when FENTON_TOOL_SHARD=I/N (modules named by tools/ci_shard.py, imported as discover does).
run_core() {
  if [[ -z "${FENTON_TOOL_SHARD:-}" ]]; then python3 -m unittest discover -s tools/tests; return; fi
  if [[ ! "$FENTON_TOOL_SHARD" =~ ^[0-9]+/[0-9]+$ ]]; then echo "run_tool_tests: FENTON_TOOL_SHARD must be I/N, got '$FENTON_TOOL_SHARD'" >&2; return 2; fi
  local modules
  modules="$(python3 tools/ci_shard.py --shard "${FENTON_TOOL_SHARD%/*}" --of "${FENTON_TOOL_SHARD#*/}")" || return 2
  if [[ -z "$modules" ]]; then echo "run_tool_tests: shard $FENTON_TOOL_SHARD has no modules"; return 0; fi
  # shellcheck disable=SC2086  # one module name per word
  PYTHONPATH="tools/tests${PYTHONPATH:+:$PYTHONPATH}" python3 -m unittest $modules
}

run_part() {
  case "$1" in
    core) run_core ;;
    triage) python3 -m unittest discover -s tools/triage/tests ;;
    release) python3 -m unittest tools.release.tests.test_versioning tools.release.tests.test_testflight tools.release.tests.test_release_workflows ;;
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
