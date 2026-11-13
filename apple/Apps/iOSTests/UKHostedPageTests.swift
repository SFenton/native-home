import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Hosted UIKit page tests: the test bundle runs inside the app, so a test can build a UIKit view controller with
/// the gallery's fixture context (``UKGalleryChrome/context(store:caller:)``), put it in a window, lay it out and read what it
/// drew, in seconds where a journey takes minutes. UX line coverage is not measured; these check behaviour. Copy ``HostedPage`` for a new page; keep the asserts about what the user sees, not about line counts.
@MainActor
enum HostedPage {
    /// Every window a hosted test opened through ``show(_:size:)`` or ``HostedScene``. A test that fails an assertion, or never
    /// hides its window, would otherwise leave it visible in the app's scene for every later test (a stale key window and its
    /// presented sheets); the observer below hides them all when each test finishes.
    private static var opened: [Weak<UIWindow>] = []
    private static let observer = WindowCleaner()

    static func track(_ window: UIWindow) {
        _ = observer
        opened.removeAll { $0.value == nil }
        opened.append(Weak(window))
    }

    /// Lays out every tracked window now. A hosted run does not always get a display-link commit between two of the test's run-loop
    /// turns, so a page changed by a state change (a row added, a sheet resized) would otherwise wait for a layout pass that never comes.
    static func layoutTracked() {
        for entry in opened { entry.value?.layoutIfNeeded() }
    }

    /// Hides every tracked window still up.
    static func hideTracked() {
        for entry in opened {
            guard let window = entry.value else { continue }
            window.isHidden = true
            // Release the page: a hidden window still holds its controllers, whose timers, observers and display links would keep
            // running (and keep laying out) under every later test.
            window.rootViewController?.dismiss(animated: false)
            window.rootViewController = nil
            window.windowScene = nil
        }
        opened.removeAll()
    }

    /// The layout census switch as the process started (it reads the environment once).
    private static let censusDefault = UKLayoutCensus.isEnabled

    /// Restores every test-only static to its production default, so no test sees what an earlier one switched on: the motion,
    /// glass-era, device-signal, hinge, census and probe overrides, and any trait override left on the app's scene or its windows.
    static func resetGlobals() {
        UKMotion.reduceMotionOverride = nil
        UKGlassEra.override = nil
        UKGlassEra.iOS18Override = nil
        UKDeviceSignals.regionsOverride = nil
        UKDeviceSignals.verticalBarOverride = nil
        UKLayoutCensus.isEnabled = censusDefault
        UKScrollCostProbe.forceEnabled = false
        UKResourceCensusProbe.forceEnabled = false
        UKNavigationPerfProbe.forceEnabled = false
        UKLaunchCostProbe.forceEnabled = false
        HingePresence.shared.resetForTests()
        UKHinge.hasFold = false
        UKHinge.frame = nil
        if let scene {
            clearTraits(&scene.traitOverrides)
            for window in scene.windows {
                clearTraits(&window.traitOverrides)
                window.overrideUserInterfaceStyle = .unspecified
            }
        }
    }

    private static func clearTraits(_ overrides: inout UITraitOverrides) {
        overrides.remove(UITraitPreferredContentSizeCategory.self)
        overrides.remove(UITraitHorizontalSizeClass.self)
        overrides.remove(UITraitVerticalSizeClass.self)
        overrides.remove(UITraitUserInterfaceStyle.self)
    }

    /// Lets the main run loop turn for `seconds`. The one real wait for every hosted test: `RunLoop.run(until:)` returns at once when
    /// no source or timer is scheduled, so a keep-alive timer makes the wait last (push animations, deferred layout, animated
    /// snapshots and presented sheets finish inside it). Do not call `RunLoop.run(until:)` directly in a test.
    static func wait(_ seconds: TimeInterval = 0.15) {
        let keepAlive = Timer(timeInterval: 0.02, repeats: true) { _ in }
        RunLoop.main.add(keepAlive, forMode: .default)
        defer { keepAlive.invalidate() }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.05))) }
    }

    /// Spins the main run loop until `condition` holds or `timeout` passes; a pop or a sheet takes as long as the machine is busy.
    @discardableResult
    static func until(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { wait(0.05); layoutTracked() }
        return condition()
    }

    /// The host app's first window scene, which a window needs to finish animated pushes, transitions and snapshots.
    static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// A landscape window that may split (``SplitPolicy/allowsSplit(size:isRegularWidth:)``: wider than tall, each half at least
    /// ``SplitPolicy/minimumPaneWidth``) and stays inside the scene's width wherever the scene is wide enough. A window wider than its
    /// scene puts views outside the scene's safe area, and on the iPad (portrait scene, 834 pt) opening a recipe in the pane of an
    /// 1100 pt window never finished laying out: the keyboard guide's layout pass looped on scroll view safe-area and margin updates
    /// (`UKHostedRecipesTests`, 3 of 3 runs, 2026-11-04), while the same pane in the app's real landscape window lays out at once.
    static var splitSize: CGSize {
        let least = 2 * SplitPolicy.minimumPaneWidth
        let width = max(least, min(1100, scene?.coordinateSpace.bounds.width ?? 1100))
        return CGSize(width: width, height: min(800, (width * 0.72).rounded(.down)))
    }

    /// `size` clamped to the scene, for a test whose window must not stick out past it (the folded Duo's scene is 466 by 678 pt, so a
    /// 393 by 852 phone window is taller than it): a recipe pane moving back to a sheet in such a window never finished laying out.
    static func inScene(_ size: CGSize) -> CGSize {
        guard let bounds = scene?.coordinateSpace.bounds.size else { return size }
        return CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
    }

    /// Puts `controller` in a key window of the given size, loads and lays it out, and returns the window (kept alive by the caller).
    /// The window joins the app's scene (a scene-less window never finishes an animated push or transition); pass
    /// `inScene: false` for a test that needs a free window.
    /// The phone window a test gets by default, inside the scene (``inScene(_:)``): 393 by 852 on the iPhone and the iPad, the folded
    /// Duo's 678 pt height there.
    static var phoneSize: CGSize { inScene(CGSize(width: 393, height: 852)) }

    static func show(_ controller: UIViewController, size: CGSize? = nil, inScene: Bool = true) -> UIWindow {
        let frame = CGRect(origin: .zero, size: size ?? phoneSize)
        let window: UIWindow
        if inScene, let scene {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        track(window)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // One main-loop turn so observers, async rebuilds and the first layout pass settle.
        wait(0.2)
        controller.view.layoutIfNeeded()
        return window
    }

    /// Every view under `root`, depth first.
    static func descendants(of root: UIView) -> [UIView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    /// The text of every label under `root`.
    static func labels(in root: UIView) -> [String] {
        descendants(of: root).compactMap { ($0 as? UILabel)?.text }.filter { !$0.isEmpty }
    }
}

/// The Settings page on an empty store, as the gallery draws it (`FENTON_GALLERY=settings`).
@MainActor
final class UKHostedSettingsTests: DemoHouseTestCase {
    func testSettingsListShowsTheHouseholdTopicsAndAbout() {
        let context = UKGalleryChrome.context()
        let page = UKSettingsViewController(context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }

        let list = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "settings.list" }
        XCTAssertNotNil(list, "the Settings list is on screen")
        let texts = HostedPage.labels(in: page.view)
        XCTAssertTrue(texts.contains("Vacation"), "Settings lists Vacation; saw \(texts.prefix(12))")
        XCTAssertTrue(texts.contains("Appearance"), "Settings lists Appearance; saw \(texts.prefix(12))")
    }
}

/// A weak box, so tracking a window does not keep it alive.
final class Weak<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// Hides the hosted tests' windows after every test, pass or fail.
final class WindowCleaner: NSObject, XCTestObservation {
    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        MainActor.assumeIsolated {
            HostedPage.hideTracked()
            HostedPage.resetGlobals()
        }
    }
}
