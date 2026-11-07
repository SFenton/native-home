# Rooms

> **What:** the sixteen config-driven room pages, Quick Links and the room grid. **Read when:** changing a room, its cards or sheets, or adding a page Quick Links opens.

Source: `ha-sfenton-react-dash@9ac2a46` `src/constants/roomPages.ts` (`ROOM_PAGE_CONFIGS`), `src/pages/DashboardViewPage.tsx` (`SourceRoomPage`, `RoomSourceModal`, `KitchenGroceriesSection`), `src/components/hass/GlobalQuickLinksAction.tsx`, `RoomNavigationGrid.tsx`, `roomAccessRanking.ts`. Native config: `HassCore/Rooms/RoomsConfig.swift` (card for card), groups in `RoomGroups.swift`.

## Page

- Status rail of overview cards (Lights, Climate, Occupancy, Window/Door, Air Quality), then titled sections.
- Section layouts: `grid` (2 to 4 columns), `leadRow` (first card alone, then two filling columns when more than 2 follow), `twoColumnFill`, `appLaunch` (the room remote's app tiles, full width). A page's only section spans the full width.
- Rooms with no sections show "Nothing Here Yet!" / "Once some devices are added to this room, we can display them here." The Kitchen always shows its Groceries section (Grocery List, Food & Recipes).
- Studio cards act through the room remote's optimistic state (`optimisticRemoteId`), so its source tiles and remote sheet agree.

## Cards

- Subtitle: subtitle entities joined with " • " (with units), else the state label when `showState`.
- Dimmed: unavailable, a `disabledStates` state, or an inactive light/fan/grill/media/power card. Unavailable cards do nothing.
- Washes: `stateColors` (towel rack on), Eight Sleep `hvac_action` (heating, cooling, idle; off with presence).
- Personal titles: "Your Side" / "Your PC" for the signed-in resident, "<Name>'s Side" for the other.
- Actions: towel racks flip with explicit `turn_on` / `turn_off` (never `toggle`); PCs press their on/off `input_button` from the shown power state; Studio sources run the remote's toggles.

## Sheets

Resolution order follows `RoomSourceModal`: beds, media remotes, bathroom fan, humidifier, vacuum, wake light, dishwasher, fixed items (vents), the room's light / climate / occupancy / contact groups (rooms without a contact group list every room's doors and windows), air quality, grill, else a fallback. Titles read "Kitchen Lights" for group sheets and "Living Room: Robot Vacuum" for devices. Device sheets come from their lanes (room device sheets, Vacuums); the dishwasher still lists the card's entities read-only until its lane lands.

## Quick Links

Rooms (room grid inside the sheet), Security System (alarm state, tinted by state), Food & Recipes ("12 Items • 2 Expiring Soon"), Vacuums, Media, Custom Lights, Sprinklers (only while `input_boolean.demo_input_boolean_3` is on). Page links close the sheet and push their page. Security System carries the Arm Home / Disarm disc and, where two tracks cannot hold its text, disc and chevron, takes a full row: the folded Duo's sheet is then five rows and scrolls (owner, 2026-11-01; [action-tiles](../../patterns/action-tiles.md)).

## Room grid

All sixteen rooms ranked by `counter.demo_media_room_<room>` (ties keep config order). Opening a room calls `script.turn_on` on `script.demo_script_2` with `variables.room`.
