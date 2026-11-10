# Motion

> **What:** the app-wide rules for movement in S+H. They cover the launch and sign-in moments, switching tabs, opening pages and modals, loading, live updates and user actions. They also cover when *not* to animate, how motion is measured, and the components that enforce all of it. **Read when:** you add or change any animation, transition, navigation path, loading state or sheet, or review a PR that does.

Owner decision, 2026-10-18. Design: the canvas **S+H Launch and sign-in motion** (the owner's private mockup gallery, link kept outside the repo), boards 1–11. The pattern record (components, API, tests) is [patterns/motion.md](../patterns/motion.md).

## 1. The idea in one paragraph

S+H is a control panel people open many times a day for a few seconds, so motion has to get out of the way. The **system's own transitions are the motion**: a tab switch is a cut, a page pushes, a modal is a sheet. They behave exactly as they do in Apple's apps, interactive gestures included. On top of that there are only two kinds of animation:

1. **Moments.** A handful of one-time events: the first-launch intro, and the arrival into Home after signing in. A moment plays once and then never again for that session.
2. **Change.** When something actually changes, because you did something or the house did, the changed thing animates briefly in place: a number rolls, a colour cross-fades, a completed row leaves.

Things that merely *appear* do not animate: a tab you return to, a page whose content is already known, a reopened app, data from the saved snapshot. **Animate change, not presence.**

## 2. What iOS does as standard (and we keep)

| Surface | Platform standard | S+H |
|---|---|---|
| Tab switch | A cut, with no transition. Each tab keeps its navigation stack and scroll position. Tapping the selected tab pops to its root, and a second tap scrolls to the top. | Same. No custom tab transitions, ever. |
| Push / pop | The system push: the new page slides in and the old one shifts left and dims. The edge swipe back is interactive. Duration and curve are the system's. | Same, except on the single-page layouts (iPhone, folded Duo, Duo and iPad portrait) of the UIKit port, which use the column motion (owner, 2026-11-02, [single-page-motion](single-page-motion.md)): both pages move a full width on `standard` over one still wallpaper, no dim or shadow, the swipe follows the finger. Otherwise never replaced, slowed or decorated. |
| Modal | The system sheet: it slides up to its detent and the page behind dims (and on iPad it is a centred form sheet). Swipe down to dismiss. | Same, through `hassSheet` ([modal-sheet](../patterns/modal-sheet.md)). |
| Opening the thing a tile shows (iOS 18+) | The **zoom** navigation transition: the source view grows into the destination, which zooms back into its source on close, with a swipe-down or pinch to dismiss. Photos, Music and the App Store use it. | Used where a tile *is* the thing it opens (§4.3). Falls back to the push or sheet on iOS 17. |
| Changing values | `contentTransition(.numericText())`, symbol effects, short state cross-fades. | Same, with the timings in §7. |
| Reduce Motion | Slides, zooms and springs become cross-fades or nothing. | Mandatory everywhere (§8). |
| Loading | Show content as soon as possible, and only show an indicator when a wait is real. | The loading gate ([content-gate](../patterns/content-gate.md)), and only for network-backed pages (§5). |

Sources:
- [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion): "use motion purposefully", "make motion optional", "brief and precise".
- [HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars).
- [HIG Loading](https://developer.apple.com/design/human-interface-guidelines/loading).
- [Enhance your UI animations and transitions (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10145/): the zoom transition.

## 3. Decisions per surface

| Surface | First time this session | Again later | Why |
|---|---|---|---|
| **Launch, signed out** | Intro (board 1): glow → mark springs in → title → form rises, ≈1.2 s | Every launch while signed out | The only time the app introduces itself |
| **Launch, signed in** | No intro. The launch ground cross-fades (≤0.2 s) to the saved screen | Same | Reopen invariant: never blank, re-fade or reorder |
| **Sign in → Home** | Arrival (board 2): the sign-in screen lifts away, the house photo fades in, the title and chips arrive, the tiles rise with a 60 ms stagger (first screenful only), the tab bar rises; ≈0.8 s | Once per session; a second sign-in after a sign-out plays it again | A moment worth marking |
| **Tab switch** | Cut | Cut | Standard; switching tabs is navigation, not an event |
| **Tab root content** | Already there (snapshot or live) | Already there | Presence, not change |
| **Push to a page** | System push | System push, every time | The push is how you know where you went; it is cheap and interactive |
| **Pushed page's content** | Already there | Already there | Presence |
| **Tile → its own page or viewer** (room, camera, recipe) | Zoom (iOS 18+) | Zoom, every time | It is navigation feedback, like the push |
| **Modal sheet** | System sheet; the content is there on arrival | Same | Standard |
| **Modal sheet with the sheet reveal** (opt-in, `UKHassModalOptions.reveal`; owner 2026-11-05) | The sheet slides up with its content hidden; when the slide ends the content fades in together (0.2 s). Only content that is not ready gets the centred arc first ([sheet-reveal](sheet-reveal.md)) | Same, on every presentation; never on a reconnect, reapply, fold or push | The owner's requested reveal; an arc only for a real wait |
| **Network-backed page or sheet with nothing saved** | Loading gate: spinner after 150 ms (`.page` profile per the owner: ≥1 s, then 500 ms out), content fades in and rises 4 pt | Saved results show at once; fresh data swaps in quietly | Animate only what had nothing to show |
| **Live value change** | Numbers roll (0.2 s); background and tint colours cross-fade (`state`, 0.6 s) | Same | Change |
| **User action** (toggle, complete, delete, reorder) | Optimistic change at once; rows insert or remove with the standard list animation | Same | Change the user caused |
| **Resume, reconnect, snapshot load** | Nothing animates | Nothing | Presence |

### What "again later" means

The rule for a screen's first visit versus a revisit is not "first visit animates". It is this: **a screen animates in only when it had nothing to show.** In practice:

- **Tab roots** never animate in. Their content is always there, from the snapshot or live data, and the tab switch itself is a cut.
- **Navigation transitions** (push, pop, sheet, zoom) run every time. They are the system's feedback for a move the person made, they are short, and they can be interrupted. Suppressing them on revisits would feel broken.
- **Content entrances** (fade-ins, rises, staggers) run only when there was a wait. A page whose content is in memory or the saved snapshot shows it at once, on any visit.
- **Moments** play once per session. `MotionPolicy` remembers what has played. "Session" means from signing in (or a cold launch while signed in) until the process ends or you sign out.

Exceptions must be written into this file with the owner's say-so. **Exception (owner, 2026-11-05, [sheet-reveal](sheet-reveal.md)):** a modal that opts into the sheet reveal fades its root page's content in together when its presentation completes, on every presentation, even when the content is in memory. It is one fade (0.2 s, no rise, no stagger), it runs once per presentation, and never on a reconnect, a snapshot reapply, a pose change or a push.

## 4. Navigation details

### 4.1 Tabs
- **The bar:** the system tab bar, or our custom bar driving it, switches with no animation on the content. The selection highlight may move with the system's own bar animation; never add a page slide or fade.
- **Re-tapping the selected tab:**
  - **First tap:** pops the stack to the root, using the system pop.
  - **Second tap, when already at the root:** scrolls the main scroll view to the top (`scrollTo` on the page's top anchor, animated with the system scroll). This is standard UIKit behaviour; a custom tab bar must reproduce it.
- **State:** each tab keeps its own path and scroll position (`MainTabView` holds a path per section). Switching never resets or re-fetches, so returning to a tab shows exactly what was there.

### 4.2 Pages (push)
- **Navigation:** `NavigationStack` with `navigationDestination` only. No `.transition`, no custom `NavigationTransition`, and no matched geometry on push, except the zoom in §4.3.
- **UIKit port exception (owner, 2026-11-02, [single-page-motion](single-page-motion.md)):** the section stacks (`UKSectionNavigationController`) return `UKStackMotion`'s animator instead of the system push, whenever the section's columns are not active. Both pages move a full width on `standard`, with no dim, shadow or fade, over the one wallpaper behind the tab controller; the edge swipe follows the finger (complete past half or at 600 pt/s, else reverse). Back, the swipe and re-tapping a tab all use it. Nothing else about §4.2 changes.
- **Destination content:** a destination must render its content in its first frame. It reads `EntityStore` synchronously. It must not start a fade or a cascade in `onAppear`.
- **Heavy work:** a destination that needs heavy setup (camera streams, maps) starts it after the transition settles (`.onAppear` plus `Task { await Task.yield() }`, or the `transitionSettled` callback in §9). That keeps the push smooth.

### 4.3 Zoom (iOS 18+)

**Use it when** the tapped view *is* the thing that opens:
- a room tile opening its room page;
- a camera card opening the camera viewer;
- a recipe card opening the recipe;
- a photo or map thumbnail opening its full view.

**Don't use it for:**
- a row in a list (push);
- a chip opening an overview sheet (sheet);
- anything inside a sheet, such as a room tile in the room overview sheet: the zoom hides the sheet's content while its backdrop stays blurred, then the page appears (owner, 2026-10-22). Pushes inside a sheet are plain pushes;
- device tiles that open control sheets (sheet: the tile is a control, not a thumbnail of the sheet);
- buttons.

**Implementation:**
- The source gets `.zoomSource(id:in:)`; the destination gets `.zoomDestination(id:in:)`. Both are `MotionPolicy` helpers that wrap `matchedTransitionSource` and `navigationTransition(.zoom(sourceID:in:))` behind `#available(iOS 18, *)`, and do nothing on iOS 17.
- The source's corner radius must match the tile's (26 pt), so the morph is clean.

### 4.4 Modals
- **Presentation:** always through `hassSheet` and its detents. A full-screen viewer that a tile opens may use the zoom with `fullScreenCover`. Everything else is a sheet.
- **Content:** sheet content is present on arrival. A sheet that loads from the network uses the loading gate inside the sheet, never a spinner sheet. **Exception (owner, 2026-11-05):** a modal that sets `reveal: .gate(.sheet)` holds its root page's content hidden during the slide and fades it in together when the slide ends. The centred arc appears only if the content is still not ready 150 ms later ([sheet-reveal](sheet-reveal.md), [content-gate](../patterns/content-gate.md) "Sheet reveal").
- **Inner motion:** no entrance animations inside sheets (no tiles rising, no tabs sliding, no per-tile or per-glyph entrance; the sheet reveal is one fade of the whole content). Switching a sheet's own tabs (`modalTabBar`) is a cut, like the app's tab bar.

## 5. Loading and waiting
- **One spinner design:** the `ArcSpinner`. It only appears where something is genuinely pending:
  - in the button you pressed ("Signing In…");
  - in a loading gate for network content with nothing saved.
- **Never full-screen.** There is no full-screen or app-wide spinner, and no spinner while live house data loads (the snapshot covers it).
- **First sign-in placeholders:** on the first sign-in only, before any snapshot exists, tiles show their names at once, with a soft pulsing bar (opacity 0.35 ↔ 1, 1.4 s) where the value will go.
- **Connection lost:** a white arc spinner fades in left of Quick Links (no text), but only after 2 s down, so a quick blip never shows it, and fades out when live again. Values stay on screen. See [reconnecting-spinner](reconnecting-spinner.md).
- **No shimmer:** no skeleton sweeps (moving gradients). They cost a full-screen animated pass and say nothing a pulse doesn't.

## 6. Live updates and user actions
- **Numbers:** `contentTransition(.numericText(value:))` with `MotionTokens.quick`.
- **Background colour changes are always animated (owner, 2026-10-18).** Whenever a component's background, fill, tint, rim or material colour changes because its state changed (house-caused or user-caused), it cross-fades with `MotionTokens.state` through `.stateColorTransition(value:)`. That covers tiles lit/unlit, chips filled/unfilled, pills changing tone, selected segments and day chips, alarm panels turning triggered, button active states and more. The timing is the status chip's, which the owner approved (0.6 s ease-in-out, 0.2 s under Reduce Motion). Only the colour animates; layout never rides along. Every component and its status is listed in [motion-components.md](motion-components.md).
- **Layout:** live updates never move layout. No re-sorting a grid because a value changed, and no resizing tiles. If an order must change (a new chore assigned), apply it without animation unless the person caused it.
  - *Exception: a settings row that appears or disappears with another setting (owner, 2026-10-28, [vacuum-sheet-redesign](vacuum-sheet-redesign.md)).* The vacuum's Water row (Mode without mopping) and Fan row (Mode Mop) are person-caused layout: the row's height animates with `MotionTokens.standard`, its content fades with `MotionTokens.quick`, and the group, the footer and the Clean button simply resize and slide below it. Same guard rails as the tile exception below, except that a change arriving while the sheet scrolls applies at once instead of waiting (only a change made elsewhere can arrive mid-scroll): never on a reconnect or a snapshot reapply, Reduce Motion cross-fades in place and changes the height at once (`VacuumShapeMotion`). Ships with `LayoutChange` signposts (`Vacuum.settingRows`, `Vacuum.target`) and `testVacuumSettingRowCost`.
  - *Exception: a tile's action set changing (owner, 2026-10-26, [action-tiles](../patterns/action-tiles.md)).* A remote starting to play adds transport and a volume slider below its text, and stopping removes them. The tile animates its height with `MotionTokens.standard` and the discs fade with `MotionTokens.quick`. Guard rails, all enforced in `TileActionSetTransition`: full-row tiles only (a half-row tile's neighbour would move); deferred while the page scrolls (`pageIsScrolling`; on iOS 17, which cannot report scrolling, it never fires); never on a snapshot or reconnect reapply (`EntityStore.reapplyGeneration` changed since the tile appeared, so a cold launch or a reconnect never animates); Reduce Motion replaces the height animation with a 0.2 s cross-fade. It ships with a `LayoutChange` signpost (page `TileActionSet`) and `LayoutChangePerformanceTests.testRemoteActionSetChangeCost` (`tools/ios_motionperf.sh --only iphone`).
- **User actions:**
  - The optimistic change happens at once ([optimistic-actions](../patterns/optimistic-actions.md)).
  - Rows the person adds, completes or deletes animate with the standard `List` or `withAnimation(MotionTokens.standard)`.
  - A failed action animates back.
- **Symbols:** `symbolEffect` is fine for a confirming change (e.g. `.bounce` once on a completed check). Never use repeating effects except a live "pending" state.

## 7. Tokens (`HassDesign/Motion/MotionTokens.swift`)

| Token | Value | For |
|---|---|---|
| `quick` | `.easeOut(duration: 0.2)` | Numbers, small fades, button state |
| `state` | `.easeInOut(duration: 0.6)`, reduced `.easeInOut(duration: 0.2)` | Every background, fill, tint and rim colour change (the status chip's approved timing) |
| `standard` | `.smooth(duration: 0.3)` (no bounce) | Layout a person caused: rows in or out, expanding sections |
| `emphasized` | `.spring(duration: 0.5, bounce: 0.2)` | The house-and-heart mark in the intro, nothing else |
| `segment` | `.snappy(duration: 0.2)` | The selected capsule gliding between a modal's tabs (`BadgedTabSegment`) |
| `contentFade` | `.easeInOut(duration: 0.15)` | One panel's content cross-fading when its own tab changes (`SummaryPanel`) |
| `arrivalStagger` | 0.06 s per item, first screenful only (`Arrival.staggerLimit`, 5 items) | The sign-in arrival |
| `gate` | per [content-gate](../patterns/content-gate.md) (`.results`, `.page`, `.sheet`; `.sheet`'s fades are `quick`'s 0.2 s) | Loading gate and the sheet reveal |
| `Ticker` | 30 pt/s, 1.5 s holds, 0.3 s return, 3 passes, 12 pt edge fades (`MotionTokens.Ticker`) | A label too wide for its column (the Home weather card's condition, the page title in the navigation bar), see the exception below |
| Navigation | system | Push, sheet, zoom, tab |

**Never:**
- durations over 0.4 s, except the two moments and colour cross-fades (`state`): nothing moves in a colour fade, so it never delays a tap;
- `bounce` above 0.15;
- `repeatForever`, except spinners and pending pulses.

## 8. Reduce Motion

Read `accessibilityReduceMotion`, through `motionSafeAnimation` or `MotionPolicy.reduceMotion`, and apply:

| Motion | With Reduce Motion |
|---|---|
| Moments (intro, arrival) | Cross-fade only, ≈0.35 s total; no rise, scale, spring or stagger |
| Zoom | The system already turns it into a cross-fade; nothing to add |
| Push (single-page layouts of the UIKit port) | A 0.2 s cross-fade in place, no slide; the swipe back still pops and scrubs the fade ([single-page-motion](single-page-motion.md) S4). The columns do the same |
| Sheet | The system handles it |
| Numbers | The numeric transition is allowed (it is a content change). Under Reduce Motion it can become a plain cross-fade |
| Colour changes | Still cross-fade (colour is not motion), at 0.2 s |
| Pulses and spinners | Spinners keep turning (they carry meaning). Placeholder pulses become static |

## 9. Overkill: what we don't do

1. **Animating tab switches** (slides, fades, page curls), or animating tab content on every visit.
2. **Cascades everywhere:** staggered tiles on every page, sheet or tab. The stagger happens once per session, on arrival into Home.
3. **Entrance animations for content that was already there:** cached pages, snapshot loads, resume, reconnect.
4. **Bouncy springs on content:** tiles that overshoot, cards that wobble.
5. **Decorating the system transitions:** custom push curves, parallax headers on push, 3D flips, hero animations on things that aren't thumbnails. (The one owner-approved replacement is the single-page push of §4.2: the columns' motion, nothing added to it.)
6. **Long durations:** anything that moves for over 0.4 s outside the two moments, and any chained sequence that makes you wait to tap. *Exception: the label ticker* (below).
7. **Blocking input during animation:** every transition is interruptible, and taps during the arrival go through.
8. **Animated backgrounds:** moving gradients, animated blur radii, particle effects, shimmer sweeps. They are expensive (offscreen passes every frame) and noisy.
9. **Live updates that move layout:** re-sorting, resizing or jumping while the person is reading.
10. **Animating what's off screen,** or animating anything while the person scrolls. *Exception: the label ticker* (below), which is bounded by the pauses listed there.

**The ticker exception (owner, 2026-10-22).** A label that does not fit its column scrolls through it at a constant 30 pt/s instead of truncating or wrapping ([ticker](../patterns/ticker.md), [weather card header](weather-card-header.md)). It is the one motion allowed past 0.4 s outside the two moments, and the one that moves for seconds at a time. It is allowed because it is bounded:
- it runs only while the label overflows its column (measured, never keyed to a string or a size), and plays three passes (1.5 s hold, travel, 1.5 s hold, 0.3 s return) after the card appears or the text changes, then rests at the start;
- it pauses while the page scrolls, while its view is off screen or behind another tab, and while the scene is not active, and resumes where it stopped;
- under Reduce Motion it does not run: the text wraps instead;
- it never moves layout (a clipped, masked overlay on a fixed-size line), and its text is hidden from VoiceOver;
- it ships with the `TickerRun` signpost, a hitch and scroll-cost test, and budgets ([performance](../testing/apple/performance.md)).

Tiles are a consumer (owner, 2026-10-26, [action-tiles](../patterns/action-tiles.md)): a tile's title or state line becomes a `TickerLabel` only when the tile already spans its whole row or side (`spanIsCapped`) and the line still overflows. Every rule above applies unchanged.

It is not a precedent for other marquees: add another only with the owner's approval and a row here.

**Why this is the line:** each of these either costs frames on a 120 Hz screen we've worked hard to keep smooth (see [performance](../testing/apple/performance.md)), or makes a two-second task slower without telling the person anything new.

## 10. Measuring motion

Motion is instrumented like scrolling. Every rule above has a number that can regress.

- **Signposts** (`HassTelemetry`, subsystem `com.sfenton.home`, category `Performance`):
  - **Navigation, from the tap to the destination's first frame and to "settled":**
    - `TabSwitch`
    - `Push`
    - `Pop`
    - `SheetPresent`
    - `SheetDismiss`
    - `ZoomOpen`
    - `ZoomClose`
  - **Moments:** `Intro` and `Arrival`.
  - **Layout changes:** `LayoutChange` (`measuresMotion`), the page named in the interval: a row inserted, a section swapped, a badge faded. Runner: `tools/ios_motionperf.sh`.
  - **Launch:** `Launch` (process start to first frame) and `SnapshotShown`.
  - **Network:** `ContentReady` (already exists) and `Reconnect`.
- **How intervals are recorded:**
  - **Begin:** the intent (the tab tap, the `NavigationLink` or path append, the sheet binding set).
  - **"First frame":** recorded on the destination's first `onAppear` plus the next display-link tick.
  - **"Settled":** recorded when the transition completes (`UINavigationController` delegate's `didShow`, or the sheet's `onAppear` after its presentation animation).
  - `MotionPolicy.measure(_:)` wraps this so call sites stay one line.
- **Simulator budgets** (CPU, through `MainThreadCostMeter`; simulator hitch ratios are false, see [performance](../testing/apple/performance.md)):

  | What | Budget |
  |---|---|
  | Each transition | p95 run-loop turn ≤ 8 ms, no turn over 16 ms |
  | Tab switch tap → first frame | ≤ 50 ms p95 |
  | Push tap → settled | ≤ 600 ms |
  | Sheet present → settled | ≤ 600 ms |
  | Arrival | ≤ 1.0 s |
  | Warm launch → `SnapshotShown` | ≤ 400 ms |
- **Device budgets** (physical device only; the tests skip on simulators):
  - `XCTOSSignpostMetric.navigationTransitionMetric` and custom signpost animation metrics for push, sheet and zoom;
  - hitch ratio < 5 ms/s, Apple's "good".

  Device runs need the owner's say-so before the planner starts them.
- **Tests:** `NavigationPerformanceTests` (UI test target):
  - a tab cycle (each tab × 3);
  - push and pop a room page × 10;
  - open and close a device sheet × 10;
  - zoom open and close a room × 10 (iOS 18+);
  - sign in → Home once.

  Runner: `tools/ios_navperf.sh`, simulator, inside devcap holds. It prints the per-interval p50 and p95 and the turn costs.
- **In the app:** Settings → Performance gains a "Navigation" section (per surface p50/p95 and hitch ratio from real use), and Export Telemetry includes it.

## 11. Checklist for a PR that touches motion

1. Which row of §3 does it fall in? If none, update this file first, with the owner's approval.
2. Is it presence or change? Presence doesn't animate.
3. Does it use system navigation (`NavigationStack`, `hassSheet`, zoom helpers), with no custom transitions?
4. Does it use `MotionTokens` and `motionSafeAnimation`, with no raw durations and no `.animation(_:)` without a value?
5a. Does every state-driven background or tint colour go through `.stateColorTransition(value:)`, with a row in [motion-components.md](motion-components.md) and its test?
5. Does it respect Reduce Motion? Test it with Reduce Motion on.
6. Does it add or update the signpost and keep within the budgets in §10? Is the perf test updated?
7. Does it stay interruptible, with nothing blocking taps?
