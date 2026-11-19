# Settings (tab root) (page)

> **What:** the Settings tab root as built: Vacation and To-Do, Appearance, the household topics, Home Assistant Settings, Performance, Feedback and About (Version) on the wallpaper. **Read when:** you change `HassUI/Features/Settings` or need the Settings list on any device.

- Mockup: [settings.html](settings.html) · shipped (#184; draws the Notifications section in its target form; decided in [setup-flow](../../../../setup-flow.md)) · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/UIKitPort/Features/Settings/UKFeedback.swift`, `apple/Sources/HassUI/Features/Settings/AboutSettingsSection.swift`
- Spec: `.agents/pages/settings/ios.md`, `household.md`, `feedback.md`  · Patterns: settings-section, module-list, page-backdrop
- States covered: default, sam-viewer, blur-changed, icon-badge-off, icon-changed, icon-unsupported, version-copied, reduce-transparency, offline, reconnecting, long-text, ax5 (loading, refreshing, empty and error do not exist).
- Motion: blur-slider (live value, no token), icon-badge-toggle (standard 0.3 s knob, state 0.6 s track). Transitions: push to Performance, Home Assistant cover, feedback and App Icon sheets.
- Devices: iPhone, Duo folded, unfolded portrait and landscape, iPad portrait and landscape (never splits).
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Grouped rows: one module per section, inset hairlines, title3 bold headers, the list at the 16 pt page margin in every window (patterns module-list and settings-section).
- Open notes: the App Icon row's preview and name wait on a publication change; the published page's sections (Home Assistant with Performance, no Notifications) differ from the sections drawn here. Docs: split-view.md still lists Settings as a split.
