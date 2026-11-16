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

## Configured composition primitives

`climate@1` injects explicit synthetic-or-server entity targets into `ClimateController`.
`climate-control` provides atomic `dial`, `hub`, `notice`, `toggle`, `check`, `explicit-switch`,
`mode`, `fan`, `preset`, `options`, `status`, `link` and `room-tile` variants. Each variant negotiates its
own `sh.climate-<kind>@1` capability (`explicit-switch` shares `sh.climate-toggle@1`),
plus `sh.climate-source@1` and bindings. The frozen first-slice capability set is unchanged.
Studio generates the inspector from the same closed, matching contract; copy,
SF Symbols, choice order, dial bounds/step/unit and explicit fanout are authored.
Menus intersect authored choices with live supported options and revalidate at dispatch.
Units are not silently converted or relabeled.

The canonical hub accepts values/closures while retaining its existing controller
initializer. The dial keeps its editor, hit testing, haptics, adjustable elements
and late-failure rollback; publication is blocked during a gesture or actual
service call, independently of the optimistic timeout. One configured controller
is shared by document sources so tracking gates see optimistic peer changes.
The away notice and tracking-count projections use extracted canonical rules,
not new automation. Missing tracking inputs produce unavailable rather than zero.
Eco option rows share the canonical animated checkmark face with the legacy
feature; tracking checks reuse `UKCheckRow`, including selected semantics and
critical-room exclusion.

HIG [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles):
"Use the switch style only in a list row" (iOS/iPadOS). These controls reuse the
canonical row and switch. HIG
[Pop-up buttons](https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons):
"Make options predictable before opening with an introductory label or
effect-describing button label." The canonical hub/pickers retain their labels
and checked native menu choices. The existing dial accessibility rules below
remain authoritative.

This is not a Climate-screen adapter. Status projections include combined
comfort/forecast ranges, the canonical prediction explanation, predictive switch
summary and all three tracking summaries. Explicit switches may attach a status
subtitle; recommendation/adjustment labels use the canonical formatter unless
authored labels override them. Missing bounds and mismatched units remain
unavailable, never relabeled readings.
`room-tile` reads explicitly configured temperature/occupancy sensors, keeps
them on separate lines, and uses the canonical room palette index and authored
room symbol. This follows the current UIKit room tile, not the older web
occupancy-dependent symbol above. `link` carries only a navigation action;
tracking links revalidate canonical live enablement, while Occupied Only
remains independent of selected-room tracking. Status presentations can be
canonical aligned metrics, a recommendation headline or separate paragraphs.
The existing module-list host accepts the narrow row-shaped Climate variants;
dials, tiles and check grids cannot masquerade as module rows.

The complete Home-domain fixture supplies all three local tabs, room details,
Eco options, tracking checks and prediction metrics. Shell integration still
owns pinned bottom tab placement, atomically selecting a tab when presenting,
and conditional child placement inside a retained module-list.
These seams and the parent-run device evidence still gate parity certification.
The canonical Climate page has no schedule editor; thermostat scheduling must
not be invented from the unrelated bedroom/room-device schedule surfaces.

## Departures from web

- An `unknown` effective home/away state counts as Unknown. The web passes a sensor's raw lowercase `unknown` through `formatCompactEntityState`, so its `Unknown` checks never match; the spec's intent (unknown falls back to Away Mode) wins.
- Unavailable switches are disabled (the web's room checkboxes stay tappable).
- The hub's mode and fan pickers are native dropdown menus with the current choice checked (owner, 2026-10-13), not the web's option-tile dialog; a menu closes after each choice, so the mode no longer stays open.
- The sheet is titled "Advanced Controls" (owner, 2026-10-13), not the web's "Thermostat · Advanced Controls".
- The Predictive Comfort detail shows the recommendation as a "Recommendation: …" line under the title instead of a sheet subtitle.
