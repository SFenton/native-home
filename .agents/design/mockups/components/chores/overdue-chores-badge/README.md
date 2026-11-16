# Overdue chores badge (tab, flyout, profile) (component)
> **What:** the overdue count on the Chores tab, flyout row and Profile button. **Read when:** you change the badge, its count source or its spoken label.
- Mockup: [overdue-chores-badge.html](overdue-chores-badge.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/Shell/ShellAttention.swift`, `apple/Sources/HassUI/UIKitPort/App/Shell/UKProfileButton.swift` (the publication authors the layout) · Spec: `.agents/pages/chores/ios.md`, `design/apple/ipados.md` · Patterns: none
- States covered: parts by count, tab and rail, none, flyout, non-resident, ax5
- Motion: none
- Devices: iPhone, Duo, iPad (the Device control picks the size class)
- Open notes: kit TabBar caps at 9+, the system tab badge and flyout print the number.
