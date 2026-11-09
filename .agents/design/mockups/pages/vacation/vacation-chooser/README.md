# Vacation (chooser) (page)

> **What:** Settings > Vacation: the two-row chooser between Vacation and Solo Trip. **Read when:** you change the chooser or the engaged-mode skip.

- Mockup: [vacation-chooser.html](vacation-chooser.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Vacation/VacationScreen.swift`, `HassUI/Features/Settings/SettingsScreen.swift`
- Spec: `.agents/pages/vacation/spec.md`, `ios.md` · Patterns: module-list, settings-section
- States covered: default, setup required, engaged (skip), offline, reconnecting, AX5.
- Motion: system push from Settings and into a mode.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape.
- Open note: Rows lack the listRowBackground the Settings list sets (review fix).
- Open note: Helper `pages/vacation/_vacation-sprinklers.js` holds copy, fixtures and builders for every vacation item.
