# GlassTile (component)
> **What:** the entity tile: faces by state, kinds (toggle, command, navigate, selection, state), layouts, accessory rail, wash, progress. **Read when:** you change `GlassTile`, `GlassTileFace` or add a tile.
- Mockup: [glass-tile.html](glass-tile.html) · status shipped (action and navigation tiles, #186) · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/GlassTile.swift`, `TileFaceStyle.swift`, `TileAppearance.swift`, `TileMetrics.swift`, `TileSurface.swift`, `PendingValue.swift` · Spec: `.agents/patterns/entity-tile.md`, `.agents/design/direction-g.md` · Patterns: entity-tile, optimistic-actions, dynamic-grid
- States covered: every kit variant (families on, rooms, Quick Link, stacked) and state (off, on, lit, error, pending, unavailable, progress, tinted, navigate, two-line), kinds, layouts, accessory, wash, long text, unavailable versus error, solid finish, progress, ax5; page and sheet, light and dark
- Motion: face cross-fade (0.6 s), press (opacity 0.8, no scale), symbol replace, pending pulse
- Devices: size class only (iPhone, iPad)
- Open notes: the catalog said "press scale" but the code only dims; entity-tile.md contradicts itself on `.accessibilityElement(.ignore)`; kit gaps (Power ink in a sheet, lit tile under Reduce Transparency)
- Change log: 2026-10-27 action tiles (claude/action-nav-tiles): behavior/actions, discs, strip, volume slider, flat read-only face; see patterns/action-tiles.md.
