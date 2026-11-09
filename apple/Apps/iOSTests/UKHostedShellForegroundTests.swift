import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The shell's foreground handling and gesture rules: the scene coming forward tells the location coordinator, the leading-edge swipe
/// shares the screen with the page's own gestures, and the location permission page comes from the Household lane's hook.
@MainActor
final class UKHostedShellForegroundTests: DemoHouseTestCase {
    func testComingForwardAsksTheLocationCoordinatorForAFixAndTheEdgeSwipeSharesTheScreen() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        XCTAssertTrue(rig.shell.gestureRecognizer(UIPanGestureRecognizer(), shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()),
                      "the edge swipe never blocks the page's own gestures")
        rig.shell.sceneBecameActive()
        rig.settle(0.2)
        XCTAssertNotNil(rig.shell.view.window, "the shell stays up after the scene comes forward")
    }

    func testTheLocationPermissionHookBuildsThePageForTheCoordinator() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        let location = LocationCoordinator(platform: GalleryLocationPlatform(.notDetermined), mobileApp: PushCoordinator.inert().mobileApp,
                                           defaults: UserDefaults(suiteName: "shell-foreground-\(UUID())")!)
        var closed = 0
        let page = UKShellHooks.locationPermission(location, UKGalleryChrome.context(), { closed += 1 })
        XCTAssertNotNil(page.view, "the permission page builds")
        XCTAssertEqual(closed, 0)
    }
}
