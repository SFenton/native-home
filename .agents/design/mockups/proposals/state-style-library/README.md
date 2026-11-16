# Studio style library (proposal)
> **What:** how the Studio lists, edits and applies state styles, and how a tile overrides a layer. **Read when:** you build style authoring in the Studio or change what a style holds.
- Mockup: [state-style-library.html](state-style-library.html) · status proposed
- Source: `apple/Sources/HassCore/TileActions/StateStyle.swift` (the shipped look the preview draws) · Spec: `.agents/design/state-styles.md`, `.agents/design/state-styled-tile.md` · Patterns: action-tiles
- States covered: the library with a built-in style, a saved style in use, a tile with two overridden layers
- Motion: picking a state in the preview plays the tile's own transition at iPhone, Duo and iPad widths
- Devices: a desktop web tool; the preview shows the three families
- Open notes: content and behaviour only; the Studio draws it with its own panels and controls
