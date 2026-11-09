# App name: S+H

> **What:** the public name, how it is spoken, what stayed "Fenton Home", and how people can still find the app by "Home", "Home Assistant" or "HASS". **Read when:** touching `CFBundleDisplayName`, usage strings, Spotlight, App Shortcuts or `mobile_app` registration.

**Owner decision (2026-10-17):** the app is called **S+H**. The bundle id stays `com.sfenton.home`; "S+H" is the name on the home screen, in search and in every string people read. Since 2026-11-01 that app is the UIKit app (`FentonHome` in `apple/project.yml`; `Apps/iOS/SHShortcuts.swift` carries the App Shortcuts); there is no `com.sfenton.home.uikit` "S+H UIKit" any more. People should still find it by "Home", "Home Assistant", "HASS" and similar.

## What carries the name

| Place | Value | Source |
|---|---|---|
| Home-screen label, Spotlight app result, Siri | `S+H` | `CFBundleDisplayName` in `apple/project.yml` (Apple: "the user-visible name shown on the iOS Home screen and used by Siri") |
| Spoken name (VoiceOver, text-to-speech) | `S and H` | `CFBundleSpokenName` ([doc](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundlespokenname): "a replacement for the app name in text-to-speech operations"). "S+H" would be read "S plus H". |
| Siri alternative names | Home Assistant, HASS, Fenton Home | `INAlternativeAppNames` ([doc](https://developer.apple.com/documentation/sirikit/specifying-synonyms-for-your-app-name)): at most three, each with an optional "sounds like" hint |
| Notification service / content extensions | `S+H Notifications`, `S+H Camera Notifications` | Their `CFBundleDisplayName`. iOS lists notification settings under the containing app, so the extension names are not shown to people; they only show in logs. |
| Watch app | `S+H`, spoken "S and H" | `INFOPLIST_KEY_CFBundleDisplayName`, and an `accessibilityLabel` on the stub's title (`AppBranding`) |
| Permission strings | "S+H shares your location with Home Assistant…", "S+H connects to Home Assistant directly…" | `apple/project.yml` |

`AppBranding` (HassCore) holds the same values for code and tests.

## What did not change, and why

- **Bundle identifiers, app group, Keychain access group.** Changing any of them would sign people out, drop the push registration and orphan the `mobile_app` registration.
- **`mobile_app` registration** (`PushApp.appName = "Fenton Home"`, `deviceNameSuffix = " · Fenton"`). `app_name` is only sent at `POST /api/mobile_app/registrations`; the later `update_registration` webhook cannot change it, and a new registration would add a second device and a second `notify.mobile_app_…` service next to the automations that call the first. Home Assistant shows the app as "Fenton Home" until the device is removed and the app signs in again; that is by design. Change it only together with a migration that removes the old device.
- **Home Assistant side:** the "Fenton Home Feedback" integration, the S+H Home Integration (domain `fenton_home`, formerly Fenton Push; repo `ha-fenton-push`), the `FentonHome` user agent and the repo name.
- **Code identifiers:** the `FentonHome` scheme, product module and test targets, `HassCore`, `HassUI`, `HassDesign`.
- ~~The sign-in screen never named the app.~~ Resolved (owner, 2026-10-17): the sign-in screen shows **S+H** (spoken "S and H") under the house-and-heart mark ([auth](auth.md), Sign-in screen).

## Finding the app by other names

What the system matches, for an app signed for development (no App Store listing, so no App Store keywords):

| Search | What shows |
|---|---|
| "S+H", "S and H" | The app icon (Spotlight matches the display name) and the app's pages and shortcuts |
| "Home Assistant", "HASS", "Fenton", "Fenton Home", "Smart Home", "Home" | The app's **pages and shortcuts** in Spotlight (Core Spotlight keywords, below). **Not the icon itself**: iOS matches an installed app's icon only by its display name; `CFBundleDisplayName` has one value, and no Info.plist key adds search words to the icon. The first result (a page, such as Security) opens S+H. |
| Siri: "Open Climate in Home Assistant" (or HASS, Fenton Home) | App Shortcut phrases accept the alternative names |

### Core Spotlight pages

`SpotlightCatalog` (HassCore) lists the five sections and the house document's rooms (one per room in the document). Each is a `CSSearchableItem` whose `keywords` are the page's own words plus `AppBranding.searchTerms`, and whose description starts with "S+H". `CoreSpotlightIndexer` (HassUI) replaces the set and deletes the domain at sign-out. `SpotlightReindexer` (HassUI) indexes when a session starts and again whenever the house document changes the entries (it observes `HouseConfigSource.shared` through `SpotlightCatalog.entries(in:)`), one second after the last change and not at all when the entries are as indexed, and stops before sign-out clears the document. A tap arrives as `CSSearchableItemActionType`; `RootView.onContinueUserActivity` hands the identifier to `PushCoordinator.open(spotlightUserInfo:)`, which opens the page like a notification's link, including a launch the tap caused.

### App Shortcuts

`SHShortcuts` (`apple/Apps/iOS/SHShortcuts.swift`) is an `AppShortcutsProvider` with four shortcuts (Open Home, Security, Climate, Chores) over one `OpenPageIntent` whose `perform()` goes through `AppShortcutRouter` to the same open path. Shortcuts need no registration; they exist once the app is installed, and show in Spotlight, Siri and the Shortcuts app. Every phrase contains `\(.applicationName)` (required); `INAlternativeAppNames` extends that to the other names. The intent's `IntentDescription` adds `searchKeywords`.

Apple's note: Siri recognises alternative names for apps that include an Intents extension; an Apple engineer's forum answer says `INAlternativeAppNames` keeps working for App Shortcuts. Verify on a device before relying on the spoken alternatives.

## Tests

- `SpotlightCatalogTests` (HassCore) and `SpotlightTests` and `SpotlightReindexerTests` (HassUI): items, keywords, identifier to destination mapping, indexer lifecycle, router.
- `SpotlightJourneyTests` (UI): `FENTON_OPEN_SPOTLIGHT=<item id>` (debug builds) gives the app the same `NSUserActivity` the system would; each section and a room open their page on iPhone, Duo and iPad.
- Built Release `Info.plist`: `plutil -p …/FentonHome.app/Info.plist` shows `CFBundleDisplayName`, `CFBundleSpokenName`, `INAlternativeAppNames` and the usage strings.
