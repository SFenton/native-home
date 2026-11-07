# Audit

> **What:** the 2026-10-13 pass over everything merged to `main` (#1 to #29): shared components, redundant code, and the SwiftUI Pro rules. **Read when:** you need the evidence behind a rule, not to learn the rule.

> **Archived 2026-10-28.** A point-in-time audit; its dedup plan is finished or tracked elsewhere. Its standing rules moved to [patterns/README.md](../../patterns/README.md#reuse-rules).

Ran at `d9548ba` and `5c78202` with four read-only reviewers, then checked by Opus. Every finding below has file:line, identical-vs-different notes, a proposed home and a risk in its file.

| File | Covers |
|---|---|
| [hasscore.md](hasscore.md) | Logic in `HassCore` |
| [ui.md](ui.md) | Views, tokens and gallery fakes in `HassUI` and `HassDesign` |
| [swiftui-pro.md](swiftui-pro.md) | The [SwiftUI Pro](../../workflow/swiftui-pro.md) rules over `apple/Sources` |
| [tests.md](tests.md) | Journeys, test doubles, gallery recorders, `tools/` |
| [token-burn-2026-10-22.md](token-burn-2026-10-22.md) | Where Claude usage went Oct 10 to 22 (polling, long sessions, model routing, test loop) and the fixes |

## Verdict

Components are **not** being shared well. Agents reused the canonical pattern components where a pattern record existed (grids, tiles, the option picker), but anything without one was rebuilt per feature. The worst cases:

- **Logic.** `titleCase` has 9 variants with 3 behaviors, `isUnavailable` about 12, and there are 7 JSON-number parsers and 7 date parsers. The controller shell (in-flight tracking, `waitForCalls`, `observeLive`, optimistic commit and rollback) is copied into 9 to 11 controllers. Two protocols under two names (`callServiceWithResponse`, `callServiceForResponse`) sit on six hand-written websocket bridges.
- **Views.** There are 9 notice/alert views over about 55 call sites. Section headers have 14+ variants, and four of them drop `Ink.primary`. There are three tab pickers, a light/dark color helper pasted 5 times, and the same green declared 8 times.
- **Sheet chrome.** About 20 copies of NavigationStack + inline title + Done, and 4 copies of the presentation modifier. The docs name a "HassSheet" chrome that does not exist.
- **Tests.** The 23 journey files share no base class, so the iPad orientation `setUp` is pasted 23 times and has already drifted. About 10 service-call fakes and 8 copies of `makeConnection` exist because the two SwiftPM test targets cannot share code. Two copies of the screenshot handshake still carry a late-capture bug that the shared copy fixed.
- **Release builds.** 14 of 17 gallery files (about 2,700 lines of fixtures) have no `#if DEBUG`.

The SwiftUI Pro deprecated-API rules are clean: no `foregroundColor`, `NavigationView`, `ObservableObject`, one-parameter `onChange` or non-private `@State`, and every `@Observable` class is `@MainActor`. Its real findings are behavioral:

- 7 user actions swallow service errors with `try?`.
- 7 `ForEach`s use index identity, including a Sprinkler list that removes by index.
- 6 slide animations have no Reduce Motion fallback.

## Plan and owners

The audit thread lands the dedup in small PRs, one concern each, rebased on `main` before each push. Feature threads own fixes inside their own screens; the App chrome thread owns sheet chrome.

| # | Change | Owner | Status |
|---|---|---|---|
| 1 | Move infra types out of feature folders (`ServiceCall`, `HassServiceCalling`, `HassServiceResponding`, `OptimisticOverlay`, `HassServiceCatalog`, `JSONValue(haData:)`); one `StateText.titleCase` and `EntityState.isUnavailable(_:)` | Audit | Done (#32) |
| 2 | One JSON-number parser and one `HassDates` with cached formatters | Audit | Done (#34) |
| 3 | One websocket command bridge (`HassConnection.sendCommand`); `TodoServicing` refines `EverShelfCalling` (#40) | Audit | Done |
| 4 | Controller shell: superseded by `OptimisticActions` (#36, [optimistic-actions](../../patterns/optimistic-actions.md)); controllers move over when their owner next touches them | Feature threads | Reported |
| 5 | Shared entity ids defined once (#56); per-room tables in `RoomsConfig`/`RoomGroups` still restate `Config/` ids | Audit | In progress |
| 6 | Notices: one `InlineAlert` with warning and error severities (#58, #61); Form section text via `FormHeader`/`FormFooter` (#63); section headers into `SettingsSection`; `BedroomTabPicker` into `SheetTabPicker`; color tokens into `HassTokens` | Audit | In progress |
| 7 | Gallery: `#if DEBUG` on every gallery file (#41); one Last-call view (#54); one recorder base | Audit | In progress |
| 8 | Journey base class `JourneyTestCase` (#51; other journeys move over when touched); dead `coverage_gate.py` XML branch removed (#52); `HassTestSupport` doubles (#53) | Audit | Done |
| 9 | Sheet chrome, presentation modifiers, `SheetTabPicker` API | App chrome thread | Reported |
| 10 | `try?` on user actions, index identity, Reduce Motion in feature screens | Each feature's thread; Sprinklers, Recipes and Inventory done by Audit (#33) | Reported |
| 11 | Hosted tests that fail only in a full `swift test` on a loaded Mac: `SecurityViewTests.galleryRecorderEchoes`, `OnDemandSplitHostedTests` (frame and placeholder checks). They pass when run alone. Fixed at the source (settle by passes, tolerant render comparison, the camera first-frame timeout race); rules in [testing](../../testing/apple/README.md#order-independent-tests). `galleryRecorderEchoes` did not recur in four full runs | Audit | Done |
| 12 | `FoodJourneyTests.testHubShowsSuggestionsRecipesAndSpaces` fails its iPhone audit (since the Food lane): the audit flags all 9 suggestion `ImageCard`s, each one `StaticText` with the whole-card frame (175×193) on `.regularMaterial`, and the helper loses their elements after the second, scrolling pass. Needs text-region sampling in `RenderedContrast` or `ImageCard` exposing its title as its own framed element; not a whole-frame waiver (#55 closed). Direction G lane 5 makes the caption the card's only element, framed to the text over its scrim | Fix in review | Reported |
| 13 | `FoodJourneyTests.testFilterSheetPassesAccessibilityAudit` fails on iPad only (portrait, on main `c5240c3`): "0 of 12 sampled texts on the AX5 page" and 3 element-less Dynamic Type issues. The AX5 relaunch does not show the filter sheet's texts where the page check looks for them, so nothing can be compared | Open | Reported |

## Rules this audit adds

- Before writing a helper, grep `HassCore/Entities`, `HassCore/Connection` and `HassDesign` for it. Feature folders hold feature logic only; infrastructure types live in those three places.
- A second copy of anything in this audit is a major review finding. Extend the shared one instead.
- Every file in `HassUI/Features/Gallery` is wrapped in `#if DEBUG`. Production code reaches the galleries only through `ComponentGallery.requested` and `galleryLastCallBanner()`, which is a no-op in Release.
- Journeys subclass `JourneyTestCase` ([devices](../../testing/apple/devices.md)).
- Warnings and errors use `InlineAlert`; Form section headers and footers use `FormHeader`/`FormFooter` (the system secondary label is about 3.3:1 on the sheet background).
