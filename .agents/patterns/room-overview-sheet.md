# Room overview sheet

> **What:** the room-by-room sheets behind Home's Lights, Climate, Occupancy, Contact Sensors and Air Quality chips, and the room detail they push. **Read when:** changing any of those sheets, the Security page's Contact Sensors sheet, or a room page's lights, climate, occupancy or contact sheet.

Web source: `ha-sfenton-react-dash@f5a7bf9:src/pages/AtAGlancePage.tsx:247-1077` (`LightsSheet`, `ClimateSheet`, `OccupancySheet`, `ContactSheet`, `AirQualitySheet`), reused by `SecurityDashboard.tsx:180` and `DashboardViewPage.tsx:830-847`.

| Piece | Native |
|---|---|
| Titles, sections, subtitles, colors | `HassCore/Rooms/RoomOverview.swift` (pure, unit tested) |
| Group data | `HassCore/Rooms/RoomGroups.swift` (`LIGHT_GROUPS`, `CLIMATE_GROUPS`, `OCCUPANCY_GROUPS`, `CONTACT_GROUPS`, one list for Home and room pages) |
| Sheet + overview grid | `HassUI/Common/RoomOverview/RoomOverviewSheet.swift` |
| Room detail (page and content) | `HassUI/Common/RoomOverview/RoomGroupDetail.swift` |
| Light tile | `HassUI/Common/RoomOverview/LightGroupTile.swift` |

## Behavior

- **One sheet, five kinds** (`RoomOverviewKind`). Each opens full height (`hassSheet(height: .full)`: it pushes pages) with Close; a room tap pushes its detail page inside the sheet's own `NavigationStack` with Back (HIG: Sheets).
- **Overview sections.** Lights split into "Lights On" / "Lights Off" and Occupancy into "Occupied" / "Clear" (active first, an empty section dropped). Climate, Contact Sensors and Air Quality list every room under "Rooms". Headings sit inside the grid (`gridHeader()`), so every card in the sheet shares one height.
- **Room cards.** Title is the room; subtitle per web: lights "On" / "3 On" / group state ("Off"), climate the range helper truncated to one decimal (else the sensors' min–max, else "N sensors"), occupancy "Occupied" / "Not Occupied", contacts "Door Open" / "All Windows Closed" / "2 Doors Open". Direction G faces (2026-10-15, `RoomOverviewStyle.isFilled`): a room with lights on is the lit tile, an occupied room or one with a door open fills with its colour family (occupancy green, contact soft green), and the rest stay dark with the family glyph. Climate and Air Quality cards never fill (they always report), so climate shows the dark tile with its glyph, and Air Quality cards are read-only with the glyph and rim in each room's AQI colour (the AQI scale is the information). The web's per-room colour washes are gone; the HassCore colour helpers stay for the web parity tests.
- **Sheet title.** On iOS 26 and later the name is centred with its state as the navigation subtitle (`RoomOverview.sheetName` and `sheetSubtitle`, `.sheetSubtitle(_:)`): Lights "3 of 12 On" or "All Off", Occupancy "2 Rooms Occupied" or "All Clear", Contact Sensors "2 Open" or "All Closed"; Climate and Air Quality have none. Earlier systems keep the web title with its count ("Lights (3 On)").
- **Sheet titles.** "Lights (3 On)" / "Lights (All Off)", then "Climate", "Occupancy", "Contact Sensors", "Air Quality". Detail pages take the web group title ("Living Room Lights", "Gym Light", "Office Climate", "Hallway Occupancy", "Entryway Contact Sensors") with the live subtitle as the page's first line (occupancy: "2 sensors occupied").
- **Room detail.** Lights: "Lights" heading, the room's group light as one full-width brightness tile when the room has several lights on a `light.` group, then each light (`LightGroupTile`: brightness tile when dimmable, else power tile; nightstands personalize to "Your Nightstand"). Climate: "Temperature Sensor(s)" and "Vent(s)" runs, temperature tiles dark with the climate glyph, and vent tiles in the Vents family: filled while open with the position as the state ("Open · 50%", the same `ClimateLogic.isVentOpen` / `ventSubtitle` rule as Climate Advanced Controls), dark with the glyph while closed (direction G drops the temperature colours). Occupancy and contacts: "Occupancy Sensor(s)" / "Contact Sensor(s)" heading on Home, none on room pages (the sheet title names the group). Sensor tiles are read-only (`.state`).
- **Light commands** are explicit `turn_on` / `turn_off` and brightness through `LightControl`, never `toggle` (the web sheet sends `homeassistant.toggle`; Presence Based Lighting's Presence Lock reverts toggles). This is a recorded departure from web parity. Home's detail page shows the new power at once through `OptimisticActions` with `.liveChange` (a rejected call rolls back, a PBL revert wins); room pages go through `RoomController`.
- **Equal tile heights.** Every grid uses `DynamicGridLayout(equalRowHeights: true)` inside `.equalHeightTiles()`: the tallest tile (Primary Bedroom Closet wrapping to two lines on an iPhone) sets every row's height, measured on each layout pass so it follows Dynamic Type and rotation.
- **Chip summaries** (`HomeConfig.summary`): Lights counts each room light once ("All Off" / "3 On"), Contact Sensors each contact sensor ("All Closed" / "2 Open"), Occupancy reads "Detected" / "Clear", Air Quality "AQI x · PM2.5 y" from the house range helpers.
- **Privacy.** With `FENTON_REDACT_PRIVATE` set, occupancy subtitles read "Hidden" and the tiles stay dark.
- **Identifiers.** `overview.<kind>`, `overview.<kind>.section.<title>`, `overview.<kind>.room.<room>`, `overview.detail.<room>`, `overview.detail.subtitle`, `room.lightGroup.<entity>`, `room.light.<entity>`, `room.entity.<entity>`.

## Consumers

Home (`HomeScreen` chip sheets), Security (`SecurityPage` Contact Sensors chip), room pages (`RoomSheetBody` lights, climate, occupancy, contacts, and the all-rooms contact sheet for Back Deck and Garage).

- **Owned files** (also in `contracts/patterns.json`): `AirQualityRoomTile.swift`, `RoomGroupDetailPage.swift`, `RoomOverviewGrid.swift`, `RoomOverviewTile.swift`.
