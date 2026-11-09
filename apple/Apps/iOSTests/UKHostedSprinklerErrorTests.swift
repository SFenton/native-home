import HassCore
import UIKit
import XCTest
@testable import HassUI

/// A sprinkler command Home Assistant refuses is explained at the top of the zone's pages, not swallowed.
@MainActor
final class UKHostedSprinklerErrorTests: DemoHouseTestCase {
    private struct Stuck: LocalizedError { var errorDescription: String? { "The valve is stuck." } }

    private final class Refusing: HassServiceCalling {
        func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws { throw Stuck() }
    }

    private func refusingController() throws -> (SprinklerController, UKContext) {
        let store = HomePageFixtures.store()
        let controller = SprinklerController(config: try XCTUnwrap(SprinklersConfig.controllers.first), store: store, caller: Refusing())
        return (controller, UKGalleryChrome.context(store: store).with { $0.surface = .sheet })
    }

    private func failedController() throws -> (SprinklerController, UKContext) {
        let (controller, context) = try refusingController()
        controller.stopWatering()
        XCTAssertTrue(HostedPage.until(5) { controller.errorMessage != nil }, "the refusal is recorded")
        return (controller, context)
    }

    func testTheWaterNowPageShowsTheFailure() throws {
        let (controller, context) = try failedController()
        let page = UKSprinklerWaterPage.make(controller: controller, zone: 0, context: context, done: {}, close: {})
        let window = HostedPage.show(UINavigationController(rootViewController: page), size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until(3) { HostedPage.descendants(of: page.view).contains { $0.accessibilityLabel == "The valve is stuck." } },
                      "Water now says why; saw \(HostedPage.labels(in: page.view))")
    }

    func testTheScheduleEditorShowsTheFailure() throws {
        let (controller, context) = try failedController()
        let page = UKSprinklerSchedulePage.make(controller: controller, zone: 0, context: context, done: {}, close: {})
        let window = HostedPage.show(UINavigationController(rootViewController: page), size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until(3) { HostedPage.descendants(of: page.view).contains { $0.accessibilityLabel == "The valve is stuck." } },
                      "the schedule page says why")
    }

    func testTheControllerSheetShowsTheFailure() throws {
        // The sheet clears a stale error as it opens (`UKSprinklerSheet.present`), so the refusal comes after it is up. Applying it
        // before opening passed only while the sheet's first draw still held the error the open was about to clear.
        let (controller, context) = try refusingController()
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        UKSprinklerSheet.present(controller: controller, initialDetail: nil, context: context, from: host)
        XCTAssertTrue(HostedPage.until(5) { host.presentedViewController != nil }, "the sheet opens")
        let sheet = try XCTUnwrap(host.presentedViewController)
        controller.stopWatering()
        XCTAssertTrue(HostedPage.until(5) { controller.errorMessage != nil }, "the refusal is recorded")
        XCTAssertTrue(HostedPage.until(4) { HostedPage.descendants(of: sheet.view).contains { $0.accessibilityLabel == "The valve is stuck." } },
                      "the sheet says why; saw \(HostedPage.labels(in: sheet.view))")
    }
}

/// A list row view the list moves between cells stays laid out in the cell configured last.
@MainActor
final class UKHostedSprinklerCellContentTests: DemoHouseTestCase {
    func testARowMovedToAnotherCellIsTakenBackWhenTheFirstIsConfiguredAgain() {
        let row = UILabel()
        row.text = "Zone 1"
        let other = UILabel()
        other.text = "Zone 2"
        let content = UKSprinklerCellContent(view: row, insets: .init(top: 8, leading: 0, bottom: 8, trailing: 0), edgeToEdge: false)
        let first = UKSprinklerCellContentView(content)
        let second = UKSprinklerCellContentView(UKSprinklerCellContent(view: other, insets: .init(), edgeToEdge: false))
        XCTAssertTrue(row.superview === first)

        second.configuration = content
        XCTAssertTrue(row.superview === second, "the second cell takes the row")
        XCTAssertNil(other.superview, "and lets its own old row go")

        first.configuration = content
        XCTAssertTrue(row.superview === first, "configured again, the first cell takes the row back instead of constraining one that left")
        first.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        first.layoutIfNeeded()
        XCTAssertEqual(row.frame.minY, 8, accuracy: 0.5, "the row sits inside the first cell's insets")

        second.configuration = UKSprinklerCellContent(view: other, insets: .init(), edgeToEdge: false)
        XCTAssertTrue(row.superview === first, "a cell moving on to another row leaves the row it lost where it is")
        XCTAssertTrue(other.superview === second)
    }
}

