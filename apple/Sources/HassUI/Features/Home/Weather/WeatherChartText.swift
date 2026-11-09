import HassCore
import SwiftUI

/// Text for the highlight charts and their spoken series.
enum WeatherChartText {
    /// Hour labels for the first hours: `Now`, then `4 PM`.
    static func hourLabels(_ points: [PrecipitationPoint]) -> [String] {
        points.enumerated().map { index, point in
            index == 0 ? WeatherCopy.text("precipitation.now") : point.startTime.map { WeatherDates.hour($0) } ?? "--"
        }
    }

    static func percent(_ value: Double?) -> String {
        value.map { "\(WeatherFormat.integer($0))%" } ?? WeatherCopy.text("unavailable")
    }

    static func amount(_ value: Double?, unit: String) -> String {
        guard let value else { return WeatherCopy.text("unavailable") }
        let normalized = unit.trimmingCharacters(in: .whitespaces).isEmpty ? "in" : unit
        let digits = normalized.lowercased().contains("mm") ? 1 : 2
        return "\(String(format: "%.\(digits)f", value)) \(normalized)"
    }
}
