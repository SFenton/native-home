# Settings: household pages (Admin, Special Device Modes, Guest Controls, car)

> **What:** the household topics in Settings (its own tab) and the Admin sheets. **Read when:** changing `HassUI/Features/Settings/Household`, `HassCore/Settings` or `HouseholdSettingsConfig`.

## Web source

`ha-sfenton-react-dash@9ac2a46`: `src/pages/DashboardViewPage.tsx` `SettingsPage` (1944), `GuestControlsPage` (1948), `SpecialDeviceModesPage` (1964), `AdminPage` (2871), `AdminHashButton` / `LivingRoomPowerRecoveryButton` / `AdminPresenceOverrideGrid` (428-488), `ControlPage` for `car`; `src/constants/portedDashboard.ts` (`ADMIN_*`, `SETTINGS_PAGE_ITEMS`, `GUEST_CONTROL_ITEMS`, `CONTROL_PAGES` vehicle page); `src/components/hass/{PresenceOverrideCard,presenceOverrideState,SpecialDeviceModeCard,EntityActionCard}.tsx`; copy in `src/i18n/locales/en/pages/{settings,admin,specialDeviceModes,guests}.json`. Project spec: `plans/settings-household-spec.md`.

## Native

- Entities and copy: `HassCore/Config/HouseholdSettingsConfig.swift`. State and commands: `HassCore/Settings/HouseholdSettingsController.swift` (one per page), presence resolver `PresenceOverrideState.swift`.
- Pages: `HouseholdSettingsPageView(page:)` (a `ScrollView` of `SettingsSection`s, readable width 840 pt); `HouseholdSettingsDestination` wires it to the signed-in connection. Rows in `SettingsScreen` push it inside the Account sheet (`AccountSheet`; a sheet never splits); ids `settings.topic.<admin|specialDeviceModes|guests|car>` match the navigation shell's topic ids. Vacation and To-Do rows land with their own pages.
- Car topic label: generic, no make or model (owner, 2026-11-08).
- **Decision (2026-11-08): Car topic wording.** Owner's request 2026-11-08: "Rename to generic". Gate: request-driven, `matches_request=yes`, one topic (Settings row, topic subtitle, page title, Security section header).
  - Options considered: "Car" (picked); "EV" (an abbreviation; HIG Writing asks for plain language); "Car charging" (the page also holds doors, seats and climate).
  - Rationale: HIG Writing: settings labels are clear and brief, and match the neighbouring title-case rows (Admin Controls, Guest Controls). Subtitle: "Controls for the car." The mockups already draw "Car".
- Admin: Security Controls, Living Room Power Recovery (`automation.trigger`, no confirmation, as on the web), Relay Control Mode with the guest-mode `InlineAlert`, the two sheet openers (`GlassTile` `.navigate`), Show Specific Controls. Sheets (`.large`, drag indicator, Done) in every pose, never a split pane. Done is on the presence detail too (`householdSheetDone`, passed the sheet's own dismiss: `dismiss` read on a pushed page only pops it), so the sheet closes from any depth and audits see a sheet's Done in the bar.
- Presence-Based Overrides sheet: 14 room tiles tinted by mode (an unavailable room stays openable at full contrast and says Unavailable; its detail disables the choices); a room pushes its four modes inside the sheet as `SelectableOptionRow`s, one column on phones and two where there is room (the web's 2x2 grid crowds an iPhone). The detail is titled with just the room name (its bar also holds Back and Done, and the web's "<Room> Presence Lighting" clipped at large text; HIG: Navigation bars). Select sends `presence_based_lighting.set_automation_state` with `state` = `active` | `off` | `paused` | `quieted`.
- Toggles send explicit `turn_on` / `turn_off` from the shown state (`input_boolean`, `switch`; anything else through `homeassistant`), not the web's `homeassistant.toggle`. Toggles and presence modes are optimistic until Home Assistant confirms, the call fails, or 2 s pass (web `DEFAULT_OPTIMISTIC_REVERT_MS`).
- car tiles are `GlassStateTile`s (not buttons): the web gives them no action. Departure: Charge Status shows its value (the web hides it, leaving a tile with no information).
- HIG: Settings (grouped topics, push into detail), Toggles (`.isToggle` with On/Off), Sheets (Done, large detent for grids), Lists and tables (single choice with a checkmark and `.isSelected`).

## Tests

- Unit (`HouseholdSettingsTests`): config parity, presence resolver mapping, explicit on/off, optimistic confirm / revert / failure, unavailable entities ignored, relay warning rule, power recovery, car formatting.
- Hosted (`HouseholdSettingsViewTests`): every page live and unavailable at phone and iPad widths, sheets, detail, gallery, shared pieces, every SF Symbol exists, gallery recorder echo.
- Journeys (`HouseholdSettingsJourneyTests`): controls run in the debug gallery (`FENTON_GALLERY=household-settings`, `FENTON_GALLERY_HOUSEHOLD=<page>`, `FENTON_GALLERY_UNAVAILABLE=1`) on fixtures with a recording caller, so nothing in the house switches. The signed-in journey only opens each live page and audits Admin. Audits with the AX5 relaunch cover every page, both sheets and the presence detail.
