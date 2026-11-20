# Status rail

> **What:** the horizontal chip row under a page title. **Read when:** adding a summary chip.

- Chips come from config (`HomeConfig.statusChips`) with an entity, symbol, tone and the sheet they open. Pages pass their own subset to `StatusRail(chips:idPrefix:)` (Security shows Security and Contact Sensors).
- `ChipRail` lays the chips out: every width (iPhone, folded Duo, iPad, unfolded Duo) scrolls them sideways in one row across the whole page, over a hinge too; only an accessibility Dynamic Type size wraps them with `FlowLayout` (`ChipRailMode.resolve(isAccessibilitySize:)`).
  A wrapped rail on a window with a hinge stops 24 pt short of the fold (`ChipRailMetrics.trailingInset`, applied by `appliedInset(measured:hinge:mode:)` in `.wrap` only).
  Where the window is wide enough for every chip the row fits and does not scroll.
  On the unfolded Duo's two-column pages the rail sits above both columns, full page width, except at an accessibility size while partly folded: the wrapped rail is then the first block of the leading column ([section-sides](../design/section-sides.md) rule 11).
  Home, Security and the room pages' rails all use it. Chips keep their own widths so live values never shift neighbors.
- Home has six chips in web order: Lights, Security, Climate, Occupancy, Contact Sensors, Air Quality. Summaries follow the web (`HomeConfig.summary`): Lights and Contact Sensors count their rooms' entities, Occupancy reads Detected/Clear, Air Quality joins the AQI and PM2.5 range helpers. Every chip but Security opens a [room overview sheet](room-overview-sheet.md); Security opens `SecuritySystemSheet`.
- Each chip is a button with the label "<title>, <summary>" for VoiceOver and opens a sheet.
- A chip narrower than its text wraps its title and state at word boundaries inside the capsule; it never truncates or shrinks its text (HIG Typography, Supporting Dynamic Type; section-sides verdict V1). A wrapped chip keeps the corner radius of a one-line chip at the current text size (`UKChipShape.cornerRadius`), in both chip views.
- Chips are pills (`StatusChipButton`, `StatusChipStyle`): a capsule at least 48 pt tall (web `.headerPill`). Owner, 2026-10-13: "Page-level chips are not pills like they are in web or the Apple Home app, and need background colors." Direction G ([direction-g](../design/direction-g.md), "Status chips follow the web"): a filled chip draws its fill with a slight top highlight, a white title, state in full white, and its glyph in the tint's glyph colour; an idle chip is neutral on the thin `module`.
- **One resolver.** `StatusChipAppearance` (HassUI/Features/Home) decides symbol, family, filled-or-neutral and the optional `ChipTint` for a Home/Security chip (`home(_:read:)`) and a room chip (`room(_:chip:)`); `StatusChipButton` only draws. A new chip rule goes there, with a test, never in a view.
- **Chip colours** (owner, 2026-10-16; sources in direction-g):
  - Lights on: amber with an orange glyph. Security: always its mode's fill (`ColorFamily.security(alarmState:)`), neutral while arming or unknown.
  - Climate: the temperature colour. Helper first (`input_text.demo_color_1`, a room's `…_climate_color`), else the web gradient at the range's mean (`ChipWebColor.climate`); a room's bed chip and a chip with no colour keep navy `#195482`. `ChipTint.fromWeb` scales it to 73% and darkens until white reads at 4.5:1, keeping the yellow thermometer where it holds 3:1.
  - Air Quality: the AQI colour on fill and glyph (`input_text.demo_color_2`, a room's `…_aqi_color`, else the web teal). Summary `AQI <range> · PM2.5 <range>` as on the web.
  - Occupancy: one `person` symbol, outline when clear, filled when detected; green fill only while detected, with no alarm or away tint (the web has none).
  - Contact Sensors: `ContactChipState` (HassCore/Chips), shared by Home, room rails and Security: all closed soft green, open at home amber `#8A5200`, open away coral `#B23A26`, open while armed red `#D70015` with an alert glyph; armed outranks away. Away is `ClimateLogic.isEffectivelyAway`.
- **Animation.** A fill or glyph colour change, and a chip turning filled or neutral, cross-fade (`StatusChipStyle.colorAnimation`: 0.6 s, 0.2 s under Reduce Motion). The animation is scoped with `.animation(_:body:)` to the colour modifiers only, so a longer state text never slides the capsule, and it is allowed under Reduce Motion because nothing moves.
- Room chips map their `RoomTone` to a family (`RoomTone.family`); `RoomController.chip(_:)` adds the contact state and web colour to `RoomChipDisplay` so the view layer needs no entity reads.
- **Chips start at the leading margin, always.** Even when every chip fits, a row is left-aligned, never centred.
  `HostedScrollView.layoutSubviews` gives the hosted view exactly the row's natural width at the leading edge (`ChipRailMetrics.hostedContentFrame`: x = 0 left to right, the right-hand end right to left, offset `hostedLeadingOffset`), and `contentSize` stays at least the scroll view's width so nothing bounces.
  The wrapped rail (`FlowLayout`) places each row from the leading edge, mirrored right to left.
  Rule: a row's alignment is the container's job, never a side effect of a hosting view's size.
  Journeys: `ChipAlignmentJourneyTests` (every row's first chip is `HassTokens.Spacing.l` from the page's leading edge on every family); unit tests: `ChipRailTests`.
- **Scrolling is UIKit's.** The compact rail is a `UIScrollView` hosting the chips (`HostedHorizontalScroll`, handed the page's environment with `transformEnvironment(\.self)`), not a SwiftUI `ScrollView`.
  A `ScrollView` nested in a page's `ScrollView` writes its offset through the page's view graph on every frame, and that cost grows with the page around it, not the chips (main-thread samples 6,020 to 2,943 on 120 tiles).
  Rule: keep a row that scrolls sideways inside a page out of SwiftUI's `ScrollView`; the other nested horizontal scrolls are in [performance](../testing/apple/performance.md), Round 2.
  The hinge inset is measured only by a wrapped rail in a window that has a hinge, because a window-space frame is recomputed on every scrolled frame.
  A rail on a server-driven page follows the fold itself (`UKChipRailView.followsFold`, the same `UKHinge.didChange` publish and one-turn hop as `UKDynamicGridView.followsFold`), so a live posture change reaches it with no re-render; the scrolling rail's applied inset stays 0 in both poses.
- **Accessibility sizes wrap.** `ChipRailMode.resolve(isAccessibilitySize:)` returns `.wrap` at an accessibility Dynamic Type size on any width, the only wrap: chips are nearly screen-wide there, so a sideways row would show one with the rest off screen and no cue.
  The state line under a chip's title is `.subheadline`.

- **A chip that changes size tells its container.** The rail measures its chips only in its own `layoutSubviews`, so a chip whose text, symbol or font changes after that keeps a frame sized for the old content and wraps its new text inside it.
  Rule: every chip class (`UKStatusChipView`, `UKRoomChipView`, any new one) calls `ukRemeasureContainers(ifSizeChangedFrom:)` (`UKDesignSupport.swift`) whenever its measured size can change: new text, symbol or fill in `configure`, a font change in its `ukOnContentSizeChange` handler, and `didMoveToWindow`.
  It compares the chip's size at an unbounded width with the last one it reported and does nothing when it is the same; otherwise it flags every ancestor and invalidates the grids above, so the rail measures again.
  Tests: `UKHostedChipUndersizedTests`.
  Both chip classes set label text through `UILabel.ukSetWrappedText`, whose paragraph style disables hyphenation, so a wrapped chip breaks between words only (`testChipsNeverBreakAWordInTheMiddleWhenTheyWrap`).
  A single word wider than the chip (AX5, very narrow window) still breaks by character.
  Follow-up: `UKRoomChipView` duplicates `UKStatusChipView`; consolidate once a before and after screenshot shows no visible difference.

- **Owned files** (also in `contracts/patterns.json`): `ChipRailArrangement.swift`, `ChipRailLayout.swift`.

## Configured UIKit consumers

Schema-2 compositions use `home-status@1` with explicit entity membership and the
canonical `RoomOverview`, `RoomFormat` and `ContactChipState` value helpers.
`status-chip` authors its title, state-to-symbol/fill/glyph/text mapping, fallback,
change-announcement policy and optional navigation destination. The source owns
loading, empty, unavailable and privacy-redacted values; missing inactive members
must not produce an all-clear summary. There is no house-config lookup in this path.

`status-rail` contains only status chips and reuses `UKChipRailView`. Keyed updates
retain the rail and its scroller; only a changed child identity/order calls
`setChips`. Typography / Supporting Dynamic Type: "Make sure your layout adapts to
all font sizes" remains the rule; the existing AX-size wrap and native chip
remeasure/colour-animation paths are unchanged. A rail keeps the page gutter before
its first chip (`UKChipRailView.edgeInset`, 16 pt by default); inside a composed page
that already pads its sides the page sets it to `max(0, Spacing.l - padding)`, so the
chips start where the page's other rows do and never one gutter further in.

These are atomic authoring contracts, not a complete configured Home or Security
rail. Dynamic helper-derived tints, Home's entity-driven guest visibility,
cross-column placement, sibling destinations and the room tile's independently
coloured glyph remain explicit integration gaps. A room tile with an authored
glyph is rejected, not silently recoloured. Native preflight rejects solid fills that cannot
support white chip text under the canonical highlight; it never silently recolours
an authored fill. Studio structural validation does not replace that native gate.
