# ClimateNotice (component)
> **What:** a glyph and text on a module on the Climate page: away, mode and the Automatic Thermostat warning. **Read when:** you change `ClimateNotice` or the notice rules in `ClimateLogic.awayNotice`.
- Mockup: [climate-notice.html](climate-notice.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Climate/ClimateNotice.swift`, `ClimateScreen.swift`, `HassCore/Climate/ClimateLogic.swift` · Spec: `.agents/pages/climate/spec.md`, `ios.md`, `direction-g.md` · Patterns: motion
- States covered: away, vacation, unknown mode (with and without a reason), warning (dense, orange glyph), long-text, ax5; page surface only
- Motion: thin to dense, blue to orange (state 0.6 s)
- Devices: iPhone and iPad size classes (swatches, no device frame)
- Open notes: never used in a sheet (room detail uses a plain Label row), so no sheet surface is drawn
