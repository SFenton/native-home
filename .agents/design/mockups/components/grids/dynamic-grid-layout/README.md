# DynamicGridLayout (component)
> **What:** the responsive tile grid: column count by width, equal row heights, spans, grid headers, hinge-even columns. **Read when:** you lay out tiles, cameras, quick links or pills, or change the column rules.
- Mockup: [dynamic-grid-layout.html](dynamic-grid-layout.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/DynamicGridLayout.swift`, `HassCore/ServerUIComposition/ServerUIGridGroups.swift`, `HassUI/UIKitPort/ServerUI/UKServerUIGridGrouping.swift`, `HassUI/Features/Home/CameraGrid.swift`, `Rooms/RoomScreen.swift`
- Spec: `.agents/patterns/dynamic-grid.md` · Patterns: dynamic-grid, entity-tile, status-pill
- State groups (`sh.grid-state-groups@1`): title-only headings in one grid on iPhone, Duo folded, Duo unfolded landscape and iPad; the preset on a page and in a sheet; an empty group dropped; authored state words; AX5
- States covered: variants and states (kit), widths (370 to 1162 pt with counts), spans-headers, hinge (Duo even columns), in-context, ax5 (one column)
- Motion: a tile changing group (a person's tap slides it on standard 0.3 s, Reduce Motion fades it in 0.2 s; a house change does not animate); layout switches carry no animation
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes: state groups follow the hosted still `groups.png` and hosted tests; a hinge band crossing a grouped page grid is not captured; helpers in `components/tiles/_tile-contract.js`. Counts come from the same formula as DynamicGridMetrics; hinge rounding applies on any unfolded Duo pose; the web content-aware spans are not ported.
