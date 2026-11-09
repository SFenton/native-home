# Content gate

> **What:** how a page waits for its content before showing it. **Read when:** a page or sheet loads data asynchronously (a service response, a REST fetch, images), not when it reads `EntityStore`.

- **Decided 2026-10-24 (`proposals/loading-states` section 1): show content as soon as possible.** Only the region that waits gets an arc. The Food hub (tiles show at once; the Suggested Recipes carousel keeps placeholder cards and a "Finding suggestions" arc), the inventory pages (title and Scan Item live; rows already loaded this session show at once; an arc sits where rows will land) and the media remote (every control, Power included, is live; app tiles fade their artwork in) no longer use a gate. Recipes still gates its results region, which truly has nothing to show. Name the arc for what it waits for ("Finding suggestions", "Loading Pantry"), never a bare "Loading". A page that reads `EntityStore` is never gated.
- **Component:** `ContentGate(page:isReady:timing:reloadTiming:label:content:)` (`HassDesign/Loading/ContentGate.swift`). Web source: the recipe results region phases (`ha-sfenton-react-dash@f5a7bf9:src/components/hass/recipes/useRecipeCollection.ts:47-49`, `src/pages/RecipesPage.module.css`).
- **Sequence:**
  1. While loading, the content is laid out but hidden (opacity 0, no hit testing, hidden from VoiceOver).
  2. A centered spinner labeled "Loading" fades in after 150 ms, so a fast load never flashes it.
  3. Once `isReady` is true **and** every reported piece of content is ready, the spinner fades out (140 ms). The content then fades in and rises 4 pt (170 ms; Reduce Motion keeps the fade and drops the rise).
  4. When `isReady` goes back to false (a new search, a reload), the content fades out (170 ms) and the sequence repeats.
- **Timing profiles** (`ContentGateModel.Profile`, owner, 2026-10-16: "graceful spinner fade-in → content loads → spinner fade-out → content fade-in (no pop)"):
  - `.results` (default): the recipe results region above, for a region that reloads in place (search, sort, filter).
  - `.page`: a page's first cold load, ported from the web's `DashboardPageLoadGate` (`ha-sfenton-react-dash@9ac2a46:src/components/shell/DashboardPageLoadGate.tsx`, `src/constants/loading.ts`, `DashboardPageLoadGate.module.css`): the spinner fades in at once (200 ms) and stays at least 1 s from the start (`DASHBOARD_MIN_LOADING_MS`), fades out over 500 ms (`DASHBOARD_LOADING_EXIT_MS`), then the content fades in over 170 ms and rises 4 pt. Data that never arrives shows the content after 10 s (`DASHBOARD_PAGE_LOAD_TIMEOUT_MS`).
  - Pages pass `timing: .page, reloadTiming: .results`: the first load is the web's, later loads (a search) are the quick results ones. A page whose data is already there (a reopen) starts ready and shows at once. Food hub (ready once Suggested Recipes settled), Recipes (first page) and the six inventory pages (first rows) use it. Controls that must survive a reload (the floating search) stay outside the gate; controls that belong with the content (the inventory's Sort, Filter, Scan Item) go inside, so they fade in with it.
- **Form sheets that load (owner, 2026-10-30):** the Edit Task sheet follows the web's sequence on every form factor (one behaviour, decided with `apple-hig` Loading/Sheets and `design-skills:interaction-design`): the sheet opens at a pre-determined size (see `modal-sheet.md`, "Task form size"), the `.page` gate fades the arc in, fades it out when `get_task` answers, then fades the form in (`ContentGate` in `DonetickTaskSheet`, `UKContentGateView` in `UKDonetickTaskViewController`; MotionTokens-free, the gate's own profile; Reduce Motion drops the 4 pt rise). A failed load counts as ready, so the arc gives way to the failure message; a new task, a restored draft (fold or rotation) and a reopened form start ready and show at once. Web: `ha-sfenton-react-dash@7c4ebf9:src/components/hass/DonetickTaskFormPage.tsx:69` (`DashboardPageLoading`), `src/components/shell/DashboardPageLoading.module.css:1-9` (500 ms exit).
- **HIG departure (recorded 2026-10-16):** HIG Loading says to show content as soon as possible, but the owner asked for the web's sequence on cold page loads, so `.page` holds the spinner for at least 1 s and fades it out over 500 ms even when the data is already there. HIG wins everywhere it can: a page whose data is already there starts open, results reloads use `.results` (no minimum), and the gate posts a VoiceOver `layoutChanged` when the hidden content appears.
- **Readiness of children:**
  - `CachedImage` (and so `RemoteImage` and `ImageCard`) reports itself, so a gated grid waits for its visible images.
  - Anything else can report with `.contentReadiness(id, isReady:)`.
  - The gate stops waiting after `ContentGateModel.Timing.childTimeout` (1.5 s), so one slow image never holds the page.
- **No reload on reopen:** a gate created with `isReady == true` shows content immediately, with no spinner and no fade. Pass the cached or snapshot state as ready. Never gate a page that reads `EntityStore`: the store is always ready from the disk snapshot.
- **Telemetry:** each cold load is a `ContentReady` interval named by `page`. Instant shows are counted (`gate.instant`).
- **Tests:**
  - `Tests/HassDesignTests/ContentGateTests.swift` (the phase machine with an injected sleeper and clock, including the page profile: minimum, timeout, reload).
  - `PerformanceJourneyTests.testGateShowsSpinnerThenContent` (gallery `FENTON_GALLERY=performance`, `FENTON_GALLERY_PERF=gate`).
- HIG: Loading; Progress indicators (indeterminate for unknown waits); Motion (Reduce Motion).

- **Owned files** (also in `contracts/patterns.json`): `ReadinessTracker.swift`, `PendingValue.swift`.

- **Shared reveal.** `UKContentReveal` (`UKContentGate.swift`) holds and reveals content (hold, 4 pt rise, Reduce Motion fade); `UKContentGateView` and `UKHouseLayoutGate` both use it. The house-layout gate records `LayoutChange` signposts (page `HouseLayout`) and has `HouseLayoutRevealPerformanceTests`.
