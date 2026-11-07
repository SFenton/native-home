import HassCore
import HassDesign
import SwiftUI

/// The card's presentation: reads entities and the store, owns the sheet.
///
/// Direction G (`.agents/design/direction-g.md`, mockup n1 home): a thin module on the wallpaper with the glyph, the
/// condition and today's high and low on the left, the screen's one display numeral on the right (header: option D,
/// `.agents/design/weather-card-header.md`), then the day's first briefing sentence, then the hours.
struct WeatherCardContent {
    var forecasts: WeatherForecastStore
    var startsOpen = false

    /// The briefing's sentence while forecasts are missing (`WeatherDayBriefingGenerator`).
    static let unavailableKey = "briefing.unavailable"
    /// The numeral's largest size at accessibility text sizes.
    static let maxNumeralSize: CGFloat = 96


    /// The card's one-line outlook: the first sentence of today's briefing, or nil before one is written. The
    /// "appears once … returns forecast data" placeholder sentence is left out: the hours already say so.
    static func briefingLine(_ briefing: WeatherDayBriefing?) -> String? {
        guard let first = briefing?.sentences.first, first.key != unavailableKey else { return nil }
        let line = WeatherBriefingRenderer.render(first)
        return line.isEmpty ? nil : line
    }








    // MARK: - Today

    /// The web's aria-label for the Today row: `Today Rain H:70°  L:55°`.
    static func todayLabel(_ today: WeatherForecast) -> String {
        "Today \(WeatherConditionInfo(today.condition).label) \(WeatherFormat.compactHighLow(today))"
    }


}
