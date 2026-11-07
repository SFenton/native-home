# ThermostatHubPill and HubPicker (component)
> **What:** the physical thermostat's pill with mode and fan pop-up menus. **Read when:** you change `ThermostatHubPill`, `HubPicker`, or the hub's menus.
- Mockup: [thermostat-hub-pill.html](thermostat-hub-pill.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Climate/ClimateHubPill.swift`, `HassCore/Climate/ClimateLogic.swift`, `ClimateController.swift`, `HassCore/Config/ClimateConfig.swift` · Spec: `.agents/pages/climate/spec.md`, `ios.md` · Patterns: optimistic-actions, motion
- States covered: default, glyph by action (heating, cooling, idle), off, no fan, mode menu, fan menu, unavailable, ax5 (stacked, value text); page surface
- Motion: glyph tint (state 0.6 s), system menu
- Devices: iPhone and iPad size classes (swatches, no device frame)
- Open notes: heat_cool reads "Heat Cool" in the pill and "Heat/Cool" in the menu; the menu popover is a stand-in
