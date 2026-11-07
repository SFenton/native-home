# Advanced Controls sheet (Rooms, Automation, Tracking)
> **What:** the large page sheet the Climate rows open, with a section tab bar and pushed detail levels. **Read when:** you change `ClimateSheet`, its three tabs, or the section tab bar.
- Mockup: [climate-sheet.html](climate-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Climate/ClimateSheet.swift`, `ClimateFormPieces.swift`, `ClimateRoomsTab.swift`, `ClimateAutomationTab.swift`, `ClimateTrackingTab.swift`, `ClimateScreen.swift`, `HassUI/Common/ModalTabBar.swift`, `ModalTabSymbols.swift`, `HassCore/Config/ClimateConfig.swift`, `HassCore/Climate/ClimateLogic.swift`
- Spec: `.agents/pages/climate/spec.md`, `ios.md`, `.agents/patterns/modal-sheet.md` · Patterns: modal-sheet, thermostat-dial, module-list, dynamic-grid, optimistic-actions, motion
- States covered: default (Rooms), automation, tracking, tracking-off, automation-off, pushed, loading (and automation), error, offline, reconnecting, large (shipped), closed, ax5 (menu tabs) and ax5-automation; dark and light side by side. medium and fitted are never used (explained in notes)
- Motion: switch knob and track, tab cut, segment selection. Transitions: present, push to a room, pop, push to Eco, dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape (page sheet; titles on the tab bar instead of icons)
- Open notes: Form approximated with kit rows; "1 rooms forced" is not pluralised in the code; spec's three-column page entries are not built
