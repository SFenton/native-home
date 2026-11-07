# StatusPill (component)
> **What:** a read-only labelled value with a toned icon (battery, next watering, hub), on a page material, a sheet's solid row fill or inside a module. **Read when:** you show a status value that is not a control, or change StatusPill or the Sprinklers cards.
- Mockup: [status-pill.html](status-pill.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/StatusPill.swift`, `HassUI/Features/Sprinklers/{SprinklersScreen,SprinklerControllerSheet}.swift`
- Spec: `.agents/patterns/status-pill.md`, `dynamic-grid.md` · Patterns: status-pill, dynamic-grid, module-list
- States covered: variants (six tones on page and sheet from the kit), surfaces (page, grouped list, module, detail line), in-context (Sprinklers page, low battery, controller sheet), ax5
- Motion: tone cross-fade (0.6 s, 0.2 s reduced)
- Devices: iPhone, iPad (size class), embedded devices
- Open notes: tone icons use system .green and .orange, not the HassTokens inks (a fix finding); the module surface has no fill (the kit makes it transparent); sprinkler values are fixtures; humidifier and vacuum sheets use their own pill components.
