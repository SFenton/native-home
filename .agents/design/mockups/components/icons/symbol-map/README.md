# SF Symbol map (component)
> **What:** the MDI name to SF Symbol table (SymbolMap, FoodSymbols), colour family glyphs and modal tab symbols. **Read when:** a ported surface uses a new MDI icon or you change a family colour.
- Mockup: [symbol-map.html](symbol-map.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/SymbolMap.swift`, `apple/Sources/HassUI/Features/Food/FoodHubScreen.swift`, `apple/Sources/HassUI/Features/Vacuums/VacuumComponents.swift` · Spec: .agents/design/direction-g.md, .agents/patterns/entity-tile.md · Patterns: entity-tile, modal-sheet
- States covered: the full table (filterable), Food and vacuum overrides, fallback, family glyphs and fills, tab symbols, ax5
- Motion: none
- Devices: iPhone and iPad size classes
- Open notes: two tables should merge; mdi:apple maps to a brand symbol
