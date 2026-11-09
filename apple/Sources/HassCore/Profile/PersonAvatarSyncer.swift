import CoreGraphics
import Foundation
import ImageIO

/// Carries out one person's ``AvatarSyncPlan``: reads the cache, makes the (conditional) request, stores the bytes and says what
/// the screen should do. Everything here is `Sendable` and `async`; ``PersonAvatars`` runs it off the main actor.
///
/// Never deletes on doubt: a transport error, a non-success status, or bytes that are not an image all report ``Outcome/unchanged``
/// and leave the files alone. Only ``AvatarSyncPlan/Action/delete`` removes a file.
public struct PersonAvatarSyncer: Sendable {
    /// What happened to one person's photo.
    public enum Outcome: Equatable, Sendable {
        /// The cache stands (kept, `304`, or any failure). `confirmed` says the server was heard from.
        case unchanged(confirmed: Bool)
        /// New bytes are stored (read them from the store). `replaced` is true when a photo was already shown.
        case updated(replaced: Bool)
        /// The photo was deleted: the server has none.
        case removed
    }

    /// The server a picture path is resolved against, and the only host that is sent the Bearer token.
    public struct Server: Sendable {
        /// The signed-in server's base URL.
        public var baseURL: URL
        /// Supplies a valid access token (`TokenManager.validAccessToken()`); called only for a same-host request.
        public var accessToken: @Sendable () async -> String?

        /// Creates a server value.
        public init(baseURL: URL, accessToken: @escaping @Sendable () async -> String?) {
            self.baseURL = baseURL
            self.accessToken = accessToken
        }
    }

    /// The photo store.
    public let store: PersonAvatarStore
    private let session: URLSession
    private let now: @Sendable () -> Date

    /// Creates a syncer.
    /// - Parameters:
    ///   - store: Where photos are kept.
    ///   - session: Injectable for tests (a stub `URLProtocol`); the default is an ephemeral session, so the photo's HTTP
    ///     response is never cached a second time by the system.
    ///   - now: The clock, for `validatedAt`.
    public init(store: PersonAvatarStore, session: URLSession? = nil, now: @escaping @Sendable () -> Date = { .now }) {
        self.store = store
        self.session = session ?? URLSession(configuration: .ephemeral)
        self.now = now
    }

    // MARK: - Sync

    /// Plans and performs the step for one person.
    /// - Parameters:
    ///   - personID: The `person.*` entity id.
    ///   - picture: Its `entity_picture` attribute.
    ///   - entityLoaded: The entity has arrived live (see ``AvatarSyncPlan/plan(cached:serverPicture:entityLoaded:validatedThisLaunch:)``).
    ///   - validatedThisLaunch: The same path was already confirmed in this launch.
    ///   - server: The signed-in server.
    public func sync(personID: String, picture: String?, entityLoaded: Bool, validatedThisLaunch: Bool, server: Server) async -> Outcome {
        // Everything this call writes is refused if the store is wiped (sign-out) before it lands.
        let generation = store.generation
        let cached = store.metadata(for: personID)
        let action = AvatarSyncPlan.plan(cached: cached, serverPicture: picture, entityLoaded: entityLoaded,
                                         validatedThisLaunch: validatedThisLaunch)
        switch action {
        case .keep:
            // Nothing to ask: already confirmed this launch, nothing on either side, or the entity has not loaded.
            return .unchanged(confirmed: entityLoaded)
        case .delete:
            store.delete(personID: personID, ifGeneration: generation)
            return .removed
        case .download, .replace, .revalidate:
            guard let picture, let url = Self.resolve(picture, against: server.baseURL) else { return .unchanged(confirmed: false) }
            let conditional = action == .revalidate ? cached : nil
            return await fetch(personID: personID, picture: picture, url: url, conditional: conditional, hadPhoto: cached != nil,
                               server: server, generation: generation)
        }
    }

    /// A picture path as an absolute `http` or `https` URL: a relative `/api/image/serve/…` resolves against the server; an
    /// absolute URL stays. Any other scheme (`file:`, `data:`, `mailto:`) is refused.
    public static func resolve(_ picture: String, against baseURL: URL) -> URL? {
        guard let url = URL(string: picture, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// Whether two URLs share an origin: the same scheme, host and port (a scheme's default port counts as explicit).
    public static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let leftScheme = lhs.scheme?.lowercased(), let rightScheme = rhs.scheme?.lowercased(), leftScheme == rightScheme,
              let leftHost = lhs.host?.lowercased(), let rightHost = rhs.host?.lowercased(), leftHost == rightHost else { return false }
        func port(_ url: URL, _ scheme: String) -> Int { url.port ?? (scheme == "https" ? 443 : 80) }
        return port(lhs, leftScheme) == port(rhs, rightScheme)
    }

    /// Whether `url` may be sent the Bearer token: its scheme, host and port are the signed-in server's, so the token never
    /// travels in clear text to a server reached over `https`, and never to another service on the same host.
    public static func sendsToken(to url: URL, server baseURL: URL) -> Bool {
        sameOrigin(url, baseURL)
    }

    // MARK: - Limits

    /// The most bytes a photo response may have. Home Assistant serves 512 px images of tens of kilobytes.
    public static let maxBytes = 5 << 20
    /// The most pixels a photo may have (checked from the header, before any decode).
    public static let maxPixels = 50_000_000
    /// The whole request, not just idle time, may take this long.
    public static let deadline: Duration = .seconds(30)

    // MARK: - Fetch

    private func fetch(personID: String, picture: String, url: URL, conditional: PersonAvatarStore.Metadata?, hadPhoto: Bool,
                       server: Server, generation: Int) async -> Outcome {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        if let conditional {
            if let etag = conditional.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let modified = conditional.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        }
        // The token goes only to the signed-in server's origin, and is asked for only then.
        if Self.sendsToken(to: url, server: server.baseURL), let token = await server.accessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, http) = await download(request) else { return .unchanged(confirmed: false) }
        switch http.statusCode {
        case 304:
            guard var metadata = conditional else { return .unchanged(confirmed: false) }
            metadata.validatedAt = now()
            store.updateMetadata(metadata, for: personID, ifGeneration: generation)
            return .unchanged(confirmed: true)
        case 200..<300:
            // Only bytes that pass the gate (size, pixels, a real decode) are stored: a truncated or hostile body never
            // replaces a good photo and is never left on disk to fail again at the next launch.
            guard Self.validate(data) else { return .unchanged(confirmed: false) }
            let metadata = PersonAvatarStore.Metadata(
                pictureKey: AvatarSyncPlan.pictureKey(picture), etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified"), validatedAt: now()
            )
            // The server re-sent the file we have (no validators, or a new path to the same image): nothing changes on screen.
            if hadPhoto, store.data(for: personID) == data {
                store.updateMetadata(metadata, for: personID, ifGeneration: generation)
                return .unchanged(confirmed: true)
            }
            guard (try? store.save(data, metadata: metadata, for: personID, ifGeneration: generation)) != nil else {
                return .unchanged(confirmed: false)
            }
            return .updated(replaced: hadPhoto)
        default:
            return .unchanged(confirmed: false)
        }
    }

    /// The response, streamed with a byte cap and a whole-request deadline; nil on any failure.
    private func download(_ request: URLRequest) async -> (Data, HTTPURLResponse)? {
        let session = session
        return await withTaskGroup(of: (Data, HTTPURLResponse)?.self) { group in
            group.addTask {
                guard let (bytes, response) = try? await session.bytes(for: request, delegate: RedirectGuard()),
                      let http = response as? HTTPURLResponse else { return nil }
                if http.statusCode == 304 { return (Data(), http) }
                if response.expectedContentLength > Int64(Self.maxBytes) { return nil }
                var data = Data()
                do {
                    for try await byte in bytes {
                        data.append(byte)
                        if data.count > Self.maxBytes { return nil }
                    }
                } catch { return nil }
                // A body shorter than the server announced was cut off (images are not content-encoded).
                if response.expectedContentLength > 0, Int64(data.count) != response.expectedContentLength { return nil }
                return (data, http)
            }
            group.addTask {
                try? await Task.sleep(for: Self.deadline)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Validation

    /// Whether `data` is a photo worth keeping: within ``maxBytes``, within ``maxPixels`` by its header, and it decodes.
    public static func validate(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maxBytes, let pixels = pixelCount(data), pixels > 0, pixels <= maxPixels else { return false }
        // ImageIO is lenient: a truncated PNG or JPEG still yields a partial thumbnail and reports itself complete. Both formats
        // end with a marker, so a body without it was cut short.
        guard hasEndMarker(data) else { return false }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              Self.thumbnail(from: source, maxPixel: decodePixels) != nil else { return false }
        return CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
    }

    /// Whether a PNG ends with its `IEND` chunk or a JPEG with `FF D9` (trailing zero padding allowed); other formats pass.
    static func hasEndMarker(_ data: Data) -> Bool {
        let png: [UInt8] = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
        let bytes = [UInt8](data.prefix(8))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return Array(data.suffix(8)) == png }
        if bytes.starts(with: [0xFF, 0xD8]) {
            var tail = data[...]
            while tail.last == 0 { tail = tail.dropLast() }
            return Array(tail.suffix(2)) == [0xFF, 0xD9]
        }
        return true
    }

    /// Width times height from the image header, without decoding.
    public static func pixelCount(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return width * height
    }

    // MARK: - Decoding

    /// The pixel size photos are decoded at (`ImagePipeline.bucket` step). The largest disc is the Account header: 84 pt, grown
    /// by Dynamic Type up to about 1.76x at AX5, on a 3x screen is about 444 px. 512 covers it (and is the size Home Assistant
    /// serves); the 44 pt and 36 pt discs scale it down. One decode per person, not one per size.
    public static let decodePixels = 512

    /// ``decode(_:maxPixel:)`` from an `async` context: a nonisolated async function runs on the global executor, not the caller's actor,
    /// so a main-actor caller's decode happens off the main thread without detaching a task.
    public static func decodeOffMain(_ data: Data) async -> CGImage? { decode(data) }

    /// The stored photo for a person, decoded off the caller's actor.
    public func storedImage(for personID: String) async -> CGImage? {
        store.data(for: personID).flatMap { Self.decode($0) }
    }

    /// Decodes `data` with its longest side at most `maxPixel`, forced now (call off the main thread).
    public static func decode(_ data: Data, maxPixel: Int = decodePixels) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(from: source, maxPixel: maxPixel)
    }

    private static func thumbnail(from source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Drops the `Authorization` header when a redirect leaves the original origin (scheme, host or port), and refuses a redirect to
/// anything but `http` or `https`.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let target = request.url, let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        var next = request
        if let original = task.originalRequest?.url, !PersonAvatarSyncer.sameOrigin(original, target) {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return next
    }
}
