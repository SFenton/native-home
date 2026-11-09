import Foundation

/// Number and label formatting for the weather card and sheet, ported from `WeatherSummary.tsx`.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/WeatherSummary.tsx:343`.
public enum WeatherFormat {
    /// JavaScript's `Math.round`: halves round toward positive infinity.
    public static func round(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

    /// A rounded integer as text, never `-0`.
    public static func integer(_ value: Double) -> String { String(Int(round(value))) }

    /// A unit with its degree sign removed (`°F` becomes `F`), or `fallback` when blank.
    public static func unitWithoutDegree(_ unit: String?, fallback: String) -> String {
        guard let unit, !unit.trimmingCharacters(in: .whitespaces).isEmpty else { return fallback }
        return unit.replacingOccurrences(of: "°", with: "")
    }

    /// `72°F`, or `--` when there is no value.
    public static func temperature(_ value: Double?, unit: String?) -> String {
        guard let value else { return "--" }
        return "\(integer(value))°\(unitWithoutDegree(unit, fallback: "F"))"
    }

    /// `72°`, or `--`.
    public static func degree(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(integer(value))°"
    }

    /// A number with up to `digits` fraction digits and `en-US` grouping; `nil` when not finite.
    public static func number(_ value: Double?, digits: Int = 0) -> String? {
        guard let value, value.isFinite else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value))
    }

    /// `45%`.
    public static func percent(_ value: Double?) -> String? {
        number(value).map { "\($0)%" }
    }

    /// `29.92 inHg`; the unit is omitted when blank.
    public static func measure(_ value: Double?, unit: String?, digits: Int = 0) -> String? {
        guard let formatted = number(value, digits: digits) else { return nil }
        if let unit, !unit.isEmpty { return "\(formatted) \(unit)" }
        return formatted
    }

    /// A wind speed with its unit.
    public struct WindMeasure: Equatable, Sendable {
        public var amount: String
        public var numeric: Double
        public var unit: String
        public var value: String { "\(amount) \(unit)" }
    }

    /// `<1 mph`, `12 mph`; `nil` for missing or negative speeds.
    public static func windMeasure(_ value: Double?, unit: String?) -> WindMeasure? {
        guard let value, value >= 0 else { return nil }
        let unitLabel = unitWithoutDegree(unit, fallback: WeatherUnits.defaultWindSpeedUnit)
        let amount = value > 0 && value < 1 ? "<1" : number(value) ?? "--"
        return WindMeasure(amount: amount, numeric: value, unit: unitLabel)
    }

    /// `8-15 mph` for a speed and gust, collapsing equal amounts (`formatWindRange`).
    public static func windRange(speed: Double?, gust: Double?, unit: String?) -> String {
        let wind = windMeasure(speed, unit: unit)
        let windGust = windMeasure(gust, unit: unit)
        if wind == nil, windGust == nil { return "--" }
        guard let windGust else { return wind?.value ?? "--" }
        guard let wind, windGust.amount != wind.amount else { return wind?.value ?? windGust.value }
        return "\(wind.amount)-\(windGust.amount) \(windGust.unit)"
    }

    /// `Today` for the first day, then the short weekday (`forecastDayLabel`).
    public static func dayLabel(_ datetime: String?, index: Int, timeZone: TimeZone = .current) -> String {
        let fallback = index == 0 ? "Today" : "Day \(index + 1)"
        guard let datetime, let date = HassDates.iso8601(datetime) else { return fallback }
        return index == 0 ? "Today" : WeatherDates.weekday(date, in: timeZone)
    }

    /// `Now` for the first hour, then `7 PM` (`hourlyLabel`).
    public static func hourLabel(_ datetime: String?, index: Int, timeZone: TimeZone = .current) -> String {
        if index == 0 { return "Now" }
        guard let datetime, let date = HassDates.iso8601(datetime) else { return "\(index)h" }
        return WeatherDates.hour(date, in: timeZone)
    }

    /// `H:72°  L:55°` (`compactHighLowLabel`).
    public static func compactHighLow(_ forecast: WeatherForecast?) -> String {
        guard let forecast else { return "" }
        let high = degree(forecast.temperature)
        let low = degree(forecast.templow)
        if high == "--", low == "--" { return "" }
        if high == "--" { return "L:\(low)" }
        if low == "--" { return "H:\(high)" }
        return "H:\(high)  L:\(low)"
    }

    /// `High: 72°  Low: 55°` (`modalHighLowLabel`).
    public static func modalHighLow(_ forecast: WeatherForecast?) -> String {
        guard let forecast else { return "" }
        let high = degree(forecast.temperature)
        let low = degree(forecast.templow)
        if high == "--", low == "--" { return "" }
        if high == "--" { return WeatherCopy.text("hero.low", ["low": low]) }
        if low == "--" { return WeatherCopy.text("hero.high", ["high": high]) }
        return WeatherCopy.text("hero.highLow", ["high": high, "low": low])
    }
}
