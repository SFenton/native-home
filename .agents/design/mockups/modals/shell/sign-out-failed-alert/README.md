# Sign Out couldn't complete (alert) (modal)

> **What:** the title-only alert after a failed sign-out, on the Summary sheet and the Home Assistant cover. **Read when:** you change the sign-out failure path.

- Mockup: [sign-out-failed-alert.html](sign-out-failed-alert.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Settings/Profile/YourSummarySheet.swift`, `HomeAssistantSettingsView.swift`
- Spec: `.agents/pages/settings/profile.md`, `.agents/pages/settings/ios.md`  · Patterns: modal-sheet
- States covered: default (over the Summary), from-ha-settings (over the cover), ax5.
- Motion: None custom.
- Devices: iPhone, Duo folded and unfolded landscape, iPad portrait and landscape.
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js`, `modals/shell/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: The alert does not say why it failed (review finding). The literal copy is duplicated in two files.
