# Room section header (component)

> **What:** the 20 pt bold heading over a tile grid on a page or in a sheet. **Read when:** you change section headings in rooms or sheets.

- Mockup: [room-section-header.html](room-section-header.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` Features/Rooms/RoomSupport.swift; HassDesign/PageSectionHeader.swift
- Spec: .agents/design/direction-g.md, patterns/dynamic-grid.md · Patterns: dynamic-grid, room-overview-sheet
- States covered: page, sheet (inSheet), long title, in-context (page, sheet, grid header), ax5
- Motion: none
- Devices: size class: iPhone, iPad
- Open notes:
  - Duplicates PageSectionHeader (finding).
  - Kit gap: .k-wrap h2 overrides .ui-hdr h2.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
