import HassCore
import SwiftUI

/// The hourly detail modes (web `WEATHER_HOURLY_MODES`, `surfaceSemantics.ts:12`).
enum WeatherHourlyMode: String, CaseIterable, Identifiable {
    case condition, precipitation, wind

    var id: String { rawValue }

    /// Button label.
    var label: String {
        switch self {
        case .condition: "Conditions"
        case .precipitation: "Precipitation"
        case .wind: "Wind"
        }
    }

    /// What the mode shows, spoken as the button's hint.
    var hint: String {
        switch self {
        case .condition: "Shows the hourly condition and temperature."
        case .precipitation: "Shows precipitation chance and expected accumulation."
        case .wind: "Shows wind speed, direction and gusts."
        }
    }
}
