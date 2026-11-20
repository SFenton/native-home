import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Sections that take sides (sh.fold-sides@1)

/// Hosted UX and accessibility checks for a Studio page that uses `foldSides` (the gallery's composition: a status rail with chips, a note that spans the top and four sections), each run at
/// the iPhone, iPhone Duo and iPad windows. The fold is injected through the shell's `windowHinge`, the way the shell publishes it, so the hosted run needs no
/// Duo. On the iPhone's portrait window and the folded Duo's outer display nothing splits, which is the contract there.
@MainActor
final class ServerUIFoldSidesHostedTests: XCTestCase {
    private let ids = ["s1", "s2", "s3", "s4"]
    /// Window sizes of the three families: the iPhone, the folded Duo's outer display, and the iPad and unfolded Duo in landscape (the measured partly folded window).
    private let families: [(name: String, size: CGSize, regular: Bool, splits: Bool)] = [
        ("iPhone", CGSize(width: 393, height: 852), false, false),
        ("iPhone Duo folded", CGSize(width: 466, height: 678), false, false),
        ("iPad and unfolded Duo", CGSize(width: 868, height: 669), true, true),
    ]
    private let band = CGRect(x: 428, y: 0, width: 40.4, height: 669)

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func hosted(size: CGSize, regular: Bool, hinge: CGRect? = nil, rightToLeft: Bool = false,
                        publication override: ServerUICompositionPublication? = nil) throws -> (UKServerUIPage, UIWindow, UKShellEnvironment) {
        let shell = UKShellEnvironment()
        shell.windowHinge = hinge
        var context = UKContext(store: EntityStore())
        context.shell = shell
        let publication = try override ?? ServerUICompositionPublication.decode(Data(UKFoldSidesGalleryFixture.envelope.utf8))
        let host = try UKServerUIRenderer(publication: publication, context: context, backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host, size: size)
        window.traitOverrides.horizontalSizeClass = regular ? .regular : .compact
        if rightToLeft { window.traitOverrides.layoutDirection = .rightToLeft }
        HostedPage.wait(0.3)
        let root = try ServerUIRendererFixture.root(host)
        root.view.layoutIfNeeded()
        return (root, window, shell)
    }

    private func frames(_ page: UKServerUIPage) throws -> [CGRect] {
        try ids.map { id in
            let view = try XCTUnwrap(page.nodes[id]?.view, id)
            return view.convert(view.bounds, to: nil)
        }
    }

    private func frame(_ page: UKServerUIPage, _ id: String) throws -> CGRect {
        let view = try XCTUnwrap(page.nodes[id]?.view, id)
        return view.convert(view.bounds, to: nil)
    }

    private func settle(_ page: UKServerUIPage) {
        HostedPage.wait(1.0)
        page.view.layoutIfNeeded()
    }

    // MARK: Flat

    func testFlatDrawsOneColumnOnEveryFamily() throws {
        for family in families {
            let (page, _, _) = try hosted(size: family.size, regular: family.regular)
            let flat = try frames(page)
            XCTAssertTrue(page.drawsFoldSides, family.name)
            XCTAssertEqual(Set(flat.map { Int($0.minX) }).count, 1, "\(family.name): one column")
            XCTAssertEqual(flat.map(\.minY), flat.map(\.minY).sorted(), "\(family.name): in document order")
            XCTAssertNil(page.body?.content.accessibilityElements, "\(family.name): the default reading order flat")
        }
    }

    func testAPageThatDoesNotUseSidesDrawsTheSameFramesAsTodayOnEveryFamily() throws {
        // The same composition without the switch (and without the id it needs) is the plain column the page drew before.
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(UKFoldSidesGalleryFixture.envelope.utf8))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/layout/foldSides", to: .null)
        guard case .object(var object) = json["document"]?["pages"]?.array?[0]["layout"] ?? .null else { return XCTFail("no layout") }
        object["foldSides"] = nil
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/layout", to: .object(object))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).filter { $0 != .string("sh.fold-sides@1") }
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components/1/layout", to: .object(["span": .number(1)]))
        let plain = try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
        for family in families {
            let (sided, _, _) = try hosted(size: family.size, regular: family.regular)
            let (today, _, _) = try hosted(size: family.size, regular: family.regular, publication: plain)
            XCTAssertTrue(sided.drawsFoldSides && !today.drawsFoldSides, family.name)
            for (a, b) in zip(try frames(sided), try frames(today)) {
                XCTAssertEqual(a.minX, b.minX, accuracy: 0.5, family.name)
                XCTAssertEqual(a.minY, b.minY, accuracy: 0.5, family.name)
                XCTAssertEqual(a.width, b.width, accuracy: 0.5, family.name)
                XCTAssertEqual(a.height, b.height, accuracy: 0.5, family.name)
            }
        }
    }

    // MARK: Partly folded

    func testPartlyFoldedPutsEverySectionWhollyOnOneSideAndFlatComesBack() throws {
        for family in families {
            let (page, _, shell) = try hosted(size: family.size, regular: family.regular)
            let flat = try frames(page)
            shell.windowHinge = band
            settle(page)
            let partly = try frames(page)
            if family.splits {
                for frame in partly { XCTAssertTrue(frame.maxX <= band.minX + 0.5 || frame.minX >= band.maxX - 0.5, "\(family.name): no section meets the band") }
                XCTAssertLessThanOrEqual(partly[0].maxX, band.minX + 0.5)
                XCTAssertLessThanOrEqual(partly[2].maxX, band.minX + 0.5)
                XCTAssertGreaterThanOrEqual(partly[1].minX, band.maxX - 0.5)
                XCTAssertGreaterThanOrEqual(partly[3].minX, band.maxX - 0.5)
                XCTAssertEqual(partly[1].minY, partly[0].minY, accuracy: 1, "the sides start level")
                XCTAssertGreaterThan(partly[2].minY, partly[0].minY)
                XCTAssertGreaterThan(partly[3].minY, partly[1].minY)
                XCTAssertTrue(page.body?.content is UKFoldColumns, "one container in both poses")
                let spoken = (page.body?.content.accessibilityElements ?? []).compactMap { ($0 as? UIView)?.accessibilityIdentifier }
                XCTAssertEqual(spoken.filter { ids.contains($0) }, ["s1", "s3", "s2", "s4"], "column-major while split")
            } else {
                for (a, b) in zip(partly, flat) {
                    XCTAssertEqual(a.minX, b.minX, accuracy: 0.5, "\(family.name): a window that cannot split stays one column")
                    XCTAssertEqual(a.minY, b.minY, accuracy: 0.5, family.name)
                }
            }
            shell.windowHinge = nil
            settle(page)
            for (a, b) in zip(try frames(page), flat) {
                XCTAssertEqual(a.minX, b.minX, accuracy: 0.5, "\(family.name): flat again")
                XCTAssertEqual(a.minY, b.minY, accuracy: 0.5, family.name)
            }
        }
    }

    func testRightToLeftMirrorsTheSidesAndNoSideFrameMeetsTheBand() throws {
        let (page, _, shell) = try hosted(size: CGSize(width: 868, height: 669), regular: true, rightToLeft: true)
        shell.windowHinge = band
        settle(page)
        let partly = try frames(page)
        for frame in partly { XCTAssertTrue(frame.maxX <= band.minX + 0.5 || frame.minX >= band.maxX - 0.5, "a right-to-left side frame meets the band: \(frame)") }
        XCTAssertGreaterThanOrEqual(partly[0].minX, band.maxX - 0.5, "the leading side is on the right")
        XCTAssertLessThanOrEqual(partly[1].maxX, band.minX + 0.5, "the trailing side is on the left")
    }

    func testTheTopStripRunsAcrossTheBandAndBothSidesStartUnderIt() throws {
        let (page, _, shell) = try hosted(size: CGSize(width: 868, height: 669), regular: true)
        shell.windowHinge = band
        settle(page)
        let rail = try frame(page, "rail"), note = try frame(page, "notice"), sections = try frames(page)
        for strip in [rail, note] {
            XCTAssertLessThan(strip.minX, band.minX, "the strip starts before the band")
            XCTAssertGreaterThan(strip.maxX, band.maxX, "and runs over it")
        }
        XCTAssertLessThan(rail.minY, note.minY, "strip entries stack in document order")
        for index in [0, 1] { XCTAssertGreaterThanOrEqual(sections[index].minY, note.maxY - 0.5, "\(ids[index]) starts under the strip") }
    }

    func testAccessibilitySizeKeepsTwoSidesAndTheStripHeadsTheLeadingColumn() throws {
        let (page, window, shell) = try hosted(size: CGSize(width: 868, height: 669), regular: true)
        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        shell.windowHinge = band
        settle(page)
        let partly = try frames(page), rail = try frame(page, "rail"), note = try frame(page, "notice")
        XCTAssertLessThanOrEqual(partly[0].maxX, band.minX + 0.5)
        XCTAssertGreaterThanOrEqual(partly[1].minX, band.maxX - 0.5, "two sides at every text size")
        XCTAssertLessThanOrEqual(rail.maxX, band.minX + 0.5, "the wrapped rail stops short of the band")
        XCTAssertLessThanOrEqual(note.maxX, band.minX + 0.5, "every strip entry heads the leading column")
        XCTAssertEqual(partly[1].minY, rail.minY, accuracy: 1, "the trailing side starts level with the rail")
    }

    func testAHiddenSectionKeepsItsSlotAndTakesNoRoom() {
        let sections = [Tall(300), Tall(300), Tall(300), Tall(300)]
        let fold = UKFoldColumns(spacing: 16, isRegular: { true }, offeredHeight: { 669 })
        fold.sideInset = 16
        let sides: [FoldSide] = [.leading, .trailing, .leading, .trailing]
        func lay(hidden: Bool) -> [CGRect] {
            fold.setSections(zip(sections, sides).enumerated().map { UKFoldColumns.Section($1.0, side: $1.1, isHidden: hidden && $0 == 0) })
            fold.frame = CGRect(x: 0, y: 0, width: 868, height: fold.gridHeight(forWidth: 868))
            fold.hinge = band
            fold.layoutIfNeeded()
            return sections.map(\.frame)
        }
        let shown = lay(hidden: false)
        let hidden = lay(hidden: true)
        XCTAssertEqual(hidden[2].minY, shown[0].minY, accuracy: 0.5, "the next section on its side moves up into the freed room")
        XCTAssertEqual(hidden[2].minX, shown[2].minX, accuracy: 0.5, "and stays on its side")
        XCTAssertEqual(hidden[1], shown[1], "the other side does not move")
        XCTAssertEqual(hidden[3], shown[3], "the other side does not move")
    }

    // MARK: Where sides are off

    func testASheetNeverTakesSides() throws {
        let (host, _, shell) = try hosted(size: CGSize(width: 868, height: 669), regular: true)
        let sheet = UKServerUIPage(surface: host.definition, context: host.context.with { $0.surface = .sheet }, root: host.root,
                                   presentationID: nil, depth: 0, inheritedGroups: [], close: nil, renderer: try XCTUnwrap(host.renderer))
        let window = HostedPage.show(sheet, size: CGSize(width: 868, height: 669))
        window.traitOverrides.horizontalSizeClass = .regular
        shell.windowHinge = band
        HostedPage.wait(0.5)
        sheet.view.layoutIfNeeded()
        XCTAssertTrue(host.drawsFoldSides, "the page itself takes sides")
        XCTAssertFalse(sheet.drawsFoldSides)
    }

    func testAPageThatHostsColumnsNeverTakesSides() throws {
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(UKFoldSidesGalleryFixture.envelope.utf8))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/navigation", to: .object([
            "type": .string("navigation-columns"), "placeholder": .string("Pick one"), "standalone": .bool(false)]))
        let capabilities = (try XCTUnwrap(json["capabilities"]?.array) + [.string("sh.navigation-columns@1")]).sorted { ($0.string ?? "") < ($1.string ?? "") }
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities))
        let publication = try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
        let (page, _, shell) = try hosted(size: CGSize(width: 868, height: 669), regular: true, publication: publication)
        shell.windowHinge = band
        settle(page)
        XCTAssertFalse(page.drawsFoldSides)
    }

    // MARK: Motion

    private final class Tall: UIView {
        let height: CGFloat
        init(_ height: CGFloat) { self.height = height; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: height) }
    }

    private func container(hinge: CGRect? = nil) -> (UKFoldColumns, UIScrollView, [Tall], UIWindow) {
        let sections = [Tall(400), Tall(300), Tall(400), Tall(300)]
        let fold = UKFoldColumns(spacing: 16, isRegular: { true }, offeredHeight: { 669 })
        fold.sideInset = 16
        fold.setSections(zip(sections, [FoldSide.leading, .trailing, .leading, .trailing]).map { UKFoldColumns.Section($0, side: $1) })
        let scroll = UIScrollView()
        scroll.addSubview(fold)
        let controller = UIViewController()
        controller.view.addSubview(scroll)
        scroll.frame = CGRect(x: 0, y: 0, width: 868, height: 669)
        let window = HostedPage.show(controller, size: CGSize(width: 868, height: 669))
        window.traitOverrides.horizontalSizeClass = .regular
        let height = fold.gridHeight(forWidth: 868)
        fold.frame = CGRect(x: 0, y: 0, width: 868, height: height)
        fold.hinge = hinge
        scroll.contentSize = CGSize(width: 868, height: height)
        fold.layoutIfNeeded()
        return (fold, scroll, sections, window)
    }

    func testTheFirstLayoutOfAPageThatOpensPartlyFoldedDoesNotAnimate() {
        let (fold, _, sections, _) = container(hinge: band)
        XCTAssertTrue(fold.isSplit, "the pose is set on the first layout")
        XCTAssertTrue(sections.allSatisfy { $0.layer.animationKeys()?.isEmpty ?? true }, "no animation on first layout")
        XCTAssertEqual(UKFoldColumns.splitWritesInLayout, 0)
    }

    func testAScrollOffsetPastTheShorterSplitPageIsClampedInsideTheReflow() {
        // Reduce Motion runs the reflow's changes at once, so the offset the pass sets is the one read (cancelling a scroller's glide would
        // leave its start). The clamp lives in the layout pass, inside whichever animation wraps it.
        UKMotion.reduceMotionOverride = true
        let (fold, scroll, sections, _) = container()
        scroll.contentOffset.y = scroll.contentSize.height - scroll.bounds.height
        let flatOffset = scroll.contentOffset.y
        fold.hinge = band
        // A scroll view sizes its content before the content lays out; this stands in for it.
        let height = fold.gridHeight(forWidth: 868)
        fold.frame.size.height = height
        scroll.contentSize.height = height
        UKMotion.animate(.standard) { fold.layoutIfNeeded() }
        XCTAssertTrue(sections.allSatisfy { $0.layer.animationKeys()?.isEmpty ?? true }, "Reduce Motion moves nothing by animation")
        let limit = max(0, fold.gridHeight(forWidth: 868) - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        XCTAssertGreaterThan(flatOffset, limit - 0.5, "the flat page was taller")
        XCTAssertEqual(scroll.contentOffset.y, limit, accuracy: 0.5, "the offset is brought to the end of the split page")
    }

    func testTheClampHoldsWhenTheReflowAnimatesToo() {
        UKMotion.reduceMotionOverride = false
        let (fold, scroll, sections, _) = container()
        scroll.contentOffset.y = scroll.contentSize.height - scroll.bounds.height
        fold.hinge = band
        let height = fold.gridHeight(forWidth: 868)
        fold.frame.size.height = height
        scroll.contentSize.height = height
        // The standard spring runs; when its own completion fires the offset rests at the end of the shorter page, never past it.
        let finished = expectation(description: "the reflow's animation completed")
        UKMotion.animate(.standard, animations: { fold.layoutIfNeeded() }, completion: { _ in finished.fulfill() })
        // Only the animated path glides: the sections have an animation running while the offset is already set to the limit.
        XCTAssertFalse(sections.allSatisfy { $0.layer.animationKeys()?.isEmpty ?? true }, "the sections glide inside the reflow")
        let limit = max(0, height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        wait(for: [finished], timeout: 10)
        XCTAssertEqual(scroll.contentOffset.y, limit, accuracy: 0.5, "the animated reflow ends at the clamped offset")
    }

    func testAPoseReversedMidFlightEndsWhereTheNewPoseSays() {
        let (fold, _, sections, _) = container()
        let flat = sections.map(\.frame)
        UKMotion.reduceMotionOverride = false
        fold.hinge = band
        UKMotion.animate(.standard) { fold.layoutIfNeeded() }
        HostedPage.wait(0.08)
        let midFlight = sections[1].layer.presentation()?.frame ?? sections[1].frame
        fold.hinge = nil
        UKMotion.animate(.standard) { fold.layoutIfNeeded() }
        let retargeted = sections[1].layer.presentation()?.frame ?? sections[1].frame
        XCTAssertEqual(retargeted.minX, midFlight.minX, accuracy: 40, "the reversal starts from where the section was, not from a jump")
        HostedPage.wait(1.2)
        for (view, frame) in zip(sections, flat) { XCTAssertEqual(view.frame, frame, "flat again") }
    }

    func testSplitGroupsItsChildrenForVoiceOverAndFlatDoesNot() {
        let (fold, _, _, _) = container()
        XCTAssertFalse(fold.shouldGroupAccessibilityChildren)
        XCTAssertNil(fold.accessibilityElements, "flat, the default order")
        fold.hinge = band
        fold.layoutIfNeeded()
        XCTAssertTrue(fold.isSplit)
        XCTAssertTrue(fold.shouldGroupAccessibilityChildren)
        XCTAssertEqual(fold.accessibilityElements?.count, 4)
    }
}
