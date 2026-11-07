# Custom light sheet (modal)
> **What:** One light's sheet: brightness tile, system colour picker row, Reset to Warm White, Apply to All Lights, Copy Color From. **Read when:** you change `CustomLightSheet`.
- Mockup: [custom-light-sheet.html](custom-light-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/CustomLights/CustomLightSheet.swift`, `HassCore/Config/CustomLightsConfig.swift`, `HassDesign/BrightnessTile.swift` · Spec: `.agents/pages/custom-lights/ios.md`, `.agents/patterns/modal-sheet.md` · Patterns: modal-sheet, entity-tile, module-list
- States covered: default (colour), loading/error (unavailable), offline, white, off, medium, large, fitted, closed, ax5; dark and light
- Motion: band glide (quick), swatch colour (state); transitions: present, dismiss, system colour picker (not drawn)
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (page sheet)
- Open notes: no loading state (reads the store); uses the system ColorPicker; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
- Rollout L (2026-10-28): the sheet's brightness tile is an action tile with a `power` disc (text, disc, no chevron); the body keeps tap = power and the horizontal drag.
