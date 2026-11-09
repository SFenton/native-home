# Info box

> **What:** a tinted notice with a title and optional message. **Read when:** a page shows a confirmed state or an informational banner.

- Canonical component: `HassDesign/InfoBox.swift`. Web: `src/components/core/InfoBox.tsx`.
- Tones: `.success` (green, only for a state Home Assistant has confirmed) and `.neutral` (gray). Text stays in the primary label color on a 16% wash of the tone, so it keeps 4.5:1 in light and dark; the icon carries the tint.
- One accessibility element (title and message combined).
- Consumers: Solo Trip "<Traveler> Away" notice; the feedback form's "Reporting isn't set up yet" notice ([feedback](../pages/settings/feedback.md)).
- Warnings use `InlineAlert` (`HassDesign/SettingsSection.swift`): orange triangle (or a warning's own `symbol`), primary ink on a 14% orange wash, read as "Warning: …". Consumers: admin relay warning, humidifier fault, targets and schedules, sprinkler errors and low battery. It replaced `DeviceAlert` and `SprinklerAlert` (audit 2026-10-13). Errors use `InlineAlert(_:severity: .error)`: red `Ink.error` text with no box, read as "Error: …" (Vacation and Solo Trip; it replaced `AwayInlineAlert`). Do not add another alert view: the Bedroom sheets' own `BedroomNotice` was removed (2026-10-24) for `InlineAlert` and `InfoBox`. The wash opacities are `HassTokens.Wash.alert` (14%) and `.notice` (16%), drawn in `Ink.warning` / `Ink.success` / `Ink.secondary`, which adapt to appearance and contrast.
