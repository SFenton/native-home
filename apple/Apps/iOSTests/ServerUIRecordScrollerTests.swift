import HassCore
import HassDesign
import Observation
import UIKit
import XCTest
@testable import HassUI

// MARK: - A page that is one record collection scrolls the collection

/// A page whose body is one Todo, Inventory or Recipes collection hosts a ``UKRecordCollectionController`` as its scroller: only the
/// visible records exist as views, cells are reused, the grid pages and prefetches, and a live change reconfigures only the records
/// that changed. The geometry is the former one: the page base's side padding and measure, `RecipeGrid.columnCount` columns of cards
/// `HassTokens.Spacing.m` apart, rows as wide as the page's column. They run unchanged on iPhone, iPhone Duo (folded and unfolded)
/// and iPad.
@MainActor
final class ServerUIRecordScrollerTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                                CGSize(width: 744, height: 1133), CGSize(width: 1024, height: 768)]

    private func collectionComponent(template: String) -> JSONValue {
        .object(["id": "record-list", "title": "Items", "type": "collection", "layout": .object(["span": .number(1)]),
                 "props": .object(["providerId": "demo-items", "template": .string(template), "loadingText": "Loading Items",
                                   "emptyText": "No Items"])])
    }

    /// The fixture page with the collection as its whole body (and only the capabilities it needs), or after the base content.
    private func fixture(template: String, mixed: Bool = false) throws -> JSONValue {
        var root = try ServerUIRendererFixture.json()
        let base = try XCTUnwrap(root["document"]?["pages"]?.array?.first?["components"]?.array)
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components",
            to: .array(mixed ? base + [collectionComponent(template: template)] : [collectionComponent(template: template)]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("normal"))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities.filter { mixed || $0 != "sh.grid@1" } + ["sh.collection@1"]
        return try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
    }

    private func host(_ source: any UKServerUICollectionSource, template: String, size: CGSize, mixed: Bool = false)
        throws -> (UKServerUIRenderer, UKServerUIPage, UKServerUICollectionView, UIWindow) {
        let renderer = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(fixture(template: template, mixed: mixed)),
            context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop(),
            records: UKServerUIRecords(collections: ["demo-items": source]))
        let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
        let page = try ServerUIRendererFixture.root(renderer)
        let collection = try XCTUnwrap(page.nodes["record-list"]?.view as? UKServerUICollectionView)
        return (renderer, page, collection, window)
    }

    private func todoSource(count: Int) async throws -> (UKServerUITodoCollection, ScrollerTodoService) {
        let service = ScrollerTodoService()
        service.items = (0..<count).map { TodoItem(uid: "task-\($0)", summary: "Task \($0)") }
        let configuration = try ServerUITodoProvider.Configuration(entityId: "todo.demo_scroller", completionScript: nil, canRename: true,
            canDelete: true, canAdd: true, canCreateTask: false, canEditTask: false, allowsAttachments: false)
        let provider = ServerUITodoProvider(configuration: configuration, store: TodoStore(service: service), service: service)
        let source = UKServerUITodoCollection(provider)
        try await source.load()
        return (source, service)
    }

    /// The page base's content column inside a scroller: leading edge and width (padding, then centred up to the measure).
    private func column(of page: UKServerUIPage) throws -> (leading: CGFloat, width: CGFloat, padding: UIEdgeInsets) {
        let scroll = try XCTUnwrap(page.pageScroll)
        let body = try XCTUnwrap(page.body)
        let available = scroll.bounds.width - scroll.adjustedContentInset.left - scroll.adjustedContentInset.right
        let inner = min(body.maxWidth, available - body.padding.left - body.padding.right)
        return (body.padding.left + (available - body.padding.left - body.padding.right - inner) / 2, inner, body.padding)
    }

    // MARK: Hosting

    func testASingleRecordCollectionIsThePageScrollerAndAMixedPageKeepsTheColumn() async throws {
        let (todo, _) = try await todoSource(count: 3)
        for template in ["todo", "recipes"] {
            for size in Self.sizes {
                let source: any UKServerUICollectionSource = template == "todo" ? todo : ServerUIRecordFixtureSource(recipes: true)
                let (_, page, collection, window) = try host(source, template: template, size: size)
                defer { window.isHidden = true }
                XCTAssertTrue(page.pageScroll is UICollectionView, "\(template) at \(size.width): the page's scroller is the collection")
                XCTAssertTrue(page.pageScroll === collection.scrollerView)
                XCTAssertTrue(page.sheetFitScrollView === page.pageScroll)
                XCTAssertNil(page.body?.superview, "The column body is not in the page while the collection scrolls")
                XCTAssertNil(collection.superview, "The collection owner is not a view in a column")
                HostedPage.hideTracked()
            }
        }
        let (_, mixed, collection, window) = try host(ServerUIRecordFixtureSource(recipes: true), template: "recipes",
                                                     size: Self.sizes[0], mixed: true)
        defer { window.isHidden = true }
        XCTAssertTrue(mixed.pageScroll === mixed.body, "A body that mixes other content stays a column")
        XCTAssertNil(collection.scrollerView)
        XCTAssertNotNil(collection.superview)
        XCTAssertTrue(UKServerUICollectionView.hostsScroller(.todo) && UKServerUICollectionView.hostsScroller(.inventory)
                      && UKServerUICollectionView.hostsScroller(.recipes))
        XCTAssertFalse(UKServerUICollectionView.hostsScroller(.rows) || UKServerUICollectionView.hostsScroller(.carousel),
                       "Row collections and carousels keep the column")
    }

    func testAPageMovesBetweenOneCollectionAndAMixedBodyWithoutLosingItsScroller() throws {
        let source = ServerUIRecordFixtureSource(recipes: true)
        let (renderer, page, collection, window) = try host(source, template: "recipes", size: Self.sizes[0])
        defer { window.isHidden = true }
        XCTAssertTrue(page.pageScroll is UICollectionView)
        let mixed = try ServerUIRendererFixture.publication(fixture(template: "recipes", mixed: true))
        try renderer.apply(publication: mixed, backdrop: ServerUIRendererFixture.backdrop())
        XCTAssertTrue(HostedPage.until { page.pageScroll === page.body })
        XCTAssertTrue(page.nodes["record-list"]?.view === collection)
        XCTAssertNotNil(collection.superview)
        XCTAssertNotNil(page.body?.superview)
        let single = try ServerUIRendererFixture.publication(fixture(template: "recipes"))
        try renderer.apply(publication: single, backdrop: ServerUIRendererFixture.backdrop())
        XCTAssertTrue(HostedPage.until { page.pageScroll is UICollectionView })
        XCTAssertNil(page.body?.superview)
        XCTAssertTrue(HostedPage.until { !collection.rows.isEmpty }, "The grid shows its cards again after the move")
    }

    // MARK: Geometry

    func testRecipeGridKeepsTheFormerLayoutAtFourWidths() throws {
        for size in Self.sizes {
            let (_, page, collection, window) = try host(ServerUIRecordFixtureSource(recipes: true), template: "recipes", size: size)
            defer { window.isHidden = true }
            let controller = try XCTUnwrap(collection.recordController)
            XCTAssertTrue(HostedPage.until { controller.visibleKeys.count == 6 }, "Six recipes show at \(size.width)")
            HostedPage.wait(0.2)
            let place = try column(of: page)
            XCTAssertEqual(place.padding.left, HassTokens.Spacing.l, "The page base's side padding is unchanged")
            let spacing = HassTokens.Spacing.m
            let scroll = try XCTUnwrap(page.pageScroll as? UICollectionView)
            let cards = scroll.visibleCells.compactMap { $0 as? UKRecordCardCell }
            XCTAssertEqual(cards.count, 6)
            if UKHinge.hasFold {
                let xs = Set(cards.map { $0.frame.minX.rounded() })
                XCTAssertGreaterThanOrEqual(xs.count, 2, "A folded or unfolded Duo lays at least two tracks")
                XCTAssertEqual(xs.count % 2, 0, "Duo tracks are even in number, symmetric about the page's midpoint")
                if let hinge = UKHinge.frame, scroll.window != nil {
                    for card in cards {
                        XCTAssertFalse(scroll.convert(card.frame, to: nil).insetBy(dx: 0.5, dy: 0).intersects(hinge), "No card straddles the hinge")
                    }
                }
                HostedPage.hideTracked()
                continue
            }
            let columns = RecipeGrid.columnCount(width: place.width, accessibilitySize: scroll.traitCollection.ukIsAccessibilitySize)
            let each = (place.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            XCTAssertEqual(controller.gridCardWidth, each, accuracy: 0.5, "Card width at \(size.width)")
            for card in cards {
                XCTAssertEqual(card.frame.width, each, accuracy: 0.5, "Every card is \(each) wide at \(size.width)")
                let track = (card.frame.minX - place.leading) / (each + spacing)
                XCTAssertEqual(track, track.rounded(), accuracy: 0.01, "Cards sit on the tracks at \(size.width)")
                XCTAssertLessThan(Int(track.rounded()), columns)
            }
            XCTAssertEqual(Set(cards.map { $0.frame.minX.rounded() }).count, min(columns, cards.count))
            XCTAssertEqual(cards.map(\.frame.minY).min() ?? -1, place.padding.top, accuracy: 0.5, "The first row starts at the body's top padding")
            let rows = Set(cards.map { $0.frame.minY.rounded() }).sorted()
            if rows.count > 1, let first = cards.first(where: { $0.frame.minY.rounded() == rows[0] }) {
                XCTAssertEqual(rows[1] - rows[0], first.frame.height + spacing, accuracy: 1, "Rows are one spacing apart")
            }
            HostedPage.hideTracked()
        }
    }

    func testTodoRowsFillTheColumnAtFourWidths() async throws {
        let (source, _) = try await todoSource(count: 5)
        for size in Self.sizes {
            let (_, page, collection, window) = try host(source, template: "todo", size: size)
            defer { window.isHidden = true }
            let controller = try XCTUnwrap(collection.recordController)
            let settled = await HostedPage.settle { controller.visibleKeys.count == 5 }
            XCTAssertTrue(settled)
            await HostedPage.pump(passes: 10)
            let place = try column(of: page)
            let scroll = try XCTUnwrap(page.pageScroll as? UICollectionView)
            let rows = scroll.visibleCells.compactMap { $0 as? UKRecordRowCell }.sorted { $0.frame.minY < $1.frame.minY }
            XCTAssertEqual(rows.count, 5)
            for row in rows {
                XCTAssertEqual(row.frame.minX, place.leading, accuracy: 0.5, "Rows start at the column's leading edge at \(size.width)")
                XCTAssertEqual(row.frame.width, place.width, accuracy: 0.5, "Rows are the column's width at \(size.width)")
            }
            XCTAssertEqual(rows.first?.frame.minY ?? -1, place.padding.top, accuracy: 0.5)
            for (above, below) in zip(rows, rows.dropFirst()) {
                XCTAssertEqual(below.frame.minY, above.frame.maxY, accuracy: 0.5, "Rows of one module touch")
            }
            HostedPage.hideTracked()
        }
    }

    // MARK: Reuse, prefetch and paging

    func testRecipeCellsAreReusedWhileScrollingAHundredAndTwentyCards() throws {
        for size in Self.sizes {
            let source = ServerUIRecordFixtureSource(recipes: true, recipeCount: 120)
            let (_, page, collection, window) = try host(source, template: "recipes", size: size)
            defer { window.isHidden = true }
            let controller = try XCTUnwrap(collection.recordController)
            XCTAssertTrue(HostedPage.until { !controller.visibleKeys.isEmpty })
            let scroll = try XCTUnwrap(page.pageScroll as? UICollectionView)
            XCTAssertLessThan(controller.visibleKeys.count, 40, "Only the cards near the viewport exist at \(size.width)")
            var cells = Set<ObjectIdentifier>(), cards = Set<ObjectIdentifier>(), keys = Set<String>()
            func sample() {
                scroll.layoutIfNeeded()
                for case let cell as UKRecordCardCell in scroll.visibleCells {
                    cells.insert(ObjectIdentifier(cell))
                    if let hosted = cell.hosted { cards.insert(ObjectIdentifier(hosted)) }
                    if let key = cell.key { keys.insert(key) }
                }
            }
            sample()
            let travel = max(0, scroll.contentSize.height - scroll.bounds.height)
            for step in 1...12 {
                scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top + travel * CGFloat(step) / 12), animated: false)
                HostedPage.wait(0.05)
                sample()
            }
            XCTAssertGreaterThan(keys.count, 40, "Scrolling reached many different cards")
            XCTAssertLessThan(cells.count, keys.count, "Cells are reused rather than made per card at \(size.width)")
            XCTAssertLessThan(cells.count, 60)
            XCTAssertEqual(cards.count, cells.count, "Each reused cell keeps its own card view")
            HostedPage.hideTracked()
        }
    }

    func testTheViewportPagesTheGridAndTheFooterShowsOnlyWhileLoading() throws {
        for size in Self.sizes {
            let source = ServerUIRecordFixtureSource(recipes: true, recipeCount: 60)
            let (_, page, _, window) = try host(source, template: "recipes", size: size)
            defer { window.isHidden = true }
            let scroll = try XCTUnwrap(page.pageScroll as? UICollectionView)
            func bottom() { scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false) }
            XCTAssertTrue(HostedPage.until { source.displayed > 0 }, "A card on screen asks the model about paging, with no button")
            bottom()
            HostedPage.wait(0.2)
            XCTAssertEqual(source.loadMoreCalls, 0, "Nothing calls loadMore from a button")
            XCTAssertNil(Self.find(in: scroll) { ($0 as? UIButton)?.configuration?.title == "Load More" || ($0 as? UILabel)?.text == "Load More" })
            XCTAssertNil(Self.find(in: scroll) { $0.accessibilityLabel == "Loading More Recipes" })
            source.loadingMoreValue = true
            XCTAssertTrue(HostedPage.until {
                bottom()
                return Self.find(in: scroll) { $0.accessibilityLabel == "Loading More Recipes" } != nil
            }, "The next page shows the footer spinner")
            source.loadingMoreValue = false
            XCTAssertTrue(HostedPage.until { Self.find(in: scroll) { $0.accessibilityLabel == "Loading More Recipes" } == nil })
            HostedPage.hideTracked()
        }
    }

    func testGridPrefetchesImagesThroughTheController() throws {
        let (_, page, collection, window) = try host(ServerUIRecordFixtureSource(recipes: true, recipeCount: 60), template: "recipes",
                                                    size: Self.sizes[0])
        defer { window.isHidden = true }
        let controller = try XCTUnwrap(collection.recordController)
        let scroll = try XCTUnwrap(page.pageScroll as? UICollectionView)
        XCTAssertTrue(scroll.prefetchDataSource === controller, "The grid prefetches through the controller")
        XCTAssertTrue(scroll.isPrefetchingEnabled)
        XCTAssertTrue(scroll.delegate === controller)
    }

    // MARK: Only changed rows

    func testALiveChangeReconfiguresOnlyTheChangedRecordAndTheCornerItMoves() async throws {
        let (source, service) = try await todoSource(count: 60)
        let (_, page, collection, window) = try host(source, template: "todo", size: Self.sizes[0])
        defer { window.isHidden = true }
        let controller = try XCTUnwrap(collection.recordController)
        let settled = await HostedPage.settle { !controller.visibleKeys.isEmpty }
        XCTAssertTrue(settled)
        let scroll = try XCTUnwrap(page.pageScroll as? UICollectionView)
        XCTAssertLessThan(scroll.visibleCells.count, 60, "A long list draws only the visible rows")
        await HostedPage.pump(passes: 15)
        var configured: [String] = []
        controller.configured = { configured.append($0) }
        let order = source.records.map(\.id)
        let renamed = order[2]
        let renamedUID = String(renamed.drop { $0 != ":" }.dropFirst())
        service.items = service.items.map { $0.uid == renamedUID ? TodoItem(uid: renamedUID, summary: "Renamed") : $0 }
        try await source.load()
        let seen = await HostedPage.settle { configured.contains(renamed) }
        XCTAssertTrue(seen)
        // Nothing else may happen: a fixed number of suspended passes, then the neighbours are checked untouched.
        await HostedPage.pump(passes: 20)
        XCTAssertEqual(Set(configured), [renamed], "Only the changed row reconfigures; its neighbours are not touched")
        XCTAssertNotNil(Self.find(in: scroll) { ($0 as? UILabel)?.text == "Renamed" })
        configured.removeAll()
        try await source.load()
        await HostedPage.pump(passes: 20)
        XCTAssertTrue(configured.isEmpty, "An identical load touches no row")
        let last = try XCTUnwrap(source.records.last?.id)
        let previous = try XCTUnwrap(source.records.dropLast().last?.id)
        let lastUID = String(last.drop { $0 != ":" }.dropFirst())
        service.items.removeAll { $0.uid == lastUID }
        try await source.load()
        await HostedPage.pump(passes: 30)
        XCTAssertTrue(Set(configured).isSubset(of: [previous]), "Dropping the last row moves the module's corner to its neighbour only")
    }

    // MARK: Helpers

    /// A matching view that is on screen: a cell the collection has queued for reuse stays a hidden subview, which is not shown.
    private static func find(in view: UIView, where match: (UIView) -> Bool) -> UIView? {
        HostedPage.descendants(of: view).first { candidate in
            guard match(candidate) else { return false }
            var current: UIView? = candidate
            while let node = current, node !== view {
                if node.isHidden { return false }
                current = node.superview
            }
            return true
        }
    }
}

/// A todo service over canned items; a load returns whatever `items` holds now.
@MainActor
private final class ScrollerTodoService: TodoServicing {
    var items: [TodoItem] = []
    func todoItems(entityId: String) async throws -> [TodoItem] { items }
    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {}
    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue { .null }
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {}
}
