# Quick link and room navigation tile (component)

> **What:** the solid-colour navigation tile used by Quick Links and the rooms grid. **Read when:** you add a Quick Link, a room colour or a navigation tile.

- Mockup: [quick-link-tile.html](quick-link-tile.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` Features/Rooms/QuickLinksSheet.swift (QuickLinkTile); HassDesign/QuickLinkPalette.swift, RoomPalette.swift, GlassTile.swift
- Spec: .agents/design/direction-g.md, patterns/entity-tile.md · Patterns: entity-tile, dynamic-grid
- States covered: seven links, five alarm modes, subtitle, unknown, redacted, singular count, in-context grids, ax5
- Motion: Security colour follows the alarm
- Devices: size class: iPhone, iPad
- Open notes:
  - Sheet surface only; fills are fixed in both appearances.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
- Rollout L (2026-10-28): Security System carries Arm Home / Disarm beside its chevron (Disarm asks first; two tracks wide; none while redacted); the other links are unchanged. Every Quick Links tile keeps the chevron.
