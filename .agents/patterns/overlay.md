# Overlay

> **What:** small nodes drawn over a base at five anchors. **Read when:** a document node puts a readout, text or a control over a tile, or a pill or text over a map.

- `sh.overlay@1`: the first child is the base; up to four nodes sit on top, one per anchor (the four corners and the centre), each with the author's inset. `ServerUILayoutCompiler` checks the anchors; `UKServerUIOverlayView` (`HassUI/UIKitPort/ServerUI/UKServerUIOverlay.swift`) draws them.
- **A button over a map is a map control ([map-controls](map-controls.md)), never an overlay child.** Over a map the overlay holds a status pill or text only. The map frame owns Locate, the fit rule, the More menu and the map's own state rules; an overlay child can do none of them.
- The overlay is the height of its base. A node on top keeps its natural size, at least 44 by 44 pt (HIG, Buttons), and takes a touch before the base.
- `leading` and `trailing` are logical edges and swap in a right-to-left language (HIG, Right to left).
- VoiceOver reads the base, then the top row, the centre, the bottom row.
- A node on top draws no plate of its own; over a map its ink must hold contrast without one (HIG, Maps).
- Tests: `ServerUILayoutTests`, `ServerUILayoutCorpusTests`, `ServerUILayoutHostedTests` (a pill over a map beside Locate).
