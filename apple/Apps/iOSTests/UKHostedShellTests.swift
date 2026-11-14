@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A signed-in shell on a connection that never reaches a server (a closed local port), put in a window of a given size.
/// `regular` forces the regular width class, as an iPad has, so the shell shows the flyout instead of the tab bar; otherwise the rig is
/// a phone on every family (the compact width class, which a window in the iPad's scene would not get by itself, and a window inside
/// the scene, ``HostedPage/phoneSize``).
@MainActor
struct HostedShellRig {
    let session: AppSession
    let root: UKRootViewController
    let window: UIWindow
    let connection: HassConnection

    var shell: UKShellViewController { root.children.compactMap { $0 as? UKShellViewController }.first! }
    var navigator: ShellNavigator { shell.navigator }

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
        XCTAssertFalse(root.children.contains { $0 is UKShellViewController }, "no tabs while signed out")
    }

    func testCompactShellShowsTheFiveTabsWithTheTabBar() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        let titles = rig.shell.sectionControllers.map { $0.tabBarItem.title }
        XCTAssertEqual(titles, AppSection.allCases.map(\.title), "one tab per section, in order")
        XCTAssertFalse(rig.shell.tabBar.isHidden, "compact width navigates with the tab bar")
        XCTAssertEqual(rig.navigator.selection, .home)
    }

    func testTappingATabSelectsItAndASecondTapPopsToTheRoot() async throws {
        let rig = try HostedShellRig.make(inScene: true)
        defer { rig.tearDown() }
        rig.settle()
        let shell = rig.shell
        let climate = shell.sectionControllers.first { $0.section == .climate }!
        XCTAssertFalse(shell.tabBarController(UITabBarController(), shouldSelect: climate), "the navigator, not the tab bar, selects")
        XCTAssertEqual(rig.navigator.selection, .climate)
        // A page is pushed and the second tap on the tab pops it.
        rig.navigator.append(.settings(.vacation), in: .settings)
        rig.navigator.selection = .settings
        let settings = shell.sectionControllers.first { $0.section == .settings }!
        await FeatureHost.settleAsync(until: { settings.viewControllers.count == 2 })
        XCTAssertEqual(settings.viewControllers.count, 2, "the route is on the section's stack")
        // The push animates; a pop asked for while it runs waits for it (`transitionCoordinator == nil`), so let it finish first.
        // The shell follows the navigator through an observation whose hop is a queued `Task`: only suspending lets it run.
        await FeatureHost.settleAsync(until: { settings.transitionCoordinator == nil })
        await FeatureHost.settleAsync(0.3)
        _ = shell.tabBarController(UITabBarController(), shouldSelect: settings)
        XCTAssertTrue(rig.navigator.isAtRoot(.settings), "the navigator popped to the root")
        await FeatureHost.settleAsync(until: { settings.viewControllers.count == 1 })
        XCTAssertEqual(settings.viewControllers.count, 1, "the second tap goes back to the root: coord \(String(describing: settings.transitionCoordinator)) stack \(settings.viewControllers) atRoot \(rig.navigator.isAtRoot(.settings)) sel \(rig.navigator.selection) window \(String(describing: settings.view.window)) selectedVC \(String(describing: shell.tabBar.selectedItem?.title))")
        _ = shell.tabBarController(UITabBarController(), shouldSelect: settings)
        rig.settle()
        XCTAssertEqual(rig.navigator.selection, .settings)
    }

    func testSwipingTheQuickLinksSheetDownTellsTheNavigatorItIsGone() throws {
        let rig = try HostedShellRig.make(inScene: true)
        defer { rig.tearDown() }
        rig.settle()
        let home = rig.shell.sectionControllers.first { $0.section == .home }!
        rig.navigator.openQuickLinks()
        rig.settle(0.8)
        let sheet = try XCTUnwrap(home.presentedViewController, "Quick Links opens as a sheet over Home")
        let presentation = try XCTUnwrap(sheet.presentationController)
        // The system calls this after an interactive dismissal; the sheet itself is already on its way out.
        presentation.delegate?.presentationControllerDidDismiss?(presentation)
        XCTAssertNil(rig.navigator.quickLinksSection, "the navigator no longer thinks the sheet is up")
        XCTAssertTrue(rig.navigator.isAtRoot(.home), "nothing was pushed")
    }

    func testChoresBadgeFollowsTheOverdueCountOnTheTabAndItsLabel() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        rig.navigator.overdueChores = 4
        rig.settle(0.2)
        let chores = rig.shell.sectionControllers.first { $0.section == .chores }!
        XCTAssertEqual(chores.tabBarItem.badgeValue, "4")
        XCTAssertEqual(chores.tabBarItem.accessibilityLabel, "Chores, 4 overdue")
    }

    func testPopRoutePushesAndABackSwipeTrimsTheNavigator() throws {
        let rig = try HostedShellRig.make(inScene: true)
        defer { rig.tearDown() }
        rig.settle()
        rig.navigator.open(.homePage("vacuums"))
        rig.settle(0.6)
        HostedPage.until(5) { rig.shell.sectionControllers.first { $0.section == .home }!.viewControllers.count == 2 }
        let home = rig.shell.sectionControllers.first { $0.section == .home }!
        XCTAssertEqual(home.viewControllers.count, 2, "the notification's page is pushed on Home")
        // A pop asked for while the push is still animating is not taken; wait the push out.
        HostedPage.until(10) { home.transitionCoordinator == nil && home.topViewController?.view.window != nil }
        home.popViewController(animated: false)
        HostedPage.until(5) { rig.navigator.isAtRoot(.home) }
        XCTAssertTrue(rig.navigator.isAtRoot(.home), "popping the page writes the new depth back to the navigator: routes \(rig.navigator.routes(in: .home)) stack \(home.viewControllers.count) \(home.viewControllers.map { String(describing: type(of: $0)) })")
    }

    func testQuickLinksAndAccountSheetsPresentOverTheSelectedSection() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        let home = rig.shell.sectionControllers.first { $0.section == .home }!
        rig.navigator.openQuickLinks()
        rig.settle(0.8)
        XCTAssertNotNil(home.presentedViewController, "Quick Links opens as a sheet over Home")
        rig.navigator.quickLinksSection = nil
        rig.settle(0.8)
        XCTAssertNil(home.presentedViewController, "closing it dismisses the sheet")
        rig.navigator.openAccount()
        rig.settle(0.8)
        XCTAssertNotNil(home.presentedViewController, "Profile opens Your Summary")
        rig.navigator.accountSection = nil
        rig.settle(0.8)
    }

    func testRegularWidthHidesTheTabBarAndOpensTheFlyout() throws {
        let rig = try HostedShellRig.make(size: CGSize(width: 1024, height: 768), regular: true)
        defer { rig.tearDown() }
        rig.settle()
        XCTAssertTrue(rig.shell.tabBar.isHidden || rig.root.view.window != nil)
        rig.navigator.openFlyout()
        rig.settle(0.6)
        let all = HostedPage.descendants(of: rig.shell.view)
        let rows = all.compactMap { $0 as? UKFlyoutRow }
        XCTAssertEqual(rows.map(\.section), AppSection.allCases, "one row per section")
        let current = rows.first { $0.section == .home }!
        XCTAssertTrue(current.accessibilityTraits.contains(.selected), "the current section is selected for VoiceOver")
        XCTAssertEqual(all.first { $0.accessibilityIdentifier == "nav.flyout.heading" }.flatMap { ($0 as? UILabel)?.text }, "Navigation")
        // Choosing a row selects the section and closes the flyout.
        rows.first { $0.section == .security }!.sendActions(for: .touchUpInside)
        XCTAssertEqual(rig.navigator.selection, .security)
        XCTAssertFalse(rig.navigator.isFlyoutOpen)
        rig.settle(0.6)
    }

    func testFlyoutClosesFromTheScrimTheEscapeAndTheCloseButton() throws {
        let rig = try HostedShellRig.make(size: CGSize(width: 1024, height: 768), regular: true)
        defer { rig.tearDown() }
        rig.settle()
        let flyout = HostedPage.descendants(of: rig.shell.view).compactMap { $0 as? UKNavigationFlyoutView }.first!
        rig.navigator.overdueChores = 3
        rig.navigator.openFlyout()
        rig.settle(0.5)
        XCTAssertNotNil(flyout.hitTest(CGPoint(x: 900, y: 400), with: nil), "while open the overlay takes touches")
        XCTAssertNotNil(flyout.keyCommands?.first, "Escape closes it")
        let chores = HostedPage.descendants(of: flyout).compactMap { $0 as? UKFlyoutRow }.first { $0.section == .chores }!
        XCTAssertEqual(chores.accessibilityLabel, "Chores, 3 overdue")
        let scrim = HostedPage.descendants(of: flyout).first { $0.accessibilityIdentifier == "nav.flyout.scrim" } as? UIButton
        scrim?.sendActions(for: .touchUpInside)
        XCTAssertFalse(rig.navigator.isFlyoutOpen, "the scrim closes it")
        rig.settle(0.5)
        HostedPage.until { flyout.hitTest(CGPoint(x: 900, y: 400), with: nil) == nil }
        XCTAssertNil(flyout.hitTest(CGPoint(x: 900, y: 400), with: nil), "closed, the overlay lets touches through")
        XCTAssertNil(flyout.keyCommands)
        rig.navigator.openFlyout()
        rig.settle(0.4)
        let panel = HostedPage.descendants(of: flyout).first { $0 is UKFlyoutPanel }!
        XCTAssertTrue(panel.accessibilityPerformEscape(), "the VoiceOver escape gesture closes it")
        XCTAssertFalse(rig.navigator.isFlyoutOpen)
        rig.settle(0.4)
    }

    func testFlyoutWithReduceMotionFadesAndAccessibilitySizesAddACloseButton() throws {
        let rig = try HostedShellRig.make(size: CGSize(width: 1024, height: 768), regular: true)
        defer { rig.tearDown() }
        rig.settle()
        rig.shell.view.overrideUserInterfaceStyle = .dark
        UKShellEnvironmentProbe.environment(of: rig.shell)?.reduceMotion = true
        let flyout = HostedPage.descendants(of: rig.shell.view).compactMap { $0 as? UKNavigationFlyoutView }.first!
        flyout.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        rig.navigator.openFlyout()
        rig.settle(0.5)
        let close = HostedPage.descendants(of: flyout).first { $0.accessibilityIdentifier == "nav.flyout.close" }
        XCTAssertNotNil(close?.superview, "at accessibility sizes the heading row carries a close button")
        (close as? UIButton)?.sendActions(for: .touchUpInside)
        XCTAssertFalse(rig.navigator.isFlyoutOpen)
        rig.settle(0.5)
        flyout.traitOverrides.preferredContentSizeCategory = .large
        rig.settle(0.2)
        XCTAssertNil(close?.superview, "back at normal sizes the close button goes")
    }

    func testEdgeSwipeOpensTheFlyoutAtTheRootOnly() throws {
        let rig = try HostedShellRig.make(size: CGSize(width: 1024, height: 768), regular: true)
        defer { rig.tearDown() }
        rig.settle()
        rig.navigator.edgeSwipeEnded(startX: 0, translation: CGSize(width: 200, height: 0))
        XCTAssertTrue(rig.navigator.isFlyoutOpen)
        rig.navigator.dismissFlyout()
        rig.settle(0.5)
    }

    func testOfflineShowsTheChipUnderTheHeaderAndTheProfileBadge() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        rig.connection.setOnline(false)
        rig.settle(0.8)
        let texts = HostedPage.labels(in: rig.shell.view)
        XCTAssertTrue(texts.contains("Offline. Showing last known values."), "the chip says so; saw \(texts.prefix(8))")
        let chip = HostedPage.descendants(of: rig.shell.view).first { $0.accessibilityIdentifier == "offline.chip" }
        XCTAssertEqual(chip?.accessibilityLabel, "Offline. Showing last known values.")
        rig.connection.setOnline(true)
        rig.settle(0.8)
        XCTAssertNil(HostedPage.descendants(of: rig.shell.view).first { $0.accessibilityIdentifier == "offline.chip" }, "the chip leaves when the network returns")
    }

    func testSavedRoutesComeBackAndSignOutClearsThem() throws {
        let rig = try HostedShellRig.make(inScene: true)
        defer { rig.tearDown() }
        rig.settle()
        rig.navigator.append(.settings(.performance), in: .settings)
        rig.shell.sceneLeftForeground()
        let info = rig.window.windowScene?.session.userInfo
        XCTAssertNotNil(info?["shellRoutes"], "leaving the foreground saves the stacks")
        rig.shell.clearStoredState()
        XCTAssertNil(rig.window.windowScene?.session.userInfo?["shellRoutes"])
        rig.shell.sceneBecameActive()
        rig.shell.sceneEnteredBackground()
    }

    func testSignOutRemovesTheTabsAndShowsTheSignIn() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        rig.session.signOut()
        rig.settle(0.8)
        XCTAssertFalse(rig.root.children.contains { $0 is UKShellViewController })
        XCTAssertTrue(rig.root.children.contains { $0 is UKLoginViewController })
    }
}

/// Reaches the environment the shell publishes, through a page it built (the shell keeps it private).
@MainActor
enum UKShellEnvironmentProbe {
    static func environment(of shell: UKShellViewController) -> UKShellEnvironment? {
        shell.sectionControllers.first?.pageContext.shell
    }
}
