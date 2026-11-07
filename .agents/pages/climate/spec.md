# Climate

> **What:** platform-neutral spec for the Climate (thermostat) page and its advanced-controls sheet. **Read when:** changing Climate on any platform.

Source: `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx` `ThermostatPage` (7397) and the modal components above it (6295–7395); rooms in `src/constants/portedDashboard.ts:671` (`THERMOSTAT_ROOMS`), tabs in `src/constants/surfaceSemantics.ts:174` (`THERMOSTAT_MODAL_TABS`), contact sensors in `src/constants/atAGlance.ts:707` (`CONTACT_GROUPS`). Entity ids and copy live in `HassCore/Config/ClimateConfig.swift`; the rules in `HassCore/Climate/ClimateLogic.swift`.

## Page, top to bottom

1. **Whole Home** section.
   - Dial titled "Whole Home" on `climate.demo_contact_2`, or on `climate.demo_contact_1` while effectively away. The action line always reads the global entity's `hvac_action`.
   - **Effective away** = `sensor.demo_away_1` is `Away`, or it is unknown/unavailable/missing and `binary_sensor.demo_contact_1` is `on` (web `thermostatEffectiveAway`).
   - Commits: a heat/cool range set on the global thermostat goes to all eleven room thermostats (web `useCommitThermostatTemperature`); the eco-away thermostat and single targets go to the dial's own entity.
   - **Thermostat Hub** pill (`climate.demo_climate_3`): thermostat icon, "Thermostat Hub", state text; border and icon tinted by `hvac_action` (heat `#cd5401`, cool `#2c8e98`). Trailing HVAC mode dropdown (`hvac_modes` → `climate.set_hvac_mode`; labels `Heat/Cool` for `heat_cool`, icons `HVAC_MODE_ICONS`) and fan dropdown (`fan_modes` → `climate.set_fan_mode`, hidden when there are none).
   - **Away notice** when effectively away or the effective state is `Away`/`Unknown`/`Unavailable`: "{Vacation Mode|Away Mode} Active. The room may be cooler or warmer than your heat/cool targets to save energy while away." (Vacation Mode while `input_boolean.demo_mode_3` is on) else "{state} Mode. {reason}" with `sensor.demo_away_2`, falling back to "Home Assistant has not provided an effective-mode reason."
2. **Warning** when `input_boolean.demo_contact_1` is `off`: "Automatic Thermostat is off. Open Advanced Configuration to turn Home Assistant's thermostat control back on."
3. **Open Contact Sensors**, only while `binary_sensor.demo_contact_2` is on: one read-only card per open sensor (window icon when the title names a window, else door).
4. Three **entries** in a grid of up to three columns, each a section header, description and disclosure tile: Room Thermostats → Rooms tab, Advanced Configuration → Automation tab, Room Tracking → Tracking tab (copy in `ClimateConfig.Tab`).

## Sheet "Advanced Controls"

Tabs Rooms / Automation / Tracking; detail pages push with Back to their tab.

| Tab | Content | Detail pages |
|---|---|---|
| Rooms | "Rooms" + tab description; 2-column grid of the 11 rooms, subtitle `{temp}°F · {Occupancy}` from `sensor.demo_ext_2` / `_occupancy`; thermometer-check when occupied (`on`/`active`/`occupied`), dimmed thermometer-off otherwise | Room: modal-size dial on the room's climate entity; "{Room} Vent(s)" read-only vent cards ("Vent 1/2" when several, else "Vent"); the room's away notice (`away_mode_active` attribute, else the global away sensor) |
| Automation | Automatic Thermostat toggle; Eco Mode toggle; openers for Eco Mode Critical Tracking and Eco Behavior When Away (subtitle = current option); Predictive Comfort tile | Eco option pages: description, then each option's description and a selectable tile (`select.select_option`); "{title} is unavailable until Home Assistant supplies supported options." when the select has none. Predictive Comfort: three switches, Current Prediction metrics, "Why this prediction?" bullets |
| Tracking | Track Selected Rooms toggle; openers Selected Rooms (`N of 11 selected`, disabled with "Enable Track Selected Rooms first" unless on), Critical Protection (`N rooms forced`; enabled only while selected tracking is on and the critical select is "Track Select Critical"; otherwise shows the select's value or the enable-first text), Occupied Only (`N of 11 occupied only`) | 2-column checkbox grids of `switch.demo_track_<key>`, `switch.demo_ext_3` (untracked rooms only; critical count excludes tracked rooms) and `switch.demo_ext_4` |

Predictive Comfort tile (`switch.demo_contact_4`): off → a tap sends `switch.turn_on`; on → a tap opens the detail and a trailing power button sends `switch.turn_off`. Subtitle `On · {recommendation}` from the switch's `current_recommendation`, else `sensor.demo_living_room_contact_1`'s state (`pre_cool` → `Pre-Cool`). Metrics Indoor, Predicted, Comfort Band, Forecast, Weather, Adjustment from the sensor's attributes; bullets copied from `buildPredictiveReasonBullets` (6720).

## Rooms

Living Room (vents `cover.demo_living_room_vent_1`, `_vent_2_vent`), Office, Primary Bedroom (`cover.demo_bedroom_1_vent_1`, `_vent_3_vent`), Primary Bathroom, Kitchen, Guest Room, Dining Room, Gym, Guest Bathroom, Studio, Media Room (`vent_1`, `vent_2`). Key = lower-cased title with `_`; climate `climate.demo_ext_5`; single vent `cover.{key}_vent_vent`.

## Services

| Event | Service |
|---|---|
| Any switch / input_boolean toggle or room checkbox | `homeassistant.toggle` (optimistic) |
| Predictive Comfort tile / power button | `switch.turn_on` / `switch.turn_off` (optimistic) |
| Eco option | `select.select_option` (optimistic) |
| Hub mode / fan | `climate.set_hvac_mode` / `climate.set_fan_mode` (optimistic) |
| Dial release | `climate.set_temperature` (see the thermostat-dial pattern) |

Optimistic values clear on confirmation, on failure, or after 2 s (web `DEFAULT_OPTIMISTIC_REVERT_MS`).

## Departures from web

- An `unknown` effective home/away state counts as Unknown. The web passes a sensor's raw lowercase `unknown` through `formatCompactEntityState`, so its `Unknown` checks never match; the spec's intent (unknown falls back to Away Mode) wins.
- Unavailable switches are disabled (the web's room checkboxes stay tappable).
- The hub's mode and fan pickers are native dropdown menus with the current choice checked (owner, 2026-10-13), not the web's option-tile dialog; a menu closes after each choice, so the mode no longer stays open.
- The sheet is titled "Advanced Controls" (owner, 2026-10-13), not the web's "Thermostat · Advanced Controls".
- The Predictive Comfort detail shows the recommendation as a "Recommendation: …" line under the title instead of a sheet subtitle.
