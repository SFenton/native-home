#!/usr/bin/env bash
# SwiftPM coverage gate: runs every package test bundle with LLVM coverage on the macOS host and requires 95% logic lines
# (the `logic` globs of contracts/coverage-rules.json: HassCore, HassTelemetry, FentonActivityModel, HassDemoHouse and the view-free HassUI files).
# Ported from FestivalNativeApps. View source (HassDesign, FentonActivityViews, the HassUI views) is classified `unmeasured`: its line
# coverage is not measured or gated (.agents/testing/apple/coverage.md). The UX tests, accessibility tests,
# hosted tests and journeys still run, under their own plans; nothing here starts a simulator.
#
# Usage: tools/apple_coverage.sh [--changed]
#   Default: every suite, every file: the nightly / release gate.
#   --changed: the per-PR gate. Runs `swift test --filter` for the suites the diff against the lane's base branch (tools/lane_base.py;
#   FENTON_AFFECTED_BASE overrides) affects (tools/affected_tests.py, contracts/test-map.json) and gates only the changed files the
#   rules class as `logic` (tools/coverage_gate.py --files; --baseline build/coverage-baseline.json when that file exists). A diff that
#   changes no logic file prints `== changed: no logic source changed; nothing to gate` after the suites ran and exits 0. A diff that
#   maps to no suite runs nothing; one that needs a targeted pick prints the request and exits 3.
# `swift test` runs under tools/xc_watch.py: 20 minutes without output (FENTON_COVERAGE_SILENCE) kills it (exit 125, INFRA: hung).
#   `--require-tests`: a `swift test` (or --filter) that runs no test is EMPTY: the script prints `EMPTY: no tests ran` and exits 1
#   before measuring coverage from nothing; FENTON_COV_ALLOW_EMPTY=1 accepts it.
#   Failure classification (tools/coverage_classify.py, A2 of the T-section-sides post-mortem): when host tests fail in the instrumented
#   run, only those ids rerun WITHOUT instrumentation (same hold).
#   The digest prints `coverage-only: <ids>` (passed plain), `real: <ids>` (failed both ways) and `timeout: yes|no` (a phase exited
#   124). The script exits non-zero for any `real` id and for a `coverage-only` id missing from apple/coverage-quarantine.json
#   (each entry: id, issue, date; the issue must be an open Workflow issue). The 95% bar never changes and quarantined tests count.
set -euo pipefail

# -h / --help prints the header above and exits; nothing else starts.
if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  sed -n '2,/^set -euo/{/^set -euo/!s/^# \{0,1\}//p;}' "$0"
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGED=0
[[ "${1:-}" == --changed ]] && CHANGED=1  # "$@" stays intact: the script re-runs itself inside the devcap hold
# Resolve the lane's base once (gh pr view is a network call); affected_tests and the base summary reuse it.
[[ $CHANGED == 1 ]] && export FENTON_AFFECTED_BASE="${FENTON_AFFECTED_BASE:-$(python3 "$ROOT/tools/lane_base.py" || true)}"
FILTER=()
CHANGED_SOURCES=()
if [[ $CHANGED == 1 ]]; then
  AFFECTED_STATUS=0
  FILTER=($(python3 "$ROOT/tools/affected_tests.py" --swift)) || AFFECTED_STATUS=$?
  if (( ${#FILTER[@]} == 0 )); then
    echo "== changed: no suite covers this diff; nothing to run"; exit "$AFFECTED_STATUS"
  fi
  # Only the changed files the rules class as `logic` are gated; `unmeasured` UX source never is.
  while IFS= read -r file; do
    [[ -n "$file" ]] && CHANGED_SOURCES+=("$file")
  done < <(python3 -c '
import json, sys
sys.path.insert(0, sys.argv[1])
import affected_tests, coverage_gate
rules = json.loads(coverage_gate.RULES.read_text(encoding="utf-8"))
categories, _, _ = coverage_gate.classify(coverage_gate.ROOT, rules, "swift")
logic = categories.get("logic", set())
print("\n".join(f for f in affected_tests.changed_files() if f in logic))' "$ROOT/tools")
  echo "== changed: swift test ${FILTER[*]}; gating ${#CHANGED_SOURCES[@]} changed logic source file(s)"
fi
# Every file under apple/Sources must be classified in contracts/coverage-rules.json. Check before taking a
# build slot, so a new module or file fails here by name instead of as missing coverage after the build.
python3 "$ROOT/tools/coverage_gate.py" --language swift --classify-only
# The motion rules (.agents/patterns/motion.md, "Lint"): no raw animation values, no navigation transitions, state colours animate.
"$ROOT/tools/lint_motion.sh"
# Failure classification state (tools/coverage_classify.py, tools/coverage_phases.sh): reset unless this process already belongs to the run
# whose id is in FENTON_COV_CLASS_RUN (the re-exec inside the hold inherits it; a nested build hold or a stale directory does not).
CLASS_DIR="$ROOT/apple/.build/coverage-class"
CLASSIFY="$ROOT/tools/coverage_classify.py"
# The library reads this only as a test seam (tools/tests/test_coverage_phases.py sets it after sourcing); a caller's environment must not reach it.
unset COV_CLASSIFY_ARGS
source "$ROOT/tools/coverage_phases.sh"
if [[ -z "${FENTON_COV_CLASS_RUN:-}" || "$(cat "$CLASS_DIR/run-id" 2>/dev/null || true)" != "$FENTON_COV_CLASS_RUN" ]]; then
  export FENTON_COV_CLASS_RUN="$$-$(date +%s)"
  cov_state_reset; echo "$FENTON_COV_CLASS_RUN" > "$CLASS_DIR/run-id"
fi
# Compile and test under a machine-wide `build` slot (tools/devcap.py), waiting when the Mac is full.
if [[ ",${DEVCAP_HELD:-}," != *",build,"* ]]; then
  DEVCAP_CMD=("$ROOT/tools/devcap.py")
  # hosted (a GitHub-hosted runner only): no hold, ci_hosted.py
  [[ "${FENTON_CI_HOSTED:-}" == 1 && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] && DEVCAP_CMD=("$ROOT/tools/ci_hosted.py" devcap)
  exec python3 "${DEVCAP_CMD[@]}" run --pool build --pool swift-test --hold "${FENTON_DEVCAP_HOLD:-3600}" \
    --purpose "Fenton coverage ($(basename "$ROOT"))" -- bash "$0" "$@"
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT/apple"
CODECOV_DIR="$(dirname "$(swift test --show-codecov-path)")"
# Merge this run's raw profiles ourselves: swift test skips its merge when a test fails, and a stale
# default.profdata would then be exported against new binaries.
rm -f "$CODECOV_DIR"/*.profraw "$CODECOV_DIR/default.profdata"
TEST_STATUS=0
mkdir -p "$ROOT/apple/.build"; rm -f "$ROOT/apple/.build/swifttest.tally"
REQUIRE=(--require-tests)
[[ "${FENTON_COV_ALLOW_EMPTY:-}" == 1 ]] && REQUIRE=()
cov_phase swift swift "$CLASS_DIR/swift-test.log" -- \
  python3 "$ROOT/tools/xc_watch.py" --silence "${FENTON_COVERAGE_SILENCE:-1200}" ${REQUIRE[@]+"${REQUIRE[@]}"} --tally "$ROOT/apple/.build/swifttest.tally" --label "swift test" -- \
  swift test --enable-code-coverage ${FILTER[@]+"${FILTER[@]}"}
TEST_STATUS=$COV_PHASE_STATUS
# Informational only (tools/lane_base.py): which failing tests the base commit already has. It never changes TEST_STATUS.
if [[ $CHANGED == 1 && $TEST_STATUS != 0 ]]; then python3 "$ROOT/tools/lane_base.py" baseline summary --command swift_test --log "$CLASS_DIR/swift-test.log" || true; fi
if (( TEST_STATUS == 1 )) && python3 "$ROOT/tools/uitest_support.py" tally-empty "$ROOT/apple/.build/swifttest.tally"; then
  echo "EMPTY: swift test ran no tests (selection matched nothing); no coverage was measured" >&2
  exit 1
fi
if (( TEST_STATUS == 125 )); then
  echo "ERROR: swift test hung and was killed; no coverage was measured" >&2
  exit 125
fi
shopt -s nullglob
PROFILES=("$CODECOV_DIR"/*.profraw)
if (( ${#PROFILES[@]} == 0 )); then
  echo "ERROR: swift test (exit $TEST_STATUS) wrote no coverage profiles to $CODECOV_DIR" >&2
  exit 1
fi
xcrun llvm-profdata merge -sparse "${PROFILES[@]}" -o "$CODECOV_DIR/default.profdata"

# swift test's own JSON export reads only one test binary, which drops HassDesign and HassUI. Export
# once against every test binary instead.
BIN_DIR="$(swift build --show-bin-path)"
OBJECTS=()
for bundle in "$BIN_DIR"/*Tests.xctest; do
  name="$(basename "$bundle" .xctest)"
  OBJECTS+=(${OBJECTS[@]+-object} "$bundle/Contents/MacOS/$name")
done
REPORT="$CODECOV_DIR/all-bundles.json"
xcrun llvm-cov export -format=text -instr-profile "$CODECOV_DIR/default.profdata" "${OBJECTS[@]}" > "$REPORT"
# Plain rerun of the failed host tests, after the export above: a build without coverage replaces the instrumented binaries,
# which the export needs. Only the failed ids run (swift test --filter, --require-tests), still inside this hold.
cov_rerun_swift
GATE_STATUS=0
if [[ $CHANGED == 1 ]]; then
  BASELINE=()
  [[ -f "$ROOT/build/coverage-baseline.json" ]] && BASELINE=(--baseline "$ROOT/build/coverage-baseline.json")
  if (( ${#CHANGED_SOURCES[@]} == 0 )); then
    echo "== changed: no logic source changed; nothing to gate"
  else
    python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$REPORT" --files "${CHANGED_SOURCES[@]}" ${BASELINE[@]+"${BASELINE[@]}"} || GATE_STATUS=$?
  fi
else
  python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$REPORT" || GATE_STATUS=$?
fi
# Failure classification (tools/coverage_classify.py): per phase, a non-zero exit with no named test, a timeout (124), 125, 126 or a signal
# fails the run whatever the quarantine says; named ids are real unless the plain rerun log shows them passed (and quarantined).
echo "== failure classification"
CLASS_STATUS=0
cov_verdict || CLASS_STATUS=$?
if (( CLASS_STATUS != 0 )); then
  echo "ERROR: the coverage run has real, unquarantined or unclassifiable test failures; coverage above is from a run with failing tests" >&2
  exit "$CLASS_STATUS"
fi
exit "$GATE_STATUS"
