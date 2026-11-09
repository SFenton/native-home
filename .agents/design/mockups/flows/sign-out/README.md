# Sign out (flow)
> **What:** the two ways to sign out (an alert on the Account sheet, a confirmation dialog in Home Assistant settings), the failure alert, and the signed-out intro. **Read when:** you change the sign-out copy, `confirmedSignOut` or either entry point.
- Mockup: [sign-out.html](sign-out.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Settings/Profile/YourSummarySheet.swift`, `ProfileTab.swift`, `Features/Settings/HomeAssistantSettingsView.swift`, `App/AppSession.swift`
- Spec: `.agents/pages/settings/ios.md`, `.agents/pages/settings/profile.md`, `.agents/platforms/apple/auth.md` · Patterns: modal-sheet, motion
- States covered: Account sheet, alert, HA settings, confirmation dialog (action sheet or popover), failed alert, signed-out intro and done, AX5
- Motion: alert in, dialog in, root cross-fade, arrival re-arms; transitions to the alert, to signed out, to the failed alert
- Devices: iPhone, Duo folded and unfolded, iPad (no Location section)
- Open notes: alert vs dialog and "Sign Out of" vs "Sign out of" for one act; no busy state while the server answers; HA settings cover appearance unconfirmed
