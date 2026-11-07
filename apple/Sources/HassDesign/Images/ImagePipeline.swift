import CryptoKit
import Foundation
import HassTelemetry
import ImageIO
import os

/// Loads, caches and downsamples remote images (pattern: `.agents/patterns/image-cache.md`).
///
/// - **Memory:** decoded, downsampled images, so a cell scrolling back into view draws on its first frame.
/// - **Disk:** the original bytes plus validators (`ETag`, `Last-Modified`) under Caches, so a cold launch
///   shows the last images without the network.
/// - **Updates:** an image is shown from cache at once, then revalidated in the background when it is stale:
///   - the same URL older than its max age (the server's `Cache-Control: max-age`, else ``defaultMaxAge``) is
///     re-requested with `If-None-Match` / `If-Modified-Since`; a `304` keeps the cached bytes, a `200` replaces
///     them and the view cross-fades to the new image;
///   - a different URL for the same ``key(for:)`` (Home Assistant rotated a camera's `token`, or a media
///     player's `cache` hash changed with the artwork) is fetched at once while the previous image stays up.
/// - **Decoding** happens off the main thread at the size the view draws (`kCGImageSourceThumbnailMaxPixelSize`),
///   so a 4000 px recipe photo never decodes at full size on the main thread mid-scroll.
public final class ImagePipeline: Sendable {
    private static let log = Logger(subsystem: "com.sfenton.home", category: "Images")

    // MARK: - Types

    /// What the disk store keeps beside each image's bytes.
    public struct Metadata: Codable, Equatable, Sendable {
        /// A digest of the exact URL the bytes came from. The URL itself isn't stored: Home Assistant's camera
        /// and media URLs carry access tokens, which have no place on disk.
        public var source: String
        /// When the bytes were fetched or last revalidated.
        public var validatedAt: Date
        /// The server's `ETag`.
        public var etag: String?
        /// The server's `Last-Modified`.
        public var lastModified: String?
        /// How long the bytes stay fresh.
        public var maxAge: TimeInterval

        /// Creates metadata.
        public init(sourceURL: URL, validatedAt: Date, etag: String? = nil, lastModified: String? = nil, maxAge: TimeInterval) {
            source = ImagePipeline.digest(sourceURL.absoluteString)
            self.validatedAt = validatedAt
            self.etag = etag
            self.lastModified = lastModified
            self.maxAge = maxAge
        }
    }

    /// Why a cached image is or isn't used as is.
    public enum Freshness: Equatable, Sendable {
        /// Same URL within its max age: no request.
        case fresh
        /// Same URL past its max age: a conditional request.
        case stale
        /// Same key, different URL: a full request.
        case replaced
    }

    // MARK: - Configuration

    /// Max age when the server gives none. Home Assistant's proxies send none; recipe CDNs usually do.
    public static let defaultMaxAge: TimeInterval = 5 * 60
    /// Query items that authorize a URL without identifying the image; dropped from cache keys.
    public static let volatileQueryItems: Set<String> = ["token", "authSig", "access_token"]
    /// Disk budget; the oldest files go first once it is passed.
    public let diskLimit: Int

    /// The app's pipeline.
    public static let shared = ImagePipeline()

    // MARK: - Storage

    private final class MemoryEntry {
        let image: CGImage
        let maxPixel: Int
        init(image: CGImage, maxPixel: Int) {
            self.image = image
            self.maxPixel = maxPixel
        }
    }

    private struct MemoryCache: @unchecked Sendable {
        // NSCache is thread-safe.
        let cache = NSCache<NSString, MemoryEntry>()
    }

    private let memory = MemoryCache()
    private let directory: URL
    private let session: URLSession
    private let inFlight = OSAllocatedUnfairLock<[String: Task<Data?, Never>]>(initialState: [:])

    /// Creates a pipeline.
    /// - Parameters:
    ///   - directory: Where bytes and metadata live; defaults to `Caches/FentonImages`.
    ///   - session: The session that fetches (tests pass one with a stub protocol).
    ///   - memoryLimit: Decoded bytes kept in memory.
    ///   - diskLimit: Bytes kept on disk.
    public init(directory: URL? = nil, session: URLSession? = nil, memoryLimit: Int = 96 << 20, diskLimit: Int = 200 << 20) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? caches.appendingPathComponent("FentonImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            // This pipeline is the cache; URLCache would only keep a second copy.
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpMaximumConnectionsPerHost = 6
            self.session = URLSession(configuration: configuration)
        }
        self.diskLimit = diskLimit
        memory.cache.totalCostLimit = memoryLimit
    }

    // MARK: - Keys and freshness

    /// The cache key for a URL: the URL without query items that only authorize it (``volatileQueryItems``), so a
    /// rotated token finds the image already on disk.
    public static func key(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url.absoluteString }
        if let items = components.queryItems {
            let kept = items.filter { !volatileQueryItems.contains($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    /// Whether cached bytes described by `metadata` can be used for `url` without asking the server.
    public static func freshness(of metadata: Metadata, for url: URL, now: Date = .now) -> Freshness {
        if metadata.source != digest(url.absoluteString) { return .replaced }
        return now.timeIntervalSince(metadata.validatedAt) < metadata.maxAge ? .fresh : .stale
    }

    /// The max age a response allows: `Cache-Control: max-age`, `no-cache`/`no-store` as zero, else the default.
    public static func maxAge(from response: HTTPURLResponse) -> TimeInterval {
        guard let control = response.value(forHTTPHeaderField: "Cache-Control")?.lowercased() else { return defaultMaxAge }
        if control.contains("no-store") || control.contains("no-cache") { return 0 }
        for part in control.split(separator: ",") {
            let pair = part.trimmingCharacters(in: .whitespaces).split(separator: "=")
            if pair.count == 2, pair[0] == "max-age", let seconds = TimeInterval(pair[1]) { return seconds }
        }
        return defaultMaxAge
    }

    /// Rounds a requested pixel size up to a 128 px step, so nearby sizes share one decoded image.
    public static func bucket(_ maxPixel: Int) -> Int {
        guard maxPixel > 0 else { return 1024 }
        return ((maxPixel + 127) / 128) * 128
    }

    // MARK: - Reading

    /// An image already decoded in memory for `url`'s key, at any size, for a view's first frame.
    public func memoryImage(for url: URL) -> CGImage? {
        memory.cache.object(forKey: Self.key(for: url) as NSString)?.image
    }

    /// The images to show for `url`, best first: the cached image (memory or disk) at once if there is one, then
    /// the fetched or revalidated image if it differs. Finishes without yielding when nothing loads.
    /// - Parameters:
    ///   - url: The image URL.
    ///   - maxPixel: The longest side the view draws, in pixels.
    public func images(for url: URL, maxPixel: Int) -> AsyncStream<CGImage> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                await self.load(url, maxPixel: Self.bucket(maxPixel)) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func load(_ url: URL, maxPixel: Int, yield: @Sendable (CGImage) -> Void) async {
        let key = Self.key(for: url)
        let stored = readMetadata(key)
        var shown = false

        if let entry = memory.cache.object(forKey: key as NSString), entry.maxPixel >= maxPixel {
            Telemetry.count("image.memoryHits")
            yield(entry.image)
            shown = true
        } else if let stored, let data = readData(key), let image = decode(data, maxPixel: maxPixel) {
            Telemetry.count("image.diskHits")
            remember(image, key: key, maxPixel: maxPixel)
            yield(image)
            shown = true
        }

        let freshness = stored.map { Self.freshness(of: $0, for: url) }
        if shown, freshness == .fresh { return }
        guard !Task.isCancelled else { return }

        // Stale (same URL) revalidates with validators; replaced or missing fetches in full.
        let conditional = freshness == .stale ? stored : nil
        guard let data = await fetch(url, key: key, conditional: conditional) else { return }
        guard !Task.isCancelled, let image = decode(data, maxPixel: maxPixel) else { return }
        remember(image, key: key, maxPixel: maxPixel)
        yield(image)
    }

    // MARK: - Network

    /// Fetches `url`, sharing one request per key. Returns new bytes, or `nil` for `304`, failures and errors.
    private func fetch(_ url: URL, key: String, conditional: Metadata?) async -> Data? {
        let task: Task<Data?, Never> = inFlight.withLock { tasks in
            if let existing = tasks[key] { return existing }
            let created = Task { await self.request(url, key: key, conditional: conditional) }
            tasks[key] = created
            return created
        }
        let data = await task.value
        inFlight.withLock { tasks in
            if tasks[key] == task { tasks[key] = nil }
        }
        return data
    }

    private func request(_ url: URL, key: String, conditional: Metadata?) async -> Data? {
        var request = URLRequest(url: url)
        if let etag = conditional?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = conditional?.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let interval = Telemetry.begin(Telemetry.Name.imageFetch)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                Telemetry.end(interval, detail: "not-http")
                return nil
            }
            if http.statusCode == 304, var metadata = conditional {
                metadata.validatedAt = .now
                metadata.maxAge = Self.maxAge(from: http)
                writeMetadata(metadata, key: key)
                Telemetry.end(interval, detail: "304")
                Telemetry.count("image.notModified")
                return nil
            }
            guard (200..<300).contains(http.statusCode), !data.isEmpty else {
                Telemetry.end(interval, detail: "\(http.statusCode)")
                Telemetry.count("image.failures")
                return nil
            }
            let metadata = Metadata(
                sourceURL: url, validatedAt: .now,
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                maxAge: Self.maxAge(from: http)
            )
            write(data, metadata: metadata, key: key)
            Telemetry.end(interval, value: Double(data.count), detail: "200")
            Telemetry.count(conditional == nil ? "image.fetches" : "image.changed")
            return data
        } catch {
            Telemetry.end(interval, detail: "error")
            Telemetry.count("image.failures")
            return nil
        }
    }

    // MARK: - Decoding

    /// Decodes `data` with its longest side at most `maxPixel`, forcing the decode now (off the main thread)
    /// rather than at first draw.
    public func decode(_ data: Data, maxPixel: Int) -> CGImage? {
        Telemetry.measure(Telemetry.Name.imageDecode) {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
    }

    private func remember(_ image: CGImage, key: String, maxPixel: Int) {
        memory.cache.setObject(MemoryEntry(image: image, maxPixel: maxPixel),
                               forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }

    // MARK: - Disk

    /// Hex SHA-256 of `text`, for file names and stored source URLs.
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(_ key: String, _ suffix: String) -> URL {
        directory.appendingPathComponent(Self.digest(key) + suffix)
    }

    private func readMetadata(_ key: String) -> Metadata? {
        guard let data = try? Data(contentsOf: fileURL(key, ".json")) else { return nil }
        return try? JSONDecoder().decode(Metadata.self, from: data)
    }

    private func readData(_ key: String) -> Data? {
        let url = fileURL(key, ".img")
        // Touch it so trimming drops the least recently shown images first.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return try? Data(contentsOf: url)
    }

    private func writeMetadata(_ metadata: Metadata, key: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        do { try data.write(to: fileURL(key, ".json"), options: .atomic) } catch {
            Self.log.error("image metadata write failed: \(String(describing: error), privacy: .public)")
        }
    }

    #if canImport(UIKit)
    private static let imageWriteOptions: Data.WritingOptions = [.atomic, .completeFileProtection]
    #else
    private static let imageWriteOptions: Data.WritingOptions = .atomic
    #endif

    private func write(_ data: Data, metadata: Metadata, key: String) {
        // Complete protection: stills (security-camera frames above all) are unreadable while the device is locked.
        do { try data.write(to: fileURL(key, ".img"), options: Self.imageWriteOptions) } catch {
            Self.log.error("image write failed (disk full?): \(String(describing: error), privacy: .public)")
        }
        writeMetadata(metadata, key: key)
        Telemetry.count("image.bytesWritten", by: data.count)
    }

    /// Deletes the oldest images until the disk store is under ``diskLimit``.
    public func trimDisk() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
            .filter({ $0.pathExtension == "img" }) else { return }
        var entries = files.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.2 }
        guard total > diskLimit else { return }
        entries.sort { $0.1 < $1.1 }
        for (url, _, size) in entries where total > diskLimit {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("json"))
            total -= size
        }
    }

    /// Bytes on disk and file count, for the Performance screen.
    public func diskUsage() -> (bytes: Int, files: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "img" }) ?? []
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (bytes, files.count)
    }

    /// Empties memory and disk.
    public func removeAll() {
        memory.cache.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
