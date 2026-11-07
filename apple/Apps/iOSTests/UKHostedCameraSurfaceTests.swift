import UIKit
import XCTest
@preconcurrency import WebRTC
@testable import HassUI

// MARK: - On-screen monitor

/// A video surface may draw only while a person could see it: in a window of the active scene, not hidden or transparent, inside
/// every clipping ancestor, and not mid-rotation.
@MainActor
final class OnScreenMonitorHostedTests: XCTestCase {
    private final class Changes {
        var values: [Bool] = []
    }

    private func monitored(in host: UIView, frame: CGRect = CGRect(x: 20, y: 100, width: 120, height: 80)) -> (UIView, OnScreenMonitor, Changes) {
        let changes = Changes()
        let view = UIView(frame: frame)
        host.addSubview(view)
        let monitor = OnScreenMonitor(view: view) { changes.values.append($0) }
        return (view, monitor, changes)
    }

    func testAViewInTheActiveWindowIsOnScreenAndTheChangeIsReportedOnce() {
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let (_, monitor, changes) = monitored(in: controller.view)
        XCTAssertFalse(monitor.isOnScreen, "nothing was asked yet")
        monitor.windowDidChange()
        XCTAssertTrue(monitor.isOnScreen)
        monitor.evaluate()
        monitor.layoutDidRun()
        XCTAssertEqual(changes.values, [true], "only a change of answer is reported")
    }

    func testAViewWithoutAWindowOrSizeIsNotOnScreen() {
        let changes = Changes()
        let loose = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let monitor = OnScreenMonitor(view: loose) { changes.values.append($0) }
        monitor.windowDidChange()
        monitor.layoutDidRun()
        XCTAssertFalse(monitor.isOnScreen)
        XCTAssertTrue(changes.values.isEmpty)

        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let (_, flat, _) = monitored(in: controller.view, frame: CGRect(x: 0, y: 0, width: 0, height: 80))
        flat.windowDidChange()
        XCTAssertFalse(flat.isOnScreen, "a view with no width draws nothing")
    }

    func testHidingTheViewOrAnAncestorOrFadingItTakesItOffScreen() {
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let (view, monitor, changes) = monitored(in: controller.view)
        monitor.windowDidChange()
        XCTAssertTrue(monitor.isOnScreen)
        view.isHidden = true
        monitor.evaluate()
        XCTAssertFalse(monitor.isOnScreen, "hidden")
        view.isHidden = false
        controller.view.alpha = 0
        monitor.evaluate()
        XCTAssertFalse(monitor.isOnScreen, "an ancestor is transparent")
        controller.view.alpha = 1
        monitor.evaluate()
        XCTAssertTrue(monitor.isOnScreen)
        XCTAssertEqual(changes.values, [true, false, true])
    }

    func testAViewBelowTheFoldOfAScrollViewIsOffScreenUntilItScrollsIn() {
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 100, width: 393, height: 400))
        scroll.contentSize = CGSize(width: 393, height: 3000)
        controller.view.addSubview(scroll)
        let (view, monitor, changes) = monitored(in: scroll, frame: CGRect(x: 20, y: 1500, width: 120, height: 80))
        monitor.windowDidChange()
        XCTAssertFalse(monitor.isOnScreen, "in the window, but clipped away by the scroll view's viewport")
        scroll.contentOffset = CGPoint(x: 0, y: 1300)
        XCTAssertTrue(monitor.isOnScreen, "scrolling re-evaluates by itself")
        scroll.contentOffset = CGPoint(x: 0, y: 0)
        XCTAssertFalse(monitor.isOnScreen)
        XCTAssertEqual(changes.values, [true, false])
        _ = view
    }

    func testAClippingAncestorCutsAViewOutsideItOff() {
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let clip = UIView(frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        clip.clipsToBounds = true
        controller.view.addSubview(clip)
        let (view, monitor, _) = monitored(in: clip, frame: CGRect(x: 150, y: 10, width: 40, height: 40))
        monitor.windowDidChange()
        XCTAssertFalse(monitor.isOnScreen, "entirely outside the clip")
        view.frame = CGRect(x: 80, y: 10, width: 40, height: 40)
        monitor.evaluate()
        XCTAssertTrue(monitor.isOnScreen, "partly inside is on screen")
    }

    func testAWindowSizeChangeHoldsTheViewOffScreenUntilTheRotationSettles() async {
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let (_, monitor, changes) = monitored(in: controller.view)
        monitor.windowDidChange()
        XCTAssertTrue(monitor.isOnScreen)
        window.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
        monitor.layoutDidRun()
        XCTAssertFalse(monitor.isOnScreen, "mid-rotation a Metal layer may block the main thread")
        try? await Task.sleep(for: OnScreenMonitor.transitionSettle + .milliseconds(250))
        XCTAssertTrue(monitor.isOnScreen, "settled")
        XCTAssertEqual(changes.values, [true, false, true])
    }

    func testLeavingTheWindowAndComingBackStartsFresh() {
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let (view, monitor, _) = monitored(in: controller.view)
        monitor.windowDidChange()
        XCTAssertTrue(monitor.isOnScreen)
        view.removeFromSuperview()
        monitor.windowDidChange()
        XCTAssertFalse(monitor.isOnScreen, "no window, no screen")
    }
}

// MARK: - Live video surface

/// The Metal video view joins a track only while it is visible and leaves it the moment it is not.
@MainActor
final class LiveVideoSurfaceHostedTests: XCTestCase {
    private let factory = RTCPeerConnectionFactory()

    private func track() -> RTCVideoTrack {
        factory.videoTrack(with: factory.videoSource(), trackId: "surface-\(UUID().uuidString)")
    }

    func testTheSurfaceDrawsOnlyWhileAVisibleSurfaceHoldsATrack() {
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let surface = LiveVideoSurface(frame: CGRect(x: 0, y: 100, width: 300, height: 200))
        XCTAssertFalse(surface.isDrawing)
        XCTAssertFalse(surface.isOnScreen)
        let video = track()
        surface.setTrack(video)
        XCTAssertFalse(surface.isDrawing, "off screen: a track is held but not drawn")
        controller.view.addSubview(surface)
        surface.layoutIfNeeded()
        XCTAssertTrue(surface.isOnScreen)
        XCTAssertTrue(surface.isDrawing, "on screen, it joined the track")
        surface.setTrack(video)
        XCTAssertTrue(surface.isDrawing, "the same track again changes nothing")
        surface.setTrack(nil)
        XCTAssertFalse(surface.isDrawing, "no track, nothing drawn")
    }

    func testReplacingTheTrackLeavesTheOldOneAndJoinsTheNew() {
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let surface = LiveVideoSurface(frame: CGRect(x: 0, y: 100, width: 300, height: 200))
        controller.view.addSubview(surface)
        surface.layoutIfNeeded()
        let first = track(), second = track()
        surface.setTrack(first)
        XCTAssertTrue(surface.isDrawing)
        surface.setTrack(second)
        XCTAssertTrue(surface.isDrawing, "re-attached to the new track after leaving the old one")
        surface.removeFromSuperview()
        XCTAssertFalse(surface.isOnScreen)
        XCTAssertFalse(surface.isDrawing, "taken out of the window it stops being a renderer")
    }

    func testFillCropsTheFrameAndFitLetterboxesIt() {
        let surface = LiveVideoSurface(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertFalse(surface.fills)
        surface.fills = true
        surface.layoutIfNeeded()
        XCTAssertTrue(surface.fills)
        XCTAssertFalse(surface.isAccessibilityElement, "the picture is not an accessibility element of its own")
        XCTAssertFalse(surface.isUserInteractionEnabled, "taps go to the tile under it")
        XCTAssertEqual(surface.subviews.first?.frame, surface.bounds, "the Metal view fills the surface")
    }
}

// MARK: - Background time

/// The location send asks iOS for background time and gives it back.
@MainActor
final class UIKitBackgroundTimeHostedTests: XCTestCase {
    func testInTheForegroundThereIsNoLimit() {
        let time = UIKitBackgroundTime()
        if UIApplication.shared.applicationState != .background {
            XCTAssertEqual(time.remaining, .infinity, "foreground: no limit")
        }
    }

    func testAHoldCanBeEndedMoreThanOnceWithoutHarm() {
        let time = UIKitBackgroundTime()
        let end = time.begin("hosted-test")
        end()
        end()
        let again = time.begin("hosted-test-2")
        again()
    }
}
