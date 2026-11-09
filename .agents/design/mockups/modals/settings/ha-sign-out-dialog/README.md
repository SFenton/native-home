# Sign out of Home Assistant? (confirmation dialog) (modal)

> **What:** the confirmationDialog on the cover's Sign Out: an anchored popover (iOS 26+) or an action sheet (iOS 17 to 25). **Read when:** you change the cover's sign-out confirmation.

- Mockup: [ha-sign-out-dialog.html](ha-sign-out-dialog.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/HomeAssistantSettingsView.swift`
- Spec: `.agents/pages/settings/ios.md`  · Patterns: modal-sheet
- States covered: default (popover), action-sheet, ax5. loading, error, offline and detents do not apply.
- Motion: None custom (the system presents it).
- Devices: iPhone, Duo folded and unfolded landscape, iPad portrait and landscape (regular width is always a popover).
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: Copy and spelling differ from the Account sheet alert (sign-out-alert). Popover geometry is the system's.
