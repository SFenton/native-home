# Room page (page)

> **What:** the config-driven room page: status rail then titled sections in a responsive grid, one template for sixteen rooms. **Read when:** you change a room page, a card or chip, or add a room.

- Mockup: [room-page.html](room-page.html) · status in flight (`claude/section-sides`) (action and navigation tiles, #186) · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` RoomScreen.swift; RoomTiles.swift; RoomSupport.swift; BathroomFanRoomTile.swift; RoomDeviceRouting.swift (Features/Rooms); HassCore/Rooms/RoomsConfig.swift, RoomController.swift
- Spec: .agents/pages/rooms/spec.md, ios.md · Patterns: status-rail, entity-tile, dynamic-grid, room-device-sheets, room-overview-sheet
- States covered: default (Living Room), loading, refreshing, empty (Hallway), error, offline, reconnecting (+ was), long-text (Media Room), ax5, placeholder, active, window-armed, lead-row, fan-on-timed, fan-unavailable, music-room, office, back-deck, garage
- Motion: tile optimistic flip, chip colour, glyph replace, fan countdown; transitions: card to sheet, chip to sheet, Quick Links to room (push), Back
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape
- Open notes:
  - no rail is unreachable (every room has at least one chip); loading has no gate (cards read Unavailable).
  - Unfolded Duo landscape: the second section column starts inside the hinge band (unverified on device).
  - Kit gaps found: .k-wrap h2 overrides .ui-hdr h2; power tiles in sheets lose dark ink (both patched locally in pages/rooms/_rooms.js).
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
- Change log: 2026-10-27 action tiles (claude/action-nav-tiles). PCs, towel racks and garage doors read text . disc (power / door disc); the vacuum is a navigation tile with start/pause and dock discs left of the chevron; the bathroom fan's Lock and Power are discs (room.card.Fan.action.lock|power); a playing remote shows transport and volume below; read-only tiles are flat. Shared helper pages/rooms/_rooms.js carries the change.
- Change log: 2026-10-28 tile rollout R: Air Purifier and Humidifier gain a Power disc, bed sides a confirmed Power disc, Studio sources the selected face with a check disc, Handheld Console and Media Room streaming box a tracked power disc; Vents stay a navigation tile with no disc.
- In flight (`claude/section-sides`, [section-sides](../../../../section-sides.md)): partly folded Duo, each section wholly on one side (fold columns); state `duo-part-fold`. Every other pose unchanged.
