import Foundation

/// Saves and restores the last known entity states so a cold launch draws real values immediately.
public struct EntitySnapshotCache: Sendable {
    /// On-disk format.
    public struct Snapshot: Codable, Sendable, Equatable {
        /// Format version; bump when ``EntityState`` changes incompatibly.
        public var version: Int
        /// The server these states came from; a snapshot from another server is ignored.
        public var server: URL
        /// When the snapshot was written.
        public var savedAt: Date
        /// The states.
        public var entities: [EntityState]
    }

    static let currentVersion = 1

    private let fileURL: URL

    /// Creates a cache at a file location.
    /// - Parameter fileURL: Defaults to `Application Support/EntitySnapshot.json`.
    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appending(path: "EntitySnapshot.json")
        }
    }

    /// Loads the snapshot for a server, or `nil` if missing, stale-format or for another server.
    public func load(for server: HassServer) -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.version == Self.currentVersion,
              snapshot.server == server.baseURL else { return nil }
        return snapshot
    }

    /// Writes a snapshot atomically with file protection.
    public func save(_ entities: [EntityState], server: HassServer, at date: Date = Date()) throws {
        let snapshot = Snapshot(version: Self.currentVersion, server: server.baseURL, savedAt: date, entities: entities)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    /// Deletes the snapshot (sign out).
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
