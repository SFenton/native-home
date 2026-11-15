import CryptoKit
import Darwin
import Foundation
import ImageIO

// MARK: - Explicit staging result

/// A verified immutable file identity. The private file must not be modified by consumers.
public struct ServerUIVerifiedAsset: Equatable, Sendable {
    /// The asset's manifest id.
    public let id: String
    /// The verified content digest.
    public let sha256: String
    /// The staged file.
    public let fileURL: URL
}

/// A candidate's verified assets, not a promoted publication or a rendered image.
public struct ServerUIStagedAssets: Equatable, Sendable {
    /// The publication revision the assets were staged for.
    public let revision: Int
    /// The digest of the document the assets belong to.
    public let documentDigest: String
    /// The verified assets of this render.
    public let assets: [ServerUIVerifiedAsset]
    fileprivate let namespace: String
    fileprivate let partitionIdentity: String
    fileprivate let newlyCreated: [URL]
}

/// Stages the publication's assets in a private partition for one server origin.
///
/// The caller owns `partitionDirectory` and must include its publication and render files there
/// so the budget counts them. All writers to that directory must coordinate with staging.
/// Verified objects are retained, never evicted here; the parent owns protected-data lifecycle.
public actor ServerUIAssetStager {
    /// The largest single asset, in bytes.
    public static let maximumAssetBytes = 8_388_608
    /// The largest total of staged assets and the cache write, in bytes.
    public static let maximumPartitionBytes = 52_428_800
    private let partition: ServerUIPublicationPartition
    private let root: URL
    private let transport: any ServerUIAssetFetching

    /// Creates a stager for one partition's private directory.
    public init(partition: ServerUIPublicationPartition, partitionDirectory: URL,
                transport: any ServerUIAssetFetching) throws {
        guard partitionDirectory.isFileURL, partitionDirectory.host.map({ $0.isEmpty }) ?? true
        else { throw ServerUIAssetError.assetOrigin }
        self.partition = partition
        self.root = partitionDirectory.standardizedFileURL
        self.transport = transport
    }

    /// `documentDigest` is the coordinator's SHA-256 identity for the compiled document.
    /// The coordinator must supply the digest corresponding to this exact publication.
    /// Reserve the store's `cacheWriteBytes` and any additional render bytes before downloading.
    /// Cancellation or failure removes candidate files without deleting existing verified files.
    public func stage(_ publication: ServerUICompositionPublication,
                      documentDigest: String, reservingBytes: Int = 0) async throws -> ServerUIStagedAssets {
        guard ServerUICompositionShape.matches(documentDigest, "^[0-9a-f]{64}$")
        else { throw ServerUIAssetError.assetOrigin }
        try Task.checkCancellation()
        try makeDirectory(root)
        let lockFD = try lockPartition()
        defer { flock(lockFD, LOCK_UN); close(lockFD) }

        let namespace = self.namespace(for: publication)
        let directory = root.appendingPathComponent("ServerUIAssets-\(namespace)", isDirectory: true)
        let objects = directory.appendingPathComponent("objects", isDirectory: true)
        try makeDirectory(directory)
        try makeDirectory(objects)
        try cleanupCandidates(in: directory)

        let assets = publication.document.assets
        var missing: [ServerUICompositionDocument.Asset] = []
        var seen = Set<String>()
        for asset in assets {
            let file = objects.appendingPathComponent(asset.sha256)
            if FileManager.default.fileExists(atPath: file.path) {
                try Self.verify(read(file, maximum: Self.maximumAssetBytes), asset: asset)
            } else if seen.insert(asset.sha256).inserted {
                missing.append(asset)
            }
        }
        let addition = missing.reduce(0) { $0 + $1.byteLength }
        guard (0...Self.maximumPartitionBytes).contains(reservingBytes),
              addition <= Self.maximumPartitionBytes - reservingBytes else {
            throw ServerUIAssetError.assetBudget
        }
        try ServerUIPartitionBudget.check(root, reserving: addition + reservingBytes)

        let candidate = directory.appendingPathComponent("candidate-\(UUID().uuidString)", isDirectory: true)
        try makeDirectory(candidate)
        var committed: [URL] = []
        do {
            // Small batches cap both in-flight network requests and buffered bodies at two.
            for start in stride(from: 0, to: missing.count, by: 2) {
                let batch = Array(missing[start..<min(start + 2, missing.count)])
                try await withThrowingTaskGroup(of: (ServerUICompositionDocument.Asset, Data).self) { group in
                    for asset in batch {
                        group.addTask { (asset, try await self.transport.download(asset)) }
                    }
                    for try await (asset, bytes) in group {
                        try Task.checkCancellation()
                        try Self.verify(bytes, asset: asset)
                        try write(bytes, to: candidate.appendingPathComponent(asset.sha256))
                    }
                }
            }
            // Every descriptor must agree even if two reference the same digest.
            for asset in assets where missing.contains(where: { $0.sha256 == asset.sha256 }) {
                try Self.verify(read(candidate.appendingPathComponent(asset.sha256), maximum: Self.maximumAssetBytes), asset: asset)
            }
            try Task.checkCancellation()
            for asset in missing {
                try Task.checkCancellation()
                let destination = objects.appendingPathComponent(asset.sha256)
                let source = candidate.appendingPathComponent(asset.sha256)
                guard link(source.path, destination.path) == 0 else {
                    throw ServerUIAssetError.storage
                }
                committed.append(destination)
            }
            try Task.checkCancellation()
            try syncDirectory(objects)
            try FileManager.default.removeItem(at: candidate)
        } catch {
            var cleanupFailed = false
            for file in committed {
                do { try FileManager.default.removeItem(at: file) } catch { cleanupFailed = true }
            }
            do { try FileManager.default.removeItem(at: candidate) } catch { cleanupFailed = true }
            if cleanupFailed { throw ServerUIAssetError.storage }
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let error = error as? ServerUIAssetError { throw error }
            throw ServerUIAssetError.storage
        }
        return ServerUIStagedAssets(revision: publication.revision, documentDigest: documentDigest,
            assets: assets.map { ServerUIVerifiedAsset(id: $0.id, sha256: $0.sha256,
                                                       fileURL: objects.appendingPathComponent($0.sha256)) },
            namespace: namespace, partitionIdentity: partitionIdentity(), newlyCreated: committed)
    }

    /// The cold-launch path: re-adopts assets this partition already holds, without a network call.
    ///
    /// Every asset must be present; its bytes are read and checked against the manifest's size and SHA-256. Full decoding was done
    /// when the file was staged, and the hash binds these bytes to that verification. Runs on the caller's thread, so the app can
    /// restore its last-good layout before the first frame.
    public nonisolated func restoreVerified(_ publication: ServerUICompositionPublication,
                                            documentDigest: String) throws -> ServerUIStagedAssets {
        guard ServerUICompositionShape.matches(documentDigest, "^[0-9a-f]{64}$") else { throw ServerUIAssetError.assetOrigin }
        let namespace = self.namespace(for: publication)
        let objects = root.appendingPathComponent("ServerUIAssets-\(namespace)", isDirectory: true)
            .appendingPathComponent("objects", isDirectory: true)
        let lockFD = try lockPartition()
        defer { flock(lockFD, LOCK_UN); close(lockFD) }
        for asset in publication.document.assets {
            let bytes = try read(objects.appendingPathComponent(asset.sha256), maximum: Self.maximumAssetBytes)
            guard bytes.count == asset.byteLength, Self.hex(SHA256.hash(data: bytes)) == asset.sha256 else {
                throw ServerUIAssetError.assetIntegrity
            }
        }
        return ServerUIStagedAssets(revision: publication.revision, documentDigest: documentDigest,
            assets: publication.document.assets.map { ServerUIVerifiedAsset(id: $0.id, sha256: $0.sha256,
                fileURL: objects.appendingPathComponent($0.sha256)) },
            namespace: namespace, partitionIdentity: partitionIdentity(), newlyCreated: [])
    }

    private nonisolated func namespace(for publication: ServerUICompositionPublication) -> String {
        let identity = [partition.origin, publication.publisherId, publication.document.id]
            .map { "\($0.utf8.count):\($0)" }.joined()
        return Self.hex(SHA256.hash(data: Data(identity.utf8)))
    }

    /// Discards files first created by a stale candidate. Supply every current, previous, or
    /// other outstanding handle in this partition; shared files in those handles are retained.
    /// This does not evict pre-existing cache entries or promote any publication.
    public func discard(_ candidate: ServerUIStagedAssets, retaining protected: [ServerUIStagedAssets]) throws {
        try makeDirectory(root)
        let lockFD = try lockPartition()
        defer { flock(lockFD, LOCK_UN); close(lockFD) }
        let objects = root.appendingPathComponent("ServerUIAssets-\(candidate.namespace)", isDirectory: true)
            .appendingPathComponent("objects", isDirectory: true)
        guard candidate.partitionIdentity == partitionIdentity(),
              candidate.newlyCreated.allSatisfy({ $0.deletingLastPathComponent() == objects }),
              protected.allSatisfy({ $0.namespace == candidate.namespace && $0.partitionIdentity == candidate.partitionIdentity })
        else { throw ServerUIAssetError.assetOrigin }
        let retained = Set(protected.flatMap { $0.assets.map(\.fileURL) })
        for file in candidate.newlyCreated where !retained.contains(file) {
            do {
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }

            } catch { throw ServerUIAssetError.storage }
        }
    }

    /// Account teardown only: the owning publication store must have drained preparation and
    /// retained exclusive partition ownership. Removes cached prior-run assets as well as renders.
    public func purgePartition() throws {
        try makeDirectory(root)
        let lockFD = try lockPartition()
        defer { flock(lockFD, LOCK_UN); close(lockFD) }
        do { try FileManager.default.removeItem(at: root) }
        catch { throw ServerUIAssetError.storage }
    }

    // MARK: - Verification

    static func verify(_ bytes: Data, asset: ServerUICompositionDocument.Asset) throws {
        guard (1...maximumAssetBytes).contains(bytes.count), bytes.count == asset.byteLength,
              (1...8192).contains(asset.pixelWidth), (1...8192).contains(asset.pixelHeight),
              asset.pixelWidth * asset.pixelHeight <= 16_000_000,
              hex(SHA256.hash(data: bytes)) == asset.sha256
        else { throw ServerUIAssetError.assetIntegrity }
        let signature: [UInt8] = asset.mimeType == .png
            ? [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] : [0xff, 0xd8, 0xff]
        guard bytes.starts(with: signature),
              (asset.mimeType != .png || staticPNG(bytes)),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let type = CGImageSourceGetType(source) as String?,
              type == (asset.mimeType == .png ? "public.png" : "public.jpeg"),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == asset.pixelWidth, height == asset.pixelHeight,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { throw ServerUIAssetError.assetIntegrity }
    }

    private static func staticPNG(_ data: Data) -> Bool {
        var offset = 8
        while offset <= data.count - 12 {
            let length = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= data.count - offset - 12 else { return false }
            let type = data[offset + 4..<offset + 8]
            if type.elementsEqual([0x61, 0x63, 0x54, 0x4c]) { return false }
            offset += length + 12
            if type.elementsEqual([0x49, 0x45, 0x4e, 0x44]) {
                return length == 0 && offset == data.count
            }
        }
        return false
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private storage

    private nonisolated func lockPartition() throws -> Int32 {
        let file = root.appendingPathComponent(".asset-staging.lock")
        let fd = open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ServerUIAssetError.storage }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw ServerUIAssetError.busy
        }
        return fd
    }

    private nonisolated func partitionIdentity() -> String {
        Self.hex(SHA256.hash(data: Data("\(partition.origin.utf8.count):\(partition.origin)".utf8)))
    }

    private func syncDirectory(_ directory: URL) throws {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ServerUIAssetError.storage }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw ServerUIAssetError.storage }
    }

    private nonisolated func makeDirectory(_ directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
                  info.st_mode & 0o077 == 0 else {
                throw ServerUIAssetError.storage
            }
        } catch { throw ServerUIAssetError.storage }
    }

    private func cleanupCandidates(in directory: URL) throws {
        do {
            let objects = directory.appendingPathComponent("objects", isDirectory: true)
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let name = url.lastPathComponent
                guard name.hasPrefix("candidate-"),
                      UUID(uuidString: String(name.dropFirst("candidate-".count))) != nil else { continue }
                var candidateInfo = stat()
                guard lstat(url.path, &candidateInfo) == 0, (candidateInfo.st_mode & S_IFMT) == S_IFDIR else {
                    throw ServerUIAssetError.storage
                }
                for source in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    guard ServerUICompositionShape.matches(source.lastPathComponent, "^[0-9a-f]{64}$")
                    else { throw ServerUIAssetError.storage }
                    var sourceInfo = stat()
                    guard lstat(source.path, &sourceInfo) == 0, (sourceInfo.st_mode & S_IFMT) == S_IFREG else {
                        throw ServerUIAssetError.storage
                    }
                    let destination = objects.appendingPathComponent(source.lastPathComponent)
                    var destinationInfo = stat()
                    if lstat(destination.path, &destinationInfo) == 0 {
                        guard (destinationInfo.st_mode & S_IFMT) == S_IFREG else { throw ServerUIAssetError.storage }
                        if sourceInfo.st_dev == destinationInfo.st_dev && sourceInfo.st_ino == destinationInfo.st_ino {
                            try FileManager.default.removeItem(at: destination)
                        }
                    } else if errno != ENOENT { throw ServerUIAssetError.storage }
                }
                try FileManager.default.removeItem(at: url)
            }
        } catch { throw ServerUIAssetError.storage }
    }

    private nonisolated func read(_ file: URL, maximum: Int) throws -> Data {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ServerUIAssetError.storage }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= maximum else { throw ServerUIAssetError.assetIntegrity }
        do {
            let data = try handle.read(upToCount: maximum + 1) ?? Data()
            guard data.count <= maximum else { throw ServerUIAssetError.assetIntegrity }
            return data
        } catch let error as ServerUIAssetError { throw error }
        catch { throw ServerUIAssetError.storage }
    }

    private func write(_ data: Data, to file: URL) throws {
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ServerUIAssetError.storage }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            #if os(iOS) || os(watchOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                  ofItemAtPath: file.path)
            #endif
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch { throw ServerUIAssetError.storage }
    }
}
