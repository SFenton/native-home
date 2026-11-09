import UIKit
import XCTest
@testable import HassUI

/// The shell's environment follows the system's Reduce Motion and Reduce Transparency switches as they change.
@MainActor
final class UKHostedShellEnvironmentTests: XCTestCase {
    func testTheEnvironmentReadsTheSystemSettingsAgainWhenTheyChange() {
        let environment = UKShellEnvironment()
        let observers = environment.observeAccessibilitySettings()
        defer { observers.forEach(NotificationCenter.default.removeObserver) }
        XCTAssertEqual(observers.count, 2, "one observer each for motion and transparency")

        environment.reduceMotion = !UIAccessibility.isReduceMotionEnabled
        environment.reduceTransparency = !UIAccessibility.isReduceTransparencyEnabled
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        NotificationCenter.default.post(name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        HostedPage.wait(0.1)
        XCTAssertEqual(environment.reduceMotion, UIAccessibility.isReduceMotionEnabled)
        XCTAssertEqual(environment.reduceTransparency, UIAccessibility.isReduceTransparencyEnabled)
    }
}
