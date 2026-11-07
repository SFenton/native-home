# DynamicGridLayout (component)
> **What:** the responsive tile grid: column count by width, equal row heights, spans, grid headers, hinge-even columns. **Read when:** you lay out tiles, cameras, quick links or pills, or change the column rules.
- Mockup: [dynamic-grid-layout.html](dynamic-grid-layout.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/DynamicGridLayout.swift`, `HassUI/Features/Home/CameraGrid.swift`, `Rooms/RoomScreen.swift`
- Spec: `.agents/patterns/dynamic-grid.md` · Patterns: dynamic-grid, entity-tile, status-pill
- States covered: variants and states (kit), widths (370 to 1162 pt with counts), spans-headers, hinge (Duo even columns), in-context, ax5 (one column)
- Motion: none (layout switches carry no animation)
- Devices: iPhone, iPad portrait, Duo unfolded landscape
- Open notes: counts come from the same formula as DynamicGridMetrics; hinge rounding applies on any unfolded Duo pose; the web content-aware spans are not ported.
