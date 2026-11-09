import Foundation

/// A command that got no answer in time: the socket died under it, or HAKit dropped it on a reset.
public struct CommandTimeout: Error, Equatable, Sendable {
    /// The command that timed out.
    public let command: String
}
