import FentonActivityModel
import Foundation

/// Saves and restores the last good house document so a cold launch has it before the socket connects.
///
/// The file lives in the app group container, so the widgets, Live Activities and Watch app can read it, with the
/// same file protection as the entity snapshot (``EntitySnapshotCache``). It is keyed to the signed-in server: a file
/// written for another server, in another format version, or whose document this build cannot read is deleted, not
/// used. Sign-out clears it.
public struct HouseConfigCache: Sendable {
    /// What a successful load returns.
    public struct Loaded: Equatable, Sendable {
        /// The document.
        public var config: HouseConfig
        /// The server's hash of the document.
        public var hash: String?
        /// When the file was written.
        public var savedAt: Date
    }

    /// On-disk format.
    struct File: Codable, Equatable {
        /// Format version; bump when this wrapper changes incompatibly.
        var version: Int
        /// The server the document came from.
        var server: URL
        /// When the file was written.
        var savedAt: Date
        /// The server's hash of the document.
        var hash: String?
        /// The document's `schema`, checked before the document is read.
        var schema: Int
        /// The document as ``HouseConfig/encoded()`` wrote it; read back through ``HouseConfig/decode(_:)``.
        var document: Data
    }

    /// The format version this build writes and reads.
    static let currentVersion = 1

    private let fileURL: URL

    /// Creates a cache at a file location.
    /// - Parameter fileURL: Defaults to `HouseConfig.json` in the app group container, or in Application Support
    ///   where there is no container (host tests).
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL
    }

    /// The default location.
    static var defaultURL: URL {
        let manager = FileManager.default
        let base = manager.containerURL(forSecurityApplicationGroupIdentifier: ActivityAppIconStore.appGroup)
            ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "HouseConfig.json")
    }

    /// Loads the document saved for a server, or `nil` when there is none.
    ///
    /// A file for another server, another format version or a schema this build does not read is removed; so is one
    /// whose document no longer decodes.
    public func load(for server: HassServer) -> Loaded? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let file = try? decoder.decode(File.self, from: data), file.version == Self.currentVersion,
              file.server == server.baseURL, file.schema <= HouseConfig.supportedSchema,
              let config = try? HouseConfig.decode(file.document)
        else {
            clear()
            return nil
        }
        return Loaded(config: config, hash: file.hash, savedAt: file.savedAt)
    }

    /// Writes the document atomically with file protection.
    public func save(_ config: HouseConfig, hash: String?, server: HassServer, at date: Date = .now) throws {
        let file = File(
            version: Self.currentVersion, server: server.baseURL, savedAt: date, hash: hash,
            schema: config.schema, document: try config.encoded()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(file)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    /// Deletes the file (sign-out).
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
