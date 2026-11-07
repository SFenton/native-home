import Foundation

/// A JSON value a `mobile_app` sensor reports as its state or an attribute.
///
/// Sensors mix strings, numbers, booleans and lists (the geocoded location's coordinate pair), so the value keeps
/// its JSON type instead of stringifying: Home Assistant templates compare `battery_level` as a number.
public indirect enum SensorValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([SensorValue])
    case null

    /// The value as a `JSONSerialization` object.
    public var jsonObject: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        case .array(let values): values.map(\.jsonObject)
        case .null: NSNull()
        }
    }
}

extension SensorValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
