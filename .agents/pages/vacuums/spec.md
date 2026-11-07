# Vacuums

> **What:** platform-neutral spec for the Vacuums page, vacuum sheet and Mapped map. **Read when:** changing vacuums on any platform.


Source: SFenton/ha-sfenton-react-dash @9ac2a46. `src/pages/DashboardViewPage.tsx` (VacuumPage :1857-1880, ORDERED_VACUUMS :345-350, route :7472, room-page vacuum tile/modal :850, :1116-1122, :1373-1375), `src/constants/portedDashboard.ts` (VacuumConfig :99-176, VACUUM_COLOR :186, VALETUDO_CONSUMABLES :354-371, VACUUMS :516-640, VACUUM_OUTCOME_RECONCILIATIONS :844-858), `src/constants/vacuumAutoClean.ts`, `src/constants/surfaceSemantics.ts` (VACUUM_MODAL_TABS :93-124), `src/components/hass/` VacuumTile.tsx, vacuumTilePresentation.ts, vacuumVisualState.ts, VacuumAutoCleanControls.tsx, VacuumCard.tsx (2747 lines), vacuumModalRuntime.ts, vacuumStatus.ts, VacuumOutcomes.tsx + vacuumOutcomes.ts, ValetudoMapCard.tsx + .utils.ts, ValetudoMapGeometry.ts, ValetudoMapFocus.ts. Copy: `src/i18n/locales/en/modals/vacuum.json`. Route `vacuums`, title "Vacuums", icon mdi:robot-vacuum (routes.ts:73); also reached from the At-a-Glance "Vacuums" tile (atAGlance.ts:251).

## Page (top to bottom), two responsive sections
1. **Robot Vacuums**: bounded grid, 2 cols (max 3, max cell 280pt, last row fills). One VacuumTile per vacuum ordered Main Floor, Studio, Media Room (order from VACUUM_AUTO_CLEAN_CONTROLS titles).
2. **Auto-Clean**: same grid, three toggle tiles (VacuumAutoCleanControls.tsx):
   - Main Floor `switch.demo_main_floor_1` (inverted: enabled when **off**), service `switch.turn_on/turn_off`.
   - Studio `automation.demo_studio_1`, Media Room `automation.demo_media_room_schedule_1`; enabled when on, `automation.turn_on/turn_off`.
   - Subtitle Enabled / Paused / Unavailable; bg VACUUM_COLOR rgba(67,160,71,0.6) when enabled; optimistic, cleared on confirmation, revert 8 s.

## Vacuums (exact ids)
| | Main Floor | Studio | Media Room |
|---|---|---|---|
| vacuum | `vacuum.demo_vacuum_1` | `vacuum.demo_vacuum_2` | `vacuum.demo_vacuum_3` |
| status (contract) | `sensor.demo_main_floor_status_1` | `sensor.demo_studio_status_5` | `sensor.demo_media_room_status_1` |
| clean script | `script.demo_main_floor_1` | `script.demo_studio_1` | `script.demo_media_room_1` |
| area script | `script.demo_main_floor_zone_1` | `script.demo_studio_zone_1` | `script.demo_media_room_zone_1` |
| dock clean / dry | `script.demo_main_floor_2` / `_dry` | `script.demo_studio_2` / `_dry` | `script.demo_media_room_2` / `_dry` |
| passes | `input_select.demo_main_floor_1` | `input_select.demo_studio_1` | `input_select.demo_media_room_1` |
| mode text | `input_text.demo_main_floor_mode_1` | `input_text.demo_studio_mode_1` | none |
| hash | main-floor-robot-vacuum | music-room-robot-vacuum | theater-room-robot-vacuum |
| map | scale 1.2, rotated 180, room-tap selection | scale 2.4, room-tap selection, focus on segments 3/10/12 (pad 15 cm, wall 20 cm) | scale 2.4 |

Per `{m}` = vacuumMapId: `sensor.{m}_battery_level`, `_error`, `_status_flag`, `_dock_status`; `select.{m}_mode`, `_fan`, `_water`; `button.{m}_trigger_auto_empty_dock`; `binary_sensor.{m}_mop_attachment`; map `camera.{m}_map_data`; consumables `sensor.{m}_{main_brush|right_brush|main_filter|sensor_cleaning|wheel_cleaning}` (minutes; titles Main Brush, Side Brush, Main Filter, Sensors, Wheels) and `sensor.{m}_{dustbag|freshwater|wastewater|detergent}_dock_component` (status; Dustbag, Fresh Water, Waste Water, Detergent).
Zones: Studio `input_boolean.demo_studio_2`, `clean_downstairs_hallway`, `clean_downstairs_bathroom` (mop required). Main Floor 11 rooms `input_boolean.demo_ext_15` for living_room, primary_bedroom, kitchen, office, hallway, guest_room, primary_bathroom, guest_bathroom, gym, primary_bedroom_closet (title "Closet"), dining_room; mop required from `sensor.demo_ext_16` attr `mop_required` (default true). Media Room: no zones. Main Floor only: auto-clean skip switches `switch.demo_ext_17` (same 11 rooms), session `sensor.demo_main_floor_state_1`, reconciliation `input_text.demo_ext_18`.

## VacuumTile
Title = vacuum title (room pages override). Subtitle "{State} • {battery}%" or just state. Visual by state (vacuumVisualState.ts): cleaning mdi:broom teal rgba(0,150,136,.58); docked mdi:home green; returning mdi:home-import-outline blue; paused mdi:pause-circle amber; error mdi:alert-circle red; idle mdi:robot-vacuum neutral; unavailable/unknown mdi:robot-vacuum-off muted. Tap opens the modal (hash per table; room pages use `#robot-vacuum`).

## Vacuum modal ("{Title} Robot Vacuum", workspace size)
Layout: map + status left, tab panel right (stacks on narrow). Runtime mode `full` when command policy is normal and state is docked/idle/error (not low battery) and not resumable; otherwise `minimal` (vacuumModalRuntime.ts).
Command policy (VacuumCard.tsx:406-476): none if primary unavailable; restricted if error/status_flag/battery/dock sources unreadable, an issue is present, active conditions exist, state not docked/idle, or dock busy (cleaning/drying/emptying/error/pause); merged with the most restrictive `command_policy` from the status-sensor contract.

**Map (ValetudoMapCard)**: fetch `/api/camera_proxy/camera.{m}_map_data` (or `entity_picture`) with auth, parse PNG chunks, find `zTXt` keyword `ValetudoMap`, zlib-inflate to JSON (`__class: "ValetudoMap"`); poll every 3.5 s while live, entity refresh every 3 s. If vacuum unavailable but camera exists, show "Last Reported Map" (single no-store fetch) with notice copy. Render layers (floor/segments/walls with material accents), robot, dock, obstacles, go-to; pinch/scroll zoom 1-10x; room tap toggles zone (full mode, mapRoomSelection); numbered order badges. Focus crop (ValetudoMapFocus.resolveValetudoMapFocus) to required segments. Locate pill calls `vacuum.locate`.

**Status panel**: pills Status, Battery "{n}%", Dock Status (when dock controls), Locate. Notices: unavailable help, "Error Source Unavailable", "Current Issue" (raw error), "Home Assistant Condition" (Kept for Later / Vacuuming Only / Docking May Be Incomplete), "Previous Issue". **Cleaning Report** ("{Room} Cleaning Report (n)") from session attr `while_away_outcomes`, summary chips (n Rooms Completed / Unverified / Need Attention / Errors); tap pushes detail titled "Cleaning Report" with the subtitle "{Room} · Automatic · n rooms" (departs from the web's long "{Room} · Automatic Cleaning Report (n)", which truncated on iPhone and the Duo outer display; owner 2026-10-24, HIG Navigation bars: keep titles short; before iOS 26 the subtitle is the first line of the list), back "Back to Vacuum Controls", per-room status groups and expandable "Cleaning Evidence".

**Tabs** (VACUUM_MODAL_TABS; Controls always; others filtered):
- **Controls** (mdi:robot-vacuum): section titled by state. Rooms/Area segmented selector (when area script). Rooms: description "Choose how many passes...", Selected Rooms list (ordered) or "Full Clean" warning box, passes picker (`input_select.demo_front_yard_1`), Clean calls the clean script directly as a service (`script.<id>`, no data; VacuumCard.tsx:601). Area: "Draw Area"/"Edit Area" pushes area editor (title "{Title} Cleaning Area"; drag to draw, move, corner-resize; min 25 cm), "Clear Area", "Start Area Clean" calls the area script service with `{x_min_cm, x_max_cm, y_min_cm, y_max_cm}`; disabled with "Local preview only..." if script not in HA services. Switching rooms<->area confirms (copy `confirmations.*`). State actions: idle Dock (`vacuum.return_to_base`); error Stop (`vacuum.demo_vacuum_2`) + Dock; resumable Resume (`vacuum.start`) + Cancel (`vacuum.demo_vacuum_2`, optimistic status_flag none); cleaning Pause (`vacuum.pause`, disabled during dock prep) + Stop (return_to_base) or "Cancel Cleaning Session"; paused Resume + Stop; returning Pause. **Power Settings** (full only): Mode `select.{m}_mode` (label from mode text helper), Fan (hidden when mode mop), Water (hidden when mode vacuum); `select.select_option`.
- **Rooms** (`zones`, mdi:floor-plan, full mode + zones): zone description lines, 2-col buttons, toggle `input_boolean.turn_on/off`, order badge; auto-sets mode to `vacuum` if no selected room needs mop else `vacuum_and_mop`.
- **Auto-Clean** (mdi:robot-vacuum-off, Main Floor only): "Disabled Auto-Clean Rooms" + description, 2-col checkboxes; on = skipped; `switch.turn_on/off`, optimistic 8 s.
- **Actions** (`more`, mdi:flash; full mode, or minimal while dock cleaning/drying): "Dock Controls": Clean Mop Dock / Stop Dock Clean, Dry Mops / Stop Mop Drying (scripts; need docked, mop attached, `valetudo_vacuum_coordinator.dock_action` service), Empty Bin (`button.demo_button_3`). Alerts "Attach the mop pads..." / "...after Home Assistant restarts."
- **Info** (mdi:information-outline): consumable pills; duration as hours, warning at <=600 min, danger at <=0; status ok/alert.
- There is **no Schedules tab** for vacuums in source (Schedules exists only on the humidifier modal).

Optimistic: vacuum state (8 s, clean start 30 s; clean is queued until pending setting intents confirm plus 650 ms quiet; fails with "The vacuum did not begin cleaning within 30 seconds." or the queued-canceled copy); selects/zones register intents confirmed by live state.

## Native notes
- Reuse: GlassTile (`.navigate` VacuumTile, `.toggle` auto-clean), DynamicGridLayout, modal-sheet pattern (`.large`, NavigationStack for area editor and report detail), ComponentGallery.
- New: `VacuumTile` + `VacuumVisualState` (HassDesign, used on rooms too; note in entity-tile.md). `ValetudoMapView` + `ValetudoMapParser` (HassCore: PNG zTXt + zlib via Compression framework) + `ValetudoMapGeometry`/`Focus` (pure Swift, port the unit tests) -> HassDesign with pattern doc `valetudo-map.md`. `VacuumCommandCoordinator` and status-contract parser (HassCore). `VacuumSheet`, `VacuumOutcomeReport` (Features/Vacuums). Gallery pages: VacuumTile states, map (mock maps from ValetudoMapCard.utils), consumable pills.
- Split view: single page on phones, Duo folded/unfolded portrait, iPad portrait. Unfolded landscape and iPad landscape: Robot Vacuums primary, Auto-Clean secondary. The modal itself keeps map-left/panel-right in landscape.
- Open questions: Is "Schedules" meant to be added (no source)? Keep area editor on phones or iPad only? Is `valetudo_vacuum_coordinator.dock_action` always installed now?
