# Test suites: composing journeys

Journeys are being split into single-purpose tests. `contracts/test-suites.json` names groups of them (a *suite*) so any mix can be run, and `tools/test_suites.py` resolves a suite to `Class/method` ids from the same source scan that generates the plans (`tools/test_plans.py`).

## Selectors

| Selector | Matches |
|---|---|
| `Class`, `Chores*JourneyTests` | every test of the matching classes |
| `Class/testMethod`, `Setup*JourneyTests/testStep*`, `*/test*Audit*` | matching tests (fnmatch globs on `Class/method`; `*` crosses the slash; a trailing `()` is ignored) |
| `plan:Gate` | a plan's members (Gate, Smoke, Capture, Perf, Live) |
| `map:layoutJourneys` | a class list of `contracts/test-map.json` |
| `suite:name` | another suite (nesting; a cycle is an error) |

A suite is `{"description", "include": [...], "exclude": [...], "plan": false}`: the union of `include` minus the union of `exclude`. `"plan": true` also emits `apple/TestPlans/Suite-NAME.xctestplan` (run `python3 tools/test_plans.py`; `--check` covers it), runnable from Xcode.

## Commands

```
python3 tools/test_suites.py list                       # suites, test counts, estimated seconds (median from build/runs logs, 120 s when untimed)
python3 tools/test_suites.py resolve chores             # Class/method ids
python3 tools/test_suites.py resolve --only-testing 'Setup*/testStep*'
python3 tools/test_suites.py check                      # CI: dead selectors, unknown suites/plans, cycles
tools/ios_uitest.sh --suite audits,ax5                  # run suites
tools/ios_uitest.sh --tests 'ChoresPage*/test*Audit*'   # ad-hoc selectors
tools/ios_uitest.sh --changed --suite audits            # the affected audits only (intersection, per device family)
FENTON_UITEST_PRINT_FILTERS=1 tools/ios_uitest.sh --changed --suite audits   # dry run: what each family would run
```

`--suite`/`--tests` go through the same path as `--plan` and `--changed`: products cache, per-family lists (Duo and iPad get the selection intersected with their layout journeys under `--changed`; without `--changed` every family runs the whole selection), ledger key (it holds the resolved test list, so a changed suite re-runs), hold sizing and `--parallel-families`. With no `--plan`, the plan that owns the selection is used; a selection spanning plans runs with no test plan (an `-only-testing` filter on a test the chosen plan skips runs nothing, see README).

## Naming convention for split journeys

When a multi-step journey is split into one test per step, the tests share a stem: `test<Area><Stem><Step>` (for example `testChoresSwipeUndoOpen`, `testChoresSwipeUndoCommit`). A glob then recombines them: `Chores*JourneyTests/testChoresSwipeUndo*`. Each split **must add or extend a suite** in `contracts/test-suites.json` (at least the feature-area suite, plus a stem suite when the steps are meant to run in order or together), and `python3 tools/test_suites.py check` must stay green: it fails when a selector matches nothing, so a rename that orphans a suite fails the PR. Audits keep `Audit` in the name and AX5 tests `AX5`, so the `audits` and `ax5` suites pick them up with no edit.
