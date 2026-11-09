# Appearance section (Background Blur, count badge, App Icon) (component)

> **What:** the Appearance section of the Settings list on the page and sheet surfaces. **Read when:** you change `AppearanceSettingsSection.swift` or `PercentSliderRow`.

- Mockup: [appearance-settings-section.html](appearance-settings-section.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/Appearance/AppearanceSettingsSection.swift`, `apple/Sources/HassUI/Features/Food/RecipesScreen.swift`
- Spec: `.agents/pages/settings/ios.md`, `.agents/patterns/page-backdrop.md`, `.agents/patterns/settings-section.md`  · Patterns: page-backdrop, settings-section
- States covered: default, blur-changed, reduce-transparency, icon-badge-off, icon-unsupported, icon-changed, ax5.
- Motion: blur-drag (value render, no token), badge-toggle (standard and state).
- Devices: Size classes: iPhone and iPad portrait (the device control).
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: PercentSliderRow lives in the Food folder and is shared with the recipe filter.
