# InlineAlert and SelectableOptionRow (component)

> **What:** The inline warning or error under a control, and the single-choice option row. **Read when:** showing a message beside a control or a single-choice list.

- Mockup: [settings-controls.html](settings-controls.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/SettingsSection.swift`
- Spec: `.agents/patterns/settings-section.md`, `.agents/patterns/info-box.md` · Patterns: settings-section, info-box
- States covered: variants (warning, error), alerts (custom symbol, multi-line), options (selected, disabled, tinted), option list, ax5; sheet surface.
- Motion: option select (state 0.6 s, checkmark quick 0.2 s), disabled dim (quick).
- Devices: size class via the Device control.
- Open notes: The catalog hint "info" severity does not exist in code (warning and error only). The kit row lacks tint and disabled; decorated locally.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
