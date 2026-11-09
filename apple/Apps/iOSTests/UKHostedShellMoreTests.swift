import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A pan recognizer whose state a test chooses (UIKit only lets the recognizer itself set it).
private final class FakeEdgePan: UIScreenEdgePanGestureRecognizer {
    var fakeState: UIGestureRecognizer.State = .possible
    var fakeTranslation = CGPoint.zero
    var fakeVelocity = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { fakeState }
        set {}
    }
    override func translation(in view: UIView?) -> CGPoint { fakeTranslation }
    override func velocity(in view: UIView?) -> CGPoint { fakeVelocity }
}

@MainActor
final class UKHostedShellMoreTests: DemoHouseTestCase {
    private func settle(_ seconds: TimeInterval = 0.3) { HostedPage.wait(seconds) }

    /// Waits until `scroll` and the bar above it are at rest: the offset and the top inset unchanged across a 0.2 s wait.
    private func settleScroll(_ scroll: UIScrollView) {
        var last = (scroll.contentOffset.y, scroll.adjustedContentInset.top)
        HostedPage.until(3) {
            HostedPage.layoutTracked()
            HostedPage.wait(0.2)
            let now = (scroll.contentOffset.y, scroll.adjustedContentInset.top)
            defer { last = now }
            return abs(now.0 - last.0) < 0.5 && abs(now.1 - last.1) < 0.5
        }
    }

    private func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    override func tearDown() {
        UKGlassEra.iOS18Override = nil
        UKGlassEra.override = nil
        UKMotion.reduceMotionOverride = nil
    }

    // MARK: Shell

    func testADebugNotificationSelectsATab() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        post("uk.debug.tab.chores")
        rig.settle(0.3)
        XCTAssertEqual(rig.navigator.selection, .chores)
        post("uk.debug.tab.home")
        rig.settle(0.3)
        XCTAssertEqual(rig.navigator.selection, .home)
    }

    func testANotificationsPageOpensWhileTheShellIsUpAndIsMarkedDone() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        rig.session.push.open(.section(.security))
        rig.settle(0.4)
        XCTAssertEqual(rig.navigator.selection, .security, "the requested page's section is shown")
        XCTAssertNil(rig.session.push.pendingRequest, "and the request is finished")
    }

    func testALeadingEdgeSwipeOpensTheFlyoutAtTheRootOnly() throws {
        let rig = try HostedShellRig.make(regular: true)
        defer { rig.tearDown() }
        rig.settle()
        rig.shell.edgeSwipeEnded(translation: CGPoint(x: 10, y: 0), edges: .left)
        XCTAssertFalse(rig.navigator.isFlyoutOpen, "too short a swipe")
        rig.shell.edgeSwipeEnded(translation: CGPoint(x: 160, y: 0), edges: .left)
        XCTAssertTrue(rig.navigator.isFlyoutOpen)
        rig.navigator.dismissFlyout()
        rig.shell.edgeSwipeEnded(translation: CGPoint(x: -160, y: 0), edges: .right)
        XCTAssertTrue(rig.navigator.isFlyoutOpen, "a trailing-edge swipe counts the other way in right to left")
    }

    func testTheSizeClassChangingSwitchesBetweenTabBarAndFlyoutLayouts() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        let environment = try XCTUnwrap(UKShellEnvironmentProbe.environment(of: rig.shell))
        XCTAssertEqual(environment.style, .tabBar)
        rig.root.traitOverrides.horizontalSizeClass = .regular
        rig.settle(0.5)
        XCTAssertEqual(environment.style, .flyout, "a width change lays the shell out again")
        UKGlassEra.iOS18Override = false
        rig.root.traitOverrides.horizontalSizeClass = .compact
        rig.settle(0.4)
        XCTAssertEqual(environment.style, .tabBar)
        rig.root.traitOverrides.horizontalSizeClass = .regular
        rig.settle(0.4)
        XCTAssertTrue(rig.shell.tabBarController?.tabBar.isHidden ?? rig.shell.children.compactMap { $0 as? UITabBarController }.first?.tabBar.isHidden ?? false,
                      "before iOS 18 the tab bar itself is hidden")
    }

    // MARK: Section navigation

    func testASecondTapScrollsAPlainPageToItsTop() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        let home = try XCTUnwrap(rig.shell.sectionControllers.first { $0.section == .home })
        let plain = UIViewController()
        plain.loadViewIfNeeded()
        // The page's own bounds, which the flexible size then follows: a fixed 393 by 852 frame in a page loaded at the iPad's width
        // shrank to no width when the page took the phone window's (found by nothing, so nothing scrolled; 2026-11-04).
        let scroll = UIScrollView(frame: plain.view.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.contentSize = CGSize(width: 393, height: 4000)
        plain.view.addSubview(scroll)
        // A page opened through the navigator (as the app does), so the first re-tap pops it.
        rig.navigator.open(.homePage("vacuums"))
        rig.settle(0.6)
        XCTAssertEqual(home.viewControllers.count, 2, "a page is open over the Home root")
        rig.navigator.reselect(.home)
        rig.settle(0.8)
        XCTAssertEqual(home.viewControllers.count, 1, "the first re-tap pops to the root")
        // The next re-tap scrolls the revealed root back to its top.
        // The fixture Home root has no data, so nothing on it scrolls (hosted-environment limit); the navigator's answer to the next
        // re-tap is what is checked here, and the scroll itself is the plain page below and MotionJourneyTests.testSelectedTabPopsThenScrollsToTop.
        XCTAssertEqual(rig.navigator.reselect(.home), .scrolledToTop, "at the root, the next re-tap scrolls instead of popping")
        rig.settle(0.3)
        // A section whose top is a plain page with a scroll view, at its root.
        let root = home.viewControllers[0]
        home.setViewControllers([plain], animated: false)
        rig.settle(0.3)
        scroll.setContentOffset(CGPoint(x: 0, y: 900), animated: false)
        // Let the bar collapse its large title first, as it has long done when a person taps: a tap in the same turn raced it, and the
        // collapse's inset change stopped the scroll at 952 (the iPad, first run of the class, 2026-11-04).
        settleScroll(scroll)
        rig.navigator.reselect(.home)
        // The scroll is animated and starts on the next turn of the run loop; wait for it rather than for a fixed time (the iPad, under
        // a full run's load, was still at the collapsed title's 952 after 0.8 s).
        XCTAssertTrue(HostedPage.until(3) { scroll.contentOffset.y < 900 }, "the second tap scrolls it back up (at \(scroll.contentOffset.y); "
                      + "top \(home.topViewController === plain), in a window \(scroll.window != nil), found \(UKScrollToTop.mainScrollView(in: plain.view) === scroll), "
                      + "requests \(rig.navigator.scrollToTopRequests[.home] ?? 0), inset \(scroll.adjustedContentInset.top), size \(scroll.bounds.size))")
        home.setViewControllers([root], animated: false)
    }

    func testAPageQuickLinksChoseIsPushedOnceTheSheetHasGone() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        let home = try XCTUnwrap(rig.shell.sectionControllers.first { $0.section == .home })
        rig.navigator.openQuickLinks()
        rig.settle(0.8)
        let sheet = try XCTUnwrap(home.presentedViewController)
        let tiles = HostedPage.descendants(of: sheet.view).filter { $0.isAccessibilityElement && ($0.accessibilityLabel ?? "").localizedCaseInsensitiveContains("vacuum") }
        let tile = try XCTUnwrap(tiles.first, "a Vacuums tile: \(HostedPage.labels(in: sheet.view))")
        (tile as? UIControl)?.sendActions(for: .touchUpInside)
        if !(tile is UIControl) {
            var up: UIView? = tile
            var cell: UICollectionViewCell?
            var collection: UICollectionView?
            while let view = up {
                if cell == nil, let found = view as? UICollectionViewCell { cell = found }
                if let found = view as? UICollectionView { collection = found; break }
                up = view.superview
            }
            if let cell, let collection, let path = collection.indexPath(for: cell) { collection.delegate?.collectionView?(collection, didSelectItemAt: path) }
        }
        rig.settle(2.5)
        XCTAssertNil(home.presentedViewController, "the sheet is gone")
        XCTAssertEqual(home.viewControllers.count, 2, "and the chosen page is pushed on Home")
        XCTAssertTrue(home.view.isUserInteractionEnabled, "touches come back once it has arrived")
    }

    func testAnAnimatedPopOfARoutedPageIsMeasuredAndSettles() throws {
        let rig = try HostedShellRig.make(inScene: true)
        defer { rig.tearDown() }
        rig.settle()
        let home = try XCTUnwrap(rig.shell.sectionControllers.first { $0.section == .home })
        home.isSettled = true
        rig.navigator.open(.homePage("vacuums"))
        rig.settle(1)
        XCTAssertEqual(home.viewControllers.count, 2)
        home.popViewController(animated: true)
        rig.settle(1)
        XCTAssertEqual(home.viewControllers.count, 1)
        XCTAssertTrue(rig.navigator.isAtRoot(.home))
    }

    // MARK: Stack motion

    func testTheStackSwipeFollowsTheFingerThroughEveryPhaseOfTheGesture() throws {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.isNavigationBarHidden = true
        // A window in the app's scene: one outside it never renders, so a transition's animator does not run.
        guard let window = HostedScene.show(navigation, size: CGSize(width: 393, height: 852)) else { throw XCTSkip("the host app has no window scene") }
        defer { window.isHidden = true }
        let motion = UKStackMotion(navigation: navigation)
        navigation.delegate = motion
        let next = UIViewController()
        navigation.pushViewController(next, animated: false)
        settle(0.2)
        let pan = FakeEdgePan()
        navigation.view.addGestureRecognizer(pan)
        let selector = NSSelectorFromString("panned:")
        for (state, x, vx) in [(UIGestureRecognizer.State.began, CGFloat(0), CGFloat(0)), (.changed, 80, 100), (.ended, 80, 100)] {
            pan.fakeState = state
            pan.fakeTranslation = CGPoint(x: x, y: 0)
            pan.fakeVelocity = CGPoint(x: vx, y: 0)
            _ = motion.perform(selector, with: pan)
            settle(0.05)  // a finger takes frames to move: the transition starts a turn after the pop is asked for
        }
        settle(0.6)
        XCTAssertEqual(navigation.viewControllers.count, 2, "a short, slow swipe springs back (coordinator \(String(describing: navigation.transitionCoordinator)), top \(String(describing: navigation.topViewController)), interaction \(String(describing: motion.interaction)))")
        navigation.setViewControllers([root, UIViewController()], animated: false)
        settle(0.2)
        navigation.view.addGestureRecognizer(pan)
        for (state, x, vx) in [(UIGestureRecognizer.State.began, CGFloat(0), CGFloat(0)), (.changed, 300, 900), (.ended, 300, 900)] {
            pan.fakeState = state
            pan.fakeTranslation = CGPoint(x: x, y: 0)
            pan.fakeVelocity = CGPoint(x: vx, y: 0)
            _ = motion.perform(selector, with: pan)
            settle(0.05)  // a finger takes frames to move: the transition starts a turn after the pop is asked for
        }
        settle(0.8)
        XCTAssertEqual(navigation.viewControllers.count, 1, "past halfway, or fast, it pops")
        navigation.pushViewController(UIViewController(), animated: false)
        settle(0.2)
        for state in [UIGestureRecognizer.State.began, .cancelled] {
            pan.fakeState = state
            _ = motion.perform(selector, with: pan)
            settle(0.05)
        }
        pan.fakeState = .possible
        _ = motion.perform(selector, with: pan)
        settle(0.6)
        XCTAssertEqual(navigation.viewControllers.count, 2, "a swipe that is cancelled leaves the page where it was")
    }

    func testAScrollViewsPanWaitsForTheEdgePanToFail() {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = HostedPage.show(navigation)
        defer { window.isHidden = true }
        let motion = UKStackMotion(navigation: navigation)
        let scroll = UIScrollView(frame: navigation.view.bounds)
        navigation.view.addSubview(scroll)
        XCTAssertTrue(motion.gestureRecognizer(motion.edgePanRecognizer, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
        XCTAssertFalse(motion.gestureRecognizer(motion.edgePanRecognizer, shouldBeRequiredToFailBy: UITapGestureRecognizer()))
        let outside = UIScrollView()
        XCTAssertFalse(motion.gestureRecognizer(motion.edgePanRecognizer, shouldBeRequiredToFailBy: outside.panGestureRecognizer))
    }

    // MARK: Columns

    private func columns() -> (UKColumnsViewController, UIWindow) {
        let root = UIViewController()
        let columns = UKColumnsViewController(rootController: root, shell: nil) {
            UKPanePlaceholderViewController(symbol: "gearshape", text: "Select a setting", identifier: "pane.empty")
        }
        let window = HostedPage.show(columns, size: CGSize(width: 1024, height: 768))
        columns.setWide(true)
        return (columns, window)
    }

    func testTheEdgePanScrubsTheOpenPageBackAndLettingGoDecides() {
        let (columns, window) = columns()
        defer { window.isHidden = true }
        let page = UIViewController()
        columns.open(page, tag: "a", animated: false)
        settle(0.3)
        columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        columns.handleEdgePan(state: .changed, translation: 100, velocity: 50)
        columns.handleEdgePan(state: .ended, translation: 100, velocity: 50)
        settle(0.8)
        XCTAssertEqual(columns.entries.count, 1, "a short drag returns the page")
        columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        columns.handleEdgePan(state: .changed, translation: 700, velocity: 900)
        columns.handleEdgePan(state: .ended, translation: 700, velocity: 900)
        settle(0.8)
        XCTAssertEqual(columns.entries.count, 0, "past halfway the page goes")
        columns.handleEdgePan(state: .ended, translation: 0, velocity: 0)
        columns.handleEdgePan(state: .possible, translation: 0, velocity: 0)
        let guarded = HostedGuardedPage()
        guarded.columnPopDecision = .block
        columns.open(guarded, tag: "b", animated: false)
        settle(0.3)
        columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        XCTAssertEqual(columns.entries.count, 1, "a page that holds itself open is not dragged away")
    }

    func testAHostedPageShowingAnotherReplacesWhatIsToItsRight() {
        let (columns, window) = columns()
        defer { window.isHidden = true }
        let first = UIViewController(), second = UIViewController()
        columns.open(first, tag: "a", animated: false)
        settle(0.3)
        XCTAssertEqual(columns.depth(of: first), 1)
        XCTAssertEqual(columns.depth(of: UIViewController()), 0, "a stranger is in no column")
        XCTAssertEqual(columns.depth(of: nil), 0)
        columns.show(second, sender: first)
        settle(0.4)
        XCTAssertEqual(columns.entries.last?.controller, second)
        columns.showDetailViewController(first, sender: nil)
        settle(0.4)
    }

    func testDebugStepsPressBackAndCloseAtTheirSeconds() {
        setenv("FENTON_DEBUG_COLUMN_STEPS", "0.2:back,0.5:close", 1)
        defer { unsetenv("FENTON_DEBUG_COLUMN_STEPS") }
        let (columns, window) = columns()
        defer { window.isHidden = true }
        columns.open(UIViewController(), tag: "a", animated: false)
        columns.open(UIViewController(), tag: "b", animated: false)
        columns.viewDidAppear(false)
        settle(1.5)
        XCTAssertEqual(columns.entries.count, 0)
    }

    func testDebugScrollMovesTheOpenPageOnce() {
        setenv("FENTON_DEBUG_COLUMN_SCROLL", "50", 1)
        defer { unsetenv("FENTON_DEBUG_COLUMN_SCROLL") }
        let (columns, window) = columns()
        defer { window.isHidden = true }
        let page = HostedScrollPage(context: UKGalleryChrome.context(), title: "Tall")
        columns.open(page, tag: "a", animated: false)
        settle(0.3)
        columns.viewDidAppear(false)
        columns.viewDidAppear(false)
        XCTAssertEqual(columns.entries.count, 1)
    }

    // MARK: Page base

    private func page() -> (HostedScrollPage, UINavigationController, UIWindow) {
        var context = UKGalleryChrome.context()
        context.navigator = ShellNavigator()
        context.section = .home
        context.shell?.headerEdgeCap = 96
        let page = HostedScrollPage(context: context, title: "Climate")
        page.isSectionRoot = true
        let navigation = UINavigationController(rootViewController: page)
        UKNavigationBarStyle.apply(to: navigation.navigationBar, large: true)
        return (page, navigation, HostedPage.show(navigation))
    }

    func testTheRailsSideInsetsKeepTheContentAndTheChildrenClearOfIt() {
        let (page, _, window) = page()
        defer { window.isHidden = true }
        let child = UIViewController()
        page.addChild(child)
        page.contentView.addSubview(child.view)
        child.didMove(toParent: page)
        page.sideInsetsOverride = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 60)
        settle(0.3)
        XCTAssertEqual(page.contentView.frame.maxX, page.view.bounds.maxX - 60, accuracy: 0.5, "the content stops at the rail")
        XCTAssertEqual(page.additionalSafeAreaInsets.right, 60 - page.view.safeAreaInsets.right + page.additionalSafeAreaInsets.right, accuracy: 60)
        XCTAssertEqual(child.additionalSafeAreaInsets.right, -60, "a pane inside is not inset by the rail a second time")
        page.sideInsetsOverride = nil
        settle(0.3)
        // Without the stand-in the page measures the window's own side inset: none on a phone or an iPad, the system's vertical bar
        // on the folded Duo.
        XCTAssertEqual(page.contentView.frame.maxX, page.view.bounds.maxX - window.safeAreaInsets.right, accuracy: 0.5,
                       "the rail leaves, the content takes the width the window leaves it")
        XCTAssertEqual(child.additionalSafeAreaInsets.right, -window.safeAreaInsets.right, accuracy: 0.5,
                       "a pane inside is not inset a second time by what the window's side inset leaves (none on a phone)")
    }

    func testDebugProbesDriveTheSectionRootsScrollAndSheets() {
        setenv("FENTON_DEBUG_SCROLL", "0.1:300,0.3:-1", 1)
        setenv("FENTON_DEBUG_TITLE", "1", 1)
        defer { unsetenv("FENTON_DEBUG_SCROLL"); unsetenv("FENTON_DEBUG_TITLE") }
        let (page, _, window) = page()
        defer { window.isHidden = true }
        page.viewDidAppear(false)
        settle(0.6)
        // The timed steps end with an animated scroll to the top; posting while it still moves let the page's keep-at-top rule
        // (`followTopInset`) take the new scroll back to the top (the folded Duo, first run of the class, 2026-11-04).
        settleScroll(page.scroll)
        post("uk.debug.scrollDown")
        // The scroll is animated; wait for it to start moving rather than for a fixed time (the folded Duo was still at the top after
        // 0.8 s on a first run, 2026-11-04).
        XCTAssertTrue(HostedPage.until(3) { page.scroll.contentOffset.y > -page.scroll.adjustedContentInset.top + 1 }, "the page was scrolled down")
        settle(0.8)
        post("uk.debug.scrollTop")
        settle(0.8)
        XCTAssertEqual(page.scroll.contentOffset.y, -page.scroll.adjustedContentInset.top - 52, accuracy: 60)
        post("uk.debug.quickLinks")
        settle(0.2)
        XCTAssertEqual(page.opened, ["quick"])
        page.viewDidAppear(false)
    }

    func testTheRailCrowdingProbeAddsItemsToTheShellGroup() {
        setenv("FENTON_DEBUG_RAIL_EXTRA", "2", 1)
        defer { unsetenv("FENTON_DEBUG_RAIL_EXTRA") }
        let (page, navigation, window) = page()
        defer { window.isHidden = true }
        var context = page.context
        context.shell?.inVerticalBar = true
        let owner = HostedColumnOwner()
        _ = owner
        page.setColumnBar(UKColumnBar(items: [], kind: .back, isEnabled: true, perform: {}))
        settle(0.3)
        let titles = (page.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)).compactMap(\.title)
        XCTAssertTrue(titles.contains("Extra 1") && titles.contains("Extra 2"), "\(titles)")
        _ = navigation
    }

    func testThePageHostMirrorsAPlainScreenAndASheetPagePresentsItsOwnSheets() {
        let (page, _, window) = page()
        defer { window.isHidden = true }
        let sheet = UIViewController()
        page.presentSheet(sheet)
        settle(0.8)
        XCTAssertNotNil(page.presentedViewController, "the page presents a sheet over itself")
        page.dismiss(animated: false)
    }
}
