# Sign Out of Home Assistant? (alert) (modal)

> **What:** the alert behind Sign Out on the Your Summary sheet's Profile tab. **Read when:** you change sign-out confirmation copy or presentation.

- Mockup: [sign-out-alert.html](sign-out-alert.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Settings/Profile/YourSummarySheet.swift`, `ProfileTab.swift`
- Spec: `.agents/pages/settings/profile.md`, `.agents/design/direction-g.md`  · Patterns: modal-sheet
- States covered: default, ax5 (dark and light by the Sheet appearance control).
- Motion: None custom. Transition: the alert fades in over the sheet.
- Devices: iPhone, Duo folded and unfolded landscape, iPad portrait and landscape.
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js`, `modals/shell/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: Title Case here, sentence case in the Home Assistant cover (ha-sign-out-dialog).
