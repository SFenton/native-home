import Foundation
import os

/// The device's copy of each person's Home Assistant photo: one data file and one JSON sidecar per person id, under
/// Application Support and excluded from backup (pattern: `.agents/patterns/avatar.md`).
///
/// Not `ImagePipeline`'s cache: that one lives in Caches and may be trimmed or cleared, evicts by size, and keys by URL.
/// A profile photo must survive until the person signs out, so it has its own store, wiped by ``removeAll()`` (sign-out).
/// Reads and writes are synchronous file operations; callers run them off the main actor.
///
/// **Generations.** ``removeAll()`` bumps a lock-guarded ``generation``. A writer reads the generation before it starts
/// (a download takes seconds) and passes it to ``save(_:metadata:for:ifGeneration:)``, ``updateMetadata(_:for:ifGeneration:)`` and
/// ``delete(personID:ifGeneration:)``, which refuse inside the same lock when it is stale. A request that began in a session that
/// has since signed out can therefore neither recreate the directory nor delete a file the next session saved for the same person.
public final class PersonAvatarStore: Sendable {
    /// A write was refused because ``removeAll()`` ran since the writer began.
    public struct StaleGeneration: Error, Equatable {}

    /// What is kept beside each photo.
    public struct Metadata: Codable, Equatable, Sendable {
        /// The picture path the bytes came from, minus `token` / `authSig` / `access_token` (``AvatarSyncPlan/pictureKey(_:)``).
        public var pictureKey: String
        /// The server's `ETag`.
        public var etag: String?
        /// The server's `Last-Modified`.
        public var lastModified: String?
        /// When the bytes were fetched or last confirmed.
        public var validatedAt: Date

        /// Creates a sidecar.
        public init(pictureKey: String, etag: String? = nil, lastModified: String? = nil, validatedAt: Date) {
            self.pictureKey = pictureKey
            self.etag = etag
            self.lastModified = lastModified
            self.validatedAt = validatedAt
        }
    }

    /// Where the files live.
    public let directory: URL

    private let generationLock = OSAllocatedUnfairLock(initialState: 0)

    /// Counts ``removeAll()`` calls; read it before starting work that will write.
    public var generation: Int { generationLock.withLock { $0 } }

    /// The default location: `Application Support/PersonAvatars`.
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "PersonAvatars", directoryHint: .isDirectory)
    }

    /// Creates a store.
    /// - Parameter directory: Injectable for tests; nil is ``defaultDirectory``. The directory is created on first write.
    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    // MARK: - Reading

    /// The photo's bytes, nil when there is none.
    public func data(for personID: String) -> Data? {
        try? Data(contentsOf: dataURL(personID))
    }

    /// The sidecar, nil when there is none or the photo file is missing (a sidecar alone is not a cached photo).
    public func metadata(for personID: String) -> Metadata? {
        guard FileManager.default.fileExists(atPath: dataURL(personID).path),
              let raw = try? Data(contentsOf: metadataURL(personID)) else { return nil }
        return try? Self.decoder.decode(Metadata.self, from: raw)
    }

    /// Every person id that has a photo on disk.
    public func personIDs() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == Self.dataExtension }
            .map { Self.personID(fromFileStem: $0.deletingPathExtension().lastPathComponent) }
            .sorted()
    }

    // MARK: - Writing

    /// Stores a photo and its sidecar, replacing both.
    /// - Parameter expected: The ``generation`` read when the work began; nil skips the check. Throws ``StaleGeneration`` when
    ///   ``removeAll()`` has run since.
    public func save(_ data: Data, metadata: Metadata, for personID: String, ifGeneration expected: Int? = nil) throws {
        try generationLock.withLock { generation in
            if let expected, expected != generation { throw StaleGeneration() }
            try prepareDirectory()
            try data.write(to: dataURL(personID), options: .atomic)
            try Self.encoder.encode(metadata).write(to: metadataURL(personID), options: .atomic)
        }
    }

    /// Rewrites only the sidecar (a `304` refreshes `validatedAt`). Does nothing when there is no photo or the generation is stale.
    public func updateMetadata(_ metadata: Metadata, for personID: String, ifGeneration expected: Int? = nil) {
        generationLock.withLock { generation in
            if let expected, expected != generation { return }
            guard FileManager.default.fileExists(atPath: dataURL(personID).path),
                  let raw = try? Self.encoder.encode(metadata) else { return }
            try? raw.write(to: metadataURL(personID), options: .atomic)
        }
    }

    /// Deletes one person's photo and sidecar. Does nothing when the generation is stale: that photo belongs to a newer session.
    public func delete(personID: String, ifGeneration expected: Int? = nil) {
        generationLock.withLock { generation in
            if let expected, expected != generation { return }
            try? FileManager.default.removeItem(at: dataURL(personID))
            try? FileManager.default.removeItem(at: metadataURL(personID))
        }
    }

    /// Deletes every photo, sidecar and the viewer record, and starts a new generation: sign-out (`AppSession.signOut()`) and an
    /// expired session. Writers that began earlier are refused from here on.
    public func removeAll() {
        generationLock.withLock { generation in
            generation += 1
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Viewer

    /// The person id that is the signed-in user, kept so a cold launch draws the right photo on the Profile button before
    /// the network answers. Wiped with the photos.
    public var viewerPersonID: String? {
        get {
            (try? String(contentsOf: viewerURL, encoding: .utf8)).flatMap { $0.isEmpty ? nil : $0 }
        }
        set {
            guard let newValue else { try? FileManager.default.removeItem(at: viewerURL); return }
            guard (try? prepareDirectory()) != nil else { return }
            try? newValue.write(to: viewerURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Files

    private static let dataExtension = "photo"
    private static let metadataExtension = "json"
    private static let viewerFile = "viewer.txt"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var viewerURL: URL { directory.appending(path: Self.viewerFile) }

    /// A person id as a file name: anything outside `[A-Za-z0-9_-]` is percent-escaped, so `person.demo_alex` is `person%2Edemo_alex`
    /// (the dot is escaped too, and a hostile id can never name a parent directory).
    static func fileStem(_ personID: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return personID.addingPercentEncoding(withAllowedCharacters: allowed) ?? "person"
    }

    private static func personID(fromFileStem stem: String) -> String { stem.removingPercentEncoding ?? stem }

    private func dataURL(_ personID: String) -> URL {
        directory.appending(path: Self.fileStem(personID) + "." + Self.dataExtension)
    }

    private func metadataURL(_ personID: String) -> URL {
        directory.appending(path: Self.fileStem(personID) + "." + Self.metadataExtension)
    }

    /// Creates the directory and marks it excluded from backup (photos are re-downloadable).
    private func prepareDirectory() throws {
        var url = directory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
