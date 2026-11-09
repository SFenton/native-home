# Weather sheet: hourly panel (component)
> **What:** the Conditions panel: 24 hours in three modes (conditions, precipitation, wind) with a 44 pt icon picker. **Read when:** you change `WeatherHourlyPanel`, `WeatherModalHour` or the carousel.
- Mockup: [weather-hourly-panel.html](weather-hourly-panel.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Home/Weather/WeatherHourlyPanel.swift`, `WeatherHourlyMode.swift`, `WeatherModalHour.swift`, `WeatherModalHourPlaceholder.swift`, `WeatherPagedCarousel.swift` · Spec: `.agents/patterns/weather.md` · Patterns: weather, motion
- States covered: conditions, precipitation, wind, loading (placeholders), error and empty, stale-error, ax5; rain and sunny gradients
- Motion: mode switch (quick content swap), page paging. Transitions: none
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad (5 hours a page compact, 7 regular with Previous and Next)
- Open notes: patterns/weather.md says `scrollTargetBehavior(.paging)`, the code uses a UIKit PagedRow; no long-text state (cells hold short numerals)
