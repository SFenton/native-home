import Foundation

/// A value inside a briefing sentence: literal text, a number, or another copy reference.
public enum WeatherBriefingValue: Codable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case ref(WeatherBriefingRef)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .text(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .ref(try container.decode(WeatherBriefingRef.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .ref(value): try container.encode(value)
        }
    }
}
