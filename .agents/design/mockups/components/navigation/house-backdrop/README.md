# House photo backdrop (component)

> **What:** The blurred house photo, scrim and fallbacks behind every page. **Read when:** you touch pageChrome(), HouseBackdrop, BackdropRenderer or Settings > Background Blur.

- Mockup: [house-backdrop.html](house-backdrop.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Common/HouseBackdrop.swift`, `apple/Sources/HassUI/Common/BackdropRenderer.swift`, `apple/Sources/HassCore/Settings/BackdropBlur.swift`
- Spec: `.agents/patterns/page-backdrop.md`, `.agents/design/direction-g.md`, `.agents/design/motion.md` · Patterns: page-backdrop, image-cache
- States covered: blur-50, blur-0, blur-100, blur-compare (0/25/50/75/100), reduce-transparency-plain, no-photo-base, increase-contrast, scrim table, ax5
- Motion: arrival settle, photo arrives, live re-render while the slider drags; push shows one picture
- Devices: iPhone, folded Duo, iPad (portrait, landscape)
- Open notes: Photo and blur are kit stand-ins (a CSS drawing and an SVG Gaussian at the real sigma); the scrim stops are exact. SN.wallpaperBlur is a local helper to promote.
