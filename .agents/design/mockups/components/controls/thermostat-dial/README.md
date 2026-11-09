# ThermostatDial (component)
> **What:** the 270 degree thermostat control: range or single target, marker, readout. **Read when:** you change the dial, show a thermostat anywhere, or reuse its geometry.
- Mockup: [thermostat-dial.html](thermostat-dial.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/ThermostatDial/ThermostatDial.swift`, `ThermostatDialGeometry.swift`, `ThermostatDialModel.swift`, `HassUI/Controls/Thermostat/ClimateThermostatDial.swift` · Spec: `.agents/patterns/thermostat-dial.md`, `direction-g.md` · Patterns: thermostat-dial, optimistic-actions, motion
- States covered: range, single, off, unavailable, read-only, dragging, sizes (316, 300, 250), interactive (drag; arrow keys stand in for VoiceOver's adjust action), ax5; page and sheet surfaces
- Motion: handle glide (quick 0.2 s), drag (none, haptics), status colour (state 0.6 s)
- Devices: iPhone and iPad size classes (swatches, no device frame)
- Open notes: drawn by the local `SecClimate.dial` (the kit's draws only the range look; promote it); docs say numerals roll, the code does not; arcs step while handles glide
