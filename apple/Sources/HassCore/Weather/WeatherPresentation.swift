import Foundation

/// Classification and gauge math for the weather sheet's highlight tiles.
///
/// Every function is a direct port of the web helper of the same name so thresholds and marker positions match.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/weatherPresentation.ts`.
public enum WeatherPresentation {
    // MARK: - Shared helpers

    static func clampPercent(_ value: Double) -> Double { min(100, max(0, value)) }

    /// `value` modulo 360 into `0..<360` (`normalizeBearingDegrees`).
    public static func normalizeBearingDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return (remainder + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The signed shortest rotation from one bearing to another, in `(-180, 180]` (`shortestBearingDelta`).
    public static func shortestBearingDelta(from: Double, to: Double) -> Double {
        let delta = ((normalizeBearingDegrees(to) - normalizeBearingDegrees(from) + 540).truncatingRemainder(dividingBy: 360)) - 180
        return delta <= -180 ? 180 : delta
    }

    /// How long the compass needle takes to turn, in milliseconds (`compassRotationDurationMs`).
    public static func compassRotationDurationMs(from: Double, to: Double) -> Int {
        Int(WeatherFormat.round(260 * (1 + min(180, abs(to - from)) / 180)))
    }

    /// The data-change animation length (`WEATHER_DATA_TRANSITION_MS`).
    public static let dataTransitionMs = 390

    // MARK: - Air quality

    /// US AQI categories, lowest first.
    public enum AqiLevel: String, Codable, Sendable, CaseIterable {
        case good, moderate, sensitive, unhealthy, veryUnhealthy, hazardous

        /// Copy key of the category label.
        public var categoryKey: String { "aqi.categories.\(rawValue)" }
        /// Copy key of the health guidance.
        public var guidanceKey: String { "aqi.guidance.\(rawValue)" }
        var range: ClosedRange<Int> {
            switch self {
            case .good: 0...50
            case .moderate: 51...100
            case .sensitive: 101...150
            case .unhealthy: 151...200
            case .veryUnhealthy: 201...300
            case .hazardous: 301...500
            }
        }
    }

    /// A classified AQI reading.
    public struct AqiReading: Equatable, Sendable {
        public var elevated: Bool
        public var level: AqiLevel
        /// 0...100 position on six equal-width category bands.
        public var markerPercent: Double
        public var value: Int
    }

    /// Classifies a US AQI value; `nil` when it is not a non-negative number (`classifyUsAqi`).
    public static func classifyUsAqi(_ value: Double?) -> AqiReading? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        let rounded = Int(WeatherFormat.round(value))
        let levels = AqiLevel.allCases
        let index = levels.firstIndex { rounded <= $0.range.upperBound } ?? levels.count - 1
        let band = levels[index].range
        let clamped = min(band.upperBound, max(band.lowerBound, rounded))
        let progress = Double(clamped - band.lowerBound) / Double(max(1, band.upperBound - band.lowerBound))
        return AqiReading(
            elevated: rounded > 100, level: levels[index],
            markerPercent: (Double(index) + progress) / Double(levels.count) * 100, value: rounded
        )
    }

    /// Classifies a sensor state string (`"42"`); `nil` for `unavailable` and other text.
    public static func classifyUsAqi(state: String?) -> AqiReading? {
        classifyUsAqi(state.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) })
    }

    // MARK: - UV

    public enum UvLevel: String, Codable, Sendable {
        case low, moderate, high, veryHigh, extreme
        public var categoryKey: String { "details.uv.categories.\(rawValue)" }
    }

    public struct UvReading: Equatable, Sendable {
        public var level: UvLevel
        public var markerPercent: Double
        public var value: Double
    }

    /// UV index category and marker (`uvPresentation`). The category uses the unrounded value.
    public static func uv(_ value: Double?) -> UvReading? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        let level: UvLevel = value < 3 ? .low : value < 6 ? .moderate : value < 8 ? .high : value < 11 ? .veryHigh : .extreme
        return UvReading(level: level, markerPercent: clampPercent(value / 11 * 100), value: value)
    }

    // MARK: - Feels like

    public enum FeelsLikeRelation: String, Codable, Sendable { case cooler, similar, warmer }

    public struct FeelsLikeReading: Equatable, Sendable {
        public var delta: Double
        public var markerPercent: Double
        public var relation: FeelsLikeRelation
    }

    /// Apparent temperature relative to the actual one (`feelsLikePresentation`).
    public static func feelsLike(actual: Double?, apparent: Double?, unit: String?) -> FeelsLikeReading? {
        guard let actual, let apparent else { return nil }
        let celsius = unit?.lowercased().contains("c") ?? false
        let neutral: Double = celsius ? 1 : 2
        let range: Double = celsius ? 7 : 12
        let delta = apparent - actual
        let relation: FeelsLikeRelation = abs(delta) <= neutral ? .similar : delta > 0 ? .warmer : .cooler
        return FeelsLikeReading(delta: delta, markerPercent: clampPercent((delta + range) / (range * 2) * 100), relation: relation)
    }

    // MARK: - Wind

    struct CompassPoint {
        var abbreviation: String
        var spoken: String
    }

    static let compassPoints: [CompassPoint] = [
        .init(abbreviation: "N", spoken: "north"), .init(abbreviation: "NNE", spoken: "north-northeast"),
        .init(abbreviation: "NE", spoken: "northeast"), .init(abbreviation: "ENE", spoken: "east-northeast"),
        .init(abbreviation: "E", spoken: "east"), .init(abbreviation: "ESE", spoken: "east-southeast"),
        .init(abbreviation: "SE", spoken: "southeast"), .init(abbreviation: "SSE", spoken: "south-southeast"),
        .init(abbreviation: "S", spoken: "south"), .init(abbreviation: "SSW", spoken: "south-southwest"),
        .init(abbreviation: "SW", spoken: "southwest"), .init(abbreviation: "WSW", spoken: "west-southwest"),
        .init(abbreviation: "W", spoken: "west"), .init(abbreviation: "WNW", spoken: "west-northwest"),
        .init(abbreviation: "NW", spoken: "northwest"), .init(abbreviation: "NNW", spoken: "north-northwest"),
    ]

    /// A wind direction ready to draw and speak.
    public struct WindBearingReading: Equatable, Sendable {
        /// `WNW`.
        public var cardinal: String
        /// Degrees the wind blows toward (the arrow's direction).
        public var destinationDegrees: Double
        /// Whole degrees, only when the provider reported degrees.
        public var displayDegrees: Int?
        /// Degrees the wind blows from.
        public var sourceDegrees: Double
        /// `west-northwest`.
        public var spoken: String
    }

    /// A bearing's degrees, and whether Home Assistant reported degrees rather than a compass abbreviation. With
    /// `principalOnly`, only the eight principal points read as abbreviations (the briefing's `bearingValue`).
    public static func bearingDegrees(_ value: WeatherWindBearing?, principalOnly: Bool = false) -> (degrees: Double, reported: Bool)? {
        switch value {
        case let .degrees(number)?:
            return (number, true)
        case let .cardinal(text)?:
            let normalized = text.trimmingCharacters(in: .whitespaces).uppercased()
            if let numeric = Double(normalized), numeric.isFinite { return (numeric, true) }
            guard let index = compassPoints.firstIndex(where: { $0.abbreviation == normalized }),
                  !principalOnly || index.isMultiple(of: 2) else { return nil }
            return (Double(index) * 22.5, false)
        case nil:
            return nil
        }
    }

    /// Reads a bearing in degrees or as a compass abbreviation (`windBearingPresentation`).
    public static func windBearing(_ value: WeatherWindBearing?) -> WindBearingReading? {
        guard let (degrees, reportedAsDegrees) = bearingDegrees(value) else { return nil }
        let source = normalizeBearingDegrees(degrees)
        let point = compassPoints[Int(((source + 11.25) / 22.5).rounded(.down)) % compassPoints.count]
        return WindBearingReading(
            cardinal: point.abbreviation,
            destinationDegrees: (source + 180).truncatingRemainder(dividingBy: 360),
            displayDegrees: reportedAsDegrees ? Int(WeatherFormat.round(source)) % 360 : nil,
            sourceDegrees: source,
            spoken: point.spoken
        )
    }

    // MARK: - Pressure

    public enum PressureBand: String, Codable, Sendable { case above, below, typical }

    public struct PressureReading: Equatable, Sendable {
        public var band: PressureBand
        public var hpa: Double
        /// 0...100 across 970 to 1050 hPa.
        public var markerPercent: Double
    }

    /// Normalizes pressure to hPa and bands it (`pressurePresentation`); `nil` for an unknown unit.
    public static func pressure(_ value: Double?, unit: String?) -> PressureReading? {
        let normalized = (unit ?? "").lowercased().filter { !$0.isWhitespace }
        guard let value, !normalized.isEmpty else { return nil }
        let hpa: Double
        if normalized.contains("inhg") { hpa = value * 33.8638866667 }
        else if normalized.contains("hpa") || normalized.contains("mbar") || normalized == "mb" { hpa = value }
        else if normalized.contains("kpa") { hpa = value * 10 }
        else if normalized == "pa" { hpa = value / 100 }
        else { return nil }
        let band: PressureBand = hpa < 1009 ? .below : hpa > 1023 ? .above : .typical
        return PressureReading(band: band, hpa: hpa, markerPercent: clampPercent((hpa - 970) / 80 * 100))
    }

    // MARK: - Visibility

    public enum VisibilityBand: String, Codable, Sendable { case clear, good, moderate, poor, veryPoor }

    public struct VisibilityReading: Equatable, Sendable {
        public var band: VisibilityBand
        public var markerPercent: Double
        public var miles: Double
    }

    /// Normalizes visibility to miles and bands it (`visibilityPresentation`).
    public static func visibility(_ value: Double?, unit: String?) -> VisibilityReading? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        let normalized = (unit ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let miles: Double
        if normalized.contains("km") { miles = value * 0.621371 }
        else if normalized == "m" || normalized.contains("meter") { miles = value / 1609.344 }
        else { miles = value }
        let band: VisibilityBand = miles >= 10 ? .clear : miles >= 6 ? .good : miles >= 3 ? .moderate : miles >= 1 ? .poor : .veryPoor
        return VisibilityReading(band: band, markerPercent: clampPercent(miles / 10 * 100), miles: miles)
    }

    // MARK: - Sun

    public enum SunEvent: String, Sendable { case sunrise, sunset }

    public struct SunReading: Equatable, Sendable {
        /// Daylight progress 0...100 while the sun is up, else `nil`.
        public var markerPercent: Double?
        public var primary: SunEvent
        public var primaryTime: Date
        public var secondary: SunEvent
        public var secondaryTime: Date

        /// Copy key of the primary event's tile title.
        public var titleKey: String { "details.sun.\(primary.rawValue)" }
    }

    /// The next solar event and daylight progress (`sunPresentation`).
    /// - Parameters:
    ///   - state: `sun.sun` state (`above_horizon` or `below_horizon`).
    ///   - nextRising: The `next_rising` attribute.
    ///   - nextSetting: The `next_setting` attribute.
    public static func sun(state: String?, nextRising: String?, nextSetting: String?, now: Date = Date()) -> SunReading? {
        guard let rising = nextRising.flatMap(HassDates.iso8601), let setting = nextSetting.flatMap(HassDates.iso8601) else { return nil }
        if state == "above_horizon" {
            let previousRising = rising.addingTimeInterval(-86_400)
            let duration = setting.timeIntervalSince(previousRising)
            let marker = duration > 0 ? clampPercent(now.timeIntervalSince(previousRising) / duration * 100) : nil
            return SunReading(markerPercent: marker, primary: .sunset, primaryTime: setting, secondary: .sunrise, secondaryTime: rising)
        }
        return SunReading(markerPercent: nil, primary: .sunrise, primaryTime: rising, secondary: .sunset, secondaryTime: setting)
    }

    /// The marker position on the 100 x 48 sun-arc viewBox (`sunArcMarker`).
    public static func sunArcMarker(percent: Double) -> (x: Double, y: Double) {
        let normalized = clampPercent(percent) / 100
        return (8 + normalized * 84, 40 - 72 * normalized * (1 - normalized))
    }
}
