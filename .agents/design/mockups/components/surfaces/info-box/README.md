# InfoBox (component)
> **What:** a tinted notice with a title and optional message: success (green) or neutral (grey). **Read when:** you show a confirmed state or an informational banner.
- Mockup: [info-box.html](info-box.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/InfoBox.swift`, `HassUI/Features/Vacation/SoloTripNoticeBox.swift`, `Settings/Feedback/FeedbackFormSheet.swift`, `Vacuums/VacuumMapPanel.swift`
- Spec: `.agents/patterns/info-box.md` · Patterns: info-box, settings-section
- States covered: variants (success, neutral), messages (title only, bullet list, long), in-context (Solo Trip, vacuum sheet, feedback sheet), ax5
- Motion: none
- Devices: iPhone, iPad (size class)
- Open notes: warnings and errors use InlineAlert, not InfoBox; the tint does not animate (a low-priority fix); vacuum condition strings are fixtures.
