import Foundation

/// A failed report, phrased for the person. Mapped from the integration's stable `code` (never its text).
public enum FeedbackFilingError: LocalizedError, Equatable, Sendable {
    /// The Fenton Home Feedback integration isn't installed or set up in Home Assistant.
    case notConfigured
    /// Home Assistant couldn't file with its GitHub token (expired, revoked, no access, GitHub down).
    case githubProblem
    /// The form was refused (a field the integration validates differently).
    case invalidReport
    /// One attachment was refused.
    case attachmentRejected(String)
    case tooLarge
    case unsupportedMedia
    /// Too many reports in a short time.
    case rateLimited
    /// Home Assistant didn't accept the app's sign-in.
    case signedOut
    case network
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Reporting isn't set up in Home Assistant yet. Ask whoever manages Home Assistant to set it up."
        case .githubProblem:
            "Home Assistant couldn't file this on GitHub. Try again later, or ask whoever manages Home Assistant to check its GitHub connection."
        case .invalidReport:
            "Home Assistant couldn't accept this report. Check the boxes and try again."
        case let .attachmentRejected(name):
            "\(name) couldn't be uploaded. Remove it and try again."
        case .tooLarge:
            "An attachment is too large to send. Remove it and try again."
        case .unsupportedMedia:
            "One of the attachments isn't a supported photo or video. Remove it and try again."
        case .rateLimited:
            "Too many reports were sent just now. Try again in a few minutes."
        case .signedOut:
            "Home Assistant didn't accept the app's sign-in. Sign in again and try again."
        case .network:
            "Couldn't reach Home Assistant. Check your connection and try again."
        case .unexpectedResponse:
            "Home Assistant sent an unexpected answer. Try again."
        }
    }

    /// Maps a non-success answer from the integration.
    ///
    /// - Parameters:
    ///   - status: HTTP status.
    ///   - code: The body's `code`, when there is one.
    ///   - attachment: The file being uploaded, for upload errors.
    public static func forResponse(status: Int, code: String?, attachment: String? = nil) -> FeedbackFilingError {
        switch code {
        case "not_configured": return .notConfigured
        case "rate_limited": return .rateLimited
        case "payload_too_large": return .tooLarge
        case "unsupported_media": return .unsupportedMedia
        case "attachment_rejected": return .attachmentRejected(attachment ?? "An attachment")
        case let code? where code.hasPrefix("github_"): return .githubProblem
        case "invalid_form", "title_required", "description_required", "field_too_long", "too_many_attachments",
             "invalid_media": return .invalidReport
        default: break
        }
        switch status {
        case 401, 403: return .signedOut
        case 404: return .notConfigured
        case 413: return .tooLarge
        case 415: return .unsupportedMedia
        case 429: return .rateLimited
        case 400, 422: return .invalidReport
        case 502, 503: return .githubProblem
        default: return .unexpectedResponse
        }
    }
}
