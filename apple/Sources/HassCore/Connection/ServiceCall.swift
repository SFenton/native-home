import Foundation

// MARK: - Service calls

/// One Home Assistant service call, as the web dashboard's `service(domain, service, target, data)` helper builds it.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/mediaRemotes.ts:107`.
public struct ServiceCall: Hashable, Sendable, Codable {
    /// e.g. `remote`.
    public var domain: String
    /// e.g. `send_command`.
    public var service: String
    /// The target entity, sent as `entity_id`.
    public var target: String?
    /// Service data without the target.
    public var data: [String: JSONValue]

    /// Creates a service call.
    public init(_ domain: String, _ service: String, target: String? = nil, data: [String: JSONValue] = [:]) {
        self.domain = domain
        self.service = service
        self.target = target
        self.data = data
    }

    /// The data sent to Home Assistant: ``data`` plus `entity_id` when there is a ``target``.
    public var serviceData: [String: JSONValue] {
        var merged = data
        if let target { merged["entity_id"] = .string(target) }
        return merged
    }
}
