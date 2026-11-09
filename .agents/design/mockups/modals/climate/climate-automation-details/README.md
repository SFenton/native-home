# Automation and Tracking detail pages (pushed)
> **What:** the pages pushed from the Automation and Tracking tabs: Predictive Comfort, the two Eco choices and the three room lists. **Read when:** you change `PredictiveComfortDetail`, `EcoOptionDetail` or `TrackingRoomsDetail`.
- Mockup: [climate-automation-details.html](climate-automation-details.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Climate/ClimateAutomationTab.swift`, `ClimateTrackingTab.swift`, `ClimateFormPieces.swift`, `ClimateSheet.swift`, `HassCore/Climate/ClimateLogic.swift`, `ClimateController.swift`, `HassCore/Config/ClimateConfig.swift`
- Spec: `.agents/pages/climate/spec.md`, `ios.md`, `.agents/patterns/modal-sheet.md` · Patterns: modal-sheet, module-list, optimistic-actions, settings-section, motion
- States covered: default (Predictive Comfort), eco-critical, eco-away, eco-unavailable, tracking-selected, tracking-critical, tracking-occupied, tracking-disabled, critical-disabled, loading (deep link), error, offline, large, ax5 and ax5-eco; dark and light side by side
- Motion: Eco checkmark (quick 0.2 s), switch knob and track. Transitions: push from a tab row, pop
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape
- Open notes: room lists swap their circle with no transition (not in motion-components.md); the Weather metric prints the entity id; "Recommendation:" replaces the web's sheet subtitle
