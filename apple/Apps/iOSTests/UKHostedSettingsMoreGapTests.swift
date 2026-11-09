import FentonActivityModel
import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The app-icon picker follows the person's text size and appearance while it is open.
@MainActor
final class UKHostedSettingsMoreGapTests: XCTestCase {
    private func picker() -> AppIconPickerModel {
        AppIconPickerModel(
            platform: AppIconPlatform(supportsAlternateIcons: { true }, currentName: { nil }, setName: { _ in }),
            iconStore: ActivityAppIconStore(defaults: UserDefaults(suiteName: "appicon-gap-\(UUID())")!))
    }

    private func cellHeight(_ page: UKAppIconPickerViewController) -> CGFloat {
        let id = "appIcon.choice.\(AppIconChoice.default.rawValue)"
        return FeatureHost.view(id, in: page.view)?.frame.height ?? 0
    }

    func testPickerRelaysItsTilesWhenTheTextSizeGrows() throws {
        let page = UKAppIconPickerViewController(model: picker())
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 2400))
        defer { window.isHidden = true }
        let normal = cellHeight(page)
        XCTAssertGreaterThan(normal, 43, "a tile is at least a 44 pt target")

        page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        HostedPage.wait(0.4)
        page.view.layoutIfNeeded()
        let large = cellHeight(page)
        XCTAssertGreaterThan(large, normal, "larger text makes the tile taller instead of clipping its name (\(normal) -> \(large))")
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(FeatureHost.reveal("appIcon.choice.\(choice.rawValue)", in: page.view), "\(choice) is still offered at the larger size")
        }
    }

    func testPreviewIconRedrawsItsHairlineInTheDarkAppearance() throws {
        let page = UKAppIconPickerViewController(model: picker())
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 2400))
        defer { window.isHidden = true }
        let previews = HostedPage.descendants(of: page.view).compactMap { $0 as? UKAppIconPreviewView }
        XCTAssertFalse(previews.isEmpty, "each tile draws its icon")
        let preview = try XCTUnwrap(previews.first)
        preview.overrideUserInterfaceStyle = .light
        HostedPage.wait(0.2)
        let light = preview.subviews.last?.layer.borderColor
        preview.overrideUserInterfaceStyle = .dark
        HostedPage.wait(0.3)
        let dark = preview.subviews.last?.layer.borderColor
        XCTAssertNotNil(dark)
        XCTAssertNotEqual(light, dark, "the hairline that keeps the icon's edge visible is resolved again for the dark appearance")
    }
}
