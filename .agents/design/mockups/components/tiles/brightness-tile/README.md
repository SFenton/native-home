# Brightness tile (component)
> **What:** The light dragger: the lit tile whose bright band is the brightness; tap, drag, bubble, lift. **Read when:** you change `BrightnessTile` or a screen that uses it.
- Mockup: [brightness-tile.html](brightness-tile.html) · status shipped · reviewed 2026-10-23
- Source: `HassDesign/BrightnessTile.swift`, `HassDesign/GlassTile.swift` · Spec: `.agents/design/direction-g.md`, `.agents/patterns/entity-tile.md` · Patterns: entity-tile
- States covered: on (with and without chevron), off, colour fill, dragging, unavailable, ax5 on page and sheet
- Motion: drag (quick), power flip
- Devices: size classes via the Device control
- Open notes: kit BrightnessTile says "On at 70%" and has no chevron; the app says "70%"; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
