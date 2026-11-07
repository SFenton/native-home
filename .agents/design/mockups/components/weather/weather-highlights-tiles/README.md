# Weather sheet: highlight and metric tiles (component)
> **What:** the Highlights grid: AQI, precipitation and accumulation, humidity and cloud cover charts, feels like, UV, wind compass, sun arc, visibility, pressure gauge. **Read when:** you change any `Weather*Tile`, the compass, gauge, rail or bar chart.
- Mockup: [weather-highlights-tiles.html](weather-highlights-tiles.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Home/Weather/WeatherHighlightsPanel.swift`, `WeatherHighlightTile.swift`, `WeatherTile.swift`, `WeatherMetricTile.swift`, `WeatherWindTile.swift`, `WeatherCompass.swift`, `WeatherPressureGauge.swift`, `WeatherSunArc.swift`, `WeatherBarChart.swift`, `WeatherRail.swift` · Spec: `.agents/patterns/weather.md`, `.agents/patterns/dynamic-grid.md`
- States covered: all (the grid), wind (four bearings and calm), pressure, sun, AQI (six bands), rails, charts, unavailable, no-AQI, ax5
- Motion: compass needle (standard 0.3 s, short way round), rail marker. Transitions: none
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad (two tracks on a phone, four on the 704 pt page sheet; one at AX5)
- Open notes: not Swift Charts (plain bars so axis labels scale); sun times are stand-ins; promote the compass, gauge, sun arc and rail builders and five icons to the kit
