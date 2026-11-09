# AlarmPanel and AlarmModeButton (component)
> **What:** the security card: badge, mode as a fact with its start time, four mode buttons. **Read when:** you change the card, a mode button, or how the page and the sheet draw it.
- Mockup: [alarm-panel.html](alarm-panel.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Security/SecuritySystemSheet.swift`, `HassCore/Config/SecurityConfig.swift`, `HassDesign/ColorFamily.swift` · Spec: `.agents/pages/security/ios.md`, `direction-g.md` · Patterns: optimistic-actions, entity-tile, motion
- States covered: default, modes (four), triggered, arming, unavailable, hidden (redacted), since variants, optimistic, ax5; on the page module and on the sheet's cell colour (dark and light)
- Motion: mode fill and badge cross-fade, triggered wash (state 0.6 s, steady), press dim
- Devices: iPhone and iPad size classes (swatches, no device frame)
- Open notes: hidden is derived locally from arming (promote to kit); Quick Links > Security System reuses the card
