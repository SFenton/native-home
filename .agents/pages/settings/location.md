# Location permission screen

> **What:** the explainer that asks for location and shows its status. **Read when:** changing `LocationPermissionView`, its copy or its journey.

Native only; the web dashboard has no counterpart. Logic and reporting rules: [location](../../platforms/apple/location.md).

## Stages

`LocationPermission.stage` picks one of five; While Using has a second form once iOS has shown its one Always alert (`canAskForAlways: false`). Copy lives in `LocationPermissionCopy`.

| Stage | Title | Status value | Button | Close |
|---|---|---|---|---|
| Not determined | Know When You're Home | Not Set | Continue → While Using alert | No |
| While Using | Notice When You Leave | While Using the App | Continue → Always alert | No |
| Always | Home and Away Are On | Always | none | Yes |
| Off (denied or restricted) | Location Is Off | Off / Restricted | Open Settings | Yes |
| Approximate | Precise Location Is Off | Always, Approximate | Open Settings | Yes |
| While Using, Always alert already shown | Notice When You Leave | While Using the App | Open Settings | Yes |

The asking stages also show three points (arrivals and departures, only to your server, light on battery) and a footnote naming the option to pick in the system alert.

## Decisions

- **HIG wins over the modal pattern.** HIG Privacy, Pre-alert screens: one button that opens the system alert, titled "Continue", not "Allow", and no other way out. So the two asking stages drop the Close every modal carries ([modal-sheet](../../patterns/modal-sheet.md)) and can't be swiped away (`interactiveDismissDisabled`). The system alert itself offers the decline.
- One `PrimaryButton` per screen, at the end of the scrolling content. Not pinned: on an iPad form sheet a pinned bar covered the last point and the audit measured that text through it (3.6:1, 2026-10-14). At AX5 the action is reached by scrolling.
- The status row is one element: label "Location Access", value the status.
- Each point is one element (title and detail). The large symbol is decorative and hidden.
- Dark, like every sheet in Direction G v1 (`preferredColorScheme(.dark)`, as `WeatherSheet`); light text on the grouped ground keeps the secondary copy well above 4.5:1 (the light ground measured 4.4:1 on the Duo, 2026-10-14).
- Sheet: `.hassSheet(.page, height: .full)`, full height on iPhone, a page sheet on iPad; content capped at 560 pt. A form sheet hid Continue below the fold on iPad portrait at the default text size (2026-10-14).
- Settings: `UIApplication.openSettingsURLString`. The asking stages never send people to Settings.

## Entry points

- After sign-in on iPhone, iPhone Duo and iPad, as the last step of the Setup flow (Notifications, Time Sensitive, Location in one sheet whose steps swap in place; [push](../../platforms/apple/push.md#setup-flow-owner-2026-10-27)), offered once per install while there is something to ask (`LocationCoordinator.needsPermissionStep`, `SetupFlow`). The sheet's bar names the step on screen: "Notification Settings", "Time Sensitive Notification Settings", "Location Settings" (every stage of the Location step).
- Debug gallery (`FENTON_GALLERY=location`, `FENTON_GALLERY_LOCATION=<stage>` or `when-in-use-asked`); Continue plays the system's answer.
- The Your Summary sheet's Profile tab **Location** section (`LocationAccountSection`), iPhone, iPhone Duo and iPad (since 2026-10-27; an iPad reports as its own device and is never linked to a person, so its footer says so): **Share Location** shows the status value and opens this screen as a page sheet over the Account sheet (`LocationPermissionSheet`, shared with the after-sign-in offer); There is no Report switch (2026-10-20): reporting follows the permission. With nothing to send (not set, off, approximate) an `InlineAlert` warning in the section footer, above the explanation, says why; a second one says when this phone could not be added to the person's trackers (`PresenceLinkOutcome`: needs an administrator, no person, no tracker yet, failed) (inside the card as a clear row it cut off the card's rounded corners, 2026-10-15). Header and footer use `FormHeader` and `FormFooter` (secondary ink on the sheet's grouped ground). HIG: Privacy (no switch duplicating the system permission).

## Tests

- Hosted: `HassUITests/LocationPermissionViewTests` (copy, status, actions, renders of every stage at default and AX5 on phone and tablet widths).
- Journeys: `Apps/iOSUITests/LocationJourneyTests` (pre-alert rules, walking to Always, Settings stages, audit plus AX5 per stage) and `LocationShadowJourneyTests` (signed in: every device walks the real system alerts to Always) and `LocationAccountJourneyTests` (the offer in the four-tab shell, the Account section's row, toggle, warning, persistence and audit at default and AX5 on phones; no section on iPad) on iPhone, iPhone Duo and iPad.
- Hosted: `HassUITests/LocationAccountSectionTests` (warning rules, renders at default and AX5).
