import CoreGraphics
import Foundation
@testable import HassCore
import ImageIO
import os
import HassTestSupport
import Testing
import UniformTypeIdentifiers

// MARK: - Fixtures

/// Serves canned responses and records requests for the avatar tests.
final class StubAvatarProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
        var delay: TimeInterval = 0
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        let reply = handler?(request) ?? Reply(status: 404)
        if reply.delay > 0 { Thread.sleep(forTimeInterval: reply.delay) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset(_ handler: (@Sendable (URLRequest) -> Reply)?) {
        lock.lock()
        requests = []
        self.handler = handler
        lock.unlock()
    }

    static var recorded: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

/// A solid PNG `side` pixels square.
func avatarPNG(side: Int = 512, gray: CGFloat = 0.5) -> Data {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("avatars-\(UUID())")
}

private func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubAvatarProtocol.self]
    return URLSession(configuration: configuration)
}

private let base = URL(string: "https://ha.example.com")!

private func metadata(_ path: String, etag: String? = nil, modified: String? = nil) -> PersonAvatarStore.Metadata {
    .init(pictureKey: AvatarSyncPlan.pictureKey(path), etag: etag, lastModified: modified, validatedAt: Date(timeIntervalSince1970: 1))
}

// MARK: - Plan

/// The proposal's decision matrix (`.agents/design/mockups/proposals/profile-photos`), one test per row.
@Suite(.demoHouse)
struct AvatarSyncPlanTests {
    private let path = "/api/image/serve/abc/512x512"

    @Test func noPhotoAndNoPictureKeepsInitials() {
        #expect(AvatarSyncPlan.plan(cached: nil, serverPicture: nil, entityLoaded: true) == .keep)
        #expect(AvatarSyncPlan.plan(cached: nil, serverPicture: "", entityLoaded: true) == .keep)
    }

    @Test func noPhotoAndAPictureDownloads() {
        #expect(AvatarSyncPlan.plan(cached: nil, serverPicture: path, entityLoaded: true) == .download)
    }

    @Test func aPhotoAndNoPictureDeletesOnlyOnceTheEntityHasLoaded() {
        #expect(AvatarSyncPlan.plan(cached: metadata(path), serverPicture: nil, entityLoaded: true) == .delete)
        #expect(AvatarSyncPlan.plan(cached: metadata(path), serverPicture: "", entityLoaded: true) == .delete)
        // Never delete on doubt: the entity has not arrived.
        #expect(AvatarSyncPlan.plan(cached: metadata(path), serverPicture: nil, entityLoaded: false) == .keep)
    }

    @Test func aNewPicturePathReplaces() {
        #expect(AvatarSyncPlan.plan(cached: metadata(path), serverPicture: "/api/image/serve/xyz/512x512", entityLoaded: true) == .replace)
    }

    @Test func theSamePathRevalidatesOncePerLaunch() {
        #expect(AvatarSyncPlan.plan(cached: metadata(path), serverPicture: path, entityLoaded: true) == .revalidate)
        #expect(AvatarSyncPlan.plan(cached: metadata(path), serverPicture: path, entityLoaded: true, validatedThisLaunch: true) == .keep)
    }

    @Test func nothingHappensBeforeTheEntityLoads() {
        #expect(AvatarSyncPlan.plan(cached: nil, serverPicture: path, entityLoaded: false) == .keep)
        #expect(AvatarSyncPlan.plan(cached: metadata(path), serverPicture: path, entityLoaded: false) == .keep)
    }

    @Test func aRotatedTokenIsNotANewPhoto() {
        let before = "/api/image/serve/abc/512x512?token=one"
        let after = "/api/image/serve/abc/512x512?token=two&authSig=zzz&access_token=q"
        #expect(AvatarSyncPlan.pictureKey(before) == AvatarSyncPlan.pictureKey(after))
        #expect(AvatarSyncPlan.pictureKey(before) == "/api/image/serve/abc/512x512")
        #expect(AvatarSyncPlan.plan(cached: metadata(before), serverPicture: after, entityLoaded: true) == .revalidate)
        // Other query items are identity, like a media player's cache= hash.
        #expect(AvatarSyncPlan.pictureKey("/a?token=x&v=2") == "/a?v=2")
    }

    @Test func theVolatileListMatchesTheImagePipelines() {
        #expect(AvatarSyncPlan.volatileQueryItems == ["token", "authSig", "access_token"])
    }

    @Test func theViewersPersonIsTheOneWithTheirUserID() {
        let states = [
            EntityState(entityId: "person.demo_alex", state: "home", attributes: ["user_id": .string("u1")]),
            EntityState(entityId: "person.demo_sam", state: "home", attributes: ["user_id": .string("u2")]),
            EntityState(entityId: "sensor.demo_x", state: "1", attributes: ["user_id": .string("u3")]),
        ]
        #expect(AvatarSyncPlan.personID(forUser: "u2", in: states) == "person.demo_sam")
        #expect(AvatarSyncPlan.personID(forUser: "u3", in: states) == nil)
        #expect(AvatarSyncPlan.personID(forUser: "nobody", in: states) == nil)
    }
}

// MARK: - Store

@Suite(.demoHouse)
struct PersonAvatarStoreTests {
    @Test func roundTripsBytesAndSidecar() throws {
        let store = PersonAvatarStore(directory: tempDirectory())
        let meta = metadata("/p", etag: "\"e1\"", modified: "Mon")
        #expect(store.data(for: "person.demo_a") == nil && store.metadata(for: "person.demo_a") == nil)
        try store.save(Data([1, 2, 3]), metadata: meta, for: "person.demo_a")
        #expect(store.data(for: "person.demo_a") == Data([1, 2, 3]))
        #expect(store.metadata(for: "person.demo_a") == meta)
        #expect(store.personIDs() == ["person.demo_a"])
    }

    @Test func eachPersonHasTheirOwnFiles() throws {
        let store = PersonAvatarStore(directory: tempDirectory())
        try store.save(Data([1]), metadata: metadata("/a"), for: "person.demo_a")
        try store.save(Data([2]), metadata: metadata("/b"), for: "person.demo_b")
        store.delete(personID: "person.demo_a")
        #expect(store.data(for: "person.demo_a") == nil && store.metadata(for: "person.demo_a") == nil)
        #expect(store.data(for: "person.demo_b") == Data([2]))
        #expect(store.personIDs() == ["person.demo_b"])
    }

    @Test func removeAllWipesFilesAndTheViewerRecord() throws {
        let directory = tempDirectory()
        let store = PersonAvatarStore(directory: directory)
        try store.save(Data([1]), metadata: metadata("/a"), for: "person.demo_a")
        try store.save(Data([2]), metadata: metadata("/b"), for: "person.demo_b")
        store.viewerPersonID = "person.demo_a"
        #expect(store.viewerPersonID == "person.demo_a")
        store.removeAll()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(store.personIDs().isEmpty && store.viewerPersonID == nil)
        // Writable again afterwards (the next sign-in).
        try store.save(Data([3]), metadata: metadata("/c"), for: "person.demo_a")
        #expect(store.data(for: "person.demo_a") == Data([3]))
    }

    @Test func aSidecarWithoutItsPhotoIsNotACachedPhoto() throws {
        let store = PersonAvatarStore(directory: tempDirectory())
        try store.save(Data([1]), metadata: metadata("/a"), for: "person.demo_a")
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent("person%2Edemo_a.photo"))
        #expect(store.metadata(for: "person.demo_a") == nil)
    }

    @Test func theDirectoryIsExcludedFromBackup() throws {
        let store = PersonAvatarStore(directory: tempDirectory())
        try store.save(Data([1]), metadata: metadata("/a"), for: "person.demo_a")
        let values = try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func hostileIDsStayInsideTheDirectory() throws {
        let store = PersonAvatarStore(directory: tempDirectory())
        try store.save(Data([1]), metadata: metadata("/a"), for: "../../escape")
        #expect(store.personIDs() == ["../../escape"])
        #expect(store.data(for: "../../escape") == Data([1]))
    }

    @Test func aWriterThatBeganBeforeRemoveAllCannotRecreateTheDirectory() throws {
        let directory = tempDirectory()
        let store = PersonAvatarStore(directory: directory)
        let began = store.generation
        store.removeAll()
        #expect(store.generation == began + 1)
        #expect(throws: PersonAvatarStore.StaleGeneration.self) {
            try store.save(Data([1]), metadata: metadata("/a"), for: "person.demo_a", ifGeneration: began)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path), "the sign-out left nothing behind")
    }

    @Test func aStaleDeleteCannotRemoveTheNextSessionsFile() throws {
        let store = PersonAvatarStore(directory: tempDirectory())
        let old = store.generation
        store.removeAll()
        try store.save(Data([2]), metadata: metadata("/b"), for: "person.demo_a", ifGeneration: store.generation)
        store.delete(personID: "person.demo_a", ifGeneration: old)
        store.updateMetadata(metadata("/stale"), for: "person.demo_a", ifGeneration: old)
        #expect(store.data(for: "person.demo_a") == Data([2]) && store.metadata(for: "person.demo_a")?.pictureKey == "/b")
        store.delete(personID: "person.demo_a", ifGeneration: store.generation)
        #expect(store.data(for: "person.demo_a") == nil)
    }

    @Test func theDefaultLocationIsApplicationSupport() {
        #expect(PersonAvatarStore.defaultDirectory.lastPathComponent == "PersonAvatars")
    }
}

// MARK: - Syncer

/// The suites that share ``StubAvatarProtocol`` run one after another.
@Suite(.serialized)
enum AvatarNetworkTests {}

extension AvatarNetworkTests {
@Suite(.serialized, .demoHouse)
struct PersonAvatarSyncerTests {
    private let path = "/api/image/serve/abc/512x512"

    private func syncer() -> (PersonAvatarSyncer, PersonAvatarStore) {
        let store = PersonAvatarStore(directory: tempDirectory())
        return (PersonAvatarSyncer(store: store, session: stubSession(), now: { Date(timeIntervalSince1970: 99) }), store)
    }

    private func server(token: String? = "T0KEN") -> PersonAvatarSyncer.Server {
        .init(baseURL: base, accessToken: { token })
    }

    @Test func downloadStoresBytesAndValidators() async {
        let (syncer, store) = syncer()
        StubAvatarProtocol.reset { _ in .init(status: 200, headers: ["ETag": "\"v1\"", "Last-Modified": "Mon"], body: avatarPNG()) }
        let outcome = await syncer.sync(personID: "person.demo_a", picture: path, entityLoaded: true, validatedThisLaunch: false, server: server())
        #expect(outcome == .updated(replaced: false))
        let meta = store.metadata(for: "person.demo_a")
        #expect(meta?.etag == "\"v1\"" && meta?.lastModified == "Mon")
        #expect(meta?.pictureKey == path && meta?.validatedAt == Date(timeIntervalSince1970: 99))
        #expect(StubAvatarProtocol.recorded.first?.url?.absoluteString == "https://ha.example.com\(path)")
        #expect(PersonAvatarSyncer.decode(store.data(for: "person.demo_a")!) != nil)
    }

    @Test func aNotModifiedAnswerKeepsTheBytesAndSendsValidators() async throws {
        let (syncer, store) = syncer()
        let bytes = avatarPNG()
        try store.save(bytes, metadata: metadata(path, etag: "\"v1\"", modified: "Mon"), for: "person.demo_a")
        StubAvatarProtocol.reset { _ in .init(status: 304) }
        let outcome = await syncer.sync(personID: "person.demo_a", picture: path, entityLoaded: true, validatedThisLaunch: false, server: server())
        #expect(outcome == .unchanged(confirmed: true))
        #expect(store.data(for: "person.demo_a") == bytes)
        let request = StubAvatarProtocol.recorded.first
        #expect(request?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(request?.value(forHTTPHeaderField: "If-Modified-Since") == "Mon")
        #expect(store.metadata(for: "person.demo_a")?.validatedAt == Date(timeIntervalSince1970: 99))
    }

    @Test func aNewPathReplacesWithoutValidators() async throws {
        let (syncer, store) = syncer()
        try store.save(avatarPNG(gray: 0.1), metadata: metadata(path, etag: "\"old\""), for: "person.demo_a")
        let fresh = avatarPNG(gray: 0.9)
        StubAvatarProtocol.reset { _ in .init(status: 200, body: fresh) }
        let outcome = await syncer.sync(personID: "person.demo_a", picture: "/api/image/serve/new/512x512", entityLoaded: true,
                                        validatedThisLaunch: true, server: server())
        #expect(outcome == .updated(replaced: true))
        #expect(store.data(for: "person.demo_a") == fresh)
        #expect(StubAvatarProtocol.recorded.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(store.metadata(for: "person.demo_a")?.pictureKey == "/api/image/serve/new/512x512")
    }

    @Test func noPictureOnALoadedEntityDeletes() async throws {
        let (syncer, store) = syncer()
        try store.save(avatarPNG(), metadata: metadata(path), for: "person.demo_a")
        StubAvatarProtocol.reset { _ in .init(status: 500) }
        let outcome = await syncer.sync(personID: "person.demo_a", picture: nil, entityLoaded: true, validatedThisLaunch: false, server: server())
        #expect(outcome == .removed)
        #expect(store.data(for: "person.demo_a") == nil && store.metadata(for: "person.demo_a") == nil)
        #expect(StubAvatarProtocol.recorded.isEmpty)
    }

    @Test func anUnloadedEntityNeverDeletesOrAsks() async throws {
        let (syncer, store) = syncer()
        let bytes = avatarPNG()
        try store.save(bytes, metadata: metadata(path), for: "person.demo_a")
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG(gray: 0.9)) }
        let outcome = await syncer.sync(personID: "person.demo_a", picture: nil, entityLoaded: false, validatedThisLaunch: false, server: server())
        #expect(outcome == .unchanged(confirmed: false))
        #expect(store.data(for: "person.demo_a") == bytes)
        #expect(StubAvatarProtocol.recorded.isEmpty)
    }

    @Test func failuresKeepTheCache() async throws {
        let (syncer, store) = syncer()
        let bytes = avatarPNG()
        try store.save(bytes, metadata: metadata(path), for: "person.demo_a")
        for status in [404, 500, 503, 401] {
            StubAvatarProtocol.reset { _ in .init(status: status) }
            let outcome = await syncer.sync(personID: "person.demo_a", picture: "/other", entityLoaded: true, validatedThisLaunch: false, server: server())
            #expect(outcome == .unchanged(confirmed: false))
            #expect(store.data(for: "person.demo_a") == bytes)
            #expect(store.metadata(for: "person.demo_a")?.pictureKey == path)
        }
    }

    @Test func aTransportErrorKeepsTheCache() async throws {
        let (syncer, store) = syncer()
        let bytes = avatarPNG()
        try store.save(bytes, metadata: metadata(path), for: "person.demo_a")
        // No handler and a URL scheme the stub cannot answer: the session throws.
        let outcome = await syncer.sync(personID: "person.demo_a", picture: "mailto:x@y.z", entityLoaded: true, validatedThisLaunch: false,
                                        server: server())
        #expect(outcome == .unchanged(confirmed: false))
        #expect(store.data(for: "person.demo_a") == bytes)
    }

    @Test func bytesThatAreNotAnImageNeverReplaceAPhoto() async throws {
        let (syncer, store) = syncer()
        let bytes = avatarPNG()
        try store.save(bytes, metadata: metadata(path), for: "person.demo_a")
        StubAvatarProtocol.reset { _ in .init(status: 200, body: Data("<html>login</html>".utf8)) }
        let outcome = await syncer.sync(personID: "person.demo_a", picture: "/new", entityLoaded: true, validatedThisLaunch: false, server: server())
        #expect(outcome == .unchanged(confirmed: false))
        #expect(store.data(for: "person.demo_a") == bytes)
    }

    @Test func theTokenGoesOnlyToTheServersHost() async {
        let (syncer, _) = syncer()
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG()) }
        _ = await syncer.sync(personID: "person.demo_a", picture: path, entityLoaded: true, validatedThisLaunch: false, server: server())
        #expect(StubAvatarProtocol.recorded.last?.value(forHTTPHeaderField: "Authorization") == "Bearer T0KEN")
        _ = await syncer.sync(personID: "person.demo_b", picture: "https://cdn.other.com/p.png", entityLoaded: true, validatedThisLaunch: false,
                              server: server())
        #expect(StubAvatarProtocol.recorded.last?.url?.host == "cdn.other.com")
        #expect(StubAvatarProtocol.recorded.last?.value(forHTTPHeaderField: "Authorization") == nil)
        // An absolute URL on the server's own host gets it; a look-alike host does not.
        _ = await syncer.sync(personID: "person.demo_c", picture: "https://HA.example.com/x.png", entityLoaded: true, validatedThisLaunch: false,
                              server: server())
        #expect(StubAvatarProtocol.recorded.last?.value(forHTTPHeaderField: "Authorization") == "Bearer T0KEN")
        _ = await syncer.sync(personID: "person.demo_d", picture: "https://ha.example.com.evil.net/x.png", entityLoaded: true,
                              validatedThisLaunch: false, server: server())
        #expect(StubAvatarProtocol.recorded.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func undecodableAndTruncatedBodiesAreNeverStored() async throws {
        let (syncer, store) = syncer()
        let truncated = Data(avatarPNG().prefix(300))
        for body in [truncated, Data(repeating: 0xFF, count: 2000), Data()] {
            StubAvatarProtocol.reset { _ in .init(status: 200, body: body) }
            let outcome = await syncer.sync(personID: "person.demo_a", picture: path, entityLoaded: true, validatedThisLaunch: false, server: server())
            #expect(outcome == .unchanged(confirmed: false))
            #expect(store.data(for: "person.demo_a") == nil && store.metadata(for: "person.demo_a") == nil)
        }
    }

    @Test func anOversizedBodyIsRefusedWhileStreaming() async {
        let (syncer, store) = syncer()
        let huge = avatarPNG() + Data(repeating: 0, count: PersonAvatarSyncer.maxBytes + 10)
        StubAvatarProtocol.reset { _ in .init(status: 200, body: huge) }
        let outcome = await syncer.sync(personID: "person.demo_a", picture: path, entityLoaded: true, validatedThisLaunch: false, server: server())
        #expect(outcome == .unchanged(confirmed: false) && store.data(for: "person.demo_a") == nil)
        #expect(!PersonAvatarSyncer.validate(huge))
    }

    @Test func aHugeImageByItsHeaderIsRefusedBeforeDecoding() throws {
        // 7,400 x 7,400 = 54.8 MP: over the cap, and small on the wire because it is one flat colour.
        let side = 7400
        let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        CGImageDestinationFinalize(destination)
        let data = output as Data
        #expect(data.count < PersonAvatarSyncer.maxBytes)
        #expect(PersonAvatarSyncer.pixelCount(data) == side * side)
        #expect(!PersonAvatarSyncer.validate(data))
        #expect(PersonAvatarSyncer.validate(avatarPNG()))
    }

    @Test func theSameBytesAgainAreConfirmedNotReplaced() async throws {
        let (syncer, store) = syncer()
        let bytes = avatarPNG()
        try store.save(bytes, metadata: metadata(path, etag: "\"old\""), for: "person.demo_a")
        StubAvatarProtocol.reset { _ in .init(status: 200, headers: ["ETag": "\"new\""], body: bytes) }
        let renamed = "/api/image/serve/renamed/512x512"
        let outcome = await syncer.sync(personID: "person.demo_a", picture: renamed, entityLoaded: true, validatedThisLaunch: false, server: server())
        #expect(outcome == .unchanged(confirmed: true))
        #expect(store.metadata(for: "person.demo_a")?.etag == "\"new\"" && store.metadata(for: "person.demo_a")?.pictureKey == renamed)
    }

    @Test func onlyHttpAndHttpsPicturesAreFetched() async {
        #expect(PersonAvatarSyncer.resolve("file:///etc/passwd", against: base) == nil)
        #expect(PersonAvatarSyncer.resolve("data:image/png;base64,AAAA", against: base) == nil)
        #expect(PersonAvatarSyncer.resolve("ftp://x/y.png", against: base) == nil)
        #expect(PersonAvatarSyncer.resolve("http://ha.example.com/p.png", against: base) != nil)
        let (syncer, _) = syncer()
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG()) }
        let outcome = await syncer.sync(personID: "person.demo_a", picture: "file:///etc/passwd", entityLoaded: true, validatedThisLaunch: false,
                                        server: server())
        #expect(outcome == .unchanged(confirmed: false) && StubAvatarProtocol.recorded.isEmpty)
    }

    @Test func theTokenNeedsTheSameSchemeHostAndPort() {
        let plain = URL(string: "http://ha.example.com/p.png")!
        #expect(!PersonAvatarSyncer.sendsToken(to: plain, server: base), "never in clear text to an https server")
        #expect(!PersonAvatarSyncer.sendsToken(to: URL(string: "https://ha.example.com:8123/p.png")!, server: base))
        #expect(PersonAvatarSyncer.sendsToken(to: URL(string: "https://ha.example.com:443/p.png")!, server: base))
        #expect(PersonAvatarSyncer.sendsToken(to: URL(string: "https://ha.example.com/p.png")!, server: base))
        let local = URL(string: "http://192.0.2.14:8123")!
        #expect(PersonAvatarSyncer.sendsToken(to: URL(string: "http://192.0.2.14:8123/p.png")!, server: local))
        #expect(!PersonAvatarSyncer.sendsToken(to: URL(string: "http://192.0.2.14:9000/p.png")!, server: local))
        // The redirect guard uses the same rule: a hop to another scheme or port drops the header.
        #expect(PersonAvatarSyncer.sameOrigin(URL(string: "https://A.example.com/x")!, URL(string: "https://a.example.com/y")!))
        #expect(!PersonAvatarSyncer.sameOrigin(plain, URL(string: "https://ha.example.com/p.png")!))
        #expect(!PersonAvatarSyncer.sameOrigin(URL(string: "https://ha.example.com/")!, URL(string: "https://ha.example.com:444/")!))
    }

    @Test func hostRuleAndResolution() {
        #expect(PersonAvatarSyncer.sendsToken(to: URL(string: "https://ha.example.com/a")!, server: base))
        #expect(!PersonAvatarSyncer.sendsToken(to: URL(string: "https://other.example.com/a")!, server: base))
        #expect(PersonAvatarSyncer.resolve("/api/image/serve/a/512x512", against: base)?.absoluteString
            == "https://ha.example.com/api/image/serve/a/512x512")
        #expect(PersonAvatarSyncer.resolve("https://cdn.x.com/p.png", against: base)?.host == "cdn.x.com")
    }

    @Test func decodeBoundsTheLongestSide() throws {
        let image = try #require(PersonAvatarSyncer.decode(avatarPNG(side: 1000)))
        #expect(max(image.width, image.height) == PersonAvatarSyncer.decodePixels)
        #expect(PersonAvatarSyncer.decode(Data([0, 1, 2])) == nil)
    }
}

// MARK: - PersonAvatars

@MainActor
@Suite(.serialized, .demoHouse)
struct PersonAvatarsTests {
    private let path = "/api/image/serve/abc/512x512"

    private func person(_ id: String, picture: String?, userID: String? = nil, state: String = "home") -> EntityState {
        var attributes: [String: JSONValue] = [:]
        if let picture { attributes["entity_picture"] = .string(picture) }
        if let userID { attributes["user_id"] = .string(userID) }
        return EntityState(entityId: id, state: state, attributes: attributes)
    }

    private func make() -> (PersonAvatars, EntityStore, PersonAvatarStore) {
        let store = PersonAvatarStore(directory: tempDirectory())
        let avatars = PersonAvatars(store: store, session: stubSession())
        return (avatars, EntityStore(), store)
    }

    private func start(_ avatars: PersonAvatars, _ entities: EntityStore) {
        avatars.start(entityStore: entities, server: .init(baseURL: base, accessToken: { "T0KEN" }))
    }

    /// Waits (event-driven, bounded) until `condition` holds.
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aPictureOnTheServerIsDownloadedAndDrawnOnce() async {
        let (avatars, entities, store) = make()
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG()) }
        let box = avatars.box(for: "person.demo_a")
        #expect(box.image == nil)
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: path)])
        await settle { box.image != nil }
        #expect(box.image != nil && box.revision == 1)
        #expect(store.data(for: "person.demo_a") != nil)
    }

    @Test func nothingHappensWhileTheStoreIsOnlyASnapshot() async {
        let (avatars, entities, store) = make()
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG()) }
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: path)], freshness: .snapshot(savedAt: .now))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(StubAvatarProtocol.recorded.isEmpty && store.data(for: "person.demo_a") == nil)
    }

    @Test func aColdLaunchSeedsTheBoxFromDiskWithoutTheNetwork() throws {
        let (avatars, _, store) = make()
        StubAvatarProtocol.reset { _ in .init(status: 500) }
        try store.save(avatarPNG(), metadata: metadata(path), for: "person.demo_a")
        let box = avatars.box(for: "person.demo_a")
        #expect(box.image != nil && box.revision == 0)
        #expect(StubAvatarProtocol.recorded.isEmpty)
    }

    @Test func aNewPictureReplacesThePhotoInPlace() async throws {
        let (avatars, entities, store) = make()
        try store.save(avatarPNG(gray: 0.1), metadata: metadata(path), for: "person.demo_a")
        let box = avatars.box(for: "person.demo_a")
        let before = try #require(box.image)
        StubAvatarProtocol.reset { request in
            request.url?.path.contains("new") == true ? .init(status: 200, body: avatarPNG(gray: 0.9)) : .init(status: 304)
        }
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: path)])
        await settle { !StubAvatarProtocol.recorded.isEmpty }
        // Same path: a conditional request, and the photo stays.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(box.revision == 0 && box.image === before)
        entities.apply([person("person.demo_a", picture: "/api/image/serve/new/512x512")])
        await settle { box.revision == 1 }
        #expect(box.revision == 1)
        #expect(box.image != nil && box.image !== before)
    }

    @Test func aMissingPictureOnALoadedEntityRemovesThePhoto() async throws {
        let (avatars, entities, store) = make()
        try store.save(avatarPNG(), metadata: metadata(path), for: "person.demo_a")
        let box = avatars.box(for: "person.demo_a")
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: nil)])
        await settle { box.image == nil }
        #expect(box.image == nil && store.data(for: "person.demo_a") == nil)
    }

    @Test func aFailedRequestKeepsThePhotoOnScreenAndOnDisk() async throws {
        let (avatars, entities, store) = make()
        try store.save(avatarPNG(), metadata: metadata(path), for: "person.demo_a")
        let box = avatars.box(for: "person.demo_a")
        StubAvatarProtocol.reset { _ in .init(status: 503) }
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: "/api/image/serve/new/512x512")])
        await settle { !StubAvatarProtocol.recorded.isEmpty }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(box.image != nil && store.data(for: "person.demo_a") != nil)
    }

    @Test func aPositionTickDoesNotRequestAgain() async {
        let (avatars, entities, _) = make()
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG()) }
        let box = avatars.box(for: "person.demo_a")
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: path)])
        await settle { box.image != nil }
        let requests = StubAvatarProtocol.recorded.count
        for tick in 0..<5 {
            entities.apply([person("person.demo_a", picture: path, state: tick.isMultiple(of: 2) ? "not_home" : "home")])
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(StubAvatarProtocol.recorded.count == requests && box.revision == 1)
    }

    @Test func theViewerIsTheUsersPersonAndIsRemembered() async {
        let (avatars, entities, store) = make()
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG()) }
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: path, userID: "u1"), person("person.demo_b", picture: path, userID: "u2")])
        avatars.setViewer(userID: "u2")
        #expect(avatars.viewerPersonID == "person.demo_b" && avatars.viewerBox?.id == "person.demo_b")
        #expect(store.viewerPersonID == "person.demo_b")
        // A new PersonAvatars (the next launch) knows it before any network.
        #expect(PersonAvatars(store: store).viewerPersonID == "person.demo_b")
        await settle { avatars.box(for: "person.demo_a").image != nil && avatars.box(for: "person.demo_b").image != nil }
    }

    @Test func aDownloadFinishingAfterSignOutLeavesNoFiles() async {
        let (avatars, entities, store) = make()
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG(), delay: 0.3) }
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: path)])
        await settle { !StubAvatarProtocol.recorded.isEmpty }
        avatars.removeAll()
        try? await Task.sleep(for: .milliseconds(600))
        #expect(!FileManager.default.fileExists(atPath: store.directory.path), "nothing was recreated after sign-out")
        #expect(avatars.box(for: "person.demo_a").image == nil)
    }

    @Test func signingOutAndInWithinOneDownloadKeepsTheNewSessionsPhoto() async {
        let (avatars, entities, store) = make()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        StubAvatarProtocol.reset { _ in
            let call = calls.withLock { (count: inout Int) -> Int in count += 1; return count }
            return call == 1 ? .init(status: 200, body: avatarPNG(gray: 0.1), delay: 0.4) : .init(status: 200, body: avatarPNG(gray: 0.9))
        }
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: path)])
        await settle { calls.withLock { $0 } == 1 }
        avatars.removeAll()
        start(avatars, entities)
        await settle { store.data(for: "person.demo_a") != nil }
        let second = store.data(for: "person.demo_a")
        #expect(second != nil)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(store.data(for: "person.demo_a") == second, "the first session's late result neither deleted nor replaced it")
        #expect(avatars.box(for: "person.demo_a").image != nil)
    }

    @Test func aLateViewerLookupAfterSignOutIsIgnored() {
        let (avatars, entities, store) = make()
        StubAvatarProtocol.reset { _ in .init(status: 404) }
        start(avatars, entities)
        avatars.removeAll()
        avatars.setViewer(userID: "u1")
        entities.replaceAll([person("person.demo_a", picture: nil, userID: "u1")])
        #expect(avatars.viewerPersonID == nil && store.viewerPersonID == nil)
        // The next session must not inherit it either.
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: nil, userID: "u1"), person("person.demo_b", picture: nil, userID: "u2")])
        #expect(avatars.viewerPersonID == nil)
        avatars.setViewer(userID: "u2")
        #expect(avatars.viewerPersonID == "person.demo_b")
    }

    @Test func aRememberedViewerNobodyMatchesIsClearedOnceLive() {
        let store = PersonAvatarStore(directory: tempDirectory())
        store.viewerPersonID = "person.demo_old"
        let avatars = PersonAvatars(store: store, session: stubSession())
        let entities = EntityStore()
        #expect(avatars.viewerPersonID == "person.demo_old")
        StubAvatarProtocol.reset { _ in .init(status: 404) }
        start(avatars, entities)
        avatars.setViewer(userID: "u9")
        #expect(avatars.viewerPersonID == "person.demo_old", "not live yet: no evidence")
        entities.replaceAll([person("person.demo_a", picture: nil, userID: "u1")])
        avatars.setViewer(userID: "u9")
        #expect(avatars.viewerPersonID == nil && store.viewerPersonID == nil)
    }

    @Test func aPersonWhoAppearsMidSessionIsPickedUp() async {
        let (avatars, entities, _) = make()
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG()) }
        start(avatars, entities)
        entities.replaceAll([EntityState(entityId: "light.demo_kitchen_item_1", state: "on")])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(StubAvatarProtocol.recorded.isEmpty)
        let box = avatars.box(for: "person.demo_new")
        entities.apply([person("person.demo_new", picture: path)])
        await settle { box.image != nil }
        #expect(box.image != nil)
    }

    @Test func peopleRevisionMovesOnlyWhenAPersonComesOrGoes() {
        let entities = EntityStore()
        entities.replaceAll([EntityState(entityId: "light.demo_a", state: "on")])
        #expect(entities.peopleRevision == 0)
        entities.apply([EntityState(entityId: "light.demo_a", state: "off"), EntityState(entityId: "light.demo_b", state: "on")])
        #expect(entities.peopleRevision == 0)
        entities.apply([person("person.demo_a", picture: nil)])
        #expect(entities.peopleRevision == 1)
        entities.apply([person("person.demo_a", picture: path, state: "not_home")])
        #expect(entities.peopleRevision == 1, "a change to a known person is the box's business")
        entities.apply([], removing: ["person.demo_a"], freshness: .live)
        #expect(entities.peopleRevision == 2)
        entities.replaceAll([person("person.demo_b", picture: nil)])
        #expect(entities.peopleRevision == 3)
        entities.reset()
        #expect(entities.peopleRevision == 4)
    }

    @Test func aPersistentFailureIsNotRetriedOnEveryTick() async {
        let store = PersonAvatarStore(directory: tempDirectory())
        let avatars = PersonAvatars(store: store, session: stubSession(), retryCooldown: 0.4)
        let entities = EntityStore()
        StubAvatarProtocol.reset { _ in .init(status: 404) }
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: path)])
        await settle { !StubAvatarProtocol.recorded.isEmpty }
        try? await Task.sleep(for: .milliseconds(50))
        for tick in 0..<6 {
            entities.apply([person("person.demo_a", picture: path, state: tick.isMultiple(of: 2) ? "not_home" : "home")])
            try? await Task.sleep(for: .milliseconds(15))
        }
        #expect(StubAvatarProtocol.recorded.count == 1, "cooling down")
        // A new picture is a new question, even while cooling.
        entities.apply([person("person.demo_a", picture: "/api/image/serve/other/512x512")])
        await settle { StubAvatarProtocol.recorded.count == 2 }
        #expect(StubAvatarProtocol.recorded.count == 2)
        // After the cooldown the next change asks again.
        try? await Task.sleep(for: .milliseconds(500))
        entities.apply([person("person.demo_a", picture: "/api/image/serve/other/512x512", state: "not_home")])
        await settle { StubAvatarProtocol.recorded.count == 3 }
        #expect(StubAvatarProtocol.recorded.count == 3)
    }

    @Test func identicalBytesDoNotPlayAFade() async throws {
        let (avatars, entities, store) = make()
        let bytes = avatarPNG()
        try store.save(bytes, metadata: metadata(path), for: "person.demo_a")
        let box = avatars.box(for: "person.demo_a")
        StubAvatarProtocol.reset { _ in .init(status: 200, body: bytes) }
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: "/api/image/serve/renamed/512x512")])
        await settle { !StubAvatarProtocol.recorded.isEmpty }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(box.revision == 0 && box.image != nil)
    }

    @Test func anUndecodableFileOnDiskIsDeletedNotDrawn() throws {
        let (avatars, _, store) = make()
        try store.save(Data(repeating: 7, count: 500), metadata: metadata(path), for: "person.demo_a")
        let box = avatars.box(for: "person.demo_a")
        #expect(box.image == nil && store.data(for: "person.demo_a") == nil)
    }

    @Test func removeAllDeletesFilesAndClearsBoxes() async throws {
        let (avatars, entities, store) = make()
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG()) }
        let box = avatars.box(for: "person.demo_a")
        start(avatars, entities)
        entities.replaceAll([person("person.demo_a", picture: path, userID: "u1")])
        avatars.setViewer(userID: "u1")
        await settle { box.image != nil }
        #expect(box.image != nil)
        avatars.removeAll()
        #expect(box.image == nil && avatars.viewerPersonID == nil)
        #expect(store.personIDs().isEmpty && store.viewerPersonID == nil)
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))
        // The old session's watcher is gone: a change after sign-out fetches nothing.
        StubAvatarProtocol.reset { _ in .init(status: 200, body: avatarPNG()) }
        entities.apply([person("person.demo_a", picture: "/api/image/serve/other/512x512")])
        try? await Task.sleep(for: .milliseconds(100))
        #expect(StubAvatarProtocol.recorded.isEmpty && box.image == nil)
    }
}
}
