import Foundation

/// A wind direction as the weather integration reports it: degrees, or a compass abbreviation (`"WNW"`).
public enum WeatherWindBearing: Hashable, Sendable {
    case degrees(Double)
    case cardinal(String)

    /// Reads a bearing from a Home Assistant attribute; `nil` for anything else.
    public init?(json: JSONValue?) {
        switch json {
        case let .number(value) where value.isFinite: self = .degrees(value)
        case let .string(value) where !value.trimmingCharacters(in: .whitespaces).isEmpty: self = .cardinal(value)
        default: return nil
        }
    }

    var json: JSONValue {
        switch self {
        case let .degrees(value): .number(value)
        case let .cardinal(value): .string(value)
        }
    }
}
