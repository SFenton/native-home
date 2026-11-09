# Live Activities (spec)

> **Superseded in part (2026-10-17):** one Live Activity **per job** replaces the single Home activity. [live-activities-per-job.md](live-activities-per-job.md) replaces §1 ("one activity, not many"), §3 (content state), §4 (presentation) and §6 (engine rules) here. §0, §2's token plumbing, §5's control map, §8's entity survey and §10 still apply.

> **What:** how Fenton Home shows running household jobs (dishwasher, fan timers, laundry and more) as one Live Activity on the Lock Screen, Dynamic Island, StandBy, Apple Watch, CarPlay and the Mac, kept current by Home Assistant over APNs while the app is closed. **Read when:** implementing or changing Live Activities, the widget extension, the `fenton_home` job engine, or their contract.

Status: spec (owner request, 2026-10-17). **Phase 1 (the pipe) is built** on `claude/live-activities-phase1` and `SFenton/ha-fenton-push#4`, and not yet checked on a phone; §0 holds what Phase 1 verified and decided, and where it departs from the text below. Phases 2 to 4 are not started. The current Apple SDK is iOS 27 / Xcode 27.1 and the deployment target is iOS 17.0. Home Assistant is 2026.10.1.

> **Superseded sketch.** The `set_live_job` / `clear_live_job` services in this spec (shown as `fenton_push.*`, the domain at the time) were a design sketch and never existed; the shipped design is [live-activities-per-job.md](live-activities-per-job.md). The integration is now the S+H Home Integration (domain `fenton_home`).

## 0. Phase 1: verified facts and decisions (2026-10-17)

**Verified** (evidence in each line; all reads, nothing mutated on the owner's Home Assistant):

| Question | Answer |
|---|---|
| (a) Does the installed `mobile_app` take and use the tokens as §1 says? | **Yes.** `GET /api/config` reports `2026.10.1` with `mobile_app` and `fenton_push` loaded. `home-assistant/core` at tag `2026.10.1`, `homeassistant/components/mobile_app/`: `const.py` `SCHEMA_APP_DATA` accepts `start_live_activity_token`; `live_activity/webhook.py` registers webhook commands `live_activity_token` (`{tag, push_token, expires_at}`, `expires_at` a positive number of Unix seconds) and `live_activity_dismissed` (`{tag}`); `live_activity/store.py` keeps one token per webhook id and tag and sweeps expired ones; `live_activity/__init__.py` `resolve_live_activity_push` picks the event from a `notify` call that has `data.tag`: `clear_notification` ends only when a stored, unexpired token exists; otherwise `data.live_update` starts with `app_data.start_live_activity_token` or updates with the stored token; with neither it returns nothing and `notify` sends an **ordinary** notification. Only registrations with `manufacturer == "Apple"` (ours) are routed (`notify.py`). `fire_event` stamps the registration's user (`registration_context`), which the button automations rely on. The post to `push_url` carries `live_activity_token` and `data.event`. |
| (b) What did `ha-fenton-push` do with them? | At `4dafdf2` `payload.py` `_live_activity` already mapped a post with `live_activity_token` to an `apns-push-type: liveactivity` request on the right topic, but with the type name `FentonActivityAttributes`, a flat `{message, title, progress…}` content-state the app has no type for, no `stale-date`, a `dismissal-date` that was always now, priority 10 for every update, and **no drop rule**: a `live_update` post for a device with no tokens fell through to the alert path and became a banner. PR #4 replaces that (contract v2, §7). The app did not send either token before Phase 1. |
| (c) Does `xcrun simctl push` deliver `liveactivity` payloads? | **No.** On Xcode 27.1 with the iOS 27.0 simulator, `simctl push <udid> com.sfenton.home update.json` for an `event: update` payload exits 121 with `UNErrorDomain 1401: Notification has no user visible content`; an `end` payload fails the same way. It parses the file as a remote notification and never reaches ActivityKit. So there is no push-driven simulator journey. The substitute is the debug hook `FENTON_LIVE_ACTIVITY_FIXTURE` (start, update, end through ActivityKit, locally), the gallery, and Python-generated fixtures decoded by the app's unit tests (`tools/push_fixtures/live-*.apns`). |
| (d) Does a push-started activity wake the app to hand over its token? | **Documented, not checkable without a device.** Apple's push guide says the system launches the app in the background when a push-to-start creates an activity, so it can read `Activity.activityUpdates` and `pushTokenUpdates`; `LiveActivityTokenReporter` follows every activity that appears, so it reports the token as soon as it is handed over. Device check below. |

**Decisions that depart from or settle the text below:**

1. **Attributes type is `HomeActivityAttributes`** (owner lane brief), not the `FentonActivityAttributes` the spec first proposed. The relay never started an activity before (no app could receive one), so no push-to-start token is orphaned. It lives in the SwiftPM target `FentonActivityModel` with the content state, ordering, pager and budget logic.
2. **No new app-side registration path was needed.** (a) and (b) held, so the design stands: the app adds `start_live_activity_token` to `app_data` (only next to the push details) and posts `live_activity_token` / `live_activity_dismissed` on its registration webhook. Turning Live Activities off in iOS Settings removes the start token from `app_data` (`activityEnablementUpdates`), so no per-app Settings switch is needed to gate registration; the in-app switch (open question 5) waits for Phase 2.
3. **Foreground derivation (departure from §6, "the app never derives jobs").** Phase 1 has no engine, so while the app is open `HomeJobDeriver` reads the dishwasher and bathroom fan timer entities through `EntityStore` and `HomeActivityDirector` starts, updates and ends the activity locally. It never starts from the disk snapshot (only once the store is live). When the Phase 2 engine and `sensor.fenton_live_jobs` exist the director must yield to them, so the activity has one writer.
4. **Buttons in Phase 1 are answered by an automation**, not the engine: the owner applies [live-activities-ha-automations.md](live-activities-ha-automations.md) (it also pushes start, update and end from Home Assistant while the app is closed). Nothing was applied to `/config`.
5. **Lock Screen rows: two compact rows, not three.** The limit is 160 pt and the focused job's line (pager and controls, 44 pt targets) takes 44 of it. One job shows the header ("Home · 1 running"), a glass row (title, status, bar) and its controls (about 138 pt). Several jobs show two compact rows (title and status on one line), the focus outlined, and the pager line, with no header (the pager already says "2 of 3", and the container reads "Home, 3 running" to VoiceOver): about 154 pt. A third and later job is reached with the pager. At accessibility text sizes one row shows, titles wrap and the header goes. Every scenario is asserted at 160 pt or less on iPhone, iPhone Duo and iPad by `LiveActivityJourneyTests`.
6. **Target and extension.** Widget extension target `FentonHomeWidgets` (`apple/Apps/Widgets`, bundle `com.sfenton.home.Widgets`, app group `group.com.sfenton.home`, team `3Q9X8JX23S`, `APPLICATION_EXTENSION_API_ONLY`), embedded in `FentonHome`; it links `FentonActivityModel` and `FentonActivityViews` (the views use `HassDesign` for the colour families) and nothing else. The intents file `apple/Apps/Shared/LiveActivityIntents.swift` is compiled into both. `NSSupportsLiveActivities` is set; `NSSupportsLiveActivitiesFrequentUpdates` is **not** (§6 rule 4). A tap opens `fentonhome://liveactivity?url=<dashboard path>` (`ActivityDeepLink`, scheme registered in the app's Info.plist) and `PushCoordinator.openLiveActivity` maps it like a notification's `url`.
7. **Where the code the coverage gate cannot see lives**, listed so the gate's numbers are honest: `apple/Apps/Widgets/*` (the `ActivityConfiguration`, island regions and `ActivityActions.intents`), `apple/Apps/Shared/LiveActivityIntents.swift`, `apple/Apps/iOS/SystemLiveActivityClient.swift` (ActivityKit translation only) and `apple/Apps/iOS/LiveActivityDebugLaunch.swift` (debug). They need ActivityKit or WidgetKit, which do not run on the macOS test host, and are thin: every decision is in `HassCore/LiveActivity`, `FentonActivityModel` and `FentonActivityViews`, which are gated.

**Device checks still needed** (the owner's phone; agents never touch it). Install the Phase 1 build from this branch and the relay from `SFenton/ha-fenton-push#4`, then:

1. **Foreground start.** Run a bathroom fan timer from the app (or the dishwasher). The Lock Screen and the Dynamic Island show the Home activity; `‹ ›` appear with two jobs; the countdown ticks; Cancel Timer works only after the automation in §3 of the automations file is applied (until then the press shows "Stopping…" and nothing changes).
2. **Start token reaches Home Assistant.** After launch, Developer Tools, States has no token (it is not an entity); check Settings, Devices & services, Mobile App, the phone's diagnostics for `start_live_activity_token` under `app_data`, or the integration log at debug level.
3. **Push-to-start while the app is closed** (this is also check (d)): swipe the app away, then Developer Tools, Actions, `notify.mobile_app_<device>_fenton` with `data: {tag: fenton-home, live_update: true, fenton_activity: {...}}` (a block from `tests/samples.py` `HOME_ACTIVITY` with future `end_ts`). The activity should appear within seconds. Then call it again with changed content: it should update without opening the app, which proves the app handed over the update token in the background. If the first call shows a banner instead, the start token is missing; if nothing shows, read Apple's Push Notifications Console for the `liveactivity` delivery log.
4. **End:** `notify.mobile_app_<device>_fenton` with `message: clear_notification` and `data: {tag: fenton-home}`.
5. **Buttons while the app is closed and the phone unlocked:** Stop and ‹ › from the Lock Screen (the system launches the app in the background; locked phones keep buttons inert).
6. **Apple Watch Smart Stack and CarPlay:** whether the `.small` family appears and whether buttons work there (spec §4 left this open).
7. **iPad Lock Screen:** the activity on an iPadOS 17+ iPad.

## 1. Answers in brief

- **Why not a background websocket on the phone.** iOS suspends an app a few seconds after it leaves the screen. A suspended app runs no code, and the system reclaims its sockets ([TN2277](https://developer.apple.com/library/archive/technotes/tn2277/_index.html), [extending background execution](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)).
  - `BGAppRefreshTask` runs when the system chooses, for about 30 s. Silent pushes are throttled to about 3 an hour ([choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)).
  - Keeping a socket alive with an unrelated background mode (audio, location) breaks App Review 2.5.4 and drains the battery.
  - The Live Activity's own views run sandboxed with no network ([displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)).
  - **The equivalent is server-side.** Home Assistant is always on, and every state change happens there. A new job engine in S+H Home Integration watches those changes and sends ActivityKit pushes through APNs. iOS applies them to the activity even when the app is terminated: push-to-start on iOS 17.2+, and update and end on any version.
- **Several jobs: one activity, not many.** The HIG says to follow several related events with a single Live Activity rather than one per event ([HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities), updated 2026-10-13).
  - Fenton Home runs one aggregate **Home activity** that lists every running job.
  - The Dynamic Island shows the *focus* job, which is the most urgent one.
  - A pager (‹ ›, App Intent buttons) changes the focus, and with it which job's controls show. That is the "carousel".
  - One activity also stays clear of the per-app limit. Apple gives no number for it, only the errors `targetMaximumExceeded` and `globalMaximumExceeded`; "5" comes from third parties. It leaves the other Dynamic Island slots (one attached plus up to two detached minimal views, HIG) for other apps, and spends the push-to-start budget, also undisclosed, once per run of jobs rather than once per job.
  - Automatic rotation is impossible. The views have no timers, animations run only on an update and last at most 2 s ([animating updates](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities)), and rotating by push would spend the update budget.
- **The plumbing already exists upstream.** Since 2026.7.0, Home Assistant's `mobile_app` stores the phone's push-to-start token (`app_data.start_live_activity_token`) and per-activity update tokens (webhooks `live_activity_token` and `live_activity_dismissed`, with expiry cleanup). It also routes `notify` calls carrying `data.live_update: true` + `tag` to start or update, and `clear_notification` to end ([core#172928](https://github.com/home-assistant/core/pull/172928), `homeassistant/components/mobile_app/live_activity/`).
  - S+H Home Integration's relay already turns those posts into `liveactivity` APNs requests (`payload.py` `_live_activity`). They use the topic `com.sfenton.home.push-type.liveactivity` and the attributes type `HomeActivityAttributes`.
  - The missing pieces are the app side, a typed content schema, and the job engine.

## 2. Architecture

```
 Home Assistant (always on)                                                  iPhone (app may be closed)
 ┌──────────────────────────────────────────────────────────────┐
 │ devices: Home Connect dishwasher, fan helpers, laundry       │
 │ helpers, valves, vacuum session, timers                      │
 │        │ state changes                                       │
 │        ▼                                                     │
 │ automations (/config/packages/fenton_live_activities.yaml)   │
 │   call fenton_push.set_live_job / clear_live_job             │
 │        ▼                                                     │
 │ fenton_home job engine (live_jobs.py, new)                   │
 │   jobs → per-person Home activity state, coalescing,         │
 │   priority, stale date, linger, 7.5 h restart                │
 │   ├─ sensor.fenton_live_jobs (same state) ───────── websocket (foreground) ──▶ app EntityStore
 │   └─ per device: notify.mobile_app_<device>_fenton           │
 │        {tag: fenton-home, live_update: true, fenton_activity}│
 │        ▼                                                     │
 │ mobile_app (core): picks start token or update token,        │◀── update_registration(start token), webhooks
 │   or end on clear_notification ─▶ POST push_url              │    live_activity_token / _dismissed (app)
 │        ▼                                                     │
 │ fenton_home relay (payload.py): APNs liveactivity request    │
 └────────┼─────────────────────────────────────────────────────┘
          ▼ api.push.apple.com (.p8 token auth, already configured)
   ActivityKit ─▶ Lock Screen · Dynamic Island · StandBy · Watch Smart Stack · CarPlay · Mac menu bar
          │ tap ‹ › or Stop → LiveActivityIntent (app process, launched in the background)
          ▼
   registration webhook fire_event fenton_live_activity_action ─▶ engine calls the job's service
   ─▶ device state changes ─▶ engine pushes the confirmed state
```

Rules:

- **Home Assistant is the only writer of job content.** It decides what a job is, when it starts or ends, and which controls apply.
- **The app writes to the activity locally in two cases only:**
  1. An optimistic state right after a button.
  2. A local start while the app is open, which uses no push-to-start budget and works on iOS 17.0 and 17.1.
- **The app never derives jobs from raw entities.** In the foreground it reads `sensor.fenton_live_jobs`, so there is one derivation and it lives in Home Assistant. This keeps the "Home Assistant is the source of truth" invariant.
- **Buttons go through Home Assistant**, like notification buttons ([push](push.md), contract §4).
  - The intent fires an event over the registration webhook, and the engine calls the service.
  - This departs from "one service call path (`HassConnection.callService`)", on purpose. A background intent then needs no websocket and no token refresh: just one HTTPS POST to the webhook it already holds. Home Assistant also checks the caller against the job's audience.

## 3. Activity model

One attributes type, `HomeActivityAttributes`. It is the name the relay already sends, and a push-to-start token is per type. It lives in a new dependency-free SwiftPM target, `FentonActivityModel`, which the widget extension links without HAKit.

| Static attribute | Type | Meaning |
|---|---|---|
| `tag` | String | `fenton-home` for the Home activity; an automation's own tag for a generic one |
| `title` | String | "Home" (generic: the automation's `title`) |
| `kind` | String | `home` or `generic` |

ContentState v1. These are the JSON keys in `aps.content-state`. Swift uses camelCase with `CodingKeys`.

```json
{"v": 1, "focus": "dishwasher", "url": "/sfenton-react-dash/home?path=kitchen",
 "jobs": [
  {"id": "dishwasher", "kind": "dishwasher", "title": "Dishwasher", "status": "Eco 50° · Drying",
   "phase": "running", "start_ts": 1792270800, "end_ts": 1792281360, "estimated": false,
   "progress": 0.62, "symbol": "dishwasher", "tint": "teal",
   "controls": [{"id": "stop", "title": "Stop", "role": "destructive"}]},
  {"id": "fan.master", "kind": "bathroom_fan", "title": "Primary Bath Fan", "status": "Off in",
   "phase": "running", "start_ts": 1792279000, "end_ts": 1792280800,
   "controls": [{"id": "cancel_timer", "title": "Cancel Timer"}]}
 ]}
```

- `phase` is one of `running`, `paused`, `waiting` (delayed start), `attention` (action required or error), `stopping` (optimistic), or `done` (shown for the linger time).
- `start_ts` and `end_ts` are **Unix seconds as numbers**. ActivityKit decodes push content with a default `JSONDecoder` and allows no custom strategies, so a Swift `Date` field would read the number as seconds since **2001**. Keep doubles on the wire and expose `Date` through computed properties.
- `estimated: true` (the dryer) shows "About …" and a clock time, never a seconds countdown.
- `progress` (0…1) is used only when the device reports it. A job with `start_ts` and `end_ts` draws its bar with `ProgressView(timerInterval:)` on its own.
- **Budget.** At most 6 jobs, `status` at most 40 characters, at most 2 controls per job, and no entity ids, people's names beyond the audience, or URLs with tokens. The 4 KB limit covers static and dynamic data together ([push guide](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)). The relay already refuses larger payloads.
- A generic `live_update` notify call (companion-app keys `message`, `progress`, `progress_max`, `chronometer`, `when`, `when_relative`, `notification_icon`, `url`) is mapped by the relay into one `generic` job. Existing automations written for the companion app therefore show something sensible.

## 4. Presentation

HIG: [Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities). Sizes below are from that page.

| Surface | Content |
|---|---|
| Lock Screen (84–160 pt tall, 14 pt margins, `ContainerRelativeShape` corners) | Header "Home · 1 running" for a single job. Two compact job rows when there is a control line, else up to 3 (§0, decision 5): symbol, title, status, and a trailing `Text(timerInterval:)` (monospaced digits) or a percentage, with a thin bar under each row. No header and no footer with several jobs (§0, decision 5). One control row for the **focus** job only (HIG: one or two essential controls), with ‹ › paging when there are 2 or more jobs |
| Island compact | Leading: focus job symbol in its tint, with a count dot when there are 2 or more jobs. Trailing: the focus countdown (`Text(timerInterval:)`, fixed width) or a percentage. "Done" with a checkmark during linger |
| Island minimal | Focus symbol inside a ring (`ProgressView(timerInterval:)`, circular). In limited width it must fit a 28 pt circle |
| Limited width (iPhone Duo, iOS 27 landscape island, two or more activities on iPhone 18 Pro) | Read `isDynamicIslandLimitedInWidth` (iOS 27 SDK, behind `#available`). Show leading only; the system hides trailing. This is geometric, like `SplitPolicy`, and never a device-name check |
| Island expanded | Leading: symbol and title. Trailing: large countdown. Center: status. Bottom: bar, up to 2 controls and the ‹ n of N › pager. `.dynamicIsland(verticalPlacement: .belowIfTooWide)` |
| StandBy (iOS 17) | The Lock Screen layout scaled 2x. Drop the header when `isActivityFullscreen`. Semantic colours only, so Night Mode's red tint reads |
| Always-On, `isLuminanceReduced` | Hide bars, keep the countdown, and dim tints |
| Apple Watch Smart Stack (watchOS 11 / iOS 18) | Automatic from compact. Add `.supplementalActivityFamilies([.small])` (iOS 18, `#available`), where `.small` shows the focus job, its countdown and "+N". Controls on the watch are unverified, so Phase 1 checks them |
| CarPlay (iOS 26) | `.small` family. Buttons do nothing there, so hide controls in `.small` until the watch check says otherwise. Tapping opens nothing, because the app has no CarPlay scene |
| Mac menu bar (macOS 26 via iPhone Mirroring) | Automatic. Nothing to build ([WWDC25 278](https://developer.apple.com/videos/play/wwdc2025/278/)) |
| iPad (iPadOS 17+) | Lock Screen (425 or 500 × 84–160 pt) and banners; there is no Dynamic Island. Apple says "available on iPhone and iPad" (displaying live data; WWDC23 [10184](https://developer.apple.com/videos/play/wwdc2023/10184/)), so the companion-app docs' "not on iPad" is out of date. Gate on `areActivitiesEnabled` |

- **Taps.** `widgetURL` on Lock Screen, compact and minimal opens the focus job's page (`url`, read by `PushLink` like notification links). The expanded view uses `Link` per row.
- **Accessibility.** Each row is one element: "Dishwasher, Eco 50, drying, 42 minutes left". Controls read "Stop Dishwasher" and "Cancel Primary Bath Fan Timer". The pager reads "Next job, 2 of 3". Test at AX5.
- **Visual language.** Direction G tints come from `ColorFamily` by `tint` name, with symbols from `SymbolMap`. The Dynamic Island background is always black (`keylineTint` only).

## 5. Controls and intents

These intents run in the **app process**. The system launches the app in the background ([LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent), iOS 17). Buttons are inert until the phone is unlocked. The source file lives in `apple/Apps/Shared/LiveActivityIntents.swift`, compiled into both the app and the widget extension. The logic lives in `HassCore/LiveActivity`.

| Intent | Does |
|---|---|
| `JobControlIntent(tag, job, control)` | 1. Sets the job to `phase: stopping` and hides its controls (local `Activity.update`). 2. Sends the registration webhook `fire_event` `fenton_live_activity_action {tag, job, control}` with a 10 s timeout. 3. On failure, restores the controls and shows "Couldn't reach Home" |
| `FocusJobIntent(tag, job)` | Sets `focus` locally right away, then sends `fenton_live_activity_focus {tag, job}` so the engine keeps that focus for this device in later pushes |

The engine maps controls to services. The map is stored in Home Assistant and never sent to the phone. It checks that the job still offers the control and that the event's user is in the job's audience, calls the service, and then pushes the real state, which also reverts a failed optimistic state.

| Job | Control | Service (verified entities, 2026-10-17) |
|---|---|---|
| Dishwasher (Home Connect) | Stop | `button.press` → `button.demo_ext_24` (while `run`, `pause`, `delayedstart`; needs `binary_sensor.demo_ext_23` on) |
| Dishwasher | Resume | `button.press` → `button.demo_ext_25` (only while `pause`) |
| Dishwasher | Pause | **Not offered.** Home Connect exposes no pause button for this model |
| Bathroom fan timer | Cancel Timer | `script.<room>_bathroom_fan_command {command: timer_cancel}`, the same as `BathroomFanController.cancelTimer`. The fan keeps running (open question 2) |
| Washer, dryer | none | Owner, 2026-10-17 |

## 6. Triggers

**Background (server, the normal path).** Automations in a package file call:

```yaml
action: fenton_push.set_live_job      # upsert by job id
data:
  job: dishwasher
  kind: dishwasher
  title: Dishwasher
  status: "{{ program }} · {{ phase_label }}"
  phase: running
  ends_at: "{{ states('sensor.demo_ext_21') }}"
  progress: "{{ states('sensor.demo_program_1') | float(0) / 100 }}"
  people: all                          # or [<resident>] for a personal job
  url: /sfenton-react-dash/home?path=kitchen
  controls:
    - {id: stop, title: Stop, role: destructive, action: button.press, target: {entity_id: button.demo_ext_24}}
```

`fenton_push.clear_live_job {job, linger: 15}` ends a job. It shows "Done" for `linger` minutes (HIG suggests 15–30), then leaves the list.

Engine rules:

1. **Composition.** For each person, the list holds the jobs whose audience includes them, ordered by urgency (attention, then soonest `end_ts`). The focus is the device's chosen job if it is still listed, otherwise the first.
2. **Fan-out.** For every Fenton registration of that person whose `app_data` has `start_live_activity_token`, the engine calls `notify.mobile_app_<device>_fenton` with `message` (the focus summary), `data: {tag: fenton-home, live_update: true, fenton_activity: {...}}`. Core sends a start when the device has no live token and an update otherwise. When the list becomes empty after the linger, the engine sends `message: clear_notification` with the tag, which is the end.
3. **Coalescing.** The engine pushes on any of these:
   - a job is added or removed;
   - a phase changes;
   - the controls change;
   - `end_ts` moves by more than 60 s;
   - progress moves by 5 points or more, at most once per 5 minutes per job;
   - the focus changes.
4. **Priority.** 10 for a start, an end, a job finishing that needs action (dishwasher clean, dryer done), and control confirmations. 5 (`silent: true`) for everything else.
   - Pushes at priority 10 count against an undisclosed budget; pushes at priority 5 don't count but may be delayed ([push guide](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)).
   - Don't set `NSSupportsLiveActivitiesFrequentUpdates` until throttling is actually seen.
5. **Alerts.** A push-to-start must carry an `alert`, so it carries a quiet one ("Dishwasher started", no sound). Updates alert only when a job finishes and needs someone. The HIG says not to also send a regular notification for the same event (open question 3).
6. **Stale date.** The stale date is the earliest `end_ts` + 10 min. A list with no end times gets now + 30 min, and the engine re-pushes the same state every 25 min at priority 5. A stale view shows "Updating…".
7. **The 8-hour limit.** The system ends an activity after 8 h and keeps it on the Lock Screen up to 4 h more ([displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)). The app reports `expires_at` = start + 8 h. At 7.5 h the engine ends the activity and starts a fresh one.
8. **Dismissal by the person.** The app sends `live_activity_dismissed` (core drops the token) and `fenton_live_activity_dismissed {tag, jobs}`. The engine won't start the activity again on that device until a *new* job id joins the list.
9. **`sensor.fenton_live_jobs`** carries the per-person lists as attributes (`by_person`) for the foreground app and for debugging.

**Foreground (app open).**

- `LiveActivityCoordinator` reads `sensor.fenton_live_jobs` from `EntityStore`. If the signed-in person has jobs, the user allows activities, and no Home activity exists, it calls `Activity.request(attributes:content:pushType: .token)` with the sensor's state. The engine updates it from then on.
- It never updates content from the sensor itself, because then two writers would race. The push `timestamp` orders updates.
- With S+H Home Integration missing (404) or without the engine, there is no Home activity. Generic `live_update` notify calls still work once Phase 1 lands.

**Token registration (app).**

- On launch, every token change and every enablement change (`activityEnablementUpdates`), on iOS 17.2+, the app adds `start_live_activity_token` (lowercase hex of `Activity<HomeActivityAttributes>.pushToStartToken`) to `app_data`, or removes it. That token is accepted by core's `SCHEMA_APP_DATA`. Sign-out already sends `app_data: {}`.
- For each activity, it watches `Activity.activityUpdates`, which includes activities started by push, and their `pushTokenUpdates`. It then sends the webhook `{"type": "live_activity_token", "data": {"tag": …, "push_token": …, "expires_at": start + 8 h}}`.
- The start relaunches the app in the background to collect the token (push guide; verified on a device in §0, check 3). Push-to-start pushes carry `input-push-token: 1` (iOS 18) to ask for it.

## 7. Server changes (`SFenton/ha-fenton-push`, read-only here; a later lane opens its PR)

- **`payload.py` `_live_activity` (contract v2, add CONTRACT.md §6):**
  - `content-state` is the validated `fenton_activity` block, or the companion keys mapped to one `generic` job.
  - `attributes: {tag, title, kind}`.
  - On start: a quiet alert and `input-push-token: 1`.
  - `stale-date` from the block.
  - On end, `dismissal-date` = now + `dismiss_after` (default now). Today it is always now.
  - Priority: 10 for start, end, alert and `urgent`; otherwise 5.
  - **A `live_update` body without `live_activity_token` is dropped, answering 201 and logging a note**, so a device that can't show activities never gets a stray banner. Core falls back to a normal notify in that case.
- **`live_jobs.py`** (new):
  - the services `set_live_job` and `clear_live_job` (`services.yaml`);
  - the store of jobs and per-device focus (`helpers.storage`, so it survives restarts);
  - the composer, coalescer and fan-out (through core notify, so core keeps owning tokens);
  - listeners for the three `fenton_live_activity_*` events (the user comes from the event context; the control map is enforced as in §5);
  - the 7.5 h restart;
  - `sensor.fenton_live_jobs`.
- **Tests and fixtures.**
  - Unit tests for the mapping and the composer.
  - HA tests through `mobile_app` with a stored token.
  - `tests/fixtures/live-*.apns` (start, update, end, generic), mirrored into `tools/push_fixtures/` so the app decodes Python's real output.
- The daily cap of 1,000 pushes per device stays. Coalescing keeps a 3-hour dishwasher cycle under about 40 pushes.

## 8. Home Assistant side (owner's `/config`; a later HA lane, with the owner's approval and a backup)

Entities read on 2026-10-17 (GET `/api/states`):

| Job | Entities | Notes |
|---|---|---|
| Dishwasher (appliance integration) | `sensor.demo_state_2` (`inactive ready delayedstart run pause actionrequired finished error aborting`), `sensor.demo_ext_21` (timestamp), `sensor.demo_program_1` (%), `select.demo_ext_22`, `sensor.demo_door_1`, `button.demo_ext_24`, `button.demo_ext_25`, `binary_sensor.demo_ext_23` | Cycles in the last 10 days: `run` 176–188 min, then `finished` for 10 min, then `ready`. The finish time gives an exact countdown. Map the program slug to a label in the automation ("Eco 50°") |
| Bathroom fan timers (guest, primary) | `input_boolean.<room>_bathroom_fan_timer_pending`, `input_datetime.<room>_bathroom_fan_timer_ends_at` (`timestamp` attribute), `timer.<room>_bathroom_fan_off_timer`, `script.<room>_bathroom_fan_command` | A job only while pending (5–60 min). Humidity auto-runs have no timer and are not jobs |
| Dryer | `binary_sensor.demo_ext_35` → `input_boolean.demo_input_boolean_7` (on after 5 min of vibration, off after 5 min still) | On spells of 6–47 min (median about 36) over 9 runs. Usable for an estimate |
| Washer | `binary_sensor.demo_ext_36` → `input_boolean.demo_input_boolean_6` | On spells of only 5–9 min: the sensor catches the spin at the end of the cycle, so **it can't tell when a wash started** |

**Laundry ETA proposal.** This is an HA task for Phase 3.

- **Dryer.** Use a trigger-based template sensor, `sensor.demo_ext_37`, which on each on→off appends the run's duration to a list of the last 10 runs kept in its attributes. Its state is their median. The recorder here keeps only about 10 days, so the learning can't rely on history queries.
  - `sensor.demo_ext_38` = the helper's on time − 5 min + the median.
  - The job is `estimated: true`, shown as "About 20 min · done around 3:40 PM".
  - At the estimate, it switches to "Finishing…" until the helper turns off.
- **Washer.** Add a power-monitoring plug, with a running threshold of about 5 W held for 2 min, then use the same learner. Alternatively, lower the vibration sensor's sensitivity or cool-down and re-measure. Until then the washer job starts only at the spin ("Spinning · finishing soon"), or is left out (open question 4).

**Other candidates found** (Phase 3, each a `set_live_job` automation):

| Job | Entities |
|---|---|
| Hot flash, per person | `timer.demo_bed_<person>_hot_flash` and `timer.demo_bed_hot_flash_{left,right}` (15 min, `finishes_at`); cancel with `input_button.demo_bed_<person>_cancel_hot_flash` |
| Sprinkler run | `valve.*_zone` open, end from the program `run_times` or `manual_preset_runtime`; stop as in `SprinklerController` |
| Vacuum session | `sensor.<floor>_vacuum_coordinator_session_state` (`active_room`, `completed_rooms`, `requested_iterations`) and `sensor.<floor>_vacuum_status`; progress is rooms done out of rooms requested |
| Wake-light ramp | `sensor.demo_bedroom_1_light_1` (`next_wake_at`, `next_ramp_minutes`, `progress`) |
| Grill cook timer | `sensor.demo_ext_39` and probe temperatures |
| Assist timers | `mobile_app` timer events |

Not candidates:

- Garage door travel lasts seconds.
- Humidifier schedules are schedules, not tasks.
- Landscaper timers are internal.

## 9. App changes

| Piece | Where |
|---|---|
| Widget extension `FentonHomeWidgets` | `apple/Apps/Widgets/`. Bundle `com.sfenton.home.Widgets`, extension point `com.apple.widgetkit-extension`, a `WidgetBundle` with `ActivityConfiguration(for: HomeActivityAttributes.self)`, iOS 17.0, team 3Q9X8JX23S automatic signing, embedded as a dependency of `FentonHome`. No network and no Keychain. It can host Home Screen widgets and Controls later |
| App `Info.plist` | `NSSupportsLiveActivities: true`. `remote-notification` is already present. The topic uses the app's existing `aps-environment` |
| Model | New SwiftPM target `FentonActivityModel` (attributes, ContentState, job ordering, formatting), which HassCore depends on |
| Views | New target `FentonActivityViews` (model + HassDesign), linked by the extension and by the app's debug gallery `FENTON_GALLERY=live-activity` |
| Logic | `HassCore/LiveActivity/`: token registrar, webhook bodies, intent logic, and an `ActivityClient` protocol over ActivityKit so tests can fake it |
| Wiring | `HassUI/App/LiveActivity/LiveActivityCoordinator.swift`: started with the session, it observes activities and tokens, does the foreground local start, and is cleared on sign-out |
| Registration | `PushAppData` gains `start_live_activity_token`. `MobileAppRegistrar` sends the two core webhooks and the three events |

## 10. Privacy and security

- **What the Lock Screen shows.** Lock Screen content is visible without unlocking, so jobs carry household labels only. Personal jobs (hot flash) go only to their person. Payloads never carry tokens, passwords, entity ids or webhook ids.
- **Tokens.**
  - Push tokens live in Home Assistant: `mobile_app` config entries and storage. The relay logs device names, never tokens.
  - The app keeps no new secrets. Intents use the registration webhook already in the Keychain, readable after first unlock.
- **Who can act.** Controls are honoured only for listed controls and for users in the job's audience, checked server-side. Buttons are inert while the phone is locked.

## 11. Testing

- **Python** (ha-fenton-push CI): mapping, composer, coalescing, the control map, and fixtures.
- **Swift unit tests** (95% logic bar):
  - ContentState decoding of the Python fixtures, including the 1970 versus 2001 date trap;
  - ordering, focus and formatting;
  - registrar bodies;
  - intent logic against a fake `ActivityClient` and `StubHTTPTransport`.
- **Journeys and accessibility, on iPhone, iPhone Duo and iPad** (`tools/ios_uitest.sh`, inside `tools/devcap.py` holds, existing simulators only):
  - The gallery renders every surface's view with fixtures (1, 3 and 7 jobs; done; stale; limited width; AX5). Audits cover labels, 44 pt targets and reading order.
  - A debug hook, `FENTON_LIVE_ACTIVITY=<base64 fixture>`, starts a real activity locally. The journey locks the simulator and reads it through SpringBoard.
- **Simulator push.** Whether `xcrun simctl push` accepts `liveactivity` payloads is **unverified**: `simctl help push` on Xcode 27.1 says only "application remote push". Phase 1 tries `simctl push <udid> com.sfenton.home.push-type.liveactivity live-update.json`. If that fails, the debug hook `FENTON_LIVE_ACTIVITY_PUSH` applies the same payload through ActivityKit.
- **The owner's phone, real APNs.** The owner runs the Phase 1 checks:
  1. push-to-start from Developer Tools → Actions (`notify.mobile_app_<device>_fenton` with `live_update`);
  2. a background token callback;
  3. button intents while the app is closed;
  4. Watch and CarPlay controls;
  5. the Lock Screen on the iPad.

  Apple's [Push Notifications Console](https://icloud.developer.apple.com/dashboard) shows delivery logs. Agents never touch the owner's phone.

## 12. Phased plan

| Phase | Scope | Lane, files |
|---|---|---|
| 1. Pipe | Extension, model and views for one `generic` job; token registration; the relay's v2 mapping and drop rule; the verification spikes in §11 | App lane (Sonnet): `apple/Apps/Widgets/**`, `apple/Apps/Shared/**`, `apple/Sources/FentonActivity*/**`, `apple/Sources/HassCore/LiveActivity/**`, its tests and the gallery. Orchestrator: `project.yml`, `Package.swift`, `HassUI/App/LiveActivity`, `PushAppData` and `MobileAppRegistrar`. Server lane: ha-fenton-push `payload.py`, CONTRACT §6 and fixtures |
| 2. Home activity | Engine, `sensor.fenton_live_jobs`, the aggregate views, pager and control intents, the foreground local start, dishwasher and both fan timers | Server lane: `live_jobs.py` and `services.yaml`. HA lane (owner approval, `ssh hass`, backup first): `/config/packages/fenton_live_activities.yaml`. App lane as above |
| 3. More jobs | Dryer ETA learner; washer once power sensing exists; hot flash, sprinklers, vacuum, wake ramp, grill, Assist timers | HA lane plus small app additions (symbols, tints) |
| 4. Polish | Watch `.small` controls, CarPlay check, frequent-updates key if throttled, iOS 18 broadcast channel evaluation (one channel for household-wide content; rejected for v1 because focus and audience differ per device) | Both |

## 13. Open questions for the owner

1. Who sees which job? The proposal: household jobs (dishwasher, laundry, fans) for everyone signed in, and personal jobs (hot flash) for their person. Should people away from home also see household jobs?
2. Should the fan control be **Cancel Timer** (the fan keeps running) or **Turn Off** (power off, which also clears the timer)? Or both, as two buttons?
3. While the activity runs, should the existing finish notifications ("Dryer · Finished", "Dishwasher clean") stop, as the HIG advises, with the finish alert moving into the activity?
4. Washer: is adding a power-monitoring plug acceptable? Or should the washer job wait, or start at the spin only?
5. Should a "Show Live Activities" switch be added in Settings (under the Account sheet with notification settings), on top of the iOS per-app switch?
6. Should the iPad show the Home activity too (iPadOS supports it on the Lock Screen), or only phones? The proposal is phones and iPads both.
7. How long should a finished job linger: 15 min (proposal), or until its door opens (dishwasher `sensor.demo_door_1` → `open`)?

## Sources

Read 2026-10-17.

- Apple:
  - [Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
  - [push guide](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
  - [custom views](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities)
  - [launching from an activity](https://developer.apple.com/documentation/activitykit/launching-your-app-from-a-live-activity)
  - [interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
  - [ActivityAuthorizationError](https://developer.apple.com/documentation/activitykit/activityauthorizationerror)
  - [broadcast](https://developer.apple.com/documentation/usernotifications/sending-broadcast-push-notification-requests-to-apns)
- WWDC sessions:
  - WWDC23 [10184 Meet ActivityKit](https://developer.apple.com/videos/play/wwdc2023/10184/)
  - WWDC23 [10185 Update Live Activities with push notifications](https://developer.apple.com/videos/play/wwdc2023/10185/)
  - WWDC24 [10069 Broadcast updates](https://developer.apple.com/videos/play/wwdc2024/10069/)
  - WWDC24 [10068 Live Activity on Apple Watch](https://developer.apple.com/videos/play/wwdc2024/10068/)
  - WWDC25 [278 What's new in widgets](https://developer.apple.com/videos/play/wwdc2025/278/) (CarPlay, Mac)
  - WWDC26 [223 Live Activities essentials](https://developer.apple.com/videos/play/wwdc2026/223/) (iOS 27 landscape island, limited width)
- Home Assistant:
  - `home-assistant/core` `mobile_app/live_activity/` (since 2026.7.0)
  - companion docs `docs/notifications/live-activities.md` ([companion.home-assistant#1303](https://github.com/home-assistant/companion.home-assistant/pull/1303))
  - the companion app's `HALiveActivityAttributes` (home-assistant/iOS)
  - `SFenton/ha-fenton-push@4dafdf2` `custom_components/fenton_push/payload.py`
