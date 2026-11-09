# Valetudo map canvas and map frame (component)
> **What:** the vacuum map on its dark card: rooms, selection badges (no room names, owner 2026-10-28), hatching, robot, dock, path, area, fallbacks. **Read when:** you change `ValetudoMapView` or the map frame.
- Mockup: [vacuum-map-canvas.html](vacuum-map-canvas.html) · status shipped (PR #210) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Vacuums/ValetudoMapView.swift, VacuumMapPanel.swift, HassCore/Vacuums/ValetudoMapStyle.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/valetudo-map.md` · Patterns: valetudo-map, vacuum-sheet
- States covered: flat rooms (three robots), selected, skipped (hatched), robot docked/cleaning/last reported, area and handles, frame (default, grown, no Locate), loading, unavailable, ax5
- Motion: map growth (0.28 s), room selection (none)
- Devices: compact and regular width (dark card, both appearances)
- Open notes: stand-in floor plan, not a decoded Valetudo map; Main Floor is rotated 180 degrees
