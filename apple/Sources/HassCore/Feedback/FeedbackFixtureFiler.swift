#if DEBUG
import Foundation

/// A ``FeedbackFiling`` that never reaches Home Assistant or GitHub, for UI tests and previews
/// (`FENTON_FEEDBACK_FIXTURE`).
///
/// - `available: false` answers like a Home Assistant without the integration.
/// - Uploads answer `https://github.com/user-attachments/assets/fixture-<n>`.
/// - Reports are filed as #1, except a title containing `fixture-failed` (GitHub problem) or `fixture-limited`
///   (rate limited).
public final class FeedbackFixtureFiler: FeedbackFiling, @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [FeedbackReport] = []
    private var uploadCount = 0
    private let available: Bool
    private let delay: Duration

    /// Creates a fixture.
    /// - Parameters:
    ///   - available: Whether reporting is set up.
    ///   - delay: Pause before each answer, so progress states are visible.
    public init(available: Bool = true, delay: Duration = .zero) {
        self.available = available
        self.delay = delay
    }

    /// Reports filed so far.
    public var submittedReports: [FeedbackReport] { lock.withLock { reports } }

    public func isAvailable() async throws -> Bool {
        try await Task.sleep(for: delay)
        return available
    }

    public func upload(_ attachment: FeedbackAttachment) async throws -> URL {
        try await Task.sleep(for: delay)
        guard available else { throw FeedbackFilingError.notConfigured }
        let count = lock.withLock { uploadCount += 1; return uploadCount }
        return URL(string: "https://github.com/user-attachments/assets/fixture-\(count)")!
    }

    public func submit(_ report: FeedbackReport) async throws -> FiledIssue {
        try await Task.sleep(for: delay)
        guard available else { throw FeedbackFilingError.notConfigured }
        if report.title.contains("fixture-failed") { throw FeedbackFilingError.githubProblem }
        if report.title.contains("fixture-limited") { throw FeedbackFilingError.rateLimited }
        lock.withLock { reports.append(report) }
        return FiledIssue(number: 1, url: URL(string: "https://github.com/example/requests/issues/1")!)
    }
}
#endif
