# App Icon picker (modal)

> **What:** the fitted form sheet with the eight icons, the installed one ringed and checked. **Read when:** you change `HassUI/Features/Settings/AppIcon` or `AppIconArtwork`.

- Mockup: [app-icon-picker-sheet.html](app-icon-picker-sheet.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/AppIcon/AppIconPickerSheet.swift`, `AppIconChoiceButton.swift`, `AppIconPickerModel.swift`, `apple/Sources/HassDesign/AppIconArtwork.swift`
- Spec: `.agents/design/direction-g.md`, `.agents/design/apple/iphone.md`, `.agents/pages/settings/ios.md`  · Patterns: modal-sheet
- States covered: default, other-selected, loading (changing), error (failure alert), offline, medium, large, fitted, ax5 (dark and light).
- Motion: selection-ring (state 0.6 s, 0.2 s reduced), system notice (iOS-owned).
- Devices: iPhone, Duo folded and unfolded landscape, iPad portrait and landscape (form sheet).
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: Icon art is redrawn from AppIconArtwork's geometry; dark and tinted Home Screen versions are the system's.
