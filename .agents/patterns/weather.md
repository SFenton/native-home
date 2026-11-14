# Weather card and sheet

> **What:** the Home weather card, its 24-hour carousel and the Weather sheet, plus the logic under them. **Read when:** changing anything in `HassUI/Features/Home/Weather` or `HassCore/Weather`.

Web source: `ha-sfenton-react-dash@f5a7bf9` `src/components/hass/WeatherSummary.tsx` (card and sheet), `useWeatherForecasts.ts`, `weatherPresentation.ts`, `weatherDayBriefing.ts` + `useWeatherDayBriefing.ts`, `precipitationTimeline.ts`, `WeatherRail.tsx`, `WeatherPrecipitationTile.tsx`, `WeatherHourlyMetricTiles.tsx`, and `i18n/locales/en/modals/weather.json` (the copy deck, ported as `WeatherCopy`).

## Pieces

| Piece | Where | Notes |
|---|---|---|
| Forecast store | `HassCore/Weather/WeatherForecastStore` | One shared instance per card. Port of the web cache: 5 min TTL, 5 s retry doubling to the TTL on a dropped connection, refetch when the weather entity changes (`revision(of:)` stands in for `last_updated`), hourly entries pruned when their hour passes, never blanks while refreshing, phases idle/loading/ready/empty/error. A request that never answers (HAKit drops unanswered `shouldRetry: false` requests across a reconnect) times out after 20 s and counts as a dropped connection. |
| Disk snapshot | `WeatherForecastDiskCache` | Caches directory, keyed by server, cleared on sign-out. Restored in the store's `init`, so a cold launch draws the carousel before any network work. The restored copy is never treated as fresh. |
| Presentation | `WeatherPresentation`, `WeatherFormat`, `WeatherCondition*`, `WeatherHighlights`, `WeatherRails` | Direct ports; thresholds and marker maths match the web tests. |
| Today briefing | `WeatherDayBriefingGenerator`, `WeatherBriefingPlanner` | Structured copy references rendered by `WeatherBriefingRenderer`; frozen once per local day at or after 00:01 and stored in the disk snapshot. |
| Card | `WeatherSummaryCard` (wiring) + `WeatherCardContent` | Wiring: appear/disappear, entity revision, websocket ready, scene phase, 30 s briefing check. The gallery injects `\.weatherForecastStore` and `\.weatherForecastCaller`. |
| Carousel | `WeatherPagedCarousel`, `WeatherCarouselPaging` | Pages of whole hours (`scrollTargetBehavior(.paging)`). Hours per page come from the size class and text size, not from measuring (a measured width never reached state in the hosted test host); hour labels scale freely (a `minimumScaleFactor` made the AX5 audit flag them). The page indicator is the shared `PageIndicator` ([page-indicator](page-indicator.md)): tap either half to move, adjustable for VoiceOver, "n of N" past ten pages. Regular layouts add 44 pt Previous/Next buttons (the web shows them for pointer devices); at the ends they fade once, to 55%, through `WeatherCarouselControlStyle`, never `.plain` plus an opacity ([chevron contrast](../design/weather-chevron-contrast.md)). The hourly Conditions switcher is a system segmented control of the three mode icons, each segment named and hinted for VoiceOver. |
| Sheet | `WeatherSheet` and the `Weather*Panel` views | Dark appearance, condition gradient as the sheet background, panels as a darkening wash (no blur, so Reduce Transparency changes nothing). |
| Highlights | `WeatherHighlightsPanel` on `DynamicGridLayout` | Wide tiles `gridSpan(2)`; the grid minimum cell width scales with text size so it reflows to one column at AX5. |
| Gallery | `Gallery/WeatherGallery` (`FENTON_GALLERY=weather`) | `FENTON_GALLERY_WEATHER_CONDITION`, `_NIGHT`, `_STATE=loading|error|empty`, `_OPEN`, `_NOAQI`, `_FILL=<points>` (padding so the page scrolls). Debug only. |

## Accessibility rules

- The card's header is laid out as option D ([weather card header](../design/weather-card-header.md)): glyph, condition (a [ticker](ticker.md) when it overflows) and today's high and low on the left, the numeral with its chevron on the right (the one button); accessibility sizes, or a range wider than its column, stack the condition and range under the glyph and numeral row. `WeatherSymbols.leadingInsets` pulls each glyph left so its ink meets the label's edge (`WeatherViewTests.leadingInsetTableMatchesTheRenderedInk`).
- The card's header is the one button ("Open seven-day weather forecast. Rain, 72°F"); the rest of the card also opens the sheet by tap, but only the header is a button for assistive technology. Hours, today's high and low and the page indicator are separate elements.
- Hours, days and tiles speak the web's aria-labels (`7 PM Rain 62°F`, `Mon precipitation 0.1 in 40%`, `Wind 9 mph; Gusts 14 mph; From west-southwest, 250 degrees`). Charts and gauges are hidden; their tile speaks the series.
- Mode buttons are labelled "Conditions", "Precipitation", "Wind" with an `isSelected` trait; the web's label ("Conditions conditions") reads awkwardly with a selected state.
- Text colours are `HassTokens.Ink.onDark` / `onDarkSecondary` over gradients whose lightest stop is at least 5.6:1 against white (checked by `WeatherViewTests.backdropsAreDarkEnoughForWhiteText`).
- Reduce Motion: no page, rail or compass animation, and the rain/snow decoration is a still frame. Reduce Transparency: no decoration.

## Departures from the web

- SF Symbols (multicolor) replace the custom SVG glyphs; night variants only for the current condition, from `sun.sun`.
- No animated atmosphere beyond slow rain/snow streaks; clouds, stars and glow are still.
- The Today briefing is stored in the disk snapshot instead of `localStorage`.
- No navigation subtitle: the bar subtitle measured 4.1:1 over the gradient (iPhone audit, 2026-10-13), and the hero already shows "72°" and the condition. The title stays the system "Weather".
- Charts are plain bars (HIG: Charting data), not Swift Charts, so every axis label can scale with Dynamic Type.

## House config

The weather, air-quality and sun entity ids (`WeatherEntities.weather`, `.airQuality`, `.sun`; document paths `home.weatherEntityId`, `home.airQualityEntityId`, `home.sunEntityId`, the last two optional) are facades over the loaded house document; with no document they answer empty (architecture.md, "House config facades"). `WeatherForecastStore` reads the id each time a fetch is due, never at creation, so a document that arrives after the card is built (a first sign-in) reaches it: the card's driver tracks the id and starts the first fetch. While the id is empty the store sends no call, arms no timer and leaves both feeds pending, so the card shows its placeholders. A failed fetch shows the deck line (`WeatherCopy.forecastFailure`), never Home Assistant's own text; the server's reason goes to Telemetry only (`weather.forecastFailed`). The rules above still hold.

## Guards

Checked by `python3 tools/pattern_guard.py` against `contracts/patterns.json` (comment lines are ignored).

- `weather/static-let-reads-house-facade`: a `static let` that reads a flipped house-config facade freezes the first value until relaunch; use a computed `static var`. Scans `apple/Sources/**/*.swift` statement by statement, so a multi-line initializer is caught. The facade names are the guard's `facades` map in `contracts/patterns.json` (type to names, all of batches a to d); each new flip adds its names. An unqualified read inside the facade's own type and a call to a helper that reads one are not caught: sweep for them. The guard sits here because the weather entity was the first facade it protects.

- `weather/unique-keys-in-facade-files`: `Dictionary(uniqueKeysWithValues:)` traps on a repeated key; in a file that reads a house-config facade the keys come from the server's document, so use `uniquingKeysWith: { first, _ in first }`. Only files that name a facade from the guard above are scanned, which keeps it quiet. A server value read without naming a facade (a helper) is not caught: sweep for it.

Known debt (the gallery and debug fixtures; step 5b replaces them with the demo house): `apple/Sources/HassUI/Features/Gallery/HomePagesGallery.swift` (2), `apple/Sources/HassUI/Features/Gallery/RoomDevicesGallery.swift`, `apple/Sources/HassUI/Features/Gallery/SecurityGallery.swift`, `apple/Sources/HassUI/Features/Gallery/VacuumGallery.swift`, and for the second guard `apple/Sources/HassUI/Features/Gallery/BedroomGallery.swift`.

## Tests

`apple/Tests/HassCoreTests/Weather*Tests.swift` (store, presentation, briefing, chart maths, highlights, parsing), `apple/Tests/HassUITests/WeatherViewTests.swift` (symbols, paging, labels, every state rendered, wiring in a live window), `apple/Apps/iOSUITests/WeatherJourneyTests.swift` (gallery journeys and audits at default and AX5; run on iPhone, Duo and iPad with `tools/ios_uitest.sh`).

- **Owned files** (also in `contracts/patterns.json`): `PagedRow.swift`, `PagedRowMetrics.swift`.
