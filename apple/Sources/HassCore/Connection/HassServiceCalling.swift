import Foundation

/// Anything that can call a Home Assistant service. ``HassConnection`` is the app's one implementation;
/// tests and the debug gallery record calls instead, so automated runs never touch the house.
@MainActor
public protocol HassServiceCalling: AnyObject {
    /// Calls `domain.service` with `data` (including `entity_id`).
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws
}

extension HassConnection: HassServiceCalling {}

public extension HassServiceCalling {
    /// Calls a ``ServiceCall``, converting its data to JSON-serializable Foundation values.
    func call(_ call: ServiceCall) async throws {
        try await callService(call.domain, call.service, data: call.serviceData.mapValues(\.foundationValue))
    }
}

public extension JSONValue {
    /// The value as `JSONSerialization` accepts it; integral numbers become `Int`.
    var foundationValue: any Sendable {
        switch self {
        case let .string(value): value
        case let .number(value): value == value.rounded() && abs(value) < 1e15 ? Int(value) : value
        case let .bool(value): value
        case let .array(values): values.map(\.foundationValue)
        case let .object(values): values.mapValues(\.foundationValue)
        case .null: Optional<String>.none as any Sendable
        }
    }
}
