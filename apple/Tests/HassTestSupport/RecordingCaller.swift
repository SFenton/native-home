import HassCore

/// Records service calls instead of sending them; can be told to fail. The one plain caller double for every test
/// target (`.agents/archive/audit/tests.md` finding 4).
@MainActor
public final class RecordingCaller: HassServiceCalling {
    /// One recorded call, with its data printed for easy comparison.
    public struct Call: Equatable, Sendable {
        public var domain: String
        public var service: String
        public var data: [String: String]

        public init(domain: String, service: String, data: [String: String]) {
            self.domain = domain
            self.service = service
            self.data = data
        }

        /// `domain.service`.
        public var name: String { "\(domain).\(service)" }
    }

    /// The error a failing call throws.
    public struct Failure: Error {
        public init() {}
    }

    public var calls: [Call] = []
    /// The data of each call, unprinted.
    public var raw: [[String: any Sendable]] = []
    /// Fails the next call only.
    public var failNext = false

    public init() {}

    /// `domain.service` of every call, in order.
    public var names: [String] { calls.map(\.name) }

    public func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append(Call(domain: domain, service: service, data: data.mapValues { "\($0)" }))
        raw.append(data)
        if failNext {
            failNext = false
            throw Failure()
        }
    }
}
