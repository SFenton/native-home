# Kit changelog

> **What:** what changed in `_kit/`, newest first, so a mockup author knows which local workaround can go. Existing mockups keep rendering; the entries below list what looks different.

## Unreleased (2026-11-06, house-config-states)

**Symbols (`lib/symbols.js`)**
- Two names added for the house-config states proposal: `puzzlepiece.extension` (an integration is missing) and `arrow.down.circle` (update the app). No existing mockup changes.

## Unreleased (2026-11-04, duo-widths)

**`TileGrid` (`components/TileGrid.js`)**
- New `fill: 'share' | 'none'` (default `share`): a short row fills its section ([duo-widths](../../duo-widths.md) rule 1). One-row grids share the width equally (max-min fair); grids of more rows fill short rows in whole tracks (spare tracks to the narrowest item, ties to the later item), so 4 + 3 draws 4 + 1, 1, 2. With a vertical band (`data-posture="part"`) each side fills on its own and nothing crosses it. Automatic `none` for a minimum under 100 pt and for grids of only `.ui-cam` / `.ui-img`; pass `fill: 'none'` for choice chips, remote app tiles and dials. Every mockup with a lone tile or a short row now draws it filled; an item already at `grid-column: 1 / -1` and `.gridheader` rows are untouched.
- `pages/rooms/_rooms.js`: the section grid's 340 pt minimum scales with text up only (rule 5), and a section alone in its row spans both columns (rule 6).

## Unreleased (2026-11-02, single-page motion)

**`Mock.anim.slide` (`lib/anim.js`)**
- The UIKit port's single-page push and pop ([single-page-motion](../../single-page-motion.md) S2): both pages move a full width over a still wallpaper on `standard`, no dim, shadow or fade; Reduce Motion cross-fades on `quick`. Beside `Mock.anim.push` (the system push), which is unchanged; no existing mockup changes.

## Unreleased (2026-10-28, rollout L)

**BrightnessTile and TileGrid (`components/BrightnessTile.js`, `components/TileGrid.js`)**
- `BrightnessTile` is an action tile with a `power` disc and no leading glyph; with `chevron: true` it is a navigation tile with the disc left of the chevron (none while unavailable). A tile built with `data-wide="1"` takes two tracks in `TileGrid`. Callers that drew their own power button (`MLC.lightTile`) now use the kit's.

**Stacked tile with discs (`kit.css`)**
- `.ui-tile.stack.has-discs` keeps its discs vertically centred beside the chevron (promoted from `proposals/tile-rollout-rooms-media/_rollout.js`); Quick Links Security System uses it.

## Unreleased (2026-10-26)

**GlassTile action tiles (`components/GlassTile.js`, `kit.css`)**
- New props `behavior` (`'perform'`, `'navigate'`, `'inert'`), `actions` (`[{id, symbol, label, on, dim, busy}]`) and `below` (force the strip under the text) and `under` (a node under it; `Mock.tileVolume(pct)` draws the remote's volume slider). Up to two actions draw as 44 pt trailing discs (left of the chevron on a navigate tile) and a `perform` tile drops its leading glyph; three or more, or `below: true`, draw a strip under the text; `inert` is the flat read-only face. Styles `.disc`, `.discs`, `.strip`, `.under`, `.flat`, `.no-glyph`. Existing tiles are unchanged.

**GlassTile disc glyph (`components/GlassTile.js`)**
- A disc draws the `power` glyph as an outline (stroke only). The kit filled every disc glyph, and `power`, a pure stroke symbol with no filled variant, became a blob. Promoted from the tile-rollout proposals' local workaround (`proposals/tile-rollout-settings-more/_rollout.js`, `RO.act`); every other disc glyph keeps the filled variant, so existing mockups change only where a disc shows `power`.

**Symbols (`lib/symbols.js`)**
- Added `backward.fill`, `forward.fill`, `speaker.fill`, `speaker.wave.3.fill` and `arrow.up.to.line`, `lock.trianglebadge.exclamationmark`, `arrow.uturn.down`, `arrow.uturn.up` (media transport, volume, shade actions) for the action-navigation-tiles proposal. No existing mockup changes.

## v3.3 (2026-10-28)
- `Mock.sheet`: documented that a fitted compact sheet is the header, the content and one bottom band (the safe area). No pixels change: the kit already drew one band; the app drew two until the detent stopped counting the safe area ([sheet-bottom-gap](../../sheet-bottom-gap.md)), so every fitted-sheet mockup now matches the app instead of understating its height. The kit's folded Duo has `safeBottom: 20` where the simulator's sheets measure 34; not changed here (it moves every Duo page).

## v3.2 (2026-10-27)
- `WeatherCard`: a disabled Previous or Next circle fades once, to 55% (was 40%), as the app now draws it ([weather-chevron-contrast](../../weather-chevron-contrast.md)).

## v3.1 (2026-10-24)

**Scroll fit (`lib/chrome.js`, `lib/mount.js`, `kit.css`)**
- New `Mock.scrollFit(el)`: measures a page (`.ui-scroll`) or sheet (`.ui-mscroll`) scroller from the rendered content height against the viewport and returns `{scrolls, content, viewport, over, cap, label, short}`; also `Mock.scrollFit.list`, `.mark` (tags `data-fit` and draws the indicator only when it scrolls), `.badge` (a live annotation, re-measured on resize) and `.bounce` (the drag-past-the-end demo, with the pull-to-refresh spinner). Rule: patterns/scroll-fit.md.
- `Mock.mount` options: `scrollFit: true | {indicator, lock, always}` prints the measurement under every device (stage and States gallery; a state may set its own `scrollFit`), and `sections: [{id, title, after?, build()}]` adds a section to the page and the Jump list.
- Styles `.k-fit`, `.k-fitrow`, `.k-sbar`, `.k-fit-flash`, `.k-pull`. Nothing is drawn unless a mockup opts in: no existing mockup changes. The kit never drew a scroll indicator (scrollbars stay hidden), so there was nothing to remove for a screen that fits; the new mockup is [components/shell/scroll-fit](../components/shell/scroll-fit/scroll-fit.html).

## v3 (2026-10-24)

**Devices and hinge posture (`lib/devices.js`, `lib/chrome.js`, `lib/reflow.js`, `lib/mount.js`)**
- `Mock.postures` (`open` fully open, `part` slightly closed), `ctx.posture`, `ctx.splitAtHinge`, `Mock.splitFrame`, `Mock.lerpFrame`, `Mock.closedFrame`. `ctx.splitGeometry` follows the owner's 2026-10-24 rule: on the hinge while slightly closed, else the midpoint of the free space. A Duo split that used to sit on the hinge in every pose now sits at the midpoint by default (`#p=part` restores the old picture).
- The hinge band draws as a faint seam when flat and a crease when closed (`data-posture`); a Hinge control and `p=` in the URL hash select it.
- `Mock.split` panes are tagged (`data-split`); new `Mock.detailPane(ctx, page, content)` is the full-height trailing pane (`--split-inset` narrows the page's scroll area and floating bar). Recipes, Inventory and Vacuums use them.
- New `Mock.reflow` (`split`, `posture`, `move`) and a kit-made "Reflow and hinge" section on every framed mockup that has a landscape window: split opens, split closes, fully open to slightly closed, slightly closed to fully open. `cfg.reflow = {state, open, close, posture}` overrides the state it plays on and adds a note.
- Component pages (`frame: false`) lay out at the device's content width (window minus the rail) and carry the hinge band; `Mock.componentConfig` defaults to all six windows. `TileGrid` reads the hinge inside a component page.

## v2 (2026-10-23)

**Loader (`kit.js`)**
- Deterministic ordered load: each file carries an `onerror` hook, a verify step re-writes the failed file and every file after it (up to four retries, brief back-off) before the page's own scripts run; `Mock.loadErrors` and the red banner report a final failure. Fixes `Mock.components.X is not a function` under parallel load. `file://` and the inline export are unchanged.

**CSS (`kit.css`)**
- Page-furniture selectors (`.k-wrap h1/h2/h3/p/code/a/ul/li/table/th/td`) no longer match inside `.screen`, `.k-device`, `.k-swatch`, `.k-plain`, `.ui-root`, `.ui-sheet`, `.in-sheet`, `.ui-host`. Section headers, SettingsSection titles and form headers inside frames lose the stray 44 pt margins and 22 px sizes (the kit rules now win).
- Grid: the scaled minimum is capped at the container width (`min(100%, ...)`): AX5 gives one full-width column and never overflows; same for the alarm mode grid. `TileGrid` equal rows keep `.gridheader` rows at their own height; the ResizeObserver work runs a frame later and only on a width or scale change (no loop warning on the Duo).
- Reduce Transparency: lit tiles keep the warm lit ground and ink, power tiles keep dark ink, error tiles keep the dense ground, and tiles in a sheet keep the sheet cell instead of the dark page solid. A power tile in a sheet keeps its dark ink in every mode.
- InlineAlert error icon is red; ImageCard AX thumbnail is 72 pt; weather hour time is 13 pt and temperature 17 pt; the weather numeral is capped at 96 pt at AX5.
- `.k-swatch` is a containing block, so overlays (flyout, scrims) stay inside their swatch in the gallery.

**Components**
- `BrightnessTile`: status line is the percent ("70%", "Off", "Unavailable"), bubble is a 60 x 32 capsule centred 24 pt above the tile (BrightnessBubble), `chevron: true` for the open-details tile; Reduce Motion drops the lift scale. `GlassTile` gains `showsChevron`.
- `CameraTile`: no state pill on the tile (CameraGrid draws only the name capsule and a red dot while live). The viewer's badge (Live, Live · Delayed, Last live 6:51 PM, Connecting, Snapshot) is `viewer: true`.
- `TabBar`: badge prints the number (system `.badge`), not "9+" (only the Profile button says 9+).
- `Alert`: every alert stacks its buttons at AX5 (reads `ctx.axSize`); optional `field`, plus `AlertField`.
- `AlarmPanel`: new `hidden` state (privacy redaction: "Hidden", neutral badge, buttons enabled).
- `ThermostatDial`: single `target` (one handle, no arc), `off`, `unavailable`, `dragging`; coloured 4 pt handle borders, status-coloured current marker with a dark rim, ring shadow, Light numeral, bold unit and a caption with a thermometer ("72.0°F" / "68.0 · 74.0"). Only a heat+cool range draws arcs in the app; `heat` or `cool` alone remain as a legacy arc.
- `WeatherCard`: 24 sample hours in pages (6 per page, 9 on regular width, scaled with text size) with the page-dot indicator and Previous and Next on regular width; pending is "--" with static placeholder hours and no briefing; `page`, `narrow`, `ctx` props.
- `Mock.page`: inline title in the bar that fades in as the large title scrolls under it; `collapsed: true` stages that state. `Mock.sheet` accepts a `ConfirmationDialog` as `alert` without a second scrim.

**New components (promoted from author helpers)**
- `ConfirmationDialog` (= `ActionSheet`), `ContentUnavailableView`, `AlertField` (in `Alert.js`), `SettingsLinkRow`, `TextToolbarButtons` / `TextToolbarButton`, `FullScreenCover` (+ `Mock.cover`). Callers of the helpers (`SA.actionSheet`, `HF.contentUnavailable`, `V.linkRow`, ...) are untouched; switch when you next edit them.

**Symbols (`lib/symbols.js`)**
- About 130 names added (303 total): every look-alike authors patched into `Mock.symbols` at run time was promoted verbatim (appliances, battery levels, windows, stairs, barcodes, sunrise and sunset, ...), and the rest were drawn. Local `if (!Mock.symbols[k])` patches become no-ops.

## v1 (2026-10-23)
- Shared kit, authoring spec and the first component set.
