# PendingValueBar (component)
> **What:** the soft pulsing bar where a tile's value will go on the first sign-in. **Read when:** you change first-run placeholders or tile values.
- Mockup: [pending-value-bar.html](pending-value-bar.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/PendingValue.swift` · Spec: .agents/design/direction-g.md, .agents/design/motion.md, .agents/patterns/entity-tile.md · Patterns: entity-tile, content-gate, motion
- States covered: pending, arrived, anatomy and Reduce Motion, measured pulse, value arrives, relaunch, loading, ax5
- Motion: pulse (0.35 to 1 over 1.4 s, static 0.65 under Reduce Motion), value arrives
- Devices: iPhone and iPad size classes
- Open notes: the kit's StatusChip pending and Skeleton have no SwiftUI counterpart
