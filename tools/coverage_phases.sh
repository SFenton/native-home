#!/usr/bin/env bash
# Phase bookkeeping for the coverage run (sourced by the coverage script; tools/tests/test_coverage_phases.py drives it with stubs).
# Needs ROOT, CLASS_DIR and CLASSIFY (tools/coverage_classify.py) from the caller. State, all in CLASS_DIR:
#   failed.txt    `KIND id` per failing test id an instrumented phase named (KIND: hosted, journey, swift)
#   phases.txt    `NAME STATUS NIDS CRASHED UNEXPLAINED` per phase run: its exit status, ids named, a crash marker, failures the log cannot explain
#   rerun-logs.txt  the logs of the plain reruns; the verdict reads positive evidence (a passed id) from them
# Why per phase: one named failure must not explain a different phase that crashed, timed out or failed to build.

# cov_state_reset: a fresh, empty state.
cov_state_reset() {
  rm -rf "$CLASS_DIR"; mkdir -p "$CLASS_DIR"
  : > "$CLASS_DIR/failed.txt"; : > "$CLASS_DIR/phases.txt"; : > "$CLASS_DIR/rerun-logs.txt"
}

# cov_phase KIND NAME LOG -- CMD...: run CMD with its output in LOG; record its exit status (COV_PHASE_STATUS) and the ids it named.
cov_phase() {
  local kind="$1" name="$2" log="$3" status=0 named crashed unexplained; shift 4
  "$@" 2>&1 | tee "$log" || status=$?
  python3 "$CLASSIFY" failed-ids "$log" > "$CLASS_DIR/ids.tmp" || true
  sed "s/^/$kind /" "$CLASS_DIR/ids.tmp" >> "$CLASS_DIR/failed.txt"
  # NAMED CRASHED UNEXPLAINED: a crash marker (SwiftPM exits 1 on a signal) or a failure count the log does not explain fails the phase.
  read -r named crashed unexplained < <(python3 "$CLASSIFY" phase-facts "$log" || echo "0 1 0")
  echo "$name $status ${named:-0} ${crashed:-1} ${unexplained:-0}" >> "$CLASS_DIR/phases.txt"
  COV_PHASE_STATUS=$status
}

# cov_rerun_plain LOG -- CMD...: run a plain (no instrumentation) rerun; its log is read for passed ids.
cov_rerun_plain() {
  local log="$1"; shift 2
  "$@" 2>&1 | tee "$log" || true
  echo "$log" >> "$CLASS_DIR/rerun-logs.txt"
}

# cov_ids_of KIND: the failing ids of a kind, comma separated.
cov_ids_of() { { grep "^$1 " "$CLASS_DIR/failed.txt" || true; } | cut -d' ' -f2 | paste -sd, -; }

# cov_rerun_ios: rerun failed hosted classes and journeys without --impact; the command lines come from coverage_classify.py.
cov_rerun_ios() {
  local uitest="${COV_IOS_UITEST:-$ROOT/tools/ios_uitest.sh}" hosted journey
  hosted="$(cov_ids_of hosted)"; journey="$(cov_ids_of journey)"
  if [[ -n "$hosted" ]]; then
    echo "== ios: plain rerun of failed hosted tests: $hosted"
    eval "cov_rerun_plain \"\$CLASS_DIR/rerun-hosted.log\" -- $(python3 "$CLASSIFY" rerun-cmd hosted "$hosted" --script "$uitest")"
  fi
  if [[ -n "$journey" ]]; then
    echo "== ios: plain rerun of failed journeys: $journey"
    eval "cov_rerun_plain \"\$CLASS_DIR/rerun-journeys.log\" -- $(python3 "$CLASSIFY" rerun-cmd journey "$journey" --script "$uitest")"
  fi
}

# cov_rerun_swift: rerun the failed host tests with `swift test --filter` (no coverage), requiring that a test ran.
cov_rerun_swift() {
  local ids filters=() line
  ids="$(cov_ids_of swift)"
  [[ -n "$ids" ]] || return 0
  while IFS= read -r line; do [[ -n "$line" ]] && filters+=(--filter "$line"); done < <(python3 "$CLASSIFY" swift-filters "$ids")
  echo "== swift test: plain rerun of failed tests (no coverage): $ids"
  cov_rerun_plain "$CLASS_DIR/rerun-swift.log" -- python3 "$ROOT/tools/xc_watch.py" --silence "${FENTON_COVERAGE_SILENCE:-1200}" --require-tests \
    --label "swift test (plain rerun)" -- swift test "${filters[@]}"
}

# cov_verdict: print the digest and return its status (non-zero: a real or unquarantined id, a timeout, or a phase that cannot be classified).
cov_verdict() {
  local logs=() log
  while IFS= read -r log; do [[ -n "$log" ]] && logs+=("$log"); done < "$CLASS_DIR/rerun-logs.txt"
  python3 "$CLASSIFY" classify --failed "$CLASS_DIR/failed.txt" --phases "$CLASS_DIR/phases.txt" ${COV_CLASSIFY_ARGS:-} \
    ${logs[@]+--rerun-log "${logs[@]}"}
}
