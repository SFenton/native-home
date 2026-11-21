# Climate (page)
> **What:** the Climate tab: the Whole Home thermostat dial on the wallpaper, the Thermostat Hub pill, notices, open contact sensors and the three Advanced Controls rows. **Read when:** you change `ClimatePage`, the dial's page use, the hub pill or the notices, or need the page's states on every device.
- Mockup: [climate.html](climate.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/UIKitPort/Features/Climate/UKClimateParts.swift`, `apple/Sources/HassUI/Controls/Thermostat/ClimateThermostatDial.swift`
- Spec: `.agents/pages/climate/spec.md`, `ios.md`, `.agents/patterns/thermostat-dial.md` · Patterns: thermostat-dial, module-list, dynamic-grid, modal-sheet, motion
- States covered: default (heating, a window open), loading, refreshing, empty (nothing open), error, offline, reconnecting (arc), long-text, cooling, idle, off, away (eco thermostat, notice, warning), integration-off, hub-menu, ax5
- Motion: dial handles glide (quick 0.2 s), status colour on the dial and hub glyph (state 0.6 s), warning notice. Transitions: Advanced Controls sheet, tab cut, hub pop-up menu
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape; one 720 pt column; partly folded Duo: fold columns (Whole Home leads; contacts, Advanced Controls trail)
- Open notes: numerals do not roll in the code (docs say they do); arcs step while handles glide (RingArc has no animatableData; confirm on a device); the kit's `.k-wrap h2` leaks into `.ui-hdr h2` (worked around in the shared helper)
- Partly folded Duo: when the Studio sets the page to Two Sides, each section sits wholly on one side ([section-sides](../../../../section-sides.md)), at every text size; a page left on One Column draws its flat layout with the band. State `duo-part-fold`. Every other pose unchanged.
