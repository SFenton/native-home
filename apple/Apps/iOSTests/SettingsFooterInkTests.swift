import UIKit
import XCTest
import HassCore
@testable import HassUI

/// A footer on the wallpaper reads in white, not the system's secondary label: the notifications footer rendered 3.9:1
/// over the photo and failed the Settings contrast audit once the wallpaper moved behind the whole window.
@MainActor
final class SettingsFooterInkTests: XCTestCase {
    private func footerColor(style: UKSettingsListDriver.Style, ink: UIColor?) throws -> UIColor? {
        let driver = UKSettingsListDriver(style: style)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        driver.collectionView.frame = host.view.bounds
        host.view.addSubview(driver.collectionView)
        driver.setSections([UKSettingsListSection(id: "a", footer: "Footer text", footerInk: ink, rows: [])])
        driver.collectionView.layoutIfNeeded()
        let footer = driver.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter,
                                                             at: IndexPath(item: 0, section: 0)) as? UICollectionViewListCell
        let content = try XCTUnwrap(footer?.contentConfiguration as? UIListContentConfiguration, "No footer was drawn")
        return content.textProperties.color
    }

    func testWallpaperFooterDefaultsToWhite() throws {
        let color = try footerColor(style: .wallpaper, ink: nil)
        XCTAssertEqual(color, .white)
    }

    func testAnExplicitInkWins() throws {
        XCTAssertEqual(try footerColor(style: .wallpaper, ink: .red), .red)
    }

    func testSheetFooterKeepsTheSystemInk() throws {
        let color = try footerColor(style: .sheet, ink: nil)
        XCTAssertNotEqual(color, .white)
    }

    /// The Settings page draws its sections with the stack driver, not the collection list.
    private func stackFooterColor(style: UKSettingsListDriver.Style, ink: UIColor?) throws -> UIColor? {
        let driver = UKSettingsStackDriver(style: style)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        driver.scrollView.frame = host.view.bounds
        host.view.addSubview(driver.scrollView)
        driver.setSections([UKSettingsListSection(id: "a", footer: "Footer text", footerIdentifier: "test.footer", footerInk: ink, rows: [])])
        host.view.layoutIfNeeded()
        func find(_ view: UIView) -> UILabel? {
            if let label = view as? UILabel, label.accessibilityIdentifier == "test.footer" { return label }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        return try XCTUnwrap(find(driver.scrollView), "No footer was drawn").textColor
    }

    func testSettingsPageFooterOnTheWallpaperIsWhite() throws {
        XCTAssertEqual(try stackFooterColor(style: .wallpaper, ink: nil), .white)
    }

    func testSettingsPageFooterExplicitInkWinsAndSheetKeepsSystemInk() throws {
        XCTAssertEqual(try stackFooterColor(style: .wallpaper, ink: .red), .red)
        XCTAssertNotEqual(try stackFooterColor(style: .sheet, ink: nil), .white)
    }

    // MARK: Every wallpaper footer uses the one token

    func testTokenIsWhiteAndDefaultsUseIt() throws {
        XCTAssertEqual(UKSettingsInk.wallpaperFooter, .white)
        XCTAssertEqual(try footerColor(style: .wallpaper, ink: nil), UKSettingsInk.wallpaperFooter)
        XCTAssertEqual(try stackFooterColor(style: .wallpaper, ink: nil), UKSettingsInk.wallpaperFooter)
    }

    func testSettingsPageFootersCarryNoInkOfTheirOwn() {
        let page = UKSettingsViewController(context: UKContext(store: EntityStore()))
        let footed = page.sections().filter { $0.footer != nil }
        XCTAssertGreaterThanOrEqual(footed.count, 3, "The Settings page lost footers")
        for section in footed {
            XCTAssertNil(section.footerInk, "Settings footer \(section.id) sets its own ink instead of UKSettingsInk.wallpaperFooter")
        }
    }

    func testPerformancePageFootersCarryNoInkOfTheirOwn() {
        let page = UKPerformanceViewController(context: UKContext(store: EntityStore()))
        let footed = page.sections().filter { $0.footer != nil }
        XCTAssertFalse(footed.isEmpty, "The Performance page lost its footers")
        for section in footed {
            XCTAssertNil(section.footerInk, "Performance footer \(section.id) sets its own ink instead of UKSettingsInk.wallpaperFooter")
        }
    }
}
