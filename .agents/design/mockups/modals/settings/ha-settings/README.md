# Home Assistant settings (full-screen cover) (modal)

> **What:** the full-screen cover behind the Home Assistant Settings row: server, account, web page links and Sign Out. **Read when:** you change `HomeAssistantSettingsView.swift` or the sign-in and sign-out flow.

- Mockup: [ha-settings.html](ha-settings.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/HomeAssistantSettingsView.swift`, `SettingsScreen.swift`, `HomeAssistantWebPage.swift`
- Spec: `.agents/pages/settings/ios.md`, `.agents/design/apple/split-view.md`, `.agents/platforms/apple/auth.md`  · Patterns: modal-sheet, settings-section
- States covered: default, loading, error, offline, reconnecting, rejected, user, owner, confirm (popover), confirm-sheet, failed, ax5. No detents (a full-screen cover).
- Motion: None. Transitions: cover up and down, the confirmation popover, push to the web page.
- Devices: iPhone, Duo folded and unfolded landscape, iPad portrait and landscape (single page everywhere).
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: Drawn dark (inherited from the shell, unverified in the simulator). Sign-out confirmation is a confirmationDialog here and an alert in the Account sheet.
