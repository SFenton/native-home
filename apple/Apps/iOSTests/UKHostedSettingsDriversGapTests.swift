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

    private func stackPage(_ sections: [UKSettingsListSection], style: UKSettingsListDriver.Style = .sheet) -> (UKSettingsStackDriver, UIWindow) {
        let driver = UKSettingsStackDriver(style: style)
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 390, height: 844))
        driver.scrollView.frame = host.view.bounds
        host.view.addSubview(driver.scrollView)
        driver.setSections(sections)
        host.view.layoutIfNeeded()
        return (driver, window)
    }

    func testStackFooterIsEditedInPlaceAndRemovedWhenTheSectionLosesIt() {
        let section = UKSettingsListSection(id: "version", footer: "Version 1", footerIdentifier: "version.footer", rows: [])
        let (driver, window) = stackPage([section])
        defer { window.isHidden = true }
        let label = footerLabel("version.footer", in: driver.scrollView)
        XCTAssertEqual(label?.text, "Version 1")

        driver.updateFooter(sectionID: "version", text: "Version 1 (copied)")
        XCTAssertEqual(footerLabel("version.footer", in: driver.scrollView)?.text, "Version 1 (copied)")
        XCTAssertTrue(footerLabel("version.footer", in: driver.scrollView) === label, "the same label is edited, not rebuilt")
        driver.updateFooter(sectionID: "missing", text: "ignored")
        driver.updateFooter(sectionID: "version", text: "Version 1 (copied)")

        driver.setSections([UKSettingsListSection(id: "version", rows: [])])
        XCTAssertNil(footerLabel("version.footer", in: driver.scrollView), "a section with no footer draws none")
    }

    func testStackHeadersReadAsHeadings() {
        let custom = UKSettingsListSection(id: "c", header: .view(label: "Custom heading", signature: "1", build: {
            let view = UILabel()
            view.text = "Custom"
            return view
        }), rows: [])
        let system = UKSettingsListSection(id: "s", header: .system("System heading"), rows: [])
        let title = UKSettingsListSection(id: "t", header: .title("Title heading"), rows: [])
        let (driver, window) = stackPage([custom, system, title], style: .wallpaper)
        defer { window.isHidden = true }
        for name in ["Custom heading", "System heading", "Title heading"] {
            let element = HostedPage.descendants(of: driver.scrollView).first { $0.accessibilityLabel == name }
            XCTAssertNotNil(element, "\(name) is an accessibility element")
            XCTAssertTrue(element?.accessibilityTraits.contains(.header) ?? false, "\(name) is a heading")
        }
    }

    func testStackRowTakesSystemContentConfigurationAndTrailingView() {
        let trailing = UISwitch()
        let row = UKSettingsListRow(id: "row", signature: "a") { cell in
            var content = UIListContentConfiguration.cell()
            content.text = "Quiet hours"
            cell.contentConfiguration = content
            cell.addTrailing(trailing)
        }
        let (driver, window) = stackPage([UKSettingsListSection(id: "s", rows: [row])])
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: driver.scrollView).contains("Quiet hours"), "the configuration's text is drawn")
        XCTAssertTrue(trailing.isDescendant(of: driver.scrollView), "the trailing control sits in the row")
        XCTAssertFalse(trailing.superview?.isHidden ?? true)
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

    /// A row that arranges itself by the width it is given, and says when that changed its height.
    private final class Adapter: UIView, UKWidthAdapting {
        var widths: [CGFloat] = []
        func adapt(toWidth width: CGFloat) -> Bool {
            widths.append(width)
            return widths.count == 1
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            adaptToBounds()
        }
    }

    /// A flow layout that counts how often the list is asked to measure its rows again.
    private final class SpyLayout: UICollectionViewFlowLayout {
        var invalidations = 0
        override func invalidateLayout() {
            invalidations += 1
            super.invalidateLayout()
        }
    }

    func testWidthAdaptingRowAsksItsContainerToMeasureAgain() {
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 320, height: 400))
        defer { window.isHidden = true }
        // In the stack the row measures through Auto Layout.
        let inStack = Adapter(frame: CGRect(x: 0, y: 0, width: 320, height: 40))
        host.view.addSubview(inStack)
        inStack.layoutIfNeeded()
        XCTAssertEqual(inStack.widths.first, 320, "the row adapts to the width it was given")
        HostedPage.wait(0.2)

        // In a list the layout is invalidated, without animation, so the row is measured at its new height.
        let layout = SpyLayout()
        let list = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), collectionViewLayout: layout)
        host.view.addSubview(list)
        let inList = Adapter(frame: CGRect(x: 0, y: 0, width: 280, height: 40))
        list.addSubview(inList)
        let before = layout.invalidations
        inList.layoutIfNeeded()
        XCTAssertEqual(inList.widths.first, 280)
        XCTAssertTrue(HostedPage.until(2) { layout.invalidations > before }, "the list measures its rows again")
    }
}
