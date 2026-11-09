import Foundation

/// One HTTP exchange; injectable so tests never reach the network.
public protocol FeedbackHTTPTransport: Sendable {
    /// Sends a request and returns the body and response.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
