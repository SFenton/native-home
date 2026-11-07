# Live Activity parts, corner mark, glyph, ring, buttons, severity circle (component)

> **What:** the pieces every Live Activity presentation is built from. **Read when:** you change a glyph, the ring, a button, the bar, the corner mark colours or the type scale.

- Mockup: [live-activity-parts.html](live-activity-parts.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/FentonActivityViews/CornerMark.swift`, `CornerMarkPalette.swift`, `ActivityHeaderGlyph.swift`, `ActivityGlyphImage.swift`, `ActivityRing.swift`, `ActivityButtons.swift`, `SeverityCircle.swift`, `ActivityFont.swift`, `ActivityBar.swift`, `ActivityStyle.swift` · Spec: `.agents/platforms/apple/live-activities-per-job.md`, `live-activities.md` · Patterns: none
- States covered: default (corner mark, 8 icon colours), glyphs, ring, severity, buttons, bar, type, palette, ax5
- Motion: none of its own
- Devices: iPhone (the parts are device independent)
- Open notes:
  - Doc vs code: ring is 64 pt on the Lock Screen and 34 pt beside the camera in the doc; the code has 32 pt (small) and 24 pt (island) rings and no Lock Screen ring.
  - The mark geometry is the app's own (AppIconArtwork) drawn as SVG; glyphs are stand-ins.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
