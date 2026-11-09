# Guests Staying Over section (component)
> **What:** the header, footnote and three occupancy tiles that appear on Home and Security only while a guest toggle is on. **Read when:** you change `GuestPresenceSection` or the guest toggles.
- Mockup: [guest-presence-section.html](guest-presence-section.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Home/GuestPresenceSection.swift`, `HomeScreen.swift`, `HassCore/Config/HomeConfig.swift`, `HassDesign/GlassTile.swift` · Spec: `.agents/pages/home/spec.md`, `.agents/pages/security/ios.md` · Patterns: entity-tile, dynamic-grid
- States covered: one-on, all-on, hidden (nothing drawn), error (a toggle unavailable), loading (not drawn before state arrives), narrow (the Duo's trailing pane), ax5
- Motion: tile fill (0.6 s state colour). The section itself appears with no animation. Transitions: none
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad
- Open notes: first pass only (stay toggles, no extra security copy); no spinner, it follows the snapshot
