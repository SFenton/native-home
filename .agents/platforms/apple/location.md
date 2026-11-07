# Location and device sensors

> **What:** how the app reports location and device sensors to Home Assistant through `mobile_app`. **Read when:** touching `HassCore/MobileApp`, `HassCore/Location` or the location permission screen.

Plan and rationale: the owner's "Location, Home/Away and device sensors" report (2026-10-14), and the 2026-10-20 report that made reporting unconditional and added the person link.

## Shape

| Piece | Where | Role |
|---|---|---|
| `MobileAppWebhookClient` | `HassCore/MobileApp` | `update_location`, `register_sensor`, `update_sensor_states`, `get_zones` to `/api/webhook/<id>`; 410 → `.registrationGone` |
| `MobileAppWebhookSource` | same | Supplies the current webhook: the shared registration store ([mobile-app](mobile-app.md)) |
| `LocationReport`, `HAZone`, `ZonePlanner`, `ZoneEventResolver`, `ZoneEntryFuzzer`, `LocationFixFilter`, `LocationTrigger` | same | Pure reporting rules (below) |
| `OneShotFix`, `OneShotSelector` | `HassCore/Location` | Grades and chooses one-shot fixes; per-trigger timeouts |
| `MobileAppSensor`, `MobileAppSensorProvider`s, `DeviceStatus` | same | Sensors from one device reading |
| `SensorReporter`, `DeviceStatusSource`, `SensorContext` | same | Registers the sensors, sends what changed with each update, skips what did not (below) |
| `SystemDeviceStatusSource` | `HassUI/App/Location`, iOS only | Reads battery, network and Wi-Fi, audio route, Focus, app version and the geocode |
| `LocationReporter` | `HassCore/Location` | Drives permission, zones, significant changes and fixes over the `LocationPlatform` seam |
| `CoreLocationPlatform` | same, iOS only | `CLLocationManager` + iOS 17 `CLMonitor` |
| `BackgroundRefresh` (+ `BackgroundRefreshScheduler`, `BackgroundRefreshTask`) | `HassCore/Location` | Background App Refresh rules: schedule +15 min, run, expire, complete once |
| `SystemBackgroundRefresh` | `HassUI/App/Location`, iOS only | `BGTaskScheduler` glue |
| `LocationPermissionView` | `HassUI/Features/Location` | The explainer and permission steps ([page](../../pages/settings/location.md)) |
| `LocationCoordinator`, `LocationLaunchPolicy`, `LocationPermissionPresenter` | `HassUI/App/Location` | Starts and stops the reporter with the registration and permission; says when the Setup flow's location step has something to ask; foreground fixes |
| `SetupFlow`, `SetupCoordinator`, `SetupPresenter` | `HassUI/App/Setup` | The after-sign-in Setup flow that presents the location screen as its last step (below) |
| `PresenceLinker`, `PresenceLinkOutcome`, `HassCommandSending` | `HassCore/MobileApp` | Adds this phone's tracker to the signed-in user's person (below) |

One `mobile_app` registration per phone, shared with push ([mobile-app](mobile-app.md)), so each phone is one Home Assistant device. Webhook calls carry no token (the id addresses the registration) and never use the websocket: they are one-off exchanges, not entity state.

## Rules

- **Permission:** While Using the App first, then the upgrade to Always, with Precise Location. Background reporting (zones, significant changes) needs Always and Precise; While Using sends a fix on app open only.
- **Zones:** at most 20 regions (iOS limit), counting every circle. `zone.home` always; passive zones never; the rest nearest to the last fix by distance to their edge (a relaunch with no fix yet uses Core Location's cached position); whole zones are dropped, farthest first. A zone of 100 m or more is one region. A zone under 100 m is three 100 m circles whose centers sit `100 - radius` meters from the zone's center at 0°, 120° and 240°, ids `<zone>@000`, `@120`, `@240`: each contains the whole zone, so leaving any one is leaving the zone. Zone events carry the circle's id; the reporter strips `@…` to find the zone. Conditions are added `assuming: .unsatisfied`, so the first evaluation reports only the zone the phone is in, never a burst of exits.
- **Background relaunch:** `start()` marks the reporter running, starts significant changes and opens the `CLMonitor` (`LocationPlatform.openZoneMonitor`) before any network call, then plans regions from the zones cached by the last good `get_zones` (`ZoneStore`, `UserDefaults`). `refreshZones()` fetches afterwards and re-plans; a failure keeps the cache. Zone events and significant changes each hold background time (`BackgroundTime`; `UIKitBackgroundTime` in `HassUI` wraps `beginBackgroundTask`) from receipt until the send finishes or fails.
- **One-shot fixes (`OneShotFix`):** `currentFix(timeout:)` runs its own `CLLocationManager` (`startUpdatingLocation` at Best, `allowsBackgroundLocationUpdates`) and also considers the cached reading. Grades: perfect (within 100 m and 30 s old) answers at once; invalid (over 600 s old, over 1500 m, or at 0,0) is never used; anything else is meh, and at the timeout the best meh reading answers (one more than 60 s newer wins, else the more accurate); only invalid readings throw. Approximate Location widens perfect to 3 km and never invalidates on accuracy. Timeouts: region crossing 20 s; significant change, push and background fetch 10 s; launch and manual 30 s; never more than `max(background time left - 5, 1)` s.
- **Significant changes:** a prompt to look, not a position. Ignored when an update succeeded under 30 s ago or the reading is over 180 s old; otherwise a fresh one-shot fix is taken and sent (if none arrives the reading itself is sent, unless it grades invalid). The significant-change manager sets `allowsBackgroundLocationUpdates` and `pausesLocationUpdatesAutomatically = false`, as the official app does.
- **Triggers outside the app (2026-10-29):**
  - **Push:** `request_location_update` ([push](push.md#payload-contract-rule-3)) takes a one-shot fix (10 s) and sends it with trigger `Push Notification` (`LocationCoordinator.handleLocationRequest()`, `LocationReporter.requestUpdate`), holding background time. Needs Always + Precise in the background; While Using is enough in the foreground.
  - **Background App Refresh:** a `BGAppRefreshTask` (`com.sfenton.home.backgroundfetch`; `BGTaskSchedulerPermittedIdentifiers` and the `fetch` background mode in `project.yml`), registered in `didFinishLaunching` before launch finishes, requested for +15 min at launch, when the app enters the background and inside every run (`BackgroundRefresh`, `SystemBackgroundRefresh`). Each run sends a fix with trigger `Background Fetch` (10 s) when location is allowed in the app's state; otherwise it runs `LocationCoordinator.sendSensorsOnly` (`LocationReporter.updateSensorsOnly`: the sensors alone, trigger `Background Fetch`, needing only a webhook). The expiration handler cancels the work and completes the task as failed; `setTaskCompleted` is called exactly once. iOS decides when it runs (typically a few times a day, never after a force quit or with Background App Refresh off). The simulator refuses the requests.
  - **Launch:** one update per foreground session, as the official `LifecycleManager` does: armed at startup and each time the app enters the background (`LocationCoordinator.didEnterBackground`), sent on the first activation after. Reactivating inside a session (a system alert, the app switcher) sends nothing, and a background relaunch (zone event, push, refresh) sends none until the person opens the app.
- **Sensors with every update (2026-10-29, PR C):** see *Sensors* below. Every `update_location` that passes the filter starts `SensorReporter.update` at the same moment, with the same trigger and the fix's geocode; the two run in parallel and the background time hold covers both. A background fetch that cannot take a fix sends the sensors alone.
- **After an exit with no fresh fix:** the zone-center `not_home` stands until a reading taken after the crossing has been sent. Until then every other report (launch, push, background fetch, significant change) asks for readings no older than the exit's receipt time (`notBefore`) and ignores older ones, so a cached reading from before the crossing cannot put the person back home. An entry or `stop()` ends the restriction. The check is made when the fix is about to be sent (`attemptSend`), not when it was requested: a request that was waiting for its fix when an exit fell back to the zone's center cannot then send a reading from before the crossing.
- **A relaunch for a push or a refresh** takes background time first, starts the reporter without the network (zone monitor, significant changes, cached zones) and takes the fix; `get_zones` runs afterwards, inside the same hold (`start(deferZoneRefresh:)`, `refreshPendingZones()`).
- **Zone result:** iOS's crossing is the news, the fix only checks it. Enter with a fix: the fix, no `location_name` (as in the official app; Home Assistant places it), its accuracy widened by `ZoneEntryFuzzer` when iOS says inside and the fix is up to 100 m outside the circle (by the shortfall plus 1 m), or when it is inside every circle of a small zone but outside the zone (by the shortfall plus 1 m); the coordinate is never moved. Enter with no fix: the zone's center at its radius' accuracy, named. Exit with a fix: `not_home` unless the position lies inside a non-passive zone (then no name). Exit with no fix: the exited zone's center, accuracy the exited circle's radius, `not_home`, unless another monitored non-passive zone is satisfied (then nothing). Why: a missing exit left the person "home" for hours, and an accuracy circle touching a zone must not veto a departure iOS already reported. A region no zone owns is ignored.
- **Event order and freshness:** zone events are handled one at a time in arrival order (leaving a small zone crosses two circles together; the second must see whether the first was reported). An exit is answered only by a reading taken after the crossing was received (`currentFix(timeout:notBefore:)`; a cached one from before it would still be inside the zone). When there is no such reading, or the filter refuses the exit's fix, the zone-center `not_home` fallback is sent. `kCLErrorLocationUnknown` does not end a one-shot (the timeout decides). The first state a newly added circle reports within 10 s of the add is ignored, with its `fire_event` (the official `ignoreNextState`; `NewRegionGuard`), because it only says where the phone already is.
- **Repeat exits:** after an exit of one circle of a small zone is sent with the fix outside the zone, an exit of another circle of the same zone within 5 minutes is ignored (the same departure); an entry re-arms. The made-up fix of an exit with no reading stays out of the filter's history and the nearest-zone reference (its timestamp is the clock's, and a real reading taken just before it would look out of order).
- **Zone events:** each crossing of a known zone also fires `ios.zone_entered` / `ios.zone_exited` (`fire_event`) with `zone` (entity id), `multi_region_zone_id` (the circle's degrees, small zones only) and `sourceDevicePermanentID`, `sourceDeviceName`, `sourceDeviceID` (the vendor id stands in for the permanent id), after the location update. Best effort: only a gone registration is an error.
- **Filter:** drop invalid fixes; drop a fix older than the last one admitted; drop a non-manual fix older than 10 minutes against the clock; drop a fix within 10 m and 30 s of the last one sent unless the trigger is Manual or a zone crossing. Accuracy is the grade's job (above), not the filter's. A fix that fails to send never becomes the duplicate reference.
- **Body:** whole numbers; leave out anything Core Location marks invalid (negative speed, course, accuracies). Altitude below sea level is valid; it is left out only when vertical accuracy is negative.
- **Failures:** 410 or no webhook stops reporting until the phone registers again; other errors keep it running and show in `lastError`.
- **iPad (owner, 2026-10-27):** every iOS device opts in to location, an iPad too. An iPad reports to its own `device_tracker` but is never linked to the signed-in person (`LocationReporter.linksPresence(isPad:)`, `LocationCoordinator.linksPresence`): an iPad left at home and tied to a person would mark them home. See *The iPad rule* below.

## Sensors

Source: `home-assistant/iOS` @ `cb064d4e` (`HomeAssistantAPI.UpdateSensors`, `registerSensors`, `WebhookResponseUpdateSensors`, `Sensors/*`).

- **Registration first.** The first sensor update for a registration (webhook id) and app version sends `register_sensor` for every sensor with its state (`SensorReporter`; remembered in `UserDefaults` `mobileapp.sensors.registered` as `<webhook id>|<version>`). A new registration, a 410 (the key is dropped) or a new app version registers again. A sensor answered `not_registered` by `update_sensor_states` is registered on the spot with its current state.
- **Unchanged payloads are skipped,** per sensor, against what Home Assistant last accepted; a failed request or a per-sensor error is not remembered, so the next update carries it. A sensor Home Assistant reports `is_disabled` is left alone until the next Launch update. Nothing is sent when nothing changed.
- **Same trigger, same fix.** The reporter starts the sensors beside `update_location` with its trigger and the fix just taken; the geocode is of that fix (a made-up zone-center fix is not geocoded, and a sensors-only update has none). The "Zones" attribute lists the non-passive zones the fix is in, smallest first. Sensor work runs on the `SensorReporter` actor and the HTTP transport, never the main thread; the geocode and Wi-Fi lookup are in `SystemDeviceStatusSource` and the geocode gives up after 10 s.
- **Last Update Trigger** is the trigger of the update being sent, on every update: `Launch`, `Geographic Region Entered`, `Geographic Region Exited`, `Significant Location Change`, `Push Notification`, `Background Fetch`, `Manual`. It is the diagnostic for why the phone reported.
- **Failures.** A sensor failure never fails the location update. Only a gone registration (410, no webhook) is recorded on the reporter (it stops, and the coordinator registers again), as for location.
- **A fix the filter refuses sends no sensors** (the official app has no filter). The next update carries them.
- **Order.** Updates form a first-in, first-out chain in `SensorReporter` (each waits for the one asked before it), so an older reading never lands after a newer one.
- **Never in the way (round 1 of #204).** `attemptSend` starts the sensor task and returns; the zone `fire_event`, the sub-region bookkeeping and the next queued zone event do not wait for the geocode or the sensor requests. Each background-time hold waits for the outstanding sensor tasks at its end (after the zone work, the push or refresh update, the significant-change work), for at most the background time left minus 5 s (at least 1 s; no limit in the foreground), then lets them carry on. A foreground Launch update has no hold and nothing waits for it.
- **Background time is clamped before any sleep.** iOS reports `DBL_MAX` for `backgroundTimeRemaining` in the foreground, which `Duration` cannot hold. `UIKitBackgroundTime.remaining` returns `.infinity` unless the app is in the background and the value is real, and every wait goes through `OneShotFix.waitLimit(backgroundRemaining:maximum:)` (`max(remaining - 5, 1)`, at most 60 s, NaN safe): the one-shot fix timeout, the sensor wait at the end of a hold, and the one-shot timer in `CoreLocationPlatform`. `stop()` cancels running and queued sensor updates (`SensorReporter.cancelPending()`), and each checks that before every send.
- **Deprecation.** The geocode uses `CLGeocoder`, deprecated from iOS 26. The deployment target is iOS 17, so it stays; `SystemDeviceStatusSource` carries a `TODO` to move to MapKit's `MKReverseGeocodingRequest` behind `#available(iOS 26, *)` when the target moves.

Not built, official providers we lack (follow-ups): Activity (CoreMotion activity), Pedometer, Barometer pressure, Active, Displays, Frontmost App, Camera and Microphone state, Hinge angle and status, Device pose, Focus name, Kiosk sensors, Health sensors, Input/output device and Camera motion/stream. Also: the per-sensor enable/disable switches in Settings (a visible change; all are on), the geocoded location's "use zone" option (the state is always the address), and a Focus authorization request (the Focus sensor reports only once the person has allowed Focus status sharing; this build never asks, and has no `NSFocusStatusUsageDescription`). Not verifiable on the host: the Wi-Fi lookup (`NEHotspotNetwork`), the geocode, the audio route, Focus and storage readings, and that Home Assistant creates the entities from the registration.

## Matching the official app

Names, unique ids, state strings and icons mirror `home-assistant/iOS` (`Sources/Shared/API/Webhook/Sensors`, `WebhookSensorId`, `LocationUpdateTrigger`) so templates only change the device prefix. Entity ids come from the device name plus the sensor name, so the names matter most.

| Sensor | unique_id | Notes |
|---|---|---|
| Battery Level / Battery State | `battery_level` / `battery_state` | `Charging`, `Full`, `Not Charging` |
| Connection Type, SSID, BSSID | `connectivity_connection_type`, `connectivity_ssid`, `connectivity_bssid` | SSID/BSSID need the Access Wi-Fi Information entitlement; `Not Connected` off Wi-Fi |
| Location permission | `location-permission` | `Authorized Always`, `Authorized when in use`, … plus a `Precise` attribute (ours) |
| Last Update Trigger | `last_update_trigger` | `Launch`, `Geographic Region Entered`, `Geographic Region Exited`, `Significant Location Change`, `Background Fetch`, `Push Notification`, `Manual` |
| Geocoded Location | `geocoded_location` | Mailing address; parts as attributes, `N/A` when unknown |
| App Version, Audio Output | `app-version`, `iphone-audio-output` | No Storage sensor (owner, 2026-10-29): Apple's only disk-space display reason, `85F4.1`, forbids sending the value off the device, see [testflight](testflight.md#privacy-manifests). A `sensor.<device>_storage` entity left from an earlier build stays unavailable; delete it in Home Assistant. |
| Focus | `focus` | Binary sensor |

The brief's shorthand ids (`ssid`, `region entered`) were replaced by the official ones above (2026-10-14).

## Reporting and the person link (2026-10-20)

Owner report: got home with the official app uninstalled and this app was not marked home despite Share Location Always and Report to Home Assistant on. Root causes, fixed here:

1. **Reporting was gated behind a hidden switch.** `LocationCoordinator.startIfReady` returned unless `isReportingArmed` (`location.reportingArmed`, default false) was set. The switch is gone: whenever a webhook exists and the permission is While Using or Always, the reporter runs.
2. **Nothing linked the tracker to a person.** Home Assistant follows only the `device_trackers` listed on a person; the app registered `device_tracker.<name>` but never touched the person. `PresenceLinker` now does (below).
3. **Background reporting was already wired** (`UIBackgroundModes: location`, significant changes, `CLMonitor` zones from `get_zones`, `update_location` on each event; usage strings in `project.yml`) but was dead while disarmed. It needs Always and Precise Location; While Using reports one fix per foreground only.

- **Every device reports.** The app delegate creates `LocationCoordinator` at launch when `LocationLaunchPolicy.isEnabled` (iPhone and iPad; not in test-token, reset or gallery launches unless `FENTON_LOCATION=1`). Only a phone also links a person (*The iPad rule*).
- **Offer once, as the last Setup step.** After sign-in and connection (`MainTabView.loadProfileName` → `SetupCoordinator.offerIfNeeded`) the Setup flow shows the location screen once per install while there is something to ask: nothing set yet, or While Using not yet upgraded and the Always alert not yet shown (`LocationCoordinator.needsPermissionStep`). It is the third step, after Notifications and Time Sensitive, in the same sheet (below). The old wording that location waits for the notification alert was never what the code did; now the order is real, because the steps share one sheet.
- **Seen set.** The flow remembers the steps it showed in `setup.stepsSeen` (`UserDefaults`, a string array: `notifications`, `timeSensitive`, `location`). An install that offered location before the flow existed has `location.permissionOffered` set; `SetupFlow.seen(in:)` reads that as "location seen", so nobody sees the location step twice and a person who accepted location gets only Time Sensitive (if they have not seen it). Location is marked seen when it first appears, as the single offer was. Journeys that reset offers (`FENTON_UITEST_RESET`, `LocationCoordinator.resetOffers`) clear both keys.
- **Start and stop.** The reporter starts when a webhook exists (this session's sync, or one saved by an earlier launch, so a background relaunch for a zone event reports without the websocket) and the permission is While Using or Always. Each return to the foreground sends a `Launch` fix. Sign-out stops it. A 410 syncs once, which registers again.
- **No toggle.** Reporting follows the permission; the Profile tab shows Share Location only.

### The iPad rule (owner, 2026-10-27, interim)

- An iPad asks for location (the same Setup step, copy unchanged) and reports to its own `device_tracker`. It is **never** linked to the signed-in person: `LocationCoordinator.linkPresence(user:api:)` and `unlinkPresence(user:api:)` do nothing when `linksPresence` is false, so `PresenceLinker` is not reached on iPad, not on sign-in, not when permission comes back, and sign-out does not wait on an unlink it never needed (`AppSession.confirmedSignOut`).
- `LocationReporter` no longer refuses to run on an iPad; the old `isPresenceDevice` gate is replaced by `linksPresence`, which only the coordinator reads.
- The Profile tab shows Share Location on iPad too. Its footer says the iPad reports as its own device and does not change whether you are home or away; no person-link notice shows.
- **Future item (out of scope now): multi-device presence.** Later, a person's home or away should consider every device they own ("any device away counts as away", configurable), which is what would make linking an iPad safe. Until then an iPad cannot mark anyone home.

### Presence link (`PresenceLinker`, `HassCore/MobileApp`)

On every sign-in (`MainTabView.loadProfileName`, after the registration sync) and again after the first accepted location update (Home Assistant creates the tracker lazily), `MobileAppCoordinator.linkPresence` runs `PresenceLinker.link` over the websocket:

1. `config/entity_registry/list`: find the `mobile_app` `device_tracker` whose `unique_id` is this registration's webhook id; if it is disabled, enable it (`config/entity_registry/update`).
2. `person/list`: find the person whose `user_id` is the signed-in user.
3. If the tracker isn't in that person's `device_trackers`, `person/update` with the existing list plus the tracker (append only; nothing else sent). Already listed: no call.

The registration itself already belongs to the signed-in user (the registrations API registers as the token's user). Outcomes (`PresenceLinkOutcome`) show in Share Location's section as an `InlineAlert`: `needsAdmin` (these commands are admin-only; owners and admins are tried, others skip without sending), `noPerson` (no UI-managed person has this user; YAML persons can't be edited), `trackerMissing`, `failed`. **Composite persons are skipped** (`compositeManaged`, silent): when the person's `device_trackers` already lists an entity the entity registry gives `platform: composite`, the S+H Home Integration 1.2 presence feature owns their tracking and would undo a direct link 2 s later, so the phone's tracker is not added. A YAML-only composite without a `unique_id` has no registry entry and is not detected. A linked, already-linked or composite-managed result is silent and isn't repeated for the same registration and user in a session; unlinked outcomes retry at the next connection or first report.

### Turning location off, on, and signing out (2026-10-20)

- **Off** (denied, restricted, no longer authorized): the reporter stops and the phone's tracker is taken off the person. Why: Home Assistant keeps a tracker's last state, so a phone that can no longer report would hold "home" for good and block the person's other trackers from being believed. Removing it (only this tracker) lets the others decide. Best effort.
- **On again**: the reporter starts at once (fresh `Launch` update, zones re-planned) and the tracker is linked again.
- **Sign-out** waits for `PresenceLinker.unlink` on a phone (`AppSession.confirmedSignOut`; an iPad never linked, so it signs out directly). Already unlinked, no person, or no tracker counts as success so retries never stick; any failure shows "Sign Out couldn't complete. Try again." and stays signed in. The `mobile_app` registration is then removed from Home Assistant by the sign-out unregister ([push](push.md)); the next sign-in registers fresh. Non-admin users never linked anything and sign out directly. Journeys stub the failure with `FENTON_SIGNOUT_FAIL=1`.
- Skipped: Mac steps (macOS is no longer a target; the macOS-only `AppSessionTests` are untouched).

## Matching the official app's location behavior (2026-10-29)

Source: `home-assistant/iOS` @ `cb064d4e` (`ZoneManager`, `AppZone`, `OneShotLocation`). Alignment PR A (zones, fixes, payload); PR B (push, background fetch, launch triggers); sensors are PR C (*Sensors*).

| Official | Ours | Departure and why |
|---|---|---|
| Legacy `CLCircularRegion` | `CLMonitor` circular conditions | Kept: the iOS 17 system API reports the same crossings. |
| Zones under 100 m: three 100 m regions, centers `100 - r` from the center at 0°, 120°, 240°, ids `<id>@<deg>` | Same (`ZonePlanner.regions(for:)`) | None. |
| 20-region cap, nearest zones first, whole zones dropped | Same; relaunch uses `manager.location` as the reference | None. |
| One-shot: `startUpdatingLocation` plus cached `manager.location`, perfect / meh / invalid, timeouts 20 / 10 / 30 s capped by background time - 5 | Same (`OneShotFix`, `OneShotSelector`; `CoreLocationPlatform` runs a `CLLocationManager` per request) | None. |
| Significant change: dropped if an update succeeded under 30 s ago or the reading is over 180 s old, else its own one-shot | Same | If no own fix arrives, the reading (not invalid) is sent. The official app sends nothing. |
| Repeat exit of the same zone from another circle within 5 minutes ignored | Same | None. |
| Enter with a fix: no `location_name`; `RegionEnter` and `MultiRegionOverlap` widen accuracy | Same (`ZoneEntryFuzzer`) | `MultiZone` (moves the coordinate when zones overlap) is not built: it lies about the position. |
| Exit with a fix: no `location_name` | `not_home` unless the fix is inside a non-passive zone | Deliberate. A missing exit and an accuracy circle touching a zone left the person home for hours (2026-10-29). |
| Failed one-shot on a region event: nothing sent | Enter: zone center named; exit: zone center at the circle's radius, `not_home` | Deliberate. The crossing iOS reported is the news. |
| `ios.zone_entered` / `ios.zone_exited` fired per crossing | Same | The vendor id is both `sourceDevicePermanentID` and `sourceDeviceID`. |
| `request_location_update` push: background task, 10 s one-shot, trigger `Push Notification`, via `payload["homeassistant"]["command"]` | Same work (`handleLocationRequest`); the command is read from `fenton.command` (our relay) and `homeassistant.command` | Relay payload differs from the official one; both are read. Push delivery is APNs only ([push](push.md)): no local push channel. |
| `BGAppRefreshTask`, +15 min at launch, on background and in the handler; `Background Fetch` fix, or sensors only when location is not allowed | Same (`BackgroundRefresh`); the sensors-only branch is `updateSensorsOnly` | Identifier `com.sfenton.home.backgroundfetch`. |
| `UpdateSensors(trigger, location)` beside every `update_location`; `registerSensors`; `not_registered` re-registers; unchanged payloads skipped | Same (`SensorReporter`); registered once per webhook id and app version | A fix the filter refuses sends no sensors. Retry timers (15 s to 15 min) are not built: the next update carries a failed one. |
| Sensors: battery, connectivity, location permission, last update, geocoded location, app version, storage, audio output, focus | Same ids, names, states and icons, without Storage; Focus only once Focus sharing is allowed | Storage is dropped on purpose (privacy manifest, above). The other official providers are follow-ups (*Sensors*). |
| Launch update once per foreground session (`LifecycleManager`) | Same (`LocationCoordinator.didEnterBackground` re-arms) | None. |
| `ignoreNextState`, SSID filter, beacons, per-zone `track_ios`, privacy modes, the four Settings toggles | Not built | Out of scope; the toggles are a visible change (propose-first). Behaves as all on. |
| Unknown region states ignored | Same: `CoreLocationPlatform` maps only satisfied and unsatisfied | None. |

Not verifiable without a device: that `CLMonitor` delivers a crossing for each of the three circles at the same distances as `CLCircularRegion`, and the graded one-shot in the background; both are Core Location behavior. Check the phone's history after the next real departure.

## Departures (2026-10-29)

Evidence, owner's history for the phone's `device_tracker`, 2026-10-19 to 28 (home zone radius 33 m, padded to a 100 m region):

1. The exit never arrived: last report at 7 m, next one 17 minutes later at 693 m (10-28), or 84 minutes at 522 m (10-27).
2. Exit sent at 382 m and 525 m (`not_home`), then in the same second a report with the same coordinates and `home`; the person stayed home 11 minutes. Several home/not_home flips at 42 to 89 m (inside the padded region, outside the real zone).
3. At home, one cached "309 m" fix was re-sent every 40 s for two hours, alternating with the real 7 m fix.

Causes and fixes: the monitor opened only after the `get_zones` call, which fails as Wi-Fi drops (now first, with cached zones); no background task around the send (now held); fixes had no timeout or freshness check and cached readings were delivered (now graded one-shot fixes with a timeout, plus out-of-order and age checks); coarse background fixes were dropped (now graded, not filtered by accuracy); enter always named the zone and exit demanded the accuracy circle clear every zone (enter now sends no name, so the 382 m and 525 m entries are placed by Home Assistant; exit trusts iOS). The 100 m padding of small zones is replaced by the official three-circle scheme (above). Tests: `LocationDepartureTests`, `ZonePlanningTests`, `LocationReporterTests`, `LocationParityTests`.

Done since (parity PR B): the `request_location_update` push command and Background App Refresh location updates (above). Parity PR C: the app's sensors with every update (*Sensors*).

## Inventory

What Home Assistant does with presence today (zones, people, trackers, the automations that react): [presence-inventory](presence-inventory.md).
