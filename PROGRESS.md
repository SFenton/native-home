# Fenton HASS Native: current plan

> **What:** what is being built now and next, and who owns which seam. **Read when:** planning a lane or picking up work. History (finished lanes, the dated log, the old status table) is in [.agents/archive/progress-2026-10.md](.agents/archive/progress-2026-10.md); per-surface status is the mockup atlas [catalog.json](.agents/design/mockups/catalog.json). Keep this file at 60 lines or fewer ([docs-conventions](.agents/workflow/docs-conventions.md#current-vs-history)).

## 1. Operating model

The UIKit port landed on `main` on 2026-11-05 (#308); `workflow_base` is `main`. Fable 5.2 (medium) plans and designs, Opus does the final review (owner, 2026-11-10); Sonnet lanes implement in separate worktrees; Haiku gathers ([AGENTS.md](AGENTS.md#model-roles)). A lane reads anything and edits only what it owns; ask in your report for a change in a shared seam.

| Seam | Owner |
|---|---|
| `apple/Package.swift`, `apple/project.yml`, `HassCore/Auth`, `Connection`, `Entities`, `HassDesign/`, `HassUI/App/` | orchestrator (lanes may add new files to `HassDesign/`) |
| `HassUI/Features/<Feature>/`, `HassCore/<Feature>/`, `HassCore/Config/<Area>Config.swift` | the lane for that feature |
| `apple/Tests/**` | tests for your own files only |
| `.agents/pages/<id>/`, `.agents/controls/<id>/` | the lane for that page or control |
| `.agents/**` (the rest), `tools/`, `.claude/` | orchestrator |

## 2. Now: workflow overhaul, Phase 1 (owner approved 2026-10-28)

Three lanes, one worktree each; rebase on `origin/main` before landing. Drop a lane's row when its PR is merged.

| Lane | Pieces | Holds |
|---|---|---|
| test-tiers (landed, #189) | W1, W7 | one test-tier table, `tools/affected_tests.py`, `contracts/test-map.json`, `ios_uitest.sh --changed`, tree-hash rerun skip |
| pr-lifecycle | W2, W3, W4 | `workflow/pr-lifecycle.md`, `tools/pr_land.sh`, the pre-merge review subagent and PR template, merge-blocking hook, system-API-first rung 0, `audit/system-api-audit.md` |
| mockups-docs | W5, W6 | mockup lifecycle (`decided`, `superseded`, merged-branch check), automatic hub republish and its Stop hook; docs show only current truth, history in `.agents/archive/` |
| vacuum-sheet-redesign | owner-decided 2026-10-28/29 | `HassCore/Vacuums`, `HassUI/Features/Vacuums`, `TileActionItem.indicator` choice discs; decision doc `.agents/design/vacuum-sheet-redesign.md`; built and tested on branch `vacuum-sheet-redesign`, awaiting PR |

## 2a. Now: agent roster, Phase B (owner approved 2026-11-01, autonomous)

Spec: [agent-roster](.agents/workflow/agent-roster.md). Phase A (roles, contracts, hooks, ledger, Jev sections and corpus) merged as #262. Phase B lanes, integrated on `claude/agent-roster-b` as one PR: `pb-triage` (labels on both repos with self-heal, `claude auth` preflight, ledger in shadow, `route.role` hint, worker on the orchestrator playbook, L2 park path, weekly Steward and Researcher jobs), `pb-eval` (design-defect eval runner and a pilot), `pb-live` (hooks, skills and agent types checked in live sessions; `duo_pose.py` on a simulator).

## 2b. Now: house config at runtime (owner decisions 2026-11-06)

Step 1 landed in code: `HassCore/Config/HouseConfig*.swift` is the Codable schema (`schema: 1`) of the house statics, `HouseConfig.compiled` builds it from them, and `HouseConfigTests` writes the git-ignored `build/ha/house.json` fixture for step 2. Nothing reads it yet. Prose copy and behaviour are not mirrored.

Step 9a (docs and fixtures scrub): `.agents` pages, platforms, patterns, workflow and testing docs, the Jev example corpora and `tools/push_fixtures` carry demo ids and neutral wording, no house data. Names bound to code or to tests (enum cases, Swift types, fixture names the app tests assert, the `valetudo-map.md` path) stay until schema v2 and the app lane rename them. Step 9b is the mockups.

## 3. Next

- **Hosted CI follow-ups ([ci](.agents/workflow/ci.md#hosted-github-actions-owner-2026-11-07)):** `hosted-ci-linux-portability` (find and fix the causes of the method-level Linux skips in `test_devcap.LifecycleTests`, `test_hass_creds.LoaderTests`, `test_xc_watch` and `test_agent_roster`, then drop the skips; `test_test_ha.GeneratorTests` is red on main on macOS as well); set `HOSTED_MACOS=on` and `DENYLIST_STRICT=on` at the public flip.

- **Phase 2 (W9, W10) is built:** private repo, self-hosted runners `hass-mac` (MacBook) and `host-mini` (Mac mini, host-only jobs, 2026-10-30), `pr-checks`, `ios-release` and the 02:00 nightly run with `Nightly Fix` issues for the triage runner ([ci](.agents/workflow/ci.md)). Owner actions left: the `pmset` wake command and, if the first `ios-release` run says `BLOCKED`, the signing items it names.
- **Phase 3, knowledge you can query:** `contracts/patterns.json` and `tools/pattern_guard.py` ported from the private sibling triage project, `contracts/components.json` generated from `HassDesign`, `HassUI/Common` and `HassUI/Controls`, then a Jev pre-read (`tools/jev_ask.py`) measured against keyword lookup before it is relied on.
- **Phase 3 follow-up:** `pattern_guard.py`, `components_index.py --check` and `jev_ask.py sync --check` now run in `pr-checks` ([pr-lifecycle](.agents/workflow/pr-lifecycle.md#registry-checks-for-pr-checks)). Still open: put the key in the key file `~/.config/fenton-hass/typesafe.key` (or `TYPESAFE_API_KEY` in the triage launchd job when there is no file).
- **W12 (landing):** live-validation credentials load only inside the processes that need them (`tools/hass_creds.sh`, `--env shell`); `--env FILE` and `temp.env` are retired. Owner steps in [devices](.agents/testing/apple/devices.md) (Owner setup).
- **TestFlight:** privacy manifests, `ITSAppUsesNonExemptEncryption` and `tools/release/testflight_upload.sh` (internal testing only, no Watch app) are in; see [testflight](.agents/platforms/apple/testflight.md). CI path (2026-11-10, `testflight-hosted`): merge → `ios-release` bump → hosted signed IPA artifact → the same archive uploaded to TestFlight in the `ipa` job; no variable, no gate; `ios-release-build.yml`, the queue and the `ios/tf/` ledger are retired; pause with `gh workflow disable ios-release.yml` ([checklist](.agents/platforms/apple/testflight.md#release-pipeline-owner-checklist)).
- **Release pipeline (T-release-pipeline, 2026-11-09):** a push to `main` bumps the version (`ios-release.yml`, always on) and builds and signs a release IPA on a hosted macOS runner, kept as the workflow artifact `FentonHome-<version>` (no tests, no Release asset). `version-bump.yml` is folded in. Needs the owner's `release-signing` environment and secrets first: [checklist](.agents/platforms/apple/testflight.md#release-pipeline-owner-checklist).

- **Test speed (owner approved 2026-10-29, [handoff](build/handoff/test-speed.md)):** four lanes. Lane B (tiers and plans) is built: `apple/TestPlans` from `tools/test_plans.py`, `tools/hooks/tier_guard.py`, the tools-only scope class and affected `swift test` in `pr-checks`, a plan-aware parallel-family nightly, `smoke` and `layout_sensitive` in the test map ([test tiers](.agents/testing/apple/README.md#test-tiers)). Lanes A (scripts, watchdogs), C (host suites) and D (journeys, app) are tracked in their own PRs.

## 4. Product backlog

- **Watch app:** target stub only; glanceable status and a handful of controls.
- **Location and device sensors:** the shared `mobile_app` registration is on `main` in shadow mode; next is Phase 3, the device readers and sensors ([location](.agents/platforms/apple/location.md), [mobile-app](.agents/platforms/apple/mobile-app.md)). Native push is built and verified on a real iPhone ([push](.agents/platforms/apple/push.md)). 2026-10-29: departures fixed on branch `claude/location-departure` (monitor opens before the network, cached zones, background time, fresh fixes, exit trusts iOS; [location](.agents/platforms/apple/location.md#departures-2026-10-29)); follow-ups: the `request_location_update` push command, Background App Refresh location, registering the app's sensors. Location parity with the official app: PR A (small-zone circles, graded one-shot fixes, official payload and zone events) on `claude/location-parity-zones`; B (triggers: `request_location_update` push, Background App Refresh every ~15 min, one launch update per foreground session, no stale reading after a fallback exit) on `claude/location-parity-triggers`; C (sensors: `register_sensor` then `update_sensor_states` beside every location update, Last Update Trigger on every update, sensors-only background fetch; #203 minors: late-fix exit race, background time before the zone refresh, cold-launch scene phase) on `claude/location-parity-sensors` ([matching the official app](.agents/platforms/apple/location.md#matching-the-official-apps-location-behavior-2026-10-29)).
- **Owner-deferred:** measured vs felt performance.
- **Duo Back label (found 2026-11-03, settings-motion):** on the folded Duo the pushed page's system Back (`BackButton`) reports an empty accessibility label to XCUITest (iPhone reports one). Not touched by the single-page motion change (the bar is the system's); not yet checked on 66ae0c9f. Give the item an explicit label and add the Duo assertion back in `SinglePageMotionJourneyTests.testPushedPageIsTheOnlyReachablePage`.
- **iPad flyout stays open after choosing a section (found 2026-11-02):** also on 66ae0c9f; item 8 of `.claude/worktrees/uikit-port/build/handoff/dry-run-9998-findings.md`. The iPad single-page journeys skip until it is fixed; `StackMotionTests` cover the iPad-portrait width.
- **Journeys that fail on 66ae0c9f too (classified 2026-11-03, settings-motion):** run with `--env shell --plan Live`, one `-only-testing:` each, evidence in `.claude/worktrees/base-classify/build/runs/base-iphone2.log` and `base-duo.log`. iPhone and folded Duo both fail `NavigationJourneyTests.testCompactNavTabBarItems` ("Chores tab missing", NavigationJourneyTests.swift:75), `testQuickLinksHeaderButtonPresentsTheSheet` ("Flyout open under the sheet", :308), `ShellJourneyTests.testQuickLinksPushesItsPageOnTheCurrentStack` ("Back did not return to Climate", :231) and `testSummarySheetOpensOnSummary` ("The sheet opened on Profile, not the summary", :243); iPhone alone also fails `NavigationJourneyTests.testCompactNavHamburgerOpensFlyout` (:95, no flyout after the hamburger tap), `testEdgeSwipeOpensFlyout` (:229) and `ShellJourneyTests.testTitleIsLargeAtRestAndCollapsesBesideTheMenu` (the title frame is 40.67 pt tall, not under 40; :308). The lane's failures are the same tests with the same messages and lines, so none is a regression of the single-page motion. Each still needs its own fix. (The Settings audit, `testSettingsTabPassesAccessibilityAudit`, was the one regression: the Settings page's footers drew in the system secondary ink; fixed in `UKSettingsStack.swift`.)
- **Hub:** run `tools/mockups_hub.py` and republish the hub Artifact when settings-motion lands, and note it in the merge commit.
- Everything else on the list in the archive is on `main`; check the atlas before assuming a surface is missing.

## 5. Where to look

| Need | Read |
|---|---|
| How to work a change | [change-loop](.agents/workflow/change-loop.md), [propose-first](.agents/workflow/propose-first.md) |
| How a surface looks and moves | [mockup atlas](.agents/design/mockups/README.md) (hub link inside) |
| The rules for a screen or control | [.agents/README.md](.agents/README.md) |
| Why something is the way it is | [.agents/archive/](.agents/archive/README.md) |
