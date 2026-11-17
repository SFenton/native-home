# Tile swipe, words, ink and groups

> **What:** the four tile-contract capabilities the native app draws. **Read when:** touching a tile's swipe, state line, idle ink or a grouped grid.

Code: `UKTileSwipeController`, `HassDesign/TileSwipe`, `TileInkDefault`, `UKServerUIGridGrouping`.

## Swipe to adjust (`sh.tile-swipe@1`)

- A horizontal drag sets the number under the finger: absolute, snapped to `step`, clamped, mirrored in right to left.
- One call on release, only if the value changed. A cancel, scroll, edge swipe, fold or leaving the app sends nothing.
- Band and state line follow the finger with no `configure`; a republish waits for the release.
- The tile lifts 1.03, none with Reduce Motion. A bubble names the value above the tile.
- Bubble: dark capsule, 32 pt tall, 60 pt wide at least, 12 pt padding, semibold 15 pt monospaced digits.
- Bubble at accessibility sizes: 44 pt tall, 84 pt wide at least. At most the tile's width, 8 pt clear above, 4 pt inside the scroller's top.
- A tick at each detent line crossed, ends included, one per sample, never on the first.
- Absent means off: no pan, no adjustable trait, no hint. Existing light tiles keep the 0 to 100 by 10 brightness swipe.
- VoiceOver: adjustable, the value, increment and decrement by one detent, named actions "Increase" and "Decrease" plus the label.
- Not the swipe: a vertical start, a disc, a horizontal scroller above, the edge pans, another tile dragging.
- HIG: Sliders, Gestures, Accessibility. Departure: `UKTileVolumeSlider` keeps its own drag, its handle sits inside the tile.

## State words (`sh.state-words@1`)

- A light group tile, brightness tile and room overview tile say the document's `on`, `off`, `unavailable`, `count`, `level`.
- `count` holds `{count}`, `level` holds `{value}`. The state line, the spoken value and the bubble use them; production's text fills the rest.

## Tile ink (`sh.tile-ink-default@1`)

- A document that declares it draws an idle or tinted icon with no colour of its own, and the state line, in the primary ink.
- Primary is white on a dark face and black on a light sheet. Lit, filled, error, authored tint and family keep their ink.
- A warning keeps its amber. Unavailable stays grey at 50%.
- A document without the id keeps today's grey.

## Groups by state (`sh.grid-state-groups@1`)

- A tile-grid puts its tiles under one to three headings by the face each draws: lit, idle, unavailable.
- Headings are the section heading, header trait, a full row. A group with no tile is dropped. Columns are solved once.
- A tile whose face changed moves as the same view. A person's tap slides it on the standard duration.
- A change the house made, a snapshot or a reconnect moves with no animation. Nothing moves under a finger or a scroll.
- Reduce Motion: the moved tile fades in on the quick duration. A `LayoutChange` signpost spans the move.
