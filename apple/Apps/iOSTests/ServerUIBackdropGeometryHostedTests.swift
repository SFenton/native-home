import CryptoKit
import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - A scene that has not laid out defers the publication

/// Window geometry is timing, not document validity: a backdrop asked for before the scene has a size defers the candidate, and the
/// host's layout retries it. It never fails acceptance.
@MainActor
final class ServerUIBackdropGeometryHostedTests: XCTestCase {
    func testZeroWindowBoundsAreDeferrableNeverARejection() throws {
        for size in [CGSize.zero, CGSize(width: 390, height: 0), CGSize(width: 0, height: 844)] {
            XCTAssertThrowsError(try UKServerUIProductionRuntime.Prepared.requireGeometry(size), "\(size)") {
                XCTAssertEqual(($0 as? any ServerUIDeferrableFailure)?.isDeferred, true,
                               "the store keeps the candidate and commits it once the scene has laid out")
            }
        }
    }

    func testAWindowWithASizeHasGeometry() {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 466, height: 678), CGSize(width: 1024, height: 1366)] {
            XCTAssertNoThrow(try UKServerUIProductionRuntime.Prepared.requireGeometry(size), "\(size)")
        }
    }

    /// A publication that arrives before the scene has a size is kept, and the window's first layout commits it.
    func testADeferredCandidateCommitsOnceTheWindowHasBounds() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("geometry-defer-\(UUID())")
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [])
        defer {
            session.signOut()
            try? FileManager.default.removeItem(at: directory)
        }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing synthetic session") }
        let runtime = UKServerUIProductionRuntime(session: session, connection: connection, privateRoot: directory,
                                                  transport: QuietTransport())
        defer { runtime.endSession() }
        let store = try XCTUnwrap(runtime.store)
        await store.bind(userID: "ha-user-1")
        // The host exists and is attached, but has never been laid out: its bounds are zero.
        let host = UKServerUIProductionHost(runtime: runtime, session: session, connection: connection, environment: UKShellEnvironment())
        host.view.frame = .zero
        XCTAssertFalse(host.hasGeometry)

        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "/document/assets", to: .array([]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/theme/background",
            to: .object(["type": "solid", "token": "shell-base@1"]))
        json = try ServerUIRendererFixture.changing(json, path: "/assetManifestSha256",
            to: .string(SHA256.hash(data: Data("[]".utf8)).map { String(format: "%02x", $0) }.joined()))
        if case .object(let root) = json, case .array(let capabilities)? = root["capabilities"] {
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities",
                to: .array(capabilities.filter { $0 != .string("sh.assets.publisher@1") }))
        }
        let envelope = try JSONSerialization.jsonObject(with: JSONEncoder().encode(json))
        let reply = try JSONSerialization.data(withJSONObject: [
            "state": "published", "epoch": "epoch-1", "revision": 1,
            "envelopeSha256": String(repeating: "c", count: 64), "envelope": envelope,
        ] as [String: Any])
        await store.apply(ServerUIPublicationEvent.judge(.success(reply)))
        XCTAssertTrue(store.hasDeferredCandidate, "zero bounds keep the candidate instead of failing it")
        XCTAssertNil(store.current)
        XCTAssertNil(host.renderer)

        let window = HostedPage.show(host, size: HostedPage.phoneSize)
        defer { window.isHidden = true; host.didMove(toParent: nil) }
        XCTAssertTrue(host.hasGeometry)
        var committed = false
        let deadline = ContinuousClock.now + .seconds(5)
        while !committed, ContinuousClock.now < deadline {
            committed = store.current != nil && host.renderer != nil
            if !committed { try await Task.sleep(for: .milliseconds(20)) }
        }
        XCTAssertTrue(committed, "the window's first layout retried the deferred candidate and it committed")
        XCTAssertFalse(store.hasDeferredCandidate)
    }
}

// MARK: - The publication's render folder

/// The render files belong to the publication, not the window: every window, and the next launch, reads and writes one folder, and the
/// app's return from the background, not the background itself, makes a render.
@MainActor
final class ServerUIBackdropFolderHostedTests: XCTestCase {
    func testOnlyTheRetiredPerWindowFoldersAreRemoved() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("render-folders-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let retired = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let digest = directory.appendingPathComponent(String(repeating: "a", count: 64), isDirectory: true)
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: digest, withIntermediateDirectories: true)
        try Data([1]).write(to: retired.appendingPathComponent("latest.txt"))
        let uuidFile = directory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: uuidFile)
        try Data([1]).write(to: directory.appendingPathComponent("latest.txt"))

        UKServerUIProductionRuntime.Prepared.removeWindowFolders(in: directory)

        let left = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertEqual(left, [digest.lastPathComponent, uuidFile.lastPathComponent, "latest.txt"],
                       "only a folder named by a scene UUID goes; renders, digests and files stay")
    }

    func testEveryWindowAndTheNextLaunchShareThePublicationsRenderFolder() async throws {
        let rig = try await Rig.make()
        defer { rig.tearDown() }
        let renders = rig.directory.appendingPathComponent("renders", isDirectory: true)
        let retired = renders.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: true)
        let photo = try XCTUnwrap(HouseBackdropStore.fixturePhoto())

        let prepared = UKServerUIProductionRuntime.Prepared(assets: rig.assets, photo: photo, blurPercent: 50, directory: renders)
        defer { prepared.releasePlans() }
        let hosts = (0..<2).map { _ in rig.host() }
        let windows = hosts.map { HostedPage.show($0, size: HostedPage.phoneSize) }
        defer { windows.forEach { $0.isHidden = true } }
        for host in hosts { try await prepared.prepare(host: host) }
        let stores = try hosts.map { try prepared.backdrop(for: $0) }
        XCTAssertFalse(stores[0] === stores[1], "each window keeps its own store")
        let stored = await Self.until { BackdropRenderer.loadLatest(in: renders) != nil }
        XCTAssertTrue(stored, "the render is stored in the publication's folder")
        let retiredGone = await Self.until { !FileManager.default.fileExists(atPath: retired.path) }
        XCTAssertTrue(retiredGone, "the retired per-window folder is gone")
        let folders = try FileManager.default.contentsOfDirectory(at: renders, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        XCTAssertTrue(folders.isEmpty, "no window folder: \(folders.map(\.lastPathComponent))")

        // The next launch: a new preparation and a new window over the same folder.
        let relaunched = UKServerUIProductionRuntime.Prepared(assets: rig.assets, photo: photo, blurPercent: 50, directory: renders)
        defer { relaunched.releasePlans() }
        let next = rig.host()
        let window = HostedPage.show(next, size: HostedPage.phoneSize)
        defer { window.isHidden = true }
        let store = try relaunched.backdrop(for: next)
        XCTAssertNotNil(store.image, "the stored render is up before any render runs")
        try await relaunched.prepare(host: next)
        XCTAssertEqual(store.renderCount, 0, "and it is reused, not made again")
    }

    func testPreparationInTheBackgroundDefersUntilTheForeground() async throws {
        let rig: Rig
        do { rig = try await Rig.make() } catch { return XCTFail("rig: \(error)") }
        defer { rig.tearDown() }
        let photo = try XCTUnwrap(HouseBackdropStore.fixturePhoto())
        let prepared = UKServerUIProductionRuntime.Prepared(assets: rig.assets, photo: photo, blurPercent: 50,
                                                            directory: rig.directory.appendingPathComponent("renders"))
        defer { prepared.releasePlans() }
        let host = rig.host()
        let window = HostedPage.show(host, size: HostedPage.phoneSize)
        defer { window.isHidden = true }
        let store: HouseBackdropStore
        do { store = try prepared.backdrop(for: host) } catch { return XCTFail("backdrop: \(error)") }
        store.setSuspended(true)
        do {
            try await prepared.prepare(host: host)
            XCTFail("a suspended render cannot finish preparation")
        } catch {
            XCTAssertEqual((error as? any ServerUIDeferrableFailure)?.isDeferred, true,
                           "the background is timing: the candidate is kept and retried, never rejected")
        }
        XCTAssertNil(store.image)

        store.setSuspended(false)
        do { try await prepared.prepare(host: host) } catch { return XCTFail("resumed prepare: \(error)") }
        XCTAssertNotNil(store.image, "back in the foreground the render finishes and preparation completes")
    }

    // MARK: - Fixture

    private static func until(_ seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    /// A signed-in session, its runtime, and the staged assets of a publication with no asset of its own.
    @MainActor private struct Rig {
        let directory: URL
        let session: AppSession
        let connection: HassConnection
        let runtime: UKServerUIProductionRuntime
        let assets: ServerUIStagedAssets

        static func make() async throws -> Rig {
            let directory = URL.temporaryDirectory.appendingPathComponent("render-folder-\(UUID())")
            let session = AppSession(tokenStore: InMemoryTokenStore(),
                snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
                houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
                buildDefault: nil, launchArguments: [])
            let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
            try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
            guard case .signedIn(let connection, _) = session.phase else { throw XCTSkip("Missing synthetic session") }
            let runtime = UKServerUIProductionRuntime(session: session, connection: connection, privateRoot: directory,
                                                      transport: QuietTransport())
            var json = try ServerUIRendererFixture.json()
            json = try ServerUIRendererFixture.changing(json, path: "/document/assets", to: .array([]))
            json = try ServerUIRendererFixture.changing(json, path: "/document/theme/background",
                to: .object(["type": "solid", "token": "shell-base@1"]))
            json = try ServerUIRendererFixture.changing(json, path: "/assetManifestSha256",
                to: .string(SHA256.hash(data: Data("[]".utf8)).map { String(format: "%02x", $0) }.joined()))
            let capabilities = ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.assets.publisher@1" }
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
            let publication = try ServerUIRendererFixture.publication(json)
            let partition = try ServerUIPublicationPartition(server: server)
            let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: partition.storageDirectory(in: directory),
                transport: ServerUIAssetTransport(server: server, tokenProvider: { throw URLError(.notConnectedToInternet) }))
            let assets = try await stager.stage(publication, documentDigest: publication.documentSha256)
            return Rig(directory: directory, session: session, connection: connection, runtime: runtime, assets: assets)
        }

        func host() -> UKServerUIProductionHost {
            UKServerUIProductionHost(runtime: runtime, session: session, connection: connection, environment: UKShellEnvironment())
        }

        func tearDown() {
            runtime.endSession()
            session.signOut()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

/// A transport that never answers: the test hands the store its publication directly.
@MainActor
private final class QuietTransport: ServerUIPublicationTransport {
    func subscribe(capabilities: [String], handler: @escaping @Sendable (Result<Data, any Error>) -> Void) -> @Sendable () -> Void { {} }
}
