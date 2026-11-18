import CoreSpotlight
import FentonActivityModel
import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A token store whose save fails, to refuse a sign-in.
private struct RefusingTokenStore: TokenStore {
    struct Refused: Error {}
    func load() -> StoredCredentials? { nil }
    func save(_ credentials: StoredCredentials) throws { throw Refused() }
    func clear() {}
}

/// The root controller: sign-in, the arrival after it, the scene's phases, the launch ground and the debug hooks.
@MainActor
final class UKHostedRootTests: DemoHouseTestCase {
    private let server = HassServer(baseURL: URL(string: "http://127.0.0.1:9")!)
    private var tokens: AuthTokens { AuthTokens(accessToken: "test", expiresAt: .distantFuture, refreshToken: "test") }

    private func session(store: TokenStore = InMemoryTokenStore()) -> AppSession {
        AppSession(tokenStore: store, snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "uk-hosted-root-\(UUID().uuidString).json")))
    }

    private func settle(_ seconds: TimeInterval = 0.3) { HostedPage.wait(seconds) }

    private func hasLogin(_ root: UIViewController) -> Bool { root.children.contains { $0 is UKLoginViewController } }
    private func hasShell(_ root: UIViewController) -> Bool { root.children.contains { $0 is UKServerUIProductionHost } }

    func testSigningInHoldsHomeUnderTheSignInLayerThenLiftsItAway() async throws {
        let session = session()
        let root = UKRootViewController(session: session)
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        XCTAssertTrue(hasLogin(root))
        XCTAssertFalse(session.motion.hasPlayed(.signInArrival))
        try root.signedIn(server, tokens)
        XCTAssertTrue(hasShell(root), "the product is built behind the sign-in layer")
        XCTAssertTrue(hasLogin(root), "and the sign-in layer is still up while Home arrives")
        XCTAssertTrue(session.motion.hasPlayed(.signInArrival), "the arrival plays once per session")
        let login = root.children.first { $0 is UKLoginViewController }
        XCTAssertFalse(login?.view.isUserInteractionEnabled ?? true, "the layer takes no touches while it leaves")
        XCTAssertEqual(login?.view.accessibilityElementsHidden, true, "and is hidden from VoiceOver")
        let end = Date().addingTimeInterval(4)
        while Date() < end, hasLogin(root) { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(hasLogin(root), "the layer is gone once its lift ends")
        XCTAssertTrue(hasShell(root))
    }

    func testReduceMotionCrossFadesTheSignInLayerAway() async throws {
        let session = session()
        let root = UKRootViewController(session: session)
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        root.environment.reduceMotion = true
        try root.signedIn(server, tokens)
        let end = Date().addingTimeInterval(4)
        while Date() < end, hasLogin(root) { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(hasLogin(root))
        XCTAssertTrue(hasShell(root))
    }

    func testASecondSignInInTheSameSessionJustSwapsTheScreens() throws {
        let session = session()
        session.motion.markPlayed(.signInArrival)
        let root = UKRootViewController(session: session)
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        try root.signedIn(server, tokens)
        settle(0.3)
        XCTAssertTrue(hasShell(root))
        XCTAssertFalse(hasLogin(root), "no arrival: the sign-in layer goes with the swap")
    }

    func testARefusedSignInEndsTheArrivalAndLeavesTheSignInUp() {
        let session = session(store: RefusingTokenStore())
        let root = UKRootViewController(session: session)
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        XCTAssertThrowsError(try root.signedIn(server, tokens))
        settle(0.3)
        XCTAssertTrue(hasLogin(root))
        XCTAssertFalse(hasShell(root))
        XCTAssertFalse(session.isSignedIn)
    }

    func testARejectedTokenShowsTheWelcomeBackSignIn() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        rig.session.sessionExpired()
        rig.settle(0.8)
        XCTAssertFalse(hasShell(rig.root), "the tabs leave at once")
        XCTAssertTrue(hasLogin(rig.root))
    }

    func testTheSceneTellsTheRootWhenItIsActiveAndWhenItLeavesTheForeground() throws {
        let rig = try HostedShellRig.make(inScene: true)
        defer { rig.tearDown() }
        rig.settle()
        let scene = try XCTUnwrap(rig.window.windowScene)
        let center = NotificationCenter.default
        center.post(name: UIScene.didActivateNotification, object: scene)
        center.post(name: UIScene.willDeactivateNotification, object: scene)
        center.post(name: UIScene.didEnterBackgroundNotification, object: scene)
        rig.settle(0.1)
        XCTAssertTrue(hasShell(rig.root), "the product stays through the scene's phases")
        // Another scene's notifications are not ours: nothing here may throw or tear the product down.
        center.post(name: UIScene.didEnterBackgroundNotification, object: nil)
        rig.settle(0.1)
        XCTAssertTrue(hasShell(rig.root))
    }

    func testTheDebugHooksOpenASpotlightResultAndDumpTheViews() throws {
        let catalog = RouteCatalog(sessionID: String(repeating: "a", count: 64), revision: 1, routes: [
            RouteCatalogEntry(id: "kitchen-page", path: "kitchen", title: "Kitchen", summary: "Kitchen lights", icon: "fork.knife"),
        ])
        let id = try XCTUnwrap(SpotlightCatalog.entries(for: catalog).first).id
        let dump = FileManager.default.temporaryDirectory.appending(path: "uk-viewdump-\(UUID().uuidString).txt").path
        for (key, value) in [("FENTON_OPEN_SPOTLIGHT", id), ("FENTON_DUMP_VIEWS", "0.1"), ("FENTON_DUMP_FILE", dump)] { setenv(key, value, 1) }
        defer { for key in ["FENTON_OPEN_SPOTLIGHT", "FENTON_DUMP_VIEWS", "FENTON_DUMP_FILE"] { unsetenv(key) } }
        let session = session()
        session.push.routeCatalog = { catalog }
        let root = UKRootViewController(session: session)
        let window = HostedScene.show(root) ?? HostedPage.show(root)
        defer { window.isHidden = true }
        settle(0.8)
        XCTAssertEqual(session.push.pendingRequest?.route, RouteRequest(path: "kitchen"), "the Spotlight result's route is requested")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dump), "the view hierarchy is written once")
        try? FileManager.default.removeItem(atPath: dump)
    }

    func testAGalleryRequestedAtLaunchIsReplacedWhenTheJourneyResets() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "uk-reuse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        setenv("FENTON_UITEST_REUSE", directory.path, 1)
        setenv("FENTON_GALLERY", "backdrop", 1)
        defer {
            unsetenv("FENTON_UITEST_REUSE")
            unsetenv("FENTON_GALLERY")
            try? FileManager.default.removeItem(at: directory)
        }
        let root = UKRootViewController(session: session())
        let window = HostedScene.show(root) ?? HostedPage.show(root)
        defer { window.isHidden = true }
        let marker = { root.view.subviews.compactMap { $0 as? UKProbeElementView }.first { $0.accessibilityIdentifier == "uitest.generation" } }
        XCTAssertNotNil(marker(), "the generation a journey waits on")
        XCTAssertEqual(root.children.count, 1, "the requested gallery fills the window instead of the session")
        let generation = GalleryReset.shared.generation
        let url = try XCTUnwrap(URL(string: "fentonhome://uitest-reset?FENTON_GALLERY=motion"))
        XCTAssertTrue(GalleryReset.shared.apply(url))
        settle(0.2)
        XCTAssertEqual(root.children.count, 0, "a reset drops the gallery")
        let end = Date().addingTimeInterval(5)
        while Date() < end, GalleryReset.shared.generation == generation { settle(0.1) }
        settle(0.3)
        XCTAssertEqual(root.children.count, 1, "and builds the next one")
        XCTAssertEqual(marker()?.accessibilityLabel, "\(GalleryReset.shared.generation)")
    }

    func testTheRotationProbeAsksTheSceneForPortrait() throws {
        let rig = try HostedShellRig.make(inScene: true)
        defer { rig.tearDown() }
        rig.settle()
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("uk.debug.portrait" as CFString), nil, nil, true)
        rig.settle(0.3)
        XCTAssertEqual(rig.window.windowScene?.interfaceOrientation, .portrait)
    }

    func testTheRootGoesAwayWithItsObservers() {
        weak var weakRoot: UKRootViewController?
        autoreleasepool {
            let root = UKRootViewController(session: session())
            weakRoot = root
            let window = HostedPage.show(root)
            window.isHidden = true
            window.rootViewController = nil
        }
        settle(0.2)
        XCTAssertNil(weakRoot)
    }
}

// MARK: - What the session observation follows

/// The root's observation follows the session's phase and the remembered account, and nothing the sync builds.
@MainActor
final class UKHostedRootObservationTests: DemoHouseTestCase {
    func testBuildingTheShellMakesTheSessionObservationFollowNoEntity() throws {
        let server = HassServer(baseURL: URL(string: "http://127.0.0.1:9")!)
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "uk-hosted-root-obs-\(UUID().uuidString).json")))
        session.motion.markPlayed(.signInArrival)
        try session.didSignIn(server: server, tokens: AuthTokens(accessToken: "test", expiresAt: .distantFuture, refreshToken: "test"))
        guard case .signedIn(let connection, _) = session.phase else { return XCTFail("signed in") }
        // A known resident, so the Profile attention value reads the vacation, chores and expired-food entities when the providers make it.
        session.setPublicationUser("demo-user-alex", connection: connection)
        let root = UKRootViewController(session: session)
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        HostedPage.wait(0.3)
        XCTAssertTrue(root.children.contains { $0 is UKServerUIProductionHost }, "the shell was built from the observation's first run")
        let syncs = root.phaseSyncs
        _ = connection.store.apply([EntityState(entityId: ChoresConfig.vacationModeEntityId, state: "on")])
        _ = connection.store.apply([EntityState(entityId: ProfileSummary.expiredFoodEntityId, state: "2")])
        HostedPage.wait(0.3)
        XCTAssertEqual(root.phaseSyncs, syncs, "a change to the entities the attention count reads does not run the root's session sync again")
    }
}
