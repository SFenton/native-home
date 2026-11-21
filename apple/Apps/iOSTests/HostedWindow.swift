import CoreGraphics
import UIKit

// MARK: - The hinge band of a hosted window

/// Where a hosted fold test puts the hinge band. The band is the vertical strip the Duo draws across the middle of its unfolded inner
/// display, so a test takes it from the width of the scene (or of the content area) it lays out, never from a literal x. A literal such
/// as `CGRect(x: 190, ...)` is the middle of an iPhone-width scene only: on the Duo's hosted scene (its folded 466 pt outer display, with
/// the 868 pt window sticking out of it) it leaves one side under ``SplitPolicy/minimumPaneWidth`` and nothing splits, so the test
/// passes without proving the fold. `tools/pattern_guard.py` refuses a literal-x hinge in this target (`hinge-avoidance/hosted-literal-hinge`).
enum HostedWindow {
    /// The measured partly folded band: 40.4 pt wide (455.3 to 495.7 pt on the 951 pt inner display).
    static let bandWidth: CGFloat = 40.4

    /// The band centred in a scene that is `sceneWidth` wide and `height` tall, in that scene's coordinates.
    ///
    /// - Parameters:
    ///   - sceneWidth: The width of the scene or container the test lays out.
    ///   - width: The band's width, ``bandWidth`` by default.
    ///   - height: The band's height, the scene's height.
    static func hingeBand(sceneWidth: CGFloat, width: CGFloat = bandWidth, height: CGFloat) -> CGRect {
        hingeBand(centredIn: CGRect(x: 0, y: 0, width: sceneWidth, height: height), width: width)
    }

    /// The band centred across `area`, spanning the area's height. The area is where the content really sits, in the space the hinge is
    /// read in (window coordinates), so a window wider than its scene still splits at the middle of what the user sees.
    static func hingeBand(centredIn area: CGRect, width: CGFloat = bandWidth) -> CGRect {
        CGRect(x: area.midX - width / 2, y: area.minY, width: width, height: area.height)
    }

    /// The band centred across `view`'s laid-out bounds, in window coordinates, as tall as `window`.
    @MainActor
    static func hingeBand(centredOn view: UIView, in window: UIWindow, width: CGFloat = bandWidth) -> CGRect {
        let area = view.convert(view.bounds, to: nil)
        return CGRect(x: area.midX - width / 2, y: 0, width: width, height: window.bounds.height)
    }
}
