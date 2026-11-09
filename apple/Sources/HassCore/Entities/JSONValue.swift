import Foundation

/// A Codable, Sendable JSON value, used for entity attributes so they can be snapshotted to disk.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    // MARK: - Bridging

    /// Converts a `JSONSerialization`-style value. Unknown types become ``null``.
    public init(any value: Any?) {
        switch value {
        case nil, is NSNull: self = .null
        case let value as NSNumber:
            // NSNumber booleans arrive as __NSCFBoolean; keep them as Bool.
            if CFGetTypeID(value) == CFBooleanGetTypeID() { self = .bool(value.boolValue) } else { self = .number(value.doubleValue) }
        case let value as String: self = .string(value)
        case let value as Int: self = .number(Double(value))
        case let value as Double: self = .number(value)
        case let value as [Any]: self = .array(value.map { JSONValue(any: $0) })
        case let value as [String: Any]: self = .object(value.mapValues { JSONValue(any: $0) })
        default: self = .null
        }
    }

    // MARK: - Accessors

    /// The string value, if this is a string.
    public var string: String? { if case let .string(value) = self { value } else { nil } }
    /// The numeric value, if this is a number.
    public var number: Double? { if case let .number(value) = self { value } else { nil } }
    /// The boolean value, if this is a bool.
    public var bool: Bool? { if case let .bool(value) = self { value } else { nil } }
    /// The array value, if this is an array.
    public var array: [JSONValue]? { if case let .array(value) = self { value } else { nil } }
    /// Member lookup for objects.
    public subscript(key: String) -> JSONValue? { if case let .object(value) = self { value[key] } else { nil } }
    /// A finite number from a number or a numeric string, trimmed (web `finiteNumber`). The one lenient number
    /// reader: `" 5 "` is 5; `"inf"`, `"nan"`, blank text and other types are `nil`.
    public var finiteNumber: Double? {
        switch self {
        case let .number(value): value.isFinite ? value : nil
        case let .string(text): Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        default: nil
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
