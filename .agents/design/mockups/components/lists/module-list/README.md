# ModuleList and ModuleRow (component)
> **What:** the inset list on the wallpaper (thin or dense) and on the sheet cell, with glyph, subtitle, accessory and chevron rows. **Read when:** a page shows rows rather than tiles, or you change ModuleList, ModuleRow or ModuleRowBackground.
- Mockup: [module-list.html](module-list.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/{ModuleList,Module}.swift`, `HassUI/Features/Inventory/InventoryRow.swift`, `Sprinklers/SprinklersScreen.swift`
- Spec: `.agents/patterns/module-list.md`, `.agents/design/direction-g.md` · Patterns: module-list
- States covered: variants (thin, dense, no glyph), accessories, dense-and-list (List row backgrounds), rows, in-context, ax5
- Motion: row press (0.2 s), glyph colour (0.6 s), card corners re-round when a first or last row leaves
- Devices: iPhone, iPad (size class), embedded devices
- Open notes: iOS 17 draws no hairlines; the in-context rows follow the preview in ModuleList.swift (the Security and Climate pages belong to other mockups).
