import Foundation
import HassCore

/// Answers webhook commands by their `type`, not by arrival order, for tests where two commands (the location and the
/// sensors) are sent at the same time. A command with no scripted reply gets `200 {}`.
public final class RoutingHTTPTransport: FeedbackHTTPTransport, @unchecked Sendable {
    /// A scripted answer.
    public typealias Reply = (status: Int, body: String)
    private let lock = NSLock()
    private var replies: [String: [Reply]]
    private var recorded: [URLRequest] = []
    private var gates: [String: AsyncGate] = [:]

    /// Creates a transport that answers each command type from its own list, in order, then `200 {}`.
    public init(_ replies: [String: [Reply]] = [:]) { self.replies = replies }

    /// Every request sent, in order.
    public var requests: [URLRequest] { lock.withLock { recorded } }

    /// The `type` of every request sent, in order.
    public var types: [String] { requests.map(Self.type(of:)) }

    /// The bodies of every request of `type`, in order.
    public func bodies(of type: String) -> [[String: Any]] {
        requests.filter { Self.type(of: $0) == type }.compactMap { request in
            request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    /// Holds every request of `type` at `gate` until the test opens it.
    public func hold(_ type: String, at gate: AsyncGate) { lock.withLock { gates[type] = gate } }

    /// Appends scripted answers for `type`.
    public func script(_ type: String, _ more: [Reply]) { lock.withLock { replies[type, default: []] += more } }

    static func type(of request: URLRequest) -> String {
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return body?["type"] as? String ?? request.url?.path ?? ""
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let type = Self.type(of: request)
        let (reply, gate): (Reply, AsyncGate?) = lock.withLock {
            recorded.append(request)
            var next: Reply = (200, "{}")
            if replies[type]?.isEmpty == false { next = replies[type]!.removeFirst() }
            return (next, gates[type])
        }
        if let gate { await gate.wait() }
        return (Data(reply.body.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!)
    }
}
