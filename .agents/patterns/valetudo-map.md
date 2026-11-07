# Mapped map

> **What:** decoding and drawing a Mapped map (rooms, walls, robot, dock, paths, areas). **Read when:** showing a vacuum map anywhere.

Web source: `ha-sfenton-react-dash@9ac2a46:src/components/hass/ValetudoMapCard.tsx`, `ValetudoMapCard.utils.ts`, `ValetudoMapGeometry.ts`, `ValetudoMapFocus.ts`.

| Piece | File |
|---|---|
| PNG `zTXt` → map JSON, layers, entities, rooms | `HassCore/Vacuums/ValetudoMap.swift` |
| Focus (crop to the configured rooms) | `HassCore/Vacuums/ValetudoMapFocus.swift` |
| Rotation, viewport, area rectangles | `HassCore/Vacuums/ValetudoMapGeometry.swift` |
| Colors and materials | `HassCore/Vacuums/ValetudoMapStyle.swift` |
| Loading and polling | `HassCore/Vacuums/ValetudoMapLoader.swift` |
| Canvas and scene | `HassUI/Features/Vacuums/ValetudoMapView.swift` |
| Fixture maps for the gallery and tests | `ValetudoMapFixtures` in `ValetudoMapStyle.swift` |

- The map camera's `entity_picture` is a PNG whose `zTXt` chunk holds the Mapped JSON (zlib); pixels are run-length `[x, y, count]` or compressed per layer. Decoding is pure and tested against the web's expectations.
- `ValetudoMapScene` rasterises floor, segments and walls once into one pixel per cell, scaled with nearest-neighbour sampling, so pan and zoom only redraw vectors and icons.
- Focus crops a shared map to a vacuum's rooms (Studio, Media Room) and keeps walls only near them; area drawing is limited to the interaction bounds.
- A reported (unavailable) map drops paths and the live robot style.
- Direction G draws the map flat on `#262628` (`ValetudoMapScene.Palette`; no material accents): neutral rooms, selected rooms white with black numbered badges (`roomOrders`, hidden from VoiceOver), rooms skipped by Auto-Clean hatched (`skippedRooms`). Each room's mask is built once with the cells, so selection never rasterises again.
- **Room names are NOT drawn** (owner, 2026-10-28, reversing the 2026-10-24 "Room names are always drawn" rule): the map carries no text except the order badge on a selected room. Rooms are named by the Rooms section, the Selected Rooms summary and VoiceOver, so removing `drawNames` also removes a per-draw `Text` resolve and measure for every room (measure with `tools/ios_scrollcost.sh`). The area editor and the report use the same map without names. **Locate stays the floating glass circle** on the map's top-left corner, not a tile ([vacuum-sheet-redesign](../design/vacuum-sheet-redesign.md)).
