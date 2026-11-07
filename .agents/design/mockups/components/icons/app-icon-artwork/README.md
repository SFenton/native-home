# App icon artwork (component)
> **What:** the eight tinted-glass app icons, their dark and tinted appearances, the picker and the one-colour HouseHeartShape. **Read when:** you change `AppIconArtwork`, the icon picker or the Live Activity corner mark.
- Mockup: [app-icon-artwork.html](app-icon-artwork.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/AppIconArtwork.swift`, `apple/Sources/HassDesign/HouseHeartShape.swift`, `apple/Sources/HassUI/Features/Settings/AppIcon/AppIconPreview.swift` · Spec: .agents/design/direction-g.md, .agents/platforms/apple/app-name.md · Patterns: modal-sheet
- States covered: eight icons, appearances, sizes, picker (2, 3 or 1 column), corner mark, layers, ax5
- Motion: selection ring (state 0.6 s)
- Devices: iPhone and iPad size classes
- Open notes: motion-components.md says quick; code uses state
