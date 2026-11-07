# Setup flow (Notifications, Time Sensitive, Location)

> **What:** the first-run and later-launch setup sheet that asks for notifications, explains Time Sensitive and asks for location, plus the Settings → Notifications entries that are the way back; decided 2026-10-27. **Read when:** touching the setup sheet, `SetupFlow`, `LocationPermissionSheet`, `NotificationsSettingsSection` or the permission copy.

Mockups: [setup-flow-time-sensitive](mockups/proposals/setup-flow-time-sensitive/setup-flow-time-sensitive.html) (flow, who sees what, screens) and [settings-notifications-time-sensitive](mockups/proposals/settings-notifications-time-sensitive/settings-notifications-time-sensitive.html) (Settings entries, drawn on the real Settings kit). Both are on the owner's mockup hub.

## The goal

Time Sensitive notifications (entitlement `com.apple.developer.usernotifications.time-sensitive`, verified on a device 2026-10-27) become a step of the setup flow that already asks for location. A first-time person sees every step; someone who already accepted location and never saw the Time Sensitive step gets only that step on the next launch.

## The decision (owner, 2026-10-27)

- **One Setup sheet, steps swap in place** (option A1), in the order Notifications, Time Sensitive, Location. One sheet at a time, no stacking.
- **No dots, counter or carousel.** HIG Privacy, pre-alert screens: one button that opens the system alert and no other way past it. A swipe or tappable dots would skip an alert, and the steps are a gated sequence (Time Sensitive needs notifications; the Always step needs While Using), not peer pages. Fallback if a position cue is ever wanted: a read-only, bottom-centred indicator (HIG Page controls, Minimal style) as a variant of the page-indicator pattern.
- **Time Sensitive is shown once to everyone who has not seen it** (B1), reporting its real status: "Got It" when the switch is on, "Open Settings" and "Not Now" when it is off. iOS has no system alert for Time Sensitive; the app can read `timeSensitiveSetting` but cannot set it. HIG Notifications also says the system explains an app's first Time Sensitive notification itself, so this step is a confirmation, not the only explanation.
- **Seen steps are persisted** (`setup.stepsSeen`); an existing `location.permissionOffered` (the legacy once-per-install flag, `LocationCoordinator.offeredKey`) counts as "location seen". The mockups say `location.offered`; the code's key is the one above.
- **Notifications becomes a step** for people never asked; the Home banner stays as the fallback.
- **iPad gets the whole flow, Location included.** All iOS devices opt in to location (owner). Interim rule: an iPad reports its own location but is never linked to the signed-in person, so it cannot mark them home while they are away. Long term (not built): several devices per person where any device away counts as away, or the person chooses which devices count.
- **The sheet's bar title names the step on screen** (owner, 2026-10-27, replacing the mockup's generic "Setup"): "Notification Settings", "Time Sensitive Notification Settings", "Location Settings".
- **Location copy names the device.** "This iPad can tell Home Assistant when it arrives or leaves." on iPad (no Away mode promise: it is never linked to the person); "This iPhone can tell Home Assistant when you arrive or leave, so Away mode and the thermostat follow you." on iPhone and iPhone Duo, derived from the device idiom. No Mac wording: macOS is not a product target.
- **The Time Sensitive step has no Close and cannot be swiped away**; its buttons ("Got It", or "Open Settings" and "Not Now") are the only way out.
- **Copy** names door and camera alerts only (the integration's time-sensitive pushes are those).
- **Settings → Notifications**, when notifications are allowed: two entries, "Notifications" and "Time Sensitive Notifications", each a row with glyph, title and a status line (descriptions in the rows, no section footer), each opening this app's notification page in iOS Settings. Glyph `bell.fill` when on, `bell.slash` when off. No switch: the app cannot change either value.

## Full-height sheet: a departure from the fitted-height rule (owner, 2026-10-27)

The Setup sheet is a **full-height** page sheet (`hassSheet(.page, height: .full)`), not the fitted height the other sheets use (owner decisions 2026-10-16 and 2026-10-25). Reason, measured on iPhone: iOS insets a content-fitted sheet and draws everything in it at about 0.96x, so a designed 50 pt button reads 48.01 pt and a 44 pt target about 42 pt. The same Setup sheet at full height reads x 24.0, width 354.0, height 50.0, so its targets draw at design size. `RoomDevicesJourneyTests.assertSheetTarget` already tolerates the same shrink in fitted sheets (floor 41.5 pt), so the shortfall is app-wide and existing; making only this sheet full height is the owner's call for the one sheet that asks for a permission. The other fitted sheets keep the shrink; a follow-up can address them.

The Notifications and Location steps are HIG pre-alert screens, so a full-height sheet with one Continue and no Close is also the closer fit to "a custom screen before the system alert".

## Rules this adds

- **Chevron exception.** Both entries carry a chevron although they open iOS Settings. [settings-section](../patterns/settings-section.md) says a chevron means push and nothing else; this is an owner decision (2026-10-27), recorded there.
- The deep link is `UIApplication.openNotificationSettingsURLString` (iOS 16 and later), falling back to `openSettingsURLString`.
- The system values are re-read when the app becomes active, so the step and Settings are right on return from iOS Settings.
- Updates [location.md](../platforms/apple/location.md) (offer rules; iPad reports but never links) and [push.md](../platforms/apple/push.md).
