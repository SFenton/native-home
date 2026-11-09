import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A view that reports a fixed size to the layout views that measure their children.
private final class FixedChip: UIView {
    let fixed: CGSize
    init(_ size: CGSize) {
        fixed = size
        super.init(frame: CGRect(origin: .zero, size: size))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func sizeThatFits(_ size: CGSize) -> CGSize { fixed }
}

private enum Section: String, CaseIterable, Identifiable {
    case one, two, three
    var id: String { rawValue }
}

/// The list row (accessory swaps, the tap target, pending values, the check variant, the row button), the modal tab bar's text form,
/// the pinned bar on the top edge, the layout views' measuring and right-to-left mirroring, and the tile paint.
@MainActor
final class UKHostedDesignRowTests: XCTestCase {
    private func show(_ view: UIView, size: CGSize = CGSize(width: 393, height: 80), host: UIViewController = UIViewController()) -> UIWindow {
        let window = HostedPage.show(host)
        view.frame = CGRect(origin: CGPoint(x: 0, y: 100), size: size)
        host.view.addSubview(view)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return window
    }

    // MARK: Row

    func testACentredActionShowsItsBusyTitleAndAnArcInPlaceOfTheTitleWhileTheServerWaits() {
        let idle = UKRowContent.centeredAction("Sign Out", ink: .systemRed, busyTitle: "Signing Out")
        XCTAssertEqual(idle.title, "Sign Out")
        XCTAssertTrue(idle.isCentered)
        XCTAssertNil(idle.leadingView)
        let busy = UKRowContent.centeredAction("Sign Out", ink: .systemRed, busyTitle: "Signing Out", isBusy: true)
        XCTAssertEqual(busy.title, "Signing Out")
        XCTAssertNotNil(busy.leadingView, "the inline arc stands where the title was")
        XCTAssertNotEqual(idle, busy)
        let unnamed = UKRowContent.centeredAction("Save", ink: .label, isBusy: true)
        XCTAssertEqual(unnamed.title, "Save", "without a busy title the title stays")
    }

    func testRowContentIsEqualFieldForFieldAndAnyDifferenceMakesItNew() {
        func full() -> UKRowContent {
            var content = UKRowContent("Title", subtitle: "Sub", value: "7", symbol: "bolt", glyph: .red, subtitleInk: .blue, glyphOpacity: 0.5,
                                       subtitleIsValue: true, showsChevron: true, style: .grouped)
            content.titleInk = .green
            content.titleWeight = .bold
            content.valueInk = .orange
            content.identifier = "row.x"
            content.verticalPadding = 3
            content.minHeight = 50
            content.alignsLeadingToTop = true
            content.spokenValue = "seven"
            content.spokenLabel = "Title spoken"
            content.isCentered = true
            content.horizontalPadding = 9
            content.subtitleStyle = .caption1
            content.glyphStyle = .title3
            content.valueWeight = .semibold
            content.hint = "Does a thing"
            return content
        }
        XCTAssertEqual(full(), full())
        var other = full()
        other.hint = "Other"
        XCTAssertNotEqual(full(), other)
        other = full()
        other.valueWeight = .light
        XCTAssertNotEqual(full(), other)
        other = full()
        other.glyphStyle = .body
        XCTAssertNotEqual(full(), other)
        other = full()
        other.horizontalPadding = 1
        XCTAssertNotEqual(full(), other)
        other = full()
        other.spokenLabel = "x"
        XCTAssertNotEqual(full(), other)
        XCTAssertTrue(full().hasLeading)
        XCTAssertFalse(UKRowContent("Plain").hasLeading)
    }

    func testSwappingTheAccessoryRemovesTheOldOneAndAddsTheNew() {
        let first = UISwitch()
        let second = UIButton(type: .system)
        let row = UKRowView(.init("Lamp"), accessory: first)
        let window = show(row)
        defer { window.isHidden = true }
        XCTAssertTrue(first.isDescendant(of: row))
        row.update(.init("Lamp"), accessory: second)
        row.layoutIfNeeded()
        XCTAssertNil(first.superview, "the old accessory leaves the row")
        XCTAssertTrue(second.isDescendant(of: row))
        XCTAssertTrue(row.accessory === second)
        row.setAccessory(second, trailingInset: 4)
        XCTAssertTrue(row.accessory === second, "the same accessory stays")
        XCTAssertEqual(row.accessoryTrailingInset, 4)
        row.setAccessory(nil)
        XCTAssertNil(second.superview)
    }

    func testABodyViewSitsUnderTheRowAndSetBodyIgnoresTheSameViewTwice() {
        let row = UKRowView(.init("Volume", value: "40%"))
        let window = show(row, size: CGSize(width: 393, height: 120))
        defer { window.isHidden = true }
        let slider = UISlider()
        row.setBody(slider)
        row.setBody(slider)
        row.layoutIfNeeded()
        XCTAssertTrue(row.bodyView === slider)
        XCTAssertGreaterThan(slider.frame.minY, 20, "the body sits under the title line")
        let elements = row.accessibilityElements ?? []
        XCTAssertTrue(elements.contains { ($0 as AnyObject) === slider }, "VoiceOver visits the body's control")
        row.setBody(nil)
        XCTAssertNil(slider.superview)
    }

    func testTheCheckVariantShowsItsStateDimmedOrNotAndDropsTheSymbol() {
        var content = UKRowContent("Milk", symbol: "cart")
        content.check = .init(isChecked: false, checkedTint: .systemGreen, uncheckedTint: .systemGray, dimmed: false)
        let row = UKRowView(content)
        let window = show(row)
        defer { window.isHidden = true }
        row.setChecked(true, checkedTint: .systemGreen, uncheckedTint: .systemGray, dimmed: true, animated: false)
        XCTAssertEqual(row.rowContent.check?.isChecked, true)
        XCTAssertEqual(row.rowContent.check?.dimmed, true)
        XCTAssertNil(row.rowContent.symbol, "the check replaces the symbol")
        let glyph = HostedPage.descendants(of: row).compactMap { $0 as? UIImageView }.first { $0.image != nil }
        XCTAssertEqual(glyph?.alpha ?? 1, CGFloat(CheckRowMetrics.dimmedGlyphOpacity), accuracy: 0.001)
        row.setChecked(false, checkedTint: .systemGreen, uncheckedTint: .systemGray, animated: true)
        XCTAssertEqual(glyph?.alpha, 1)
        XCTAssertEqual(glyph?.tintColor, .systemGray)
        // Restyling from content that already carries a check state draws it too.
        var checked = content
        checked.check = .init(isChecked: true, checkedTint: .systemGreen, uncheckedTint: .systemGray, dimmed: true)
        row.update(checked)
        XCTAssertEqual(glyph?.alpha ?? 1, CGFloat(CheckRowMetrics.dimmedGlyphOpacity), accuracy: 0.001)
        XCTAssertEqual(glyph?.tintColor, .systemGreen)
    }

    func testAPendingValueShowsTheBarAndIsNotSpokenUntilStateArrives() {
        let content = UKRowContent("Temperature", subtitle: "21 degrees", subtitleIsValue: true)
        let row = UKRowView(content)
        let window = show(row)
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.descendants(of: row).contains { $0 is UKPendingValueBar } == false)
        row.valuesPending = true
        row.layoutIfNeeded()
        XCTAssertTrue(HostedPage.descendants(of: row).contains { $0 is UKPendingValueBar }, "a pending value draws the placeholder bar")
        let text = row.accessibilityElements?.first as? UIView
        XCTAssertEqual(text?.accessibilityLabel, "Temperature", "the unknown value is not read out")
        row.valuesPending = false
        row.layoutIfNeeded()
        XCTAssertEqual((row.accessibilityElements?.first as? UIView)?.accessibilityLabel, "Temperature, 21 degrees")
    }

    func testARowCardDrawsTheGroupedGroundAndRoundsItsCorners() {
        let row = UKRowView(.init("Card"))
        row.drawsCard = true
        XCTAssertEqual(row.backgroundColor, .secondarySystemGroupedBackground)
        XCTAssertEqual(row.layer.cornerRadius, HassTokens.Radius.tile)
        row.cardColor = .systemPink
        XCTAssertEqual(row.backgroundColor, .systemPink)
        row.drawsCard = false
        XCTAssertNil(row.backgroundColor)
        XCTAssertEqual(row.layer.cornerRadius, 0)
    }

    func testATapTargetTakesTheTouchesLeftOfTheAccessoryAndTheAccessoryKeepsItsOwn() {
        let accessory = UIButton(type: .system)
        accessory.setTitle("Edit", for: .normal)
        let row = UKRowView(.init("Task", subtitle: "Due today"), accessory: accessory)
        let target = UIControl()
        let window = show(row)
        defer { window.isHidden = true }
        row.installTapTarget(target)
        row.installTapTarget(target)
        row.layoutIfNeeded()
        let onText = CGPoint(x: 40, y: row.bounds.midY)
        XCTAssertTrue(row.hitTest(onText, with: nil) === target, "the text area is the target's")
        let onAccessory = row.convert(CGPoint(x: accessory.bounds.midX, y: accessory.bounds.midY), from: accessory)
        XCTAssertTrue(row.hitTest(onAccessory, with: nil) === accessory, "the accessory keeps its own touch")
        target.isHighlighted = true
        XCTAssertEqual(row.alpha, 1)
        XCTAssertEqual((row.accessibilityElements?.first as? UIControl), target, "the tap target is the element behind the text")
    }

    func testARowButtonIsOneButtonNamedByTitleAndSubtitleThatTapsAndGoesNotEnabled() {
        var taps = 0
        let row = UKRowView(.init("Front Door", subtitle: "Locked", value: "9"))
        let button = UKRowButton(row) { taps += 1 }
        let window = show(button)
        defer { window.isHidden = true }
        button.surface = .sheet
        XCTAssertEqual(row.surface, .sheet)
        XCTAssertEqual(button.surface, .sheet)
        XCTAssertEqual(button.accessibilityLabel, "Front Door, Locked")
        XCTAssertEqual(button.accessibilityValue, "9")
        XCTAssertEqual(button.accessibilityTraits, .button)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(taps, 1)
        button.isEnabled = false
        XCTAssertTrue(button.accessibilityTraits.contains(.notEnabled))
        button.isEnabled = true
        let highlight = button.subviews.first
        button.isHighlighted = true
        XCTAssertEqual(highlight?.alpha ?? 0, 0.10, accuracy: 0.001, "held rows take a light highlight")
        button.isHighlighted = true
        button.isHighlighted = false
        hostedSettle(0.4)
        XCTAssertEqual(highlight?.alpha, 0)
        button.accessibilityLabel = "ignored"
        button.accessibilityValue = "ignored"
        button.accessibilityTraits = []
        XCTAssertEqual(button.accessibilityLabel, "Front Door, Locked", "the label always follows the row")
        let pending = UKRowView(.init("Temp", subtitle: "21", subtitleIsValue: true))
        pending.valuesPending = true
        XCTAssertEqual(UKRowButton(pending).accessibilityLabel, "Temp")
    }

    // MARK: Modal tab bar and pinned bar

    func testATabBarWithoutSymbolsDrawsTextSegmentsAndSelectsOnTap() {
        var chosen: Section?
        let bar = UKModalTabBar(tabs: Section.allCases, label: "Sections", title: { $0.rawValue.capitalized }, selection: .one, identifier: "tabs") { chosen = $0 }
        let window = show(bar.inset(), size: CGSize(width: 393, height: 60))
        defer { window.isHidden = true }
        let control = HostedPage.descendants(of: bar).compactMap { $0 as? UISegmentedControl }.first
        XCTAssertEqual(control?.numberOfSegments, 3)
        XCTAssertEqual(control?.titleForSegment(at: 1), "Two", "titles, not icons")
        XCTAssertEqual(control?.accessibilityLabel, "Sections")
        XCTAssertEqual(control?.selectedSegmentIndex, 0)
        control?.selectedSegmentIndex = 2
        control?.sendActions(for: .valueChanged)
        XCTAssertEqual(chosen, .three)
        XCTAssertEqual(bar.selection, .three)
        bar.selection = .two
        XCTAssertEqual(control?.selectedSegmentIndex, 1, "a selection set from outside moves the segment")
    }

    func testAPinnedBarOnTheTopEdgeInsetsTheContentByItsHeight() {
        let content = UIViewController()
        let scroll = UIScrollView()
        content.view.addSubview(scroll)
        let bar = UIView()
        bar.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let pinned = UKPinnedBarViewController(content: content, bar: bar, scrollView: scroll, edge: .top, spacing: 6, barMaterial: true)
        let window = HostedPage.show(pinned)
        defer { window.isHidden = true }
        pinned.view.layoutIfNeeded()
        hostedSettle(0.3)
        XCTAssertEqual(content.additionalSafeAreaInsets.top, 54, accuracy: 0.5, "bar height plus spacing")
        XCTAssertEqual(content.additionalSafeAreaInsets.bottom, 0)
        XCTAssertTrue(bar.isDescendant(of: pinned.view))
    }

    // MARK: Layout views

    func testAFlowViewMirrorsItsRowsInARightToLeftLayoutAndMeasuresItsHeight() {
        let flow = UKFlowView(spacing: 10)
        flow.semanticContentAttribute = .forceRightToLeft
        let chips = (0..<3).map { _ in FixedChip(CGSize(width: 100, height: 30)) }
        flow.setChildren(chips)
        let window = show(flow, size: CGSize(width: 250, height: 100))
        defer { window.isHidden = true }
        XCTAssertEqual(chips[0].frame.maxX, 250, accuracy: 0.5, "the first chip starts at the trailing... leading edge, the right")
        XCTAssertEqual(chips[1].frame.maxX, 140, accuracy: 0.5)
        XCTAssertEqual(chips[2].frame.minY, 40, accuracy: 0.5, "the third wraps")
        XCTAssertEqual(flow.sizeThatFits(CGSize(width: 250, height: 0)).height, 70, accuracy: 0.5)
        XCTAssertEqual(flow.intrinsicContentSize.height, 70, accuracy: 0.5)
        flow.spacing = 0
        flow.layoutIfNeeded()
        XCTAssertEqual(chips[1].frame.maxX, 150, accuracy: 0.5, "a smaller gap moves the chips")
    }

    func testAChipRailScrollsAtNormalSizesWrapsAtAccessibilitySizesAndMirrorsForRightToLeft() {
        let rail = UKChipRailView()
        rail.semanticContentAttribute = .forceRightToLeft
        let chips = (0..<4).map { _ in FixedChip(CGSize(width: 120, height: 32)) }
        rail.setChips(chips)
        let window = show(rail, size: CGSize(width: 300, height: 40))
        defer { window.isHidden = true }
        XCTAssertEqual(rail.sizeThatFits(CGSize(width: 300, height: 0)).height, 32, "one row of the tallest chip")
        XCTAssertEqual(rail.intrinsicContentSize.height, 32)
        let scroll = HostedPage.descendants(of: rail).compactMap { $0 as? UIScrollView }.first
        XCTAssertNotNil(scroll)
        XCTAssertGreaterThan(scroll?.contentSize.width ?? 0, 300, "four chips overflow the rail")
        XCTAssertGreaterThan(chips[0].frame.minX, chips[3].frame.minX, "in right-to-left the first chip is rightmost")
        rail.hinge = CGRect(x: 150, y: 0, width: 20, height: 800)
        rail.hinge = CGRect(x: 150, y: 0, width: 20, height: 800)
        rail.layoutIfNeeded()
        XCTAssertLessThanOrEqual(scroll?.frame.width ?? 0, 300)
    }

    func testASectionHeaderPutsTheDetailBesideTheTitleAndMirrorsIt() {
        let header = UKPageSectionHeaderView("Rooms", detail: "4 lights")
        header.semanticContentAttribute = .forceRightToLeft
        let window = show(header, size: CGSize(width: 320, height: 40))
        defer { window.isHidden = true }
        let labels = HostedPage.descendants(of: header).compactMap { $0 as? UILabel }
        let title = labels.first { $0.text == "Rooms" }
        let detail = labels.first { $0.text == "4 lights" }
        XCTAssertNotNil(title)
        XCTAssertEqual(title?.textAlignment, .right)
        XCTAssertEqual(detail?.textAlignment, .left)
        XCTAssertGreaterThan(title?.frame.minX ?? 0, detail?.frame.minX ?? 1000, "mirrored: the title is on the right")
        XCTAssertEqual(header.sizeThatFits(CGSize(width: 320, height: 0)).height, header.intrinsicContentSize.height)
        header.configure(title: "Rooms", detail: nil)
    }

    func testAColumnStacksVisibleViewsWithSpacingAndInsetsAndReplacesThemOnSetViews() {
        let column = UKColumnView(spacing: 4, insets: .zero)
        let first = FixedChip(CGSize(width: 50, height: 20)), second = FixedChip(CGSize(width: 50, height: 30)), hidden = FixedChip(CGSize(width: 50, height: 99))
        hidden.isHidden = true
        column.setViews([first, hidden, second])
        let window = show(column, size: CGSize(width: 200, height: 100))
        defer { window.isHidden = true }
        XCTAssertEqual(column.sizeThatFits(CGSize(width: 200, height: 0)).height, 54, accuracy: 0.5, "20 + 4 + 30, the hidden view takes no room")
        column.spacing = 10
        column.insets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        column.layoutIfNeeded()
        XCTAssertEqual(second.frame.minY, 35, accuracy: 0.5)
        let third = FixedChip(CGSize(width: 50, height: 10))
        column.setViews([third])
        XCTAssertNil(first.superview, "replaced views leave")
        XCTAssertEqual(column.gridHeight(forWidth: 200), 20, accuracy: 0.5)
    }

    // MARK: Tile paint

    private func input(_ style: TileFaceStyle, level: Double? = nil, flat: Bool = false, enabled: Bool = true, unavailable: Bool = false) -> UKTilePaintInput {
        UKTilePaintInput(style: style, surface: .page, appearance: .dark, finish: .tintedGlass, tint: .systemTeal, tintGlyph: .systemTeal, wash: nil,
                         level: level, levelTint: nil, isEnabled: enabled, isUnavailable: unavailable, reduceTransparency: false,
                         traits: UITraitCollection(userInterfaceStyle: .dark), isFlat: flat)
    }

    func testAFlatTintedTileDrawsNoSheenRimOrStroke() {
        let flat = UKTilePaint.make(input(.tinted, flat: true))
        XCTAssertNil(flat.stroke)
        XCTAssertTrue(flat.sheen == .none)
        XCTAssertTrue(flat.rim == .none)
        XCTAssertNil(UKTileFinishImage.image(size: CGSize(width: 80, height: 80), scale: 2, radius: 14, paint: flat), "nothing to draw")
        let live = UKTilePaint.make(input(.tinted))
        XCTAssertNotNil(live.stroke)
        XCTAssertFalse(live == flat)
        XCTAssertTrue(live == UKTilePaint.make(input(.tinted)))
    }

    func testATintedTilesStrokeFadesWhenDisabledAndWhenUnavailable() {
        func alpha(_ input: UKTilePaintInput) -> CGFloat { UKTilePaint.make(input).stroke?.cgColor.alpha ?? -1 }
        let enabled = alpha(input(.tinted))
        let disabled = alpha(input(.tinted, enabled: false))
        let unavailable = alpha(input(.tinted, enabled: false, unavailable: true))
        XCTAssertEqual(disabled, enabled / 2, accuracy: 0.01)
        XCTAssertEqual(unavailable, disabled / 2, accuracy: 0.01)
    }

    func testAFilledTilesProgressIsALightBandOnDarkInkFamiliesAndAShadeOnWhiteInkOnes() {
        let light = UKTilePaint.make(input(.filled(.lights), level: 0.5))
        XCTAssertEqual(light.band?.fraction ?? 0, 0.5, accuracy: 0.001)
        XCTAssertNil(light.shade)
        let heat = UKTilePaint.make(input(.filled(.heating), level: 0.25))
        XCTAssertEqual(heat.shade?.fraction ?? 0, 0.75, accuracy: 0.001, "the part progress has not reached")
        XCTAssertNil(heat.band)
        let none = UKTilePaint.make(input(.filled(.heating), level: 0))
        XCTAssertNil(none.shade)
        XCTAssertFalse(heat == none)
    }

    func testARimOnlyFinishStillDrawsAnImage() {
        var paint = UKTilePaint.make(input(.off))
        paint.sheen = .none
        let image = UKTileFinishImage.image(size: CGSize(width: 60, height: 40), scale: 2, radius: 12, paint: paint)
        XCTAssertNotNil(image, "the hairline alone is an image")
        XCTAssertEqual(image?.size.width ?? 0, 60, accuracy: 0.5)
        XCTAssertTrue(UKTileFinishImage.image(size: CGSize(width: 60, height: 40), scale: 2, radius: 12, paint: paint) === image, "equal tiles share one image")
    }
}
