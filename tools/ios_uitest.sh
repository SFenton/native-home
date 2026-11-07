#!/usr/bin/env bash
# Runs the XCUITest journeys (sign-in, Home, layout, accessibility audits) on iPhone, iPhone Duo and
# iPad, one simulator at a time. Credentials are read at runtime from a local env file and passed as
# TEST_RUNNER_ variables; they are never printed or committed.
#
# Capacity: the app compiles once under a machine-wide `build` slot, then each family runs under its
# device gate plus a `simulator` slot (tools/devcap.py, shared with FestivalNativeApps). When the Mac is
# full the script waits its turn; `python3 tools/devcap.py status` shows who holds what.
#
# Usage: tools/ios_uitest.sh [--env shell|FILE] [--only iphone|duo|ipad] [--appearance light|dark] [--quick] [--changed] [--force]
#                            [--plan Gate|Smoke|Capture|Perf|Live] [--suite NAME[,NAME]] [--tests 'SELECTOR[,SELECTOR]'] [--full] [--parallel-families] [--allow-empty] [extra xcodebuild args]
#   A family that executes no test fails EMPTY (xc_watch --require-tests). Every-test-skipped (journeys that skip for lack of credentials)
#   is decided over the whole run: EMPTY (exit 1) only when no family ran a test, or `--only` names one family that ran none; a family
#   that skipped everything while another ran the tests (family-gated journeys) prints a NOTE. The digest reads RESULT: EMPTY.
#   --allow-empty accepts one (it prints an `allow-empty` line so the digest stays PASS).
#   An unfiltered run (no -only-testing, no --changed, no --plan Smoke) is the nightly/release tier and needs --full; without it the
#   script refuses and points at --changed, -only-testing or --plan Smoke. --plan NAME runs apple/TestPlans/NAME.xctestplan
#   (default Gate; the scheme's own selection when the file is missing).
#   --suite NAME[,NAME] runs the named suites of contracts/test-suites.json; --tests 'Class/test*,Other*' runs ad-hoc selectors (globs,
#   plan:NAME, suite:NAME; tools/test_suites.py). Both resolve to -only-testing filters per family, so the products cache, the ledger key
#   (it holds the resolved tests), the hold size and --parallel-families work as for --changed. With --changed they intersect:
#   `--changed --suite audits` runs the affected audits only (per family). With no --plan the plan that owns the selection is used
#   (Gate, Capture, Perf or Live; a selection spanning plans runs with no test plan, as an -only-testing filter without --plan does).
#   --parallel-families runs iphone/duo/ipad at once, each in its own devcap simulator hold with its own log and xcresult
#   (apple/.build/uitest-FAMILY.log/.xcresult); the results are merged into apple/.build/uitest.xcresult and the status is the worst.
#   The app is built once per tree into ~/Library/Caches/fenton/testproducts/HASH.xctestproducts (HASH covers the content of apple/,
#   the build settings and Xcode; tools/products_cache.py) and every family, filter, appearance, worktree and lane reuses it with
#   test-without-building; the log says `products: hit|built KEY`. Entries unused for two days, and the least recently used past 8 GB, are pruned. Journey runs never gather coverage (tools/apple_coverage.sh does) and every test has a time allowance.
#   Watchdogs (tools/xc_watch.py): no output for 180 s (FENTON_UITEST_SILENCE) = `sample`, kill that xcodebuild, shut the simulator
#   down, exit 125 (digest: INFRA hung); 90 s after "Test Suite 'Selected tests' passed|failed" the xcodebuild is killed and the result
#   taken from the log (INFRA slow exit). A simulator that fails `simctl bootstatus -b` (120 s) or a screenshot (20 s) is rebooted
#   once, then the run fails fast as INFRA (exit 126).
#   --changed runs only the journeys the diff against the lane's base branch (tools/lane_base.py: FENTON_AFFECTED_BASE, the PR base, the recorded
#   branch.<name>.sh-base, else the nearest long-lived branch; a failure summary lists which failures the base already has, informational only) needs (tools/affected_tests.py, contracts/test-map.json) on the
#   device families it affects. Each family has its own list: iPhone runs every selected journey, Duo and iPad only the layout ones
#   (`layoutJourneys`, a rule's `layout_journeys`; a blanket `layout_sensitive` rule sends all of its journeys everywhere). The ledger
#   key and the xcodebuild filter use the family's list. A file with no mapping prints a request for a targeted pick and runs nothing: the full suite is the
#   nightly tier, never a fallback. It also sets the map's `changedEnvironment` (FENTON_UITEST_SPACES=all-food: the Inventory pages
#   audit covers one space) unless the caller already exported it as TEST_RUNNER_NAME; a run without --changed covers all six.
#   A (tree hash of apple/, filter, device) run that already passed is skipped with a notice (record: build/testruns/); --force reruns it.
#   --quick skips `xcodegen` when project.yml is unchanged (the compile is skipped by the products cache whenever the code is
#   unchanged). Use it when iterating on one test. The device hold is sized from the selected test count (tools/uitest_support.py): 120 s per test method + 5 minutes,
#   at least 10 minutes, at most 7200 s (FENTON_DEVCAP_HOLD overrides).
#   Run it through `tools/bg_run.py LABEL -- tools/ios_uitest.sh …` with run_in_background and end the turn: you get a digest, not a log.
#   FENTON_DERIVED_DATA=DIR builds and tests with -derivedDataPath DIR (CI gives each run its own and deletes it; unset = Xcode's default).
#   --impact DIR (spike) builds the app instrumented (CLANG_COVERAGE_MAPPING build settings, so its own products-cache entry) and has every app launch write
#   DIR/<Class>.<test>.<pid>.profraw (TEST_RUNNER_FENTON_IMPACT_DIR); tools/test_impact.py extract turns that into a per-test line map.
#   --hosted runs only the app-hosted unit tests, FentonHomeTests. With --impact DIR their profile goes into DIR; without it they run plain
#   (the coverage run's classification rerun, tools/coverage_classify.py). FENTON_HOSTED_FILTER='Class1 Class2' limits it to those classes.
#   --tests does not select hosted tests (they are not UI tests); use FENTON_HOSTED_FILTER.
#   --appearance draws every sheet in that appearance (FENTON_APPEARANCE; pages stay dark). Without it sheets follow the
#   simulator's own setting.
#   FENTON_CI_HOSTED=1 on a GitHub-hosted runner (RUNNER_ENVIRONMENT=github-hosted) is the hosted mode (tools/ci_hosted.py, .agents/workflow/ci.md): no devcap holds or pool (ci_hosted.py devcap
#   runs the command at once), the image's simulators by name (iPhone 17, iPhone Duo, iPad Pro 11-inch (M5); FENTON_SIM_IPHONE / _DUO /
#   _IPAD override), and xcodegen installed when missing. Unset, nothing in this script changes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/sim_pool.sh"
DERIVED=()
[[ -n "${FENTON_DERIVED_DATA:-}" ]] && DERIVED=(-derivedDataPath "$FENTON_DERIVED_DATA")
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ENV_FILE=""
ONLY=""
QUICK=0
CHANGED=0
FORCE=0
FULL=0
ALLOW_EMPTY=0
PARALLEL=0
PLAN="Gate"
PLAN_GIVEN=0
SUITE_SPEC=""
TESTS_SPEC=""
IMPACT_DIR=""
HOSTED=0
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --appearance) export TEST_RUNNER_FENTON_APPEARANCE="$2"; shift 2 ;;
    --quick) QUICK=1; shift ;;
    --changed) CHANGED=1; shift ;;
    --force) FORCE=1; shift ;;
    --full) FULL=1; shift ;;
    --allow-empty) ALLOW_EMPTY=1; echo "allow-empty: an empty run (no test ran, or every test skipped) is not a failure"; shift ;;
    --parallel-families) PARALLEL=1; shift ;;
    --impact) IMPACT_DIR="$2"; shift 2 ;;
    --hosted) HOSTED=1; shift ;;
    --plan) PLAN="$2"; PLAN_GIVEN=1; shift 2 ;;
    --suite) SUITE_SPEC="${SUITE_SPEC:+$SUITE_SPEC,}$2"; shift 2 ;;
    --tests) TESTS_SPEC="${TESTS_SPEC:+$TESTS_SPEC,}$2"; shift 2 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

# Simulator names (the Duo is the product device "iPhone Duo (HASS)", .agents/testing/apple/devices.md; bare "iPhone Duo" is shared); override with FENTON_SIM_IPHONE / FENTON_SIM_DUO / FENTON_SIM_IPAD to pin one device.
# Without an override each family draws from a pool of identical simulators ("<name>", "<name> (pool 2)", …,
# FENTON_SIM_POOL members, default the simulator slot count), so lanes on the same device type run in
# parallel; a lane keeps its last (warm) pool member while it is free.
# (macOS ships bash 3.2: no associative arrays.)
CI_HOSTED=0
[[ "${FENTON_CI_HOSTED:-}" == 1 && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] && CI_HOSTED=1  # never on the owner's Macs (self-hosted)
pinned_name() {
  if [[ $CI_HOSTED == 1 ]]; then device_name "$1"; return; fi  # hosted: always a named simulator from the image, never a pool clone
  case "$1" in
    iphone) echo "${FENTON_SIM_IPHONE:-}" ;;
    duo) echo "${FENTON_SIM_DUO:-}" ;;
    ipad) echo "${FENTON_SIM_IPAD:-}" ;;
  esac
}
device_name() {
  if [[ $CI_HOSTED == 1 ]]; then  # the xcode-27 image's devices (ci_hosted.py DEFAULT_SIMS)
    case "$1" in
      iphone) echo "${FENTON_SIM_IPHONE:-iPhone 17}" ;;
      duo) echo "${FENTON_SIM_DUO:-iPhone Duo}" ;;
      ipad) echo "${FENTON_SIM_IPAD:-iPad Pro 11-inch (M5)}" ;;
    esac
    return
  fi
  case "$1" in
    iphone) echo "${FENTON_SIM_IPHONE:-iPhone 17 Pro}" ;;
    duo) echo "${FENTON_SIM_DUO:-iPhone Duo (HASS)}" ;;
    ipad) echo "${FENTON_SIM_IPAD:-iPad Pro 11-inch (M5)}" ;;
  esac
}

if [[ -n "$ENV_FILE" ]]; then
  # Accept KEY=VALUE lines; map common names onto the runner variables without echoing them.
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hass_creds.sh"; hass_use_env_arg "$ENV_FILE" || exit 2  # in-process only (tools/hass_creds.sh)
  export TEST_RUNNER_FENTON_HASS_USERNAME="${FENTON_HASS_USERNAME:-}"
  export TEST_RUNNER_FENTON_HASS_PASSWORD="${FENTON_HASS_PASSWORD:-}"
  # FENTON_UITEST_NO_TOKEN=1 forces the password login flow.
  [[ "${FENTON_UITEST_NO_TOKEN:-}" == 1 ]] || export TEST_RUNNER_FENTON_HASS_TOKEN="${FENTON_HASS_TOKEN:-}"
  SERVER="${FENTON_HASS_SERVER:-}"
  [[ -n "$SERVER" ]] && export TEST_RUNNER_FENTON_HASS_SERVER="$SERVER"
fi

export COVERAGE=NO
if [[ -n "$IMPACT_DIR" ]]; then
  mkdir -p "$IMPACT_DIR"; IMPACT_DIR="$(cd "$IMPACT_DIR" && pwd)"
  export TEST_RUNNER_FENTON_IMPACT_DIR="$IMPACT_DIR"
  # Instrument with build settings, not -enableCodeCoverage YES: Xcode's own coverage overwrites the app's LLVM_PROFILE_FILE
  # (and drops its profiles in a temp directory), so a per-test file name never reaches the app. The settings also change the
  # products-cache key. Coverage stays NO.
  EXTRA+=(CLANG_ENABLE_CODE_COVERAGE=YES CLANG_COVERAGE_MAPPING=YES)
  FORCE=1
fi
if [[ $HOSTED == 1 ]]; then
  # The app-hosted unit tests (FentonHomeTests: UIKit view controllers driven directly inside the app). With --impact their profile goes
  # to DIR/FentonHomeTests.<pid>.%c.profraw (TEST_RUNNER_ variables reach the test host, which is the instrumented app) and
  # tools/coverage_ios.py export merges it with the journeys' profiles. Takes seconds once the products are cached.
  # Without --impact the hosted tests run plain (no profile): the coverage run's classification rerun (tools/coverage_classify.py).
  # FENTON_HOSTED_FILTER='Class1 Class2' runs only those hosted classes (bisecting a test that fails after another).
  if [[ -n "${FENTON_HOSTED_FILTER:-}" ]]; then for c in $FENTON_HOSTED_FILTER; do EXTRA+=(-only-testing:FentonHomeTests/$c); done; else EXTRA+=(-only-testing:FentonHomeTests); fi
  [[ -z "$IMPACT_DIR" ]] || export TEST_RUNNER_LLVM_PROFILE_FILE="$IMPACT_DIR/FentonHomeTests.%p.%c.profraw"
  # Sized from the hosted test count (uitest_support.py hosted-hold): a fixed 1800 s ended the full suite part way and left its
  # app running into the journeys that followed.
  # shellcheck disable=SC2086  # FENTON_HOSTED_FILTER is a list of class names
  export FENTON_DEVCAP_HOLD="${FENTON_DEVCAP_HOLD:-$(python3 "$ROOT/tools/uitest_support.py" hosted-hold ${FENTON_HOSTED_FILTER:-})}"
fi
case "$PLAN" in Gate|Smoke|Capture|Perf|Live) ;; *) echo "ios_uitest: unknown --plan '$PLAN' (Gate, Smoke, Capture, Perf or Live)" >&2; exit 2 ;; esac
# The plan applies when its file exists; before lane B's plans land the scheme's own selection runs.
PLAN_FILE="$ROOT/apple/TestPlans/$PLAN.xctestplan"
PLAN_ARGS=""
[[ -f "$PLAN_FILE" ]] && PLAN_ARGS="$PLAN"

# FENTON_AFFECTED_FILES / FENTON_TEST_MAP point the selection at a file list and a map instead of the git diff (the tool tests use them).
# --changed resolves the lane's base once (gh pr view is a network call); every later call, here and in the children, reuses it.
[[ $CHANGED == 1 ]] && export FENTON_AFFECTED_BASE="${FENTON_AFFECTED_BASE:-$(python3 "$ROOT/tools/lane_base.py" || true)}"
affected() { python3 "$ROOT/tools/affected_tests.py" "$@" ${FENTON_AFFECTED_BASE:+--base "$FENTON_AFFECTED_BASE"} ${FENTON_TEST_MAP:+--map "$FENTON_TEST_MAP"} ${FENTON_AFFECTED_FILES:+--files $FENTON_AFFECTED_FILES}; }
BASE_EXTRA=("${EXTRA[@]+"${EXTRA[@]}"}")  # the caller's arguments, before --changed adds its journeys
CHANGED_FAMILIES=""
CHANGED_IPHONE=""; CHANGED_DUO=""; CHANGED_IPAD=""  # the -only-testing list each family runs under --changed
if [[ $CHANGED == 1 ]]; then
  AFFECTED_STATUS=0
  CHANGED_JOURNEYS="$(affected --journeys)" || AFFECTED_STATUS=$?
  if [[ -z "$CHANGED_JOURNEYS" ]]; then
    # Exit 3 = a changed file needs a targeted pick (affected_tests.py printed which); 0 = nothing needs a journey.
    echo "== changed: no journey covers this diff; nothing to run"; exit "$AFFECTED_STATUS"
  fi
  for arg in $CHANGED_JOURNEYS; do EXTRA+=("$arg"); done  # the iPhone list (the superset): count, hold and the full-suite check
  CHANGED_FAMILIES="$(affected --families || true)"
  CHANGED_IPHONE="$CHANGED_JOURNEYS"
  CHANGED_DUO="$(affected --journeys --device duo || true)"
  CHANGED_IPAD="$(affected --journeys --device ipad || true)"
  echo "== changed: $CHANGED_JOURNEYS on ${CHANGED_FAMILIES:-no family}"
  [[ "$CHANGED_DUO" == "$CHANGED_JOURNEYS" && "$CHANGED_IPAD" == "$CHANGED_JOURNEYS" ]] || \
    echo "== changed: per family: duo ${CHANGED_DUO:-(smoke)} | ipad ${CHANGED_IPAD:-(smoke)}"
  # The pull request tier narrows looping audits (contracts/test-map.json `changedEnvironment`, e.g. one Inventory space); a value
  # already in the caller's environment wins, and the nightly and release runs (no --changed) never get any.
  for pair in $(affected --environment || true); do
    var="TEST_RUNNER_${pair%%=*}"
    if [[ -z "${!var:-}" ]]; then export "$var=${pair#*=}"; echo "== changed: $var=${pair#*=}"; fi
  done
  [[ -n "$CHANGED_FAMILIES" ]] || exit 0
fi

# --suite / --tests: resolve the selectors (tools/test_suites.py) to -only-testing lists per family; under --changed they are
# intersected with each family's affected journeys. SEL_<FAMILY> empty = that family has nothing to run.
SELECTING=0; SEL_IPHONE=""; SEL_DUO=""; SEL_IPAD=""
if [[ -n "$SUITE_SPEC$TESTS_SPEC" ]]; then
  SELECTING=1
  sel() { python3 "$ROOT/tools/test_suites.py" args ${SUITE_SPEC:+--suite "$SUITE_SPEC"} ${TESTS_SPEC:+--tests "$TESTS_SPEC"} "$@"; }
  if [[ $CHANGED == 1 ]]; then
    SEL_IPHONE="$(sel --within "$CHANGED_IPHONE")" || exit 2
    SEL_DUO="$(sel --within "$CHANGED_DUO")" || exit 2
    SEL_IPAD="$(sel --within "$CHANGED_IPAD")" || exit 2
    echo "== suite: per family: iphone ${SEL_IPHONE:-(none)} | duo ${SEL_DUO:-(none)} | ipad ${SEL_IPAD:-(none)}"
  else
    SEL_IPHONE="$(sel)" || exit 2; SEL_DUO="$SEL_IPHONE"; SEL_IPAD="$SEL_IPHONE"
  fi
  if [[ -z "$SEL_IPHONE$SEL_DUO$SEL_IPAD" ]]; then echo "== suite: nothing selected by the diff; nothing to run"; exit 0; fi
  EXTRA=("${BASE_EXTRA[@]+"${BASE_EXTRA[@]}"}")
  for arg in $SEL_IPHONE; do EXTRA+=("$arg"); done
  if [[ $PLAN_GIVEN == 0 ]]; then
    OWNER="$(python3 "$ROOT/tools/test_suites.py" plan ${SUITE_SPEC:+--suite "$SUITE_SPEC"} ${TESTS_SPEC:+--tests "$TESTS_SPEC"})"
    case "$OWNER" in
      Gate|Capture|Perf|Live) PLAN="$OWNER" ;;
      mixed:*) MIXED=1; echo "== suite: the selection spans plans (${OWNER#mixed:}); running without a test plan so no plan skips a test" >&2 ;;
    esac
    PLAN_FILE="$ROOT/apple/TestPlans/$PLAN.xctestplan"; PLAN_ARGS=""
    [[ -f "$PLAN_FILE" && "${MIXED:-0}" == 0 ]] && PLAN_ARGS="$PLAN"
  fi
fi

# Build settings (NAME=value) also apply to the compile; test options (-only-testing:…) only to the runs.
SETTINGS=()
for arg in ${EXTRA[@]+"${EXTRA[@]}"}; do
  [[ "$arg" =~ ^[A-Z_][A-Z0-9_]*= ]] && SETTINGS+=("$arg")
done
LANE="$(basename "$ROOT")"
FULL_SUITE=1
FILTERS=(); SKIPS=()
for arg in ${EXTRA[@]+"${EXTRA[@]}"}; do
  [[ "$arg" == -only-testing* || "$arg" == -skip-testing* ]] && FULL_SUITE=0
  [[ "$arg" == -only-testing* ]] && FILTERS+=("$arg")
  [[ "$arg" == -skip-testing* ]] && SKIPS+=("$arg")
done
# Smoke, Capture, Perf and Live are on-demand plans; only an unfiltered Gate run (or no plan) is the full tier.
case "$PLAN" in Smoke|Capture|Perf|Live) FULL_SUITE=0 ;; esac
# A hung run holds simulator slots until the hold ends. The hold follows the number of selected test methods: 120 s each
# plus five minutes, at least ten minutes, never more than 7200 s.
SELECTED="$(python3 "$ROOT/tools/uitest_support.py" count ${PLAN_ARGS:+--plan "$PLAN_FILE"} ${FILTERS[@]+"${FILTERS[@]}"})"
# The watchdog gets the EXACT count (plan selection, skips and both filters applied; empty when it cannot be exact), not the hold estimate above.
EXPECTED=""
[[ -n "$PLAN_ARGS" ]] && EXPECTED="$(python3 "$ROOT/tools/uitest_support.py" exact --plan "$PLAN_FILE" ${FILTERS[@]+"${FILTERS[@]}"} ${SKIPS[@]+"${SKIPS[@]}"})"
DEFAULT_HOLD="$(python3 "$ROOT/tools/uitest_support.py" hold "$SELECTED")"
if [[ "${FENTON_UITEST_PRINT_HOLD:-}" == 1 ]]; then echo "${FENTON_DEVCAP_HOLD:-$DEFAULT_HOLD}"; exit 0; fi
if [[ $FULL_SUITE == 1 && $FULL == 0 ]]; then
  echo "ios_uitest: an unfiltered run is the nightly/release tier. Pick a smaller one:" >&2
  echo "  tools/ios_uitest.sh --changed                          the journeys this diff needs" >&2
  echo "  tools/ios_uitest.sh -only-testing:FentonHomeUITests/<Class>" >&2
  echo "  tools/ios_uitest.sh --plan Smoke                       the smoke set" >&2
  echo "  tools/ios_uitest.sh --full                             everything (all selected families)" >&2
  exit 2
fi
DEVCAP=(python3 "$ROOT/tools/devcap.py" run --hold "${FENTON_DEVCAP_HOLD:-$DEFAULT_HOLD}")
# Hosted: the stand-in runs the command at once (devcap.py is a vendored copy, so it is not edited).
[[ $CI_HOSTED == 1 ]] && DEVCAP=(python3 "$ROOT/tools/ci_hosted.py" devcap run --hold "${FENTON_DEVCAP_HOLD:-$DEFAULT_HOLD}")

# Runs one family's journeys inside its devcap hold. The simulator stays booted (warm) afterwards so the
# lane's next run skips the boot; it still counts against the simulator slots, and devcap shuts it down
# after 60 s idle when another lane is waiting, or 5 min idle otherwise. A hung run (hold timeout) shuts it
# down at once. A full-suite run (no -only-testing/-skip-testing filter) ran every test for the device, so
# it shuts the simulator down when it finishes; so does FENTON_SHUTDOWN_SIM=1 (the lane is done with it).
# Exit status: 0 passed, 1 failed, 125 hung (no output), 126 simulator unhealthy.
sim_healthy() {  # udid -> 0 when the simulator booted and can draw a frame
  local udid="$1" shot
  shot="$(mktemp "${TMPDIR:-/tmp}/fenton-health.XXXXXX")"
  python3 "$ROOT/tools/xc_watch.py" --wall 120 --label "simctl bootstatus" -- xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 \
    && { python3 "$ROOT/tools/xc_watch.py" --wall 20 --label "simctl screenshot" -- xcrun simctl io "$udid" screenshot --type=png "$shot" >/dev/null 2>&1 \
         || python3 "$ROOT/tools/xc_watch.py" --wall 20 --label "simctl screenshot (primary display)" -- xcrun simctl io "$udid" screenshot --display=primary --type=png "$shot" >/dev/null 2>&1; }
  # The Duo has two displays (primary and primary-1): a bare `screenshot` fails with "Cannot choose between 2 displays" (exit 22),
  # so the health check retries on the primary display (the flag tools/uikit_shot.sh uses).
  local ok=$?
  rm -f "$shot"
  return $ok
}
run_family() {
  local family="$1" udid="$2" status=0
  "$ROOT/tools/sim_slim.sh" "$udid" || status=1  # inside the hold: boots the simulator and disables the daemons the journeys do not need
  if ! sim_healthy "$udid"; then
    echo "== $family: simulator $udid unhealthy; rebooting once"
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    "$ROOT/tools/sim_slim.sh" "$udid" || true
    if ! sim_healthy "$udid"; then
      xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
      echo "INFRA: simulator unhealthy ($family $udid: bootstatus or screenshot failed twice)"
      return 126
    fi
  fi
  # The system text size is the default for every run: journeys and hosted tests reach AX5 through launch arguments or the
  # in-app switch, never the device setting, and a simulator left at AX5 by hand or by another tool failed 36 hosted tests on the
  # Duo (chips, sheets, forms laid out at AX5; 2026-11-04).
  xcrun simctl ui "$udid" content_size large >/dev/null 2>&1 || echo "== $family: could not reset the text size on $udid"
  # Optional: install another build of the app (a .app) before the run.
  if [[ -n "${FENTON_INSTALL_APP:-}" ]]; then xcrun simctl install "$udid" "$FENTON_INSTALL_APP" || status=1; fi
  local target derived=()
  if [[ -n "${FENTON_TESTPRODUCTS:-}" && -d "$FENTON_TESTPRODUCTS" ]]; then
    target=(-testProductsPath "$FENTON_TESTPRODUCTS")
  else
    target=(-project FentonHome.xcodeproj -scheme FentonHome)
  fi
  [[ -n "${FENTON_DERIVED_DATA:-}" ]] && derived=(-derivedDataPath "$FENTON_DERIVED_DATA")
  local plan=()
  [[ -n "${FENTON_PLAN:-}" ]] && plan=(-testPlan "$FENTON_PLAN")
  # A run that executes nothing (classes the plan skips, or every test skipped for lack of credentials) is EMPTY and fails, not
  # xcodebuild's empty pass; --allow-empty opts out.
  # Per family only "nothing executed" fails (family-gated journeys skip on other families); every-test-skipped is decided over the
  # whole run after the families finish, from the tally each family appends to.
  local require=(--require-tests)
  [[ $ALLOW_EMPTY == 1 ]] && require=()
  # -enableCodeCoverage NO: coverage belongs to tools/apple_coverage.sh, and gathering it is the likely cause of an
  # xcodebuild that never exits after the tests. Every test gets 300 s (900 s at most) before XCTest fails it.
  # A slow exit between plan bundles must not pass as the first bundle's result: hand the watchdog the exact count (EXPECTED) when
  # every family runs the same selection.
  local expect=()
  [[ $CHANGED == 0 && $SELECTING == 0 && "${EXPECTED:-0}" -gt 0 ]] && expect=(--expect-tests "$EXPECTED")
  local tally=(); [[ -n "${FENTON_TALLY:-}" ]] && tally=(--tally "$FENTON_TALLY")
  # FENTON_UITEST_RECORD_DIR=DIR records the simulator's screen for the run to DIR/<family>.mov and its start to DIR/<family>.start
  # (unix seconds), for motion evidence: tools/video_frames.swift turns the video and the journey's marks into frame sheets.
  local recorder=""
  if [[ -n "${FENTON_UITEST_RECORD_DIR:-}" ]]; then
    mkdir -p "$FENTON_UITEST_RECORD_DIR"
    rm -f "$FENTON_UITEST_RECORD_DIR/$family.mov"
    local display=(); [[ "$family" == duo ]] && display=(--display=primary)  # the folded Duo's lit panel; the default display is black
    xcrun simctl io "$udid" recordVideo ${display[@]+"${display[@]}"} --codec=h264 --force "$FENTON_UITEST_RECORD_DIR/$family.mov" > /dev/null 2>&1 &
    recorder=$!
    python3 -c 'import time; print("%.3f" % time.time())' > "$FENTON_UITEST_RECORD_DIR/$family.start"
  fi
  python3 "$ROOT/tools/xc_watch.py" --silence "${FENTON_UITEST_SILENCE:-180}" --exit-cap 90 ${require[@]+"${require[@]}"} ${expect[@]+"${expect[@]}"} ${tally[@]+"${tally[@]}"} --sim "$udid" --label "xcodebuild $family" -- \
    xcodebuild test-without-building ${target[@]+"${target[@]}"} \
    -destination "platform=iOS Simulator,id=$udid" ${derived[@]+"${derived[@]}"} ${plan[@]+"${plan[@]}"} \
    -resultBundlePath "$ROOT/apple/.build/uitest-$family.xcresult" \
    -enableCodeCoverage $COVERAGE -test-timeouts-enabled YES -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 900 \
    ${EXTRA[@]+"${EXTRA[@]}"} || status=$?
  if [[ -n "$recorder" ]]; then kill -INT "$recorder" 2>/dev/null || true; wait "$recorder" 2>/dev/null || true; fi
  return $status
}
export -f run_family sim_healthy
FENTON_TALLY="$(mktemp "${TMPDIR:-/tmp}/fenton-tally.XXXXXX")"; : > "$FENTON_TALLY"; trap 'rm -f "$FENTON_TALLY"' EXIT
export ROOT CHANGED SELECTING SELECTED EXPECTED ALLOW_EMPTY FENTON_TALLY
# App reuse (one resident app per journey class, reset between tests; .agents/testing/apple/app-reuse.md) is on for every run
# (owner, 2026-10-31); TEST_RUNNER_FENTON_UITEST_REUSE=0 turns it off for one.
export TEST_RUNNER_FENTON_UITEST_REUSE="${TEST_RUNNER_FENTON_UITEST_REUSE:-1}"

# Skip a filtered run that already passed on this exact tree, filter, device and runtime environment. The key hashes every
# TEST_RUNNER_FENTON_* value (appearance, orientation, capture, perf switches, live server), the env source, the simulator
# name and the Xcode version. An unfiltered run is never skipped.
ENV_HASH="$( (env | grep '^TEST_RUNNER_FENTON_' | sort || true; echo "env=$ENV_FILE"; xcodebuild -version 2>/dev/null | tr '\n' ' ' || true) | shasum | cut -c1-12 )"
# The arguments one family runs: the caller's own, plus under --changed that family's journey list (iPhone all of the selected
# journeys, Duo and iPad only the layout ones). Sets FAMILY_ARGS; the ledger key and the run both use it.
family_args() {  # family
  FAMILY_ARGS=("${BASE_EXTRA[@]+"${BASE_EXTRA[@]}"}")
  [[ $CHANGED == 1 || $SELECTING == 1 ]] || return 0
  local list="" arg
  if [[ $SELECTING == 1 ]]; then
    case "$1" in iphone) list="$SEL_IPHONE" ;; duo) list="$SEL_DUO" ;; ipad) list="$SEL_IPAD" ;; esac
  else
    case "$1" in iphone) list="$CHANGED_IPHONE" ;; duo) list="$CHANGED_DUO" ;; ipad) list="$CHANGED_IPAD" ;; esac
  fi
  for arg in $list; do FAMILY_ARGS+=("$arg"); done
}
run_key() {
  family_args "$1"
  echo "${FAMILY_ARGS[*]-}|plan:$PLAN_ARGS|env:$ENV_HASH|sim:$(device_name "$1")"
}
TREE_HASH="$(python3 "$ROOT/tools/affected_tests.py" tree-hash 2>/dev/null || echo unknown)"
wanted() {  # family -> 0 when it should run
  [[ -n "$ONLY" && "$ONLY" != "$1" ]] && return 1
  [[ -n "$CHANGED_FAMILIES" && " $CHANGED_FAMILIES " != *" $1 "* ]] && return 1
  if [[ $SELECTING == 1 ]]; then
    case "$1" in iphone) [[ -n "$SEL_IPHONE" ]] || return 1 ;; duo) [[ -n "$SEL_DUO" ]] || return 1 ;; ipad) [[ -n "$SEL_IPAD" ]] || return 1 ;; esac
  fi
  return 0
}
already_passed() {  # family -> 0 when a recorded pass matches
  [[ $FORCE == 1 || $FULL_SUITE == 1 || "$TREE_HASH" == unknown ]] && return 1
  python3 "$ROOT/tools/affected_tests.py" seen --tree "$TREE_HASH" --device "$1" --filter "$(run_key "$1")"
}
recorded_skipped() {  # family -> 0 when the ledger holds a `skipped` record (never a pass) for this exact run
  [[ $FORCE == 1 || $FULL_SUITE == 1 || "$TREE_HASH" == unknown ]] && return 1
  [[ "$(python3 "$ROOT/tools/affected_tests.py" result --tree "$TREE_HASH" --device "$1" --filter "$(run_key "$1")")" == skipped ]]
}
if [[ "${FENTON_UITEST_PRINT_FILTERS:-}" == 1 ]]; then  # dry run for the tool tests: what each family would run
  for family in iphone duo ipad; do wanted "$family" || continue; family_args "$family"; echo "$family: ${FAMILY_ARGS[*]-}"; done
  exit 0
fi
# Preflight: every selected family needs its base simulator in the devcap pool (devcap pick-sim draws pool members from the
# device named here). A missing one is a gap, never a silent skip: one `GAP:` line (the digest shows it) and exit 78 for the run,
# before the build, so a Duo-less machine cannot pass a run that "selected" Duo. FENTON_SIM_LIST_FILE replaces `simctl list` (the tool tests).
POOL_LIST_RC=0; POOL_LIST="$(sim_pool_list)" || POOL_LIST_RC=$?
if (( POOL_LIST_RC != 0 )); then echo "ERROR: could not list the simulator pool (simctl list exit $POOL_LIST_RC); not a GAP" >&2; exit 1; fi
GAPS=0
for family in iphone duo ipad; do
  wanted "$family" || continue
  name="$(device_name "$family")"
  if ! sim_pool_has "$name" <<<"$POOL_LIST"; then
    echo "GAP: $family simulator not in pool ($name)"; GAPS=$((GAPS + 1))
  fi
done
if (( GAPS > 0 )); then echo "ios_uitest: $GAPS selected family simulator(s) missing from the pool; exit 78 (override the name with FENTON_SIM_IPHONE / FENTON_SIM_DUO / FENTON_SIM_IPAD)" >&2; exit 78; fi
PENDING=0
for family in iphone duo ipad; do
  wanted "$family" || continue
  if already_passed "$family"; then
    echo "== $family: already passed on this tree with this filter (build/testruns); --force reruns"
    echo "xcodebuild_$family 1 0" >> "$FENTON_TALLY"  # a recorded pass ran tests: it counts for the run-level EMPTY check
  elif recorded_skipped "$family"; then
    # Replay the recorded outcome without rerunning: it ran no test, which counts as 0 ran in the run-level EMPTY check below.
    echo "== $family: recorded as skipped on this tree with this filter (every selected test skipped); --force reruns"
    echo "xcodebuild_$family 0 0" >> "$FENTON_TALLY"
  else PENDING=$((PENDING + 1)); fi
done
if [[ $PENDING == 0 ]]; then
  echo "== nothing to run"
  if [[ $ALLOW_EMPTY == 0 ]]; then python3 "$ROOT/tools/uitest_support.py" tally "$FENTON_TALLY" || exit 1; fi
  exit 0
fi

cd "$ROOT/apple"
if [[ $CI_HOSTED == 1 ]]; then
  # A fresh VM: xcodegen is not on the image, and the first simctl call after boot can fail ("Unable to connect to simulator",
  # actions/runner-images#13570), so list once before anything boots.
  command -v xcodegen > /dev/null || brew install xcodegen
  xcrun simctl list > /dev/null 2>&1 || true
fi
# xcodegen lists every source file, so an added, moved or deleted file needs a regenerate even when project.yml is unchanged.
SOURCE_LIST=$(git ls-files --cached --others --exclude-standard -- . | grep -E '\.(swift|xcstrings|xcassets/Contents\.json|plist|entitlements)$' | shasum | cut -c1-16)
SOURCE_STAMP=FentonHome.xcodeproj/.fenton-source-list
if [[ $QUICK == 1 && -f FentonHome.xcodeproj/project.pbxproj && ! FentonHome.xcodeproj/project.pbxproj -ot project.yml \
      && "$(cat "$SOURCE_STAMP" 2>/dev/null)" == "$SOURCE_LIST" ]]; then
  echo "== quick: project.yml and the file list unchanged, skipping xcodegen"
else
  xcodegen generate --quiet
  echo "$SOURCE_LIST" > "$SOURCE_STAMP"
fi
# One build per tree: tools/products_cache.py names the bundle by a content hash of apple/, the build settings and Xcode (never the
# environment, worktree, filter, plan or family), so any run on the same code, in any worktree, reuses it. A run that needs a
# missing key builds it under a lock on the key while another run for the same key waits, then hits. It prints `products: hit|built KEY`.
PRODUCTS_DIR="${FENTON_PRODUCTS_DIR:-$HOME/Library/Caches/fenton/testproducts}"
PRODUCTS_KEY="$(python3 "$ROOT/tools/products_cache.py" key ${SETTINGS[@]+"${SETTINGS[@]}"})"
export FENTON_TESTPRODUCTS="$PRODUCTS_DIR/$PRODUCTS_KEY.xctestproducts"
export FENTON_PLAN="$PLAN_ARGS"
# @PARTIAL@ is the cache's per-run output path (xcodebuild needs it to end in ".xctestproducts"; the helper's name does).
python3 "$ROOT/tools/products_cache.py" ensure --key "$PRODUCTS_KEY" --dir "$PRODUCTS_DIR" -- \
  "${DEVCAP[@]}" --pool build --purpose "Fenton uitest build ($LANE)" -- \
  xcodebuild build-for-testing -project FentonHome.xcodeproj -scheme FentonHome \
    -destination 'generic/platform=iOS Simulator' ${DERIVED[@]+"${DERIVED[@]}"} ${SETTINGS[@]+"${SETTINGS[@]}"} \
    -enableCodeCoverage $COVERAGE -testProductsPath @PARTIAL@
export FENTON_TESTPRODUCTS

# One family: pick a simulator, hold it, run, record a pass. Prints its status; the parent collects it.
# Under --parallel-families it runs in the background with its output in its own log.
process_family() {
  local family="$1" name last_file udid shutdown=(--shutdown-on-timeout) status=0
  name="$(device_name "$family")"
  if ! sim_pool_list | sim_pool_has "$name"; then
    echo "GAP: no available simulator named '$name' for $family (a gap, not a pass)"; return 1
  fi
  last_file="$ROOT/apple/.build/uitest-$family.udid"
  if [[ -n "$(pinned_name "$family")" ]]; then
    # Resolve the UDID: xcodebuild's name= matcher misses names with parentheses ("iPhone 17 Pro (Rooms)").
    udid="$(sim_pool_list | sim_pool_udid "$name")"
  else
    local prefer=()
    [[ -s "$last_file" ]] && prefer=(--prefer "$(cat "$last_file")")
    udid="$(python3 "$ROOT/tools/devcap.py" pick-sim --name "$name" --pool "${FENTON_SIM_POOL:-0}" ${prefer[@]+"${prefer[@]}"})"
  fi
  mkdir -p "$(dirname "$last_file")"; echo "$udid" > "$last_file"
  echo "== $family: $name pool ($udid)"
  rm -rf "$ROOT/apple/.build/uitest-$family.xcresult"
  family_args "$family"
  [[ "${FENTON_SHUTDOWN_SIM:-}" == 1 || $FULL_SUITE == 1 ]] && shutdown=(--shutdown)
  "${DEVCAP[@]}" --sim "$udid" ${shutdown[@]+"${shutdown[@]}"} --purpose "Fenton uitest $family ($LANE)" -- \
    bash -c 'EXTRA=("${@:3}"); run_family "$1" "$2"' _ "$family" "$udid" ${FAMILY_ARGS[@]+"${FAMILY_ARGS[@]}"} || status=$?
  if [[ $status == 0 ]]; then
    # A family whose selected tests all skipped (family-gated journeys) is recorded `skipped`, never `pass`: a pass would short-circuit
    # a later run (--only that family) past the run-level EMPTY check.
    local result=pass
    python3 "$ROOT/tools/uitest_support.py" tally-ran "$FENTON_TALLY" "xcodebuild_$family" || result=skipped
    python3 "$ROOT/tools/affected_tests.py" record --tree "$TREE_HASH" --device "$family" --filter "$(run_key "$family")" --result "$result" || status=1
  fi
  return $status
}

# The worst status wins; a hang (125) or unhealthy simulator (126) outranks a plain failure so the digest says INFRA.
worst() { local a="$1" b="$2"; if (( b == 0 )); then echo "$a"; elif (( a == 0 || a == 1 )); then echo "$b"; else echo "$a"; fi; }
STATUS=0
mkdir -p "$ROOT/apple/.build"  # a fresh worktree has none, and the per-family logs live there
# --changed keeps a copy of the run's output for the informational base-failure summary below (it never changes the exit status).
[[ $CHANGED == 1 ]] && exec > >(tee "$ROOT/apple/.build/uitest-run.log") 2>&1
FAMILIES=()
for family in iphone duo ipad; do
  wanted "$family" || continue
  already_passed "$family" && continue
  recorded_skipped "$family" && continue
  FAMILIES+=("$family")
done
if [[ $PARALLEL == 1 && ${#FAMILIES[@]} -gt 1 ]]; then
  PIDS=()
  for family in "${FAMILIES[@]}"; do
    ( process_family "$family" ) > "$ROOT/apple/.build/uitest-$family.log" 2>&1 &
    PIDS+=($!)
  done
  i=0
  for family in "${FAMILIES[@]}"; do
    fs=0; wait "${PIDS[$i]}" || fs=$?
    echo "===== $family (exit $fs) ====="; cat "$ROOT/apple/.build/uitest-$family.log"
    STATUS="$(worst "$STATUS" "$fs")"
    i=$((i + 1))
  done
  BUNDLES=()
  for family in "${FAMILIES[@]}"; do
    [[ -d "$ROOT/apple/.build/uitest-$family.xcresult" ]] && BUNDLES+=("$ROOT/apple/.build/uitest-$family.xcresult")
  done
  if (( ${#BUNDLES[@]} > 1 )); then
    rm -rf "$ROOT/apple/.build/uitest.xcresult"
    xcrun xcresulttool merge "${BUNDLES[@]}" --output-path "$ROOT/apple/.build/uitest.xcresult" >/dev/null 2>&1 \
      && echo "== merged results: apple/.build/uitest.xcresult" || echo "== could not merge the xcresults; read apple/.build/uitest-FAMILY.xcresult"
  fi
else
  for family in ${FAMILIES[@]+"${FAMILIES[@]}"}; do
    fs=0; process_family "$family" || fs=$?
    STATUS="$(worst "$STATUS" "$fs")"
  done
fi
# Run-level EMPTY: no family ran a single test (every one skipped), or --only names one family and it ran none. Families that ran
# nothing while another ran something are family-gated skips: a note. (--only FAMILY leaves one tally line, so a single family that
# skipped everything is EMPTY.) --allow-empty opts out.
if [[ $STATUS == 0 && $ALLOW_EMPTY == 0 ]]; then
  TALLY_RC=0
  TALLY_OUT="$(python3 "$ROOT/tools/uitest_support.py" tally "$FENTON_TALLY")" || TALLY_RC=$?
  [[ -n "$TALLY_OUT" ]] && echo "$TALLY_OUT"
  if [[ $TALLY_RC != 0 ]]; then
    STATUS=1
    # The nightly digests each family's own log with that family's exit code (0): put the run-level EMPTY line in each of them too.
    # Only parallel mode writes those logs, so only this run's families get it (a serial run would append to stale logs).
    if [[ $PARALLEL == 1 && ${#FAMILIES[@]} -gt 1 ]]; then
      for family in "${FAMILIES[@]}"; do
        [[ -f "$ROOT/apple/.build/uitest-$family.log" ]] && echo "$TALLY_OUT" >> "$ROOT/apple/.build/uitest-$family.log"
      done
    fi
  fi
fi
# Informational only (tools/lane_base.py): which failures the base commit already has. It never changes $STATUS.
if [[ $CHANGED == 1 && $STATUS != 0 ]]; then sleep 1; python3 "$ROOT/tools/lane_base.py" baseline summary --command ios_uitest --log "$ROOT/apple/.build/uitest-run.log" || true; fi
exit $STATUS
