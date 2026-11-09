# CachedImage and RemoteImage (component)
> **What:** how remote pictures load, cache, fall back and update without flicker. **Read when:** you draw any remote image.
- Mockup: [remote-image.html](remote-image.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/Images/CachedImage.swift`, `apple/Sources/HassDesign/Images/ImagePipeline.swift`, `apple/Sources/HassDesign/ImageCard.swift` · Spec: .agents/patterns/image-cache.md, image-card.md, content-gate.md · Patterns: image-cache, image-card, content-gate, motion
- States covered: frame states, in cards, how a changed image updates (playable), layers, gated, loading, error, ax5
- Motion: first image fade (quick 0.2 s), new key cross-fade, same key swap (none)
- Devices: iPhone and iPad size classes
- Open notes: photos are stand-ins
