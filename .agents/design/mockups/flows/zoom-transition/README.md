# Zoom transition (flow)

> **What:** The designed iOS 18 zoom for a tile that is what it opens; not wired. **Read when:** the owner asks whether to wire zoom, or you touch ZoomTransition.swift.

- Mockup: [zoom-transition.html](zoom-transition.html) · designed, not wired (shown as proposed) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/Motion/ZoomTransition.swift`, `apple/Sources/HassUI/Features/Home/CameraGrid.swift`, `apple/Sources/HassUI/Features/Cameras/CameraViewer.swift`
- Spec: `.agents/design/motion.md`, `.agents/patterns/motion.md` · Patterns: motion, image-card
- States covered: tile-source, mid-zoom, destination, reduce-motion-cross-fade, today-camera-sheet, ios17-fallback, ax5
- Motion: zoom open and close; three transitions
- Devices: iPhone, folded Duo, iPad portrait
- Open notes: No call sites for zoomSource or zoomDestination. The docs disagree about where it applies; the owner said none inside sheets (2026-10-22). Draw only if re-confirmed.
