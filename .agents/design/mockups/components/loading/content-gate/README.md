# ContentGate (component)
> **What:** how a network-backed page or region waits: hidden content, spinner after 150 ms, fade in and 4 pt rise. **Read when:** you gate a page or sheet, or change the loading profiles.
- Mockup: [content-gate.html](content-gate.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/Loading/ContentGate.swift`, `apple/Sources/HassDesign/Loading/ContentGateModel.swift`, `apple/Sources/HassDesign/Loading/ReadinessTracker.swift` · Spec: .agents/patterns/content-gate.md, .agents/design/motion.md · Patterns: content-gate, image-cache, motion
- States covered: phases, both profiles playable with Reduce Motion variants, timing profiles, reopen (starts ready), Food hub context, ax5
- Motion: .results, .page, reload (170 ms out, then repeat)
- Devices: iPhone and iPad size classes
- Open notes: .page holds the spinner at least 1 s (recorded HIG departure)
