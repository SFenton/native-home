# Tile finish and layouts (component)
> **What:** tinted glass against the solid fallback, its layers and tokens, and the four tile arrangements. **Read when:** you change `TileFinish`, `TileLayout` or the tinted glass layers.
- Mockup: [tile-finish-layout.html](tile-finish-layout.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/TileFinish.swift`, `TileLayout.swift`, `TileMetrics.swift`, `TintedGlassGround.swift`, `TintedGlassRim.swift`, `TintedGlassSheen.swift`, `TintedGlassEdge.swift` · Spec: `.agents/design/direction-g.md`, `.agents/patterns/entity-tile.md`, `.agents/testing/apple/performance.md`
- States covered: finishes (tinted glass, solid, sheet), layers (build-up), tokens, layouts (row, anchored bottom, centred stack, stacked top), title-reserve (two lines), solid, ax5
- Motion: none of its own (the colour fade is GlassTile's). Transitions: none
- Devices: size class only (iPhone, iPad)
- Open notes: centred stack and stacked top are gallery-only arrangements drawn with local style; the kit repaints a lit tile dark under Reduce Transparency (kit gap)
