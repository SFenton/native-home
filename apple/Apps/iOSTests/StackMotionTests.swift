import UIKit
import XCTest
@testable import HassUI

/// Push and pop on the single-page layouts (`.agents/design/single-page-motion.md`): the animator, the interactive swipe back and the one
/// wallpaper, on a real navigation controller in a real window; and the columns' Reduce Motion path (L1).
@MainActor
final class StackMotionTests: XCTestCase {
    /// The window width the rig uses: an iPhone's by default; the iPad-portrait cases below set ``iPadPortrait`` first (the iPad
    /// journeys skip, so the animator, swipe and gesture rules are proved at that width here).
    private var width: CGFloat = 390
    private static let iPadPortrait = CGSize(width: 820, height: 1180)
    private var height: CGFloat { width == Self.iPadPortrait.width ? Self.iPadPortrait.height : 844 }

    private final class Page: UIViewController {
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
        }
    }

    private struct Rig {
        let window: UIWindow
        let nav: UINavigationController
        let motion: UKStackMotion
        let root: Page
    }

    override func tearDown() {
        UKMotion.reduceMotionOverride = nil
        super.tearDown()
    }

    private func makeWindow(_ size: CGSize? = nil) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: size ?? CGSize(width: width, height: height))
        return window
    }

    private func makeRig(reduceMotion: Bool = false) -> Rig {
        let root = Page()
        let nav = UINavigationController(rootViewController: root)
        nav.isNavigationBarHidden = true
        let window = makeWindow()
        window.rootViewController = nav
        window.makeKeyAndVisible()
        let motion = UKStackMotion(navigation: nav)
        motion.reduceMotion = { reduceMotion }
        nav.delegate = motion
        run(0.05)
        return Rig(window: window, nav: nav, motion: motion, root: root)
    }

    private func run(_ seconds: TimeInterval) {
        HostedPage.wait(seconds)
    }

    /// Runs the main loop until the navigation controller has no transition in flight.
    private func settle(_ nav: UINavigationController, timeout: TimeInterval = 3) {
        let end = Date().addingTimeInterval(timeout)
        run(0.02)
        while nav.transitionCoordinator != nil, Date() < end { run(0.02) }
        run(0.05)
    }

    private func x(_ view: UIView) -> CGFloat { view.layer.presentation()?.affineTransform().tx ?? 0 }
    private func opacity(_ view: UIView) -> Float { view.layer.presentation()?.opacity ?? view.layer.opacity }

    // MARK: The animator

    func testPushMovesBothPagesAFullWidthWithNothingElse() {
        let rig = makeRig()
        let next = Page()
        rig.nav.pushViewController(next, animated: true)
        run(0.1)
        let incoming = x(next.view), outgoing = x(rig.root.view)
        XCTAssertGreaterThan(incoming, 0)
        XCTAssertLessThan(incoming, width, "The new page should be on its way in")
        XCTAssertLessThan(outgoing, 0, "The old page should be on its way out by the leading edge")
        XCTAssertGreaterThan(outgoing, -width)
        // A full width each, in lockstep: the system's 30% parallax is gone.
        XCTAssertEqual(incoming - width, outgoing, accuracy: 8)
        XCTAssertEqual(rig.root.view.alpha, 1, "No fade")
        XCTAssertEqual(rig.root.view.layer.shadowOpacity, 0, "No shadow")
        XCTAssertEqual(next.view.layer.shadowOpacity, 0, "No shadow")
        settle(rig.nav)
        XCTAssertTrue(rig.nav.topViewController === next)
        XCTAssertEqual(next.view.transform, .identity)
        XCTAssertEqual(rig.root.view.transform, .identity)
        XCTAssertNil(rig.root.view.window, "The old page leaves the window when it is out of it")
        XCTAssertNotNil(next.view.window)
    }

    func testPopReversesIt() {
        let rig = makeRig()
        let next = Page()
        rig.nav.pushViewController(next, animated: false)
        run(0.05)
        rig.nav.popViewController(animated: true)
        run(0.1)
        XCTAssertGreaterThan(x(next.view), 0, "The popped page goes out by the trailing edge")
        XCTAssertLessThan(x(rig.root.view), 0, "The page below comes in from the leading edge")
        XCTAssertGreaterThan(x(rig.root.view), -width)
        settle(rig.nav)
        XCTAssertTrue(rig.nav.topViewController === rig.root)
        XCTAssertEqual(rig.root.view.transform, .identity)
        XCTAssertNil(next.view.window)
    }

    func testReduceMotionCrossFadesInPlace() {
        let rig = makeRig(reduceMotion: true)
        let next = Page()
        rig.nav.pushViewController(next, animated: true)
        run(0.08)
        XCTAssertEqual(x(next.view), 0, accuracy: 0.5, "No slide under Reduce Motion")
        XCTAssertEqual(x(rig.root.view), 0, accuracy: 0.5)
        let fadingIn = opacity(next.view), fadingOut = opacity(rig.root.view)
        XCTAssertGreaterThan(fadingIn, 0)
        XCTAssertLessThan(fadingIn, 1, "The new page fades in")
        XCTAssertLessThan(fadingOut, 1, "The old page fades out")
        settle(rig.nav)
        XCTAssertEqual(next.view.alpha, 1)
        XCTAssertEqual(rig.root.view.alpha, 1, "The old page is left at full opacity for its next appearance")
        XCTAssertTrue(rig.nav.topViewController === next)
    }

    func testTransitionDurationsAreTheTokens() {
        XCTAssertEqual(UKStackTransition(isPush: true, reduceMotion: false).transitionDuration(using: nil), UKMotion.Token.standard.duration)
        XCTAssertEqual(UKStackTransition(isPush: false, reduceMotion: true).transitionDuration(using: nil), UKMotion.Token.quick.duration)
        XCTAssertEqual(UKMotion.Token.quick.duration, 0.2, accuracy: 0.001)
    }

    func testNoAnimatorWhileTheColumnsHoldTheRoutes() {
        let rig = makeRig()
        var enabled = true
        let motion = UKStackMotion(navigation: rig.nav) { enabled }
        let next = Page()
        XCTAssertNotNil(motion.navigationController(rig.nav, animationControllerFor: .push, from: rig.root, to: next))
        enabled = false
        XCTAssertNil(motion.navigationController(rig.nav, animationControllerFor: .push, from: rig.root, to: next))
        XCTAssertNil(motion.navigationController(rig.nav, animationControllerFor: .none, from: rig.root, to: next))
        enabled = true
        XCTAssertNil(motion.navigationController(rig.nav, animationControllerFor: .none, from: rig.root, to: next))
    }

    // MARK: The swipe

    func testLetGoThresholds() {
        XCTAssertFalse(UKStackMotion.completes(progress: 0.5, velocity: 0), "Exactly half does not complete")
        XCTAssertTrue(UKStackMotion.completes(progress: 0.51, velocity: 0))
        XCTAssertFalse(UKStackMotion.completes(progress: 0.2, velocity: 600), "Exactly 600 pt/s is not a flick")
        XCTAssertTrue(UKStackMotion.completes(progress: 0.2, velocity: 601))
        XCTAssertFalse(UKStackMotion.completes(progress: 0.4, velocity: -900), "Back toward the edge cancels")
    }

    func testTheEdgePanReplacesTheSystemGestures() {
        let rig = makeRig()
        let next = Page()
        rig.nav.pushViewController(next, animated: false)
        settle(rig.nav)
        XCTAssertEqual(rig.nav.interactivePopGestureRecognizer?.isEnabled, false)
        XCTAssertTrue(rig.nav.view.gestureRecognizers?.contains(rig.motion.edgePanRecognizer) == true)
        XCTAssertEqual(rig.motion.edgePanRecognizer.edges, .left)
        XCTAssertTrue(rig.motion.gestureRecognizerShouldBegin(rig.motion.edgePanRecognizer), "A pushed page can be swiped back")
        rig.nav.popViewController(animated: false)
        XCTAssertFalse(rig.motion.gestureRecognizerShouldBegin(rig.motion.edgePanRecognizer), "The root's edge belongs to the flyout")
    }

    func testAHiddenBackButtonKeepsTheSwipeOff() {
        let rig = makeRig()
        let next = Page()
        next.navigationItem.hidesBackButton = true
        rig.nav.pushViewController(next, animated: false)
        XCTAssertFalse(rig.motion.gestureRecognizerShouldBegin(rig.motion.edgePanRecognizer))
    }

    func testSwipeFollowsTheFingerAndCompletesPastHalf() {
        let rig = makeRig()
        let next = Page()
        rig.nav.pushViewController(next, animated: false)
        settle(rig.nav)
        rig.motion.beginSwipe()
        run(0.05)
        rig.motion.updateSwipe(progress: 0.4)
        run(0.05)
        XCTAssertEqual(x(next.view), 0.4 * width, accuracy: 24, "The popped page follows the finger")
        XCTAssertEqual(x(rig.root.view), -0.6 * width, accuracy: 24, "The page below is adjacent to it")
        rig.motion.updateSwipe(progress: 0.7)
        run(0.05)
        XCTAssertEqual(x(next.view), 0.7 * width, accuracy: 24)
        rig.motion.endSwipe(progress: 0.7, velocity: 0)
        settle(rig.nav)
        XCTAssertEqual(rig.nav.viewControllers.count, 1, "Let go past half: the pop completes")
        XCTAssertEqual(rig.root.view.transform, .identity)
        XCTAssertNil(rig.motion.interaction)
    }

    func testSwipeLetGoEarlyReverses() {
        let rig = makeRig()
        let next = Page()
        rig.nav.pushViewController(next, animated: false)
        settle(rig.nav)
        rig.motion.beginSwipe()
        run(0.05)
        rig.motion.updateSwipe(progress: 0.3)
        run(0.05)
        rig.motion.endSwipe(progress: 0.3, velocity: 100)
        settle(rig.nav)
        XCTAssertEqual(rig.nav.viewControllers.count, 2, "Let go early: the page stays")
        XCTAssertTrue(rig.nav.topViewController === next)
        XCTAssertEqual(next.view.transform, .identity)
        XCTAssertEqual(next.view.alpha, 1)
        XCTAssertNotNil(next.view.window)
        XCTAssertNil(rig.root.view.window, "The page below is taken out again")
        // And a Back after the cancelled swipe still pops.
        rig.nav.popViewController(animated: true)
        settle(rig.nav)
        XCTAssertEqual(rig.nav.viewControllers.count, 1)
    }

    func testAFlickCompletesFromAShortDrag() {
        let rig = makeRig()
        rig.nav.pushViewController(Page(), animated: false)
        settle(rig.nav)
        rig.motion.beginSwipe()
        run(0.05)
        rig.motion.updateSwipe(progress: 0.15)
        rig.motion.endSwipe(progress: 0.15, velocity: 900)
        settle(rig.nav)
        XCTAssertEqual(rig.nav.viewControllers.count, 1)
    }

    func testACancelledGestureReverses() {
        let rig = makeRig()
        rig.nav.pushViewController(Page(), animated: false)
        settle(rig.nav)
        rig.motion.beginSwipe()
        run(0.05)
        rig.motion.updateSwipe(progress: 0.9)
        rig.motion.endSwipe(progress: 0.9, velocity: 0, cancelled: true)
        settle(rig.nav)
        XCTAssertEqual(rig.nav.viewControllers.count, 2, "A cancelled gesture never pops, however far it went")
    }


    // MARK: iPad portrait width

    func testPushAtIPadPortraitWidth() { width = Self.iPadPortrait.width; testPushMovesBothPagesAFullWidthWithNothingElse() }
    func testPopAtIPadPortraitWidth() { width = Self.iPadPortrait.width; testPopReversesIt() }
    func testReduceMotionAtIPadPortraitWidth() { width = Self.iPadPortrait.width; testReduceMotionCrossFadesInPlace() }
    func testSwipeCompletesAtIPadPortraitWidth() { width = Self.iPadPortrait.width; testSwipeFollowsTheFingerAndCompletesPastHalf() }
    func testSwipeReversesAtIPadPortraitWidth() { width = Self.iPadPortrait.width; testSwipeLetGoEarlyReverses() }
    func testEdgePanAtIPadPortraitWidth() { width = Self.iPadPortrait.width; testTheEdgePanReplacesTheSystemGestures() }
    func testScrolledPageStaysPutAtIPadPortraitWidth() { width = Self.iPadPortrait.width; testPopGestureDoesNotScrollThePage() }
    func testVoiceOverAtIPadPortraitWidth() { width = Self.iPadPortrait.width; testVoiceOverIsToldTheScreenChangedAfterPushAndPop() }

    // MARK: A column host deeper in the stack

    /// A page that hosts columns, as the Food hub does.
    private final class ColumnHost: UIViewController, UKColumnsHosting {
        let columns = UKColumnsViewController(rootView: UIView(), shell: nil, placeholder: { Page() })
        func syncColumnRoutes(_ routes: [ShellRoute], animated: Bool) {}
        override func loadView() {
            view = UIView()
            addChild(columns)
            columns.view.frame = view.bounds
            columns.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(columns.view)
            columns.didMove(toParent: self)
        }
    }

    /// One leading-edge swipe does one thing: with a column open on a column host that is not the stack's root, the columns' pan takes
    /// it and the stack pan does not begin; with the columns at their root column, the stack pops the host.
    func testOneSwipeClosesTheColumnThenTheNextPopsTheHost() {
        let rig = makeRig()
        let host = ColumnHost()
        rig.nav.pushViewController(host, animated: false)
        settle(rig.nav)
        host.columns.setWide(true)
        host.columns.view.layoutIfNeeded()
        host.columns.open(Page(), tag: 1, animated: false)
        run(0.1)
        let edge = rig.motion.edgePanRecognizer
        XCTAssertTrue(host.columns.takesEdgePan)
        XCTAssertFalse(rig.motion.gestureRecognizerShouldBegin(edge), "A column is open: the columns' pan takes the swipe")
        // The columns' swipe closes the column (what its handler does at the end of a swipe).
        host.columns.setDetail(nil, animated: false)
        run(0.1)
        XCTAssertTrue(host.columns.entries.isEmpty)
        XCTAssertFalse(host.columns.takesEdgePan)
        XCTAssertEqual(rig.nav.viewControllers.count, 2, "The first swipe closed the column only")
        XCTAssertTrue(rig.motion.gestureRecognizerShouldBegin(edge), "At the root column the stack pan may begin")
        rig.motion.beginSwipe()
        run(0.05)
        rig.motion.endSwipe(progress: 0.8, velocity: 0)
        settle(rig.nav)
        XCTAssertEqual(rig.nav.viewControllers.count, 1, "The second swipe popped the host")
    }

    // MARK: The swipe against scrolling

    private final class ScrollPage: UIViewController {
        let scroll = UIScrollView()
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            scroll.frame = view.bounds
            scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scroll.contentSize = CGSize(width: 10, height: 4000)
            view.addSubview(scroll)
        }
    }

    /// A pop from the edge does not scroll the page under the finger: the page's scroll pan may not run alongside the edge pan and
    /// waits for it to fail, and the offset does not move while the swipe scrubs.
    func testPopGestureDoesNotScrollThePage() {
        let rig = makeRig()
        let page = ScrollPage()
        rig.nav.pushViewController(page, animated: false)
        settle(rig.nav)
        page.scroll.contentOffset = CGPoint(x: 0, y: 600)
        let edge = rig.motion.edgePanRecognizer
        let scrollPan = page.scroll.panGestureRecognizer
        XCTAssertFalse(rig.motion.gestureRecognizer(edge, shouldRecognizeSimultaneouslyWith: scrollPan), "The scroll pan must not run alongside the pop")
        XCTAssertTrue(rig.motion.gestureRecognizer(edge, shouldBeRequiredToFailBy: scrollPan), "The scroll pan waits for the edge pan to fail")
        let flyoutPan = UIScreenEdgePanGestureRecognizer()
        UIView().addGestureRecognizer(flyoutPan)
        XCTAssertTrue(rig.motion.gestureRecognizer(edge, shouldRecognizeSimultaneouslyWith: flyoutPan), "The flyout's edge pan (outside the stack) still may")
        let columnsPan = UIScreenEdgePanGestureRecognizer()
        page.view.addGestureRecognizer(columnsPan)
        XCTAssertFalse(rig.motion.gestureRecognizer(edge, shouldRecognizeSimultaneouslyWith: columnsPan), "A column host's own edge pan, inside the stack, does not")
        XCTAssertFalse(rig.motion.gestureRecognizer(edge, shouldBeRequiredToFailBy: UIPanGestureRecognizer()), "Only scroll views' pans wait")
        let outside = UIScrollView()
        XCTAssertFalse(rig.motion.gestureRecognizer(edge, shouldBeRequiredToFailBy: outside.panGestureRecognizer), "A scroll view outside the stack is not held")
        rig.motion.beginSwipe()
        run(0.05)
        rig.motion.updateSwipe(progress: 0.4)
        run(0.05)
        XCTAssertEqual(page.scroll.contentOffset.y, 600, "The page did not scroll while the swipe scrubbed")
        rig.motion.endSwipe(progress: 0.2, velocity: 0)
        settle(rig.nav)
        XCTAssertEqual(page.scroll.contentOffset.y, 600, "Nor when the swipe was let go and reversed")
    }

    // MARK: VoiceOver

    /// After a push and after a pop the screen is announced as changed, so focus lands on the arriving page's first element.
    func testVoiceOverIsToldTheScreenChangedAfterPushAndPop() {
        var posted: [String] = []
        let rig = makeRig()
        rig.motion.announceScreenChange = { posted.append("screenChanged") }
        rig.nav.pushViewController(Page(), animated: true)
        settle(rig.nav)
        XCTAssertEqual(posted, ["screenChanged"], "A push tells VoiceOver the screen changed")
        rig.nav.popViewController(animated: true)
        settle(rig.nav)
        XCTAssertEqual(posted, ["screenChanged", "screenChanged"], "So does a pop")
        let before = posted.count
        rig.nav.pushViewController(Page(), animated: false)
        settle(rig.nav)
        XCTAssertEqual(posted.count, before, "A cut (not animated) is the system's to announce")
    }

    // MARK: One wallpaper

    #if DEBUG
    private func backdrops(in view: UIView) -> Int {
        (view is UKBackdropView ? 1 : 0) + view.subviews.reduce(0) { $0 + backdrops(in: $1) }
    }

    /// The window holds exactly one wallpaper view, at rest and in the middle of a push and of a pop; pages hold none.
    func testExactlyOneBackdropInTheWindowAtRestAndMidPush() throws {
        let context = UKGalleryChrome.context()
        let first = UKPageViewController(context: context, title: "First")
        let host = UKGalleryChrome.wrap(first, context: context)
        let window = makeWindow()
        window.rootViewController = host
        window.makeKeyAndVisible()
        run(0.2)
        let nav = try XCTUnwrap(host.children.compactMap { $0 as? UINavigationController }.first)
        XCTAssertEqual(backdrops(in: window), 1, "At rest")
        first.loadViewIfNeeded()
        XCTAssertEqual(backdrops(in: first.view), 0, "A page creates no wallpaper of its own")

        let second = UKPageViewController(context: context, title: "Second")
        nav.pushViewController(second, animated: true)
        run(0.1)
        XCTAssertNotNil(nav.transitionCoordinator, "The push should still be moving")
        XCTAssertEqual(backdrops(in: window), 1, "Mid-push")
        XCTAssertEqual(backdrops(in: second.view), 0)
        settle(nav)
        XCTAssertEqual(backdrops(in: window), 1, "After the push")

        nav.popViewController(animated: true)
        run(0.1)
        XCTAssertEqual(backdrops(in: window), 1, "Mid-pop")
        settle(nav)
        XCTAssertEqual(backdrops(in: window), 1, "After the pop")
    }
    #endif

    // MARK: The columns under Reduce Motion (L1)

    private func makeColumns() -> (window: UIWindow, columns: UKColumnsViewController, root: UIView) {
        let root = UIView()
        let columns = UKColumnsViewController(rootView: root, shell: nil, placeholder: { Page() })
        let window = makeWindow(CGSize(width: 1000, height: 700))
        window.rootViewController = columns
        window.makeKeyAndVisible()
        columns.setWide(true)
        columns.view.layoutIfNeeded()
        run(0.1)
        return (window, columns, root)
    }

    private func frame(_ view: UIView) -> CGRect { view.layer.presentation()?.frame ?? view.frame }

    /// Drilling from the first page to a second: the first page's column changes. With motion it slides; under Reduce Motion it
    /// jumps and fades in place, so it is never between its two columns.
    func testColumnsDoNotSlideSurvivorsUnderReduceMotion() {
        for reduce in [true, false] {
            UKMotion.reduceMotionOverride = reduce
            let (window, columns, _) = makeColumns()
            let a = Page(), b = Page()
            columns.open(a, tag: 1, atDepth: 0, animated: false)
            run(0.1)
            let before = columns.entries[0].host.frame
            columns.open(b, tag: 2, atDepth: 1, animated: true)
            let after = columns.entries[0].host
            XCTAssertNotEqual(before, after.frame, "The first page changes column (reduce: \(reduce))")
            run(0.06)
            let shown = frame(after)
            if reduce {
                XCTAssertEqual(shown.minX, after.frame.minX, accuracy: 0.5, "Under Reduce Motion the page that stays does not slide")
                XCTAssertLessThan(opacity(after), 1, "It cross-fades instead")
                XCTAssertTrue(columns.view.subviews.count > 3, "A snapshot of where it was fades out over it")
            } else {
                XCTAssertGreaterThan(abs(shown.minX - after.frame.minX), 4, "With motion the page that stays slides")
            }
            run(0.5)
            XCTAssertEqual(after.alpha, 1)
            XCTAssertEqual(frame(after), after.frame)
            window.isHidden = true
        }
    }

    /// The columns' edge swipe works under Reduce Motion (it was switched off).
    func testColumnsEdgePanBeginsUnderReduceMotion() throws {
        UKMotion.reduceMotionOverride = true
        let (window, columns, _) = makeColumns()
        columns.open(Page(), tag: 1, atDepth: 0, animated: false)
        run(0.1)
        let pan = try XCTUnwrap(columns.view.gestureRecognizers?.compactMap { $0 as? UIScreenEdgePanGestureRecognizer }.first)
        XCTAssertTrue(pan.isEnabled)
        let fake = FakeEdgePan(target: columns, action: NSSelectorFromString("edgePanned:"))
        fake.fakeState = .began
        _ = columns.perform(NSSelectorFromString("edgePanned:"), with: fake)
        let animator = Mirror(reflecting: columns).children.first { $0.label == "backAnimator" }?.value as? UIViewPropertyAnimator
        XCTAssertNotNil(animator, "The swipe started a scrubbed Back under Reduce Motion")
        fake.fakeState = .cancelled
        _ = columns.perform(NSSelectorFromString("edgePanned:"), with: fake)
        run(0.5)
        window.isHidden = true
    }

    private final class FakeEdgePan: UIScreenEdgePanGestureRecognizer {
        var fakeState: UIGestureRecognizer.State = .possible
        override var state: UIGestureRecognizer.State {
            get { fakeState }
            set { fakeState = newValue }
        }
        override func translation(in view: UIView?) -> CGPoint { .zero }
        override func velocity(in view: UIView?) -> CGPoint { .zero }
    }
}
