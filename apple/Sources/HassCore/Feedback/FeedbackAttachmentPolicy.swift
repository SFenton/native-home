import Foundation
import UniformTypeIdentifiers

/// Admission rules and naming for attachments.
public enum FeedbackAttachmentPolicy {
    /// Checks a candidate against the count and per-file limits.
    ///
    /// - Parameters:
    ///   - byteCount: Candidate size after compression.
    ///   - filename: Candidate name, for messages.
    ///   - existing: Already attached files.
    /// - Returns: nil when it fits, otherwise the reason it does not.
    public static func rejection(
        byteCount: Int64, filename: String, existing: [FeedbackAttachment]
    ) -> FeedbackAttachmentRejection? {
        if existing.count >= FeedbackLimits.attachments { return .tooMany }
        if byteCount > FeedbackLimits.attachmentBytes { return .fileTooLarge(filename) }
        return nil
    }

    /// Classifies a file as an uploadable photo or video.
    ///
    /// - Parameter filename: Name with extension.
    /// - Returns: MIME type and video flag, or nil when it is neither an image nor a movie.
    public static func media(forFilename filename: String) -> (mimeType: String, isVideo: Bool)? {
        let ext = (filename as NSString).pathExtension
        guard let type = UTType(filenameExtension: ext) else { return nil }
        let isVideo = type.conforms(to: .movie) || type.conforms(to: .video)
        guard isVideo || type.conforms(to: .image) else { return nil }
        let mime = type.preferredMIMEType ?? (isVideo ? "video/quicktime" : "image/jpeg")
        return (mime, isVideo)
    }

    /// A safe single-line name for display and the upload.
    ///
    /// - Parameter raw: Picked file name.
    /// - Returns: The last path component without quotes, control characters or separators, at most
    ///   120 characters; `attachment` when nothing remains.
    public static func sanitizedFilename(_ raw: String) -> String {
        let last = raw.split(separator: "/").last.map(String.init) ?? raw
        let cleaned = last.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !"\"\\/:[]()<>".unicodeScalars.contains($0)
        }
        let name = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "attachment" }
        guard name.count > 120 else { return name }
        let ext = (name as NSString).pathExtension
        let keep = 120 - (ext.isEmpty ? 0 : ext.count + 1)
        return String(name.prefix(keep)) + (ext.isEmpty ? "" : ".\(ext)")
    }
}
