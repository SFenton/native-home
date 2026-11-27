# ContentGate (component)
> **What:** how a page or region waits, and how an opted-in sheet reveals its root after presentation. **Read when:** you gate a page or sheet, or change the loading profiles.
- Mockup: [content-gate.html](content-gate.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/UIKitPort/Design/UKContentGate.swift`, `apple/Sources/HassDesign/Loading/ContentGateModel.swift`, `apple/Sources/HassDesign/Loading/ReadinessTracker.swift` · Spec: .agents/patterns/content-gate.md, .agents/design/motion.md · Patterns: content-gate, image-cache, motion
- States covered: page and results phases, playable Reduce Motion variants, timings, grouped sheet reveal (chrome only, ready, slow load), ready reopen, Food hub context, AX5
- Motion: .results, .page, reload (170 ms out, then repeat)
- Devices: iPhone and iPad size classes
- Open notes: .page holds the spinner at least 1 s (recorded HIG departure)
