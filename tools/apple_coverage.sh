#!/usr/bin/env bash
# SwiftPM coverage gate: runs every package test bundle with LLVM coverage on the macOS host and
# requires 95% logic (HassCore + HassTelemetry) / 95% UX (HassDesign + HassUI) lines. Ported from FestivalNativeApps.
#
# Usage: tools/apple_coverage.sh [--changed]
#   Default: every suite, every file: the nightly / release gate.
#   --changed: the per-PR gate. Runs `swift test --filter` for the suites the diff against the lane's base branch (tools/lane_base.py; FENTON_AFFECTED_BASE overrides) affects
#   (tools/affected_tests.py, contracts/test-map.json) and gates only the changed source files
#   (tools/coverage_gate.py --files; --baseline build/coverage-baseline.json when that file exists). A diff that
#   maps to no suite runs nothing; one that needs a targeted pick prints the request and exits 3.
# UX coverage of the UIKit app (apple/Sources/HassUI/UIKitPort, iOS-only: the Mac host cannot compile it) comes from the XCUITest
#   journeys: the Gate plan on iPhone against an instrumented app (`ios_uitest.sh --impact`, one profile per launch), merged with the
#   host report file by file (tools/coverage_ios.py; .agents/testing/apple/coverage.md). Under --changed the iOS phase runs only
#   when a changed file is in UIKitPort, with that diff's journeys.
#   The hosted unit tests (apple/Apps/iOSTests, FentonHomeTests) run first in the same instrumented app and add their profile; the
#   journeys then run in FENTON_COV_IOS_PARTS (default 4) class-filtered parts, each its own run and hold.
#   FENTON_COV_IOS=skip   Mac-host numbers only (UIKitPort then counts as 0: a diagnostic, never a certification)
#   FENTON_COV_IOS_PROFILES=DIR   reuse the *.profraw in DIR (and the products they came from) instead of running the journeys
# `swift test` runs under tools/xc_watch.py: 20 minutes without output (FENTON_COVERAGE_SILENCE) kills it (exit 125, INFRA: hung).
#   `--require-tests`: a `swift test` (or --filter) that runs no test is EMPTY: the script prints `EMPTY: no tests ran` and exits 1
#   before measuring coverage from nothing; FENTON_COV_ALLOW_EMPTY=1 accepts it. The iOS phase's ios_uitest.sh runs hold the same rule.
#   Failure classification (tools/coverage_classify.py, A2 of the T-section-sides post-mortem): when tests fail in the instrumented
#   run, only those ids rerun WITHOUT instrumentation (same holds: ios_uitest.sh takes its own, `swift test` runs inside this one).
#   The digest prints `coverage-only: <ids>` (passed plain), `real: <ids>` (failed both ways) and `timeout: yes|no` (a phase exited
#   124). The script exits non-zero for any `real` id and for a `coverage-only` id missing from apple/coverage-quarantine.json
#   (each entry: id, issue, date; the issue must be an open Workflow issue). The 95% bars never change and quarantined tests count.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGED=0
[[ "${1:-}" == --changed ]] && CHANGED=1  # "$@" stays intact: the script re-runs itself inside the devcap hold
# Resolve the lane's base once (gh pr view is a network call); affected_tests, the journeys and the summary all reuse it.
[[ $CHANGED == 1 ]] && export FENTON_AFFECTED_BASE="${FENTON_AFFECTED_BASE:-$(python3 "$ROOT/tools/lane_base.py" || true)}"
FILTER=()
CHANGED_SOURCES=()
if [[ $CHANGED == 1 ]]; then
  AFFECTED_STATUS=0
  FILTER=($(python3 "$ROOT/tools/affected_tests.py" --swift)) || AFFECTED_STATUS=$?
  if (( ${#FILTER[@]} == 0 )); then
    echo "== changed: no suite covers this diff; nothing to run"; exit "$AFFECTED_STATUS"
  fi
  while IFS= read -r file; do
    [[ "$file" == apple/Sources/*.swift ]] && CHANGED_SOURCES+=("$file")
  done < <(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import affected_tests; print("\n".join(affected_tests.changed_files()))' "$ROOT/tools")
  echo "== changed: swift test ${FILTER[*]}; gating ${#CHANGED_SOURCES[@]} changed source file(s)"
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
# The library reads these two only as test seams (tools/tests/test_coverage_phases.py sets them after sourcing); a caller's environment must not reach it.
unset COV_CLASSIFY_ARGS COV_IOS_UITEST
source "$ROOT/tools/coverage_phases.sh"
if [[ -z "${FENTON_COV_CLASS_RUN:-}" || "$(cat "$CLASS_DIR/run-id" 2>/dev/null || true)" != "$FENTON_COV_CLASS_RUN" ]]; then
  export FENTON_COV_CLASS_RUN="$$-$(date +%s)"
  cov_state_reset; echo "$FENTON_COV_CLASS_RUN" > "$CLASS_DIR/run-id"
fi
# iOS phase: the journeys on an instrumented app. It runs before the host phase below because ios_uitest.sh takes its own
# build and simulator holds (it must not nest inside this script's build hold); the host phase merges its report.
IOS_REPORT=""
IOS_STATUS=0
COV_DIR="$ROOT/apple/.build/coverage-ios"
if [[ ",${DEVCAP_HELD:-}," != *",build,"* && "${FENTON_COV_IOS:-}" != skip ]]; then
  RUN_IOS=1
  if [[ $CHANGED == 1 ]]; then
    RUN_IOS=0
    for file in ${CHANGED_SOURCES[@]+"${CHANGED_SOURCES[@]}"}; do [[ "$file" == apple/Sources/HassUI/UIKitPort/* ]] && RUN_IOS=1; done
  fi
  if [[ $RUN_IOS == 1 ]]; then
    PROFILES_DIR="${FENTON_COV_IOS_PROFILES:-$COV_DIR/profraw}"
    if [[ -z "${FENTON_COV_IOS_PROFILES:-}" ]]; then
      rm -rf "$PROFILES_DIR"; mkdir -p "$PROFILES_DIR"
      # 1. The app-hosted unit tests (FentonHomeTests: UIKit pages driven directly inside the instrumented app): seconds, always run.
      echo "== ios: hosted unit tests (FentonHomeTests) with an instrumented app; profiles in $PROFILES_DIR"
      HOSTED_STATUS=0
      cov_phase hosted hosted "$CLASS_DIR/ios-hosted.log" -- \
        "$ROOT/tools/ios_uitest.sh" --only iphone --plan Gate --hosted --impact "$PROFILES_DIR"
      HOSTED_STATUS=$COV_PHASE_STATUS
      (( HOSTED_STATUS == 125 || HOSTED_STATUS == 126 )) && { echo "ERROR: hosted tests did not run (infra, exit $HOSTED_STATUS); no UIKit coverage" >&2; exit "$HOSTED_STATUS"; }
      IOS_STATUS=$HOSTED_STATUS
      # 2. The journeys. --changed: that diff's journeys in one run. Otherwise the Gate plan's classes in FENTON_COV_IOS_PARTS parts
      #    (default 4, balanced by test count), each its own ios_uitest.sh run and devcap hold, so one run no longer has to fit the
      #    7200 s hold cap; every part writes into the same profile directory.
      if [[ $CHANGED == 1 ]]; then
        echo "== ios: journeys on iPhone (changed) with an instrumented app"
        PART_STATUS=0
        # --allow-empty: the diff's journeys may all be iPad-only (skipped on this iPhone-only coverage run); the swift test phase keeps its own check.
        cov_phase journey journey-changed "$CLASS_DIR/ios-journeys-changed.log" -- \
          "$ROOT/tools/ios_uitest.sh" --only iphone --plan Gate --changed --allow-empty --impact "$PROFILES_DIR"
        PART_STATUS=$COV_PHASE_STATUS
        (( PART_STATUS != 0 && IOS_STATUS == 0 )) && IOS_STATUS=$PART_STATUS
        (( PART_STATUS == 125 || PART_STATUS == 126 )) && { echo "ERROR: journeys did not run (infra, exit $PART_STATUS); no UIKit coverage" >&2; exit "$PART_STATUS"; }
      else
        PART=0
        while IFS= read -r FILTER_LINE; do
          [[ -n "$FILTER_LINE" ]] || continue
          PART=$((PART + 1))
          echo "== ios: journeys on iPhone, Gate plan part $PART ($(wc -w <<<"$FILTER_LINE" | tr -d ' ') classes)"
          PART_STATUS=0
          # shellcheck disable=SC2086  # the line is a list of -only-testing: words
          cov_phase journey "journey-$PART" "$CLASS_DIR/ios-journeys-$PART.log" -- \
            "$ROOT/tools/ios_uitest.sh" --only iphone --plan Gate --full --impact "$PROFILES_DIR" $FILTER_LINE
          PART_STATUS=$COV_PHASE_STATUS
          echo "== ios: part $PART exit $PART_STATUS"
          # Each part writes the same result bundle; keep this one so a failure in an early part keeps its screenshot.
          rm -rf "$ROOT/apple/.build/uitest-iphone-part$PART.xcresult"
          [[ -d "$ROOT/apple/.build/uitest-iphone.xcresult" ]] && mv "$ROOT/apple/.build/uitest-iphone.xcresult" "$ROOT/apple/.build/uitest-iphone-part$PART.xcresult"
          (( PART_STATUS != 0 && IOS_STATUS < PART_STATUS )) && IOS_STATUS=$PART_STATUS
        done < <(python3 "$ROOT/tools/uitest_support.py" parts --plan "$ROOT/apple/TestPlans/Gate.xctestplan" "${FENTON_COV_IOS_PARTS:-4}")
      fi
    fi
    # Failed ids rerun once without instrumentation (no --impact): only those tests, same family, each run in its own hold.
    if [[ -z "${FENTON_COV_IOS_PROFILES:-}" ]]; then cov_rerun_ios; fi
    PRODUCTS_KEY="$(python3 "$ROOT/tools/products_cache.py" key CLANG_ENABLE_CODE_COVERAGE=YES CLANG_COVERAGE_MAPPING=YES)"
    PRODUCTS="${FENTON_PRODUCTS_DIR:-$HOME/Library/Caches/fenton/testproducts}/$PRODUCTS_KEY.xctestproducts"
    mkdir -p "$COV_DIR"
    python3 "$ROOT/tools/coverage_ios.py" export "$PROFILES_DIR" --products "$PRODUCTS" --out "$COV_DIR/ios.json"
    IOS_REPORT="$COV_DIR/ios.json"
    export FENTON_COV_IOS_REPORT="$IOS_REPORT" FENTON_COV_IOS_STATUS="$IOS_STATUS"
  fi
fi
IOS_REPORT="${FENTON_COV_IOS_REPORT:-$IOS_REPORT}"; IOS_STATUS="${FENTON_COV_IOS_STATUS:-$IOS_STATUS}"
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
if [[ -n "$IOS_REPORT" && -f "$IOS_REPORT" ]]; then
  MERGED="$CODECOV_DIR/merged.json"
  python3 "$ROOT/tools/coverage_ios.py" merge "$REPORT" "$IOS_REPORT" --out "$MERGED"
  REPORT="$MERGED"
fi
# Plain rerun of the failed host tests, after the export above: a build without coverage replaces the instrumented binaries,
# which the export needs. Only the failed ids run (swift test --filter, --require-tests), still inside this hold.
cov_rerun_swift
GATE_STATUS=0
if [[ $CHANGED == 1 ]]; then
  BASELINE=()
  [[ -f "$ROOT/build/coverage-baseline.json" ]] && BASELINE=(--baseline "$ROOT/build/coverage-baseline.json")
  if (( ${#CHANGED_SOURCES[@]} == 0 )); then
    echo "== changed: no Swift source file changed; the suites ran, nothing to gate"
  else
    python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$REPORT" --files "${CHANGED_SOURCES[@]}" ${BASELINE[@]+"${BASELINE[@]}"} || GATE_STATUS=$?
  fi
else
  python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$REPORT" || GATE_STATUS=$?
fi
if [[ -n "$IOS_REPORT" ]]; then
  echo "== 15 UIKitPort files with the most uncovered lines"
  python3 "$ROOT/tools/coverage_ios.py" top "$REPORT" --n 15 || true
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
