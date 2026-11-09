#!/usr/bin/env bash
# Fling frame rate: flings S+H's pages on a physical iPhone (FlingFrameRateControlTests) and prints the app's own FrameMonitor
# numbers per page; with --trace it also records an Animation Hitches trace (Apple's Settings is the control for S+H's).
#
# Default measurement: the app's own FrameMonitor (a passive UIUpdateLink, so it does not hold the display rate) collects every
# presented frame while the test flings, and the test prints one FLINGFPS-STATS line per page. No trace, so it takes seconds,
# not gigabytes. Apple's Settings cannot be measured this way (it needs --trace).
#
# Usage: tools/ios_flingfps.sh --device <udid> [--tests "testFlingSettings testFlingRecipes"] [--live] [--hold SECONDS]
#        [--disable LAYER] [--flyout] [--tag NAME] [--ab-disable LAYER] [--runs N] [--trace]   (LAYER: a case in HassDesign/PerfSwitches.swift)
#   --ab-disable SWITCH --runs N  A/B in ONE device hold: N runs of each test with the default build, then with
#                  FENTON_PERF_DISABLE=SWITCH (a name from HassDesign/PerfSwitches.swift; interleaved per run), and a summary table at
#                  the end. Variants are named `default` and `<SWITCH>-off`.
#   --trace        Also record an Animation Hitches trace per test (Apple's own displayed-surfaces numbers; needed for Apple's Settings).
#                  Bounded: the recorder is stopped when the test ends or fails, a trace over 400 MB is not exported (deleted), and
#                  each export is cut off after 300 s. Add testFlingAppleSettings to --tests for the control.
#   --disable / --flyout  Experiment switches for the app under test (FENTON_PERF_DISABLE; FENTON_GALLERY_FLYOUT=1: gallery pages in the
#                         phone's flyout chrome). --tag names the output files so variants sit side by side.
#
# Builds once under a build slot, then the tests (and traces, with --trace) run inside one devcap device hold. Output and the
# exported XML stay in apple/.build/flingfps-<stamp>/; a trace is always deleted after export (and by an EXIT trap), because its
# environment / process-info section can hold the live token. Only extracted numbers are printed; this script never prints it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DEVICE=""; TESTS=""; HOLD=""; TAG=""; AB=0; AB_SWITCH=""; RUNS=1; TRACE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --tests) TESTS="$2"; shift 2 ;;
    --live) export TEST_RUNNER_FENTON_PERF_LIVE=1; shift ;;
    --hold) HOLD="$2"; shift 2 ;;
    --disable) export TEST_RUNNER_FENTON_PERF_DISABLE="$2"; shift 2 ;;
    --flyout) export TEST_RUNNER_FENTON_GALLERY_FLYOUT=1; shift ;;
    --tag) TAG="$2"; shift 2 ;;
    --ab-disable) AB=1; AB_SWITCH="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --trace) TRACE=1; shift ;;
    *) echo "unknown arg $1"; exit 2 ;;
  esac
done
[[ -n "$TESTS" ]] || { [[ "$TRACE" == 1 ]] && TESTS="testFlingAppleSettings testFlingSettings" || TESTS="testFlingSettings testFlingRecipes"; }
if [[ "$AB" == 1 ]]; then
  grep -Eq "^[[:space:]]*case[[:space:]]+${AB_SWITCH}[[:space:]]*(//.*)?$" "$ROOT/apple/Sources/HassDesign/PerfSwitches.swift" \
    || { echo "--ab-disable '$AB_SWITCH' is not a case in apple/Sources/HassDesign/PerfSwitches.swift" >&2; exit 2; }
fi
# Hold: one test is about 90 s without a trace (launch, 24 flicks, stats) and about 130 s with one (6 s head start, 8 s wait, exports);
# times tests x runs x variants, plus 20% slack. devcap caps a hold at 7200 s.
NTESTS=$(wc -w <<<"$TESTS" | tr -d ' ')
PER_TEST=90; [[ "$TRACE" == 1 ]] && PER_TEST=300
NEEDED=$(( NTESTS * RUNS * (AB + 1) * PER_TEST * 12 / 10 ))
[[ -n "$HOLD" ]] || HOLD=$(( NEEDED > 1800 ? NEEDED : 1800 ))
if (( HOLD > 7200 )); then echo "warning: hold ${HOLD}s is above devcap's 7200 s cap; use fewer --runs/--tests" >&2; fi
[[ "$TRACE" == 1 ]] || export TEST_RUNNER_FENTON_FLING_NOTRACE=1
[[ -n "$DEVICE" ]] || { echo "usage: tools/ios_flingfps.sh --device <udid> [--tests \"...\"] [--live]"; exit 2; }
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/apple/.build/flingfps-$STAMP${TAG:+-$TAG}"; mkdir -p "$OUT"
# A trace can hold the live token: whatever ends this script (an interrupt, a hold overrun killing the inner group), none stays.
trap 'rm -rf "$OUT"/*.trace' EXIT
DERIVED="$ROOT/apple/.build/perf-dd"
cd "$ROOT/apple"
xcodegen generate --quiet
echo "== building for the device" >&2
python3 "$ROOT/tools/devcap.py" run --pool build --purpose "ios_flingfps build" -- \
  xcodebuild build-for-testing -project FentonHome.xcodeproj -scheme FentonHome \
    -destination "platform=iOS,id=$DEVICE" -allowProvisioningUpdates -derivedDataPath "$DERIVED" SWIFT_OPTIMIZATION_LEVEL=-O \
    > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; exit 1; }

# The trace (--trace only) must outlast the whole test: 6 s head start + app launch and navigation (about 25 s allowed) + 8 s wait for the
# recorder + 24 flicks at up to 2 s each (48 s) + 2 x 2 s pauses = 91 s; 120 s leaves headroom. (45 s cut the flicks short.)
TRACE_LIMIT=120

# Runs `cmd` for at most N seconds (macOS has no timeout(1)).
with_timeout() { local n="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$n" "$@"; }

# Inside the hold: one test, one variant, one run. Arguments: test, out dir, device, derived data, repo root, trace limit,
# trace (0/1), variant label, disable value ("" for the default build).
run_test() {
  local t="$1" OUT="$2" DEVICE="$3" DERIVED="$4" ROOT="$5" TRACE_LIMIT="$6" TRACE="$7" VARIANT="$8" DISABLE="$9"
  local name="$t.$VARIANT" XP=""
  local trace="$OUT/$name.trace"
  if [[ "$TRACE" == 1 ]]; then
    xcrun xctrace record --device "$DEVICE" --template 'Animation Hitches' --all-processes --time-limit "${TRACE_LIMIT}s" \
      --output "$trace" --no-prompt > "$OUT/$name.xctrace.log" 2>&1 &
    XP=$!
    sleep 6   # the recorder needs to be running before the test's 8 s wait ends
  fi
  local rc=0
  if [[ -n "$DISABLE" ]]; then export TEST_RUNNER_FENTON_PERF_DISABLE="$DISABLE"; else unset TEST_RUNNER_FENTON_PERF_DISABLE; fi
  xcodebuild test-without-building -project FentonHome.xcodeproj -scheme FentonHome \
    -destination "platform=iOS,id=$DEVICE" -derivedDataPath "$DERIVED" \
    -only-testing:"FentonHomeUITests/FlingFrameRateControlTests/$t" > "$OUT/$name.test.log" 2>&1 || rc=$?
  if [[ -n "$XP" ]]; then
    # Pass or fail the recorder must not outlive the test: SIGINT finalises the trace, then wait, then SIGKILL.
    kill -INT "$XP" 2>/dev/null || true
    for _ in $(seq 1 40); do kill -0 "$XP" 2>/dev/null || break; sleep 1; done
    kill -9 "$XP" 2>/dev/null || true
    wait "$XP" 2>/dev/null || true
  fi
  [[ "$rc" == 0 ]] || echo "test $t [$VARIANT] failed rc=$rc (see $OUT/$name.test.log)" >&2
  echo "-- $t [$VARIANT]: $(grep -E 'FLINGFPS lowPowerMode' "$OUT/$name.test.log" | head -1 | sed 's/.*FLINGFPS //')"
  grep -E "Test Case.*(passed|failed|skipped)" "$OUT/$name.test.log" | head -1 | sed 's/.*Test Case/   Test Case/'
  grep -E 'FLINGFPS(-STATS|-end)' "$OUT/$name.test.log" | sed -E 's/^.*(FLINGFPS)/   \1/' | sort -u
  [[ "$TRACE" == 1 && -e "$trace" ]] || return 0
  local sz; sz=$(du -sm "$trace" | cut -f1)
  echo "   trace ${sz} MB"
  if [[ "$sz" -gt 400 ]]; then rm -rf "$trace"; echo "   trace deleted unexported (over 400 MB)"; return 0; fi
  for schema in displayed-surfaces-per-second hitches; do
    with_timeout 300 xcrun xctrace export --input "$trace" --xpath "/trace-toc/run/data/table[@schema=\"$schema\"]" > "$OUT/$name.$schema.xml" 2>/dev/null || echo "   export $schema cut off" >&2
  done
  python3 -I "$ROOT/tools/flingfps_report.py" "$OUT/$name.displayed-surfaces-per-second.xml" "$OUT/$name.hitches.xml" || true
  rm -rf "$trace"   # the environment section can hold the live token: never keep a trace
}

# One hold for everything: for each run, each variant, each test.
run_all() {
  local OUT="$1" DEVICE="$2" DERIVED="$3" ROOT="$4" TRACE_LIMIT="$5" TRACE="$6" AB="$7" RUNS="$8" TESTS="$9" DISABLE="${10}" AB_SWITCH="${11}"
  local variants=("default:$DISABLE")
  [[ "$AB" == 1 ]] && variants=("default:" "${AB_SWITCH}-off:${AB_SWITCH}")
  for r in $(seq 1 "$RUNS"); do
    for v in "${variants[@]}"; do
      for t in $TESTS; do
        echo "== run $r ${v%%:*} $t"
        run_test "$t" "$OUT" "$DEVICE" "$DERIVED" "$ROOT" "$TRACE_LIMIT" "$TRACE" "${v%%:*}.r$r" "${v#*:}"
      done
    done
  done
}
# --disable on a plain run (not --ab-disable) is passed to the default variant.
DISABLE_ARG="${TEST_RUNNER_FENTON_PERF_DISABLE:-}"
python3 "$ROOT/tools/devcap.py" run --device "$DEVICE" --hold "$HOLD" --purpose "ios_flingfps $TESTS" -- \
  bash -c "$(declare -f with_timeout run_test run_all); run_all \"\$@\"" _ "$OUT" "$DEVICE" "$DERIVED" "$ROOT" "$TRACE_LIMIT" "$TRACE" "$AB" "$RUNS" "$TESTS" "$DISABLE_ARG" "$AB_SWITCH" | tee "$OUT/summary.txt"
python3 -I "$ROOT/tools/flingfps_table.py" "$OUT/summary.txt" || true
echo "Output: $OUT"
