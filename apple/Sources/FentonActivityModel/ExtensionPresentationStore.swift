import Foundation

// MARK: - App-group delivery

/// Minimized accepted copy. `jobId` is the exact engine job ID (the attributes tag without `job.`).
public struct ExtensionPresentationSnapshot: Codable, Equatable, Sendable {
    public let sessionID: String
    public let revision: Int64
    public let activities: [ActivityPresentation]
    public let targets: NativeExtensionPresentation?

    /// Creates a extension presentation snapshot.
    public init(sessionID: String, revision: Int64, activities: [ActivityPresentation], targets: NativeExtensionPresentation?) throws {
        self.sessionID = sessionID
        self.revision = revision
        self.activities = activities
        self.targets = targets?.extensionCopy
        _ = try Self.decode(JSONEncoder().encode(self))
    }

    /// Decodes the value from its wire form.
    public static func decode(_ data: Data) throws -> Self {
        let object = try ExtensionJSON.object(data, maximum: 65_536)
        try ExtensionJSON.keys(object, object["targets"] == nil
            ? ["sessionID", "revision", "activities"] : ["sessionID", "revision", "activities", "targets"])
        try ExtensionJSON.text(object["sessionID"], maximum: 64, pattern: "^[a-f0-9]{64}$")
        guard let activities = object["activities"] as? [[String: Any]], activities.count <= 16 else { throw ExtensionJSON.Failure.invalid }
        if let targets = object["targets"] {
            _ = try NativeExtensionPresentation.decode(JSONSerialization.data(withJSONObject: targets))
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.revision > 0, value.revision <= 9_007_199_254_740_991,
              Set(value.activities.map(\.id)).count == value.activities.count,
              Set(value.activities.map(\.jobId)).count == value.activities.count else { throw ExtensionJSON.Failure.invalid }
        return value
    }

    /// The presentation stored for these activity attributes, or nil when none is current.
    public func presentation(for attributes: HomeActivityAttributes) -> ActivityPresentation? {
        activities.first { $0.jobId == attributes.jobID }
    }
}

/// The widget reads only this bounded file, never the publication, Keychain, HA state or a network.
public struct ExtensionPresentationStore: Sendable {
    private let directory: URL
    /// Creates a extension presentation store.
    public init(directory: URL) { self.directory = directory }
    public static var shared: Self? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ActivityAppIconStore.appGroup)
            .map { Self(directory: $0.appendingPathComponent("ServerUIExtensions", isDirectory: true)) }
    }
    private var snapshotURL: URL { directory.appendingPathComponent("presentation.json") }
    private var sessionURL: URL { directory.appendingPathComponent("session") }
    /// The route catalog file (``RouteCatalogStore``), which shares this store's account marker.
    var routesURL: URL { directory.appendingPathComponent("routes.json") }

    /// The account marker is changed before a new account can publish. Old bytes become unreadable immediately.
    public func beginSession(_ sessionID: String) throws {
        try ExtensionJSON.text(sessionID, maximum: 64, pattern: "^[a-f0-9]{64}$")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try atomicWrite(Data(sessionID.utf8), to: sessionURL)
    }

    /// Stores the snapshot in the app group, replacing the earlier one.
    public func write(_ snapshot: ExtensionPresentationSnapshot) throws {
        guard try activeSession() == snapshot.sessionID else { throw ExtensionJSON.Failure.unavailable }
        let bytes = try JSONEncoder().encode(snapshot)
        _ = try ExtensionPresentationSnapshot.decode(bytes)
        try atomicWrite(bytes, to: snapshotURL)
    }

    /// The current snapshot. A widget renders many times per update, so a decoded snapshot is reused until the session marker or
    /// the snapshot file changes (the app replaces the file atomically, which changes its identity and modification date).
    public func read() throws -> ExtensionPresentationSnapshot? {
        guard let session = try activeSession() else { return nil }
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        let key = try cacheKey(session: session)
        if let cached = Self.cache.value(for: key), cached.sessionID == session { return cached }
        let snapshot = try ExtensionPresentationSnapshot.decode(boundedRead(snapshotURL, maximum: 65_536))
        guard snapshot.sessionID == session, try activeSession() == session else { return nil }
        Self.cache.store(snapshot, for: key)
        return snapshot
    }

    private static let cache = SnapshotCache()

    private func cacheKey(session: String) throws -> String {
        let values = try snapshotURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .fileResourceIdentifierKey])
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(directory.path)|\(session)|\(modified)|\(values.fileSize ?? 0)|\(values.fileResourceIdentifier.map { "\($0)" } ?? "")"
    }

    /// Clears the marker first. A failed payload deletion cannot expose the previous account's copy.
    public func endSession(_ sessionID: String) throws {
        guard try activeSession() == sessionID else { return }
        try FileManager.default.removeItem(at: sessionURL)
        if FileManager.default.fileExists(atPath: snapshotURL.path) { try FileManager.default.removeItem(at: snapshotURL) }
        if FileManager.default.fileExists(atPath: routesURL.path) { try FileManager.default.removeItem(at: routesURL) }
    }

    /// Rolls back a first publication without invalidating the current account marker.
    public func clearPresentation(sessionID: String) throws {
        guard try activeSession() == sessionID else { throw ExtensionJSON.Failure.unavailable }
        if FileManager.default.fileExists(atPath: snapshotURL.path) { try FileManager.default.removeItem(at: snapshotURL) }
    }

    func atomicWrite(_ bytes: Data, to destination: URL) throws {
        let candidate = directory.appendingPathComponent("candidate-\(UUID().uuidString)")
        defer { if FileManager.default.fileExists(atPath: candidate.path) { try? FileManager.default.removeItem(at: candidate) } }
        try bytes.write(to: candidate, options: .atomic)
        try protect(candidate)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: candidate)
        } else {
            try FileManager.default.moveItem(at: candidate, to: destination)
        }
    }

    func activeSession() throws -> String? {
        guard FileManager.default.fileExists(atPath: sessionURL.path) else { return nil }
        let bytes = try boundedRead(sessionURL, maximum: 64)
        guard let session = String(data: bytes, encoding: .utf8) else { throw ExtensionJSON.Failure.invalid }
        try ExtensionJSON.text(session, maximum: 64, pattern: "^[a-f0-9]{64}$")
        return session
    }
    func boundedRead(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true, (values.fileSize ?? maximum + 1) <= maximum else {
            throw ExtensionJSON.Failure.invalid
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: maximum + 1) ?? Data()
        guard bytes.count <= maximum else { throw ExtensionJSON.Failure.invalid }
        return bytes
    }
    private func protect(_ url: URL) throws {
        #if os(iOS) || os(watchOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

/// The last decoded snapshot, keyed by where it came from and the identity of its file.
private final class SnapshotCache: @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    private var snapshot: ExtensionPresentationSnapshot?

    func value(for key: String) -> ExtensionPresentationSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return self.key == key ? snapshot : nil
    }

    func store(_ snapshot: ExtensionPresentationSnapshot, for key: String) {
        lock.lock(); defer { lock.unlock() }
        self.key = key
        self.snapshot = snapshot
    }
}
