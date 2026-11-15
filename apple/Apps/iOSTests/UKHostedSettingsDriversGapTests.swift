import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The two Settings row drivers (the collection list in sheets, the stack on the page): footers edited in place, footers that go
/// away, the three header kinds, row content set through the system configuration, and the pressed-wash colour blend.
@MainActor
final class UKHostedSettingsDriversGapTests: XCTestCase {
    private func footerLabel(_ id: String, in root: UIView) -> UILabel? {
        HostedPage.descendants(of: root).first { ($0 as? UILabel)?.accessibilityIdentifier == id } as? UILabel
    }

    func testListFooterIsEditedInPlace() {
        let driver = UKSettingsListDriver(style: .sheet)
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        driver.collectionView.frame = host.view.bounds
        host.view.addSubview(driver.collectionView)
        driver.setSections([UKSettingsListSection(id: "v", footer: "Build 1", rows: [])])
        driver.collectionView.layoutIfNeeded()
        func footerText() -> String? {
            let cell = driver.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: IndexPath(item: 0, section: 0)) as? UICollectionViewListCell
            return (cell?.contentConfiguration as? UIListContentConfiguration)?.text
        }
        XCTAssertEqual(footerText(), "Build 1")
        driver.updateFooter(sectionID: "v", text: "Build 1 (copied)")
        driver.collectionView.layoutIfNeeded()
        XCTAssertEqual(footerText(), "Build 1 (copied)")
        driver.updateFooter(sectionID: "none", text: "ignored")
        XCTAssertEqual(footerText(), "Build 1 (copied)")
    }

    func testBlendDrawsTheOverlayOverTheBase() {
        let blended = UIColor.white.ukBlend(with: UIColor.black.withAlphaComponent(0.5))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        blended.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.5, accuracy: 0.01, "half-black over white is mid grey")
        XCTAssertEqual(a, 1, accuracy: 0.01)
        let clear = UIColor.clear.ukBlend(with: .clear).resolvedColor(with: UITraitCollection())
        clear.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(a, 0, "nothing over nothing stays clear")
    }
}
