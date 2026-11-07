# Status chip (component)
> **What:** one capsule of the status rail: glyph, title, one-line state, filled by family or a computed colour. **Read when:** you change `StatusChipButton`, `StatusChipAppearance`, `ChipTint` or add a chip rule.
- Mockup: [status-chip.html](status-chip.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Home/StatusRail.swift`, `StatusChipAppearance.swift`, `apple/Sources/HassDesign/ChipTint.swift`, `ColorFamily.swift` · Spec: `.agents/patterns/status-rail.md`, `.agents/design/direction-g.md` · Patterns: status-rail, status-pill
- States covered: every kit variant (lights, five security modes, climate gradient, AQI, occupancy, four contact states), unavailable, pending, neutral, lights on, security modes, climate, occupancy, contacts, air quality, inert (no sheet), redacted (Hidden), long text, a contrast table (white on fill, glyph on fill), ax5
- Motion: chip colour cross-fade (0.6 s), neutral to filled, climate colour. Transition: opens a sheet (see Home)
- Devices: size class only (iPhone, Duo, iPad)
- Open notes: the kit keeps the state on one line (the app can wrap it in a narrow window); the AQI palette is a stand-in for the helper colour
