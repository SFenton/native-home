# Coverage measurement

> **What:** how `tools/apple_coverage.sh` measures and gates the >=95% logic line bar on the Mac host; UX line coverage is not measured (owner, 2026-11-10). **Read when:** the logic number looks wrong, a coverage run fails, or you add a source module.

## What is measured, and where

One source, one report: `swift test --enable-code-coverage` on the Mac host (a test runner only; macOS is not a product platform). `tools/apple_coverage.sh` exports one LLVM report across every `*Tests.xctest` binary (`swift test`'s own JSON export reads only one bundle), and `tools/coverage_gate.py` requires **95%** of the executable lines in the `logic` globs of `contracts/coverage-rules.json`: `HassCore`, `HassTelemetry`, `FentonActivityModel` and `HassDemoHouse`. No simulator, no instrumented app, no iOS profile merge. A full run is about ten minutes and takes one devcap `build` hold. It is the nightly and release tier (`FENTON_TIER=nightly tools/apple_coverage.sh` through `tools/bg_run.py`); `tier_guard.py` no longer guards it.

A classified `logic` file with no LLVM record compiled to no instrumented code (declarations only): it counts as zero lines and the gate lists it. A whole module with no record is an error, because its test bundle was not exported.

## UX is classified `unmeasured` (owner, 2026-11-10)

`HassDesign`, `HassUI` (including `UIKitPort`) and `FentonActivityViews` sit under `swift.unmeasured` in `contracts/coverage-rules.json`; `thresholds` names only `logic`. The category exists for classification alone: every file under `apple/Sources` still matches exactly one category, so a new module fails `coverage_gate.py --language swift --classify-only` by name (the script runs it first, before taking a build slot) until its pattern is added. `unmeasured` files get no report line, no threshold and no "no LLVM record" error, and `--files` skips them. An old `--baseline` file's UX entries are ignored.

This reverses the 2026-10-16 decision that set the UX bar at 95%. The UX tests, accessibility tests, app-hosted tests (`FentonHomeTests`, `HassUITests`) and journeys are all kept, and every UI change still owes a UX test and an accessibility test on each affected family ([testing](README.md)). What changes is that nobody chases a line count in view code. Branching logic belongs in `HassCore` or a model the host tests reach, so the gate sees it; a view controller that grows branching logic is a review finding.

## `--changed`

`tools/apple_coverage.sh --changed` runs `swift test --filter` for the suites the diff affects (`tools/affected_tests.py`, `contracts/test-map.json`) against the lane's base (`tools/lane_base.py`; `FENTON_AFFECTED_BASE` overrides), and gates only the changed files the rules class as `logic` (`coverage_gate.py --files`; `--baseline build/coverage-baseline.json` when that file exists, so a file that was already under the bar passes unless it gets worse). A diff that changes no logic file prints `== changed: no logic source changed; nothing to gate` after the suites ran and exits 0. A diff that maps to no host suite prints `nothing to run` and exits as `affected_tests.py` did (3 when it needs a targeted pick). Under `--files`, a changed logic file with no record fails loudly (`<N> records are under <prefix>, outside this checkout`) when `llvm_file_totals` skipped `/apple/(Sources|Apps|Tests)/` records from another checkout's path; with no such drops the declarations-only note stays. `tools/lint_motion.sh` also runs first, as it does in `pr-checks`.

## Failures in a host test run are classified

`swift test` runs under `tools/xc_watch.py` (`FENTON_COVERAGE_SILENCE`, default 20 minutes without output, kills it as `INFRA: hung`, exit 125) with `--require-tests`: a run that executes no test is `EMPTY` (exit 1) unless `FENTON_COV_ALLOW_EMPTY=1`. The phase records its exit status and the ids it named (`tools/coverage_classify.py`, `tools/coverage_phases.sh`); a phase that exited 124, 125, 126 or above 128, or failed without naming a test, fails the run whatever the quarantine says. A crash marker in the log (`signal code`, `Restarting after unexpected exit`, `crashed with signal`, `Test crashed`: SwiftPM exits 1 for these) or a failure count the log cannot explain (more `Executed N tests, with F failures` or Swift Testing issues than named ids and issue lines) also fails it.

Each named id reruns once without instrumentation (`swift test --filter` under `xc_watch --require-tests`, same hold), after the export, because a plain build replaces the instrumented binaries. An id is `coverage-only` only when the rerun log shows it passed; anything else is `real`. The digest prints `coverage-only:`, `real:` and `timeout:`. The run exits non-zero for any `real` id, a timeout, and a `coverage-only` id missing from `apple/coverage-quarantine.json` (entries `{id, issue, date}`; the issue must be an open `Workflow` issue, checked with `gh` only for an id that leans on it; on a green run a bad entry is a warning). The 95% bar never changes and quarantined tests still count.

## History

The two-source UX measurement this replaced (journeys and app-hosted tests on an instrumented iPhone app, merged with the host report), and its last numbers, are archived in [coverage-baseline-2026-11-04.md](../../archive/testing/coverage-baseline-2026-11-04.md).
