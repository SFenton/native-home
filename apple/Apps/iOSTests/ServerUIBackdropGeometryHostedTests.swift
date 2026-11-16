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

/// A transport that never answers: the test hands the store its publication directly.
@MainActor
private final class QuietTransport: ServerUIPublicationTransport {
    func subscribe(capabilities: [String], handler: @escaping @Sendable (Result<Data, any Error>) -> Void) -> @Sendable () -> Void { {} }
}
