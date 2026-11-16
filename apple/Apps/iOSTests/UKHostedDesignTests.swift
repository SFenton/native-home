import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Lets the main run loop turn for `seconds` (see ``HostedPage/wait(_:)``).
@MainActor
func hostedSettle(_ seconds: TimeInterval = 0.15) { HostedPage.wait(seconds) }

@MainActor
func hostedPhoto(_ color: UIColor, size: Int = 8) -> CGImage {
    UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { c in
        color.setFill(); c.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }.cgImage!
}

