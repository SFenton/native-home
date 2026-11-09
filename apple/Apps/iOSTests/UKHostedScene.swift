import UIKit
@testable import HassUI

/// A window attached to the app's real scene. ``HostedPage/show(_:size:inScene:)`` now does this by default; this stays for call
/// sites that need to know whether the host has a scene (nil where it has none).
@MainActor
enum HostedScene {
    static func show(_ controller: UIViewController, size: CGSize = CGSize(width: 393, height: 852)) -> UIWindow? {
        guard HostedPage.scene != nil else { return nil }
        return HostedPage.show(controller, size: size)
    }
}
