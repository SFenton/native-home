import HassCore
import SwiftUI

/// SF Symbols for weather conditions, hazards and highlight tiles.
///
/// The web draws custom SVG glyphs; native uses SF Symbols in multicolor rendering (HIG: SF Symbols, Weather data).
/// A hosted test checks that every name exists in the system symbol set.
enum WeatherSymbols {
    /// The symbol for a Home Assistant condition. `night` swaps the sun for the moon (current conditions only).
    static func condition(_ condition: String?, night: Bool = false) -> String {
        switch condition ?? "" {
        case "sunny": night ? "moon.stars.fill" : "sun.max.fill"
        case "clear-night": "moon.stars.fill"
        case "partlycloudy": night ? "cloud.moon.fill" : "cloud.sun.fill"
        case "cloudy": "cloud.fill"
        case "rainy": night ? "cloud.moon.rain.fill" : "cloud.rain.fill"
        case "pouring": "cloud.heavyrain.fill"
        case "snowy": "cloud.snow.fill"
        case "snowy-rainy": "cloud.sleet.fill"
        case "lightning": "cloud.bolt.fill"
        case "lightning-rainy": "cloud.bolt.rain.fill"
        case "fog": "cloud.fog.fill"
        case "hail": "cloud.hail.fill"
        case "windy": "wind"
        case "windy-variant": "smoke.fill"
        case "exceptional": "exclamationmark.triangle.fill"
        default: "cloud.fill"
        }
    }

    /// The symbol for a briefing hazard.
    static func hazard(_ hazard: WeatherHazard) -> String {
        switch hazard {
        case .damagingWind, .wind: "wind"
        case .denseFog: "cloud.fog.fill"
        case .extremeCold: "thermometer.snowflake"
        case .extremeHeat: "thermometer.sun.fill"
        case .freeze: "snowflake"
        case .hail: "cloud.hail.fill"
        case .heat: "thermometer.high"
        case .heavyRain: "cloud.heavyrain.fill"
        case .heavySnow, .snow: "cloud.snow.fill"
        case .highUv: "sun.max.trianglebadge.exclamationmark.fill"
        case .ice: "snowflake.circle.fill"
        case .poorAir: "aqi.medium"
        case .severeStorms: "cloud.bolt.fill"
        }
    }

    /// The symbol for a highlight tile.
    static func highlight(_ kind: WeatherHighlight.Kind, sun: WeatherPresentation.SunEvent? = nil) -> String {
        switch kind {
        case .aqi: "aqi.medium"
        case .feels: "thermometer.medium"
        case .uv: "sun.max.fill"
        case .wind: "wind"
        case .sun: sun == .sunrise ? "sunrise.fill" : "sunset.fill"
        case .visibility: "eye.fill"
        case .pressure: "gauge.with.dots.needle.33percent"
        }
    }

    /// Empty space between a condition symbol's frame and its ink on the left, as a fraction of the point size. SF Symbols carry
    /// 2 to 5 pt of it at 40 pt, which pushed the hero glyph's edge right of the text under it
    /// (`.agents/design/weather-card-header.md`). ``WeatherGlyph`` pulls the symbol left by this much; `WeatherViewTests` renders
    /// every condition symbol and fails when an entry is more than half a point off at 40 pt.
    static let leadingInsets: [String: CGFloat] = [
        "cloud.bolt.fill": 0.075,  // 3 pt at 40 pt
        "cloud.bolt.rain.fill": 0.075,  // 3 pt at 40 pt
        "cloud.fill": 0.075,  // 3 pt at 40 pt
        "cloud.fog.fill": 0.075,  // 3 pt at 40 pt
        "cloud.hail.fill": 0.075,  // 3 pt at 40 pt
        "cloud.heavyrain.fill": 0.075,  // 3 pt at 40 pt
        "cloud.moon.fill": 0.059375,  // 2.375 pt at 40 pt
        "cloud.moon.rain.fill": 0.059375,  // 2.375 pt at 40 pt
        "cloud.rain.fill": 0.075,  // 3 pt at 40 pt
        "cloud.sleet.fill": 0.075,  // 3 pt at 40 pt
        "cloud.snow.fill": 0.075,  // 3 pt at 40 pt
        "cloud.sun.fill": 0.05625,  // 2.25 pt at 40 pt
        "exclamationmark.triangle.fill": 0.1,  // 4 pt at 40 pt
        "moon.stars.fill": 0.125,  // 5 pt at 40 pt
        "smoke.fill": 0.05,  // 2 pt at 40 pt
        "sun.max.fill": 0.075,  // 3 pt at 40 pt
        "wind": 0.128125,  // 5.125 pt at 40 pt
    ]

    /// The leading inset of a condition symbol, as a fraction of its point size; 0 for a symbol not in ``leadingInsets``.
    static func leadingInset(of symbol: String) -> CGFloat { leadingInsets[symbol] ?? 0 }

    static let precipitation = "cloud.rain.fill"
    static let humidity = "humidity.fill"
    static let cloudCover = "cloud.fill"
    static let drop = "drop.fill"
    static let windArrow = "location.north.fill"
    static let windFlag = "wind"
    static let previous = "chevron.left"
    static let next = "chevron.right"

    /// The three hourly detail modes' toggle icons (web `WEATHER_HOURLY_MODES`).
    static func mode(_ mode: WeatherHourlyMode) -> String {
        switch mode {
        case .condition: "cloud.fill"
        case .precipitation: "drop.fill"
        case .wind: "wind"
        }
    }

    /// Every Home Assistant condition the card draws (plus an unknown one, which falls back to the cloud).
    static let conditionKeys = ["sunny", "clear-night", "partlycloudy", "cloudy", "rainy", "pouring", "snowy", "snowy-rainy", "lightning",
                                "lightning-rainy", "fog", "hail", "windy", "windy-variant", "exceptional", "unknown"]

    /// Every symbol a condition can draw, day and night, for the existence and ink-edge tests.
    static var conditionNames: [String] {
        Array(Set(conditionKeys.flatMap { [condition($0), condition($0, night: true)] })).sorted()
    }

    /// Every name this file can return, for the hosted existence test.
    static var allNames: [String] {
        let conditions = conditionKeys
        var names = conditions.flatMap { [condition($0), condition($0, night: true)] }
        names += WeatherHazard.allCases.map(hazard)
        names += WeatherHighlight.Kind.allCases.map { highlight($0) }
        names += [highlight(.sun, sun: .sunrise), precipitation, humidity, cloudCover, drop, windArrow, windFlag, previous, next]
        names += WeatherHourlyMode.allCases.map(mode)
        return Array(Set(names)).sorted()
    }
}
