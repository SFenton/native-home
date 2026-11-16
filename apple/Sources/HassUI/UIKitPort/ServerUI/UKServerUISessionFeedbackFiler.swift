#if os(iOS)
import Foundation
import HassCore

// MARK: - Session-fenced feedback

/// Feedback's established HTTP API uses the same account fence as websocket commands.
@MainActor
final class UKServerUISessionFeedbackFiler: FeedbackFiling {
    private let filer: any FeedbackFiling
    private let current: () -> Bool

    init(filer: any FeedbackFiling, isCurrentSession: @escaping () -> Bool) {
        self.filer = filer
        current = isCurrentSession
    }

    private func validate() throws {
        try Task.checkCancellation()
        guard current() else { throw FeedbackFilingError.signedOut }
    }

    func isAvailable() async throws -> Bool {
        try validate()
        let available = try await filer.isAvailable()
        try validate()
        return available
    }

    func upload(_ attachment: FeedbackAttachment) async throws -> URL {
        try validate()
        let url = try await filer.upload(attachment)
        try validate()
        return url
    }

    func submit(_ report: FeedbackReport) async throws -> FiledIssue {
        try validate()
        let issue = try await filer.submit(report)
        try validate()
        return issue
    }
}
#endif
