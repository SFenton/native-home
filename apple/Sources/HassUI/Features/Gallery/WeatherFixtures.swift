#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// Synthetic weather for the gallery and hosted tests (not a copy of the live house). Times are relative to now, so
/// the hourly list never expires while a journey runs.
enum WeatherFixtures {
    static func states(condition: String, night: Bool, airQuality: Bool, now: Date = Date()) -> [EntityState] {
        var states = [
            EntityState(entityId: WeatherEntities.weather, state: condition, attributes: [
                "friendly_name": .string("Pirate Weather"), "temperature": .number(72), "apparent_temperature": .number(75),
                "temperature_unit": .string("°F"), "humidity": .number(58), "wind_speed": .number(9), "wind_gust_speed": .number(14),
                "wind_speed_unit": .string("mph"), "wind_bearing": .number(250), "pressure": .number(29.92), "pressure_unit": .string("inHg"),
                "visibility": .number(10), "visibility_unit": .string("mi"), "precipitation_unit": .string("in"),
            ]),
            EntityState(entityId: WeatherEntities.sun, state: night ? "below_horizon" : "above_horizon", attributes: [
                "next_rising": .string(iso(now.addingTimeInterval(night ? 6 * 3600 : 17 * 3600))),
                "next_setting": .string(iso(now.addingTimeInterval(night ? 20 * 3600 : 5 * 3600))),
            ]),
        ]
        if airQuality { states.append(EntityState(entityId: WeatherEntities.airQuality, state: "72")) }
        return states
    }

    /// A `weather.get_forecasts` response object for the weather entity.
    static func response(_ forecasts: [JSONValue]) -> JSONValue {
        .object([WeatherEntities.weather: .object(["forecast": .array(forecasts)])])
    }

    /// 24 hours starting at the current hour: rain easing to cloud and then clearing.
    static func hourly(now: Date = Date()) -> [JSONValue] {
        let hourStart = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        let conditions = ["rainy", "rainy", "pouring", "rainy", "cloudy", "cloudy", "partlycloudy", "partlycloudy", "sunny", "sunny", "clear-night", "clear-night"]
        return (0..<24).map { index in
            let wet = index < 5
            return .object([
                "datetime": .string(iso(hourStart.addingTimeInterval(Double(index) * 3600))),
                "condition": .string(conditions[(index / 2) % conditions.count]),
                "temperature": .number(72 - Double(index % 12) * 0.8),
                "apparent_temperature": .number(74 - Double(index % 12) * 0.8),
                "precipitation": .number(wet ? 0.04 + Double(index) * 0.01 : 0),
                "precipitation_probability": .number(wet ? 80 - Double(index) * 8 : 5),
                "humidity": .number(58 + Double(index % 6) * 3),
                "cloud_coverage": .number(wet ? 90 : 40),
                "wind_speed": .number(8 + Double(index % 5)),
                "wind_gust_speed": .number(14 + Double(index % 5) * 2),
                "wind_bearing": .number(250 + Double(index) * 4),
                "uv_index": .number(Double(index % 8)),
            ])
        }
    }

    /// Seven days starting today.
    static func daily(now: Date = Date()) -> [JSONValue] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: now)
        let conditions = ["rainy", "partlycloudy", "sunny", "sunny", "cloudy", "pouring", "lightning-rainy"]
        return (0..<7).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start) ?? start
            return .object([
                "datetime": .string(iso(day)),
                "condition": .string(conditions[index]),
                "temperature": .number(78 + Double(index % 4) * 3),
                "templow": .number(58 + Double(index % 3) * 2),
                "precipitation": .number(index == 0 || index >= 5 ? 0.3 : 0),
                "precipitation_probability": .number(index == 0 ? 70 : index >= 5 ? 60 : 10),
                "wind_speed": .number(8 + Double(index)),
                "wind_gust_speed": .number(15 + Double(index) * 2),
                "wind_bearing": .number(220 + Double(index) * 20),
                "uv_index": .number(7),
            ])
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
#endif
