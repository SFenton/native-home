import Foundation

/// Files reports. ``HomeAssistantFeedbackClient`` sends them through the Fenton Home Feedback integration in
/// Home Assistant (which holds the GitHub token); ``FeedbackFixtureFiler`` answers UI tests.
public protocol FeedbackFiling: Sendable {
    /// Whether Home Assistant can file reports (the integration is installed and has a working token).
    func isAvailable() async throws -> Bool
    /// Uploads one attachment and returns its GitHub URL.
    func upload(_ attachment: FeedbackAttachment) async throws -> URL
    /// Files the report; the integration composes and labels the issue.
    func submit(_ report: FeedbackReport) async throws -> FiledIssue
}
