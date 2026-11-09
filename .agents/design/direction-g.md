# Design direction G: native on the house

> **What:** the visual language for every page and sheet (owner choice, 2026-10-13: Apple system components on the blurred house photo, after rejecting custom looks as "very Android and too far removed from Apple"). **Read when:** building or restyling any screen, tile, chip, sheet or spinner.

Mockups of every screen live on the owner's private gallery (the owner's private mockup gallery, link kept outside the repo); the HTML sources are in the project's shared folder, not this public repo. Owner decisions win over this file, and HIG *must* rules win over both. The build order is in [direction-g-plan.md](direction-g-plan.md).

## The idea

S+H (formerly Fenton Home) should look like Apple made it, with Apple Home and Apple Weather as the reference. Distinctiveness comes from three places:
- the house wallpaper;
- a few signature controls: the thermostat dial from main, the light dragger and the remote;
- putting cameras and climate up front.

It never comes from custom chrome, custom surfaces or a custom palette.

## Layers

| Layer | Look | Where |
|---|---|---|
| Wallpaper | The house photo (`/local/images/house.webp`), blurred 16.8 pt (the web's `blur(16px)` under its `scale(1.05)`, owner 2026-10-17: "less blur on the background image. Get us closer to web"; the user can change it in Settings → Appearance → Background Blur, 0 to 33.6 pt), saturation 1.1, scaled 1.06, under a dark scrim. The scrim runs 0.44 → 0.45 (28%) → 0.46 (50%) → 0.52 → 0.64 from top to bottom; the top half stays at 0.44 or more so white titles and headers pass 4.5:1 over a light sky (2026-10-14 audit; raised from 0.40 and 0.42 on 2026-10-17, when the web-matched blur kept more of the roofline's detail: the 30 to 40% band measured 4.3:1 at the old stops, 4.96:1 at these, on the house photo at the default blur). Render it once at the window's pixel size (blurred in points, not in image pixels), cache the bitmap in memory and on disk, and never run a live `.blur` per frame ([page-backdrop](../patterns/page-backdrop.md) R8). | Every tab root and pushed page, on every platform. Never in sheets. |
| Modules on the wallpaper | `systemGray6` dark at 55% with a 30pt background blur (thin material); built as `#1C1C1E` at 66% with no live blur, because the wallpaper is already blurred and a backdrop layer per tile cost GPU time (and crashed the simulator's render server, 2026-10-14). 26pt radius, no rim or bevel, white text. A module that carries red or orange status text (overdue chores, expired food, an error tile) uses the denser `rgba(20,20,22,.78)` so that text stays readable over the lit windows. | Cards, inset lists and tiles on pages. These are content-layer materials and never `.glassEffect` (HIG must). |
| Sheets | System sheet in the **system appearance** (owner decision, 2026-10-15). Dark: `#1C1C1E` ground, `#2C2C2E` cells and tiles. Light: `#F2F2F7` ground (`systemGroupedBackground`), white cells and tiles (`secondarySystemGroupedBackground`), label ink. The presenting page scales back and dims. | Every modal, except the ones that are dark by design (below). |
| Liquid Glass | System glass. iOS 17–25 fall back to `.ultraThinMaterial` capsules. | Navigation only: the tab bar, the Quick Links and Profile header circles, toolbar circles (Back, Close, Cancel, Save), bottom section controls and page bottom toolbars. |

Pages are always dark-styled because they sit on the dimmed photo, the way Apple Home's wallpaper works. Sheets follow the system appearance, like Apple's own sheets in Home, Settings and Reminders (HIG: Dark Mode, "support both appearances"; Color).

**How the split works** (`HassDesign/SystemAppearance.swift`):
- The shell and the galleries keep `preferredColorScheme(.dark)` on the window, which hides the user's appearance from their own environment. `RootView` publishes the display's own interface style instead (`UIScreen`, which the override does not touch; `publishesSystemAppearance()`) as `EnvironmentValues.systemColorScheme`, and each sheet reads the display again when it is presented, so a change made while the app runs reaches the next sheet at once. The window scene's traits were observed dark while the display was light, so they are not the source.
- Journeys: one `LightAppearance<Sheet>JourneyTests` class per sheet (pixel check that the sheet is light and the page dark, then the audit with the AX5 relaunch), selected by that sheet's source files in `contracts/test-map.json`; `LightAppearanceSystemJourneyTests` covers the pinned, system and live-changing appearance and is selected by `SystemAppearance.swift`.
- Known gaps: the system navigation subtitle ("Playing") is drawn by UIKit in `secondaryLabel` and measures 3.3:1 on a light sheet, as in Apple's own sheets, so the journey audit waives it as system chrome. The vacuum map canvas keeps its dark neutral ground in a light sheet.
- Every sheet states that scheme for itself: `hassSheet()`, `HassModal`, `FilterSheet`, `OptionPickerSheet` and the inventory editor apply `followsSystemAppearance()`. A sheet that bypasses all of those stays dark, so a new sheet must use `hassSheet()`.
- Always dark by design, passed as `hassSheet(appearance: .dark)` or `preferredColorScheme(.dark)`: the Weather sheet (a condition gradient), the camera viewer (live video), Login and the Location permission sheet.
- Tokens are light and dark pairs resolved from the scheme at draw time (`Color.adaptive`), so a view needs no branch: the same `Surface.sheetCell` is white in a light sheet and `#2C2C2E` in a dark one, and on a page (always dark) it never changes. Debug builds also honour `FENTON_APPEARANCE=light|dark` at launch, so journeys can render sheets in light without changing the simulator.

| Token | Dark | Light |
|---|---|---|
| `Surface.sheetGround` | `#1C1C1E` | `#F2F2F7` |
| `Surface.sheetCell` | `#2C2C2E` | `#FFFFFF` |
| `Surface.secondaryInSheet` | `#EBEBF5` at 60% | `#3C3C43` at 76% (the system's 60% is 3.3:1 on white; this is 5:1 or better on the ground and the cell) |
| `Surface.separator` | white at 14% | `#3C3C43` at 29% |
| `Ink.action` (text and glyph tint) | `#409CFF` | `#0066CC` |
| `Ink.error`, `Ink.danger`, `Ink.warning` | `#FF6961`, `#FF6961`, `#FFB340` | darker reds and amber at 4.5:1 or better on white |
| `Ink.success` | `#30D158` | `#1E7B34` |
| `Ink.unavailable` (an unavailable device's glyph or status; never the only signal, the word travels with it) | `#8E8E93` | `#636366` (6:1 on white; system gray is 3.3:1) |
| `Ink.onSuccessFill` (glyph on a filled success disc) | `#1C1C1E` | `#FFFFFF` |
| `Ink.track(increasedContrast:)` (a control's track, the thermostat ring) | white at 43% (60% with Increase Contrast) | black at 43% (60% with Increase Contrast); 3:1 as a control boundary |

**Tiles and rows in a light sheet:**
- An off tile is a white cell with label-colour title, `secondaryInSheet` state and the family glyph. Each family has a darker light glyph (`ColorFamily.glyphLightRGB`, at least 3:1 on white and on the ground, same hue); the off glyph mixes it 72% with `#6C6C70`.
- Error faces draw `#C21717` (6:1 on white). A state wash tints the cell at 22% instead of 60% so the secondary ink holds 4.5:1.
- Lit tiles and filled family tiles are unchanged: fixed fills with fixed inks look the same in both appearances, which is also what keeps the family colour meaning.
- A caller's tint on a family-less tile is darkened until it reaches 3:1 on the ground.
- `ModuleList` and `ModuleRow` in a sheet draw their cell, hairlines, title and secondary ink from the same tokens.
- The brightness bubble stays a dark capsule with white text in both appearances, like the system volume HUD.
- Selected rooms in the vacuum sheet are the label's opposite (white with dark ink in dark, `#1C1C1E` with white ink in light), because white would vanish on a white cell.

## Colour

- **Never colour alone (owner, 2026-10-24).** Every state colour has a second channel. Greens, oranges and grays in light sheets use `Ink.success`, `Ink.warning`, `Ink.danger` and `Ink.unavailable`, never system `.green`, `.orange` or `.gray`. Media power is a filled `Ink.success` disc while on and a neutral outlined ring while off (no red and green pair). The Live Activity problem card is an octagon (stopped, "Needs help") or a triangle (carries on, "Needs attention") with the word on the problem line. Weekday chips go bold with a checkmark when selected. A performance row's bad value carries a triangle and "poor" in its spoken value. An unavailable bed side dims and says "Unavailable"; the Wake-Light tile (and room card) fills only while a wake runs (ramping, holding, snoozed), not whenever an alarm is armed. Form headers and footers on the wallpaper use `Surface.secondaryOnWallpaper` (`FormHeader(_, onWallpaper:)`). Tests: `ColourContrastTests`.
- **Labels:** white; secondary `rgba(235,235,245,.68)` on material and `.6` in sheets; separators white at 14%.
- **Tint:** system blue.
  - Text and glyph actions on dark: `#409CFF`.
  - Filled controls with white text: `#0071E3`.
  - Neither `#007AFF` nor `#0A84FF` passes contrast as small text on dark.
- **Destructive, error and overdue:** `#FF6961`. Soon or warning: `#FFB340`. Count badges: `#D93025`.
- **Colour families** (owner request, 2026-10-14): every kind of device has one colour, used for glyphs, chips and filled tiles, never for chrome.
  - Off tiles stay dark, with the glyph in the family colour mixed 72% with grey.
  - On tiles fill with the family colour (tinted glass since 2026-10-17: the fill at 78% over a dark underlay on a page, a soft top highlight, a lit hairline; see Tile finish) and white ink, with subtitles at 92% white. Every fill passes 4.5:1 with white.
  - Lights keep the warm lit tile. Power uses bright yellow with dark ink.
  - Red is never a family: alerts are a red glyph and red state on any tile.
  - **Thermostats and bed sides keep a family when off** (owner, 2026-10-15; mockup fc-families): heating and cooling fill as above. An idle or off thermostat draws the off face with the Heating glyph when its HVAC mode is `heat`, else the Cooling glyph. A bed side that is on fills whatever its level (owner, 2026-10-16: "Beds are on right now but still no colors"): Heating at or above zero, Cooling below; an off side draws the off face with that family's glyph. Bed cards read the side's level and power through `BedSideController`, never the climate entity, whose state says `heat` whatever the pod does. Never grey, except an unavailable bed side. One rule: `HassDesign/ThermostatTileFace`.

| Family | Members | Glyph on dark | On-tile fill |
|---|---|---|---|
| Lights | lights, lamps, wake lights | `#FF9630` (web chip icon) | lit tile `#FFF3DE` → `#FFE2B2` over `#EADBC4`, glyph `#D97A00`, dark ink |
| Heating | thermostats and bed sides while heating | `#FF7A2F` | `#A8440A` (dial heat `#CD5401` darkened for white text) |
| Cooling | thermostats and bed sides while cooling | `#3FC6D2` | `#1B6F78` (dial cool `#2C8E98` darkened) |
| Vents | smart vents | `#8FA8FF` | `#3B58B8` |
| Air | fans, purifiers, bath fans, air quality | `#2FD3C1` | `#006E62` (web air teal) |
| Water | humidifiers, sprinklers | `#4CC9F0` | `#076C91` |
| Occupancy | presence and motion sensors | `#5BD16A` | `#2A732E` (web presence green) |
| Doors and windows | contact sensors, garage | `#7ED787` | `#3B523E`, the web's soft green |
| Media | TVs, remotes, consoles, PCs, speakers | `#FF7AA8` | `#A03A61` (web media pink) |
| Cleaning | vacuums, dishwasher, laundry | `#C88CFA` | `#7A3FB0`; progress is a lighter band from the leading edge |
| Power | plugs, towel rack, chargers | `#FFD60A` | `#FFE45C` → `#FFD60A`, dark ink |
| Cooking | grill, oven | `#FF8A4C` | `#A8420E` |
| Chores quick links | Alex's, Sam's, Unassigned, Home Tasks, Groceries (owner, 2026-10-16: distinct colours used nowhere else) | `#8FA0FF`, `#FF8CF7`, `#FF8FBF`, `#B98CFF`, `#E0916F` | ultramarine `#0022CC`, magenta `#B410AE`, raspberry `#C2127A`, violet `#6600CC`, chestnut `#802200`; white filled glyph; each at least 0.05 OKLab from every device, security, Food and room fill |
| Food (owner, 2026-10-16: "Food Spaces / All Food should have colours like the web") | Food hub tiles, always filled: Pantry `#855A25`, Fridge and All Recipes `#196B94`, Freezer `#2F4A9E`, Spice Rack `#AA4727`, Cabinet `#6A5F55`, All Food `#4A6B4E` | each a lightened tint of its fill | the web's tile colours (`ha-sfenton-react-dash@9ac2a46:src/constants/everShelfFood.ts:13-18`, `FoodHubPage.tsx:46,60`), nudged until white ink passes 4.5:1 and no two spaces read as one (≥ 30 apart in sRGB). The Freezer indigo sits near Vents and the Spice Rack near Cooking, as the web's own colours do; they never share a page |
| Security | by mode, as on the web | white on the fill | Home `#1565C0`, Away `#C62828`, Night `#7B1FA2`, Disarmed `#2A732E`, Triggered `#D70015` |

**Status chips follow the web** (owner, 2026-10-16: climate, air quality, occupancy and contact chips brought to web parity; one rule per chip, in `StatusChipAppearance` and `HassCore/Chips`):
- Lights on: amber, orange glyph.
- Security: filled with the mode colour, white glyph.
- **Climate follows the temperature** (owner, 2026-10-16: "temperature-dependent, like the web"). The web colours every climate card with the `input_text.*_climate_color` helper Home Assistant computes, else its temperature gradient (`ha-sfenton-react-dash@9ac2a46:src/components/cards/climateColor.ts:8-15,49-59`, `ClimateCard.tsx:71`). The Home chip reads `input_text.demo_color_4`, a room chip its `input_text.<room>_climate_color`; with neither it takes the gradient at the mean of the range text (50 °F blue, 60 purple, 68 green, 74 yellow, 80 orange, 85 red, clamped). The fill is that colour scaled to 73% (and darkened further until white reads at 4.5:1, also under the top highlight); the thermometer stays the web's yellow `#FFCC00` where it keeps 3:1, else a lightened tint. No colour at all falls back to the old navy `#195482`. Beds keep the family colour.
- **Air quality follows the AQI.** Fill and glyph use `input_text.demo_color_3` (a room chip its `input_text.<room>_aqi_color`; the web teal `rgb(0, 150, 136)` while unset) through the same scale-and-lighten rule, so good air is `#006E63`, within a step of the Air family teal. The summary is the web's, `AQI <range> · PM2.5 <range>` (`AtAGlancePage.tsx:1187`); the web has no "Good" word on this chip, so there is none.
- **Occupancy:** a person glyph, outline while clear and filled while detected, with the Occupancy green fill only while detected. The web tints this chip by detection alone (`StatusRail.tsx:41-46`: green fill and `motion-sensor` when active, neutral `motion-sensor-off` when clear); it has no alarm or away tint, so neither has the native chip.
- **Contact Sensors reads the house** (owner, 2026-10-16: "need to decide all closed, open but we're home, open but we're away, open but security system is on"). The web draws this chip green when open and neutral when closed and has no house rule, so these are the planner's decisions. One rule, `ContactChipState`, shared by Home, every room rail and Security:

| State | When | Fill | Glyph | State text |
|---|---|---|---|---|
| All closed | nothing open | soft contact green `#3B523E` | door closed, `#7ED787` | "All Closed" (a single sensor: "Closed") |
| Open, home | something open, someone home, system not armed | warning amber `#8A5200` (the `#FFB340` warning, darkened for white text) | door open, `#FFC25C` | "<n> Open" |
| Open, away | something open, household effectively away, system not armed | the web's window-open coral `#B23A26` | door open, `#FFD2C8` | "<n> Open" |
| Open, armed | something open and the alarm is in any armed mode or triggered (outranks away) | triggered red `#D70015` | alert triangle, white | "<n> Open" |

  "Away" is `ClimateLogic.isEffectivelyAway` (Whole Home mode, `sensor.demo_away_1`), the app's one home/away reading. The alert triangle keeps the armed state from resting on colour alone. The web's count text ("N Open") stays; the owner's "Back Deck Open" wording was an example, and the web has no per-sensor name here.
- **Colour changes animate.** A chip's fill and glyph cross-fade when the colour changes or the chip turns on or off (a warmer house, a door opening, the alarm arming): 0.6 s ease-in-out, scoped to colour so the chip's width and glyph never slide. Reduce Motion allows the cross-fade (no movement), shortened to 0.2 s (`StatusChipStyle.colorAnimation`).

**Security Doors are tiles** (owner, 2026-10-16): the Doors section is a grid of `GlassTile`s in the Doors and windows family (front-door lock, left and right garage doors; the car lock when shown), not rows. A tile is filled while the door is open, unlocked or moving and dark while closed or locked; a jammed lock or a failed garage command draws the red error face; garage doors keep their Sending, Opening, Closing and Error states. Same grid rules as room tiles: 140 pt scaled minimum width, equal heights, one column at accessibility sizes.

People have no colour of their own. **Rooms do** (owner reversal, 2026-10-16: "room tiles don't have nice colours, and icons should be filled/white"):

**Room tiles** (the Rooms grid in Quick Links and Climate's Advanced Controls rooms; `HassDesign/RoomPalette`):
- A solid fill per room, a filled white glyph and white text, on or off, in every appearance. The palette names no room: it is sixteen fills in the document's room order, and a room takes the fill at its position in `rooms.grid.items` (`RoomNavigation.paletteIndex(forPath:)`, `RoomPalette.fill(at:)`), wrapping past sixteen.
- The web colours rooms too (`ha-sfenton-react-dash@f5a7bf9:src/constants/atAGlance.ts:324-340`, `AREA_ITEMS`, drawn as `rgb(color / 0.6)` under white text by `src/components/core/Card.module.css`). Each room keeps its web hue.
- Room colours now follow each room's position in the house document's room grid, so reordering rooms recolours the ones after it.
- The raw web values are not usable as fills. Seven of the sixteen miss 4.5:1 with white once composited (Downstairs Hallway 2.9:1, Entryway 3.3:1, Living Room 3.6:1), and Media Room is `rgb(0 0 1)`, invisible on a dark tile.
- So each room is moved to a lightness where white holds at least 4.7:1. Every fill is also at least 0.05 (OKLab) from every other room and from every colour family and security mode fill, so a room never reads as a device or an alarm state.
- Media Room (web black) takes a deep plum and Bathroom 1 (web grey) a slate; neither has a hue to keep.
- Room cards in the chip overview sheets (Lights, Climate, Occupancy, Contacts, Air Quality) are status tiles, not navigation, and keep their state faces.

| Room | Fill | Room | Fill |
|---|---|---|---|
| Living Room | `#8A6F44` | Kitchen | `#547F12` |
| Guest Room | `#0D8457` | Studio | `#901E79` |
| Gym | `#AF5F00` | Garage | `#A6222C` |
| Bedroom 1 | `#3E3EB7` | Media Room | `#453057` |
| Office | `#007E94` | Back Deck | `#195E20` |
| Hallway | `#72492D` | Downstairs Hallway | `#637145` |
| Guest Bathroom | `#407B6E` | Bathroom 1 | `#59596F` |
| Dining Room | `#975B46` | Entryway | `#7D7200` |

**Quick Links tiles** (owner, 2026-10-16: "Quick Links now have different tile sizes (prefer consistency of what we had before), and no color there as well"; `HassDesign/QuickLinkPalette`):
- Same treatment as a room: a solid fill, a filled white glyph and white text, on every link. Each link reuses the colour its own pages already use; only Rooms is new.
- The arrangement is the Rooms grid's (below), not the Row. Every tile is one size: `equalRowHeights` plus `equalHeightTiles()`, so the tallest tile (a two-line name over a two-line state, "Food & Recipes" over "42 Items • 3 Expiring Soon") sets the height of all of them, and at accessibility sizes they grow together. The cause of the unequal sizes was the Row layout (#95) in a grid without equal heights: a tile with a state line was taller than one without.

| Link | Fill | Source |
|---|---|---|
| Rooms | `#1F3A5F` deep navy | new: at least 0.06 (OKLab) from every room, family and alarm fill, because the tile stands for all of them |
| Security System | the alarm mode's fill: Home `#1565C0`, Away `#C62828`, Night `#7B1FA2`, Disarmed `#2A732E`, Triggered `#D70015`; slate `#4C6270` while arming, unknown or redacted | Security family (and the Security page and chip) |
| Food & Recipes | `#4A6B4E` | All Food |
| Vacuums | `#7A3FB0` | Cleaning |
| Media | `#A03A61` | Media |
| Custom Lights | `#7A4A00` | the Lights chip's amber (lights have no tile fill: only the warm lit tile, which would read as "on") |
| Sprinklers | `#076C91` | Water |

White passes 4.5:1 on every fill and no two links on the sheet are within 0.05 OKLab (`QuickLinkPaletteTests`). The chore lists' quick links (Chores tab) are the Chores lane's.

## Tile finish: tinted glass (owner decision, 2026-10-17)

Owner, 2026-10-16: "Ideate on a more 'frosted' tile look like we have on the web; subtle but looks less childish? Consult the design agents and HIG." Three proposals were built beside the solid finish (#105). **Owner, 2026-10-17: option A, Tinted Glass, rolled out app-wide as the default finish for every tile.** B (Frosted Module) and C (Web Port) were deleted with their tokens; this section and the #105 PR keep them for reference. `HassDesign/TileFinish` has two cases: `tintedGlass` (shipped) and `solid` (the Reduce Transparency and Increase Contrast fallback, `TileFinish.effective`). The gallery (`FENTON_GALLERY=direction-g`, Tile Finish; `-directionGOrder finish`, `-directionGFinish tintedGlass|solid`, also a "Finish" section in the gallery sheet, which follows `FENTON_APPEARANCE`) shows both on the same tiles.

**What ships.** One token set (`TileFinish.Tokens.tintedGlass(on:)`), one ground (`TintedGlassGround`), one hairline (`TintedGlassRim`), one gradient (`TintedGlassSheen`), all inside `GlassTileFace`, so every tile gets it: families, the lit tile, power, room fills, Quick Links (including the chore list links), the Food and Security tiles, selection tiles, progress bands, and `BrightnessTile`. Chosen controls that are not a `GlassTile` (the alarm mode buttons) take `.tintedGlassEdge(cornerRadius:)`.

| Token | Tinted glass |
|---|---|
| `underlay` (`#1C1C1E`, the off ground) | 0.66 |
| `fillUnderlay` (beneath a fill, page) | 0.50 |
| `fillOpacity` (white-ink fills) | 0.78 on a page, 1 in a sheet |
| `sheen` top white / bottom black | 0.14 / 0.08 (clear at 46% of the height) |
| `rim` top / bottom white | 0.32 / 0.06, 1 pt |
| radius | 22 (`Radius.tile`) |

**Faces.**
- *Off, tinted, error:* the thin module (the underlay alone) or the dense module for an error, then the sheen and the rim. The off glyph keeps 88% of its family colour (72% on solid) and is lifted toward white until it reads 3:1 on the lightest ground a glyph can sit on (`ColorFamily.offGlyphRGB(_:under:)`: the muted Food families needed it, 2.85 before). State text on a page takes `Surface.secondaryOnWallpaper` (85%).
- *On (family fill) and room, Quick Link and chore-list fills:* the fill at 78% over the underlay on a page; opaque in a sheet. `FinishColor.flatten` composites the two into one colour.
- *Lit (lights) and power:* opaque with dark ink in every place, because a translucent light fill over a dark wallpaper only gets darker. They take the sheen and the rim.
- *Progress bands* (vacuum, dishwasher): unchanged, over the glass fill.
- *Sheets:* no wallpaper to show through, so fills are opaque and keep the sheen and the rim. A white cell in a light sheet has nothing for a highlight to work on: no sheen, and the hairline is the sheet's separator colour. A room or Quick Link fill in a sheet gets only the bottom shade (no highlight): white ink on those fills is within 0.2 of 4.5:1 flat, so a highlight over the title would break it.
- *Reduce Transparency or Increase Contrast:* the solid finish (opaque fills, the module tint, no rim), checked by pixels in `TilesRound2JourneyTests`.

**Measured** (iPhone 17 Pro simulator, optimized build, `tools/ios_scrollcost.sh`; CPU instructions while scrolling, so read the ratios, not the totals):

Before (solid, main at c67a3d5) and after (tinted glass), the same optimized build recipe, one busy Mac, `--section gallery`:

| Surface | Instr. before | Instr. after | Main-thread ms before / after | p95 ms before / after | Turns over 8 ms before / after |
|---|---|---|---|---|---|
| 300-tile grid (stress) | 4729 M | 5158 M (+9%) | 1963 / 2348 | 6.01 / 5.25 | 7 / 0 |
| Chores | 1779 M | 1800 M (+1%) | 1103 / 976 | 3.65 / 3.47 | 2 / 0 |
| Food hub | 1071 M | 1011 M (-6%) | 1014 / 952 | 3.78 / 3.87 | 0 / 0 |
| Climate (Rooms tab, tiles) | 1304 M | 924 M (-29%) | 1292 / 885 | 5.19 / 2.06 | 0 / 0 |

The page rows move with whatever else the Mac was running (Climate fell 29% with no change to its layout), so read the grid as the upper bound and the pages as "no regression". A room page, Kitchen and Security fit one screen on the fixtures and have nothing to scroll. The same-build A/B on the grid (`--section finish`, `FENTON_TILE_FINISH`, `FENTON_TILE_FINISH_OMIT`) isolates the finish:

| Variant | Instructions while scrolling | Main-thread ms | p95 ms | Turns over 8 ms |
|---|---|---|---|---|
| Solid (fallback) | 4360 M | 1955 | 4.61 | 5 |
| Tinted glass | 4971 M (+14%) | 2102 (+8%) | 4.77 | 2 |
| without sheen | 4828 M (+11%) | 2163 | 5.14 | 10 |
| without rim | 4708 M (+8%) | 2151 | 5.01 | 2 |
| without sheen or rim | 4332 M (-1%) | 1975 | 4.61 | 4 |

Sheen and rim together are the whole cost (+14% instructions, +8% main-thread CPU on 300 tiles; a real page has 10 to 40, under 1% of one core). No turn passes 8 ms on any page; the 300-tile grid's worst turn (a first-layout turn) is 22 to 27 ms in every variant, solid included. Both layers stay. No finish adds a backdrop or offscreen pass; the simulator cannot show GPU cost, so run the phone A/B (`--disable`) before a Release build ships.

**Contrast** (`TileFinishTests`: rendered pixels of `TintedGlassGround` for every family fill, the 16 rooms, the Quick Link fills (Rooms, Custom Lights, Security by alarm mode and unknown), the chore and Food families, the off, lit, power and error faces, at the heights text sits, on the wallpaper's lightest region (sRGB grey 0.46, the lightest under which white text still reads 4.5:1) and darkest (`#111723`), and in a dark and a light sheet). The tests enforce 4.5:1 for titles and state text, 3:1 for glyphs and the Chores count numeral; the worst cases are:

| Place | Title | State | Error text | Off glyph |
|---|---|---|---|---|
| Page, white-ink fill | 4.90 | 4.95 | n/a | n/a |
| Page, off face | 9.75 | 7.45 | 5.14 | 3.05 or better after the lift |
| Sheet, white-ink fill (rooms flat) | 4.71 | 4.7 or better | n/a | n/a |

(The figures are the same stacks computed outside the tests, `scratchpad/lane-glass/contrast_model.py`, within a rounding of the rendered pixels. Earlier proposals' table, for reference: solid 4.71 / 4.66 / 5.12 / 3.56, A 5.09 / 5.09 / 4.67 / 3.24, B 10.31 / 6.94 / 4.80 / 4.12, C 5.91 / 5.91 / 5.41 / 3.24; the new run also covers the top of the tile, where the highlight sits.)

### The proposals that were not chosen

**What the web does** (`ha-sfenton-react-dash@f5a7bf9`): a tile is `background: var(--tile-color)` (a family colour at 0.1 to 0.6 alpha, the neutral and off tiles `rgba(255,255,255,0.1)`) over `backdrop-filter: blur(15px) saturate(1.08)`, with `box-shadow: inset 0 1px 0 rgba(255,255,255,0.22), inset 0 -1px 0 rgba(0,0,0,0.08)` and a 32 px radius (`src/components/core/GlassTile.module.css:11-15`; `src/components/core/Card.module.css:15-18`, radius 30, 28 compact). Cards add an `::after` sheen: `linear-gradient(135deg, rgba(255,255,255,0.13), transparent 44%)` plus a vertical `rgba(255,255,255,0.02)` to `rgba(0,0,0,0.12)` (`Card.module.css:53-61`), a 1 px `text-shadow` on the title (`:110`) and a white icon with a drop shadow (`:88`). The page behind is the photo at `blur(16px) saturate(1.04) brightness(.76)` (`src/components/shell/AppShell.module.css:62-65`). So the web's frost is a milky veil, a lit hairline and a diagonal sheen over a blurred photo. Colour is a tint wash, not a solid fill.

**Design-skill conclusions.**
- *apple-hig, Materials:* "Don't use Liquid Glass in the content layer. Use standard materials for content-layer elements"; tiles are content, so no `.glassEffect`. Standard materials differ by thickness: "Thicker, more opaque materials improve contrast for fine details; thinner, more translucent materials preserve context". The wallpaper is already blurred once, so a thin-material look comes from translucency over it. *Color:* "Avoid relying solely on color to differentiate objects" (a tile's state keeps its glyph fill and text) and "colors can look different behind or on translucent elements"; supply light and dark variants. *Accessibility:* Reduce Transparency and Increase Contrast must give a higher-contrast scheme: every proposal resolves to the shipped opaque finish (`TileFinish.effective`). *HomeKit:* the HIG's HomeKit page covers terms and setup, not tile styling; Apple Home's own tiles (a neutral rounded module that turns light when on) are the reference.
- *design-critique* (Von Restorff, Law of Similarity, H8 minimal design, aesthetic-usability): an "on" tile must stand out from an off one at a glance (Von Restorff), and the same state must look the same everywhere (Similarity). Decoration that adds nothing to state or hierarchy fails H8. The solid fills read as "childish" because a saturated flat rectangle has no edge light, no depth and no relation to the photo; the cure is edge and depth, not less colour. A finish that dims "on" into the off ground (B) trades the glance for polish; one that copies the web's tint strength (C) pays contrast for little change.
- *design-systems:* the finish is a **perceptual pattern** of one functional pattern (the tile), so it is a variant token set, not a fourth tile. Three tiers: reference values (`#1C1C1E`, family fills, `#FFFFFF`), semantic (`underlay`, `fillUnderlay`, `offVeil`, `fillOpacity`, `sheen`, `rim`, `edgeGlow`) and component (`GlassTileFace`). At most five variants per pattern, named by what they do, not how they look.

**Rules shared by the three** (and the reasons the numbers are what they are):
- No live blur or material per tile; translucency over the cached wallpaper, one sheen gradient layer, one hairline stroke, one flattened ground colour (`FinishColor.flatten` composites the underlay, veil and fill into one `Color`).
- Dark-ink faces (the lit tile, Power) stay opaque: a translucent light fill over a dark wallpaper only gets darker.
- On a page the state text uses `Surface.secondaryOnWallpaper` (85%) instead of the module's 68%, because a frosted ground is a little lighter.
- A sheet has no wallpaper to show through, so every finish is opaque there (fill 100%, no veil), keeping the sheen and rim; on a white cell the sheen is dropped and the hairline is the sheet's separator colour.
- The off glyph keeps 88% of its family colour on a frosted ground (72% on solid), so it holds 3:1 where the ground is lighter.

| Token | Solid (shipped) | A Tinted Glass | B Frosted Module | C Web Port |
|---|---|---|---|---|
| `underlay` (`#1C1C1E`, off ground) | 0.66 | 0.66 | 0.66 | 0.62 |
| `fillUnderlay` (beneath a fill) | 0.66 | 0.50 | n/a | 0.42 |
| `offVeil` (white over off, page) | 0 | 0 | 0 | 0.05 |
| `fillOpacity` (white-ink fills, page) | 1 | 0.78 | n/a, neutral module | 0.84 |
| `sheen` top white / bottom black | 0.10 / 0 | 0.14 / 0.08 | 0.10 / 0.06 | 0.15 / 0.12, diagonal |
| `rim` top / bottom white | none | 0.32 / 0.06 | 0.22 / 0.06 | 0.24 / 0 |
| `edgeGlow` / `edgeWash` | none | none | 0.62 / 0.26 | none |
| glyph | bare | bare | on a 34 pt disc: family fill when on, a dark well when off | bare |
| radius | 22 | 22 | 22 | 28 (the web's) |
| title shadow | none | none | none | 0 1 1 black 0.30, on a page |

- **A Tinted Glass.** The family fill at 78% over a dark underlay, so the photo tints it a little; a lit hairline and a soft top highlight with a faint bottom shade. Every state keeps the solid finish's meaning; the difference is edge and depth. The subtlest of the three.
- **B Frosted Module.** One neutral frosted module for every state. The family colour moves to a glyph disc (filled when on, a shallow well when off) and a coloured hairline and corner wash when on; text is the off face's white. Closest to Apple Home, and the calmest page, but "on" no longer fills the tile, which departs from the owner's coloured, filled tiles (2026-10-14 families; 2026-10-16 "icons should be filled/white").
- **C Web Port.** The web's structure at the strength contrast allows: milky veil on off, the tint at 84% rather than 60%, a diagonal sheen, 28 pt radius, the title shadow. Reads as A with rounder corners and a stronger sheen; the closest to the web.

The #105 measurements of the three proposals (300-tile grid, instructions while scrolling): solid 4.73 G, A 5.60 G (+18%), B 5.82 G (+23%), C 5.95 G (+26%); taking the sheen off A saved about 8%, the rim about 10%. A was chosen for subtlety (edge and depth, the glanceable family fill kept), B would have moved the colour to a glyph disc (calmer, Apple-Home-like, but "on" no longer fills the tile) and C added a stronger sheen and 28 pt corners for the highest cost and little visual distance from A.

## Type

SF Pro only.
- **Large titles:** 34 Bold.
- **Section headers:** 20 Bold on pages and over tile grids in sheets. Over inset lists in sheets, 15 Semibold secondary.
- **Rows:** 17 Regular. Subtitles 15, footers 13, tab labels 10.
- **Display numerals:** one per screen, Light or Thin weight, with monospaced digits. Examples: the thermostat (71 °F), weather (54°), a light's brightness, the humidifier mist level, the bed level.
- **Copy:** Title Case labels, states said as facts ("Back Deck Open", "Heating to 68°", "3 of 12 on"), dates as "Oct 16, 2026". No exclamation marks, no "currently", and no Home Assistant jargon.

## Navigation

- **Owner decisions, 2026-10-16 (reversing the Phase 2 rules of 2026-10-14):** Settings is its own tab, like the web's; Quick Links is a header button beside Profile on every page; the Profile sheet is the web's profile modal; and on iPhone the page title sits in the header row. The four bullets below state the result.
- **iPhone and Duo folded:** a floating glass tab bar with Home, Security, Climate, Chores and Settings (five tabs, Settings last). Chores carries the overdue badge. The header row of every page, tab root or pushed, carries two trailing buttons: Quick Links (opens the Quick Links sheet) and Profile (opens the Account sheet). Quick Links is no longer a trailing tab or a floating circle.
  - **Header buttons (owner 2026-10-18, option A, FestivalNativeApps parity, HIG Toolbars "Item groupings"; supersedes the 2026-10-16 "each circle draws its own glass" rule).** Profile with a known name is a **44 pt monogram disc that is the whole button**: `ProfileButton.fill` (5.6:1 under white), initials in `.callout` semibold (16 pt, capped at xLarge), no glass ring. On iOS 26 its toolbar item hides the bar's shared glass (`sharedBackgroundVisibility(.hidden)`) and the disc overhangs the 10 pt hidden-glass padding (`.padding(.horizontal, -10)`), so it fills exactly where the glass circle would be (FestivalNativeApps issue #311, `RootProfileButton.MonogramMetrics`). Profile with no name yet is the person symbol on the bar's standard 44 pt glass circle, like any bar glyph. The attention badge sits on the disc's top-trailing edge ("9+" past nine) and is hidden from VoiceOver. **Badge rule (Designer, 2026-11-04, T-profile-badge-size, [decision](profile-badge.md)):** on every bar the capsule is caption1 bold, 18 pt tall at the default text size (24 x 18 for "9+", 18 x 18 for one digit), its trailing edge 4 pt past the disc and its top 2 pt above it, which puts its centre on the disc's 45 degree point; the system badge of a standard item (the Duo rail) may sit up to 6 pt from that point, the header disc may not move it inside the photo. Its text grows with Dynamic Type only to xLarge, the same cap as the initials (`ProfileButton.badgeTypeRange`), because a bar badge marks the button and the count is spoken in its value and shown by the Large Content Viewer: at the accessibility steps it hid the 30 pt rail disc. Then: the spoken value ("Alex Morgan, 3 items need attention"), the label, the hint, the Large Content Viewer and the identifiers `nav.profile` and `quickLinks.open` are unchanged.
  - **Quick Links stays a separate circle**: a plain symbol item on the bar's own glass (44 pt), then `ToolbarSpacer(.fixed)`, then Profile. The spacer is what keeps the bar from merging the two into one capsule and gives the 12 pt group gap. Measured on the iPhone 17 Pro simulator (iOS 27.0), pixels at 3x divided by 3: Quick Links glass 44 pt, disc 44 pt, gap 12 pt; the tests assert 12 ± 1.5 and never over 14. Rejected: Quick Links drawing its own glass with its shared background hidden (gap 18 pt: its 6 pt padding plus Profile's), a UIImage monogram with alignment insets (breaks the badge: an overlay stops the button receiving taps and baking the badge into the image shrinks the disc to 36.7 pt) and the system `.badge` (covers the initials).
  - **iOS 26.5 differs (measured on the iPhone 17 Pro iOS 26.5 simulator, 2026-10-18).** The disc is still 44 pt, but the bar gives a hidden-glass custom view a cell 8 pt wider than on iOS 27 (about a 32 pt layout width instead of 24), so the gap to Quick Links is 16 pt and the disc ends 20 pt from the screen edge (16 on iOS 27). Quick Links' system item also answered taps only nearer its centre there (a tap 19 pt from the centre missed; it hits on iOS 27). The 12 pt gap and 44 pt hit area are asserted on iOS 27.x; 26.5 is a known, smaller departure (owner's devices run iOS 27). FestivalNativeApps avoids the wider cell with an image-backed bar button; here that broke the badge (below).
  - **Before iOS 26** the bar draws no glass, so no spacer is added and each button draws its own 44 pt material circle (`headerCircle()`); Profile keeps today's 32 pt disc inside its circle instead of FestivalNativeApps' 30 pt outlined disc, so both circles stay one size.
  - **Why the old rule went:** left alone, iOS 26 grouped the two into one capsule and lightened the disc until its white initials measured 2.7:1. Hiding the shared glass on Profile only, and separating the groups with the fixed spacer, avoids both.
  - On the folded Duo the system moves bar items into its trailing vertical rail ([duo](apple/duo.md)).
- **Title in the header (iPhone and Duo folded, where there is no hamburger):** the page title is the large title and shares the header row with the two circles, leading. It collapses to a centred inline title as the page scrolls and grows back at the top. It is the system's own behaviour, `toolbarTitleDisplayMode(.inlineLarge)` (iOS 17 and later, `UINavigationItem.LargeTitleDisplayMode.inline`), applied once by `pageChrome()`; no page sets it. HIG Toolbars (iOS): "Use a large title to help people stay oriented; by default it becomes standard while scrolling and returns to large at the top", and the toolbar's leading location holds the back control "then the view title". A pushed page has a Back button, and the system then keeps the standard large title below the bar, so it never competes with the circles for width. Regular width (iPad; the unfolded Duo when it is not in the vertical bar) has the hamburger leading, so there the title stays below the bar as before.
  - **Superseded on iPhone, 2026-10-20 (owner):** Owner, 2026-10-20 (supersedes the 2026-10-16 inlineLarge rule on iPhone): the hamburger (`nav.open`, `.topBarLeading`) is the leading-most bar item; Quick Links and Profile stay trailing; the title is the standard large title below the bar (`.automatic` from `pageChrome()`) and collapses to a centred inline title on scroll. `.inlineLarge` would take the leading slot and push the hamburger right, so it is kept only where there is no hamburger (Duo rail, compact iPad). **Superseded 2026-10-28 (owner: "Bring back the title collapse as well", then "left align the title again"):** the large title returns and collapses into the system's leading-aligned inline title right of the hamburger (`.toolbarRole(.browser)`); a brief "no large title" rule of the same day was reversed ([header-edge-fade R7](patterns/header-edge-fade.md) (3) to (5)).
- **Your Summary (the Profile button; owner, 2026-10-17):** the web's profile modal (`ha-sfenton-react-dash@f5a7bf9:src/components/hass/DailyReportModal.tsx`, "Your Summary") as a full-height sheet with four bottom tabs on the shared modal tab bar: **Profile** (who is signed in, People at Home with a monogram in each resident's colour, Location on phones, Sign Out), **Overdue Chores**, **Upcoming Chores** and **Expired Food**, the last three carrying the Chores page's and the Food page's own rows (edit button and swipe actions included). It opens on Overdue Chores. Overdue and Expired Food badge their counts (Expired Food is 0 in Vacation Mode); icons on compact width, an icon over its title on regular width, a menu at accessibility sizes. A resident sees all four; anyone else Profile and Expired Food. Vacation Mode shows "Enjoy vacation!" for empty chore tabs and hides the food list, as on the web. Spec: [pages/settings/profile.md](../pages/settings/profile.md).
- **Pushed pages** (Food, Media, Sprinklers, Custom Lights, room pages, chore lists): a glass Back circle with its top edge at y=54, left 16, and the large title with padding-top 104. The tab bar stays unless the page has its own bottom toolbar (Recipes and inventory use search, sort and filter).
- **iPad:** an overlay glass flyout (Open Navigation button top-leading) that lists the same five as the tab bar, Settings last. Quick Links and Profile are the same header circles as on iPhone. Grids reach at least 4 columns in portrait and keep growing (4 is a floor, not a cap), and the chip rail is one row that scrolls sideways (owner, 2026-10-26; it wraps only at accessibility text sizes).
- **Duo unfolded:** each half is its own column and nothing straddles the hinge. Column counts are even. The tab bar stays (owner, 2026-10-26: "Unfolded Duo should still have the navbar visible"), and a horizontal rail of scrollable status chips runs across the whole page, hinge included, even when a split page is open under it. Only an accessibility-size wrapped rail stops 24pt short of the hinge.
- **macOS:** a sidebar with the five tabs, Quick Links in the toolbar, and a Settings window (⌘,). Every toolbar item is also a menu command. Sheets get a Close button in the content area, and the thermostat and remote open as panels.

## Sheets

- **Height (owner, 2026-10-16, replacing 2026-10-13's "all modals full height on iPhone").** A sheet opens only as tall as its content needs: `hassSheet()` measures the page's scroll content and sets a custom `.height` detent, capped at large (longer content scrolls), recomputed when the content or Dynamic Type changes. The exceptions open at large: **remotes** (the media remote), **any modal with a section tab bar** (thermostat, vacuum, humidifier, bed, wake light), **recipe detail** (full screen), sheets that **navigate** between pages (Account, Quick Links, room card, room overview, Sprinklers) and sheets over **live video or a condition gradient** (camera, Weather). They say `hassSheet(height: .full)`. iPad keeps its form or page size, with the height fitted to the content in the fitted case (iOS 18 and later).
- **Section tab bar on iPhone (owner, 2026-10-16):** icons, the web's (`ModalIconTabNav`), on Liquid Glass; text titles on iPad and the unfolded Duo; a menu at accessibility sizes. Titles stay the segments' VoiceOver names.
- **Edit sheets (owner, 2026-10-16):** the filled check is always visible and is **disabled until there is a change** (Calendar and Reminders; HIG Toolbars: keep controls in a stable place, disable rather than hide). **Reset** is a list row in the tint (blue), never red: resetting filters is not destructive (HIG Buttons: red for destructive actions only). Sheet headers have no material band (`modalChrome()`); the Filter sheet used to lack it.
- **Viewing and control sheets:** circle x Close trailing. Leading is empty at the root, or a glass Back circle on pushed levels (Lights → Kitchen Lights → Table Light). Centred title plus a one-line subtitle. Never "Done".
- **Create and edit sheets:** circle x Cancel leading and a filled `#0071E3` checkmark trailing, as in Calendar and Reminders. Reset is a list row. Multi-step flows put Back leading on later steps.
- **Sections:** a bottom glass segmented control, never a top one. Use symbols and labels, or symbols only at five segments (the vacuum). The control only shows sections that have content (the remote has 2 to 4). Content cross-fades with no layout jump.
- **Alerts:** iOS 26 style for destructive or hard-to-undo actions: Disarm, Turn Off Vacation Mode, Sign Out. The destructive button is red.

## Controls

| Control | Rule |
|---|---|
| Status chips (Home, room pages, Security) | Capsules with glyph, title and one-line state, coloured as on the web (see Colour families, "Status chips follow the web"); Contact Sensors also read the house. Neutral when nothing is active. Colour changes cross-fade. They scroll horizontally in one row on every width and wrap only at accessibility text sizes (`ChipRail`). |
| Tiles | 2 columns on iPhone, 22pt radius, equal heights within a grid (the tallest name, such as "Bedroom 1 Closet" on two lines, sets the row). Off is dark with the glyph in its family colour. On fills with the family colour and white ink; lights use the warm lit tile. Errors use a red glyph and red state text. A chevron appears only when the tile opens something, vertically centred on the tile (owner, 2026-10-16). The glyph, title and state follow the tile layout below. Filled tiles (on) draw the fill glyph in white; off tiles keep the family glyph. |
| Tile layout (owner, 2026-10-16: "it feels too high up / lots of dead space, but I like the tiles themselves") | Four arrangements were drawn and measured (`HassDesign/TileLayout`, gallery `FENTON_GALLERY=direction-g`, Tile Layouts). Shipped: **Row**, Apple Home's tile: glyph leading and title with state beside it, the pair centred vertically, 72 pt minimum height. Accessibility text sizes anchor the text to the bottom of a stacked tile instead (a row has no width left for text at AX5). Alternatives kept in the code for the owner to override: Anchored Bottom (glyph top-leading, text bottom-leading), Centred Stack, and the old Stacked Top. |
| Navigation tiles: Rooms, Quick Links, Climate's Rooms tab (owner, 2026-10-16: "Rooms should have taller tiles with room for two lines of text; multi-line text can still appear under the icon (as it did before), single-line takes the 'bottom' line") | **Anchored Bottom with a two-line reserve** (`.tileLayout(.anchoredBottom).tileTitleLines(2)`, `TileMetrics`): the glyph top-leading, the name anchored to the bottom, so a one-line name sits on the bottom line and a two-line name fills both. The tile is as tall as glyph + 8 pt + two title lines + padding at the current Dynamic Type size (96 pt at the default size, measured from `ScaledMetric`s of the title3 glyph and subheadline lines), equal across the grid, and growing with the text at AX sizes. **Device tiles on room pages keep the Row**: they carry a state line the glance should read first, and the Row is Apple Home's accessory tile; a navigation tile has only a name, so the reserve costs nothing and a short name still has a bottom line to sit on. A tile whose state is two lines (Climate's rooms) is taller than the reserve and sets the grid's height. |
| **Light dragger** (signature) | Tap a light tile to toggle it. Press and drag sideways to set brightness: the bright band follows the finger, a "30%" bubble floats beside it, there is a haptic tick every 10%, and the tile lifts while dragging. A room's lights stack as full-width slabs that work the same way. The light detail adds a 168pt brightness slab, White and Color modes, a colour-temperature track with presets, and a colour wheel. |
| **Thermostat dial** (signature) | main's `ThermostatDial` exactly: a 22pt round-capped 270° track, heat arc orange to the heat setpoint, cool arc teal from the cool setpoint, white knobs, a dark dot for the current temperature, "Heating", a Thin numeral with a raised °F, and the range line. The bed and humidifier dials reuse its geometry. |
| **Remote** (signature) | A 3×3 grid of 72pt grey circles: Back, Up, Power (red glyph, top-trailing), Left, OK, Right, Home, Down, Menu. Volume is a slider with speaker − and +. Transport keys sit below. |
| Choosing one option | Alarm modes are mode tiles. 2–4 short options use the system segmented control. Options with descriptions use a checkmark list. Longer short lists use a pop-up menu (`Picker(.menu)`) that stays anchored over the control, for example repeat. The vacuum's Cleaning Settings are the exception (owner, 2026-10-28, [vacuum-sheet-redesign](vacuum-sheet-redesign.md)): Mode, Fan, Water and Passes are all pop-up rows whatever their option count, so the list has one grammar and no segmented control. Thermostat Hub mode and Fan are pop-up menus too, because Alex asked for a native dropdown there. |
| Switches | Only in list rows. |
| Primary buttons | At most one per screen: a 50pt capsule filled `#0071E3` with a white label. A sheet about one owner's thing may use that owner's hue with dark text (Sprinklers cyan). There are no white or grey primary buttons. |
| Lists | Inset grouped, 26pt radius on pages, 52/60pt rows, hairlines inset to the text. Footers carry the web's explanations; on the wallpaper, explanations go inside the card. |
| Cameras | 2×2 on Home and Security, cards 1 : 0.78 like the web's tile (fill-cropped, centred), nothing over the image except a small name label with a red live dot while the stream shows frames (HIG HomeKit must). The viewer is a content-fitted dark sheet (video, then Snapshot / Audio / Record circles; owner 2026-10-23) with a live dot and glass Snapshot / Audio / Record. While connecting, or after a live stream stalls, the last snapshot stays fully visible with a pill: "Last live 6:51 PM" once the stream has been live (the snapshot's own time is not known), else "Connecting". |
| Vacuum map | Flat neutral room shapes with **no room names** (owner, 2026-10-28). Selected rooms are white with black numbered order badges, and skipped rooms are hatched. Locate is the floating glass circle on the map. While cleaning, the map grows and the controls collapse to Pause and Stop action tiles. |

## App icon

Owner decision, 2026-10-17, from the "Paired tile and house colours" mockups (`Pairs.dc.html`): all eight tinted-glass icons ship. **Navy + Sky is the app's icon** (`AppIcon`); the other seven are alternate icons chosen in Settings → App Icon.

- **The design (owner correction, 2026-10-17: full-bleed glass, no frame).** The dusk-glow frame and inset tile in `Pairs.dc.html` were mockup presentation only, so the icon is **full-bleed tinted glass**, "B · Full-Bleed" in each pair's colours: the whole 1024 square is the pair's tint at 86% over the dusk glow (`linear-gradient(165deg, #23324D, #4B4A52 48%, #7A5E3A)` with an amber glow low right and a paler one low left, so a faint warmth shows through), a top light `linear-gradient(180deg, rgba(255,255,255,.18), 0 at 46%)` across the full square, and **no inset tile, no outer frame and no edge hairline**: iOS masks the corners and Liquid Glass adds its own edge (HIG App icons: provide unmasked layers). On it, a house with a four-pane window cut out and a heart at its lower right, both in the pair's glyph colour, **80% of the icon's width** (owner, 2026-10-17; 100-unit glyph box centred, extents about x 16-86% and y 20-88%, checked against the squircle mask by a test). The heart's ring is the glass itself: the house is drawn with the ring's outline cut out, so the ring is whatever colour the glass has there and nothing stacks.
- **The eight pairs** (tint, glyph): Navy + Sky (default) `#0E1E46` `#7CC4FF`; Teal + Mint `#063A3E` `#6EE7C8`; Plum + Lilac `#3A1648` `#D3A8FF`; Forest + Green `#10301E` `#9BE29B`; Burgundy + Rose `#48101E` `#FF9EB0`; Indigo + Periwinkle `#221C5A` `#A8B4FF`; Espresso + Amber `#342014` `#FFB35C`; Midnight + Gold `#101630` `#FFD36B`.
- **One source of truth.** `AppIconChoice` (HassCore) holds the names, asset names and colours; `AppIconArtwork` (HassDesign) draws the art from them. `tools/render_app_icons.sh` compiles both with `apple/Design/AppIcon/AppIconRenderer.swift` and renders every PNG into `apple/Apps/iOS/Assets.xcassets` (deterministic, 1024 px, opaque sRGB with no alpha channel, then recompressed losslessly with Xcode's `pngcrush -rem allb -reduce`); the Settings row and sheet draw the same `AppIconArtwork` as their previews, so a preview cannot differ from its icon. A hosted test fails when a committed PNG differs from what the art renders.
- **Appearances (HIG App icons, Appearances).** Every set carries Any, Dark and Tinted. *Dark* is the same art with a deeper tint (92%) over a darker dusk with quieter glows ("base dark on light ... no excessive brightness"), the glyph unchanged ("don't swap elements between variants"). *Tinted* is an opaque greyscale of the same elements, with the glyph the brightest thing, for the system's tint; it is identical for all eight, since tinted mode is monochrome. Clear is left to the system.
- **PNG sets, not Icon Composer.** The owner approved the baked glass look, and HIG asks for layers so the system can add its own highlights, which would stack on the drawn ones. Flattened images are allowed ("You can supply a flattened image"), so the sets are PNGs; Icon Composer `.icon` layers are the route if the owner later wants the system's Liquid Glass instead. This departs from the HIG's layered preference.
- **Wiring.** `apple/project.yml` sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` and lists the seven alternates in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (`AppIcon-TealMint`, `-PlumLilac`, `-ForestGreen`, `-BurgundyRose`, `-IndigoPeriwinkle`, `-EspressoAmber`, `-MidnightGold`); the built Info.plist lists them under `CFBundleIcons` / `CFBundleAlternateIcons`. The names are stable: an installed build remembers the one chosen.
- **Settings → App Icon.** A row in its own Appearance section of the Settings list, after Vacation and To-Do and above the household topics (`AppIconSettingsRow`, a `SettingsLinkRow` whose leading icon is a 30 pt preview of the installed icon; subtitle is its name), opening a content-fitted form sheet (`AppIconPickerSheet`, `hassSheet(.form)`): a grid of the eight with their names, Navy + Sky marked "Default", the installed one checked (ring and check, never colour alone). Two columns on iPhone, three on an iPad form sheet, one at accessibility sizes where the icon grows with the text. Choosing calls `UIApplication.setAlternateIconName(_:)` (nil for the default); iOS shows its own notice, and a refusal shows an alert and keeps the selection. Each choice is a button "Navy and Sky, default" with the value Selected or Not selected, at least 44 pt. The row hides where the system cannot switch icons.

## Loading and feedback

- With a saved snapshot, Home shows it at once, with no spinner and no pill (owner, 2026-10-17); the reconnecting arc appears in the header only after the connection has been down 2 s ([launch and sign-in motion](#launch-and-sign-in-motion)).
- With nothing saved, show one centred arc spinner on the wallpaper, with no empty cards, and then everything fades in together. Images are shown from the on-disk cache first.
- **Spinners are the web's arc** (`DashboardPageLoading`), not the system petal indicator. The arc is a ring at 22% opacity with the top quarter at 96% and the right quarter at 72%. It turns once every 820 ms, linear, and takes the colour of the text around it. Sizes: 44pt with a 3pt ring for pages, 20pt for pills and rows, 16pt inline in buttons and subtitles. It is spoken as "Loading", or as the action it stands for, such as "Sending Open". With Reduce Motion on, it keeps turning at half speed, because a still arc reads as frozen. (Owner request, 2026-10-14.)
- Optimistic taps change the tile at once. If Home Assistant doesn't confirm, the tile reverts and shows "Didn't respond" in red. Garage doors show Sending, Opening, Closing and Error states on their buttons.

## Launch and sign-in motion

Owner design, 2026-10-17 (canvas **S+H Launch and sign-in motion**; the app-wide rules are in [motion.md](motion.md)). Timings live in `MotionTokens` (HassDesign); everything respects Reduce Motion (cross-fades of about 0.35 s only; the spinner still turns). The sign-in screen itself: [auth](../platforms/apple/auth.md).

| Moment | What happens |
|---|---|
| Launch, signed out (intro, ≈1.2 s, once per session) | The launch screen is the plain ground `#121722` (`LaunchBackground`). The glow fades up (0.5 s); the mark springs in (0.86 to 1.03 to 1, `emphasized`); the title and subtitle fade up 10 pt; the form rises 28 pt. No keyboard comes up |
| Launch, signed in | No intro, no spinner: the launch ground cross-fades (0.2 s) onto the disk snapshot; live values update in place |
| Sign In pressed | The capsule scales to 0.96; "Signing In…" with a white arc inside it; the fields dim to 50% |
| Sign-in succeeds (arrival, ≈0.9 s, once per session) | The sign-in layer lifts 18 pt, fades and scales to 0.97; the house backdrop fades in from 1.06 to 1; the header fades up, the status chips slide in 30 pt from the right, the cards rise 16 pt with a 60 ms stagger (the first screenful), the tab bar rises from the bottom |
| First sign-in, no snapshot | Tiles show their names and a soft pulsing bar where the value goes (`PendingValueBar`, opacity 0.35 to 1 over 1.4 s) until live data lands |
| Connection lost | White arc left of Quick Links after 2 s down, fading in and out (`ReconnectingArc`); offline keeps its chip (`OfflineChip`) |

Built from `RootView` (the launch ground, the sign-in layer's lift, `HomeArrival`), `LoginView` (the intro), `ArrivalMotion` (`.arrivalMotion(_:kind:index:)`, driven by `HomeArrival`, held back only while the moment plays), `ArrivalChromeProbe` (UIKit's navigation bar and tab bar, which SwiftUI cannot animate) and `MotionPolicy` (which moments have played this session; reset at sign-out). **Tile tap outline:** the brief asked for a faint outline on a tile until Home Assistant confirms its optimistic change. [Optimistic actions](../patterns/optimistic-actions.md) shows no state between the optimistic value and the live one and gives a control `isPending` for its own dimming; a pending outline would be a new `GlassTile` input every controller passes, so it is not added here (see that record).

## Open questions waiting on Alex (defaults shown in the mockups)

- **Occupancy:** a "Who's Home" list is added.
- **Doors chip:** it names a real sensor.
- **Chore lists:** decided 2026-10-16 (owner): filled tiles in five colours used nowhere else, with white filled glyphs (see Colour families). The web colours collide with device families, so they are not used.
- **Choreapp labels:** not on the task form.
- **Settings:** its own tab (owner, 2026-10-16). Vacation and To-Do appear in both Quick Links and Settings.
- **Duo:** four chips show beside the hinge.
- **Advanced Controls root:** has no Back button.
- **Garage:** opens on tap, with no confirmation.
- **Car:** its Doors tile is shown on Security.
- **Room pages:** keep the Lights chip; the alternative is a tile per light.
- **Remote apps:** placeholder icons, not real app icons.
- **Library:** kept as a storage choice.
- **Swipe actions:** used for row Edit and Delete.
- **Tile finish:** decided 2026-10-17: Tinted Glass (option A) ships for every tile; solid is the Reduce Transparency fallback (Tile finish).

### Owner decision, 2026-10-20: iPhone hamburger back, Duo rail one glass group

- **Hamburger on iPhone.** The leading Open Navigation button (`nav.open`, `line.3.horizontal`, 44 pt, label "Open Navigation", opens `NavigationFlyout`) returns on the iPhone tab-bar layout, because tab-bar accessories may be added later. It was dropped in #103 (2026-10-16) when Settings became a fifth tab. iPhone only: not on the iPhone Duo's vertical rail, not on a compact iPad window; iPad regular width keeps it as before. The flyout edge swipe stays off on iPhone (the edge is the system Back swipe). `ShellChrome.resolve(style:isPhone:inVerticalBar:)`.
- **Duo rail: one blob.** Quick Links and Profile share a single grouped glass shape in the vertical rail (`ToolbarItemGroup`, person symbol for Profile (owner, 2026-10-20; the monogram stays in the horizontal bar), no spacer; `ShellHeaderGrouping.oneGroup`). iPhone's top bar keeps two separate circles 12 pt apart.
