# Colour families and palettes (component)
> **What:** the colours that say what a thing is: device families, alarm modes, Chores and Food families, room and Quick Link fills, with live contrast. **Read when:** you add a family, a tile or chip colour, or check a contrast.
- Mockup: [color-families.html](color-families.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/ColorFamily.swift`, `ColorFamily+Glass.swift`, `HassTokens.swift`, `RoomPalette.swift`, `QuickLinkPalette.swift`, `FinishColor.swift`, `ChipTint.swift` · Spec: `.agents/design/direction-g.md`, `.agents/patterns/entity-tile.md`
- States covered: families (on, off, in a sheet), security, chores-food, rooms (16), quick-links, values (hex and computed contrast), glyph-off (the 72% and 88% mixes), ink-surface (HassTokens), ax5
- Motion: tile fill (0.6 s). Transitions: none
- Devices: size class only (iPhone, iPad); page and sheet surfaces, light and dark
- Open notes: kit family names differ from Swift (spice, chore-resident1); the tinted-glass lift of the off glyph is not drawn; Power in a sheet loses its dark secondary ink in the kit
