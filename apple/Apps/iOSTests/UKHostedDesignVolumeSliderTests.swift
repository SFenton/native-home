import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A pan recognizer that reports what the test says.
private final class ScriptedPan: UIPanGestureRecognizer {
    var scriptedState: UIGestureRecognizer.State = .possible
    var point = CGPoint.zero
    var travel = CGPoint.zero
    var speed = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set {}
    }
    override func location(in view: UIView?) -> CGPoint { point }
    override func translation(in view: UIView?) -> CGPoint { travel }
    override func velocity(in view: UIView?) -> CGPoint { speed }
}

/// The speaker tile's volume slider: what a drag does, what it must ignore.
@MainActor
final class UKHostedDesignVolumeSliderTests: XCTestCase {
    private func slider(percent: Int = 20, onCommit: @escaping (Int) -> Void) -> (UKTileVolumeSlider, UIWindow) {
        let host = UIViewController()
        let window = HostedPage.show(host)
        let slider = UKTileVolumeSlider(title: "Den", percent: percent, identifier: "vol", onCommit: onCommit)
        slider.frame = CGRect(x: 20, y: 80, width: 200, height: 44)
        host.view.addSubview(slider)
        slider.layoutIfNeeded()
        return (slider, window)
    }

    private func drive(_ slider: UKTileVolumeSlider, _ pan: ScriptedPan, _ state: UIGestureRecognizer.State, x: CGFloat, travel: CGPoint = CGPoint(x: 30, y: 0)) {
        pan.scriptedState = state
        pan.point = CGPoint(x: x, y: 22)
        pan.travel = travel
        slider.perform(NSSelectorFromString("handlePan:"), with: pan)
    }

    func testDraggingToTheMiddleCommitsHalfOnReleaseAndAHaptic() {
        var committed: [Int] = []
        let (slider, window) = slider { committed.append($0) }
        defer { window.isHidden = true }
        let pan = ScriptedPan()
        drive(slider, pan, .began, x: 20)
        drive(slider, pan, .changed, x: 100)
        XCTAssertEqual(slider.accessibilityValue, "50 percent", "the level under the finger shows while dragging")
        XCTAssertTrue(committed.isEmpty, "nothing is sent until the finger lifts")
        drive(slider, pan, .ended, x: 100)
        XCTAssertEqual(committed, [50])
        XCTAssertEqual(slider.accessibilityValue, "50 percent", "the level just asked for holds until the live one arrives")
    }

    func testAVerticalDragIsTheScrollAndSendsNothing() {
        var committed: [Int] = []
        let (slider, window) = slider { committed.append($0) }
        defer { window.isHidden = true }
        let pan = ScriptedPan()
        pan.speed = CGPoint(x: 5, y: 90)
        XCTAssertFalse(slider.gestureRecognizerShouldBegin(pan))
        pan.speed = CGPoint(x: 90, y: 5)
        XCTAssertTrue(slider.gestureRecognizerShouldBegin(pan))
        slider.isDisabled = true
        XCTAssertFalse(slider.gestureRecognizerShouldBegin(pan), "a disabled slider takes no drag")
        slider.isDisabled = false
        drive(slider, pan, .began, x: 150, travel: CGPoint(x: 2, y: 40))
        drive(slider, pan, .changed, x: 160, travel: CGPoint(x: 2, y: 40))
        drive(slider, pan, .ended, x: 160, travel: CGPoint(x: 2, y: 40))
        XCTAssertTrue(committed.isEmpty)
        XCTAssertEqual(slider.accessibilityValue, "20 percent")
    }

    func testACancelledDragRestoresTheLiveLevelAndReleasingOnTheSameLevelSendsNothing() {
        var committed: [Int] = []
        let (slider, window) = slider(percent: 50) { committed.append($0) }
        defer { window.isHidden = true }
        let pan = ScriptedPan()
        drive(slider, pan, .began, x: 180)
        drive(slider, pan, .cancelled, x: 180)
        XCTAssertEqual(slider.accessibilityValue, "50 percent")
        drive(slider, pan, .began, x: 100)
        drive(slider, pan, .ended, x: 100)
        XCTAssertTrue(committed.isEmpty, "the level is already 50")
    }

    func testRightToLeftMirrorsTheDrag() {
        var committed: [Int] = []
        let (slider, window) = slider { committed.append($0) }
        defer { window.isHidden = true }
        slider.semanticContentAttribute = .forceRightToLeft
        slider.layoutIfNeeded()
        let pan = ScriptedPan()
        drive(slider, pan, .began, x: 40)
        drive(slider, pan, .ended, x: 40)
        XCTAssertEqual(committed.first.map(Double.init) ?? 0, 80, accuracy: 3, "the leading edge is the right: a touch near the left is a high level")
    }
}
