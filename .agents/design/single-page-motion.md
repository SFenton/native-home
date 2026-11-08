# Single-page motion

> **What:** how pages push and pop on the single-page layouts (iPhone, folded Duo, Duo and iPad in portrait), chosen 2026-11-02 so they move like the unfolded columns. **Read when:** you touch push, pop, the swipe back, a navigation controller's delegate, or anything that draws the wallpaper.

Mockup: [single-page-motion.html](mockups/proposals/single-page-motion/single-page-motion.html) (device switch, Play for push, sub-push, pop, swipe back that completes and one let go early, tab switch with re-tap, Reduce Motion, a slider that holds the first push at any point). Research and the Designer's recommendation: `DRY-9998`, 2026-11-02.

## Owner request and decision

Owner, 2026-11-02: "I really like the smooth transitions when Duo is unfolded in Settings, when I click an element, then a sub-element, and I see pages and sub-pages smoothly enter and exit. However, in folded/portrait/iPhone, I still see pages transition in individually, swapping the background, etc. Can we bring that smooth transition to the single-page layouts as well? How would shared background work with tab navigation?"

**Pick: option B**, the columns' motion with one column, on every section, after a Settings spike; A2 (the system push plus fading the old page) was the fallback if the spike could not make the navigation bar, the flyout's edge swipe or the iOS 26 content swipe clean. The Settings spike was clean on the iPhone (frame sheets below), so B shipped on every section. Edge-only swipe back on iOS 26 for now.

| Option | What the owner would see | Outcome |
|---|---|---|
| Today | Each page slides in with its own wallpaper; the old page shifts 30%, dims and casts a shadow, so the backdrop appears to swap | Rejected: it is the complaint |
| A | One still wallpaper, system push kept; transparent pages ghost through each other and the dim darkens a moving band of wallpaper | Dropped: ghosting is certain |
| A2 | A, plus the old page fades while it moves | The fallback; not needed |
| **B** | One still wallpaper; the new page enters from the trailing edge while the old one leaves by the leading edge, a full width each, `standard` (smooth spring 0.3 s), no dim, shadow or fade; Back reverses; the swipe follows the finger | **Chosen** |
| C | Settings only, a one-column mode of the columns controller | Rejected: two motion languages and the system Back, swipe and large title replaced in one section |
| D | iOS 18 zoom from the row | Rejected: wrong shape for a list row ([motion §4.3](motion.md)), iOS 18 only |

## Rules

- **S1. One wallpaper per window, pages transparent on every layout.** `UKShellViewController` draws the only `UKBackdropView` (the gallery host draws it for gallery pages). No page, tab controller, section controller or transition container paints a ground. `UKPageViewController` never creates a backdrop; sheets keep theirs ([page-backdrop](../patterns/page-backdrop.md) R2, R4).
- **S2. Push and pop on single-page layouts use the column motion.** `UKStackMotion` (`App/Shell/UKStackMotion.swift`), returned from `UKSectionNavigationController`'s delegate whenever the section's columns are not active: both pages move a full width on `UKMotion.Token.standard`, the new page from the trailing edge, the old one out by the leading edge, with no dim, shadow or fade. Back reverses it.
- **S3. The swipe back follows the finger.** A `UIScreenEdgePanGestureRecognizer` on the section's view drives a `UIPercentDrivenInteractiveTransition`: 1:1 with the finger, completes past halfway or at 600 pt/s, otherwise reverses. It replaces `interactivePopGestureRecognizer`; on iOS 26 the content swipe (`interactiveContentPopGestureRecognizer`) is off, so the gesture is the same on every OS. It does not begin on the root (that edge is the flyout's) or on a page with `hidesBackButton`.
- **S4. Reduce Motion.** The slide is a 0.2 s cross-fade (`quick`) in place; the swipe still pops and scrubs the fade. The columns do the same (L1 below).
- **S5. Tabs are a cut.** One wallpaper sits behind the tab bar controller and never moves, re-renders or cross-fades. A tab switch only changes the page on top ([motion §4.1](motion.md): no custom tab transitions). Each tab keeps its stack and scroll position. Re-tapping the selected tab pops to the root with the Back motion and a second re-tap scrolls to the top. Per-tab wallpapers are rejected: they render the photo several times and bring back the swap on a tab switch.
- **S6. Signposts and a perf test.** `Push` and `Pop` intervals (`NavigationTelemetry`) wrap the new transition; `NavigationPerformanceTests` and `tools/ios_navperf.sh` measure push and pop cycles. The default budgets are unchanged ([motion §10](motion.md): p95 turn 8 ms, none over 16 ms). One per-page exception: the Settings → Performance page build has a worst-turn budget of 100 ms (measured 73 to 77 ms against 139 ms on the base 66ae0c9f; its p95 stays inside 8 ms), set in `NavigationPerformanceTests` and recorded in [performance](../testing/apple/performance.md).

## L1: the columns under Reduce Motion (a finding, fixed with this change)

Under Reduce Motion the columns still moved the pages that stay on screen between columns (0.2 s, `reduced: .quick` drove the frames), and the leading-edge pan was off. Now surviving pages jump to their place and only opacity animates, and the edge swipe stays enabled.

## What changed in the code

- `UKStackMotion` (animator, interaction, edge pan) replaces the system push and pop for the section stacks and the gallery host.
- Per-page `UKBackdropView`, `trackWindowPosition(during:)` and its display link are gone; the shift rule went with them.
- Tab, section and transition containers are cleared so the shell's wallpaper shows through.

## Tests

`SinglePageMotionJourneyTests` (iPhone and folded Duo; the iPad skips because its flyout never closes after a section is chosen, which fails the same way on the base 66ae0c9f and is tracked as item 8 of the port lane's findings (`/Users/dev/repos/<private-app-repo>/.claude/worktrees/uikit-port/build/handoff/dry-run-9998-findings.md`), so the animator, swipe and one-wallpaper rules are proved there by the hosted tests): push, sub-push, pop, swipe back completed and let go early, a tab switch that keeps each stack, Reduce Motion, AX5, the pushed page the only reachable page, and the wallpaper at every edge while a page moves (animations run twenty times slower so the samples fall inside the move). `StackMotionTests` (hosted): the animator completes, cancels and cross-fades, the interaction thresholds, exactly one backdrop view in the window at rest and mid-push, the columns' Reduce Motion path. `NavigationPerformanceTests.testSettingsPushAndPop…` for the cost. Evidence: a frame sheet per move before and after, in `build/evidence/settings-motion/`.

## Spike result (2026-11-02)

Frame sheets of Settings → Performance on the iPhone simulator, 10 fps from the screen recording, before and after: the old page left by the leading edge and the new one came in from the trailing edge with one wallpaper that never moved; no dim, no shadow; the large title "Performance" did not jump; the bar's Back and refresh items settled with the page. The edge swipe (completed and let go early), the Back button, the tab switch that keeps each stack, Reduce Motion and AX5 passed on the iPhone and the folded Duo. The flyout edge pan only acts at a section root and the pop pan only begins deeper, so they never compete. The iOS 26 content swipe is switched off in code; this was verified by the hosted tests on the iOS 27 simulator only (no iOS 26 runtime available).
