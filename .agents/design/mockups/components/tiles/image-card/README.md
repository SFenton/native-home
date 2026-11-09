# Image card (component)
> **What:** the tappable photo card with a caption on a scrim (recipes): 22 pt, 1 : 0.78, a row with a 72 pt thumbnail at accessibility sizes. **Read when:** you show an image-led item in a grid or carousel, or change `ImageCard` or `CachedImage`.
- Mockup: [image-card.html](image-card.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/ImageCard.swift`, `Images/CachedImage.swift`, `Images/ImagePipeline.swift` · Spec: `.agents/patterns/image-card.md`, `image-cache.md` · Patterns: image-card, image-cache, content-gate
- States covered: loaded (title, subtitle), title only, loading, placeholder, selected, three-line title, ax5 row, in the carousel and the grid
- Motion: photo fade-in (quick 0.2 s ease-out, not gated on Reduce Motion); no pressed state
- Devices: size classes via the Device control (iPhone, Duo folded, iPad)
- Open notes: the kit draws the AX thumbnail at 64 pt, the code uses 72 (overridden in `_food.js`); only the Food pages use it today
