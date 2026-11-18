@testable import HassCore
import HassDemoHouse
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Parity round two: row heights and Settings row kinds

/// Hosted checks for the native defects of parity round two (`pl-bedtile`, `pl-setrows`): a bedroom tile with no height in a stack,
/// settings link rows that were 0.67 pt hairlines, a blur row with no side inset, and Reset to Default and Version drawn as chevron rows.
///
/// Every case hosts in a window of the family's own width (`HostedPage.show` with the raw size): iPhone 390, folded Duo 466,
/// unfolded Duo 868 and iPad 744 points. The UX tests read frames; the accessibility tests read the element a person reaches.
@MainActor
final class ServerUIRowHeightsHostedTests: DemoHouseTestCase {
    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                                CGSize(width: 868, height: 678), CGSize(width: 744, height: 1133)]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Hosting

    /// Puts `holder` in a window of `size`, inset like a page, and lays it out a few times.
    private func host(_ holder: UKServerUIFittingView, size: CGSize) -> UIWindow {
        // The holder sits in a `UKColumnView`, as it does on the real page: the column measures it at its width on every layout pass and
        // places it; this test never sets the holder's height itself.
        let controller = UIViewController()
        let column = UKColumnView(insets: UIEdgeInsets(top: 60, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l))
        column.setViews([holder])
        column.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        controller.view.addSubview(column)
        let window = HostedPage.show(controller, size: size)
        for _ in 0..<3 { HostedPage.wait(0.05); window.layoutIfNeeded() }
        return window
    }

    private func width(_ size: CGSize) -> CGFloat { size.width - 2 * HassTokens.Spacing.l }

    // MARK: Settings link rows

    private func settingsLink(_ title: String, subtitle: String, chevron: Bool = false) -> UKServerUISettingsLink {
        let link = UKServerUISettingsLink()
        link.cell.show(UKRowView.settingsLink(title: title, subtitle: subtitle, symbol: "gearshape", showsChevron: chevron))
        link.cell.makeElement(label: UKRowView.accessibilityLabel(title: title, subtitle: subtitle), hint: nil, traits: .button,
                              identifier: "settings-" + title.lowercased())
        return link
    }

    private func linkRows() -> (links: [UKServerUISettingsLink], rows: [UIView]) {
        let first = UKRowView(UKRowContent("Show count on app icon"), accessory: UISwitch())
        let vacation = settingsLink("Vacation", subtitle: "Away dates and checklist", chevron: true)
        let household = settingsLink("Household", subtitle: "Guest controls and rooms")
        let last = UKRowView(UKRowContent("Background"), accessory: UISwitch())
        return ([vacation, household], [first, vacation, household, last])
    }

    /// UX: a link row between other rows keeps its height at every family width, and the list is the sum of its rows.
    func testSettingsLinkRowsKeepTheirHeightInAModuleListAtEveryFamilyWidth() {
        for size in Self.sizes {
            let (links, rows) = linkRows()
            let list = UKModuleListView(.thin, hasGlyphs: false, rows: rows)
            let holder = UKServerUIFittingView.wrapping(list)
            let window = host(holder, size: size)
            defer { window.isHidden = true }
            for link in links {
                XCTAssertGreaterThanOrEqual(link.frame.height, 44, "\(size): the link is a touch target tall, not a 0.67 pt hairline: \(link.frame)")
                XCTAssertEqual(link.cell.frame.height, link.frame.height, accuracy: 0.5, "\(size): the cell fills its link")
                XCTAssertEqual(link.gridHeight(forWidth: width(size)), link.frame.height, accuracy: 1, "\(size): measured and drawn agree")
            }
            let rowSum = rows.reduce(CGFloat(0)) { $0 + $1.frame.height }
            XCTAssertGreaterThanOrEqual(holder.frame.height + 0.5, rowSum, "\(size): the list holds every row")
            XCTAssertGreaterThanOrEqual(holder.gridHeight(forWidth: width(size)), 4 * 44, "\(size): the list measures every row")
            for (above, below) in zip(rows, rows.dropFirst()) {
                XCTAssertLessThanOrEqual(above.frame.maxY, below.frame.minY + 0.5, "\(size): rows do not overlap")
            }
        }
    }

    /// UX: a link's own padding is in its constraints before it has laid out, so the column's first measurement (made before any layout
    /// of the link) is already its drawn height: set in `layoutSubviews`, the link measured 30 pt short and the stack squashed it.
    func testSettingsLinkCountsItsPaddingBeforeItsFirstLayout() {
        let link = settingsLink("Vacation", subtitle: "Away dates and checklist", chevron: true)
        let fitted = link.systemLayoutSizeFitting(CGSize(width: 358, height: UIView.layoutFittingCompressedSize.height),
                                                  withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        XCTAssertGreaterThanOrEqual(fitted, 2 * InsetGroupedMetrics.rowPadding + 2 * 16, "the unlaid link counts both paddings: \(fitted)")
    }

    /// UX: the first measurement, before any layout pass, already counts the link (the trap a width-driven host has).
    func testSettingsListMeasuredBeforeFirstLayoutCountsEveryLink() {
        let (_, rows) = linkRows()
        let holder = UKServerUIFittingView.wrapping(UKModuleListView(.thin, hasGlyphs: false, rows: rows))
        XCTAssertGreaterThanOrEqual(holder.gridHeight(forWidth: 390 - 32), 4 * 44)
    }

    /// Accessibility: each link is one button with its title and subtitle, at least 44 pt tall, and never a sliver.
    func testSettingsLinkElementsAreNamedButtonsAtLeast44PointTallAtEveryFamilyWidth() throws {
        for size in Self.sizes {
            let (links, rows) = linkRows()
            let holder = UKServerUIFittingView.wrapping(UKModuleListView(.thin, hasGlyphs: false, rows: rows))
            let window = host(holder, size: size)
            defer { window.isHidden = true }
            for link in links {
                let element = link.cell
                XCTAssertTrue(element.isAccessibilityElement, "\(size): the cell is the element")
                XCTAssertTrue(element.accessibilityTraits.contains(.button), "\(size): a link is a button")
                let label = try XCTUnwrap(element.accessibilityLabel)
                XCTAssertTrue(label.contains("Vacation") || label.contains("Household"), "\(size): named by its title: \(label)")
                XCTAssertTrue(label.contains("Away dates") || label.contains("Guest controls"), "\(size): and its subtitle: \(label)")
                let frame = element.convert(element.bounds, to: nil)
                XCTAssertGreaterThanOrEqual(frame.height, 44, "\(size): \(label) is not a sliver: \(frame)")
                XCTAssertGreaterThan(frame.width, 100, "\(size): \(label) spans the card: \(frame)")
            }
        }
    }

    // MARK: Width changes

    /// UX: a fold, an unfold or a window resize gives the column a new width. A placed list lays out at its old width before it fits at
    /// the new one, so after one layout every link and tile has the height it measures at the width it now has.
    func testLinksAndTilesKeepTheirHeightWhenTheWidthChanges() throws {
        let (links, rows) = linkRows()
        let tile = try bedTile(0)
        let hosted = UKMeasuredView(tile)
        let list = UKModuleListView(.thin, hasGlyphs: false, rows: rows)
        let holder = UKServerUIFittingView.wrapping(ukVStack([list, hosted], spacing: HassTokens.Spacing.m))
        let window = host(holder, size: Self.sizes[1])
        defer { window.isHidden = true }
        let column = try XCTUnwrap(holder.superview)
        for size in [Self.sizes[2], Self.sizes[1], Self.sizes[0], Self.sizes[3], Self.sizes[1]] {
            column.frame.size.width = size.width
            window.layoutIfNeeded()
            XCTAssertEqual(holder.frame.width, width(size), accuracy: 0.5, "\(size): the holder has the new width")
            for link in links {
                XCTAssertEqual(link.frame.width, width(size), accuracy: 0.5, "\(size): the link has the new width")
                XCTAssertGreaterThanOrEqual(link.frame.height, 44, "\(size): the link is not a sliver: \(link.frame)")
                XCTAssertEqual(link.gridHeight(forWidth: link.frame.width), link.frame.height, accuracy: 1, "\(size): the link is its own measured height")
            }
            XCTAssertEqual(hosted.frame.height, tile.gridHeight(forWidth: width(size)), accuracy: 1, "\(size): the tile has its height at the new width")
            XCTAssertLessThanOrEqual(list.frame.maxY, hosted.frame.minY + 0.5, "\(size): the list and the tile do not overlap")
            XCTAssertGreaterThanOrEqual(holder.frame.height + 0.5, hosted.frame.maxY, "\(size): the holder holds the tile")
        }
    }

    // MARK: Hand-laid rows in a module list

    /// UX: a hand-laid row (the server-UI text) in a module list is wrapped so it has a height; an Auto Layout row is left alone.
    func testHandLaidRowsAreHostedAndAutoLayoutRowsAreNot() {
        let text = UKServerUIText()
        XCTAssertTrue(ukStackRow(text) is UKWidthPreparing, "hand-laid text gets a measured host")
        let toggle = UKRowView(UKRowContent("Toggle"), accessory: UISwitch())
        XCTAssertTrue(ukStackRow(toggle) === toggle, "a canonical row is arranged as it is")
        let link = UKServerUISettingsLink()
        XCTAssertTrue(ukStackRow(link) === link, "a pinned fitting host is arranged as it is")
        let bedroom = UKServerUIBedroomControl()
        XCTAssertTrue(ukStackRow(bedroom) === bedroom, "a stack is arranged as it is")
    }

    // MARK: Bedroom tiles

    private func wakeTile() -> UKBedroomTile {
        let store = EntityStore()
        let controller = WakeLightController(config: DemoHouse.config.bedroom.wakeLight, store: store,
                                             caller: BedroomGalleryRecorder(store: store), canEdit: true)
        return UKBedroomTile.wakeLight(controller, context: UKContext(store: store, caller: BedroomGalleryRecorder(store: store)), action: {})
    }

    private func bedTile(_ index: Int) throws -> UKBedroomTile {
        let store = EntityStore()
        let beds = DemoHouse.config.bedroom.beds
        let controller = BedSideController(config: try XCTUnwrap(beds.indices.contains(index) ? beds[index] : beds.first),
                                           store: store, caller: BedroomGalleryRecorder(store: store))
        return UKBedroomTile.bedSide(controller, context: UKContext(store: store, caller: BedroomGalleryRecorder(store: store)), action: {})
    }

    /// UX: a tile inside the measured host reports the tracks it needs (the grid reads it), as a tile placed directly does.
    func testHostedTileForwardsItsMinimumWidth() throws {
        let tile = try bedTile(0)
        XCTAssertEqual(UKMeasuredView(tile).gridMinimumWidth, tile.gridMinimumWidth)
        XCTAssertEqual(ukWrappedMinimum(UKMeasuredView(tile)), tile.gridMinimumWidth)
    }

    // MARK: Blur row

    private func blurRow(_ size: CGSize, category: UIContentSizeCategory? = nil) -> (UKPercentSliderRow, UIWindow, UKServerUIFittingView) {
        let row = UKPercentSliderRow("Background Blur", value: 40, identifier: "settings-blur",
                                     horizontalPadding: HassTokens.Spacing.l) { _ in }
        let atom = UKServerUISettingsAtom()
        atom.install(row, identifier: "settings-blur")
        let toggle = UKRowView(UKRowContent("Show count on app icon"), accessory: UISwitch())
        let holder = UKServerUIFittingView.wrapping(UKModuleListView(.thin, hasGlyphs: false, rows: [atom, toggle]))
        let window = host(holder, size: size)
        if let category {
            window.traitOverrides.preferredContentSizeCategory = category
            // No manual re-measure: the trait change must reach the column by itself.
            for _ in 0..<3 { HostedPage.wait(0.05); window.layoutIfNeeded() }
        }
        return (row, window, holder)
    }

    /// UX: the blur label starts 16 pt in from the card edge, like its neighbours, and the slider sits inside the same inset.
    func testBlurRowIsInsetFromTheCardEdgeAtEveryFamilyWidth() throws {
        for size in Self.sizes {
            let (row, window, _) = blurRow(size)
            defer { window.isHidden = true }
            let title = try XCTUnwrap(HostedPage.descendants(of: row).compactMap { $0 as? UILabel }.first { $0.text == "Background Blur" })
            let slider = try XCTUnwrap(HostedPage.descendants(of: row).compactMap { $0 as? UISlider }.first)
            let titleFrame = title.convert(title.bounds, to: row)
            let sliderFrame = slider.convert(slider.bounds, to: row)
            XCTAssertEqual(titleFrame.minX, HassTokens.Spacing.l, accuracy: 1, "\(size): the label is inset 16 pt: \(titleFrame)")
            XCTAssertEqual(sliderFrame.minX, HassTokens.Spacing.l, accuracy: 1, "\(size): the slider starts at the same inset: \(sliderFrame)")
            XCTAssertEqual(row.bounds.width - sliderFrame.maxX, HassTokens.Spacing.l, accuracy: 1, "\(size): and ends 16 pt short of the edge")
        }
    }

    /// Accessibility: the row stays one adjustable element with "N percent", and at the largest accessibility size the label is not
    /// clipped by the row.
    func testBlurRowKeepsItsAdjustableElementAndIsNotClippedAtTheLargestTextSize() throws {
        for size in Self.sizes {
            let (row, window, _) = blurRow(size, category: .accessibilityExtraExtraExtraLarge)
            defer { window.isHidden = true }
            XCTAssertTrue(row.isAccessibilityElement)
            XCTAssertTrue(row.accessibilityTraits.contains(.adjustable))
            XCTAssertEqual(row.accessibilityValue, "40 percent")
            XCTAssertEqual(row.accessibilityLabel, "Background Blur")
            let title = try XCTUnwrap(HostedPage.descendants(of: row).compactMap { $0 as? UILabel }.first { $0.text == "Background Blur" })
            let frame = title.convert(title.bounds, to: row)
            XCTAssertTrue(row.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(size): the label stays inside the row: \(frame) in \(row.bounds)")
            XCTAssertGreaterThanOrEqual(frame.minX, HassTokens.Spacing.l - 0.5, "\(size): and inside the inset")
            let required = title.sizeThatFits(CGSize(width: frame.width, height: .greatestFiniteMagnitude)).height
            XCTAssertGreaterThanOrEqual(frame.height + 1, required, "\(size): the label has the height its text needs")
        }
    }

    // MARK: Reset and Version

    private func preferenceRows(_ size: CGSize, resetEnabled: Bool) -> (UKServerUIPreferenceRow, UKServerUIPreferenceRow, UIWindow) {
        let reset = UKServerUIPreferenceRow(title: "Reset to Default", kind: .textButton, identifier: "reset-background-blur")
        reset.hint = "Sets Background Blur back to 50 percent."
        reset.isEnabled = resetEnabled
        let version = UKServerUIPreferenceRow(title: "Version", kind: .value, identifier: "app-version")
        version.value = "1.4.2 (318)"
        version.spokenValue = "1.4.2, build 318"
        version.hint = AboutSettingsModel.copyHint
        let holder = UKServerUIFittingView.wrapping(UKModuleListView(.thin, hasGlyphs: false, rows: [reset, version]))
        return (reset, version, host(holder, size: size))
    }

    private func drawnGlyphs(in row: UIView) -> [UIImageView] {
        HostedPage.descendants(of: row).compactMap { $0 as? UIImageView }.filter { $0.image != nil && !$0.isHidden }
    }

    /// UX: Reset is text only, at least 44 pt, dimmed when there is nothing to reset. Version is the canonical Version row of
    /// `.agents/design/settings-version-row.md`: the `info.circle` glyph, the title and the build text, with no chevron.
    func testResetIsTextOnlyAndVersionKeepsItsGlyphAtEveryFamilyWidth() {
        for size in Self.sizes {
            for enabled in [true, false] {
                let (reset, version, window) = preferenceRows(size, resetEnabled: enabled)
                defer { window.isHidden = true }
                for row in [reset, version] {
                    XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(size): a touch target tall: \(row.frame)")
                    XCTAssertFalse(row.row.rowContent.showsChevron, "\(size): a row that pushes nothing draws no chevron")
                }
                XCTAssertTrue(drawnGlyphs(in: reset).isEmpty, "\(size): Reset draws no glyph")
                XCTAssertNil(reset.row.rowContent.symbol)
                XCTAssertEqual(version.row.rowContent.symbol, "info.circle", "\(size): Version keeps the recorded glyph")
                XCTAssertEqual(drawnGlyphs(in: version).count, 1, "\(size): and draws it once")
                XCTAssertEqual(reset.row.alpha, enabled ? 1 : 0.5, "\(size): dimmed at the default value")
                XCTAssertTrue(HostedPage.labels(in: reset).contains("Reset to Default"))
                XCTAssertTrue(HostedPage.labels(in: version).contains("Version"))
                XCTAssertTrue(HostedPage.labels(in: version).contains("1.4.2 (318)"), "\(size): Version shows its build text")
            }
        }
    }

    /// Accessibility: Reset keeps its label, hint and button trait and is not enabled at the default value. Version reads the spoken
    /// version as its value, with the recorded hint, as a button.
    func testResetAndVersionKeepLabelsValuesHintsAndTraitsAtEveryFamilyWidth() {
        for size in Self.sizes {
            for enabled in [true, false] {
                let (reset, version, window) = preferenceRows(size, resetEnabled: enabled)
                defer { window.isHidden = true }
                XCTAssertEqual(reset.accessibilityLabel, "Reset to Default")
                XCTAssertEqual(reset.accessibilityHint, "Sets Background Blur back to 50 percent.")
                XCTAssertTrue(reset.accessibilityTraits.contains(.button))
                XCTAssertEqual(reset.accessibilityTraits.contains(.notEnabled), !enabled, "\(size): disabled at the default value")
                XCTAssertEqual(version.accessibilityLabel, "Version")
                XCTAssertEqual(version.accessibilityValue, "1.4.2, build 318", "\(size): VoiceOver reads the spoken version, not the build text")
                XCTAssertEqual(version.accessibilityHint, "Copies the version to the clipboard.")
                XCTAssertTrue(version.accessibilityTraits.contains(.button))
                for row in [reset, version] {
                    XCTAssertTrue(row.isAccessibilityElement)
                    XCTAssertGreaterThanOrEqual(row.convert(row.bounds, to: nil).height, 44, "\(size): the element is a touch target tall")
                }
            }
        }
    }
}
