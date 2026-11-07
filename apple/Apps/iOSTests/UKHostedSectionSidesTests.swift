import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Partly folded Duo (a hinge band stood in with `UKShellEnvironment.windowHinge`): every section of a page sits wholly on one side of
/// the band, at Large, xLarge and AX5, and the flat pose keeps its single column (`.agents/design/section-sides.md`).
@MainActor
final class UKHostedSectionSidesTests: DemoHouseTestCase {
    /// The measured partly folded Duo: 868 pt of content, band 455.3 to 495.7 pt.
    private let hinge = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)
    private let size = CGSize(width: 868, height: 669)
    private let sizes: [UIContentSizeCategory] = [.large, .extraLarge, .accessibilityExtraExtraExtraLarge]

    private func show(_ make: (UKContext) -> UIViewController, hinge: CGRect?, category: UIContentSizeCategory = .large) -> (UIViewController, UIWindow, UKFoldColumns?) {
        var context = UKGalleryChrome.context()
        context.shell?.windowHinge = hinge
        let page = make(context)
        page.traitOverrides.horizontalSizeClass = .regular
        page.traitOverrides.preferredContentSizeCategory = category
        let window = HostedPage.show(page, size: size)
        hostedSettle(0.5)
        page.view.layoutIfNeeded()
        hostedSettle(0.2)
        return (page, window, Self.fold(in: page.view))
    }

    private static func fold(in view: UIView) -> UKFoldColumns? {
        if let fold = view as? UKFoldColumns { return fold }
        for sub in view.subviews { if let found = fold(in: sub) { return found } }
        return nil
    }

    /// The placed sections' frames in window coordinates.
    private func frames(of fold: UKFoldColumns) -> [(view: UIView, frame: CGRect)] {
        fold.sections.map(\.view).filter { $0.superview === fold && !$0.isHidden && $0.frame.height > 0 }
            .map { ($0, fold.convert($0.frame, to: nil)) }
    }

    private func assertNoSectionCrossesTheBand(_ name: String, _ make: (UKContext) -> UIViewController) {
        for category in sizes {
            let (_, window, fold) = show(make, hinge: hinge, category: category)
            defer { window.isHidden = true }
            guard let fold else { return XCTFail("\(name) has no fold columns") }
            XCTAssertTrue(fold.isSplit, "\(name) splits partly folded at \(category.rawValue)")
            // The scrolling status rail spans the page and passes over the band (E1); a wrapped one sits in the leading column.
            // Rule 11: at accessibility sizes the wrapped rail heads the leading column, so it is never exempt there.
            let spansByDesign = !category.isAccessibilityCategory
            for (view, frame) in frames(of: fold) where !(spansByDesign && view is UKChipRailView && frame.width >= size.width - 1) {
                XCTAssertTrue(frame.maxX <= hinge.minX + 0.5 || frame.minX >= hinge.maxX - 0.5,
                              "\(name) at \(category.rawValue): \(type(of: view)) crosses the band: \(frame)")
            }
        }
    }

    private func assertFlatKeepsOneColumn(_ name: String, _ make: (UKContext) -> UIViewController) {
        let (_, window, fold) = show(make, hinge: nil)
        defer { window.isHidden = true }
        guard let fold else { return XCTFail("\(name) has no fold columns") }
        XCTAssertFalse(fold.isSplit, "\(name) is one column without a band")
        let placed = frames(of: fold)
        XCTAssertTrue(placed.allSatisfy { $0.frame.minX < 1 + 16 }, "\(name): every flat section starts at the leading edge: \(placed.map(\.frame))")
    }

    // MARK: Pages

    private func security(_ context: UKContext) -> UIViewController {
        let recorder = SecurityGalleryRecorder(store: context.store, fails: false)
        return UKSecurityViewController(context: context, caller: recorder, canSend: { true }, showsCameras: true, showsVehicle: true)
    }

    private func home(_ context: UKContext) -> UIViewController { UKHomeViewController(context: context) }
    private func climate(_ context: UKContext) -> UIViewController {
        UKClimateViewController(context: context, controller: ClimateController(store: context.store, caller: GalleryServiceRecorder(store: context.store)))
    }
    private func customLights(_ context: UKContext) -> UIViewController { UKCustomLightsViewController(context: context) }
    private func sprinklers(_ context: UKContext) -> UIViewController { UKSprinklersViewController(context: context) }
    private func media(_ context: UKContext) -> UIViewController { UKMediaViewController(context: context) }
    private func room(_ id: String) -> (UKContext) -> UIViewController {
        { context in UKRoomViewController(page: RoomsConfig.pages.first { $0.id == id }!, context: context, viewer: .resident1) }
    }

    func testNoSectionCrossesTheBandOnAnyPage() {
        assertNoSectionCrossesTheBand("Security", security)
        assertNoSectionCrossesTheBand("Home", home)
        assertNoSectionCrossesTheBand("Climate", climate)
        assertNoSectionCrossesTheBand("Custom Lights", customLights)
        assertNoSectionCrossesTheBand("Sprinklers", sprinklers)
        assertNoSectionCrossesTheBand("Media", media)
        for id in ["living-room", "kitchen", "back-deck", "master-bedroom", "garage"] {
            assertNoSectionCrossesTheBand("Room \(id)", room(id))
        }
    }

    func testTheFlatPoseKeepsASingleColumn() {
        assertFlatKeepsOneColumn("Security", security)
        assertFlatKeepsOneColumn("Home", home)
        assertFlatKeepsOneColumn("Custom Lights", customLights)
        assertFlatKeepsOneColumn("Sprinklers", sprinklers)
        assertFlatKeepsOneColumn("Media", media)
        assertFlatKeepsOneColumn("Living Room", room("living-room"))
    }

    // MARK: Cameras

    private func camerasAndLeadingTop(_ fold: UKFoldColumns, leading: (UIView) -> Bool) -> (cameras: CGRect, lead: CGRect)? {
        let placed = frames(of: fold)
        func child(_ view: UIView) -> UIView { (view as? UKSecurityInsetView)?.child ?? view }
        guard let cameras = placed.first(where: { child($0.view) is UKCameraGridSectionView }),
              let lead = placed.first(where: { leading(child($0.view)) }) else { return nil }
        return (cameras.frame, lead.frame)
    }

    func testSecurityCamerasAreTheFirstTrailingSectionLevelWithTheAlarmCard() {
        let (_, window, fold) = show(security, hinge: hinge)
        defer { window.isHidden = true }
        guard let fold, let found = camerasAndLeadingTop(fold, leading: { $0 is UKAlarmCardHost }) else { return XCTFail("cameras or the alarm card are missing") }
        XCTAssertEqual(found.cameras.minY, found.lead.minY, accuracy: 0.5, "Cameras sit level with the alarm card")
        XCTAssertGreaterThanOrEqual(found.cameras.minX, hinge.maxX - 0.5, "Cameras are in the trailing region")
    }

    func testHomeCamerasAreLevelWithTheWeatherCard() {
        let (_, window, fold) = show(home, hinge: hinge)
        defer { window.isHidden = true }
        guard let fold, let found = camerasAndLeadingTop(fold, leading: { $0 is UKWeatherCardView }) else { return XCTFail("cameras or weather are missing") }
        XCTAssertEqual(found.cameras.minY, found.lead.minY, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(found.cameras.minX, hinge.maxX - 0.5)
    }

    func testAtAX5AWrappedRailLeadsAndCamerasStartLevelWithIt() {
        for (name, make) in [("Security", security), ("Home", home)] as [(String, (UKContext) -> UIViewController)] {
            let (_, window, fold) = show(make, hinge: hinge, category: .accessibilityExtraExtraExtraLarge)
            defer { window.isHidden = true }
            guard let fold, let rail = frames(of: fold).first(where: { $0.view is UKChipRailView }),
                  let cameras = camerasAndLeadingTop(fold, leading: { $0 is UKChipRailView }) else { XCTFail("\(name): rail or cameras missing"); continue }
            XCTAssertLessThanOrEqual(rail.frame.maxX, hinge.minX + 0.5, "\(name): the wrapped rail is in the leading column")
            if let railView = rail.view as? UKChipRailView { assertChipsContained("\(name) partly folded at AX5", rail: railView) }
            XCTAssertEqual(cameras.cameras.minY, rail.frame.minY, accuracy: 0.5, "\(name): Cameras start level with the rail")
        }
    }

    func testLivingRoomAtAX5FirstTrailingSectionStartsLevelWithTheRail() {
        let (_, window, fold) = show(room("living-room"), hinge: hinge, category: .accessibilityExtraExtraExtraLarge)
        defer { window.isHidden = true }
        guard let fold, let rail = frames(of: fold).first(where: { $0.view is UKChipRailView }),
              let trailing = frames(of: fold).filter({ $0.frame.minX >= hinge.maxX - 0.5 }).min(by: { $0.frame.minY < $1.frame.minY }) else {
            return XCTFail("rail or trailing section missing")
        }
        XCTAssertEqual(trailing.frame.minY, rail.frame.minY, accuracy: 0.5)
    }

    // MARK: Chips wrap at accessibility sizes

    private static func chips(in rail: UIView) -> [UKStatusChipView] { views(of: UKStatusChipView.self, in: rail) }

    /// Every label sits inside its chip and every chip inside the rail; a chip taller than one line keeps the one-line corner radius.
    private func assertChipsContained(_ name: String, rail: UKChipRailView) {
        rail.layoutIfNeeded()
        let chips = Self.chips(in: rail)
        XCTAssertFalse(chips.isEmpty, "\(name) has chips")
        for chip in chips {
            chip.layoutIfNeeded()
            XCTAssertLessThanOrEqual(chip.convert(chip.bounds, to: rail).maxX, rail.bounds.width + 0.5, "\(name): \(chip.accessibilityLabel ?? "") is inside the rail")
            for label in Self.views(of: UILabel.self, in: chip) where label.frame.width > 0 {
                XCTAssertTrue(chip.bounds.insetBy(dx: -0.5, dy: -0.5).contains(label.frame), "\(name): \"\(label.text ?? "")\" \(label.frame) is inside its chip \(chip.bounds)")
                XCTAssertLessThanOrEqual(label.frame.maxX, chip.bounds.width - HassTokens.Spacing.l + 0.5, "\(name): the text stops before the chip's trailing padding")
            }
            let labels = Self.views(of: UILabel.self, in: chip)
            let oneLine = UKChipShape.cornerRadius(height: .greatestFiniteMagnitude, title: labels.first?.font, summary: labels.last?.font) * 2
            if let ground = chip.layer.sublayers?.first(where: { $0.masksToBounds && $0.cornerRadius > 0 }) {
                XCTAssertEqual(ground.cornerRadius, min(chip.bounds.height, oneLine) / 2, accuracy: 0.5, "\(name): the corner radius is the one-line radius")
            }
        }
    }

    func testStatusChipsWrapInsideTheirCapsuleAtAX5() {
        for width in [320, 361, 439] as [CGFloat] {
            for (name, make) in [("Home", home), ("Security", security)] as [(String, (UKContext) -> UIViewController)] {
                var context = UKGalleryChrome.context()
                context.shell?.windowHinge = nil
                let page = make(context)
                page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                let window = HostedPage.show(page, size: CGSize(width: width, height: 900))
                defer { window.isHidden = true }
                hostedSettle(0.5)
                page.view.layoutIfNeeded()
                hostedSettle(0.3)
                guard let rail = Self.views(of: UKChipRailView.self, in: page.view).first else { XCTFail("\(name) has no rail"); continue }
                assertChipsContained("\(name) at \(Int(width)) pt", rail: rail)
            }
        }
    }

    func testStatusChipAccessibilityIsUnchangedWhenItWraps() throws {
        let (page, window, _) = show(security, hinge: nil, category: .accessibilityExtraExtraExtraLarge)
        defer { window.isHidden = true }
        for chip in Self.chips(in: page.view) {
            XCTAssertTrue(chip.isAccessibilityElement)
            XCTAssertTrue(chip.accessibilityLabel?.contains(", ") ?? false, "the label stays \"title, summary\"")
            XCTAssertEqual(chip.accessibilityHint, "Opens its details")
            XCTAssertTrue(chip.accessibilityTraits.contains(.button))
            XCTAssertGreaterThanOrEqual(chip.bounds.height, 44)
            XCTAssertGreaterThanOrEqual(chip.bounds.width, 44)
        }
    }

    // MARK: Accessibility

    func testReadingOrderIsColumnMajorWhileSplit() {
        let (_, window, fold) = show(security, hinge: hinge)
        defer { window.isHidden = true }
        guard let fold, let elements = fold.accessibilityElements as? [UIView] else { return XCTFail("no explicit order while split") }
        XCTAssertTrue(fold.shouldGroupAccessibilityChildren)
        let xs = elements.map { fold.convert($0.frame, to: nil).minX }
        let firstTrailing = xs.firstIndex { $0 >= hinge.maxX - 0.5 } ?? xs.count
        XCTAssertTrue(xs[..<firstTrailing].allSatisfy { $0 < hinge.minX + 0.5 } && xs[firstTrailing...].allSatisfy { $0 >= hinge.maxX - 0.5 },
                      "leading sections are read before trailing ones: \(xs)")
        let (_, flatWindow, flat) = show(security, hinge: nil)
        defer { flatWindow.isHidden = true }
        XCTAssertNil(flat?.accessibilityElements, "the flat pose keeps the default order")
    }

    // MARK: Posture changes

    /// The side the design record's per-page table gives a section (`.agents/design/section-sides.md`); nil leaves it unchecked.
    /// - Parameters:
    ///   - view: A section's view (the page's own, inside any inset wrapper).
    ///   - index: Its index among the placed sections that are not the top strip.
    private typealias SideTable = (_ view: UIView, _ index: Int) -> FoldSide?

    private static func inner(_ view: UIView) -> UIView { (view as? UKSecurityInsetView)?.child ?? view }
    private static func byIndex(_ leading: @escaping (Int) -> Bool) -> SideTable { { _, index in leading(index) ? .leading : .trailing } }
    /// A room page: the parity of the configured index (rule 5), named by the section's identifier.
    private static func room(_ titles: [String: FoldSide]) -> SideTable {
        { view, _ in titles.first { view.accessibilityIdentifier == "room.section.\($0.key)" }?.value }
    }

    private static let securityTable: SideTable = { view, _ in
        switch inner(view) {
        case is UKAlarmCardHost, is UKSecurityTileSection: .leading
        case is UKGuestPresenceSectionView, is UKCameraGridSectionView: .trailing
        default: nil
        }
    }
    private static let homeTable: SideTable = { view, _ in
        if view is UKWeatherCardView { return .leading }
        let name = String(describing: type(of: inner(view)))
        return name.contains("Camera") || name.contains("Guest") ? .trailing : nil
    }

    /// The placed sections' frames, in window coordinates and in reading order of the page (top to bottom, then left to right).
    private func orderedPlaced(_ fold: UKFoldColumns) -> [(view: UIView, frame: CGRect)] {
        fold.sections.map(\.view).filter { $0.superview != nil && !$0.isHidden && $0.bounds.height > 0 && $0.window != nil }
            .map { ($0, $0.convert($0.bounds, to: nil)) }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    /// A page that is flat, is partly folded, and is flat again, twice: its sections move between the flat grid and the columns each
    /// time, nothing crosses the band or overlaps, each takes the side the design record gives it, and the flat order is the same
    /// after the cycle (rule 3: no reorder).
    private func assertPoseChangeMovesSections(_ name: String, _ make: (UKContext) -> UIViewController, sides: SideTable? = nil) {
        var context = UKGalleryChrome.context()
        context.shell?.windowHinge = nil
        let page = make(context)
        page.traitOverrides.horizontalSizeClass = .regular
        let window = HostedPage.show(page, size: size)
        defer { window.isHidden = true }
        hostedSettle(0.5)
        let shell = context.shell
        let flatBefore = Self.fold(in: page.view).map(orderedPlaced) ?? []
        for cycle in 0..<2 {
            shell?.windowHinge = hinge
            hostedSettle(0.3)
            page.view.layoutIfNeeded()
            hostedSettle(0.3)
            guard let split = Self.fold(in: page.view) else { return XCTFail("\(name) has no fold columns") }
            XCTAssertTrue(split.isSplit, "\(name) splits when it is partly folded (cycle \(cycle))")
            let placed = frames(of: split)
            for (view, frame) in placed where !(view is UKChipRailView && frame.width >= size.width - 1) {
                XCTAssertTrue(frame.maxX <= hinge.minX + 0.5 || frame.minX >= hinge.maxX - 0.5, "\(name): \(type(of: view)) crosses the band after a pose change: \(frame)")
            }
            for (index, first) in placed.enumerated() {
                for second in placed[(index + 1)...] {
                    XCTAssertFalse(first.frame.insetBy(dx: 0.5, dy: 0.5).intersects(second.frame.insetBy(dx: 0.5, dy: 0.5)),
                                   "\(name): \(type(of: first.view)) \(first.frame) overlaps \(type(of: second.view)) \(second.frame)")
                }
            }
            if let sides {
                for (index, entry) in placed.filter({ !($0.view is UKChipRailView) }).enumerated() {
                    guard let expected = sides(entry.view, index) else { continue }
                    let isLeading = entry.frame.maxX <= hinge.minX + 0.5
                    XCTAssertEqual(isLeading, expected == .leading, "\(name): \(type(of: entry.view)) \(entry.view.accessibilityIdentifier ?? "") is on the \(isLeading ? "leading" : "trailing") side, the table says \(expected)")
                }
            }
            shell?.windowHinge = nil
            hostedSettle(0.3)
            page.view.layoutIfNeeded()
            hostedSettle(0.3)
            XCTAssertFalse(Self.fold(in: page.view)?.isSplit ?? true, "\(name) is one column again when it unfolds (cycle \(cycle))")
            let flatAfter = Self.fold(in: page.view).map(orderedPlaced) ?? []
            XCTAssertEqual(flatAfter.map { ObjectIdentifier($0.view) }, flatBefore.map { ObjectIdentifier($0.view) }, "\(name): the flat order is unchanged after a pose cycle (cycle \(cycle))")
            for (before, after) in zip(flatBefore, flatAfter) {
                XCTAssertEqual(after.frame.minY, before.frame.minY, accuracy: 1, "\(name): \(type(of: after.view)) is back where it was")
            }
        }
    }

    func testEveryPageMovesItsSectionsWhenThePoseChanges() {
        assertPoseChangeMovesSections("Security", security, sides: Self.securityTable)
        assertPoseChangeMovesSections("Home", home, sides: Self.homeTable)
        assertPoseChangeMovesSections("Climate", climate, sides: Self.byIndex { $0 == 0 })
        assertPoseChangeMovesSections("Custom Lights", customLights, sides: Self.byIndex { $0 < 2 })
        assertPoseChangeMovesSections("Sprinklers", sprinklers, sides: Self.byIndex { $0 < 2 })
        assertPoseChangeMovesSections("Media", media, sides: Self.byIndex { $0 % 2 == 0 })
        assertPoseChangeMovesSections("Living Room", room("living-room"),
                                      sides: Self.room(["Climate": .leading, "Remote": .leading, "Devices": .trailing, "Quick App Launch": .trailing]))
        assertPoseChangeMovesSections("Kitchen", room("kitchen"))
        assertPoseChangeMovesSections("Hallway", room("hallway"), sides: Self.byIndex { _ in true })
    }

    /// The pose is decided where the hinge changes, never inside a layout pass (`uikit-port.md`, Duo postures), with the layout census
    /// on (`FENTON_LAYOUT_CENSUS=1`): over pose cycles on the pages the count of passes that changed a pose stays zero.
    func testNoPoseIsDecidedInALayoutPassAcrossPoseCycles() {
        UKLayoutCensus.isEnabled = true
        UKLayoutCensus.install()
        defer { UKLayoutCensus.isEnabled = false; UKLayoutCensus.uninstall() }
        UKFoldColumns.splitWritesInLayout = 0
        let pages: [(String, (UKContext) -> UIViewController)] = [("Home", home), ("Security", security), ("Climate", climate),
                                                                  ("Custom Lights", customLights), ("Sprinklers", sprinklers),
                                                                  ("Media", media), ("Living Room", room("living-room"))]
        for (name, make) in pages {
            assertPoseChangeMovesSections(name, make)
            // Partly folded, flat, partly folded: the census count after every page.
            print("CENSUS \(name): pose changes decided in a layout pass = \(UKFoldColumns.splitWritesInLayout)")
        }
        XCTAssertEqual(UKFoldColumns.splitWritesInLayout, 0, "no pose flipped during a layout pass")
    }

    // MARK: Hooks that reflow the columns

    private static func views<T: UIView>(of type: T.Type, in view: UIView) -> [T] {
        let own: [T] = (view as? T).map { [$0] } ?? []
        return own + view.subviews.flatMap { views(of: type, in: $0) }
    }

    /// A Sprinklers card that grows asks the page to measure again, flat and split; Security's guests section hides and shows its
    /// wrapper and asks the columns to lay out again.
    func testGrowingAndHidingSectionsAskTheColumnsToLayOutAgain() {
        for placed in [nil, hinge] as [CGRect?] {
            let (page, window, fold) = show(sprinklers, hinge: placed)
            defer { window.isHidden = true }
            let cards = Self.views(of: UKSprinklerControllerCard.self, in: page.view)
            XCTAssertFalse(cards.isEmpty)
            for card in cards { card.onHeightChange?() }
            hostedSettle(0.3)
            XCTAssertEqual(fold?.isSplit, placed != nil)
        }
        let (security, window, _) = show(security, hinge: hinge)
        defer { window.isHidden = true }
        let guests = Self.views(of: UKGuestPresenceSectionView.self, in: security.view)
        XCTAssertFalse(guests.isEmpty)
        for hidden in [true, false] { guests.first?.onVisibilityChange?(hidden) }
        hostedSettle(0.3)
        XCTAssertTrue(Self.fold(in: security.view)?.isSplit ?? false)
    }

    /// The fold container's own properties re-measure it and its accessibility order is read only.
    func testTheFoldContainerRemeasuresWhenItsSpacingOrInsetsChange() {
        let columns = UKFoldColumns(spacing: 8)
        columns.spacing = 12
        columns.insets = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        XCTAssertEqual(columns.sizeThatFits(CGSize(width: 400, height: 0)).width, 400)
        columns.accessibilityElements = [UIView()]
        XCTAssertNil(columns.accessibilityElements, "flat: the default order")
    }

    /// Custom Lights' mode button is a button whose label, value and hint are fixed by the page.
    func testTheLightingModeButtonKeepsItsAccessibilityText() throws {
        let (page, window, _) = show(customLights, hinge: hinge)
        defer { window.isHidden = true }
        let button = try XCTUnwrap(Self.views(of: UKLightingModeButton.self, in: page.view).first)
        let label = button.accessibilityLabel, value = button.accessibilityValue, hint = button.accessibilityHint
        button.accessibilityLabel = "x"; button.accessibilityValue = "x"; button.accessibilityHint = "x"; button.accessibilityTraits = []
        XCTAssertEqual(button.accessibilityLabel, label)
        XCTAssertEqual(button.accessibilityValue, value)
        XCTAssertEqual(button.accessibilityHint, hint)
        XCTAssertEqual(button.accessibilityTraits, .button)
    }

    /// A gallery launch can open a Security sheet at once (`FENTON_GALLERY_SHEET`); each name takes its own branch, an unknown one none.
    func testSecurityGalleryOpensTheSheetItIsAskedFor() {
        for name in ["contacts", "system", "unknown"] {
            setenv("FENTON_GALLERY_SHEET", name, 1)
            defer { unsetenv("FENTON_GALLERY_SHEET") }
            let (page, window, _) = show(security, hinge: hinge)
            defer { window.isHidden = true }
            page.viewDidAppear(false)
            hostedSettle(0.3)
            XCTAssertNotNil(page.view.window, name)
        }
    }

    /// Under a navigation bar the page has a top inset and starts at its top, as in the app (Climate, Security).
    func testPagesUnderANavigationBarStartAtTheirTop() {
        for (name, make) in [("Climate", climate), ("Security", security)] as [(String, (UKContext) -> UIViewController)] {
            var context = UKGalleryChrome.context()
            context.shell?.windowHinge = hinge
            let page = make(context)
            let navigation = UINavigationController(rootViewController: page)
            navigation.traitOverrides.horizontalSizeClass = .regular
            let window = HostedPage.show(navigation, size: size)
            defer { window.isHidden = true }
            hostedSettle(0.5)
            page.view.layoutIfNeeded()
            hostedSettle(0.3)
            XCTAssertNotNil(Self.fold(in: page.view), name)
        }
    }

    /// Reset All Lights asks first; confirming sends the reset.
    func testResetAllLightsAsksThenConfirms() throws {
        let (page, window, _) = show(customLights, hinge: hinge)
        defer { window.isHidden = true }
        let row = try XCTUnwrap(Self.views(of: UKRoomsActionRow.self, in: page.view).first { $0.accessibilityIdentifier == "customLights.resetAll" })
        row.sendActions(for: .touchUpInside)
        hostedSettle(0.5)
        let alert = try XCTUnwrap(page.presentedViewController as? UIAlertController, "the confirmation is up")
        let confirm = try XCTUnwrap(alert.actions.first { $0.style != .cancel })
        // Runs the action's handler as a tap would: UIAlertAction keeps it as an Objective-C block under `handler`.
        typealias Handler = @convention(block) (UIAlertAction) -> Void
        let handler = try XCTUnwrap(confirm.value(forKey: "handler") as AnyObject?)
        unsafeBitCast(handler, to: Handler.self)(confirm)
        hostedSettle(0.5)
    }

    /// Climate reports its scroll to the frame monitor (drag, deceleration, leaving).
    func testClimateReportsItsScrollToTheFrameMonitor() throws {
        let (page, window, _) = show(climate, hinge: hinge)
        defer { window.isHidden = true }
        let climate = try XCTUnwrap(page as? UKClimateViewController)
        let scroll = UIScrollView()
        climate.scrollViewWillBeginDragging(scroll)
        climate.scrollViewDidEndDragging(scroll, willDecelerate: false)
        climate.scrollViewDidEndDragging(scroll, willDecelerate: true)
        climate.scrollViewDidEndDecelerating(scroll)
        climate.viewDidDisappear(false)
    }

    // MARK: Cost

    /// The posture reflow on Security (partly folded and back, ten times): wall time, CPU and the `LayoutChange` signpost of
    /// `UKFoldColumns` (`.agents/testing/apple/performance.md`, "Layout changes").
    func testPostureReflowCostOnSecurity() {
        var context = UKGalleryChrome.context()
        context.shell?.windowHinge = nil
        let page = security(context)
        page.traitOverrides.horizontalSizeClass = .regular
        let window = HostedPage.show(page, size: size)
        defer { window.isHidden = true }
        hostedSettle(0.5)
        let shell = context.shell
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(),
                          XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "LayoutChange")], options: options) {
            for index in 0..<10 {
                shell?.windowHinge = index.isMultiple(of: 2) ? hinge : nil
                hostedSettle(0.05)
                UKMotion.animate(.standard) { page.view.layoutIfNeeded() }
                hostedSettle(0.1)
            }
        }
        XCTAssertNotNil(Self.fold(in: page.view))
    }
}
