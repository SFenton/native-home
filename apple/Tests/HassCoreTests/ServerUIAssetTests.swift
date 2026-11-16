import CryptoKit
import Foundation
import os
import Testing
@testable import HassCore

// MARK: - Synthetic transport

private final class ServerUIAssetURLProtocol: URLProtocol {
    struct Reply: Sendable {
        var status = 200
        var headers = ["Content-Type": "image/png"]
        var chunks: [Data] = []
        var redirect: URL?
        var hold = false
        var onStart: @Sendable () -> Void = {}
        var onStop: @Sendable () -> Void = {}
    }
    private struct State {
        var reply = Reply()
        var requests: [URLRequest] = []
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())
    private let stopHandler = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)

    static func configure(_ reply: Reply) { state.withLock { $0 = State(reply: reply) } }
    static var requests: [URLRequest] { state.withLock { $0.requests } }
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let request = self.request
        let reply = Self.state.withLock {
            $0.requests.append(request)
            return $0.reply
        }
        stopHandler.withLock { $0 = reply.onStop }
        reply.onStart()
        guard let url = request.url else { return }
        if let redirect = reply.redirect {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                           headerFields: ["Location": redirect.absoluteString])!
            var next = request
            next.url = redirect
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
        if !reply.hold { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { stopHandler.withLock { $0 }?() }
}

// MARK: - Asset staging

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ServerUIAssetTests {
    private typealias Asset = ServerUICompositionDocument.Asset
    private let digest = String(repeating: "a", count: 64)
    private static let server = HassServer(baseURL: URL(string: "https://home.example")!)

    private func png() throws -> Data {
        // The shared synthetic corpus's 2x2 PNG, copied so tests do not depend on ignored build output.
        try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGOQsIhIWLCBYUOBxYMDDQAiXgXRUMwx1wAAAABJRU5ErkJggg=="))
    }
    private func publication() throws -> ServerUICompositionPublication {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("ServerUICompositionFixture.json")
        return try .decode(Data(contentsOf: url))
    }
    private func asset(_ original: Asset, bytes: Data? = nil, mime: ServerUICompositionDocument.MIMEType? = nil,
                       length: Int? = nil, width: Int? = nil, height: Int? = nil) -> Asset {
        let hash = bytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? original.sha256
        let mime = mime ?? original.mimeType
        return Asset(id: original.id, role: original.role,
                     source: .init(path: "/api/assets/\(hash).\(mime == .png ? "png" : "jpg")"),
                     sha256: hash, mimeType: mime, byteLength: length ?? bytes?.count ?? original.byteLength,
                     pixelWidth: width ?? original.pixelWidth, pixelHeight: height ?? original.pixelHeight)
    }
    private func publication(_ original: ServerUICompositionPublication, assets: [Asset]) -> ServerUICompositionPublication {
        let doc = original.document
        let document = ServerUICompositionDocument(schemaVersion: doc.schemaVersion, id: doc.id, name: doc.name,
            theme: doc.theme, navigation: doc.navigation, pages: doc.pages, modals: doc.modals,
            dataSources: doc.dataSources, variables: doc.variables, assets: assets, liveActivities: [],
            bootstrap: doc.bootstrap)
        return ServerUICompositionPublication(envelopeVersion: original.envelopeVersion, publisherId: original.publisherId,
            revision: original.revision + 1, updatedAt: original.updatedAt, publishedAt: original.publishedAt,
            capabilities: original.capabilities, assetManifestSha256: original.assetManifestSha256, document: document,
            documentSha256: original.documentSha256)
    }
    private func insertingChunk(_ type: [UInt8], payload: [UInt8], in png: Data) -> Data {
        let size = UInt32(payload.count)
        var chunk = Data([UInt8(size >> 24), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)])
        chunk.append(contentsOf: type + payload)
        var crc: UInt32 = 0xffffffff
        for byte in type + payload {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        }
        crc ^= 0xffffffff
        chunk.append(contentsOf: [UInt8(crc >> 24), UInt8((crc >> 16) & 255), UInt8((crc >> 8) & 255), UInt8(crc & 255)])
        var result = png
        result.insert(contentsOf: chunk, at: 33)
        return result
    }
    private func setup() throws -> (URL, ServerUIAssetStager, ServerUIAssetTransport) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("asset-tests-\(UUID().uuidString)")
        let partition = try ServerUIPublicationPartition(server: Self.server)
        let transport = ServerUIAssetTransport(server: Self.server, tokenProvider: { "fixture-token" },
                                               session: ServerUIAssetURLProtocol.session())
        return (root, try ServerUIAssetStager(partition: partition, partitionDirectory: root, transport: transport), transport)
    }

    @Test func fixtureStagesAndReusesVerifiedBytesWithPrefix() async throws {
        let bytes = try png()
        let publication = try publication()
        let (root, stager, _) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        ServerUIAssetURLProtocol.configure(.init(chunks: [bytes]))
        let result = try await stager.stage(publication, documentDigest: digest)
        let request = try #require(ServerUIAssetURLProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://home.example/api/fenton_home/ui_assets/" + publication.document.assets[0].sha256)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        #expect(!request.httpShouldHandleCookies)
        #expect(request.timeoutInterval == 15)
        #expect(try Data(contentsOf: result.assets[0].fileURL) == bytes)
        #expect(result.documentDigest == digest)
        let reused = try await stager.stage(publication, documentDigest: digest)
        #expect(reused.assets == result.assets)
        #expect(ServerUIAssetURLProtocol.requests.count == 1)
        try await stager.discard(result, retaining: [reused])
        #expect(FileManager.default.fileExists(atPath: result.assets[0].fileURL.path))
    }

    @Test func restoreVerifiedReadsStagedAssetsWithoutTheNetworkAndRechecksTheirHash() async throws {
        let bytes = try png()
        let publication = try publication()
        let (root, stager, _) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        ServerUIAssetURLProtocol.configure(.init(chunks: [bytes]))
        let staged = try await stager.stage(publication, documentDigest: digest)
        let restored = try stager.restoreVerified(publication, documentDigest: digest)
        #expect(restored.assets == staged.assets)
        #expect(ServerUIAssetURLProtocol.requests.count == 1)
        #expect(throws: ServerUIAssetError.assetOrigin) { try stager.restoreVerified(publication, documentDigest: "nope") }
        try Data([0]).write(to: staged.assets[0].fileURL)
        #expect(throws: ServerUIAssetError.assetIntegrity) { try stager.restoreVerified(publication, documentDigest: digest) }
        try FileManager.default.removeItem(at: staged.assets[0].fileURL)
        #expect(throws: ServerUIAssetError.storage) { try stager.restoreVerified(publication, documentDigest: digest) }
    }

    @Test func aWrongBodyFailsTheHashAndAMissingOrRevalidatedAssetIsRefused() async throws {
        let bytes = try png()
        let original = try #require(publication().document.assets.first)
        let (root, stager, transport) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        var wrong = bytes
        wrong[wrong.count - 1] ^= 1
        ServerUIAssetURLProtocol.configure(.init(chunks: [wrong]))
        await #expect(throws: ServerUIAssetError.assetIntegrity) {
            _ = try await stager.stage(publication(), documentDigest: digest)
        }
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        #expect(!files.contains { $0.hasSuffix(original.sha256) })
        ServerUIAssetURLProtocol.configure(.init(status: 404, chunks: []))
        await #expect(throws: ServerUIAssetError.missing) { _ = try await transport.download(original) }
        ServerUIAssetURLProtocol.configure(.init(status: 304, chunks: []))
        await #expect(throws: ServerUIAssetError.unexpectedResponse) { _ = try await transport.download(original) }
        ServerUIAssetURLProtocol.configure(.init(status: 401, chunks: []))
        await #expect(throws: ServerUIAssetError.unexpectedResponse) { _ = try await transport.download(original) }
        ServerUIAssetURLProtocol.configure(.init(headers: ["Content-Type": "text/html"], chunks: [bytes]))
        await #expect(throws: ServerUIAssetError.unexpectedResponse) { _ = try await transport.download(original) }
    }

    @Test func tokenFailuresAreSanitizedAndNothingIsSent() async throws {
        let original = try #require(publication().document.assets.first)
        ServerUIAssetURLProtocol.configure(.init())
        struct Boom: Error {}
        let failing = ServerUIAssetTransport(server: Self.server, tokenProvider: { throw Boom() },
                                             session: ServerUIAssetURLProtocol.session())
        await #expect(throws: ServerUIAssetError.credentialUnavailable) { _ = try await failing.download(original) }
        #expect(ServerUIAssetURLProtocol.requests.isEmpty)
    }

    @Test func mismatchedDigestSignatureDimensionsAndLengthReject() throws {
        let bytes = try png()
        let original = try #require(publication().document.assets.first)
        var changed = bytes
        changed[changed.count - 1] ^= 1
        #expect(throws: ServerUIAssetError.assetIntegrity) { try ServerUIAssetStager.verify(changed, asset: original) }
        let notPNG = Data(repeating: 0, count: bytes.count)
        #expect(throws: ServerUIAssetError.assetIntegrity) { try ServerUIAssetStager.verify(notPNG, asset: asset(original, bytes: notPNG)) }
        #expect(throws: ServerUIAssetError.assetIntegrity) { try ServerUIAssetStager.verify(bytes, asset: asset(original, width: 3)) }
        #expect(throws: ServerUIAssetError.assetIntegrity) { try ServerUIAssetStager.verify(bytes, asset: asset(original, length: bytes.count + 1)) }
        #expect(throws: ServerUIAssetError.assetIntegrity) { try ServerUIAssetStager.verify(bytes, asset: asset(original, mime: .jpeg)) }
        #expect(throws: ServerUIAssetError.assetIntegrity) { try ServerUIAssetStager.verify(bytes, asset: asset(original, width: 8192, height: 1954)) }
        let animated = insertingChunk([0x61, 0x63, 0x54, 0x4c], payload: [0, 0, 0, 2, 0, 0, 0, 0], in: bytes)
        #expect(throws: ServerUIAssetError.assetIntegrity) { try ServerUIAssetStager.verify(animated, asset: asset(original, bytes: animated)) }
    }

    @Test func streamingRejectsOneByteBeyondDeclaredAndMaximum() async throws {
        let original = try #require(publication().document.assets.first)
        let (root, _, transport) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let maximum = asset(original, length: ServerUIAssetStager.maximumAssetBytes)
        let limit = Data(repeating: 0, count: ServerUIAssetStager.maximumAssetBytes)
        ServerUIAssetURLProtocol.configure(.init(chunks: [limit]))
        #expect(try await transport.download(maximum).count == ServerUIAssetStager.maximumAssetBytes)
        ServerUIAssetURLProtocol.configure(.init(chunks: [
            limit, Data([0])
        ]))
        await #expect(throws: ServerUIAssetError.assetIntegrity) { _ = try await transport.download(maximum) }
        ServerUIAssetURLProtocol.configure(.init(headers: ["Content-Type": "image/png", "Content-Length": "8388609"],
                                                 chunks: [Data([0])]))
        await #expect(throws: ServerUIAssetError.assetIntegrity) { _ = try await transport.download(maximum) }
    }

    @Test func redirectsDoNotForwardCredentials() async throws {
        let (root, stager, _) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        ServerUIAssetURLProtocol.configure(.init(redirect: URL(string: "https://other.example/collect")!))
        await #expect(throws: ServerUIAssetError.redirectRejected) {
            _ = try await stager.stage(publication(), documentDigest: digest)
        }
        #expect(ServerUIAssetURLProtocol.requests.count == 1)
        #expect(ServerUIAssetURLProtocol.requests[0].url?.host == "home.example")
    }

    @Test func untrustedPathAndInvalidCredentialsNeverStartARequest() async throws {
        let original = try #require(publication().document.assets.first)
        let (root, _, transport) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = Asset(id: original.id, role: original.role,
                        source: original.source,
                        sha256: "../../etc/passwd", mimeType: original.mimeType, byteLength: original.byteLength,
                        pixelWidth: original.pixelWidth, pixelHeight: original.pixelHeight)
        ServerUIAssetURLProtocol.configure(.init())
        await #expect(throws: ServerUIAssetError.assetOrigin) { _ = try await transport.download(bad) }
        let invalid = ServerUIAssetTransport(server: Self.server, tokenProvider: { "bad\r\nvalue" },
                                             session: ServerUIAssetURLProtocol.session())
        await #expect(throws: ServerUIAssetError.invalidCredential) { _ = try await invalid.download(original) }
        #expect(ServerUIAssetURLProtocol.requests.isEmpty)
    }

    @Test func cancellationRemovesCandidate() async throws {
        let started = AsyncStream<Void>.makeStream()
        let stopped = AsyncStream<Void>.makeStream()
        let (root, stager, _) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        ServerUIAssetURLProtocol.configure(.init(hold: true,
            onStart: { started.continuation.yield(()) }, onStop: { stopped.continuation.yield(()) }))
        let publication = try publication()
        let task = Task { try await stager.stage(publication, documentDigest: digest) }
        var starts = started.stream.makeAsyncIterator()
        _ = await starts.next()
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        var stops = stopped.stream.makeAsyncIterator()
        _ = await stops.next()
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        #expect(!files.contains { $0.contains("candidate-") })
    }

    @Test func budgetFailureKeepsProtectedAndExistingAssets() async throws {
        let bytes = try png()
        let publication = try publication()
        let (root, stager, _) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        ServerUIAssetURLProtocol.configure(.init(chunks: [bytes]))
        let result = try await stager.stage(publication, documentDigest: digest)
        let protected = root.appendingPathComponent("protected-render")
        #expect(FileManager.default.createFile(atPath: protected.path, contents: nil))
        let handle = try FileHandle(forWritingTo: protected)
        try handle.truncate(atOffset: UInt64(ServerUIAssetStager.maximumPartitionBytes))
        try handle.close()
        await #expect(throws: ServerUIAssetError.assetBudget) {
            _ = try await stager.stage(publication, documentDigest: digest)
        }
        #expect(try Data(contentsOf: result.assets[0].fileURL) == bytes)
        #expect(FileManager.default.fileExists(atPath: protected.path))
    }

    @Test func candidateBudgetCountsExistingAndCanFitExactly() async throws {
        let bytes = try png()
        let original = try publication()
        let changed = insertingChunk([0x74, 0x45, 0x58, 0x74], payload: [0x6b, 0, 0x76], in: bytes)
        let nextAsset = asset(original.document.assets[0], bytes: changed)
        try ServerUIAssetStager.verify(changed, asset: nextAsset)
        let next = publication(original, assets: [nextAsset])
        let (root, stager, _) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        ServerUIAssetURLProtocol.configure(.init(chunks: [bytes]))
        let current = try await stager.stage(original, documentDigest: digest)
        let protected = root.appendingPathComponent("protected-render")
        #expect(FileManager.default.createFile(atPath: protected.path, contents: nil))
        let handle = try FileHandle(forWritingTo: protected)
        let reservation = 2_048
        let available = ServerUIAssetStager.maximumPartitionBytes - bytes.count - changed.count - reservation
        try handle.truncate(atOffset: UInt64(available + 1))
        ServerUIAssetURLProtocol.configure(.init(chunks: [changed]))
        await #expect(throws: ServerUIAssetError.assetBudget) {
            _ = try await stager.stage(next, documentDigest: digest, reservingBytes: reservation)
        }
        #expect(ServerUIAssetURLProtocol.requests.isEmpty)
        #expect(try Data(contentsOf: current.assets[0].fileURL) == bytes)
        try handle.truncate(atOffset: UInt64(available))
        try handle.close()
        let staged = try await stager.stage(next, documentDigest: digest, reservingBytes: reservation)
        #expect(try Data(contentsOf: staged.assets[0].fileURL) == changed)
        try await stager.discard(staged, retaining: [current])
        #expect(!FileManager.default.fileExists(atPath: staged.assets[0].fileURL.path))
        #expect(FileManager.default.fileExists(atPath: current.assets[0].fileURL.path))
    }

    @Test func failedCandidateKeepsPreviouslyVerifiedBytes() async throws {
        let bytes = try png()
        let original = try publication()
        let changed = insertingChunk([0x74, 0x45, 0x58, 0x74], payload: [0x6b, 0, 0x76], in: bytes)
        let next = publication(original, assets: [asset(original.document.assets[0], bytes: changed)])
        let (root, stager, _) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        ServerUIAssetURLProtocol.configure(.init(chunks: [bytes]))
        let current = try await stager.stage(original, documentDigest: digest)
        ServerUIAssetURLProtocol.configure(.init(chunks: [Data(repeating: 0, count: changed.count)]))
        await #expect(throws: ServerUIAssetError.assetIntegrity) {
            _ = try await stager.stage(next, documentDigest: digest)
        }
        #expect(try Data(contentsOf: current.assets[0].fileURL) == bytes)
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        #expect(!files.contains { $0.contains("candidate-") })
    }

    @Test func serverPartitionsCannotShareOrDiscardEachOthersFiles() async throws {
        let bytes = try png()
        let publication = try publication()
        let (root, first, transport) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let otherPartition = try ServerUIPublicationPartition(server: HassServer(baseURL: URL(string: "https://other.example")!))
        let second = try ServerUIAssetStager(partition: otherPartition, partitionDirectory: root, transport: transport)
        ServerUIAssetURLProtocol.configure(.init(chunks: [bytes]))
        let a = try await first.stage(publication, documentDigest: digest)
        let b = try await second.stage(publication, documentDigest: digest)
        #expect(a.assets[0].fileURL != b.assets[0].fileURL)
        #expect(ServerUIAssetURLProtocol.requests.count == 2)
        await #expect(throws: ServerUIAssetError.assetOrigin) { try await second.discard(a, retaining: []) }
        #expect(try Data(contentsOf: a.assets[0].fileURL) == bytes)
        #expect(try Data(contentsOf: b.assets[0].fileURL) == bytes)
    }

    @Test func interruptedCandidateLinksAreRecoveredWithoutRemovingCurrent() async throws {
        let bytes = try png()
        let publication = try publication()
        let (root, stager, _) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        ServerUIAssetURLProtocol.configure(.init(chunks: [bytes]))
        let current = try await stager.stage(publication, documentDigest: digest)
        let objects = current.assets[0].fileURL.deletingLastPathComponent()
        let candidate = objects.deletingLastPathComponent().appendingPathComponent("candidate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
        let name = String(repeating: "b", count: 64)
        let staged = candidate.appendingPathComponent(name)
        let orphan = objects.appendingPathComponent(name)
        try bytes.write(to: staged)
        try FileManager.default.linkItem(at: staged, to: orphan)
        _ = try await stager.stage(publication, documentDigest: digest)
        #expect(!FileManager.default.fileExists(atPath: candidate.path))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(try Data(contentsOf: current.assets[0].fileURL) == bytes)
    }

    @Test func atMostTwoDownloadsRunAndCancellationCleansTheCandidate() async throws {
        let bytes = try png()
        let original = try publication()
        let items = (0..<3).map { index in
            asset(original.document.assets[0], bytes: insertingChunk([0x74, 0x45, 0x58, 0x74],
                payload: [0x6b, 0, UInt8(index)], in: bytes))
        }
        let candidate = publication(original, assets: items)
        let (root, stager, _) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let started = AsyncStream<Void>.makeStream()
        ServerUIAssetURLProtocol.configure(.init(hold: true, onStart: { started.continuation.yield(()) }))
        let task = Task { try await stager.stage(candidate, documentDigest: digest) }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        _ = await iterator.next()
        #expect(ServerUIAssetURLProtocol.requests.count == 2)
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        #expect(!files.contains { $0.contains("candidate-") })
    }
}
