# Sheet reveal: how a modal's content appears when it opens

> **What:** the one reusable reveal a modal can opt into: the sheet slides up with its content hidden. When the slide ends, ready content fades in all at once; content that is not ready gets a centred arc first. It covers the timings, the API, the tile-glyph rule that comes with it, and how it relates to the content gate. Decided 2026-11-05 (task `chip-sheet-loading`). **Read when:** a modal's content should appear on presentation, a sheet loads before it can show, you touch `ContentGateModel.Profile.sheet`, `UKHassModalOptions.reveal` or the first configure of a `UKGlassTileView`.

Owning pattern: [content-gate](../patterns/content-gate.md) ("Sheet reveal"). Motion rules: [motion.md](motion.md) §3 and §4.4. Mockups: [room-overview-climate](mockups/modals/home/room-overview-climate/room-overview-climate.html) (the states `reveal-hidden` and `reveal-arc`, and the motion items `reveal-ready`, `reveal-arc` and `reveal-late`) and [content-gate](mockups/components/loading/content-gate/content-gate.html) (the `sheet` state and the `.sheet` timeline). Both are also in the [hub](mockups/README.md).

## Goal

Owner-Request: owner bug report, 2026-11-05 (verbatim): "Bug: when opening a status chip modal, we can see an off-screen spinner, and then icons animate in. Expectation: when modal opens, we should see a vertically and horizontally centered arc spinner of appropriate size gracefully fade in while content loads, fade out when loading is complete, and then tiles should fade in together. Up to you to determine speed of fade, size of spinner, etc. but this must be patterned appropriately and architected in a way that other components could re-use the same timer, animation flows and speed, and fade speeds elsewhere in the app."

Owner's pick (2026-11-05, AskUserQuestion "Sheet reveal"): **"Arc only if not ready"**. The tiles fade in together as soon as the sheet finishes sliding up. The centred arc appears (fade in, then fade out) only if the content is not ready by then, because sheets that really load will use it. Every modal uses the same reusable code.

What the owner's recording showed (unfolded Duo, landscape): the sheet slid up with every room tile drawn but no glyph. A spinner fragment was clipped at the sheet's leading edge. About 1.0 to 1.4 s in, each glyph appeared with its own symbol animation. Cause (research note `build/research/chip-sheet-loading.md` §3a, a working file that is not committed): nothing loads. The tiles are built with a placeholder `circle`, and their first real configure runs an animated `.replace` symbol transition on an image view that is not in a window yet. The arc fragment is a separate bug, which the Verifier is tracing.

## Decision

Decision: 2026-11-05, judged Option A (an arc on every open, held a minimum, then the tiles), B (the arc only if the content is not ready when the slide ends; otherwise the tiles fade in together) and C (no reveal: fix the glyphs so the tiles are there on the first frame); the owner picked B in chat, because it gives every modal one reveal, with an arc reserved for a real wait. Within B, the Designer picked the numbers, the API and the rules below (design-decision step 4: details inside the option the owner chose). A lost because it puts a spinner on content that is already in memory. That is the "loading" the owner called a bug, and HIG Loading says "Show content instantly when possible". C lost because the owner asked for a staged reveal that other components can reuse, and the glyph fix alone gives no shared flow. C's fix ships anyway, as rule 7.

Judged from the owner's recording, the research note and the code. No option was built, because the owner chose among them directly. Evidence of the chosen option in every pose is the Verifier's job before the verdict.

Gate: app_wide=no; matches_request=unsure; owner decided in chat 2026-11-05 (Arc only if not ready).

### The sequence (`ContentGateModel.Profile.sheet`)

| Step | What | Value | Built from |
|---|---|---|---|
| 1 | Sheet slides up. The chrome (grabber, title, subtitle, Close, ground) is visible. The root page's content is laid out but hidden (alpha 0, no hit testing, hidden from VoiceOver), so the sheet's fit still measures it | system transition | system |
| 2 | The presentation completes (the modal's first `viewDidAppear`). Ready content fades in **all at once**: one alpha on the page's content view, no per-tile stagger, no rise, no symbol effect | 200 ms, ease-out | `Timing.sheetFade` = `MotionTokens.quickDuration` |
| 3 | Not ready: grace before the arc, so a load that is nearly done never flashes it | 150 ms after presentation | `Timing.spinnerDelay` (reused) |
| 4 | The arc fades in, centred in the sheet's content area | 200 ms, ease-in | `Timing.spinnerEnter` (reused; equals `quickDuration`) |
| 5 | The arc's minimum hold, measured from the start of its fade-in | 500 ms | `Timing.spinnerMinimumShown` (new) |
| 6 | Once ready (and once every reported child is ready, or after `childTimeout`), the arc fades out | 200 ms, ease-out | `Timing.sheetFade` |
| 7 | Then the content fades in all at once | 200 ms, ease-out | `Timing.sheetFade` |
| - | Load timeout, measured from presentation: after it the content shows anyway, with its own empty or failed state | 10 s | `Timing.loadTimeout` (new; `.page` moves onto it) |
| - | Child timeout (images and other reported children) | 1.5 s | `Timing.childTimeout` (reused) |

What this adds up to: ready at presentation, the content is fully in 200 ms after the slide. Ready within the 150 ms grace, there is no arc, and the content fades in when it is ready. A real load: arc in from +150 ms (fully in at +350 ms), held to at least +650 ms, then 200 ms out and 200 ms in, so the earliest full reveal is +1050 ms. After that each step follows the data.

**A load that finishes while the arc is fading in** (the no-pop case): the arc keeps its fade, completes the 500 ms hold, fades out from full alpha, then the content fades in. An arc that has started is never cut short, and nothing jumps between alphas (`beginFromCurrentState`).

**Why these numbers:**
- **One fade speed for the whole reveal.** Every step is `MotionTokens.quick` (0.2 s), the app's token for "small fades", so any component reusing the reveal also reuses the app's fade speed. The web's 140 and 170 ms stay on `.results` and `.page`, which port the web's gates.
- **The 500 ms hold** stops a load that ends at +160 ms from blinking an arc on and off. 200 ms in plus 300 ms at full alpha reads as deliberate. It is half of `.page`'s 1 s minimum because a sheet is a quick interruption (HIG Sheets: "Keep sheet interactions brief and occasional").
- **Every step stays within motion.md §7's 0.4 s ceiling.**

### Arc

- **Size `ArcSpinner.Size.page` (44 pt, 3 pt ring), at every text size including AX5.** `.page` does not scale with text (`scalesWithText` is false): it is a hero indicator in an empty area, not an inline arc beside text. 44 pt reads clearly in a full-height sheet on every family. `.compact` (20 pt) is for pills and rows, and centred in a sheet it would look lost. The arc's label and the content around it scale.
- **Position.** Centred horizontally and vertically on the root page's `view.safeAreaLayoutGuide`: below the navigation bar (title and Close), above the home indicator, and inside the folded Duo's rail inset. It is never centred under the bar and never on the full-bleed `contentView`'s centre. The sheet's own width policy keeps it in the sheet's half beside a Duo hinge (modal-sheet rule 2), so it never lands on the hinge.
- **Never outside its centred position.** The arc is created only by the reveal (or a gate) and laid out without animation the moment it is added, so its first drawn frame is its centred frame. It never animates in from the origin or slides with a layout change. No other arc may draw in a sheet's content area while a reveal is running.
- **Colour.** The label colour of the surface (`UIColor.label` in the sheet's appearance). Its turn and Reduce Motion behaviour are the arc's own (half speed).
- **VoiceOver.** One element, `accessibilityIdentifier` `contentGate.spinner`, `updatesFrequently`, labelled for what it waits for: `UKHassModalOptions.revealLabel`, by default "Loading" + the sheet's title ("Loading Climate"), never a bare "Loading".

### Minimum content area while an arc can show

A sheet that reports readiness (it really loads) must open at its final or a pre-determined size, as the Edit Task form does (modal-sheet "Task form size"), or be `.full`. While the reveal is in `.loading`, the root page's content area is at least 44 + 2 x 24 = 92 pt tall (`ArcSpinner.Size.page.diameter + 2 * HassTokens.Spacing.xl`), so the arc never sits in a sliver. Store-backed sheets never show the arc in practice, so they need nothing extra.

### Reduce Motion

The same sequence and durations. Every step is an opacity fade, which Reduce Motion allows (motion.md §8). There is no rise to drop (`contentRise` is 0 for `.sheet`). The arc turns at half speed. The sheet's own slide is the system's.

### Rise

There is none in a sheet. The content only fades (`Profile.contentRise` = 0). The sheet has just moved up, so a 4 pt rise after it reads as a second, smaller bounce, and motion.md §4.4 already says "no tiles rising" inside sheets. `.results` and `.page` keep their 4 pt.

## API (for reuse)

- **`HassDesign`.** `ContentGateModel.Profile.sheet`, plus three `Profile` fields that default to today's behaviour:
  - `contentRise: CGFloat = 4`;
  - `waitsForPresentation: Bool = false`: nothing happens (no arc timer, no load timeout) until `presentationCompleted()`, and content that is ready at init stays hidden until then;
  - `spinnerMinimumShown: Duration = .zero`: the hold from the arc's start, applied only when the arc has shown, unlike `minimumLoading`, which forces an arc.

  Also `revealsOnce: Bool = false`: once `.idle`, a later `advance(isReady: false)` is ignored. The phase machine stays the gate's own (`ContentGateModel`), so a sheet reveal and a page gate cannot drift apart.
- **`UIKitPort`.** `UKHassModalOptions.reveal: UKModalReveal` (`.none` by default, or `.gate(ContentGateModel.Profile = .sheet)`) and `revealLabel: String?`.
  - Readiness: a root page that really loads conforms to `UKRevealReadiness` (`var isContentReady: Bool { get }`, read inside an observation). A root that does not conform is ready once it has laid out, which it always has by the time the slide ends.
  - `UKHassModalController.revealTracker` (the model's `ReadinessTracker`) lets children (images) hold the reveal through `UKReadinessRequirement`.
- **Drawing.** One driver, `UKContentGateDriver`, takes the phases (`content` view, `arcHost` view, `arcCenter` layout guide, label). `UKContentGateView` and the modal reveal both use it. The modal drives the root page's `contentView`, with the arc in the page's `view`, centred on its `safeAreaLayoutGuide`. `UKContentGateView` keeps its own bounds-centred arc and its 4 pt rise, so Recipes, the inventory pages and Edit Task do not change.
- **Opt-in, not a default.** `.none` stays the default for every modal: a sheet whose content is present on arrival stays that way (motion.md §4.4). Sheets opt in at their call site. The first adopters are the five Home chip sheets and the Security page's Contact Sensors chip (`UKRoomOverviewSheet.controller`, one call site). Making it the app-wide default would be an app-wide change the owner did not request, so it would go to the gate first.

### Edit Task

Edit Task stays on its in-page `.page` gate. It is not migrated. Its sequence (arc from the first frame, held 1 s, 500 ms out) is the owner's 2026-10-30 decision (web parity). Moving it onto `reveal:` would start its arc only after the slide, which is a visible timing change of its own. A later migration must keep `.page`'s timings (`reveal: .gate(.page)` with `waitsForPresentation` false) and is a separate task.

## Rules this adds

1. **A store-backed sheet uses the reveal only to fade in together on presentation.** In practice it never shows an arc, and the reveal never delays or blanks a reopen, a reconnect or a snapshot reapply. Its readiness is layout, never data. The store is read synchronously, so the content is ready before the slide ends.
2. **A reveal runs once per presentation** (`revealsOnce`). After `.idle` it lets go of the content, and nothing hides the content again: a reconnect, a snapshot reapply, a fold, an unfold, a rotation, Dynamic Type, or a push and pop inside the sheet. A page that reloads in place gates its own region with `.results`.
3. **Root page only.** Pushed pages inside the sheet are plain pushes whose content is there on their first frame (motion.md §4.2). A sheet the app re-presents to restore a pose (none today) passes `.none`.
4. **No arc before the presentation completes, and no arc for a load that ends within 150 ms of it.**
5. **One alpha, not many.** The reveal fades the page's content view. Tiles never fade, stagger or play symbol effects for their own first appearance.
6. **No arc outside its centred position.** See Arc above.
7. **Tile glyphs on first configure (`UKGlassTileView` / `UKGlassTileFaceView`).**
   - The face runs a symbol content transition (`.replace`) only when the tile is in a window and has already drawn: `symbolTransition` also requires `window != nil`, the same guard the colour cross-fade already has.
   - A consumer builds a tile with its **real** first model, including its symbol. It never builds with a placeholder symbol (`"circle"`) and configures the real one afterwards. Compute the model once, pass it to `init`, then observe live changes.
   - A live change of symbol on a tile that is on screen still animates (`.replace`; none under Reduce Motion).

## HIG

- **Loading:** "Show content instantly when possible; for waits beyond a moment or two, you can use system progress indicators". **Departure (owner, 2026-11-05):** content already in memory is held back for the sheet's slide (about 0.5 s) plus a 200 ms fade, instead of arriving with the sheet. The owner asked for "tiles should fade in together". HIG still wins wherever it can: no arc for content that is ready, a 150 ms grace, a fade of 0.2 s, and the arc only for a real wait.
- **Progress indicators:** indeterminate for unquantifiable tasks; "add an accurate, succinct description. Avoid vague terms like loading". So the arc's spoken label names the sheet ("Loading Climate"), and it is spoken, not drawn.
- **Motion:** "Keep feedback animations brief and precise" (every step 0.2 s); "let people cancel animations rather than wait for completion" (Close and swipe-down work throughout; the hidden content is not interactive only while it is invisible).
- **Sheets:** "Keep sheet interactions brief and occasional". This is why the hold is 500 ms, not `.page`'s 1 s.
- **Designing for iPhone Duo:** "Avoid extreme changes: move only what's necessary". So the arc keeps its centre through a fold, unfold or rotation, by constraints, with no re-staging.
- **Departure from motion.md §4.4** ("sheet content is present on arrival"): recorded there as an owner exception, scoped to modals that opt into `reveal`.
