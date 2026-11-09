import Foundation

/// Why a picked file was not attached.
public enum FeedbackAttachmentRejection: LocalizedError, Equatable, Sendable {
    case tooMany
    /// Still larger than GitHub's limit after compression (or too large to try).
    case fileTooLarge(String)
    case unsupportedType(String)
    case unreadable
    /// Location metadata could not be removed, so the file stays private.
    case locationNotRemoved(String)

    public var errorDescription: String? {
        let limit = ByteCountFormatter.string(fromByteCount: FeedbackLimits.attachmentBytes, countStyle: .file)
        switch self {
        case .tooMany:
            return "You can attach up to \(FeedbackLimits.attachments) photos or videos."
        case let .fileTooLarge(name):
            return "\(name) couldn't be made smaller than \(limit). Trim the recording and try again."
        case let .unsupportedType(name):
            return "\(name) isn't a photo or video."
        case .unreadable:
            return "That file couldn't be attached. Try another."
        case let .locationNotRemoved(name):
            return "\(name) wasn't attached because its location couldn't be removed."
        }
    }
}
