# Home

> **What:** platform-neutral spec for the Home (At a Glance overview) page. **Read when:** changing Home on any platform.

Source: `ha-sfenton-react-dash@9ac2a46:src/pages/AtAGlancePage.tsx` (render at lines 1244–1280), entity config in `src/constants/atAGlance.ts`.

## Layout, top to bottom

1. Title "Home".
2. Status rail (`OVERVIEW_STATUS_CHIPS`, atAGlance.ts:128):

| Chip | Entity | Summary | Opens |
|---|---|---|---|
| Lights | `light.demo_light_1` | "All Off" / "N On" across every room light | Lights overview: Lights On / Lights Off rooms → room lights |
| Security | `alarm_control_panel.demo_alarm_control_panel_1` | alarm state | Security system sheet |
| Climate | `input_text.demo_input_text_1` | the text value (temperature range) | Climate overview: rooms → temperature sensors and vents |
| Occupancy | `binary_sensor.demo_binary_sensor_5` | Detected / Clear | Occupancy overview: Occupied / Clear rooms → presence sensors |
| Contact Sensors | `binary_sensor.demo_contact_2` | "All Closed" / "N Open" across every contact sensor | Contact overview: rooms → doors and windows |
| Air Quality | `input_text.demo_input_text_2` (+ `input_text.demo_ext_6`, icon color `input_text.demo_color_2`) | "AQI x · PM2.5 y" | Air Quality overview: rooms (read-only) |

Sheets: [room-overview-sheet](../../patterns/room-overview-sheet.md) (source `ha-sfenton-react-dash@f5a7bf9:src/pages/AtAGlancePage.tsx`).

3. Weather summary (`weather.demo_weather_1`): condition, temperature, today's high/low.
4. Guest presence and security section, shown only when a guest toggle is on (`input_boolean.demo_guest_room_1`, `…_studio`, `…_media_room`).
5. Cameras (`CAMERA_ITEMS`, atAGlance.ts:281): Front Door (4:3), Driveway (10:3), Upper Deck (16:9), Lower Deck (16:9). Tap opens the camera viewer.

## States

| State | Behavior |
|---|---|
| Snapshot only (cold launch, offline) | Render saved values at once, no spinner; the reconnecting arc in the header only after 2 s without a connection |
| First sign-in (no snapshot yet), house layout saved or arrived | Tiles show names and a soft pulsing bar for the value until live data lands |
| First sign-in, no house layout yet (server or cache) | The Home skeleton: four chip capsules, the weather module, a section bar and four camera-shaped tiles, pulsing like the value bars; never a spinner in the page ([house-config-states](../../design/house-config-states.md) rule 11) |
| No house layout and the server answered with a problem (integration missing or too old, not set up, invalid with a Repair, newer than the build, no answer in 10 s) | A state message in place of the page's content, with an action to the right Home Assistant page for administrators (rule 12) |
| A saved house layout, whatever the server says now | Drawn as usual; only the Home Assistant modal's House Layout row says it is a saved copy (rule 10) |
| Live | Values update in place |
| Entity missing (named by the layout, absent from Home Assistant) or `unavailable` | Chip shows "Unavailable", dimmed, still opens its sheet; never hidden or moved (rule 15) |

## Services

| Event | Service |
|---|---|
| Turn a room's light or group on/off or set brightness (room detail) | `light.turn_on` / `light.turn_off` (`brightness_pct`); switches `switch.turn_on` / `turn_off`. Never `toggle` (departure: the web sends `homeassistant.toggle`, which Presence Based Lighting reverts) |
| Toggle a guest room | `input_boolean.toggle` |
