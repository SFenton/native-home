import HassCore
import UIKit
import XCTest
@testable import HassUI

/// A Settings topic opened on a window that splits shows beside the list as a column; when the window narrows it moves onto the
/// section's stack, and when it widens again it goes back.
@MainActor
final class UKHostedSectionColumnsTests: XCTestCase {
    private func sectionController(_ rig: HostedShellRig) -> UKSectionNavigationController? {
        func find(_ controller: UIViewController) -> UKSectionNavigationController? {
            if let match = controller as? UKSectionNavigationController, match.section == .settings { return match }
            for child in controller.children { if let found = find(child) { return found } }
            return nil
        }
        return find(rig.root)
    }

    func testATopicIsAColumnWhereTheWindowSplitsAndAPushWhereItDoesNot() throws {
        let rig = try HostedShellRig.make(size: CGSize(width: 1180, height: 820), regular: true)
        defer { rig.tearDown() }
        // The split rule reads the window's width class (an iPad's window is regular); the hosted window sits in an iPhone scene,
        // so the window is made regular here as well as the root.
        rig.window.traitOverrides.horizontalSizeClass = .regular
        rig.settle()
        rig.navigator.select(.settings)
        rig.settle(0.6)
        let section = try XCTUnwrap(sectionController(rig), "the Settings section is built")
        XCTAssertTrue(HostedPage.until(4) { section.splitting }, "an iPad-landscape window splits")

        rig.navigator.append(.settings(.vacation), in: .settings)
        rig.settle(1.0)
        XCTAssertEqual(section.hostedCount, 1, "the topic is shown as a column")
        XCTAssertEqual(section.viewControllers.count, 1, "nothing is pushed while it is a column")

        rig.window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        rig.root.traitOverrides.horizontalSizeClass = .compact
        rig.window.traitOverrides.horizontalSizeClass = .compact
        rig.root.view.setNeedsLayout()
        XCTAssertTrue(HostedPage.until(5) { !section.splitting }, "a narrow window stops splitting")
        rig.settle(0.8)
        XCTAssertEqual(section.hostedCount, 0)
        XCTAssertEqual(section.viewControllers.count, 2, "the topic moved onto the stack")

        rig.window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        rig.root.traitOverrides.horizontalSizeClass = .regular
        rig.window.traitOverrides.horizontalSizeClass = .regular
        rig.root.view.setNeedsLayout()
        XCTAssertTrue(HostedPage.until(5) { section.splitting }, "widening splits again")
        rig.settle(0.8)
        XCTAssertEqual(section.viewControllers.count, 1, "and the topic goes back to a column")
    }
}
