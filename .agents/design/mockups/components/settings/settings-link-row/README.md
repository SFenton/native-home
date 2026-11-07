# Settings link row (glyph, title, wrapping subtitle) (component)

> **What:** SettingsLinkRow on the page and sheet surfaces: glyph or app icon preview, title, wrapping subtitle, chevron. **Read when:** you change `SettingsLinkRow` or a Settings row.

- Mockup: [settings-link-row.html](settings-link-row.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/SettingsScreen.swift`, `SettingsSectionHeader.swift`, `AppIcon/AppIconSettingsRow.swift`
- Spec: `.agents/patterns/settings-section.md`, `.agents/patterns/module-list.md`, `.agents/pages/settings/ios.md`  · Patterns: settings-section, module-list
- States covered: default, no-chevron, app-icon, long-text, feedback, ax5 (icon above text).
- Motion: None.
- Devices: Size classes: iPhone and iPad portrait.
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: Drawn with SA.link in pages/settings/_settings-account.js; promote to kit.
