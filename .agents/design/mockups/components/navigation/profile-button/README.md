# Profile button (component)

> **What:** The trailing-most header button: monogram, attention badge, offline badge. **Read when:** you touch ProfileButton, ShellAttention or the header buttons.

- Mockup: [profile-button.html](profile-button.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/Shell/ShellHeader.swift`, `apple/Sources/HassUI/App/Shell/ShellAttention.swift`, `apple/Sources/HassUI/App/Shell/ShellHeaderGrouping.swift`
- Spec: `.agents/design/direction-g.md`, `.agents/pages/settings/profile.md`, `.agents/design/apple/duo.md` · Patterns: motion (badge fade not done)
- States covered: monogram, symbol-until-name-known, badges (1, 9, 9+), offline-badge, rail-person-symbol, pre-ios26, in-header, ax5, plus the kit variants
- Motion: none today; the 0.2 s badge fade is planned; one sheet transition (Your Summary)
- Devices: iPhone, folded Duo, iPad portrait
- Open notes: iOS 26.5 differs from iOS 27 by 4 pt of gap (drawn: iOS 27). Bar items do not scale at AX5; the Large Content Viewer is the system answer.
