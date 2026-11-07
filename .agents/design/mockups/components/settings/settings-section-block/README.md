# Settings section (component)

> **What:** SettingsSection: heading, description paragraphs and controls; page and sheet inks. **Read when:** building a settings-style page or checking the paragraph contrast rule.

- Mockup: [settings-section-block.html](settings-section-block.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/SettingsSection.swift`
- Spec: `.agents/patterns/settings-section.md`, `.agents/patterns/info-box.md` · Patterns: settings-section, info-box
- States covered: title only, one paragraph, two paragraphs and a warning, stacked sections, ax5; page and sheet surfaces.
- Motion: none of its own (empty list, explained).
- Devices: size class via the Device control.
- Open notes: The pattern record says paragraphs use Ink.secondary; the code uses fixed white on a page (contrast fix). Car repeats the header by hand.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
