# Action and navigation tiles: architecture

> **What:** how the tile convention in [action-navigation-tiles.html](action-navigation-tiles.html) is built so one component draws every tile, domain rules are unit-tested without SwiftUI, and features stay thin. **Read when:** implementing or reviewing the chosen option. Proposal 2026-10-26; nothing here ships until the owner picks.

## What exists today (and why it does not scale)

| Today | Problem |
|---|---|
| `GlassTileKind` (`toggle`, `navigate`, `command`, `selection`, `state`) says what the *body* tap does | No notion of actions on the tile; a tile is one button or a chevron |
| `GlassTile(accessory:)` trailing `@ViewBuilder` | Any view, placed by `GlassTile`, but its contents are hand-built per feature |
| Three in-tile button implementations: `FanRailButton` (HassUI), `BrightnessTile.powerButton` (HassDesign), the fan sheet's own Power/Lock tiles | Different fills, sizes, a11y and haptics for the same idea |
| `LockTile`, `GarageDoorTile`, `RoomCardTile`, `MediaCardTile` each derive symbol, state text and service call inline | Domain rules (locked → "Unlock", locking → busy) live in views, tested only through UI |
| `DynamicGridLayout` spans are fixed by the caller (`.gridSpan`) | The web's content-aware spans (`itemSizing="content-aware"`) were never ported (TODO in [dynamic-grid](../../../../patterns/dynamic-grid.md)) |

## Principles

- **Composition, not inheritance.** SwiftUI views are value types; there is no `class LockTile: ActionTile`. Variation comes from *data* (a `TileBehavior` and a list of `TileAction`s) handed to one `GlassTile`, and from *protocol conformances* in HassCore for each domain (the strategy pattern). This is the swiftui-pro rule set (small views, no `AnyView`, no `ObservableObject` hierarchies) and the repo's [pattern first](../../../../patterns/README.md) rule: one component, extended.
- **Pure rules, thin views.** Everything decidable without a screen (which actions a lock in state X offers, where N actions go at width W and text size T, which ink a button takes on face F) is a pure function in HassCore or HassDesign with a unit test. Views only wire gestures, environment and animation to those values.
- **One state path.** Actions call through the existing `OptimisticActions` / `HassConnection.callService`; in-flight and failed come from `OptimisticActions.isPending` / `isFailed` and the entity's own transitional states (`locking`, `opening`). No new store, no new websocket.

## Layers

```
HassCore (no SwiftUI)                         HassDesign (SwiftUI, no store)                  HassUI (features)
──────────────────────                        ──────────────────────────────                  ─────────────────
TileActionSpec        value: id, verb,        TileAction        spec + perform closure        LockTile, GarageDoorTile,
                      symbol, call, phase                                                     MediaCardTile, RoomCardTile:
TileActionProviding   protocol: state → specs TileBehavior      .perform(id) / .navigate /    build specs from a provider,
  LockActions                                                    .inert                        bind OptimisticActions,
  CoverActions        (garage)                TileActionPlacement  pure: count × behaviour     hand GlassTile data
  PowerToggleActions  (PC, towel rack,                            × width × text size → slot
                       remote power)          TileActionButton   the one round button
  MediaTransportActions (prev/play/next)      TileActionStrip    trailing pair or centred row
  FanRailActions      (lock, power)           TileVolumeSlider   HorizontalPan slider (custom)
  VacuumActions       (start/pause, dock)     GlassTile(behavior:actions:custom:)  the template
TileClassification    pure: has destination   DynamicGridLayout  + content-aware span via
                      × actions → class                          LayoutValueKey TileMinimumWidth
```

### HassCore: the domain

```swift
/// One thing a tile can do, decided from entity state alone.
public struct TileActionSpec: Identifiable, Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case ready, inFlight, unavailable }
    public var id: String            // stable: "lock", "play_pause", "next"; the view's identity and test id suffix
    public var verb: String          // VoiceOver label and the hint: "Unlock", "Pause", "Turn On"
    public var symbol: String        // the STATE glyph for a toggle-styled action (lock.fill when locked, lock.open when unlocked); the ACTION glyph for a momentary one (pause while playing, play while paused)
    public var isOn: Bool?           // toggle-styled buttons (fan Power, Lock) fill when on; nil = momentary
    public var phase: Phase
    public enum Feedback: Equatable, Sendable { case momentary, optimistic, tracked }
    public var feedback: Feedback    // owner, 2026-10-26: see "Feedback kinds" below; declared by the provider, tested per provider
    public var call: ServiceCall?    // nil = custom (opens something, or a slider)
    public var optimistic: [OptimisticIntent]
}

/// A domain's actions. Conformers are value types, one per device kind; each has a test file.
public protocol TileActionProviding: Sendable {
    func actions(for state: EntityState?) -> [TileActionSpec]
}

public struct LockActions: TileActionProviding {
    public var entityId: String
    public func actions(for state: EntityState?) -> [TileActionSpec] {
        // locked → verb Unlock, symbol lock.fill; unlocked/open → verb Lock, symbol lock.open; locking/unlocking → same verb, .inFlight;
        // jammed → Lock, ready; unavailable → .unavailable. Explicit lock/unlock services, never toggle.
    }
}
```

**Garage doors: one morphing action (owner, 2026-10-26).** `CoverActions` returns a single spec whose role follows the state: closed → Open (`door.garage.closed`), open → Close (`door.garage.open`), moving → Stop when `supported_features & 8`, else Reverse (the opposite command, today's `garageDoorCommandForState`), stopping → `.inFlight`. The spec `id` stays `"door"` across roles so the symbol transition survives; the label changes ("Open Left Door", "Stop Left Door", "Reverse Left Door"). The existing `GarageDoorController` "Sending…" hold maps to `.inFlight`. Live check 2026-10-26: both garage covers are Aladdin Connect with `supported_features` 3 (open, close; no stop, no position), so ours reverse and never show "Partly Open". Tests: every state × stop supported or not, and the id staying stable.

**Feedback kinds (owner, 2026-10-26).** Every spec declares one, so the view never guesses:

| Kind | Examples | On tap | While waiting | On completion / failure |
|---|---|---|---|---|
| `momentary` | next, previous, locate, dock, skip | press highlight + `TapFeedback.tap` | nothing (no phase change, no glyph change) | failure: the tile's "Didn't Respond" face |
| `optimistic` | play/pause, fan power, towel rack, purifier power, guest toggle | glyph replaced at once (`quick`), `OptimisticActions` shows the intent | nothing (no spinner) | Home Assistant confirms silently; failure animates back and shows the error face |
| `tracked` | lock, garage door, PC power | `.inFlight`: spinner in the disc, or the moving role (garage Reverse / Stop) | the entity's transitional state (`locking`, `opening`, "Turning On…") or the Sending hold | animates out to the final glyph and fill when the state settles |

A provider test asserts each spec's kind, so a momentary action can never grow a spinner.

**Availability (owner, 2026-10-26).** One action becoming unavailable dims its disc in place (`.unavailable`: glyph 50%, disabled); it never disappears, so nothing moves. When the action *set* changes shape (an off remote's Power beside the chevron ⇄ a playing remote's transport and volume below), the tile's height animates with `MotionTokens.standard` and the discs fade with `quick` (out before the collapse, in after the expand). This is an owner-approved exception to motion.md §6 ("live updates never move layout"), with guard rails: only tiles already spanning their full row (content below shifts, nothing reflows sideways); a change that arrives while the page scrolls waits until scrolling ends; a reconnect or a cold launch from the snapshot applies it without animation (No reload on reopen); Reduce Motion cross-fades in 0.2 s with no height animation. The strip keys the transition on the slot set (`TileActionSlotSet`, Equatable), not on every state change, so live values never trigger it. motion.md §6 and motion-components.md gain this exception when the build lands. Tests: a pure `TileActionSlotSet` diff (same set → no transition), and a hosted test that a snapshot reapply does not animate.

`TileClassification.classify(hasDestination:actions:)` returns `.action(count)`, `.navigation(actionCount)` or `.state`, so a config (`RoomsConfig`, `SecurityConfig`, `MediaRemotes`) is classified, and checked, in a unit test: a card with no sheet and no action is `.state` and must draw the read-only face; a card with a sheet keeps its chevron whatever actions it gains.

### HassDesign: the drawing

```swift
public enum TileBehavior: Equatable, Sendable {
    case perform(TileAction.ID)   // body tap = this action (single-action tiles; the primary of two)
    case navigate                 // body tap = open; chevron trailing
    case inert                    // read-only face, not a button
}

public enum TileActionSlot: Equatable, Sendable { case none, trailing, below }


/// Owner rules, encoded once (option B of the proposal).
public enum TileActionPlacement {
    public static func slot(count: Int, behavior: TileBehavior, accessibilitySize: Bool, fitsTrailing: Bool) -> TileActionSlot {
        guard count > 0 else { return .none }
        // Owner, 2026-10-26: up to two actions trail on any tile; on a navigation tile they sit left of the
        // chevron's reserve (today's fan rail geometry), and the chevron stays vertically centred at every height.
        if accessibilitySize || count > 2 || !fitsTrailing { return .below }
        return .trailing
    }

    /// An action tile with a trailing slot drops its leading glyph: the first disc carries the state glyph, so one-action tiles stay two to a row on a phone.
    public static func carriesGlyph(behavior: TileBehavior, slot: TileActionSlot) -> Bool {
        if case .perform = behavior { return slot == .trailing }
        return false
    }
}
```

- **Actions are data, the handler is one closure** (swiftui-pro review, 2026-10-26). The tile's stored inputs hold only `[TileActionSpec]` (Equatable, Sendable) and one `perform: (TileActionSpec.ID) -> Void`, never a closure per action, so the tile diffs on values and a parent re-render does not invalidate it. `ForEach(specs)` keys on `spec.id`, which stays stable across states (a lock is `"lock"` whether it would lock or unlock) so the symbol transition survives. There is no `TileAction` wrapper type.
- `GlassTile(…, behavior:, actions:, perform:)` is a **second initializer in an extension**; the generic `Accessory` slot stays (specialised, no existential, the `EmptyView` fast path) and hosts custom controls (`TileVolumeSlider`). `kind:` maps to a behaviour: `.toggle` and `.command` → `.perform(primary)`, `.selection` → `.perform(primary)` with the `.isSelected` trait carried on the spec, `.navigate` → `.navigate`, `.state` → `.inert`; `playsTapFeedback`, the `.isToggle` trait and `spokenValue` move onto the spec. `@available(*, deprecated)` lands only after the last of the 29 call sites moves, so the build stays warning-free.
- `TileActionButtonStyle` (a `ButtonStyle`, like `GlassTileButtonStyle`, so press feedback needs no `@State`) replaces `FanRailButton` and `BrightnessTile.powerButton`: 44 pt (scaled, capped 1.5×), glyph ≤ 45% of the disc, ink from `TileActionInk.resolve(face:isOn:)` (pure, tested: white disc + family ink when on; 12% white on an off tile; 18% black on a filled one; the dark disc on a lit tile, which measured 1.9:1 otherwise). The symbol transition is one modifier, `TileActionSymbolTransition` (`.contentTransition(.symbolEffect(.replace))`; `.replace.magic(fallback: .downUp)` inside it behind `#available(iOS 18, *)`, so the view type never branches; Reduce Motion `.identity` plus the state colour cross-fade). `.inFlight` swaps the glyph for a `ProgressView` (`.controlSize(.small)`, tinted to the ink, disc size fixed) and disables the disc and the body (HIG Buttons: "show an activity indicator in the button"); the disc keeps its label so VoiceOver does not read "In progress". `TapFeedback.tap` on tap; failure stays on the tile face ([tap-feedback](../../../../patterns/tap-feedback.md)).
- **Who calls Home Assistant.** The feature view owns `@State private var actions: OptimisticActions?` (created lazily, the `SecurityDoorTile` shape, or hoisted to the page), feeds the provider the *shown* state (live with the overlay applied), and sets each spec's `phase` from the entity's transitional state (`locking`) or `isPending`. Providers stay pure. The strip reads no per-frame state; the volume slider keeps its drag in local `@State` and writes once on release (the main-thread invariant).
- **Carried glyph.** When `TileActionPlacement.carriesGlyph` is true the tile draws no leading glyph and text starts at the 12 pt padding; the first disc shows the state glyph (toggle-styled: solid white with the family fill as glyph on a filled tile, white 12% with the family's off-glyph colour on an off tile; the lit and power faces keep the dark disc). Navigation and read-only tiles keep the glyph leading, so the shape ("glyph, text, chevron" opens; "text, disc" acts) tells the two classes apart.
- `TileActionStrip` lays out the slot: trailing is an `HStack(spacing: 12)` vertically centred (HIG: about 12 pt between bezeled targets), inset by the 20 pt chevron reserve on a navigation tile so the reading order right to left is chevron, gap, discs; the chevron is vertically centred at every tile height (owner, 2026-10-26); below is a centred `HStack` under the text, and the custom slot (volume) under that. At AX sizes the trailing pair drops below, matching today's fan rail rule.
- **Accessibility, decided once.** The disc is hidden only when `behavior == .perform(spec.id)` for that exact spec (a pure, tested rule): then the tile is the one element (label = title, value = state, hint = verb), and Voice Control and Full Keyboard Access reach the action through the body, which does the same thing. Every other case (two or more actions, navigation with actions) is `.accessibilityElement(children: .contain)`: the body button, then each disc as a real button labelled "Unlock Front Door" (verb + title), `.isToggle` only on toggle-styled discs. No disc is also an `.accessibilityAction` of the same element (duplicates are noisy). Identifiers: `tileIdentifier` on the body, `<tile-id>.action.<spec.id>` on each disc (the scheme that fixed the fan's hidden identifiers).
- **One source of truth for the class.** `TileClassification` lives in HassCore; HassDesign's `TileBehavior` is mapped from it, never computed twice.

### Grid: content-aware spans

`TileMinimumWidth` is a `LayoutValueKey` each tile sets from its content (`textMinimum + slot width`: 96 pt of text plus the discs and padding; a carried-glyph tile has no 30 pt glyph column, so one disc needs about 172 pt and fits a 179 pt phone track, and two discs need about 228 pt and take the full row). **Widen, then ticker (owner, 2026-10-26).** A tile's text is one line at default sizes: its minimum includes the natural single-line width of the title and of the *longest* state it can show (a provider supplies `stateTextCandidates`, so "Off" becoming "Playing · …" never re-spans the grid on a live update). The grid widens the tile track by track (iPhone: half → full row; iPad: 1 → 2 → 3 tracks; never across the hinge band, where the cap is that side's width). Only when the tile already spans its whole row or side does an overflowing line become a `TickerLabel` ([ticker](../../../../patterns/ticker.md): measured overflow, 3 passes, pauses while scrolling, hidden from VoiceOver while the tile's label and value speak the full text). Reduce Motion and accessibility sizes wrap instead (the ticker's own rule), and the tile grows taller. `GlassTileText` gains a `tickers` flag the strip sets from the resolved span (`spanIsCapped`), so no view measures its own overflow twice. The motion.md §9 ticker exception gains tiles as a consumer by this owner decision. Tests: `DynamicGridSpanTests` (single-line minimums, capped spans, band cap, longest-state stability), and a hosted test that a capped tile's title is a ticker and an uncapped one is not.

The minimum is declared from content (`@ScaledMetric` text minimum + disc diameter × count + gaps), never measured with `sizeThatFits` per pass and never fed back through `onGeometryChange` (today's `accessorySize` state is that feedback loop; it goes). `DynamicGridLayout` resolves in two steps so nothing is circular: columns from `minCellWidth` first, then each tile's `ceil(min / trackWidth)` tracks against that track width (capped at the column count), then rows packed like the web's `fillRows: 'except-last'`. The measurement cache key adds a hash of the minimums to width and band, so a text-size or action-count change never serves stale rows. When even the whole row is too narrow (a folded Duo at AX5), `fitsTrailing` is false and the strip goes below instead. Pure part: `DynamicGridMetrics.spans(minimums:trackWidth:columns:)`, tested beside `DynamicGridMetricsTests`; hinge and band rules are unchanged (a span never crosses the band).

## Tests that ship with it

| Level | File | Covers |
|---|---|---|
| HassCore unit | `TileActionProvidersTests` (one suite per provider) | every state of lock, cover, power, media, fan, vacuum → verb, symbol, phase, call; unavailable → `.unavailable`; explicit services, never `toggle` |
| HassCore unit | `TileClassificationTests` | every card in `RoomsConfig`, `SecurityConfig`, `MediaRemotes` classifies; no card is both inert and a button |
| HassDesign unit | `TileActionPlacementTests` | the full matrix: count 0–4 × behaviour × AX × fits, including navigate + 0 actions = chevron only, navigate + 1–2 = trailing left of the chevron, navigate + 3 = below; `carriesGlyph`; the disc-hidden rule |
| HassDesign unit | `TileActionInkTests`, `DynamicGridSpanTests` | ink per face (contrast ≥ 3:1 glyph, measured), span packing, hinge band |
| Hosted UI (`HassUITests`) | `ActionTileTests` | body tap fires the primary once; disc fires it once and the body does not also fire; in-flight disables both; failed face; VoiceOver: one element for single-action, body + N buttons for the rest, disc labels "verb title"; Voice Control names and 44 pt targets at AX5 |
| Device journeys | `SecurityJourneyTests`, `MediaJourneyTests`, room journeys | iPhone, Duo, iPad: unlock → "Unlocking…" → "Unlocked"; media tile transport and volume; AX5 strip below; 44 pt targets |
| Perf | `tools/ios_scrollcost.sh` | a strip adds no per-frame state; the slider writes only on release |

## Migration order (one lane each, after the pick)

1. HassDesign: `TileActionButtonStyle`, `TileActionPlacement`, `TileActionStrip`, `GlassTile(behavior:actions:perform:)` with `kind:` mapped; fan rail and BrightnessTile power move onto `TileActionButtonStyle` (the fan rail keeps its place left of the chevron, owner 2026-10-26; pixels unchanged).
2. HassCore providers + tests; `LockTile`, `GarageDoorTile`, PC and towel rack adopt them (Security, room pages).
3. Media: `MediaTransportActions`, `TileVolumeSlider`, the remote tiles on Media and room pages.
4. Grid content-aware spans; read-only face for `.inert`.
5. Vacuum, air purifier, security system, beds: their actions as the owner approves each.

## As built (`claude/action-nav-tiles`, 2026-10-27)

- **Layering.** HassDesign has no HassCore dependency, so the HassCore types never cross into it. HassUI maps them in one place, `Features/TileActions/TileActionItem+Spec.swift`: `TileActionSpec` becomes the presentational `TileActionItem`, and `TileClassification` becomes `TileBehavior`. HassDesign's `TileActionPlacement` and HassCore's providers stay pure and are tested separately; neither imports the other.
- **How a tile learns its width.** It does not measure itself. The grid gives each tile its track span from the minimum the tile declared (`TileMinimumWidth`, from `TileTextMeasure` and the slot width), so by the time the tile draws, its width is a layout fact. `GlassTile` then lets `ViewThatFits` choose among three variants: the natural one-line text with discs trailing; a ticker with discs trailing (down to the 96 pt text floor); a ticker with the strip below. There is no `onGeometryChange`, no `sizeThatFits` per pass and no width state fed back, so a width change cannot loop.
- **Reapply generation.** `EntityStore.reapplyGeneration` increments (`noteReapply()`) when a snapshot or a reconnect reapplies state. Tiles compare it with the value they saw on appear; a change means the next action-set change applies without animation. Cold launch from the disk snapshot and reconnect therefore never animate a tile's height.
- **Optimism.** Tracked specs carry no optimistic intents; the tapped lock shows the lock's own transitional state ("Unlocking…") until any live change clears it. This replaces the planned `OptimisticActions.isPending` bridge.
