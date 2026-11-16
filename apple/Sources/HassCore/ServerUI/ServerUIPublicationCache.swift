import Darwin
import Foundation
import os

// MARK: - Record

/// One cached publication. It holds no credential: the layout, the integration's ordering and the user it was delivered to.
struct ServerUIPublicationRecord: Codable, Equatable, Sendable {
    /// The format this build writes and reads.
    static let currentVersion = 2

    var version = Self.currentVersion
    /// The server origin (``ServerUIPublicationPartition/origin``).
    var origin: String
    /// The Home Assistant user the layout was delivered to.
    var userID: String
    /// The integration's store epoch; a change invalidates revision ordering.
    var epoch: String
    /// The integration's revision, kept here so ordering never needs a decode.
    var revision: Int
    /// The integration's change-detection hash of the envelope.
    var envelopeSha256: String
    /// The envelope as ``ServerUICompositionPublication/decode(_:)`` reads it.
    var bytes: Data
}

// MARK: - File

/// The cache file's I/O, free of locks and actors so a cold launch can read it synchronously and the actor can serialize writes.
enum ServerUIPublicationFile {
    /// The envelope ceiling plus base64 expansion and the record's own fields.
    static let maximumBytes = ((ServerUICompositionJSON.maximumBytes + 2) / 3) * 4 + 4096

    static func url(in directory: URL, partition: ServerUIPublicationPartition) -> URL {
        directory.appendingPathComponent("ServerUIPublications", isDirectory: true)
            .appendingPathComponent(partition.digest + ".json")
    }

    /// Reads and validates the record, or `nil` when there is none. Never follows a symbolic link.
    static func read(at file: URL, partition: ServerUIPublicationPartition) throws -> ServerUIPublicationRecord? {
        try checkDirectory(file.deletingLastPathComponent())
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw ServerUIStoreError.cacheRead
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size >= 0, metadata.st_size <= maximumBytes else { throw ServerUIStoreError.corruptCache }
        let data: Data
        do { data = try handle.read(upToCount: maximumBytes + 1) ?? Data() }
        catch { throw ServerUIStoreError.cacheRead }
        guard data.count <= maximumBytes else { throw ServerUIStoreError.corruptCache }
        let record: ServerUIPublicationRecord
        do { record = try JSONDecoder().decode(ServerUIPublicationRecord.self, from: data) }
        catch { throw ServerUIStoreError.corruptCache }
        guard record.version == ServerUIPublicationRecord.currentVersion else { throw ServerUIStoreError.unsupportedCacheVersion }
        guard record.origin == partition.origin, ServerUIPublicationPartition.isUserID(record.userID) else {
            throw ServerUIStoreError.wrongPartition
        }
        guard record.bytes.count <= ServerUICompositionJSON.maximumBytes, record.revision >= 0,
              !record.epoch.isEmpty, record.epoch.utf8.count <= 128 else { throw ServerUIStoreError.corruptCache }
        return record
    }

    static func encoded(_ record: ServerUIPublicationRecord) throws -> Data {
        let encoder = JSONEncoder()
        // The bound accounts for base64 expansion, not escaped base64 slashes.
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(record)
        guard data.count <= maximumBytes else { throw ServerUIStoreError.cacheWrite }
        return data
    }

    /// Writes atomically with file protection; the directory is private to the app.
    static func write(_ data: Data, to file: URL, reserving root: URL?) throws {
        let directory = file.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try checkDirectory(directory)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if let root { try ServerUIPartitionBudget.check(root, reserving: data.count) }
            #if os(iOS) || os(watchOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
        } catch let error as ServerUIStoreError { throw error }
        catch let error as ServerUIAssetError { throw ServerUIStoreError.asset(error) }
        catch { throw ServerUIStoreError.cacheWrite }
    }

    /// Removes the record and any atomic-write leftovers it owns.
    static func remove(at file: URL) throws {
        let directory = file.deletingLastPathComponent()
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: directory.path) }
        catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile { return }
        catch { throw ServerUIStoreError.cacheClear }
        let stem = file.deletingPathExtension().lastPathComponent
        for name in names where name == file.lastPathComponent || (name.hasPrefix(stem + ".") && name.hasSuffix(".tmp")) {
            do { try FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
            catch CocoaError.fileNoSuchFile { continue }
            catch { throw ServerUIStoreError.cacheClear }
        }
    }

    private static func checkDirectory(_ directory: URL) throws {
        var metadata = stat()
        if lstat(directory.path, &metadata) != 0 {
            if errno == ENOENT { return }
            throw ServerUIStoreError.cacheRead
        }
        guard (metadata.st_mode & S_IFMT) == S_IFDIR else { throw ServerUIStoreError.cacheRead }
    }
}

// MARK: - Serialized writer

/// Every write and removal for one cache file goes through one actor, so a late write can never land after a clear.
///
/// There is no lock around any I/O: the actor serializes it, and the registry's lock guards only the dictionary of actors.
actor ServerUIPublicationDiskCache {
    private static let shared = OSAllocatedUnfairLock(initialState: [String: ServerUIPublicationDiskCache]())

    /// The one actor for `file`, shared by every store instance for that path.
    static func cache(for file: URL, root: URL, partition: ServerUIPublicationPartition) -> ServerUIPublicationDiskCache {
        let key = file.standardizedFileURL.path
        return shared.withLock { registry in
            if let existing = registry[key] { return existing }
            let created = ServerUIPublicationDiskCache(file: file, root: root, partition: partition)
            registry[key] = created
            return created
        }
    }

    private let file: URL
    private let root: URL
    private let partition: ServerUIPublicationPartition
    private var owner: UUID?

    private init(file: URL, root: URL, partition: ServerUIPublicationPartition) {
        self.file = file
        self.root = root
        self.partition = partition
    }

    /// Makes `session` the only writer; an earlier session's late writes then fail.
    func claim(_ session: UUID) { owner = session }

    /// Ends `session`'s right to write.
    func release(_ session: UUID) { if owner == session { owner = nil } }

    func load() throws -> ServerUIPublicationRecord? { try ServerUIPublicationFile.read(at: file, partition: partition) }

    /// The bytes a save of `record` would write, for the partition budget.
    func encodedSize(_ record: ServerUIPublicationRecord) throws -> Int { try ServerUIPublicationFile.encoded(record).count }

    func save(_ record: ServerUIPublicationRecord, session: UUID) throws {
        guard owner == session, !Task.isCancelled else { throw CancellationError() }
        if let existing = try? load(), existing.epoch == record.epoch, existing.revision > record.revision {
            throw ServerUIStoreError.staleGeneration
        }
        try ServerUIPublicationFile.write(ServerUIPublicationFile.encoded(record), to: file, reserving: root)
    }

    /// Puts back the record this session replaced, only while it still owns the file and wrote `candidate`.
    func restore(_ previous: ServerUIPublicationRecord?, replacing candidate: ServerUIPublicationRecord, session: UUID) throws {
        guard owner == session else { throw ServerUIStoreError.staleGeneration }
        guard try load() == candidate else { throw ServerUIStoreError.revisionConflict }
        do {
            if let previous { try ServerUIPublicationFile.write(ServerUIPublicationFile.encoded(previous), to: file, reserving: nil) }
            else { try ServerUIPublicationFile.remove(at: file) }
        } catch { throw ServerUIStoreError.cacheWrite }
    }

    /// Removes the record. Always allowed: an account teardown wins over any writer, which loses its ownership.
    func clear() throws {
        owner = nil
        try ServerUIPublicationFile.remove(at: file)
    }
}
