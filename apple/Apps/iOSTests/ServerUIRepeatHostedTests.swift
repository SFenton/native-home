@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Fixture

/// A page that holds one `repeat` of the shared corpus (`repeat-*`), with the records flow's collection driven by hand.
@MainActor
struct ServerUIRepeatFixture {
    let host: UKServerUIRenderer
    let window: UIWindow
    let page: UKServerUIPage
    let collection: ServerUIRowCollection
    let caller: HostedCaller

    static func records(_ count: Int, value: (Int) -> Double = { 60 + Double($0) }) -> [JSONValue] {
        (0..<count).map { .object(["at": .string("2026-11-16T\(String(format: "%02d", $0 % 24)):00:00Z"), "label": .string("H\($0)"),
                                   "value": .number(value($0)), "position": .number(Double($0))]) }
    }

    /// Opens corpus case `file` with its third page's components on the first page. `props` is merged into the repeat's props.
    static func show(_ file: String, width: CGFloat, height: CGFloat = 1180, dark: Bool = false, props: [String: JSONValue] = [:],
                     phase: ServerUIRowCollection.Phase = .ready, records: [JSONValue]? = nil,
                     category: UIContentSizeCategory? = nil, reduceMotion: Bool? = nil, confirm: Bool = false, inSheet: Bool = false) throws -> Self {
        UKMotion.reduceMotionOverride = reduceMotion
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/\(file).json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        var components = try XCTUnwrap(pages[2]["components"]?.array)
        if case .object(var node) = components[0], case .object(var own)? = node["props"] {
            for (key, value) in props { own[key] = value }
            node["props"] = .object(own)
            if confirm, case .array(var children)? = node["children"], case .object(var child) = children[0], case .object(var action)? = child["action"] {
                action["confirmation"] = .object(["type": .string("additional"), "style": .string("alert"), "title": .string("Set it?"),
                                                  "confirmLabel": .string("Set"), "cancelLabel": .string("Cancel"), "destructive": .bool(false)])
                child["action"] = .object(action)
                children[0] = .object(child)
                node["children"] = .array(children)
            }
            components[0] = .object(node)
        }
        if inSheet {
            // The repeat goes in the document's sheet (`appearance: system`), which a root page cannot be: pages pin themselves dark.
            json = try ServerUIRendererFixture.changing(json, path: "/document/modals/0/components", to: .array(components))
        } else {
            json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components))
        }
        // The third page's components moved to the first page (or the sheet); what stands there now must not repeat their ids.
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: inSheet ? .array([]) : XCTUnwrap(pages[0]["components"]))
        let publication = try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
        let collection = ServerUIRowCollection()
        if let records { try collection.apply(records: records, phase: phase) }
        let caller = HostedCaller()
        let renderer = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore(), caller: caller),
                                              backdrop: ServerUIRendererFixture.backdrop(), collections: ["series": collection])
        let window = HostedPage.show(renderer, size: HostedPage.inScene(CGSize(width: width, height: height)))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        if let category { window.traitOverrides.preferredContentSizeCategory = category }
        HostedPage.wait(0.2)
        var page = try ServerUIRendererFixture.root(renderer)
        if inSheet {
            renderer.activate(.present(modalId: "modal-swatch", arguments: .init(), ifPresented: .reject), from: page)
            HostedPage.wait(0.6)
            page = try XCTUnwrap(renderer.modal?.topViewController as? UKServerUIPage, "the sheet's page")
        }
        page.view.layoutIfNeeded()
        return Self(host: renderer, window: window, page: page, collection: collection, caller: caller)
    }

    /// The repeat view on its own, in a dark container the colour of the page ground, laid out at `width` with no window. A free window draws blank, so
    /// a width wider than the simulator's scene (the unfolded Duo's 669 pt on the folded Duo, the iPhone and the iPad's 744) is drawn this way.
    static func standalone(width: CGFloat, count: Int = 24) -> (container: UIView, view: UKRepeatView, window: UIWindow) {
        let node = ServerUICompositionDocument.Node(id: "items", title: "Forecast", span: 1)
        let words = ServerUIRepeat.Words(loading: "Loading", empty: "Nothing here", unavailable: "Unavailable", error: "Could not update", stale: "Out of date")
        let paging = ServerUIRepeat.Paging(compact: 6, regular: 9, indicator: true, buttons: .regularWidth, label: "24-hour forecast")
        let value = ServerUIRepeat(node: node, providerId: "series", axis: .horizontal, spacing: .token(.s), paging: paging, words: words, children: [])
        let cells = (0..<count).map { index -> UKServerUICellHost in
            let label = UILabel()
            label.text = "H\(index)"
            label.textColor = .label
            return UKServerUICellHost(scope: UKServerUICellScope(index: index), content: label)
        }
        let view = UKRepeatView()
        view.apply(value, cells: cells, word: nil, footnote: nil)
        let container = UIView()
        container.backgroundColor = UIColor(red: 17 / 255, green: 23 / 255, blue: 35 / 255, alpha: 1)
        container.addSubview(view)
        let height = view.sizeThatFits(.init(width: width, height: 400)).height
        view.frame = .init(x: 0, y: 12, width: width, height: height)
        container.frame = .init(x: 0, y: 0, width: width, height: height + 24)
        // In a window of its own that is set dark: with no window the label colour resolves by the simulator's setting (the iPhone's and iPad's are light).
        let controller = UIViewController()
        controller.view = container
        let window = UIWindow(frame: container.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.isHidden = false
        for _ in 0..<2 { container.setNeedsLayout(); container.layoutIfNeeded(); view.layoutIfNeeded() }
        return (container, view, window)
    }

    /// The container drawn at 3x.
    static func image(of container: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(bounds: container.bounds, format: format)
        // A symbol image is not always ready on the first draw (a first draw measured the chevron as missing); the second draw is the one kept.
        _ = renderer.image { container.layer.render(in: $0.cgContext) }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        return renderer.image { container.layer.render(in: $0.cgContext) }
    }

    var repeatView: UKRepeatView? { page.nodes["items"]?.view as? UKRepeatView }

    func settle() {
        HostedPage.wait(0.2)
        page.view.layoutIfNeeded()
        HostedPage.layoutTracked()
    }

    /// The text of every label inside `view`, top to bottom.
    static func texts(in view: UIView) -> [String] {
        let labels = labels(in: view).sorted { $0.convert($0.bounds, to: view).minY < $1.convert($1.bounds, to: view).minY }
        return labels.compactMap(\.text)
    }

    static func labels(in view: UIView) -> [UILabel] {
        ((view as? UILabel).map { [$0] } ?? []) + view.subviews.flatMap { labels(in: $0) }
    }

    static func all<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, in: $0) }
    }
}

// MARK: - Tests

/// Hosted UX and accessibility checks for the repeat (`sh.repeat@1`) at the widths of the iPhone, the folded iPhone Duo and the iPad.
///
/// Every document is a case of the shared corpus, so what the Studio previews is what these draw. A simulator narrower than a width draws it
/// at the simulator's own, so each check reads the width the page really has.
@MainActor
final class ServerUIRepeatHostedTests: XCTestCase {
    private static let widths: [CGFloat] = [390, 744, 1024]
    private typealias F = ServerUIRepeatFixture

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func expectedPageSize(_ view: UIView, step: Int = 0) -> Int {
        let paging = ServerUIRepeat.Paging(compact: 6, regular: 9, scaleByTextSize: [1, 0.8, 0.5, 0.34], minimum: 2)
        return paging.pageSize(isRegular: view.bounds.width >= UKRepeatView.regularWidth, textStep: step)
    }

    // MARK: Horizontal, paged

    /// A horizontal repeat counts its pages by the window, names the pager, and previous and next buttons show only at regular width.
    func testAHorizontalPagedRepeatCountsItsPagesByTheWindowAndShowsButtonsOnlyAtRegularWidth() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-paging-full", width: width, records: F.records(24))
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView, "width \(width)")
            let size = expectedPageSize(view)
            let dots = try XCTUnwrap(F.all(UKPageIndicator.self, in: view).first, "the page indicator (width \(width))")
            XCTAssertEqual(dots.pageCount, Int((24.0 / Double(size)).rounded(.up)), "pages at width \(view.bounds.width)")
            XCTAssertEqual(dots.label, "24-hour forecast")
            XCTAssertEqual(F.all(UKServerUICellHost.self, in: view).count, 24, "every cell exists")
            let regular = view.bounds.width >= UKRepeatView.regularWidth
            let next = F.all(UIButton.self, in: view).first { $0.accessibilityIdentifier == "repeat.next" }
            XCTAssertEqual(next.map { !$0.isHidden } ?? false, regular, "buttons show only at regular width (width \(view.bounds.width))")
            if regular, let next {
                XCTAssertGreaterThanOrEqual(next.bounds.width, 44)
                XCTAssertGreaterThanOrEqual(next.bounds.height, 44)
                next.sendActions(for: .touchUpInside)
                HostedPage.until { dots.page == 1 }
                XCTAssertEqual(dots.page, 1, "the next button moves one page")
                let previous = try XCTUnwrap(F.all(UIButton.self, in: view).first { $0.accessibilityIdentifier == "repeat.previous" })
                XCTAssertTrue(previous.isEnabled)
            }
        }
    }

    /// The page size follows the text size: the count is scaled down and the pages grow in number, never below the minimum.
    func testALargerTextSizeShrinksThePageAndAddsPages() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-paging-full", width: width, records: F.records(24))
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView)
            let dots = try XCTUnwrap(F.all(UKPageIndicator.self, in: view).first)
            let before = dots.pageCount
            shown.window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            shown.settle()
            let after = try XCTUnwrap(F.all(UKPageIndicator.self, in: view).first).pageCount
            XCTAssertGreaterThan(after, before, "more pages at the largest text size (width \(view.bounds.width))")
            XCTAssertLessThanOrEqual(after, 12, "no more than a cell a page, and the minimum of two keeps it to twelve")
        }
    }

    // MARK: Vertical, placeholders

    /// A vertical repeat stacks its cells down the page; while the flow has not answered, the placeholder draws its count with the loading word.
    func testAVerticalRepeatDrawsPlaceholdersWhileLoadingThenItsRecordsWithoutReloading() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-placeholder", width: width, props: ["axis": .string("vertical")], phase: .loading)
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView, "width \(width)")
            let ghosts = F.all(UKServerUICellHost.self, in: view)
            XCTAssertEqual(ghosts.count, 6, "the placeholder draws its count")
            XCTAssertEqual(ghosts.map { F.texts(in: $0) }, (1...6).map { ["\($0)"] }, "each placeholder reads only its index")
            XCTAssertEqual(ghosts.map(\.frame.minY), ghosts.map(\.frame.minY).sorted(), "stacked down the page")
            XCTAssertTrue(F.texts(in: view).contains("Loading"), "the loading word shows under the placeholders")
            let node = try XCTUnwrap(shown.page.nodes["items"]?.view)

            try shown.collection.apply(records: F.records(4), phase: .ready)
            shown.settle()
            XCTAssertTrue(shown.page.nodes["items"]?.view === node, "the repeat is the same view: nothing reloaded (width \(width))")
            let cells = F.all(UKServerUICellHost.self, in: view)
            XCTAssertEqual(cells.count, 4)
            XCTAssertEqual(cells.map { F.texts(in: $0) }, (0..<4).map { ["H\($0)", "\(60 + $0)°"] })
            XCTAssertFalse(F.texts(in: view).contains("Loading"))
        }
    }

    /// With no records the word for the state stands in the list's place.
    func testTheWordsStandInPlaceOfAnEmptyList() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-vertical", width: width, phase: .ready, records: [])
            defer { shown.window.isHidden = true }
            XCTAssertEqual(F.texts(in: try XCTUnwrap(shown.repeatView)), ["Nothing here"], "width \(width)")
        }
    }

    // MARK: In place

    /// One record changing updates its own cell: every view stays, every other cell's text stays, and the footnote shows when the list goes stale.
    func testOneRecordChangingUpdatesItsCellInPlace() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-vertical", width: width, records: F.records(5))
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView)
            let before = F.all(UKServerUICellHost.self, in: view)
            let contents = before.map(\.content)
            let nodesBefore = shown.page.nodes.mapValues { ObjectIdentifier($0.view) }
            XCTAssertEqual(before.map { F.texts(in: $0) }.map { $0.last }, (0..<5).map { "\(60 + $0)°" })

            try shown.collection.apply(records: F.records(5) { $0 == 2 ? 99 : 60 + Double($0) }, phase: .ready)
            shown.settle()
            let after = F.all(UKServerUICellHost.self, in: view)
            XCTAssertEqual(after.map { ObjectIdentifier($0) }, before.map { ObjectIdentifier($0) }, "the same cells (width \(width))")
            XCTAssertEqual(after.map { ObjectIdentifier($0.content) }, contents.map { ObjectIdentifier($0) })
            XCTAssertEqual(shown.page.nodes.mapValues { ObjectIdentifier($0.view) }, nodesBefore, "no node was rebuilt")
            XCTAssertEqual(after.map { F.texts(in: $0).last }, ["60°", "61°", "99°", "63°", "64°"])

            // A failed refresh keeps the cells and says the list is out of date; the next answer takes the footnote away.
            try shown.collection.apply(records: nil, phase: .stale)
            shown.settle()
            XCTAssertEqual(F.all(UKServerUICellHost.self, in: view).map { ObjectIdentifier($0) }, before.map { ObjectIdentifier($0) })
            XCTAssertTrue(F.texts(in: view).contains("Out of date"))
            try shown.collection.apply(records: F.records(5), phase: .ready)
            shown.settle()
            XCTAssertFalse(F.texts(in: view).contains("Out of date"))
            XCTAssertTrue(shown.page.nodes["items"]?.view === view)
        }
    }

    /// A tap in a cell sends the service call with that cell's own record, for a plain call and for one that asks first.
    func testATapInACellSendsThatCellsRecord() async throws {
        for width in Self.widths {
            let shown = try F.show("repeat-item-in-an-action", width: width, records: F.records(4))
            defer { shown.window.isHidden = true }
            let stacks = F.all(UKStackView.self, in: try XCTUnwrap(shown.repeatView))
            XCTAssertEqual(stacks.count, 4)
            XCTAssertTrue(stacks.allSatisfy { $0.isAccessibilityElement && $0.accessibilityLabel == "Set" && $0.bounds.height >= 44 })
            stacks[2].sendActions(for: .touchUpInside)
            await shown.host.callRunner.waitForCalls()
            XCTAssertEqual(shown.caller.calls, ["light.turn_on"], "width \(width)")
            XCTAssertEqual(Self.number(shown.caller.data.last?["brightness_pct"]), 62, "the third cell sends its own value")
            stacks[0].sendActions(for: .touchUpInside)
            await shown.host.callRunner.waitForCalls()
            XCTAssertEqual(Self.number(shown.caller.data.last?["brightness_pct"]), 60)
        }
    }

    func testAConfirmedTapInACellStillReadsThatCellsRecord() async throws {
        for width in Self.widths {
            let shown = try F.show("repeat-item-in-an-action", width: width, records: F.records(4), confirm: true)
            defer { shown.window.isHidden = true; HostedPage.hideTracked() }
            let stacks = F.all(UKStackView.self, in: try XCTUnwrap(shown.repeatView))
            stacks[3].sendActions(for: .touchUpInside)
            await HostedPage.settle { FeatureHost.alert(on: shown.host) != nil }
            XCTAssertTrue(shown.caller.calls.isEmpty, "it asks first (width \(width))")
            let alert = try XCTUnwrap(FeatureHost.alert(on: shown.host))
            XCTAssertTrue(FeatureHost.answer(alert, "Set"))
            await shown.host.callRunner.waitForCalls()
            XCTAssertEqual(shown.caller.calls, ["light.turn_on"], "the confirmed call is not refused for want of the cell")
            XCTAssertEqual(Self.number(shown.caller.data.last?["brightness_pct"]), 63)
            stacks[1].sendActions(for: .touchUpInside)
            await HostedPage.settle { FeatureHost.alert(on: shown.host) != nil }
            XCTAssertTrue(FeatureHost.answer(try XCTUnwrap(FeatureHost.alert(on: shown.host)), "Cancel"))
            await shown.host.callRunner.waitForCalls()
            XCTAssertEqual(shown.caller.calls.count, 1, "cancel sends nothing")
        }
    }

    private static func number(_ value: (any Sendable)?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    // MARK: VoiceOver

    /// VoiceOver reads the cells in order along the axis, each by its own words, and the pager is one adjustable element.
    func testVoiceOverReadsTheCellsInOrder() throws {
        for width in Self.widths {
            let vertical = try F.show("repeat-vertical", width: width, records: F.records(4))
            defer { vertical.window.isHidden = true }
            let view = try XCTUnwrap(vertical.repeatView)
            let hosts = try XCTUnwrap(view.accessibilityElements as? [UKServerUICellHost], "width \(width)")
            XCTAssertEqual(hosts.map { F.texts(in: $0).first }, ["H0", "H1", "H2", "H3"], "reading order is the record order")
            XCTAssertEqual(hosts.map(\.frame.minY), hosts.map(\.frame.minY).sorted())
            XCTAssertTrue(hosts.allSatisfy { !$0.isAccessibilityElement }, "each part inside speaks for itself")

            let paged = try F.show("repeat-paging-full", width: width, records: F.records(24))
            defer { paged.window.isHidden = true }
            let pagedView = try XCTUnwrap(paged.repeatView)
            let elements = try XCTUnwrap(pagedView.accessibilityElements)
            XCTAssertTrue(elements.first is UKPagedRowView || elements.first is UKServerUIPagedRow, "the pages come first")
            let dots = try XCTUnwrap(F.all(UKPageIndicator.self, in: pagedView).first)
            XCTAssertTrue(dots.isAccessibilityElement)
            XCTAssertTrue(dots.accessibilityTraits.contains(.adjustable))
            XCTAssertEqual(dots.accessibilityLabel, "24-hour forecast")
            XCTAssertGreaterThanOrEqual(dots.bounds.height, 44)
            let before = dots.page
            dots.accessibilityIncrement()
            HostedPage.until { dots.page == before + 1 }
            XCTAssertEqual(dots.page, before + 1, "the adjustable action pages")
        }
    }

    // MARK: Keying (cells are keyed by position, as the Studio keys them)

    /// An hourly forecast that moves up one hour changes every record, and every cell updates where it stands: the same views, the same
    /// reading order for VoiceOver, no animation on the text.
    func testAForecastThatShiftsByAnHourUpdatesEveryCellInPlace() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-vertical", width: width, records: F.records(6))
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView)
            let hosts = F.all(UKServerUICellHost.self, in: view)
            let ids = hosts.map { ObjectIdentifier($0) }
            let contents = hosts.map { ObjectIdentifier($0.content) }
            let order = (view.accessibilityElements as? [UKServerUICellHost] ?? []).map { ObjectIdentifier($0) }
            let nodes = shown.page.nodes.mapValues { ObjectIdentifier($0.view) }

            try shown.collection.apply(records: Array(F.records(7).dropFirst()), phase: .ready)
            shown.settle()
            let after = F.all(UKServerUICellHost.self, in: view)
            XCTAssertEqual(after.map { ObjectIdentifier($0) }, ids, "the same cells (width \(width))")
            XCTAssertEqual(after.map { ObjectIdentifier($0.content) }, contents)
            XCTAssertEqual((view.accessibilityElements as? [UKServerUICellHost] ?? []).map { ObjectIdentifier($0) }, order,
                           "the reading order is the same elements, so VoiceOver focus stays where it was")
            XCTAssertEqual(shown.page.nodes.mapValues { ObjectIdentifier($0.view) }, nodes, "no node was rebuilt")
            XCTAssertEqual(after.map { F.texts(in: $0).first }, (1...6).map { "H\($0)" }, "each cell shows the next hour")
            for label in after.flatMap({ F.labels(in: $0) }) {
                XCTAssertNil(label.layer.animationKeys(), "no fade on a changed record")
                XCTAssertEqual(label.alpha, 1)
            }
        }
    }

    /// A list that shrinks or grows keeps the cells it still has and adds or drops only the ends.
    func testAListThatShrinksOrGrowsKeepsTheCellsItStillHas() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-vertical", width: width, records: F.records(5))
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView)
            let first = F.all(UKServerUICellHost.self, in: view)
            try shown.collection.apply(records: F.records(3), phase: .ready)
            shown.settle()
            let shrunk = F.all(UKServerUICellHost.self, in: view)
            XCTAssertEqual(shrunk.map { ObjectIdentifier($0) }, first.prefix(3).map { ObjectIdentifier($0) }, "width \(width)")
            XCTAssertEqual(shrunk.map { F.texts(in: $0).first }, ["H0", "H1", "H2"])
            try shown.collection.apply(records: F.records(8), phase: .ready)
            shown.settle()
            let grown = F.all(UKServerUICellHost.self, in: view)
            XCTAssertEqual(grown.prefix(3).map { ObjectIdentifier($0) }, shrunk.map { ObjectIdentifier($0) })
            XCTAssertEqual(grown.count, 8)
            XCTAssertTrue(shown.page.nodes["items"]?.view === view, "the repeat itself never reloads")
        }
    }

    /// The placeholder gives way to the first real records in one step: the repeat stays, the placeholders go, no frame is empty.
    func testThePlaceholderHandsOffToTheFirstRecordsWithoutAnEmptyFrame() throws {
        let shown = try F.show("repeat-placeholder", width: 390, props: ["axis": .string("vertical")], phase: .loading)
        defer { shown.window.isHidden = true }
        let view = try XCTUnwrap(shown.repeatView)
        XCTAssertEqual(F.all(UKServerUICellHost.self, in: view).count, 6)
        try shown.collection.apply(records: F.records(8), phase: .ready)
        HostedPage.until { F.all(UKServerUICellHost.self, in: view).count == 8 }
        shown.settle()
        let cells = F.all(UKServerUICellHost.self, in: view)
        XCTAssertEqual(cells.count, 8, "only the records remain")
        XCTAssertEqual(cells.map { F.texts(in: $0).first }, (0..<8).map { "H\($0)" })
        XCTAssertTrue(shown.page.nodes["items"]?.view === view)
        XCTAssertGreaterThan(view.bounds.height, 0)
    }

    // MARK: Reduce Motion

    /// Under Reduce Motion a move is a jump, and the dots, the buttons and the adjustable value still follow the page.
    func testThePagerFollowsAMoveUnderReduceMotion() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-paging-full", width: width, records: F.records(24), reduceMotion: true)
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView)
            let dots = try XCTUnwrap(F.all(UKPageIndicator.self, in: view).first)
            let pages = dots.pageCount
            let previous = try XCTUnwrap(F.all(UIButton.self, in: view).first { $0.accessibilityIdentifier == "repeat.previous" })
            XCTAssertFalse(previous.isEnabled, "no page before the first (width \(view.bounds.width))")
            if let next = F.all(UIButton.self, in: view).first(where: { $0.accessibilityIdentifier == "repeat.next" }), !next.isHidden {
                next.sendActions(for: .touchUpInside)
                XCTAssertEqual(dots.page, 1, "Next moves the dots at once")
                XCTAssertTrue(previous.isEnabled && UKRepeatView.glyph(of: previous)?.alpha == 1, "Previous becomes available")
            } else {
                dots.accessibilityIncrement()
                XCTAssertEqual(dots.page, 1, "a VoiceOver swipe up moves the dots")
            }
            XCTAssertEqual(dots.accessibilityValue, "Page 2 of \(pages)")
            dots.accessibilityIncrement()
            XCTAssertEqual(dots.page, 2)
            dots.accessibilityDecrement()
            XCTAssertEqual(dots.page, 1)
            XCTAssertEqual(dots.accessibilityValue, "Page 2 of \(pages)")
        }
    }

    // MARK: Buttons

    /// Previous and Next sit either side of the dots in the text ink at 44 pt, and fade once to 55% when there is no page that way.
    func testPreviousAndNextSitBesideTheDotsInTheTextInk() throws {
        var regularRuns = 0
        for width in Self.widths {
            let shown = try F.show("repeat-paging-full", width: width, records: F.records(24))
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView)
            let dots = try XCTUnwrap(F.all(UKPageIndicator.self, in: view).first)
            let previous = try XCTUnwrap(F.all(UIButton.self, in: view).first { $0.accessibilityIdentifier == "repeat.previous" })
            let next = try XCTUnwrap(F.all(UIButton.self, in: view).first { $0.accessibilityIdentifier == "repeat.next" })
            guard view.bounds.width >= UKRepeatView.regularWidth else {
                XCTAssertTrue(previous.isHidden && next.isHidden, "compact windows draw no buttons")
                continue
            }
            regularRuns += 1
            let strip = dots.convert(dots.bounds, to: view)
            let before = previous.convert(previous.bounds, to: view), after = next.convert(next.bounds, to: view)
            XCTAssertLessThan(before.maxX, strip.midX)
            XCTAssertGreaterThan(after.minX, strip.midX)
            XCTAssertEqual(before.midY, strip.midY, accuracy: 1, "on the dots' row")
            XCTAssertEqual(after.midY, strip.midY, accuracy: 1)
            XCTAssertLessThan(abs((strip.midX - before.maxX) - (after.minX - strip.midX)), 1, "centred as a group")
            XCTAssertGreaterThanOrEqual(min(before.width, before.height), 44)
            XCTAssertEqual(UKRepeatView.glyph(of: previous)?.tintColor, .label, "the text ink, not the system tint")
            XCTAssertEqual(UKRepeatView.glyph(of: next)?.tintColor, .label)
            XCTAssertEqual(UKRepeatView.glyph(of: previous)?.alpha ?? 0, 0.55, accuracy: 0.01, "fades once, to 55%")
            XCTAssertEqual(UKRepeatView.glyph(of: next)?.alpha, 1)
            XCTAssertEqual(previous.alpha, 1, "the button itself is not faded a second time")
        }
        if regularRuns == 0 { throw XCTSkip("no family here is regular width") }
    }

    // MARK: Light appearance

    /// Makes the system light for the sheet. A sheet with `appearance: system` takes the system's setting, which differs by simulator (the Duo's is dark), so
    /// the test sets it on the sheet and its window rather than relying on the device.
    private static func forceLight(_ shown: F) {
        shown.window.overrideUserInterfaceStyle = .light
        shown.host.modal?.overrideUserInterfaceStyle = .light
        shown.page.overrideUserInterfaceStyle = .light
        shown.page.view.overrideUserInterfaceStyle = .light
    }

    private func brightness(_ color: UIColor?, in view: UIView) -> CGFloat {
        var white: CGFloat = 1
        (color ?? .white).resolvedColor(with: view.traitCollection).getWhite(&white, alpha: nil)
        return white
    }

    /// A repeat in a presented sheet that follows the system appearance draws light: the word, the footnote, the dots and the buttons take the
    /// dark label ink. (A root page pins itself dark, so a sheet is the one place a repeat can draw light.)
    func testARepeatInALightSheetDrawsItsWordFootnoteDotsAndButtonsInDarkInk() throws {
        for width in Self.widths {
            let kept = try F.show("repeat-paging-full", width: width, phase: .stale, records: F.records(24), inSheet: true)
            defer { kept.window.isHidden = true; HostedPage.hideTracked() }
            Self.forceLight(kept)
            kept.settle()
            let view = try XCTUnwrap(kept.repeatView, "the repeat is in the sheet (width \(width))")
            XCTAssertEqual(view.traitCollection.userInterfaceStyle, UIUserInterfaceStyle.light, "the sheet follows the system appearance")
            let note = try XCTUnwrap(F.labels(in: view).first { $0.text == "Out of date" })
            XCTAssertLessThan(brightness(note.textColor, in: view), 0.7, "the footnote is dark ink (width \(width))")
            let dots = try XCTUnwrap(F.all(UKPageIndicator.self, in: view).first)
            XCTAssertLessThan(brightness(dots.ink, in: view), 0.2, "the dots are dark ink")
            for button in F.all(UIButton.self, in: view) where button.accessibilityIdentifier?.hasPrefix("repeat.") == true && !button.isHidden {
                XCTAssertLessThan(brightness(UKRepeatView.glyph(of: button)?.tintColor, in: view), 0.2, "the buttons are dark ink")
            }

            let empty = try F.show("repeat-paging-full", width: width, phase: .ready, records: [], inSheet: true)
            defer { empty.window.isHidden = true }
            Self.forceLight(empty)
            empty.settle()
            let word = try XCTUnwrap(F.labels(in: XCTUnwrap(empty.repeatView)).first { $0.text == "Nothing here" })
            XCTAssertLessThan(brightness(word.textColor, in: word), 0.7, "the word is dark ink in light")
        }
    }

    // MARK: Unfolded Duo

    /// The unfolded Duo (669 pt) is regular width: its repeat draws Previous and Next beside the dots, and the disabled one keeps 3:1 against the
    /// ground. Drawn on its own at that width on every family (a window cannot be that wide on every simulator).
    func testTheUnfoldedDuoDrawsTheButtonsAndTheDisabledOneKeepsContrast() throws {
        let (container, view, window) = F.standalone(width: 669)
        defer { window.isHidden = true }
        let previous = try XCTUnwrap(F.all(UIButton.self, in: view).first { $0.accessibilityIdentifier == "repeat.previous" })
        let next = try XCTUnwrap(F.all(UIButton.self, in: view).first { $0.accessibilityIdentifier == "repeat.next" })
        let dots = try XCTUnwrap(F.all(UKPageIndicator.self, in: view).first)
        XCTAssertFalse(previous.isHidden || next.isHidden, "regular width at 669 pt")
        XCTAssertFalse(previous.isEnabled)
        XCTAssertTrue(next.isEnabled)
        XCTAssertEqual(UKRepeatView.glyph(of: previous)?.alpha ?? 0, UKRepeatView.disabledAlpha, accuracy: 0.001)
        XCTAssertLessThan(previous.convert(previous.bounds, to: view).maxX, dots.convert(dots.bounds, to: view).midX)
        XCTAssertGreaterThan(next.convert(next.bounds, to: view).minX, dots.convert(dots.bounds, to: view).midX)
        let ratio = try XCTUnwrap(Self.glyphContrast(of: previous, in: container))
        XCTAssertGreaterThanOrEqual(ratio, 3, "the disabled chevron keeps 3:1 (measured \(ratio))")
        let enabled = try XCTUnwrap(Self.glyphContrast(of: next, in: container))
        XCTAssertGreaterThan(enabled, ratio, "enabled is stronger than disabled (measured \(enabled))")
    }

    /// The contrast between the brightest and the darkest pixel inside `button`, drawn on screen: the glyph against what is behind it.
    private static func glyphContrast(of button: UIButton, in container: UIView) -> Double? {
        let image = F.image(of: container)
        let frame = button.convert(button.bounds, to: container)
        let crop = CGRect(x: frame.minX * 3, y: frame.minY * 3, width: frame.width * 3, height: frame.height * 3)
        guard let cg = image.cgImage?.cropping(to: crop) else { return nil }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        func luminance(_ at: Int) -> Double {
            func channel(_ value: UInt8) -> Double { let v = Double(value) / 255; return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(pixels[at]) + 0.7152 * channel(pixels[at + 1]) + 0.0722 * channel(pixels[at + 2])
        }
        let values = stride(from: 0, to: pixels.count, by: 4).map(luminance)
        guard let light = values.max(), let dark = values.min() else { return nil }
        return (light + 0.05) / (dark + 0.05)
    }

    // MARK: Keying, horizontal

    /// A paged forecast that moves up one hour updates its cells where they stand: the scroll view, the cells and the page stay.
    func testAPagedForecastThatShiftsByAnHourUpdatesInPlace() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-paging-full", width: width, records: F.records(24))
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView)
            let scroll = try XCTUnwrap(F.all(UKPagedRowView.self, in: view).first)
            let hosts = F.all(UKServerUICellHost.self, in: view).map { ObjectIdentifier($0) }
            try shown.collection.apply(records: Array(F.records(25).dropFirst()), phase: .ready)
            shown.settle()
            XCTAssertTrue(F.all(UKPagedRowView.self, in: view).first === scroll, "the pager's scroll view is the same (width \(width))")
            XCTAssertEqual(F.all(UKServerUICellHost.self, in: view).map { ObjectIdentifier($0) }, hosts)
            XCTAssertEqual(F.texts(in: try XCTUnwrap(F.all(UKServerUICellHost.self, in: view).first)).first, "H1")
        }
    }

    /// A paged list that shrinks or grows keeps its scroll view and the cells it still has; a drag is not interrupted by a new scroll view.
    func testAPagedListThatShrinksOrGrowsKeepsItsScrollViewAndKeptCells() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-paging-full", width: width, records: F.records(24))
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView)
            let scroll = try XCTUnwrap(F.all(UKPagedRowView.self, in: view).first)
            let first = F.all(UKServerUICellHost.self, in: view)
            try shown.collection.apply(records: F.records(10), phase: .ready)
            shown.settle()
            XCTAssertTrue(F.all(UKPagedRowView.self, in: view).first === scroll, "width \(width)")
            let shrunk = F.all(UKServerUICellHost.self, in: view)
            XCTAssertEqual(shrunk.map { ObjectIdentifier($0) }, first.prefix(10).map { ObjectIdentifier($0) })
            try shown.collection.apply(records: F.records(30), phase: .ready)
            shown.settle()
            XCTAssertTrue(F.all(UKPagedRowView.self, in: view).first === scroll)
            XCTAssertEqual(F.all(UKServerUICellHost.self, in: view).prefix(10).map { ObjectIdentifier($0) }, shrunk.map { ObjectIdentifier($0) })
            XCTAssertEqual(F.all(UKServerUICellHost.self, in: view).count, 30)
            let dots = try XCTUnwrap(F.all(UKPageIndicator.self, in: view).first)
            XCTAssertEqual(dots.pageCount, Int((30.0 / Double(expectedPageSize(view))).rounded(.up)), "the indicator follows the count")
        }
    }

    /// An unpaged horizontal row keeps its cells in place across a shift.
    func testAnUnpagedRowThatShiftsByAnHourUpdatesInPlace() throws {
        for width in Self.widths {
            let shown = try F.show("repeat-horizontal", width: width, records: F.records(8))
            defer { shown.window.isHidden = true }
            let view = try XCTUnwrap(shown.repeatView)
            let hosts = F.all(UKServerUICellHost.self, in: view).map { ObjectIdentifier($0) }
            try shown.collection.apply(records: Array(F.records(9).dropFirst()), phase: .ready)
            shown.settle()
            XCTAssertEqual(F.all(UKServerUICellHost.self, in: view).map { ObjectIdentifier($0) }, hosts, "width \(width)")
            XCTAssertEqual(F.all(UKServerUICellHost.self, in: view).map { F.texts(in: $0).first }, (1...8).map { "H\($0)" })
        }
    }
}
