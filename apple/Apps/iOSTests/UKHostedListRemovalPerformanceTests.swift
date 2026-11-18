import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// What a removal costs the main thread: rows leave and come back in a record list that applies through `UKListUpdater`
/// (`.agents/patterns/list-row-removal.md`, `.agents/testing/apple/performance.md`).
///
/// Three of forty rows leave in one update and return in the next, three times per iteration, with Reduce Motion off (the system list
/// animation) and on (the fade). Each animated apply opens one `LayoutChange` interval (page `ListRowRemoval.Records`) that the updater ends
/// when UIKit reports the animation done. Metrics: `XCTCPUMetric` and `XCTOSSignpostMetric` on `LayoutChange`. Run it hosted by naming the
/// class in `FENTON_HOSTED_FILTER`; the simulator's numbers are for comparison, not for hitches.
@MainActor
final class UKHostedListRemovalPerformanceTests: XCTestCase {
    private static let rowCount = 40
    private static let cyclesPerIteration = 3

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        try await super.tearDown()
    }

    func testThreeRowsLeavingAndReturningCost() {
        measureRemovals(reduceMotion: false)
    }

    func testThreeRowsLeavingAndReturningCostReduceMotion() {
        measureRemovals(reduceMotion: true)
    }

    // MARK: Private

    /// Rows are labels; nothing but the list's own work is measured.
    private final class Owner: UKRecordCollectionOwner {
        func recordView(for key: String, reusing old: UIView?) -> UIView? {
            let label = (old as? UILabel) ?? UILabel()
            label.text = key
            label.numberOfLines = 1
            return label
        }
        func recordSwipe(for key: String, leading: Bool) -> UISwipeActionsConfiguration? { nil }
        func recordMenu(for key: String) -> UIMenu? { nil }
        func recordDisplayed(_ key: String) {}
        func recordImageURL(for key: String) -> URL? { nil }
        func auxiliaryView(for item: UKRecordCollectionItem) -> UIView? { nil }
    }

    private func measureRemovals(reduceMotion: Bool) {
        UKMotion.reduceMotionOverride = reduceMotion
        let owner = Owner()
        let controller = UKRecordCollectionController(shape: .list)
        controller.owner = owner
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        host.view.addSubview(controller.collectionView)
        controller.collectionView.frame = host.view.bounds
        let keys = (0..<Self.rowCount).map { "row-\($0)" }
        func show(_ shown: [String]) {
            var content = UKRecordCollectionContent()
            content.groups = [.init(id: "rows", title: nil, keys: shown, dense: false)]
            controller.apply(content, changed: [], surface: .page)
            // The animation (0.3 s, a fade under Reduce Motion) and the interval's end land within this wait.
            RunLoop.main.run(until: Date().addingTimeInterval(reduceMotion ? 0.4 : 0.8))
        }
        show(keys)
        show(Array(keys.dropFirst(3))); show(keys) // warm up: the first animated applies build the cell caches
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let signpost = XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "LayoutChange")
        measure(metrics: [XCTCPUMetric(), signpost], options: options) {
            for _ in 0..<Self.cyclesPerIteration {
                show(Array(keys.dropFirst(3)))
                show(keys)
            }
        }
        XCTAssertEqual(controller.lastPlan?.transition, reduceMotion ? .fade : .animate, "the last return animated (or faded) as the rules say")
        XCTAssertEqual(controller.visibleKeys.first, "row-0", "every row is back")
    }
}
