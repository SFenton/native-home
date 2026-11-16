import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The root's scene handling: the scene coming forward and going away reaches the location coordinator and the production host
/// without dropping the product.
@MainActor
final class UKHostedShellForegroundTests: DemoHouseTestCase {
    func testTheSceneCyclesLeaveTheProductUp() throws {
        let rig = try HostedShellRig.make(inScene: true)
        defer { rig.tearDown() }
        rig.settle()
        let scene = try XCTUnwrap(rig.window.windowScene)
        let center = NotificationCenter.default
        center.post(name: UIScene.didActivateNotification, object: scene)
        center.post(name: UIScene.willDeactivateNotification, object: scene)
        center.post(name: UIScene.didEnterBackgroundNotification, object: scene)
        rig.settle(0.2)
        XCTAssertTrue(rig.root.children.contains { $0 is UKServerUIProductionHost }, "the product stays up through a scene cycle")
    }
}
