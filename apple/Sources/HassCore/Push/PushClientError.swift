import Foundation

/// Why a push request failed.
public enum PushClientError: Error, Equatable, Sendable {
    /// No valid access token: the user signed out.
    case signedOut
    /// Home Assistant deleted the registration (the webhook answers 410); register again.
    case registrationGone
    /// Any other HTTP status.
    case status(Int)
    /// The body was not what the contract promises.
    case unexpectedResponse
    /// The request never completed.
    case network
}
