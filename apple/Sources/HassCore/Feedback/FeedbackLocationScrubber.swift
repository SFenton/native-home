#if !os(watchOS) // AVAssetExportSession is unavailable on watchOS; the Watch never attaches media.
import AVFoundation
import Foundation
import ImageIO

// MARK: - Location scrubbing

/// Removes location metadata from an app-owned media copy before it is attached.
///
/// Reports become GitHub issues (in a private repository, still shared beyond the device), and the photo picker hands over
/// originals that may carry GPS EXIF (photos) or QuickTime location (videos). Pixels and
/// samples are copied, never re-encoded; only location is dropped.
public enum FeedbackLocationScrubber {
    /// Errors when location cannot be removed; the file must not be attached.
    public enum Failure: Error, Equatable {
        /// The file is not a readable image or movie.
        case unreadable
        /// ImageIO could not read or rewrite the image.
        case image
        /// AVFoundation could not export the movie without its location.
        case movie
    }

    /// Rewrite `url` in place without location metadata, if it has any.
    ///
    /// - Parameters:
    ///   - url: An app-owned copy (never the user's original).
    ///   - isVideo: Whether the file is a movie rather than an image.
    /// - Throws: ``Failure`` when location is present and cannot be removed.
    public static func scrub(_ url: URL, isVideo: Bool) async throws {
        if isVideo {
            try await scrubMovie(url)
        } else {
            try scrubImage(url)
        }
    }

    // MARK: - Images

    /// Whether the image at `url` carries a GPS dictionary.
    ///
    /// - Parameter url: Image file.
    /// - Returns: `true` when any frame has GPS properties.
    /// - Throws: ``Failure/unreadable`` when the file is not a readable image.
    public static func imageHasLocation(_ url: URL) throws -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) != nil
        else { throw Failure.unreadable }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw Failure.unreadable }
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any]
            if properties?[kCGImagePropertyGPSDictionary] != nil { return true }
        }
        return false
    }

    private static func scrubImage(_ url: URL) throws {
        guard try imageHasLocation(url) else { return }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source)
        else { throw Failure.image }
        let output = url.deletingLastPathComponent()
            .appendingPathComponent(".scrub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }
        // Lossless metadata rewrite where ImageIO supports it (JPEG, TIFF), else
        // re-add each frame with the GPS dictionary removed (PNG, HEIC, GIF).
        let clean = { (try? imageHasLocation(output)) == false }
        guard (copyWithoutGPS(source, type: type, to: output) && clean())
                || (reencodeWithoutGPS(source, type: type, to: output) && clean())
        else { throw Failure.image }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: output)
    }

    private static func copyWithoutGPS(_ source: CGImageSource, type: CFString, to output: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type, 1, nil)
        else { return false }
        let options = [kCGImageMetadataShouldExcludeGPS: true] as CFDictionary
        return CGImageDestinationCopyImageSource(destination, source, options, nil)
    }

    private static func reencodeWithoutGPS(_ source: CGImageSource, type: CFString, to output: URL) -> Bool {
        let count = CGImageSourceGetCount(source)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type, count, nil)
        else { return false }
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return false }
            var properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any] ?? [:]
            properties[kCGImagePropertyGPSDictionary] = nil
            properties[kCGImageDestinationLossyCompressionQuality] = 1.0
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }

    // MARK: - Movies

    /// Location identifiers QuickTime and MP4 files use.
    static let locationIdentifiers: Set<AVMetadataIdentifier> = [
        .commonIdentifierLocation,
        .quickTimeMetadataLocationISO6709,
        .quickTimeUserDataLocationISO6709,
        .quickTimeMetadataLocationName,
        .quickTimeMetadataLocationBody,
        .quickTimeMetadataLocationNote,
        .quickTimeMetadataLocationRole,
        .quickTimeMetadataLocationDate,
    ]

    /// Whether the movie at `url` carries location metadata.
    ///
    /// - Parameter url: Movie file.
    /// - Returns: `true` when any location item is present.
    /// - Throws: ``Failure/unreadable`` when the file is not a readable movie.
    public static func movieHasLocation(_ url: URL) async throws -> Bool {
        let asset = AVURLAsset(url: url)
        let items: [AVMetadataItem]
        do {
            guard try await asset.load(.isReadable) else { throw Failure.unreadable }
            items = try await asset.load(.metadata)
        } catch {
            throw Failure.unreadable
        }
        return items.contains { item in
            item.identifier.map(locationIdentifiers.contains) ?? false
        }
    }

    private static func scrubMovie(_ url: URL) async throws {
        guard try await movieHasLocation(url) else { return }
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetPassthrough
        ) else { throw Failure.movie }
        export.metadataItemFilter = .forSharing()
        let type: AVFileType = url.pathExtension.lowercased() == "mov" ? .mov : .mp4
        let output = url.deletingLastPathComponent()
            .appendingPathComponent(".scrub-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: output) }
        do {
            if #available(iOS 18, macOS 15, *) {
                try await export.export(to: output, as: type)
            } else {
                export.outputURL = output
                export.outputFileType = type
                await export.export()
                guard export.status == .completed else { throw Failure.movie }
            }
        } catch {
            throw Failure.movie
        }
        guard try await !movieHasLocation(output) else { throw Failure.movie }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: output)
    }
}
#endif
