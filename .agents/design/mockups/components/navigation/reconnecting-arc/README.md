# Reconnecting arc and offline chip (component)

> **What:** How the shell signals a stale connection: the header arc while the connection retries, and the offline chip when there is no network path. **Read when:** you touch ReconnectingArc, ReconnectingIndicatorHost, OfflineChip, OfflineOverlay or ReconnectingPolicy.

- Mockup: [reconnecting-arc.html](reconnecting-arc.html) · shipped · reviewed 2026-10-23, source map refreshed 2026-10-28
- Source: `apple/Sources/HassUI/App/Shell/ReconnectingArc.swift`, `ReconnectingIndicatorHost.swift`, `OfflineChip.swift`, `OfflineOverlay.swift`, `ShellHeader.swift`, `apple/Sources/HassCore/Connection/ReconnectingIndicator.swift`, `ReconnectingPolicy.swift`
- Spec: `.agents/design/reconnecting-spinner.md` (decision), `.agents/design/direction-g.md`, `.agents/design/motion.md`, `.agents/platforms/apple/connection-lifecycle.md` · Patterns: motion
- States covered: arc, offline, reduce-motion, timeline, ax5, swatches
- Motion: arc fade 0.35 s, arc turn 0.82 s, offline chip enter 0.3 s; two transitions for the arc, one for the chip
- Devices: iPhone, folded Duo, iPad portrait
- Open notes: the offline chip's move is `.move(edge: .top)`, about the chip's height, not 10 pt. The old orange "Reconnecting…" chip is gone from the app and from this atlas.
