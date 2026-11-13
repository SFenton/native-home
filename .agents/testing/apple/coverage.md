# Coverage measurement

> **What:** how `tools/apple_coverage.sh` measures and gates the logic line bar on the Mac host; UX line coverage is not measured. **Read when:** the logic number looks wrong, a coverage run fails, or you add a source module.

## What is measured, and where

- One source, one report: `swift test --enable-code-coverage` on the Mac host (a test runner only; macOS is not a product platform).
- `tools/apple_coverage.sh` exports one LLVM report across every `*Tests.xctest` binary, and `tools/coverage_gate.py` requires 95% of the executable lines in the `logic` globs of `contracts/coverage-rules.json`.
- No simulator, no instrumented app and no iOS profile take part. A full run takes one devcap `build` hold and is the nightly and release tier ([test tiers](README.md#test-tiers)).
- A classified `logic` file with no LLVM record compiled to no instrumented code (declarations only): it counts as zero lines and the gate lists it. A whole module with no record is an error, because its test bundle was not exported.

## UX source is unmeasured

- `HassDesign`, `HassUI` (including `UIKitPort`) and `FentonActivityViews` sit under `swift.unmeasured` in `contracts/coverage-rules.json`; `thresholds` names only `logic`.
- Every file under `apple/Sources` still matches exactly one category, so a new module fails `coverage_gate.py --language swift --classify-only` by name until its pattern is added. `unmeasured` files get no report line, no threshold and no "no LLVM record" error, and `--files` skips them.
- UX tests, accessibility tests, app-hosted tests and journeys are kept: every UI change owes a UX test and an accessibility test on each affected family ([testing](README.md)); the app-hosted and journey tiers are pass or fail ([test tiers](README.md#test-tiers)).
- Branching logic belongs in `HassCore` or a model the host tests reach, so the gate sees it. A view controller that grows branching logic is a review finding. `FentonActivityViews` is checked by its UX and accessibility tests.

## `--changed`

`tools/apple_coverage.sh --changed` runs the host suites the diff affects and gates only the changed files the rules class as `logic`. A diff that changes no logic file gates nothing and exits 0; a diff that maps to no host suite runs nothing. A changed logic file with no record fails loudly when records from another checkout's path were skipped. `tools/apple_coverage.sh --help` prints the detail.

## Failures in a host test run are classified

`swift test` runs under `tools/xc_watch.py` with `--require-tests`: a run that executes no test is `EMPTY` and fails. `tools/coverage_classify.py` and `tools/coverage_phases.sh` record each phase's exit status and the test ids it named.

- A timeout, an infrastructure exit, a crash marker or a failure with no named test fails the run whatever the quarantine says.
- Each named id reruns once without instrumentation, after the export. An id is `coverage-only` only when the rerun passed; anything else is `real`.
- The run fails for any `real` id and for a `coverage-only` id missing from `apple/coverage-quarantine.json` (each entry names an open `Workflow` issue). The 95% bar never changes and quarantined tests still count.
