@testable import HassCore
import HassDemoHouse
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - The kept height of a fitting container

/// A scrolling page asks its content for a height on every frame (`UKPageScrollView.layoutSubviews`). These tests count the real
/// measurements (`UKFitCache.fits`) to prove a scroll measures nothing, and that a width change, a text size change and a content change
/// each measure once.
@MainActor
final class ServerUIFitCacheHostedTests: DemoHouseTestCase {
    /// A page scroll view that counts how often it lays out, so a test knows the scroll really reached `layoutSubviews`.
    private final class CountingScrollView: UKPageScrollView {
        private(set) var layouts = 0
        override func layoutSubviews() {
            layouts += 1
            super.layoutSubviews()
        }
    }

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func settingsHolder() -> (UKServerUIFittingView, [UIView]) {
        let first = UKRowView(UKRowContent("Show count on app icon"), accessory: UISwitch())
        let link = UKServerUISettingsLink()
        link.cell.show(UKRowView.settingsLink(title: "Vacation", subtitle: "Away dates and checklist", symbol: "gearshape", showsChevron: true))
        let last = UKRowView(UKRowContent("Background"), accessory: UISwitch())
        let rows = [first, link, last]
        return (UKServerUIFittingView.wrapping(UKModuleListView(.thin, hasGlyphs: false, rows: rows)), rows)
    }

    private func page(_ holder: UKServerUIFittingView, width: CGFloat = 390) -> (CountingScrollView, UIWindow) {
        let scroll = CountingScrollView(content: holder)
        let controller = UIViewController()
        scroll.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        controller.view.addSubview(scroll)
        let window = HostedPage.show(controller, size: CGSize(width: width, height: 300))
        for _ in 0..<3 { HostedPage.wait(0.05); window.layoutIfNeeded() }
        return (scroll, window)
    }

    private func scrollEveryFrame(_ scroll: CountingScrollView, frames: Int = 40) {
        for frame in 1...frames {
            scroll.contentOffset = CGPoint(x: 0, y: CGFloat(frame))
            scroll.setNeedsLayout()
            scroll.layoutIfNeeded()
        }
    }

    // MARK: Fitting container

    /// UX: scrolling a Settings page lays the scroll view out on every frame and measures its list none of those times.
    func testScrollingASettingsPageMeasuresItsListNoMoreOften() {
        let (holder, _) = settingsHolder()
        let (scroll, window) = page(holder)
        defer { window.isHidden = true }
        let fits = holder.fitCache.fits
        let layouts = scroll.layouts
        XCTAssertGreaterThan(fits, 0, "the first layout measured the list")
        scrollEveryFrame(scroll)
        XCTAssertGreaterThanOrEqual(scroll.layouts - layouts, 40, "every scroll frame laid the scroll view out")
        XCTAssertEqual(holder.fitCache.fits, fits, "and none of them measured the list again")
    }

    /// UX: a new width measures once, then scrolling is free again.
    func testAWidthChangeMeasuresOnceMore() {
        let (holder, _) = settingsHolder()
        let (scroll, window) = page(holder)
        defer { window.isHidden = true }
        let fits = holder.fitCache.fits
        scroll.frame.size.width = 466
        for _ in 0..<3 { window.layoutIfNeeded() }
        let afterWidth = holder.fitCache.fits
        XCTAssertGreaterThan(afterWidth, fits, "a new width is measured")
        XCTAssertLessThanOrEqual(afterWidth - fits, 2, "and not on every pass")
        scrollEveryFrame(scroll)
        XCTAssertEqual(holder.fitCache.fits, afterWidth, "scrolling at the new width measures nothing")
    }

    /// UX: a larger text size measures again, and the page is the taller for it.
    func testATextSizeChangeMeasuresAgain() {
        let (holder, _) = settingsHolder()
        let (scroll, window) = page(holder)
        defer { window.isHidden = true }
        let fits = holder.fitCache.fits
        let height = holder.frame.height
        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        for _ in 0..<3 { HostedPage.wait(0.05); window.layoutIfNeeded() }
        XCTAssertGreaterThan(holder.fitCache.fits, fits, "a new text size is measured")
        XCTAssertGreaterThan(holder.frame.height, height, "the list grew with the text")
        let settled = holder.fitCache.fits
        scrollEveryFrame(scroll)
        XCTAssertEqual(holder.fitCache.fits, settled, "scrolling at the new size measures nothing")
    }

    /// UX: a row that reports a content change (`ukRemeasureContainers`) is measured again, and only then.
    func testAContentChangeMeasuresAgain() throws {
        let (holder, rows) = settingsHolder()
        let (scroll, window) = page(holder)
        defer { window.isHidden = true }
        let fits = holder.fitCache.fits
        let link = try XCTUnwrap(rows[1] as? UKServerUISettingsLink)
        link.cell.show(UKRowView.settingsLink(title: "Vacation", subtitle: "Away dates and a much longer checklist of things to do before leaving the house for a week",
                                              symbol: "gearshape", showsChevron: true))
        link.ukRemeasureContainers(includingSelf: true)
        for _ in 0..<3 { window.layoutIfNeeded() }
        XCTAssertGreaterThan(holder.fitCache.fits, fits, "a reported change is measured")
        let settled = holder.fitCache.fits
        scrollEveryFrame(scroll)
        XCTAssertEqual(holder.fitCache.fits, settled, "and scrolling afterwards measures nothing")
    }
}
