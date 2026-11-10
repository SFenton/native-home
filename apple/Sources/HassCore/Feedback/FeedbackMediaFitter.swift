#if !os(watchOS) // movie encoding is unavailable on watchOS; the Watch never attaches media.
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks an app-owned media copy until it fits GitHub's user-attachment limit.
///
/// FestivalNativeApps' service transcodes oversized media on the server; here the app files the issue
/// itself, so it re-encodes on the device: photos step down in size as JPEG, videos are re-encoded at a bitrate
/// computed from their duration (``FeedbackMovieEncoder``). Files already under the limit are left byte-for-byte.
public enum FeedbackMediaFitter {
    /// The fitted file.
    public struct Fitted: Sendable, Equatable {
        /// The file to attach (the input when it already fit).
        public let url: URL
        public let byteCount: Int64
        /// Whether it was re-encoded.
        public let compressed: Bool
    }

    /// Why a file couldn't be fitted.
    public enum Failure: Error, Equatable {
        /// Every step was still over the limit.
        case tooLarge
        /// The file isn't a readable image or movie.
        case unreadable
    }

    /// Longest image edges tried, largest first.
    static let imageEdges: [Int] = [4096, 3072, 2048, 1536, 1024]

    /// Returns `url` when it fits, else a smaller copy beside it (the original copy is deleted).
    ///
    /// - Parameters:
    ///   - url: An app-owned copy.
    ///   - isVideo: Whether it is a movie.
    ///   - limit: Largest allowed size in bytes.
    /// - Throws: ``Failure`` when it can't be read or made small enough.
    public static func fit(_ url: URL, isVideo: Bool, limit: Int64 = FeedbackLimits.attachmentBytes) async throws -> Fitted {
        let size = try byteCount(url)
        if size <= limit { return Fitted(url: url, byteCount: size, compressed: false) }
        let fitted = isVideo ? try await fitMovie(url, limit: limit) : try fitImage(url, limit: limit)
        try? FileManager.default.removeItem(at: url)
        return fitted
    }

    /// The file's size on disk. Read from the file system each time: `URL.resourceValues` caches per URL
    /// value, so it would report a stale size for a file rewritten at the same URL.
    static func byteCount(_ url: URL) throws -> Int64 {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else {
            throw Failure.unreadable
        }
        return size.int64Value
    }

    // MARK: - Images

    private static func fitImage(_ url: URL, limit: Int64) throws -> Fitted {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw Failure.unreadable
        }
        let output = url.deletingPathExtension().appendingPathExtension("jpg")
        let target = output == url ? url.deletingLastPathComponent().appendingPathComponent("fitted-\(output.lastPathComponent)") : output
        for edge in imageEdges {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: edge,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw Failure.unreadable }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
            let size = try byteCount(target)
            if size <= limit { return Fitted(url: target, byteCount: size, compressed: true) }
        }
        try? FileManager.default.removeItem(at: target)
        throw Failure.tooLarge
    }

    // MARK: - Movies

    private static func fitMovie(_ url: URL, limit: Int64) async throws -> Fitted {
        let target = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-small.mp4")
        let size = try await FeedbackMovieEncoder.encode(url, to: target, limit: limit)
        return Fitted(url: target, byteCount: size, compressed: true)
    }
}
#endif
