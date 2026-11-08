# Live Activities, one per job (spec v2)

> **What:** how S+H shows each running household job, and each device problem, as its own Live Activity, kept current by Home Assistant while the app is closed. It covers the wire contract, the `fenton_home` job engine, every job kind and problem code, stop and cancel flows, slots and ordering, the views, tests and the lane plan. **Read when:** building or changing Live Activities, the widget extension, the `fenton_home` engine, or the Home Assistant side.

Status: spec, owner-approved design (2026-10-17). **The app lane (§11, §12) is built** on `claude/live-activities-v2-app` (see the app-lane notes at the end of §11); the engine and relay lane (§9) and the Home Assistant config (§10) are not. It **supersedes** [live-activities.md](live-activities.md) §1 ("one activity, not many"), §3 (content state v1), §4 (presentation) and §6 (engine rules), and **retires** [live-activities-ha-automations.md](live-activities-ha-automations.md) once the engine ships. Everything else in those files (the token plumbing in §0, privacy, the Phase 1 targets) still holds.

Design source: the canvas **S+H Live Activity** (the owner's private mockup gallery, link kept outside the repo), boards 5 to 8: "Two jobs" and "Four jobs" stacks, "Corner mark follows your app icon", "Vacuum, one room per card", "Expanded island on every camera width", "Problem cards". The boards are the visual contract; this file is the behavioural one.

## 0. Decisions (owner, 2026-10-17)

1. **One Live Activity per job**, not one aggregate activity with a pager. Each card has the job's full name and one big value. There is no subtitle line for fans, the dishwasher or laundry.
   - **HIG departure:** the HIG prefers one activity that follows several events. The owner chose separate cards because each gets its own button, ends by itself and needs no paging. Recorded here; the slot cap in §6 keeps us inside the per-app limit.
2. **No auto-rotation.** Activities run no code, so a 10 s carousel is impossible. Relevance scores decide which card the Dynamic Island shows.
3. **The corner mark** is the house and heart only, 40 pt, with no tile. It is tinted with the app icon picked in Settings → Appearance → App Icon, and falls back to Navy + Sky.
4. **Buttons say Stop.** For a fan, Stop turns the fan off; it does not just cancel the timer.
5. **Vacuums show one room at a time.** A card ends when its room finishes, and a new card starts when the next room starts. There are no room counts and no map.
6. **One problem card design for every device.** The device name is the title. Red means it stopped and needs you (with sound); amber means it carries on but needs attention (silent). **There is no offline card.**
7. **Laundry has no buttons.** People swipe the card away.
8. **"Complete" everywhere** (2026-10-17, round 4). Every job that finishes on its own (dishwasher, washer, dryer, hot flash) shows **Complete** for **5 minutes** (the default linger), then ends. A job stopped by a person ends at once. Card text is 17 pt title over a 28 pt value.
9. **No laundry estimates.** Spin cycles vary, so the washer and dryer count up and never show an estimated completion. The washer card exists only during the spin. Both finish on the same signal as the household "done" notification.
10. **Everyone with S+H gets cards** (every registration with a push-to-start token), not only the owner's phone.
11. **Hot flash** is a job (§4a), with its own audience rules.
12. **Problem cards replace the household notification** for people with S+H, and live as long as the related Choreapp task: they end when Home Assistant auto-completes it or a person completes it, including with the card's own **Done** button (§5).

## 1. What failed in Phase 1 (2026-10-17)

| Symptom | Root cause | Fix (where) |
|---|---|---|
| A card stays on "Stopping…" until the app opens | `script.fenton_home_activity_push` failed on every run. `jobs` is rendered with `tojson`, HA's native typing turns it back into a list, and `jobs \| from_json` then raises. So no start, update or end ever left Home Assistant. Traces: 16:31:31, 16:32:50 and 16:32:53 PDT, all `from_json got invalid input` | Fixed in `/config/packages/fenton_live_activity.yaml` at 17:27 PDT (backup `*.from-json-fix-20261017.bak`); the next run finished. The same bug is fixed in [live-activities-ha-automations.md](live-activities-ha-automations.md) |
| …and nothing ever cleared it | The optimistic `.stopping` update sets `staleDate: nil` and the app has no timeout (`HomeActivityActionHandler.swift:54,62`), so a lost confirmation leaves it there forever | §7: an optimistic state always carries a stale date, and a stale pending state gives the button back |
| The expanded-island timer is cut off at the top right | `ActivityTrailing(width: 96)` caps an `H:MM:SS` title3 countdown at 96 pt, beside the camera | §8: only the ring and a 22 pt timer sit beside the camera, with no fixed frames; the name and buttons go below the camera |
| The app and Home Assistant both write the activity while the app is open | `HomeActivityDirector` updates from `EntityStore` with no hand-off (spec §0 decision 3 said it "must yield", which was never built) | §2: the engine is the only writer of content. The app writes only the optimistic state |

## 2. Architecture

```
Home Assistant (always on)
  device entities ──state changes──▶ fenton_home job engine (live_jobs.py, new)
                                       adapters: fan, dishwasher, dryer, washer, vacuum, problem
                                       slots, relevance, coalescing, control map, timestamps
                                       │  per job: notify.mobile_app_<device>_fenton
                                       │  {tag: "job.<id>", live_update: true, fenton_activity: {v: 2, …}}
                                       ▼
                                     mobile_app (core 2026.10.1): start | update | end per tag
                                       ▼
                                     fenton_home relay (payload.py) ─▶ APNs liveactivity
iPhone: ActivityKit renders · button → LiveActivityIntent (app process)
        → optimistic local update + webhook fire_event fenton_live_activity_action {tag, job, control}
        → engine calls the service, waits for the state, pushes the result
```

Rules:
- **The engine is the only writer of job content.** Job derivation lives in Python inside `fenton_home`, with unit tests, not in YAML templates. The Phase 1 YAML package is what broke, and nothing tested it.
- **The app writes only three things:**
  1. the optimistic pending state after a button;
  2. `endAll()` on sign-out;
  3. token reports.
- **The foreground director and `HomeJobDeriver` are deleted.**
  - The app no longer starts activities locally. iOS 17.0 and 17.1 lose Live Activities; push-to-start needs 17.2. The owner runs iOS 27.
- **Tags.** One tag per job, `job.<job_id>`. Examples: `job.fan.guest`, `job.fan.master`, `job.dishwasher`, `job.dryer`, `job.washer`, `job.vacuum.main_floor`, `job.vacuum.music_room`, `job.vacuum.media_room`.
  - A device's problem state rides on **the same tag**: the card turns into a problem card and back. A problem with no running job, for example "Dust bag full" while docked, starts that device's tag on its own.
  - So a device never has two cards.
- **One attributes type.** `HomeActivityAttributes` stays. Core holds one push-to-start token per registration (`app_data.start_live_activity_token`), and the type name is the wire `attributes-type`. Renaming it would orphan the token.

## 3. Wire contract v2

### Attributes (static, sent on start)

All new keys decode with defaults, so Phase 1 pushes still decode.

| Key | Type | Example | Notes |
|---|---|---|---|
| `tag` | String | `job.vacuum.main_floor` | |
| `title` | String | `Main Floor Vacuum` | The device. It never changes for the life of the activity |
| `kind` | String | `fan` · `dishwasher` · `dryer` · `washer` · `vacuum` · `problem` · `generic` | `home` is still decoded (Phase 1) |
| `symbol` | String | `fan` | Glyph id from the app's own set (§8), not an SF Symbol name on the wire |
| `tint` | String | `air` · `cleaning` · `water` | A `ColorFamily` raw value |

### Content state v2 (`aps.content-state`)

Explicit `CodingKeys` with snake_case keys. Times are Unix seconds as doubles (the 2001-epoch trap still applies).

```json
{"v": 2,
 "phase": "running",
 "headline": "Vacuuming Kitchen",
 "value": {"kind": "countup", "start_ts": 1792281000},
 "progress": null,
 "controls": [{"id": "pause", "title": "Pause"}, {"id": "dock", "title": "Dock", "role": "secondary"}],
 "problem": null,
 "pending": null,
 "url": "/sfenton-react-dash/home?path=vacuums"}
```

| Key | Type | Meaning |
|---|---|---|
| `v` | Int | `2`. A `1` payload decodes by taking its focus job, for one release |
| `phase` | `running` `paused` `waiting` `problem` `done` | `waiting` covers a delayed start ("Starts 5:10 PM") |
| `headline` | String? | Overrides the title line on the card. Vacuums use it ("Vacuuming Kitchen"); everything else leaves it nil and shows the attribute `title` |
| `value.kind` | `countdown` · `countup` · `percent` · `text` | `countdown` needs `end_ts` (and `start_ts` for the ring). `countup` needs `start_ts` and an optional `paused_elapsed_s`, which shows a frozen time while paused. `percent` needs `progress`. `text` needs `text` (≤ 16 characters, e.g. "Done") |
| `value.estimated` | Bool | The dryer's learned ETA. It still shows a countdown; the VoiceOver label says "about" |
| `progress` | Double? 0…1 | Drives the ring when there is no time range |
| `controls` | [≤ 2; ≤ 3 on problem cards] `{id, title, role}` | `role`: `primary` (white pill) or `secondary` (dark pill). The first control is primary. Problem cards put Done last |
| `problem` | `{severity, code, icon, problem, message, chips[≤1], task_id?}`? | Present ⇔ `phase == problem`. `severity` is `critical` or `warning`. `icon` is from the problem glyph set (§5). Strings are already worded by the engine |
| `detail` | String? (≤ 32) | The small line under the title (13 pt). Hot flash only today: "Your side", "Resident A's side", "Resident B's side" or "Whole bed", plus " · by Resident B" / " · by Home" when it fits (dropped otherwise). Title stays the attribute `title` ("Hot Flash") and `headline` is null |
| `short` | String? (≤ 10) | The compact island's trailing word when the card has no `value` (§8a): the room ("Kitchen"), "Paused" or "Area". Decoded with a default |
| `notice` | String? (≤ 60) | One-update message from §7 ("Couldn't stop. Try again.", "No longer available"); shown in place of the value |
| `pending` | `{control, label, since_ts}`? | Written **only by the app** (§7). The engine never sends it, so any push clears it |
| `url` | String? | Tap target, mapped by `ActivityDeepLink` |

Wire details agreed between the lanes (2026-10-17): null keys are omitted; `kind`, `symbol` and `tint` reach `attributes` on start (`kind` is `generic` for a v2 job card, `problem` for a card that starts as a problem); the first control carries no `role` (primary) and others carry `role: "secondary"`; a problem card's `value` is text "Needs help" or "Attention" (the island's trailing label); a Complete card has `progress: 1.0`, no controls and value text "Complete"; a `clear_notification` end carries `{v: 2, phase: done, value: {kind: text, text: "Ended"}}`. Timestamps increase per device and tag.

Budget: the whole payload must be ≤ 4 KB. Strings are capped: title 32, headline 32, problem 40, message 90, chip 20 characters. The relay refuses anything larger, and the views truncate.

### Fixtures

The relay lane generates `tests/fixtures/live2-*.apns` (fan start, fan stop end, dishwasher percent, washer and dryer count-up, Complete (dishwasher, washer, dryer, hot flash), hot flash cooling / holding / by another resident / whole bed, vacuum count-up, vacuum paused, problem critical, problem warning, unknown error, unmapped error, v1 compatibility). They are mirrored into `tools/push_fixtures/`, and the app's `RelayFixtureTests` decode every one. **The app lane hand-writes the same fixtures from this table first**, and review diffs the two sets.

## 4. Jobs

Times are local. "End now" means `clear_notification`, which the relay sends as `dismissal-date = now` (immediate removal).

| Job | Starts when | Card | Updates on | Ends when | Controls → service |
|---|---|---|---|---|---|
| **Bathroom fan** (`fan.guest`, `fan.master`) | `input_boolean.<r>_bathroom_fan_timer_pending` turns on and `input_datetime.<r>_bathroom_fan_timer_ends_at` is in the future (`ends_at` is stale after a cancel, so check both) | "Guest Bath Fan", countdown to `ends_at`; ring from pending `last_changed` | `ends_at` moves by more than 30 s (timer extended) | pending turns off (expired, cancelled, fan turned off anywhere) → end now | **Stop** → `script.<r>_bathroom_fan_command {command: power, target_power: off}`. The lane confirms in `scripts.yaml` that `power off` also clears the timer; if not, call `timer_cancel` and then `power off` |
| **Dishwasher** (`dishwasher`) | `sensor.demo_state_2` → `run` (or `delayedstart`, which is `waiting` with "Starts h:mm") | "Dishwasher", countdown to `sensor.demo_ext_21`; if that is unavailable, `percent` from `sensor.demo_program_1` | finish time moves by more than 60 s; progress +5 points, at most every 5 min, priority 5; `pause` ↔ `run` | `finished` → **Complete** for 5 min, then end; `ready` / `inactive` / `aborting` → end now | **Stop** → `button.press button.demo_ext_24` (only while `binary_sensor.demo_ext_23` is on; otherwise no button). While `pause`: **Resume** → `button.demo_ext_25`. No Pause (Home Connect has no pause entity) |
| **Dryer** (`dryer`) | `input_boolean.demo_input_boolean_7` → on (5 min after vibration starts, so `start_ts` = on − 300 s) | "Dryer", `countup` from `start_ts`. Steady full ring. No estimate | nothing in between | helper → off (the same trigger as `Washer/Dryer Notifications`) → **Complete** for 5 min, then end. No alert | none |
| **Washer** (`washer`) | `input_boolean.demo_input_boolean_6` → on (the spin; 5 min after vibration starts, so `start_ts` = on − 300 s) | "Washing Machine", `countup` from `start_ts`. No estimate | nothing in between | helper → off → **Complete** for 5 min, then end. No alert | none |
| **Vacuum, Main Floor** (`vacuum.demo_ext_26`) | `sensor.demo_ext_27` gets a `room_id` with phase `cleaning` (or `resumed_cleaning`) | headline `{Vacuuming\|Mopping\|Cleaning} {room_name}`. The verb comes from `vacuum_only`, else `select.demo_mode_3` (`vacuum` → Vacuuming, `mop` → Mopping, `vacuum_and_mop` → Cleaning). Count-up from `start_confirmed_at`. `room_name` comes from the matching `sensor.demo_main_floor_coordinator_<room>_last_cleaned` attribute | vacuum `paused` ↔ `cleaning` (with `paused_elapsed_s`); problem raised or cleared | `room_id` changes or clears → end now; a new room → start again (same tag; core removed the token on the end, so this is a fresh push-to-start) | **Pause** → `vacuum.pause`, **Resume** → `vacuum.start` (always; the coordinator observes them, and its `set_paused` pauses its scheduler, not the robot). **Dock** → while `binary_sensor.demo_ext_28` is on, `valetudo_vacuum_coordinator.cancel_session {reason: live_activity}`; otherwise `vacuum.return_to_base` (§7) |
| **Vacuum, manual runs** (any robot, no coordinator session) | vacuum → `cleaning` with no coordinator session | `sensor.mapped_<id>_status_flag`: `segment` → "Vacuuming {estimated segment}"; `zone` → "Cleaning {floor} area" (drawn area); `spot` → "Spot cleaning"; `none` → "Cleaning {floor}". Count-up from the state change | segment changes (ends and restarts, as above), pause, problem | `returning` / `docked` / `idle` → end now | as above, with plain `vacuum.*` services |
| **Problem** (any device tag) | §5 | §5 | issue changes | issue clears → back to the job content if the job still runs, else end now | §5 |

Not in this phase (owner, 2026-10-17): EV charging, the grill cook timer, sprinklers and media sleep timers.

### 4a. Hot flash (`hot_flash`, owner request 2026-10-17)

The bed is a smart bed. The engine reads the broker's own entities, **not** the legacy `timer.demo_bed_*` timers, which nothing starts any more. That separate bug is flagged as its own task; it breaks the app's countdown and the "hold started" notification.

| | Left side | Right side |
|---|---|---|
| Owner | Resident A (`person.demo_ext_29`) | Resident B (`person.demo_ext_30`) |
| Phase | `input_select.demo_bed_hot_flash_left_phase` | `…_right_phase` |
| Hold timer | `timer.demo_bed_hot_flash_left` (`finishes_at`) | `…_right` |
| Hard deadline | `input_datetime.demo_bed_hot_flash_left_restore_at` | `…_right_restore_at` |
| Started by | `input_text.demo_input_text_1` (`resident_a` / `resident_b` / `unattributed`; stale between runs) | the second side's twin |
| Cancel | `input_button.demo_input_button_2` | the second side's twin |

**Phases.**
- `cooling` is chilling to the coldest level: value `text "Cooling"`, with the ring filling from the climate's `current_temperature` toward 56 °F.
- `holding` counts down to the timer's `finishes_at` (15 min).
- `restore_pending` → `idle` is the natural end: **Complete** for 5 min.
- `superseded` (someone changed the level by hand) ends now.
- Only `cooling` and `holding` count as active. Never read `restore_at` or `requested_by` alone, because they persist from old runs.

**Audience, per side.**
- **Who:** the side's owner plus the person in `requested_by`, captured when the phase turns `cooling`.
- **Solo Trip** (`sensor.demo_status_1` `mode == solo_trip`): the traveller is removed, even for their own side.
- **Vacation** (`binary_sensor.demo_ext_31`): everyone is removed except the person who started it.
- **`unattributed`** (an automation started it): only the owner gets the card.

**Cards, one per person** (tag `job.hot_flash`, per registration):
- **Title "Hot Flash".**
- **One short line:**
  - "Your side", "Resident A's side" or "Resident B's side";
  - or "Whole bed" when both active sides are in that person's audience;
  - plus " · by Resident B" (or " · by Home" for an automation) when the starter isn't the viewer.
- **Whole bed:**
  - The value is the later of the two ends.
  - `cooling` wins until both sides are `holding`.
  - Stop presses both cancel buttons.
- **Stop:** presses that side's cancel button (§7).
- **No alert.** Relevance 70.

**Today** only one resident has an S+H registration (`notify.mobile_app_demo_phone_fenton`). The other is on the Companion app (`notify.mobile_app_demo_phone_2`), so their cards start when they install S+H. Until then the existing hold notification is their signal.

**Engine needs per-person fan-out.** Map registrations to people through the registration's `user_id` (`person.*.user_id`), not device trackers. The S+H tracker `device_tracker.demo_ext_32` is not attached to any person today.

## 5. Problem cards

Source: every robot's `sensor.<floor>_vacuum_status` (`main_floor`, `studio`, `media_room`) `current_issue` (`{status: clear}` when clear; otherwise `code`, `raw`, `reported_at`). Only when that sensor is missing does the engine map `sensor.mapped_<id>_error` itself (the known table, then `unknown error N` → `vendor.unknown_error_N`, else `unmapped.<slug>`). For the dishwasher it uses `operation_state` `actionrequired` / `error`.

Wording lives in the engine (`problems.py`), so new wording ships with a relay update, not an app release.

| Code | Severity | Icon | Problem | Message | Buttons |
|---|---|---|---|---|---|
| `navigation.stuck` | critical | alert | Stuck in {room} | Move it somewhere flat, then tap Resume. | Resume · Dock |
| `navigation.target_unreachable` | critical | door | Can't reach {room} | A door may be closed. Open it, then tap Resume. | Resume · Dock |
| `navigation.dock_unreachable` | critical | dock | Can't get back to the dock | Clear the way to the dock or carry it there. | Try Again (→ return to base) |
| `navigation.ramp_hazard` (error 95) | critical | edge | Stopped at a drop or ramp | Move it away from the edge, then tap Resume. | Resume · Dock |
| `maintenance.main_brush_jammed` | critical | brush | Main brush jammed | Turn it over, clear the brush, then tap Resume. | Resume · Dock |
| `maintenance.side_brush_jammed` | critical | brush | Side brush jammed | Untangle the side brush, then tap Resume. | Resume · Dock |
| `power.critical_battery` (error 75) | critical | battery | Battery critically low | Carry it to the dock to charge. | none |
| `power.low_battery` | warning | battery | Battery low | Heading to the dock. It finishes {room} after charging. | none |
| `mop.clean_water_empty` | warning | water | Clean water tank empty | Refill the clean water tank on the dock, then tap Resume. | Resume |
| `mop.dirty_water_unavailable` | warning | waste | Wastewater tank full or missing | Empty the wastewater tank and seat it firmly. | Resume |
| `mop.attachment_missing` (error 120) | warning | mop | Mop pads missing | Attach the mop pads, or it vacuums only. | Vacuum Only (→ mode `vacuum`, then resume) |
| vacuum-only fallback (`input_text.<floor>_vacuum_error_message` while the fallback helper is on) | warning | mop | Vacuuming only | Mopping isn't available. Check the mop attachment, water tanks and pads. | none |
| `dock.cover_open` | warning | bag | Dock cover open | Check the dust bag is in, then close the cover. | none |
| `dock.dustbag_blocked` | warning | bag | Dust bag full | Replace the dust bag in the dock. | none |
| `vendor.unknown_error_N` | critical | question | Stopped with an error | Check the robot, then tap Resume. Chip: "Error N" (no time chip) | Resume · Dock |
| `unmapped.*` | critical | question | Stopped with an error | The robot says "{raw text}". Check it, then tap Resume. No chips | Resume · Dock |
| dishwasher `actionrequired` | warning | door_dish | Needs attention | Check the dishwasher's display. (Home Connect gives no reason; refine if an event entity appears) | none |
| dishwasher `error` | critical | question | Stopped with an error | Check the dishwasher's display. | none |
| unavailable / offline | none | | | **No card** (owner). An activity already running ends | |

**Lifecycle follows the Choreapp task** (owner, 2026-10-17).

- **Where tasks come from.** `script.demo_ext_33` creates a Choreapp task for every mapped error except `Low battery` and `Unknown error 75`. The task is named `"<Vacuum name> · <mapped title>"`, for example "Main Floor Vacuum · Robot Stuck", is unassigned, and goes in `todo.demo_ext_34`. No id is stored.
- **Finding the task.** The engine finds it with `todo.get_items {status: needs_action}` on `todo.demo_ext_34`, matching `summary`, and takes `task_id = uid.split('--')[0]`. It keeps the id with the card.
- **When the card ends:**
  - **Taskable problem.** The card stays until that task is completed. The engine listens to `todo.demo_ext_34`:
    - Home Assistant auto-completes `current_fault` errors when the error sensor reads `No error`.
    - `Mapped Dock Component Task Lifecycle` completes `persistent_condition` ones (tanks, dust bag, tray, cover, mop pad) when the dock recovers. Clean-water tasks are manual only.
    - A person can complete it here, in the app or in Choreapp.
    - If the error clears and the job is still running, the card shows the job again. The task can then still be open (persistent conditions), so the card stays a problem card until the task closes.
  - **Problem with no task** (low battery, error 75, unmapped text, dishwasher `actionrequired`/`error`). The card ends when the condition clears.
- **Done button.**
  - **Every taskable problem has Done as its last control.** Problem cards may carry **3** controls (Resume, Dock, Done), the only exception to the 2-control cap.
  - **What Done does:** the engine calls `donetick.complete_task {task_id}`, with `completed_by` set to the Choreapp user mapped from the event's HA user when known. It then ends the card on every device once the todo list shows the task as completed.
  - **The pending label** is "Completing…".
  - **If the task is already completed,** the call is a no-op (`continue_on_error`).
- **The card replaces the household push** for people with S+H.
  - Today `Vacuum Error Notifications` sends to `notify.demo_notify_1` (= one notify group per person, each listing the Companion app's `mobile_app_<device>` and, where installed, `fenton_<person>`).
  - That notify step becomes a call to a new engine service, `fenton_home.problem`: `{device, code, raw, title, message, task_title, url, tag}`.
  - For each person in the household, the engine shows a card on their S+H registrations that have Live Activities enabled. **For those people it skips all their notify targets** (their Companion app too). Everyone else still gets the push, through their own `notify.<person>_phone` group.
  - **Clearing.** When the card ends, the engine also clears any fallback push with `clear_notification` on the same tag (`vacuum-<room>-error`). Today those pushes are never cleared.
  - The same service later takes the dishwasher's "Refill rinse aid" task. That task has no auto-complete, so only Done or Choreapp ends it.

Rules:
- **Alerts.** A critical problem alerts with sound. The engine sends `live_alert: true` on the update that turns the card red, or, when the problem starts a new activity, a start followed by an alerting update 2 s later. The relay's start alert is silent; §9 adds a start-sound option and then the follow-up goes away. Warnings never alert. Clearing never alerts.
- **Unknown text** is quoted as received, capped at 60 characters, and the engine logs `fenton_home.problem_unmapped` once per text so the mapping can be added.
- `power.low_battery` while returning keeps the job card's tag. When the robot docks to charge mid-session, the card stays as a warning until cleaning resumes (then it is the job card again) or the session ends.

## 6. Slots, ordering and budget

- **Cap: 5 activities per device**, the observed per-app limit (`targetMaximumExceeded`); Apple publishes no number. The engine keeps **4 for jobs and 1 for a problem**.
  - A fifth job waits in the engine's queue and starts when a slot frees.
  - A problem when all 5 are used ends the job with the lowest relevance (the latest-ending one) and takes its slot.
- **Relevance score** (`data.relevance_score`, re-sent on every update):
  - critical problem 100;
  - warning 90;
  - jobs `80 − min(minutes left, 60) / 2` (so 50 to 80, where sooner is higher);
  - count-up jobs 55;
  - hot flash 70;
  - Complete (linger) 10.

  The Dynamic Island shows the highest; the Lock Screen orders by it.
- **Priority.** 10 for start, end, alerts and control confirmations; 5 for everything else (the relay's rule already). Don't set `NSSupportsLiveActivitiesFrequentUpdates`. Running timers tick on their own, so pushes happen only on real changes.
- **Coalescing.** At most one push per tag per 2 s. A burst collapses to the latest state. The relay stamps strictly increasing timestamps per tag (§7).
- **8-hour limit.** No job here runs that long. The engine ends any activity at 7 h 45 min, and restarts it if the job is still going.
- **Person's dismissal.** On `fenton_live_activity_dismissed {tag}` the engine marks that tag dismissed until the job ends; it doesn't restart a card someone swiped away. A **problem** that becomes critical after a dismissal does start again.

## 7. Buttons, stop and cancel

Sequence for every control:

1. **Intent (app process, `JobControlIntent(tag, control)`).**
   - Find the activity by tag.
   - Write `pending = {control, label, since_ts: floor(now)}` with `staleDate = now + 20 s` and `timestamp = floor(now)`, in whole seconds, never in the future. `label` is "Stopping…", "Pausing…", "Resuming…" or "Docking…".
   - The view swaps the controls for the label.
   - Fire `fenton_live_activity_action {tag, job, control}` on the registration webhook, with a 10 s timeout.
   - On a webhook failure, write the previous content back with no `pending` and a `notice` "Couldn't reach Home".
2. **Engine.**
   - Check that the job still offers that control and that the event's user (context) is allowed.
   - Call the service from the control map (§4, §5). The map lives in the engine, never on the phone.
   - Then wait up to 15 s for the expected state (fan pending off; dishwasher `ready`/`inactive`; vacuum `paused`/`cleaning`/`returning`).
3. **Confirm.**
   - **Stop and Dock** succeed → end now. The card disappears; that removal is the confirmation.
   - **Pause / Resume** → an update with the new phase.
   - **Timeout or service error** → an update with the real current state (controls back) and `notice: "Couldn't {verb}. Try again."`, shown in place of the value for that update only.
4. **If no push arrives at all** (the network is lost after the tap):
   - the stale date passes, and the view sees `context.isStale && pending != nil`;
   - it shows the controls again with a small "Not confirmed" line.
   - A pending state can never stick.
5. **Timestamps.** ActivityKit drops an update whose timestamp is older than the current content.
   - The intent stamps `floor(now)`.
   - The relay stamps `max(ceil(time.time()), last_ts[tag] + 1)`, so a confirmation is always newer than the optimistic write and pushes for one tag never tie.
   - Home Assistant's host is NTP-synced; the engine logs a warning if `now − last_changed` of a state it reacts to is negative (clock skew).
6. **Stop from elsewhere** (the wall switch, the dishwasher panel, the vacuum app) takes the same path from step 3: the state change ends or updates the card. There is no separate "cancellation notification". The card leaving is the signal, and the household notifications (laundry done, dishwasher clean, vacuum complete or stopped early) stay as they are.

## 8. Presentation

All from the canvas boards; Lock Screen first.

- **Job card** (fan, dishwasher, dryer):
  - a 64 pt progress ring with the job glyph;
  - the title (17 pt semibold, one line, tail truncation);
  - the big value (28 pt semibold, monospaced digits; the owner found 38 pt too far from the 17 pt title);
  - finished jobs: a filled ring with a check and **Complete** in the job's tint;
  - the primary control bottom-right;
  - the corner mark top-right.
  - Height ≤ 160 pt at default text size; at AX sizes, the value wraps under the title and the controls stack.
- **Vacuum card.** The same, with `headline` as the title line and a steady full ring (no per-room progress). **Superseded by §8a:** a vacuum has no time, no ring and no bar.
- **Problem card.** It has its own layout, not the job layout:
  - a severity-tinted background (critical red gradient, warning amber) with a matching hairline border;
  - a 44 pt solid severity circle with the problem glyph;
  - the device title, the problem line in the severity's light tint, the instruction in body text, and optional chips;
  - buttons bottom-right;
  - the corner mark.
  - VoiceOver reads "Main Floor Vacuum, needs help: Stuck in Kitchen. Move it somewhere flat, then tap Resume."
- **Corner mark.** Draw the house-and-heart `Shape` from `AppIconArtwork` (HassDesign), 40 pt, tinted with the foreground colour of the chosen `AppIconChoice`.
  - The heart's knock-out uses the card's background colour (problem cards pass their tint).
  - The app writes the choice's raw value to `UserDefaults(suiteName: "group.com.sfenton.home")` key `appIconChoice` at launch and on change. The widget only reads it, falling back to `navySky`. A change shows on the next update.
- **Dynamic Island, expanded.**
  - **Leading region** (beside the camera): the 34 pt ring or the severity circle only.
  - **Trailing region** (beside the camera): the value at 22 pt semibold, monospaced, `lineLimit(1)`, `minimumScaleFactor(0.8)`, **no fixed `frame(width:)`**. Problems show "Needs help" or "Attention" here.
  - **Bottom region:** the title or headline (17 pt, one line, tail truncation) and up to 2 controls.
  - **Center region:** empty.
  - The system sizes the regions for each phone's camera, so there is no device check.
- **Compact:** leading is the ring with the glyph (26 pt); trailing is the value (15 pt, monospaced); a problem shows the severity circle and a one-word label ("Stuck", "Refill water").
- **Minimal:** the ring only, which fits a 28 pt circle.
- **Limited width:** when `isDynamicIslandLimitedInWidth` is set (iOS 27 SDK, behind `#available`), show compact leading only.
- **Always-On / `isLuminanceReduced`:** hide the ring track and keep the value.
- **StandBy** scales the Lock Screen view; drop the corner mark when `isActivityFullscreen`.
- **Watch `.small`:** the glyph, title and value; no controls.
- **Accessibility.** Each card is one element plus its buttons. Controls read "Stop Guest Bath Fan", "Pause Main Floor Vacuum". Count-up values read "running for 12 minutes". Test at AX5 on iPhone, iPhone Duo and iPad, with 44 pt targets.

### 8a. Refinements after the first device test (owner, 2026-10-17; canvas boards 12–16)

These replace the matching parts of §8.

- **Compact (bug).** `Text(timerInterval:)` reports the width of its widest possible value, so an uncapped countdown stretched the compact island almost edge to edge. This is a known iOS behaviour, and Apple's Clock is exempt. The trailing time gets a **rigid** width:
  - **Template:** a hidden, monospaced template string ("00:00", or "0:00:00" when the range is an hour or more), with the live timer in an overlay; `lineLimit(1)` and `minimumScaleFactor(0.8)`. `maxWidth` is not enough.
  - **Size:** 13–15 pt semibold, in the job's tint. Leading is the 24–26 pt ring.
  - **Limited width:** when `isDynamicIslandLimitedInWidth` is set (iOS 27; also the iPhone 18 Pro with two activities), trailing is empty.
  - **No time:** cards with no time (vacuum) show `short` (below) at 13 pt, capped at 56 pt and ending in "…".
- **Expanded = E2c.**
  - **Top, beside the camera:** the job glyph (24 pt) on the left, and the house-and-heart corner mark (24 pt, tinted with the app icon choice, heart knocked out against black) on the right, mirroring it (owner, 2026-10-17).
  - **Below the camera:** the title over the value on the left, **both white** (title 16 pt semibold, value 32 pt semibold monospaced). Up to two buttons sit on the right, **in line** with that title-and-value block. Then a 5 pt progress **bar** in the job's tint, only when there is progress (countdowns and percent).
  - **Title wrapping:** long titles **wrap to two lines**. Live Activity views cannot animate on their own, so a scrolling title is impossible.
  - **Paused:** status text is **always white** (owner, 2026-10-17); nothing dims. Paused is shown by the word itself and the Resume (play) button.
  - **Implementation:** `.leading`, `.trailing` and `.bottom` regions with no fixed frames; the bottom region holds the block.
- **Lock Screen = L4** (bars, no ring).
  - Row 1: the glyph (22 pt) in its tint, then the title (17 pt semibold; it wraps to two lines), with the corner mark (24 pt) top-right.
  - Row 2: the value (32 pt semibold monospaced), with the buttons on the right in the same row.
  - Row 3: the 5 pt bar, only when there is progress.
  - No row holds only a button. The card is about 96–110 pt.
  - Hot flash puts `detail` in row 1 ("Hot Flash · Your side").
  - Complete: a checkmark glyph, "Complete" in the tint and a full bar.
  - Problem cards keep their own layout (§8).
- **Vacuums: no time and no bar anywhere** (owner).
  - **Content:** the engine omits `value` and `progress` for vacuum cards.
  - **Small title:** the attribute title ("Main Floor Vacuum").
  - **Big line (24 pt):** the `headline` ("Vacuuming Kitchen", "Paused in Kitchen"). Always white, paused or not.
  - **Buttons** are 44 pt **round icon buttons** with spoken labels:
    - Pause: a white circle with a pause glyph; it becomes Resume, a play glyph, when paused.
    - Dock: a dark circle with a house glyph, labelled "Dock".
  - **Compact** shows the vacuum glyph and `short`; minimal shows the glyph.
- **New content key `short`** (String?, ≤ 10): the compact island's trailing word when there is no time. The engine sets the room ("Kitchen"), "Paused" or "Area".
- **General rule:** a card with no `value` shows `headline` as its big line under the title.

### 8a-notes. App-lane notes for the refinements (built 2026-10-17, `claude/live-activities-refine`)

Where the build chose or departed from §8a:

- **Titles and the big line.** `ActivityCard.title` is the attribute title. A card with no figure shows `headline` as `bigLine` (24 pt, `lineLimit(2)`). An older engine's card with both a time and a headline is still named by the headline. The hot flash `detail` joins the title as `headerLine` ("Hot Flash · Your side").
- **Two accessibility elements, not one.** The Lock Screen puts the value beside the buttons, so the title and the value can no longer share one combined element. The title reads "Dryer, running for" (or "…, time left") and the value is the next element, with the live time.
- **Compact template.** The hidden template is "0:00:00" when a countdown shows hours, when a frozen time is an hour or more, and for **every count-up** (a count-up gets no push while it runs, so a dryer would pass an hour and outgrow "00:00"; planner review, 2026-10-18). The time is 15 pt semibold (`.subheadline`, a text style, so the template and the live text scale together and the width stays the template's; the island caps its text size). Percent and text values ("62%", "Cooling", "Paused") use the 13 pt word style (`.footnote`), capped at 56 pt.
- **Compact leading and minimal.** A 24 pt ring when the card has a time or progress; the glyph alone when it has neither (a vacuum).
- **Bar.** A system linear `ProgressView` (the timer form for countdowns), scaled to 5 pt. Only countdowns, percentages, fractions and Complete have one.
- **Expanded island, problems.** The leading region is a 28 pt severity circle and the trailing region the 24 pt mark, as for a job. The one-word "Needs help" / "Attention" label that used to sit beside the camera is gone: the island's text is capped at xxxLarge, so a word there fails the Dynamic Type audit, and the bottom block already names the device and the problem line in the severity's tint. (The value text still carries the word, and the compact island keeps its one-word problem label.)
- **Round buttons** apply to a vacuum's job card (glyph `vacuum`, control ids `pause`, `resume`, `dock`). A vacuum's problem card keeps text pills (Resume, Dock, Done).
- **Rings** no longer dim when paused.
- **Not changed.** Problem cards keep their own layout and the 40 pt mark.

## 9. `fenton_home` changes (repo `SFenton/ha-fenton-push`)

1. **`live_jobs.py` engine** (the Phase 2 engine in live-activities.md §7, re-scoped per job):
   - adapters per job kind (§4), each a pure function `(states) -> JobState | None` with unit tests on recorded state snapshots;
   - the slot manager and relevance (§6);
   - coalescing;
   - the control map and the `fenton_live_activity_action` / `_dismissed` listeners (§7);
   - the wait-for-state confirmation;
   - fan-out per registration through `notify.mobile_app_*` (core keeps owning tokens);
   - `sensor.fenton_live_jobs` (per-tag state, for debugging).
   - Configured in the integration's options: which jobs are on and which registrations get cards (open question 4).
2. **`problems.py`.** The §5 table, the raw-text fallback, and the `problem_unmapped` log. Also:
   - the service `fenton_home.problem` (§5), which routes a card or a push per person;
   - the Choreapp link: find the task by title, keep its id, listen to `todo.demo_ext_34`, and handle the **Done** control with `donetick.complete_task`;
   - fallback-push clearing.
2a. **Audience.**
   - Map registrations to people by the registration's `user_id` and `person.*.user_id`.
   - Default audience: every person with S+H.
   - Hot flash audience rules (§4a) read `sensor.demo_status_1` and `binary_sensor.demo_ext_31`.
   - Content is per person (the hot flash line says "Your side" or "Resident A's side"), so fan-out builds the content per registration.
3. **`payload.py` / `live.py`.**
   - Accept content state v2 (validate keys, caps and 4 KB).
   - Put `kind`, `symbol` and `tint` into `attributes` on start.
   - `live_alert` on a **start** adds `sound: default`.
   - Strictly increasing per-tag timestamps (§7.5).
   - Keep v1 for one release.
4. **Dead token recovery.** Core turns a start for a tag that still has a stored (dead) token into an update. APNs answers 410, and core does not remove the token, so the tag can't restart until the token expires (8 h).
   - On a 410 for `liveactivity`, the relay removes that tag's token through core's `mobile_app.live_activity` store helper. It is guarded by an import check and a version check, and logs if core changes.
   - The engine then retries once as a start.
   - Also open an upstream issue so core drops the token on 410 itself.
5. **Tests.**
   - pytest for adapters, problems, slots, timestamps and the control map;
   - HA tests through `mobile_app` with a stored token;
   - fixtures `live2-*.apns` (§3).

## 10. Home Assistant config (planner, with the owner's standing approval; back up first)

- After the engine ships and is verified, remove `/config/packages/fenton_live_activity.yaml`: the engine replaces its script and automations. Back it up first.
- `Vacuum Error Notifications` (id `1769047894700`, `automations.yaml`): replace its `notify.demo_notify_1` step with `fenton_home.problem`, passing the mapped title, message, task title and tag. Back up first. Task creation and auto-complete stay exactly as they are.
- Do not change the hot flash automations here. The dead `timer.demo_bed_*` trigger in `Bed Hot Flash Hold Started Notifications` is its own task.
- Leave every household notification automation as it is (dishwasher clean, rinse aid, laundry done, vacuum complete and errors).
- Validate with `ha core check`; reload template entities. No service call against the house during tests; the engine's unit tests use recorded snapshots.

## 11. App changes

| Area | Change |
|---|---|
| `FentonActivityModel` | `HomeActivityAttributes` gains `symbol` and `tint` (defaults). Content state v2 replaces `jobs[]`/`focus`/pager with the single-job fields in §3; v1 decodes by taking the focus job. Delete `HomeActivityState.pager`, `fitted()`'s multi-job logic, `LiveActivityAction.focus`. Caps per §3 |
| `FentonActivityViews` | New `JobCardView`, `ProblemCardView`, `CornerMark`, island regions per §8. Delete `ActivityPager`, `ActivityFocusLine`, the multi-row Lock Screen, `ActivityTrailing`'s fixed widths |
| `HassCore/LiveActivity` | Delete `HomeActivityDirector`, `HomeActivityPlanner`, `HomeJobDeriver`. `HomeActivityActionHandler` → pending per §7 (stale date, timestamp, notice). `LiveActivityTokenReporter` stays, and must send `live_activity_dismissed` for **every** local end as well as a swipe-away |
| `HassUI/App/LiveActivity` | `LiveActivityCoordinator` keeps token reporting and `endAll` on sign-out only |
| Settings | Write `appIconChoice` to the app group (`AppIconPickerModel` on apply, and at launch) |
| Intents | Drop `FocusJobIntent`. `JobControlIntent(tag, control)` |
| Gallery | `FENTON_GALLERY=live-activity` scenarios for every canvas card: fan, dishwasher countdown and percent, dryer estimated, vacuum running/mopping/drawn area/paused, every problem row (§5) with and without Done, Completing…, pending, pending-stale, notice, 4-card stack |

### App-lane notes (built 2026-10-17, `claude/live-activities-v2-app`)

Where the build chose or departed from the text above, so the engine lane and review can line up:

- **Hot flash line.** The small 13 pt line ("Your side", "Whole bed", "Your side · by Resident B") is the content-state key `detail` (≤ 32), agreed with the relay lane (relay PR #5); the title is the attribute `title` ("Hot Flash") and `headline` is nil. `notice` is capped at 60, a problem's `value` is text "Needs help" or "Attention" (the island's trailing label), a Complete card carries `progress: 1.0`, no controls and value text "Complete", an end stub is `{v: 2, phase: done, value: text "Ended"}`, the first control has no `role` and the rest are `secondary`, and `task_id` may be a string or an integer.
- **Compact island label.** The wire has no field for the one-word label ("Stuck", "Refill water"), so `ActivityProblem.compactLabel` maps the known codes in the app and falls back to "Help" (critical) or "Check" (warning). A new code ships its word with an app update.
- **Corner mark knock-out.** `HouseHeartShape` (HassDesign) cuts the heart's ring out of the house, so it shows whatever is behind it: the card, plain or a problem gradient. The spec's "uses the card's background colour" is therefore true by construction and no colour is passed.
- **Complete.** `phase: done` always reads **Complete**, whatever `value.text` says.
- **Waiting.** `phase: waiting` shows `value.text` ("Starts 5:10 PM") with an empty ring.
- **Text styles.** Titles and figures use the text styles that equal the spec's sizes at the default setting (headline 17, title 28, title 2 22), so the Lock Screen scales with Dynamic Type; the island caps at xxxLarge.
- **Pending timestamps.** The app's write uses `update(_:alertConfiguration:timestamp:)` (iOS 17.2+) and keeps the card's relevance score. A failure that lands in the same second as the press can tie with the pending write and be dropped; the stale date then gives the buttons back.
- **Scheduled activities.** `ActivityState.pending` (iOS 26) counts as active in `SystemLiveActivityClient`.
- **Fixtures.** `tools/push_fixtures/live2-*.apns` replace the Phase 1 `live-*.apns`; `live2-v1-compat.apns` keeps the v1 decode covered.

## 12. Tests and verification

- **Unit tests:**
  - every fixture decodes;
  - v1 → v2;
  - the value-kind rules;
  - pending + stale → controls back;
  - truncation caps;
  - the timestamp floor;
  - the problem table renders every icon.
- **UX and accessibility** (iPhone, iPhone Duo, iPad) through the gallery:
  - every card ≤ 160 pt at default size;
  - names and roles;
  - 44 pt targets;
  - AX5 layout;
  - reading order;
  - the expanded-island stand-in at the smallest and largest widths with an `H:MM:SS` value, asserting nothing is clipped (the trailing text's frame fits inside its region).
- **Coverage** ≥ 95% logic / 95% UX (`tools/apple_coverage.sh`).
- **Relay:** pytest green, plus HA's `ha core check` after the HACS update.
- **Device checks (owner's phone; planner deploys):**
  1. Fan timer from the dashboard with the app closed → card. Stop → card gone, fan off.
  2. Dishwasher run → countdown; Stop → card gone.
  3. Main Floor room clean → card per room; Pause/Resume/Dock.
  4. A forced problem: lift the robot → red card with sound; set it down + Resume → back to the job card.
  5. Airplane mode, then tap Stop → "Stopping…", then "Not confirmed" with the button back after about 20 s.
  6. Five jobs → the cap holds.
  8. Hot flash: start your side → Cooling, then the countdown, then Complete. Have the other person start your side → "by Resident B" on yours.
  9. A vacuum problem → card, no household push on your phones. Tap Done → the Choreapp task completes and the card ends.
  7. Watch Smart Stack.

## 13. Lanes and order

| Lane | Repo | Scope | Depends on |
|---|---|---|---|
| A, engine and relay (Sonnet) | `SFenton/ha-fenton-push` | §9, fixtures | this spec |
| B, app (Sonnet) | this repo | §11, §12; hand-written fixtures first | this spec (runs in parallel with A) |
| C, HA config (planner) | owner's `/config` | §10 | A deployed through HACS |

Merge order: B can merge first (v1 stays decodable). Deploy B to the phone. Then deploy A through HACS, run the device checks, then C. Review diffs A's generated fixtures against B's hand-written ones before either merges.

## 14. Owner answers (2026-10-17) and open questions

Answered:
1. Dishwasher finished → **Complete** for 5 minutes.
2. Washer → card only during the spin. No estimates for the washer or dryer → count-up; Complete for 5 minutes on the done signal.
3. (Dryer learner) → dropped.
4. Cards go to **everyone** with S+H.
5. Hot flash → yes (§4a). Not now: EV, grill, sprinklers.
6. Problem cards **replace** the household push for S+H people. They live until the Choreapp task completes, and have a Done button.

Round 5 (2026-10-17):
7. Problems with no task (low battery, error 75, unknown numbered, unmapped, dishwasher `actionrequired`/`error`) have **no Done**. They end when they clear. Unmapped cards carry no chips; unknown numbered errors keep only the "Error N" chip.
8. The second resident and S+H → **later**. The owner wants to use and develop it more first. Until then that resident keeps the Companion pushes, and the engine's per-person routing leaves them on push automatically.
9. Problem cards go to **everyone** in the household, home or not.

No open questions remain for v2.
