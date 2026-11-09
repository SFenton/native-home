import Foundation
import HassCore

/// Records HTTP requests and answers from a script: the one REST double for the Home Assistant clients (feedback,
/// push) in every test target.
public final class StubHTTPTransport: FeedbackHTTPTransport, @unchecked Sendable {
    /// A scripted answer.
    public typealias Reply = (status: Int, body: String)
    private let lock = NSLock()
    private var replies: [Reply]
    private var recorded: [URLRequest] = []
    private var failure: (any Error)?

    /// Creates a transport that answers with `replies` in order, then 500.
    public init(_ replies: [Reply]) { self.replies = replies }

    /// Every request sent, in order.
    public var requests: [URLRequest] { lock.withLock { recorded } }

    /// Thrown by every request while set.
    public var error: (any Error)? {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = try lock.withLock {
            recorded.append(request)
            if let failure { throw failure }
            return replies.isEmpty ? (500, "{}") : replies.removeFirst()
        }
        return (Data(reply.body.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!)
    }
}
