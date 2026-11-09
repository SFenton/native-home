# Flyout navigation (flow)

> **What:** Opening, choosing from and closing the drawer, with focus handling. **Read when:** you touch the flyout, the edge swipe or VoiceOver focus around it.

- Mockup: [flyout-navigation.html](flyout-navigation.html) · shipped (#140) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/Shell/NavigationFlyout.swift`, `apple/Sources/HassUI/App/Shell/ShellNavigator.swift`, `apple/Sources/HassUI/App/Shell/ShellHeader.swift`
- Spec: `.agents/design/apple/ipados.md`, `.agents/design/direction-g.md`, `.agents/design/apple/iphone.md`, `.agents/design/motion.md` · Patterns: motion
- States covered: closed, edge-swipe, tap-menu, opening, open, scrim-tap-closes, voiceover-focus-return, destination-chosen, chores-badge, ax5
- Motion: slide and scrim, edge swipe, focus handoff; three transitions
- Devices: iPhone, unfolded Duo portrait (both hinge poses), iPad (both)
- Open notes: No folded-Duo or unfolded-landscape variant (vertical bar, no menu button). The edge swipe opens on release; the drawer does not follow the finger.
