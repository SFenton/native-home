# Settings: Home Assistant settings modal (iPhone and iPad)

> **What:** the Home Assistant settings modal and how the renderer draws Settings. **Read when:** changing the Settings pages or the Home Assistant modal.

Settings is composed from the publication ([architecture](../../platforms/apple/architecture.md#server-driven-root)).

## Web source

- `ha-sfenton-react-dash@9ac2a46:src/constants/portedDashboard.ts` `SETTINGS_PAGE_ITEMS`: the last item, "Home Assistant Settings" (`mdi:cog`), links externally to `/config`. Copy from `src/i18n/locales/en/pages/settings.json` `items.homeAssistant`.
- Row shape: `DashboardViewPage.tsx` `SettingsLink` (icon, bold title, wrapping subtitle, accessory).
- The web dashboard runs inside Home Assistant, so it has no server, account or sign-out UI. The app owns its sign-in, so those live natively in the modal (departure from web parity).

## Native

- **Settings** is the last section. Its rows are module rows over the wallpaper; every push is a value on the section's path, a topic is never split, and Profile and Quick Links ride in the header of each pushed page. A notification for Settings opens it through the authored route whose path is `settings` ([routes](../../patterns/routes.md)).
- **The list** is Vacation, the admin To-Do (hidden from non-admin viewers), Appearance (Background Blur, App Icon), the household topics, then the Home Assistant row, Performance and Feedback ([household](household.md), [feedback](feedback.md), [profile](profile.md)).
- **Background Blur** is a 0 to 100% slider (steps of 5; default 50%, the web's 16.8 pt blur) with Reset to Default, re-rendering the wallpaper live ([page-backdrop](../../patterns/page-backdrop.md)). The footer says what it does, or that Reduce Transparency has replaced the photo.
- **App Icon** shows a small preview of the installed icon and its name and opens the picker (eight named choices, the installed one checked; selection calls `setAlternateIconName`). The row hides where alternate icons are unsupported. The pairs are in [direction-g](../../design/direction-g.md).
- **Home Assistant modal.** The row opens Home Assistant's own pages (`UKHomeAssistantWebPageViewController`) in a full-screen modal, single-page on every device and pose. HIG: Modality (full-screen for a self-contained task with its own navigation), Settings.
- Sections: **Server** (address, connection, Home Assistant version), **Account** (name and role from `HassConnection.currentUser()`), **Home Assistant** (Settings `/config` for administrators and owners, Profile `/profile` for everyone), **Sign Out** with a confirmation dialog (HIG: Action sheets).
- Web pages push inside the modal's stack (Back returns to the form).
  - `FrontendSession` writes the app's tokens into `localStorage.hassTokens` at document start, only on the server origin, in a non-persistent `WKWebsiteDataStore`, so the frontend opens signed in and nothing reaches disk.
  - Off-server links open in the browser.
- `FENTON_REDACT_PRIVATE=1` hides the server address and user name for shared screenshots. Web-page screenshots stay out of the repo.

## Server-driven composition

`settings-provider@1` and `settings-control` (`sh.settings-controls@1`) expose closed domain operations, not page-ID dispatch. The host registers immutable, session-owned providers before native preflight; a missing, cross-domain or unknown target rejects the candidate and keeps the last-good publication.

- `UKServerUIPreferencesProvider` binds the blur, app-icon and About models.
- `UKServerUIPerformanceProvider` projects the telemetry report into row collections.
- `UKServerUIProfileProvider` renders read-only server and account values and role-gated web links. No credential or unrestricted connection enters a document.
