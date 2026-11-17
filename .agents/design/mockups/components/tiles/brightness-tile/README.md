# Brightness tile (component)
> **What:** The light dragger: the lit tile whose bright band is the brightness; tap, drag, bubble, lift. **Read when:** you change `BrightnessTile` or a screen that uses it.
- Mockup: [brightness-tile.html](brightness-tile.html) · status shipped · reviewed 2026-10-23
- Source: `HassDesign/BrightnessTile.swift`, `HassDesign/TileSwipe.swift`, `HassDesign/TileInkDefault.swift`, `HassDesign/TileFaceInk.swift`, `HassUI/UIKitPort/Design/UKBrightnessTileView.swift`, `UKTileSwipeController.swift` · Spec: `.agents/design/direction-g.md`, `.agents/patterns/entity-tile.md`, `.agents/patterns/tile-swipe.md` · Patterns: entity-tile, tile-swipe
- States covered: on (with and without chevron), off, colour fill, dragging, unavailable, ax5 on page and sheet
- Tile contract states: swipe tracking (the bubble at the minimum, over the edge and at the maximum, at tile widths 170, 179 and 192 pt for Duo folded, iPhone and iPad), detents, right to left and the top row, the accessibility bubble, state words, tile ink (with and without `sh.tile-ink-default@1`; grey unavailable)
- Motion: drag (quick), a swipe across the detents, power flip
- Devices: size classes via the Device control
- Open notes: the contract states follow the hosted stills in `build/evidence/screens/native-tilecontract-fba79957` (no device run of the swipe yet); helpers in `components/tiles/_tile-contract.js` (promote to kit); kit BrightnessTile says "On at 70%" and has no chevron; the app says "70%"; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
