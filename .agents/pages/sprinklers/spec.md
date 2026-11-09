# Sprinklers

> **What:** platform-neutral spec for the Sprinklers page (web route `sprinklers`). **Read when:** changing Sprinklers on any platform.

Source: `ha-sfenton-react-dash@9ac2a46:src/pages/SprinklersPage.tsx`, `src/components/hass/SprinklerController.tsx`, `sprinklerState.ts`, `src/constants/sprinklers.ts`; copy `src/i18n/locales/en/pages/sprinklers.json`. Entry: Home Quick Links "Sprinklers", shown only while `input_boolean.demo_input_boolean_3` is on.

Two Orbit B-hyve controllers under "Controllers", side by side when wide: **Front Yard** (one zone) and **Garden Faucet** (Bushes, House, Backyard, Sidewalk). Entity IDs in `SprinklersConfig`.

**Reading** (`buildSprinklerSnapshot`): available = state entity available and any valve available; watering = a valve `open`/`opening`; status unavailable > fault > watering > ready; battery low at ≤ 20%; mode from the device-mode select, else the state entity; a zone's program is the one whose `run_times[].station` matches the valve's `station`, else its configured program; program attributes `frequency.days` (0 = Sunday), `start_times`, `budget` (default 100), `run_times[].run_time`; history attributes `start_time` (else state) and `run_time`. Times show as time of day only.

**Card:** low battery alert "Battery N%"; tile (controller, "{Mode|Watering|Fault} · Next {time}" or Unavailable) opening the controller sheet; pills Battery, Next watering, Last watering, Hub (Connected/Unavailable).

**Controller sheet:** Status pills (Controller, Battery, Next, Last + run time); Zones (name, Watering/Closed/Unavailable, last run; disabled while another zone waters) → Water now; Controls "Stop watering" (while watering) → `bhyve.stop_watering` {entity_id: running valve}; Settings "Rain delay · 24 hours" and "Smart watering" → `switch.turn_on|off`; Schedule rows ("{zone} schedule", "{days|Every day} · {times}", "{zone} · {min} min · {budget}%", switch → program on/off) → schedule editor.

- **Water now:** run time 1-60 min (default 15) → "Start watering" → `bhyve.start_watering` {entity_id: valve, minutes}; disabled in `off` mode, while watering or when the zone is unavailable; returns on success.
- **Schedule:** Program enabled; Start program → `bhyve.start_program` {entity_id: program}; days S-S; start times (add 07:00, remove while more than one); Watering budget 0-200 step 5; read-only run time; Apply → `bhyve.update_program` {entity_id, budget, frequency: {type: days, days}, start_times}; returns on success.
- Every write shows optimistically, clears on confirmation, reverts after 10 s or on failure; a failure shows Home Assistant's message inline.
