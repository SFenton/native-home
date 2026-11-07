import Foundation

/// The created issue.
public struct FiledIssue: Sendable, Equatable {
    public var number: Int
    /// The issue's web page.
    public var url: URL

    /// Creates a filed issue.
    public init(number: Int, url: URL) {
        self.number = number
        self.url = url
    }
}
