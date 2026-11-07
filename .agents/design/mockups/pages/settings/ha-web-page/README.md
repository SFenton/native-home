# Home Assistant web page (pushed in the settings cover) (page)

> **What:** Home Assistant's own Settings or Profile page in a WKWebView, pushed inside the Home Assistant cover. **Read when:** you change `HomeAssistantWebPage.swift` or the sign-in hand-off.

- Mockup: [ha-web-page.html](ha-web-page.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/HomeAssistantWebPage.swift`, `HomeAssistantSettingsView.swift`
- Spec: `.agents/pages/settings/ios.md`, `.agents/platforms/apple/auth.md`  · Patterns: modal-sheet
- States covered: default (settings), profile, loading, refreshing (reload), preparing, error, offline, ax5. The web content is a labelled stand-in.
- Motion: web-progress (arc over the page, 0.82 s a turn). Transition: push inside the cover.
- Devices: iPhone, Duo folded and unfolded landscape, iPad portrait and landscape.
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: Cover grounds (#000 / #1C1C1E) and the dark scheme are inferred, not confirmed in the simulator. Live pages stay out of the repo.
