# Media tile (component)
> **What:** The Media page tile: lead tile that opens a remote, or a source tile that runs in place, in the media pink family. **Read when:** you change `MediaCardTile`.
- Mockup: [media-card-tile.html](media-card-tile.html) · status shipped (action and navigation tiles, #186) · reviewed 2026-10-23
- Source: `HassUI/Features/Media/MediaScreen.swift`, `HassDesign/GlassTile.swift` · Spec: `.agents/patterns/entity-tile.md`, `.agents/pages/media/ios.md` · Patterns: entity-tile
- States covered: lead (off, playing, unavailable), source (off, on, unavailable), pending, wraps, ax5 on page and sheet
- Motion: tile fill (state)
- Devices: size classes via the Device control
- Open notes: uses the kit GlassTile with card data from MediaPageConfig; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
- Change log: 2026-10-27 action tiles (claude/action-nav-tiles): behavior/actions, discs, strip, volume slider, flat read-only face; see patterns/action-tiles.md.
- Change log: 2026-10-28 tile rollout R: sources draw the selected face; Switch and streaming box an action tile with a tracked power disc.
