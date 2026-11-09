import Foundation
import HassCore
import UniformTypeIdentifiers

/// A photo or video copied into app temporary storage, from the photo picker's item provider (before its
/// callback returns) or a file importer URL.
struct FeedbackPickedMedia {
    let url: URL

    /// Parent of every staged copy, inside the app's temporary directory.
    static let stagingFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("fenton-feedback-media", isDirectory: true)

    /// Copies `file` into its own UUID folder, keeping a safe version of its name.
    ///
    /// - Parameter file: Readable source file.
    /// - Returns: The app-owned copy.
    /// - Throws: File system errors.
    static func stage(_ file: URL) throws -> FeedbackPickedMedia {
        let folder = stagingFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(FeedbackAttachmentPolicy.sanitizedFilename(file.lastPathComponent))
        try FileManager.default.copyItem(at: file, to: destination)
        return FeedbackPickedMedia(url: destination)
    }
}

extension FeedbackPickedMedia {
    /// Stages the file an item provider (the UIKit photo picker's result) holds: movies first, as the transferable does.
    /// The provider's temporary file is deleted when the callback returns, so the copy is made inside it.
    static func load(_ provider: NSItemProvider) async throws -> FeedbackPickedMedia? {
        let type: UTType
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            type = .movie
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            type = .image
        } else {
            return nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                do { continuation.resume(returning: try stage(url)) } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
