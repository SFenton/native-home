import Foundation

/// ``FeedbackHTTPTransport`` over a `URLSession`.
public struct URLSessionFeedbackTransport: FeedbackHTTPTransport {
    private let session: URLSession

    /// Creates a transport.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedbackFilingError.unexpectedResponse }
        return (data, http)
    }
}
