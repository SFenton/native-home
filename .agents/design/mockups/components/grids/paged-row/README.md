# PagedRow (native paging row) (component)
> **What:** the UIKit-hosted paging row of equal cells (hourly weather) with its page indicator and, on regular width, previous and next buttons. **Read when:** you change PagedRow, WeatherPagedCarousel or the hourly weather layout.
- Mockup: [paged-row.html](paged-row.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/{PagedRow,PagedRowMetrics,NativePaging,HostedHorizontalScroll}.swift`, `HassUI/Features/Home/Weather/{WeatherPagedCarousel,WeatherCarouselPaging,WeatherHourlyPanel}.swift`
- Spec: `.agents/patterns/resume-lifecycle.md`, `status-rail.md` · Patterns: resume-lifecycle, status-rail
- States covered: compact (6 and 5 per page), regular (controls), indicator, loading (placeholders), in-context (Home, Weather sheet, iPad), ax5 (2 per page)
- Motion: page change (system paging, none when reduced), indicator resize (0.2 s), button fade (0.2 s)
- Devices: iPhone, iPad (size class), embedded devices
- Open notes: scrollTargetBehavior(.paging) is avoided (leaks observation on resume); the card header is omitted in the swatches; hours are fixtures.
