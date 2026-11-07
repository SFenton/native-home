# Selection tiles (proposal)

> **What:** owner-review proposal for tiles that choose rather than act (Studio sources, Solo Trip travelers, Vacuum Rooms cards): check disc, toggle-styled disc, real switch, or selected face. **Read when:** you build or change any single-choice or ordered multi-select tile, or the owner has picked an option.

- Mockup: [selection-tiles.html](selection-tiles.html) · status `proposed` (awaiting the owner) · reviewed 2026-10-27
- Question (owner, 2026-10-27): "If it's a generic check/uncheck, why not a toggle action instead of a disc?"
- Options: A check disc (`checkmark.circle.fill` / `circle`), B1 toggle-styled disc (Power disc with the item glyph), B2 real iOS `Toggle`, C selected face (family fill plus check disc)
- Cases: Studio sources (one of four), Solo Trip travelers (one of two), Vacuum rooms (multi-select, order numbers 1 to 3)
- States: all three cases on iPhone, Duo and iPad, unavailable, AX5, Reduce Motion; motion: switching the selection, renumbering the order; VoiceOver per option
- Recommendation: C (or A) for single choice, a numbered disc for the vacuum rooms; a toggle is right for independent on/off items (Auto-Reset, guest toggles)
- Source: `apple/Sources/HassDesign/GlassTile.swift`, `Features/Media/MediaScreen.swift`, `Features/Vacation/SoloTripScreen.swift`, `Features/Vacuums/VacuumSheet.swift`
- Related: [action-navigation-tiles](../action-navigation-tiles/action-navigation-tiles.html), [design record](../../../action-navigation-tiles.md), [action-tiles pattern](../../../../patterns/action-tiles.md)
- Helper: `_selection.js` (local; promote to kit if picked). Frozen after the pick; the decision goes in `.agents/design/action-navigation-tiles.md`.
