import CoreSpotlight
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
    private func hasShell(_ root: UIViewController) -> Bool { root.children.contains { $0 is UKShellViewController } }

    func testSigningInHoldsHomeUnderTheSignInLayerThenLiftsItAway() async throws {
        let session = session()
        let root = UKRootViewController(session: session)
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        XCTAssertTrue(hasLogin(root))
        XCTAssertFalse(session.motion.hasPlayed(.signInArrival))
        try root.signedIn(server, tokens)
        XCTAssertTrue(hasShell(root), "Home is built behind the sign-in layer")
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
        rig.navigator.open(.homePage("vacuums"))
        rig.settle(0.6)
        center.post(name: UIScene.didActivateNotification, object: scene)
        center.post(name: UIScene.willDeactivateNotification, object: scene)
        rig.settle(0.1)
        XCTAssertNotNil(scene.session.userInfo?["routes"] ?? scene.session.userInfo?.values.first, "leaving the foreground saves the stacks")
        let saved = scene.session.userInfo?.count ?? 0
        scene.session.userInfo = [:]
        center.post(name: UIScene.didEnterBackgroundNotification, object: scene)
        rig.settle(0.1)
        XCTAssertGreaterThanOrEqual(scene.session.userInfo?.count ?? 0, 1, "the background saves again (\(saved) before)")
        // Another scene's notifications are not ours.
        scene.session.userInfo = [:]
        center.post(name: UIScene.didEnterBackgroundNotification, object: nil)
        rig.settle(0.1)
        XCTAssertEqual(scene.session.userInfo?.count ?? 0, 0)
    }

    func testTheDebugHooksOpenASpotlightResultAndDumpTheViews() throws {
        let id = try XCTUnwrap(SpotlightCatalog.entries.first).id
        let dump = FileManager.default.temporaryDirectory.appending(path: "uk-viewdump-\(UUID().uuidString).txt").path
        for (key, value) in [("FENTON_OPEN_SPOTLIGHT", id), ("FENTON_DUMP_VIEWS", "0.1"), ("FENTON_DUMP_FILE", dump)] { setenv(key, value, 1) }
        defer { for key in ["FENTON_OPEN_SPOTLIGHT", "FENTON_DUMP_VIEWS", "FENTON_DUMP_FILE"] { unsetenv(key) } }
        let session = session()
        let root = UKRootViewController(session: session)
        let window = HostedScene.show(root) ?? HostedPage.show(root)
        defer { window.isHidden = true }
        settle(0.8)
        XCTAssertNotNil(session.push.pendingRequest, "the Spotlight result's page is requested")
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
