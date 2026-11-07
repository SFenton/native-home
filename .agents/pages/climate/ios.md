# Climate (iPhone, iPhone Duo and iPad)

> **What:** how the Climate spec is built natively. **Read when:** changing `HassUI/Features/Climate` or `HassCore/Climate`.

## Code

| Piece | File |
|---|---|
| Entity ids, rooms, copy, tabs, option presentation | `HassCore/Config/ClimateConfig.swift` |
| Pure rules (effective away, notices, tracking summary, options, predictive metrics and bullets) | `HassCore/Climate/ClimateLogic.swift` |
| Actions and optimistic state over one `HassServiceCalling` | `HassCore/Climate/ClimateController.swift` |
| Page | `HassUI/Features/Climate/ClimateScreen.swift` (`ClimateScreen` binds the connection; `ClimatePage` takes a controller) |
| Sheet shell and `ClimateRoute` | `HassUI/Features/Climate/ClimateSheet.swift` |
| Form pieces (`ClimateForm`, row label, toggle row and section) | `HassUI/Features/Climate/ClimateFormPieces.swift` |
| Rooms tab and room detail | `HassUI/Features/Climate/ClimateRoomsTab.swift` |
| Automation tab, Predictive Comfort and Eco option pages | `HassUI/Features/Climate/ClimateAutomationTab.swift` |
| Tracking tab and its room pages | `HassUI/Features/Climate/ClimateTrackingTab.swift` |
| Page notice | `HassUI/Features/Climate/ClimateNotice.swift` |
| Thermostat Hub pill and its pop-up menus | `HassUI/Features/Climate/ClimateHubPill.swift` |
| Colours and symbols (`ClimateStyle`) | `HassUI/Features/Climate/ClimateComponents.swift` |
| Gallery and fixtures | `HassUI/Features/Gallery/ClimateGallery.swift` |

## Native decisions

- **Always full width, push** ([split-view](../../design/apple/split-view.md)); the advanced controls are a `.large` sheet with its own `NavigationStack` ([modal-sheet](../../patterns/modal-sheet.md)), so every device and pose is single page inside the sheet. HIG: Sheets, Navigation.
- Direction G (mockup n3). Page: "Whole Home" with the dial straight on the wallpaper (no card; owner 2026-10-16: "takes up too much space now and I don't want the card background", back to the pre-G arrangement with G's dial and colours), the compact Thermostat Hub pill under it (`ThermostatHubPill`: one thin module row with the hub's glyph, name and state and the mode and fan as two icon pop-up menus; at accessibility sizes the menus drop under the text and show their value), the away notice and the integration warning (`ClimateNotice`, dense when a warning), open contacts as contact-family `GlassTile`s (read-only, not buttons), then "Advanced Controls" rows that open the sheet on their tab.
- The hub's mode and fan are pop-up menus (`HubPicker`: a `Menu` holding an inline `Picker`, so the current choice is checked and read as selected; the label is the value and an up-down chevron at 44 pt, since a bare `Picker(.menu)` keeps a smaller UIKit hit area). HIG: Pop-up buttons.
- Sheet: dark system `Form`s (the sheet's ground and cells) with section text in `FormHeader` / `FormFooter`; the tabs are the shared bottom `modalTabBar` (segmented; a menu at accessibility sizes); titles are inline bar titles. Toggles are system switches (`homeassistant.toggle`; Predictive Comfort sends `switch.turn_on` / `turn_off`, and "Current Prediction" shows while it is on). Eco options are checkmark rows that read the choice and its description; tracking rooms are checkmark buttons with On/Off values; metrics are read-only `LabeledContent`.
- **Rooms tab and room modal** (owner 2026-10-16: rooms as tiles like other pages, vents as tiles in the room's modal). The Rooms tab is a grid of room tiles (`ClimateRoomsTab`): the Rooms grid's `RoomPalette` fill, the room's grid glyph filled in white, the name, and temperature and occupancy as the state ("70.9°F · Occupied"). A tap pushes the room through `onOpen`; identifier `climate.room.<key>`. A room's modal shows its dial and then its vents as read-only Vents-family tiles (`kind: .state`): filled while open (`ClimateLogic.isVentOpen`), the position as the state ("Open · 50%", `ClimateLogic.ventSubtitle`, from the cover's `current_position`), unavailable dimmed; identifier `climate.vent.<entity>`. The web's vents are read-only too (`ClimateCard`, `DashboardViewPage.tsx:7094`), so there is no vent control to open. Missing selects or disabled tracking show an `InlineAlert`. HIG: Toggles, Lists.
- Dials reuse `ClimateThermostatDial` (page size for Whole Home, modal size in a room), passing `action` for the Whole Home action line and the controller's `caller`. HIG: Accessibility › VoiceOver (adjustable handles).
- The page and sheet columns cap at 720 pt on iPad (HIG: Layout, readable width).

## Tests

- Unit: `HassCoreTests/ClimateLogicTests.swift` (config, formatting, effective away, notices, contacts, tracking summary counts, option presentation, predictive metrics and reason bullets), `ClimateControllerTests.swift` (toggle, explicit switch, select, hub mode/fan, revert, failure, unavailable).
- Hosted: `HassUITests/ClimateViewTests.swift` renders the page (both fixtures, phone and tablet, AX5), every tab, every detail route, the hub pop-up menus, plus fan-out, routing and the gallery recorder's climate echoes.
- Journeys: `ClimateJourneyTestCase` and its area classes (`Apps/iOSUITests/Climate*JourneyTests.swift`; see [testing](../../testing/apple/README.md)) on the gallery (`FENTON_GALLERY=climate`; `FENTON_GALLERY_CLIMATE_OPEN=<tab|route>`, `FENTON_GALLERY_CLIMATE_SCENARIO=away`, `FENTON_GALLERY_CLEAN=1`) for everything that taps a control; one signed-in journey only reads the live page. Audits (with the AX5 relaunch) cover the page (home and away), the open hub menu, each tab, a room, Predictive Comfort, an eco option page and a tracking page; iPad also in landscape.
- Screenshots: the `testCaptureClimate<View>` tests name `climate-<view>-<orientation>`; the host renames them `climate-<view>-<device>.png`.
