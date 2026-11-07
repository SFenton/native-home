import HassCore
import HassDesign
import SwiftUI
import UIKit
import XCTest
@testable import HassUI

/// The camera viewer's rarely-taken paths: the side-by-side layout, a viewer with no caller, a recording camera that has no
/// state entity, and the pressed look of its round controls.
@MainActor
final class UKHostedSharedCameraTests: DemoHouseTestCase {
    private func pool() -> CameraStreamPool {
        CameraStreamPool(modes: [], retainsShownStreams: true, observesApp: false,
                         opener: { _, _, _, _ in }, retryDelays: [], pauseAfterHidden: .seconds(600), stallAfter: .seconds(600),
                         stallCheckInterval: .seconds(600), upgradeDelays: [], frameCounter: { _ in 1 }, prepareConnection: { _ in })
    }

    private func layoutIdentifiers(_ page: UIViewController) -> [String] {
        HostedPage.descendants(of: page.view).compactMap(\.accessibilityIdentifier).filter { $0.hasPrefix("camera.layout.") }
    }

    func testAWideRegularWindowPutsTheVideoBesideTheControlsAndANarrowOneStacksThem() {
        let camera = HomeConfig.cameras[0]
        let context = UKGalleryChrome.context(store: EntityStore(), caller: HostedCaller()).with { $0.surface = .sheet }
        let page = UKCameraViewerViewController(camera: camera, context: context, pool: pool(), caller: HostedCaller())
        let window = RegularWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 700))
        window.windowScene = HostedPage.scene
        HostedPage.track(window)
        window.rootViewController = page
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        page.view.setNeedsLayout()
        page.view.layoutIfNeeded()
        HostedPage.wait(0.2)
        XCTAssertEqual(layoutIdentifiers(page), ["camera.layout.split"], "a wide landscape regular window splits")
        let video = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "camera.viewer.video" }
        let sound = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "camera.control.sound" }
        if let video, let sound {
            let v = video.convert(video.bounds, to: page.view), s = sound.convert(sound.bounds, to: page.view)
            XCTAssertLessThanOrEqual(v.maxX, s.minX + 1, "the controls sit to the right of the video")
        } else {
            XCTFail("video and sound control must both be on screen")
        }

        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        page.view.setNeedsLayout()
        page.view.layoutIfNeeded()
        HostedPage.wait(0.2)
        XCTAssertEqual(layoutIdentifiers(page), ["camera.layout.stacked"], "narrowing the window stacks them again")
    }

    func testAViewerWithNoCallerTriesTheContextCallerThenTheConnectionThenNothing() {
        let camera = HomeConfig.Camera(title: "Porch", entityId: "camera.demo_porch_test", rtcStreamId: "porch", aspectRatio: 16.0 / 9.0,
                                       recordingEntityId: nil, recordingScriptEntityId: "script.demo_porch_recording_test")
        let viaContext = HostedCaller()
        var context = UKGalleryChrome.context(store: EntityStore(), caller: viaContext).with { $0.surface = .sheet }
        let first = UKCameraViewerViewController(camera: camera, context: context, pool: pool(), caller: nil)
        let firstWindow = HostedPage.show(first)
        defer { firstWindow.isHidden = true }
        let record = HostedPage.descendants(of: first.view).first { $0.accessibilityIdentifier == "camera.control.record" } as? UKCameraControlButton
        record?.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until { viaContext.calls == ["script.turn_on"] },
                      "a camera with no recording state still sends the script through the context's caller; saw \(viaContext.calls)")

        context.caller = nil
        context.connection = HassConnection(server: .example, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        let second = UKCameraViewerViewController(camera: camera, context: context, pool: pool(), caller: nil)
        let secondWindow = HostedPage.show(second)
        defer { secondWindow.isHidden = true }
        XCTAssertNotNil(HostedPage.descendants(of: second.view).first { $0.accessibilityIdentifier == "camera.control.record" })

        context.connection = nil
        let third = UKCameraViewerViewController(camera: camera, context: context, pool: pool(), caller: nil)
        let thirdWindow = HostedPage.show(third)
        defer { thirdWindow.isHidden = true }
        let lonely = HostedPage.descendants(of: third.view).first { $0.accessibilityIdentifier == "camera.control.record" } as? UKCameraControlButton
        lonely?.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until { HostedPage.labels(in: third.view).contains { $0.contains("Couldn't change recording") } },
                      "with nothing to send through, the tap says the change failed")
    }

    func testControlButtonsDimWhilePressedAndReportTheirMeasuredHeight() {
        let camera = HomeConfig.cameras[0]
        let context = UKGalleryChrome.context(store: EntityStore(), caller: HostedCaller()).with { $0.surface = .sheet }
        let page = UKCameraViewerViewController(camera: camera, context: context, pool: pool(), caller: HostedCaller())
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        let sound = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "camera.control.sound" } as? UKCameraControlButton
        XCTAssertNotNil(sound)
        sound?.isHighlighted = true
        XCTAssertEqual(sound?.alpha ?? 0, CGFloat(HassTokens.ControlState.pressedOpacity), accuracy: 0.001, "a pressed control dims")
        sound?.isHighlighted = false
        XCTAssertEqual(sound?.alpha, 1)
        let height = sound?.height(forWidth: 90) ?? 0
        XCTAssertGreaterThanOrEqual(height, HassTokens.minTarget)
        XCTAssertEqual(sound?.sizeThatFits(CGSize(width: 90, height: 0)).height, height)
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        HostedPage.wait(0.05)
        XCTAssertNotNil(page.view.window, "a Reduce Motion change leaves the viewer up")
    }
}

/// A window that reports the regular width class, as an iPad window does; `WindowMetrics` reads the key window's own traits.
private final class RegularWindow: UIWindow {
    override var traitCollection: UITraitCollection {
        UITraitCollection(traitsFrom: [super.traitCollection, UITraitCollection(horizontalSizeClass: .regular)])
    }
}
