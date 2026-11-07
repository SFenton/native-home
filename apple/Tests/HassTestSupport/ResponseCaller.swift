import HassCore

/// A response-checked caller that answers from a script, so tests drive outcomes, refusals, failures and in-flight
/// commands without Home Assistant.
@MainActor
public final class ResponseCaller: HassServiceResponding {
    /// One recorded call.
    public struct Call {
        public var domain: String
        public var service: String
        public var data: [String: any Sendable]
        /// `domain.service`.
        public var name: String { "\(domain).\(service)" }
    }

    /// The error a failing call throws.
    public struct Failure: Error {
        public init() {}
    }

    public var calls: [Call] = []
    /// Answers for response-checked calls, in order; an accepted outcome once they run out.
    public var responses: [JSONValue] = []
    /// Fails every call while set.
    public var fail = false
    /// Suspends response-checked calls until ``release()``.
    public var hold = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// `domain.service` of every call, in order.
    public var names: [String] { calls.map(\.name) }

    public func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append(Call(domain: domain, service: service, data: data))
        if fail { throw Failure() }
    }

    public func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls.append(Call(domain: domain, service: service, data: data))
        if hold { await withCheckedContinuation { waiting.append($0) } }
        if fail { throw Failure() }
        return responses.isEmpty ? .object(["outcome": "accepted"]) : responses.removeFirst()
    }

    /// Lets every held call finish.
    public func release() {
        hold = false
        let continuations = waiting
        waiting.removeAll()
        continuations.forEach { $0.resume() }
    }
}
