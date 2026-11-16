# Climate (iPhone, iPhone Duo and iPad)

> **What:** how the renderer draws the Climate spec. **Read when:** changing the published Climate pages or `HassCore/Climate`.

Climate is composed from the publication ([architecture](../../platforms/apple/architecture.md#server-driven-root)). Logic stays in `HassCore/Climate` (`ClimateLogic`, `ClimateController`) and `HassCore/Config/ClimateConfig.swift`, rendered through the `ServerUIClimate*` composition types and `UIKitPort/Features/Climate`.

- **Always full width, push** ([split-view](../../design/apple/split-view.md)); the advanced controls are a `.large` sheet with its own stack ([modal-sheet](../../patterns/modal-sheet.md)), so every device and pose is single page inside the sheet. HIG: Sheets, Navigation.
- **Page.** "Whole Home" with the dial straight on the wallpaper (no card), then the compact Thermostat Hub pill under it.
  - The pill shows glyph, name and state, with mode and fan as two icon pop-up menus that drop under the text at accessibility sizes.
  - Below it come the away notice, the integration warning, open contacts as read-only contact-family tiles, and "Advanced Controls" rows that open the sheet on their tab.
- **Pop-up menus.** The hub's mode and fan are menus holding an inline picker, so the current choice is checked and read as selected; the label is the value and an up-down chevron at 44 pt. HIG: Pop-up buttons.
- **Sheet.** Dark system forms with section text as header and footer; the tabs are the shared bottom modal tab bar (a menu at accessibility sizes); titles are inline.
  - Toggles are system switches. Predictive Comfort sends `switch.turn_on` or `turn_off`, and "Current Prediction" shows while it is on.
  - Eco options are checkmark rows; tracking rooms are checkmark buttons with On and Off values; metrics are read-only.
- **Rooms tab.** A grid of room tiles in the Rooms grid's palette with the room glyph, the name, and temperature and occupancy as the state ("70.9°F · Occupied").
- **Room modal.** It shows the room's dial, then its vents as read-only Vents-family tiles: filled while open, the position as the state ("Open · 50%"), unavailable dimmed. The web's vents are read-only too (`ClimateCard`, `DashboardViewPage.tsx`), so no vent control opens. Missing selects or disabled tracking show an inline alert. HIG: Toggles, Lists.
- **Dials** reuse the canonical thermostat dial ([thermostat-dial](../../patterns/thermostat-dial.md)): page size for Whole Home, modal size in a room. HIG: Accessibility, VoiceOver (adjustable handles).
- The page and sheet columns cap at 720 pt on iPad. HIG: Layout, readable width.
