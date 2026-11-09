import Foundation
@preconcurrency import HAKit

/// A service caller that can also read a service's response (`return_response`). The wake light and Household
/// Away commands answer with an outcome the app must check before trusting a change.
@MainActor
public protocol HassServiceResponding: HassServiceCalling {
    /// Calls `domain.service` with `return_response` and returns the whole result (`{"response": ...}`); callers
    /// unwrap it with ``JSONValue/commandResponse`` or their own parser.
    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue
}

extension HassConnection: HassServiceResponding {
    /// Sends `call_service` with `return_response: true` once (no retry across reconnects, so a command is never
    /// applied twice) and returns the whole result.
    public func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try await callServiceReturningResult(domain, service, data: data)
    }
}

extension JSONValue {
    /// A command result's response object: `response` when the result wraps it, else the result itself.
    var commandResponse: JSONValue? {
        if case .object? = self["response"] { return self["response"] }
        if case .object = self { return self }
        return nil
    }
}

/// What a response-checked command came back with (web `useWakeLightController` `send`,
/// `useHouseholdAwayController` `send`).
public enum CommandOutcome: Equatable, Sendable {
    /// Applied, or already true (`no_change`).
    case accepted(noChange: Bool, revision: Int?)
    /// Refused with an error code; `alarmConflict` asks the editor to reload the alarm.
    case rejected(code: String, alarmConflict: Bool, revision: Int?)

    /// Reads a response object; `nil` when it carries no outcome (treated as a transport failure).
    public init?(response: JSONValue?) {
        guard let response = response?.commandResponse,
              let outcome = (response["outcome"] ?? response["status"])?.string else { return nil }
        let revision = response["revision"]?.number.map { Int($0) }
        switch outcome {
        case "accepted": self = .accepted(noChange: false, revision: revision)
        case "no_change": self = .accepted(noChange: true, revision: revision)
        default:
            let code = (response["error_code"] ?? response["error"])?.string ?? outcome
            self = .rejected(code: code, alarmConflict: response["conflict"]?.string == "alarm_revision", revision: revision)
        }
    }

    public var isAccepted: Bool { if case .accepted = self { true } else { false } }
}
