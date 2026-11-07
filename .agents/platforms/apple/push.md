# Native push notifications

> **What:** how Home Assistant notifications reach the app natively, and how a notification's buttons, links and attachments behave. **Read when:** touching notifications, the notification service extension, `mobile_app` registration, or sign-out.

Owner decision (2026-10-14): native notifications through our own push path, replacing the companion app for alerts. The server half is the S+H Home Integration, [`SFenton/ha-fenton-push`](https://github.com/SFenton/ha-fenton-push), whose `docs/CONTRACT.md` (v1) both halves follow. Automations keep calling `notify.*` with the companion app's `data` keys; the integration's relay turns them into APNs pushes for this app.

## Path

```
automation ─ notify.mobile_app_<device>_fenton ─▶ mobile_app ─ POST push_url ─▶ S+H Home Integration relay ─ APNs ─▶ phone
                                                                                                     │
       Home Assistant ◀─ webhook: update_registration, fire_event ◀─ app ◀─ tap / button ◀───────────┘
```

| Piece | Where |
|---|---|
| Config, payload, links, categories, attachments | `HassCore/Push` (logic, 95% bar) |
| Registration and its webhook (shared with location) | `HassCore/MobileApp`, `HassUI/App/MobileApp` ([mobile-app](mobile-app.md)) |
| Session wiring, taps, buttons, `clear_notification` | `HassUI/App/Push/PushCoordinator.swift`; `ShellNavigator.open(_:)` |
| System glue (permission, APNs token, `UNUserNotificationCenterDelegate`) | `Apps/iOS/FentonHomeApp.swift`, `Apps/iOS/SystemPushPlatform.swift` |
| App icon badge ([badge](badge.md)) | `HassUI/App/Push/AppIconBadgeSync.swift` |
| Notification Service Extension (`com.sfenton.home.NotificationService`) | `Apps/NotificationService/` |

## Registration (contract rules 1-2)

- After sign-in, once the websocket is up and the user is known (`MainTabView.loadProfileName`): read the stored answer and the Time Sensitive switch, `registerForRemoteNotifications` when allowed, then sync. The permission is asked by the Setup flow's Notifications step (below), never raised silently.
- Sync: `GET /api/fenton_home/config`, then `/api/fenton_push/config` only when the new path answers 404 (servers not yet on the 1.0 S+H Home Integration, formerly Fenton Push; repo still `SFenton/ha-fenton-push` until renamed). The registration is shared with location and sensors ([mobile-app](mobile-app.md)): **404 (integration not installed) registers websocket-only** (since 2026-10-15; push used to register nothing). `available: false`, a `bundle_id` that is not the running bundle's (`MobileAppDevice.appID`) or no APNs token: register without push details; a later `update_registration` adds them. `push_websocket_channel` stays off until the app subscribes to `mobile_app/push_notification_channel` (claiming it without listening makes Home Assistant think a token-less phone is reachable).
- One webhook per Home Assistant user per server, in the Keychain (`KeychainMobileAppRegistrationStore`, service `com.sfenton.home.push`). Reused until sign-out removes it (below); `update_registration` on every launch and token change; a 410 from the webhook forgets it and registers again.
- `device_name` is `"<name> · Fenton"`, so the notify service never collides with the official app's on the same phone. iOS reports `UIDevice.name` as just "iPhone", so a generic name becomes the model's marketing name and the user's first name: "Sam's iPhone Duo · Fenton" (`MobileAppDevice.marketingName(forModel:)`; unknown identifiers keep "iPhone"; a name the person chose is kept). Reason (2026-11-02): Home Assistant keeps one notify action per `device_name`, and three phones all named "Sam's iPhone · Fenton" left only one reachable.
- `app_id` is the running bundle's identifier (`MobileAppDevice.appID`, fallback `PushApp.appID`), never a constant: the `com.sfenton.home.uikit` build once registered as `com.sfenton.home` with a token for the wrong topic, so every push to it failed.
- `apns_environment` comes from `embedded.mobileprovision` (`aps-environment`): sandbox for Xcode installs and the simulator, production for TestFlight and the App Store.
- **Sign-out removes the registration (2026-11-02).** `MobileAppRegistrar.signOut` POSTs `{"webhook_id"}` to `/api/fenton_home/devices/unregister` (S+H Home Integration 1.1) with the access token **before** the refresh token is revoked (`AppSession.signOut` awaits `sessionEnded` first), so no stale device stays in Home Assistant. 200 or 410 forgets the saved webhook; a later sign-in finds none and registers fresh.
  - **Server without 1.1 (404)**, or 403 / another HTTP error: falls back to `update_registration` with `app_data: {}` (the old behaviour); on 404 or error the saved webhook is kept, on a 410 from that call it is forgotten.
  - **No valid access token** (`AppSession.signOut` clears the token store before the registrar runs, so a near-expired token can't refresh): the same request goes **without auth** at once, since the webhook id is the proof.
  - **No answer (offline, timeout), 429 or 503:** the removal is saved as a `PendingUnregister` `{server, webhookID}` in the same Keychain item as the registrations (survives relaunch; the webhook id is never logged) and the stored registration is forgotten. `PendingUnregisterRetrier` re-sends it **without a token** (the webhook id is the proof) at launch (`UKAppDelegate`) and whenever `SystemNetworkReachability` reports a path again, signed in or not: 200/410 drop it; 404 drops it after a best-effort clear-push-details call; 400/403 drop it (can never succeed); network failure or a 5xx keeps it.
- Debug UI journeys keep push off (no prompt, no registration) when launched with `FENTON_HASS_TOKEN`, `FENTON_UITEST_RESET` or `FENTON_GALLERY`, unless `FENTON_PUSH=1` (`PushLaunchPolicy`).

## Payload (contract rule 3)

- `userInfo.fenton` (`PushPayload`): `v`, `tag`, `group`, `url`, `actions[]`, `entity_id`, `image`, `video`, `attachment.url`, `command`, `ext` (an automation's own `data.fenton`), `extra` (unmapped keys such as `presentation_options`). A newer `v` is ignored.
- Taps open `url`; a button with `uri` opens that; other buttons fire `mobile_app_notification_action` through the webhook with `action`, `tag` and, for text input, `reply_text`. Home Assistant decides what happens: the app never acts on a button itself.
- Links are read like the web dashboard reads them (`routes.ts` `routePathFromUrl`): `/sfenton-react-dash/home?path=<route>#<anchor>`. Sections open at their root (`overview`, `security`, `thermostat`, `chores` and its sub-routes, `settings` and its sub-routes); Home pages push on Home (rooms, Groceries, Vacuums, Media; Food detail pages open the Food hub). Anchors are not scrolled to yet. Other Home Assistant paths and other sites open in the browser.
- Background push `{"aps":{"content-available":1},"fenton":{"command":"clear_notification","tag":…}}` removes delivered notifications with that tag. `request_location_update` takes a location update (below); other commands are ignored for now.
- **`request_location_update` (2026-10-29):** `notify.mobile_app_<device>_fenton` with `message: request_location_update` makes the relay send `{"aps":{"content-available":1},"fenton":{"v":1,"command":"request_location_update"}}` as a background push (`apns-push-type: background`, priority 5). `PushPayload` also reads the official app's shape, `userInfo["homeassistant"]["command"]` (the `fenton` block wins when both carry a command). `application(_:didReceiveRemoteNotification:)` (async, so the system's completion handler runs when it returns) calls `PushCoordinator.handleBackground`, which runs `LocationCoordinator.handleLocationRequest()`: start reporting if the relaunch got there first, hold background time, one-shot fix (10 s, capped by the time left), send with trigger `Push Notification`. Result `.newData` when an update was sent, else `.noData`. Needs Always + Precise in the background; in the foreground While Using is enough. Which channels reach the phone, and which can wake it:
  | Channel | Delivers it | Wakes the app in the background |
  |---|---|---|
  | S+H Home Integration relay, APNs background push | yes | Yes: `UIBackgroundModes: remote-notification`, content-available, delegate above. iOS may delay or drop priority-5 background pushes (low power, many recent wakes, Background App Refresh off) and never delivers to a force-quit app. |
  | Websocket-only registration | no | No. The app does not subscribe to `mobile_app/push_notification_channel`, so Home Assistant treats a token-less phone as unreachable; a websocket channel would only work while the app is in the foreground anyway. |
  | Local push (`NEAppPushProvider`, the official app's local-network channel) | no | Not built (needs Apple's Network Extension entitlement and a provider extension). |
  | Foreground APNs push | yes | The same delegate runs; location is allowed with While Using. |
  Not verifiable without a device: APNs delivery and the throttling above.

## Service extension

- Replaces the relay's `fenton.dynamic` category with one built from the buttons (`PushCategory`: a stable hash of the buttons; at most 32 built categories are kept, others are untouched). Buttons: `sfsymbols:<name>` icons, `authenticationRequired`, `destructive`, `activationMode: foreground`, `behavior: textInput`.
- Threads by `group` when the relay sent no `thread-id`.
- Attaches, in order: the camera snapshot for a `camera.*` `entity_id` (`/api/camera_proxy/<entity_id>`), then `image`, `video`, `attachment.url`. Server paths and same-server URLs carry the signed-in user's token, read from the Keychain item the app shares through the app group `group.com.sfenton.home` (`KeychainTokenStore.sharedAccessGroup`; an older unshared item moves in on first read). Size limits: 10 MB image, 50 MB video, 5 MB file.
- Anything that fails leaves the notification as sent.

## Live camera (content extension, `com.sfenton.home.NotificationContent`)

- A notification with a `camera.*` `entity_id` gets the fixed category `fenton.camera` (`PushCategory.camera`, set by the service extension), which the content extension serves; it sets the notification's buttons at runtime (`extensionContext.notificationActions`) and forwards presses to the app (`.dismissAndForwardAction`).
- It shows the attached snapshot, then streams Home Assistant's MJPEG (`/api/camera_proxy_stream/<entity_id>`, token header, `MJPEGFrameScanner`), and switches to HLS (`camera/stream` over a commands-only websocket, `HassConnection.connect(subscribingToStates: false)`) when that plays. Debug builds print the step in the view.
- **Link `UserNotificationsUI.framework` explicitly and keep `ENABLE_DEBUG_DYLIB: NO`.** Without it the extension crashed on the phone in `EXConcreteExtensionContextVendor _extensionContextClass` before any app code (seen 2026-10-14).
- Status 2026-10-15 (paused by the owner): the expanded view shows the snapshot, but the live video never started, and the extension wrote no trace lines at all, so start by checking whether `didReceive(_:)` runs and whether the extension can write to the app group. The app's websocket also drops on the owner's server ("Received frame with non-zero reserved bits"), which would break HLS.

## Debugging on a phone

- Debug builds write `Library/Caches/push-trace.log` in the app group (`PushTrace`: step names, entity ids, HTTP statuses; never tokens or text). Copy it with `xcrun devicectl device copy from --device <udid> --domain-type appGroupDataContainer --domain-identifier group.com.sfenton.home --source Library/Caches/push-trace.log --destination <file>` (devicectl reads only `Library`, `Documents` and `tmp`).
- Extension crashes: `xcrun devicectl device info files --device <udid> --domain-type systemCrashLogs`, then `copy from` the `.ips`.
- Verified on the owner's iPhone (2026-10-15, Debug, sandbox): registration and `update_registration` (rename to "Sam's iPhone · Fenton"), real APNs delivery, buttons from the payload, and the camera snapshot attachment. `notify.fenton_<person>` (person targets) works with Fenton Push 0.1.1, which calls each device's own `notify.mobile_app_<device>_fenton` (verified 2026-10-15).

## Routing on the owner's server

- 2026-10-15 (owner's request): a YAML notify group per person (in `/config/configuration.yaml`) lists `fenton_<person>` after the official app's `mobile_app_<device>`, so every automation that notifies that person, and a household group that nests it, reaches both the official app and Fenton. A backup was taken first (`configuration.yaml.bak-<timestamp>-fenton`). A person's group is unchanged until they run Fenton.

## Testing

- Logic: `HassCoreTests/PushTests.swift`, `HassUITests/PushCoordinatorTests.swift` (REST double: `HassTestSupport/StubHTTPTransport`).
- Device journeys: `PushJourneyTests` with `tools/push_sim.sh <udid> <folder>` running beside `tools/ios_uitest.sh` (same folder in `TEST_RUNNER_FENTON_CAPTURE_DIR`; `send-<fixture>.ready` asks for a push, other `.ready` files for a host screenshot); fixtures in `tools/push_fixtures/`. Simulator push is the bar until the APNs key exists; device delivery is deferred.
- `xcrun simctl push` never runs service extensions, and the simulator refuses content-available-only pushes ("no user visible content"; seen 2026-10-14, iOS 27). Debug builds therefore have two hooks that run the same code paths: `FENTON_PUSH_PREVIEW` (a base64 `.apns` shown as a local notification after `PushEnrichment` and `PushAttachmentLoader`, after `FENTON_PUSH_PREVIEW_DELAY` seconds) and `FENTON_PUSH_COMMAND` (a base64 background payload run through `handleBackground` at launch). The extension itself is verified only with real APNs.
- After each boot the iOS 27.0 simulator can take minutes to answer `requestAuthorization` (the alert, or a stored answer, arrives late; seen 2026-10-14), and it refuses timed local requests ("Source is not authorized"), so the preview waits in the app and posts at once. Journeys allow 240 s for a preview banner; keep the simulator warm between runs. A reinstall keeps the stored permission, so no alert comes: the journeys stop waiting for the alert as soon as the expected preview banner shows, or they miss it (seen 2026-10-15).
- An attached camera snapshot did not show a thumbnail on the iOS 27.0 simulator preview even when no error was logged (2026-10-14); confirm attachments on a device with real APNs.
- In the extension, camera snapshots need a password sign-in (the token launch keeps its token in memory, out of its reach); the preview hook uses the launch token directly.

## Open

- Real APNs: needs the owner's APNs key in the integration; TestFlight builds need `aps-environment: production` at archive.
- Critical alerts need Apple's Critical Alerts entitlement for `com.sfenton.home`; until then the integration sends time-sensitive.
- Notification settings UI goes under the Account sheet after Direction G Phase 2 (#68) lands.

## Setup flow (owner, 2026-10-27)

One **Setup** sheet whose steps swap in place after sign-in: **Notifications**, then **Time Sensitive**, then **Location** ([location](location.md)). Proposal and mockups: `.agents/design/mockups/proposals/setup-flow-time-sensitive` and `settings-notifications-time-sensitive`.

- **Pieces.** `SetupFlow` (pure rules and the seen set), `SetupCoordinator` (the one presentation state; drives the next step), `SetupPresenter` (the sheet, and re-reads the notification answers each time the app becomes active), `SetupSheet` and the step views in `HassUI/Features/Setup`; the Location step is the existing `LocationPermissionView`. The call site is unchanged: `MainTabView.loadProfileName`, after the connection and the person link.
- **No progress cue and no way around a step.** No dots, counter, carousel or swipe between steps. The Notifications and Location steps are pre-alert screens (HIG Privacy): one Continue, no Close, not swipe-dismissible. The Time Sensitive step has no alert behind it; it has no Close either, and its buttons are its way out. One sheet at a time, never stacked (HIG Sheets).
- **Which steps show** (`SetupFlow.nextStep`, `setup.stepsSeen` in `UserDefaults`; migration in [location](location.md)):

| Step | Shows when | Marked seen |
|---|---|---|
| Notifications | `PushAuthorization.notDetermined` and not seen | on Continue (before the iOS alert) |
| Time Sensitive | notifications are `granted` and `UNNotificationSettings.timeSensitiveSetting` is not `notSupported` and not seen; shown even when the switch is already on | on Got It, Not Now or Open Settings |
| Location | a location coordinator exists and `needsPermissionStep`, and not seen | when it first appears |

  After a step completes the flow re-reads the system and swaps in the next pending step in the same sheet; a refusal skips Time Sensitive (it shows once later if they allow later). A person who accepted location but never saw Time Sensitive gets only that step on the next launch.
- **Time Sensitive step** (always dark, page sheet, action at the end of the scrolling content). On: "Let Urgent Alerts Through", status "Time Sensitive Notifications: On", three points, "Already on. Nothing to change.", **Got It**. Off: "Urgent Alerts Are Held Back", status "Off", the same points, "Turn on Time Sensitive Notifications, then come back.", **Open Settings** and a text button **Not Now**. The copy follows the live switch, so after Open Settings the step reads On with Got It once the person returns. iOS has no Time Sensitive alert: the app can read the switch (`PushPlatform.timeSensitiveSetting`: `enabled`, `disabled`, `notSupported`) but never change it or ask. Open Settings goes to `UIApplication.openNotificationSettingsURLString` (iOS 16 and later; falls back to `openSettingsURLString`).
- **Reading the switch.** `PushCoordinator.refreshSettings()` reads the permission and the switch (switch is `notSupported` unless notifications are allowed) when the session connects, after each ask, when the app becomes active and when the flow evaluates, so Settings and the step are right after returning from iOS Settings. It does nothing before the session connects, so journeys that never register never prompt.
- **Home banner.** `NotificationPermissionBanner` stays as the fallback for a person who saw the Notifications step and never answered. It waits while the flow is about to ask (`PushCoordinator.setupHasShownNotifications`).
- **Settings → Notifications** (`NotificationsSettingsSection`). Never asked: Turn On Notifications. Refused: Open Settings to allow notifications. Allowed: header "Notifications", no footer, two `SettingsLinkRow`s with a chevron: **Notifications** (bell.fill, "On. Door and camera alerts reach you.", `settings.notifications`) and **Time Sensitive Notifications** (bell.fill / bell.slash, "On. Urgent alerts can break through a Focus." / "Off. Urgent alerts wait until your Focus ends.", `settings.notifications.timeSensitive`; hidden when `notSupported`). Both open the app's notification page in iOS Settings, carry the hint "Opens Settings", and read as one element each; there is no switch because the app cannot flip either value. The chevron is an owner exception to the "chevron means push" rule ([settings-section](../../patterns/settings-section.md)).
- **Tests.** Logic: `HassUITests/SetupFlowTests` (every row of the who-sees-what table, the migration), `SetupCoordinatorTests`, `TimeSensitiveTests`, `PushCoordinatorTests`. Journeys: `SetupJourneyTests` (gallery `FENTON_GALLERY=setup`) and `NotificationSettingsJourneyTests` (`FENTON_GALLERY=notification-settings`) on iPhone, iPhone Duo and iPad, audit plus AX5.

## Permission in context (owner, 2026-10-23)

The system alert is never raised on sign-in. `PushCoordinator.didConnect` only reads the stored answer (`PushPlatform.authorization`) and registers when it is allowed. A never-asked phone is first asked by the Setup flow's Notifications step (2026-10-27, above); if it never answered, it sees the Home `NotificationPermissionBanner` ("Get door and camera alerts", Turn On Notifications / Not Now; Not Now is remembered) and the Settings → Notifications row; Turn On calls `enableNotifications()`, the only place the alert is requested. A refused phone gets an Open Settings row. Proposal: `.agents/design/mockups/proposals/widgets-push-siri-watch`. A category carries at most four buttons and a hidden-previews placeholder; the app has the time-sensitive entitlement.
