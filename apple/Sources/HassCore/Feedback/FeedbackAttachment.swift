import Foundation

/// One media file the form will upload: a private app copy, never the person's original.
public struct FeedbackAttachment: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// App-owned copy inside the app's temporary directory.
    public let fileURL: URL
    /// Sanitized display and upload name.
    public let filename: String
    /// MIME type sent with the upload.
    public let mimeType: String
    public let byteCount: Int64
    public let isVideo: Bool
    /// Whether the copy was re-encoded to fit GitHub's size limit.
    public let wasCompressed: Bool

    /// Creates an attachment record.
    ///
    /// - Parameters:
    ///   - id: Stable identity for lists.
    ///   - fileURL: App-owned copy of the media.
    ///   - filename: Name to show and upload (sanitized here).
    ///   - mimeType: `image/*` or `video/*` type.
    ///   - byteCount: File size in bytes.
    ///   - isVideo: Whether the media is a movie.
    ///   - wasCompressed: Whether the copy was re-encoded to fit.
    public init(
        id: UUID = UUID(), fileURL: URL, filename: String, mimeType: String,
        byteCount: Int64, isVideo: Bool, wasCompressed: Bool = false
    ) {
        self.id = id
        self.fileURL = fileURL
        self.filename = FeedbackAttachmentPolicy.sanitizedFilename(filename)
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.isVideo = isVideo
        self.wasCompressed = wasCompressed
    }

    /// VoiceOver label for the thumbnail button.
    ///
    /// - Parameter position: 1-based position in the list.
    /// - Returns: For example "Video 2, clip.mov, 4.2 MB".
    public func accessibilityLabel(position: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        return "\(isVideo ? "Video" : "Photo") \(position), \(filename), \(size)"
    }
}
