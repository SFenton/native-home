import Foundation

/// Client-side bounds for a report. GitHub caps an issue body at 65,536 characters and a user
/// attachment at 10 MB, so the text boxes and media stay well inside those.
public enum FeedbackLimits {
    /// Title, prefix included (UTF-16 units).
    public static let titleCharacters = 200
    /// Per text box: Description, Steps to Reproduce, Expected Behavior (UTF-16 units).
    public static let bodyCharacters = 10_000
    /// Attachments per report.
    public static let attachments = 4
    /// Bytes per attached file after compression: GitHub's user-attachment limit (10 MiB).
    public static let attachmentBytes: Int64 = 10 * 1024 * 1024
    /// Largest original the form tries to compress (videos are re-encoded to fit ``attachmentBytes``).
    public static let originalBytes: Int64 = 2 * 1024 * 1024 * 1024
}
