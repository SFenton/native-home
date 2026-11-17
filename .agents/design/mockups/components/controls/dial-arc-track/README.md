# Dial and arc track (component)

> **What:** the one circular gauge and the one arc with a marker; the weather compass, barometer and sun arc draw through them. **Read when:** you change `UKDialView`, `UKArcTrackView`, `WeatherDialSpecs` or build a control on a dial.

- Mockup: [dial-arc-track.html](dial-arc-track.html) · shipped
- Source: `apple/Sources/HassUI/UIKitPort/Design/UKDialView.swift`, `UKArcTrackView.swift`, `apple/Sources/HassCore/ServerUIComposition/ServerUIDialLayout.swift`, `ServerUIArcLayout.swift`, `apple/Sources/HassCore/Weather/WeatherDialSpecs.swift`
- Spec: `.agents/patterns/dial.md`, `.agents/patterns/weather.md` · Patterns: dial, weather, motion
- States covered: compass, barometer, sun arc, right to left, ax5.
- Motion: the needle turns the short way round (standard 0.3 s); it jumps under Reduce Motion.
- Devices: size class via the Device control.
- Open notes: the drawings are SVG stand-ins; the weather-highlights-tiles mockup still draws its own tiles with local helpers.
