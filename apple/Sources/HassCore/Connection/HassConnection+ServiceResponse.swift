import Foundation
@preconcurrency import HAKit

/// Something that can call a Home Assistant service and read the `response` member it returns (`return_response`).
///
/// EverShelf's inventory, barcode and expiry services and the todo pages read this. ``HassServiceResponding`` is the
/// same call returning the whole result; both go through ``HassConnection/callServiceReturningResult(_:_:data:)``.
@MainActor
public protocol EverShelfCalling: HassServiceCalling {
    /// Calls `domain.service` with `return_response: true`.
    /// - Returns: The service's `response` object, or ``JSONValue/null`` when it returned nothing.
    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue
}

extension HassConnection: EverShelfCalling {
    /// Sends `call_service` with `return_response: true` over the app's websocket, once (no retry across
    /// reconnects, so a mutation is never applied twice).
    public func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try await callServiceReturningResult(domain, service, data: data)["response"] ?? .null
    }
}

/// User-facing text for a failed service call.
public enum ServiceErrorText {
    /// Home Assistant's own message for a rejected call (e.g. `EverShelf: inventory list failed`), else `fallback`.
    public static func message(for error: Error, fallback: String) -> String {
        if let error = error as? HAError {
            switch error {
            case let .external(external) where !external.message.isEmpty: return external.message
            case let .internal(debugDescription) where !debugDescription.isEmpty: return debugDescription
            default: return fallback
            }
        }
        if let error = error as? LocalizedError, let description = error.errorDescription, !description.isEmpty {
            return description
        }
        return fallback
    }
}
