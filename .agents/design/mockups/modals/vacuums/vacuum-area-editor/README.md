# Vacuum area editor (pushed) (modal)
> **What:** the page pushed inside the vacuum sheet to draw one cleaning rectangle on the live map. **Read when:** you change `VacuumAreaEditor` or `MapAreaEdit`.
- Mockup: [vacuum-area-editor.html](vacuum-area-editor.html) · status shipped (PR #210) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Vacuums/VacuumAreaEditor.swift, ValetudoMapView.swift, HassCore/Vacuums/MapAreaEdit.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/valetudo-map.md, vacuum-sheet.md` · Patterns: valetudo-map, vacuum-sheet, modal-sheet
- States covered: draw mode, drawing, drawn with handles, zoomed, outside the focus rooms, map unavailable, VoiceOver actions, offline, large, closed, ax5
- Motion: tool fill (0.6 s), direct-manipulation drawing; transition: push from Controls
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (page sheet)
- Open notes: the map draws no room names (owner 2026-10-28); corner handles are 16 pt drawn with a 22 pt reach (departure); dimensions are illustrative
