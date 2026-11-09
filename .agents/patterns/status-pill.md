# Status pill

> **What:** a read-only labeled value with a toned icon. **Read when:** showing a status value (battery, next run, connection) that is not a control.

- `StatusPill(label:value:detail:symbol:tone:)` (`HassDesign/StatusPill.swift`, web `src/components/core/StatusPill.tsx`). Tones: neutral, ok (`Ink.success`), active (`Tint.water`), warning (`Ink.warning`), danger (`Ink.danger`), unavailable (`Ink.unavailable`, 4.5:1 or better on every ground); the tone colors the icon only, text stays `HassTokens.Ink`. The humidifier sheet's `DeviceStatusPill` (a 24 pt icon column on the sheet cell, the icon above the text at accessibility sizes) and the vacuum map's `VacuumStatusChip` (a value-only capsule) are different shapes, not copies; they share the tone tokens.
- One accessibility element: label, then "value, detail". Not a button; never put an action on it (use `GlassTile`).
- Lay pills out in a `DynamicGridLayout` (about 150 pt minimum, scaled with Dynamic Type) so they wrap at large text sizes.
- First used by Sprinklers.
- In a grouped `List` (for example a sheet), pass `surface: .groupedList`, which draws a solid row fill. A material over a sheet's glass smeared the content behind it (seen 2026-10-11 in the sprinkler sheet).
- Lay-out sizes: pill titles are `.footnote` or larger, never `.caption` (owner, 2026-10-24: value text stays off the smallest styles).
