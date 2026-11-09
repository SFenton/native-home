# Custom Lights (iPhone and iPad)

> **What:** how the native Custom Lights page is built. **Read when:** changing `HassUI/Features/CustomLights`.

- Entities, swatches and service calls: `CustomLightsConfig` (`HassCore/Config/CustomLightsConfig.swift`), unit-tested.
- Manual control sends explicit `input_boolean.turn_on` / `turn_off` from the shown state instead of the web's `homeassistant.toggle` (same result; the app never toggles from a possibly stale state). Light power and brightness go through `LightControl` (never `toggle`; see [entity-tile](../../patterns/entity-tile.md)).
- Light tiles are `BrightnessTile(onOpen:)`: tap opens the sheet (chevron shown), drag sets brightness, VoiceOver activates to open and offers a "Turn On/Off" action.
- Lighting Mode is a pop-up `Menu` (inline `Picker`) of the modes showing the current one with the up-down chevron; no sheet (owner, 2026-10-25, revising `proposals/control-conventions` option A). The menu items are text only; the swatch shows in the row.
- The light sheet uses the system `ColorPicker` instead of the web's hue wheel and RGB fields (HIG: Color wells: the system picker has a wheel, sliders, hex entry and eyedropper, and VoiceOver support). Picks are sent 250 ms after the picker settles so a drag does not flood the light. Departure from web parity, recorded here.
- Direction G (mockup n4): the page sits on the wallpaper; Manual Control (a switch) and Lighting Mode (swatch, mode, up-down chevron in `Ink.action`) share one `ModuleList` ([module-list](../../patterns/module-list.md)), Reset All Lights is its own card. The light sheet's subtitle reads "On · 80%" (`.sheetSubtitle`); Color, Reset to Warm White and Apply to All Lights share one cell group; Copy Color From is a grid of colour circles with the light's name under each ("Off" for an off light).
- Layout: content up to 960 pt wide; tiles in a `DynamicGridLayout` (min 150 pt, up to 4). Full-width push page in every pose; sheets everywhere.
- Tests: `CustomLightsConfigTests`, `HomePagesViewTests` (renders, color conversion, gallery recorder echoes), `HomePagesJourneyTests` (gallery `FENTON_GALLERY=custom-lights`, `FENTON_GALLERY_LIGHT=<entity>`).
