import UIKit
import XCTest
@testable import HassUI

/// A page that hosts columns restyles its Back or Close item in place, also while it is not in a window (a page pushed behind another).
@MainActor
final class UKHostedColumnBarOffscreenTests: DemoHouseTestCase {
    func testTheColumnActionRestylesWithoutAWindowAndAnEmptyBarClearsTheGroups() throws {
        let page = UKPageViewController(context: UKGalleryChrome.context(), title: "Pane")
        page.loadViewIfNeeded()
        var closed = 0
        let other = UIBarButtonItem(title: "Share", style: .plain, target: nil, action: nil)
        var bar = UKColumnBar(items: [other], kind: .close, isEnabled: true, perform: { closed += 1 })
        page.setColumnBar(bar)
        XCTAssertEqual(page.navigationItem.leadingItemGroups.count, 1)
        let item = try XCTUnwrap(page.navigationItem.leadingItemGroups.first?.barButtonItems.last)
        XCTAssertEqual(item.accessibilityIdentifier, "split.close")

        bar.kind = .back
        page.setColumnBar(bar)
        XCTAssertEqual(item.accessibilityIdentifier, "columns.back", "the same item turns into Back")
        XCTAssertEqual(item.accessibilityLabel, "Back")

        bar.isEnabled = false
        page.setColumnBar(bar)
        XCTAssertFalse(item.isEnabled, "a page holding itself open dims the item")

        page.setColumnBar(nil)
        XCTAssertTrue(page.navigationItem.leadingItemGroups.isEmpty, "with no columns the group goes away")
        XCTAssertEqual(closed, 0)
    }
}
