@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A signed-in root on a connection that never reaches a server (a closed local port), put in a window of a given size. The root hosts
/// the downloaded product (``UKServerUIProductionHost``). `regular` forces the regular width class, as an iPad has; otherwise the rig is
/// a phone on every family (the compact width class, which a window in the iPad's scene would not get by itself, and a window inside
/// the scene, ``HostedPage/phoneSize``).
@MainActor
struct HostedShellRig {
    let session: AppSession
    let root: UKRootViewController
    let window: UIWindow
    let connection: HassConnection

    var product: UKServerUIProductionHost { root.children.compactMap { $0 as? UKServerUIProductionHost }.first! }

    static func make(size: CGSize? = nil, regular: Bool = false, inScene: Bool = false) throws -> HostedShellRig {
        let size = size ?? HostedPage.phoneSize
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "uk-hosted-shell-\(UUID().uuidString).json")))
        session.motion.markPlayed(.signInArrival)
        let server = HassServer(baseURL: URL(string: "http://127.0.0.1:9")!)
        try session.didSignIn(server: server, tokens: AuthTokens(accessToken: "test", expiresAt: .distantFuture, refreshToken: "test"))
        guard case let .signedIn(connection, _) = session.phase else { throw XCTSkip("no connection") }
        let root = UKRootViewController(session: session)
        root.traitOverrides.horizontalSizeClass = regular ? .regular : .compact
        let window: UIWindow
        if inScene {
            guard let sceneWindow = HostedScene.show(root, size: size) else { throw XCTSkip("the host app has no window scene") }
            window = sceneWindow
        } else {
            window = HostedPage.show(root, size: size)
        }
        return HostedShellRig(session: session, root: root, window: window, connection: connection)
    }

    func settle(_ seconds: TimeInterval = 0.4) {
        HostedPage.wait(seconds)
        root.view.layoutIfNeeded()
    }

    func tearDown() { window.isHidden = true }
}

@MainActor
final class UKHostedShellTests: XCTestCase {
    func testSignedOutRootShowsTheSignInAndNoTabs() {
        let session = AppSession(tokenStore: InMemoryTokenStore())
        let root = UKRootViewController(session: session)
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        XCTAssertTrue(root.children.contains { $0 is UKLoginViewController }, "signed out shows the sign-in")
        XCTAssertFalse(root.children.contains { $0 is UKServerUIProductionHost }, "no product while signed out")
    }

    func testSignedInRootHostsTheProductionHostAndNoCompiledTabs() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        XCTAssertEqual(rig.root.children.filter { $0 is UKServerUIProductionHost }.count, 1, "one downloaded product fills the window")
        XCTAssertFalse(rig.product.view.isHidden)
        XCTAssertFalse(rig.root.children.contains { $0 is UITabBarController }, "no compiled tab bar controller is built")
    }

    func testSigningOutRemovesTheProductAndShowsTheSignIn() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        rig.session.signOut()
        rig.settle(0.6)
        XCTAssertFalse(rig.root.children.contains { $0 is UKServerUIProductionHost }, "nothing of the last session is put back")
        XCTAssertTrue(rig.root.children.contains { $0 is UKLoginViewController })
    }

    func testTheRegularWidthRootStillHostsTheSameProduct() throws {
        let rig = try HostedShellRig.make(regular: true)
        defer { rig.tearDown() }
        rig.settle()
        XCTAssertEqual(rig.root.children.filter { $0 is UKServerUIProductionHost }.count, 1)
    }
}
