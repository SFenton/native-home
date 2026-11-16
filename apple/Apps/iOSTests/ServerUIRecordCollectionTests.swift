@testable import HassCore
import HassDesign
import Observation
import UIKit
import XCTest
@testable import HassUI

// MARK: - Hosted record collections (synthetic only)

/// Hosted journeys for the shared collection host: incremental rows, paging without a button, opt-in refresh,
/// stable bar items and rejected nodes. They run unchanged on iPhone, iPhone Duo (folded and unfolded) and iPad.
@MainActor
final class ServerUIRecordCollectionTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    /// The frozen records fixture: one `record-list` collection over `demo-items`, then a form, a recipe part and pinned actions.
    private func recordFixture(template: String = "rows", pullToRefresh: Bool? = nil, formFields: JSONValue? = nil) throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fragment = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIRecordsFixture.json")))
        let components = try XCTUnwrap(fragment["components"]?.array).filter { $0["type"]?.string != "recipe-part" }
        var root = try ServerUIRendererFixture.json()
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(components))
        root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("normal"))
        if template != "rows" {
            root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components/0/props/template", to: .string(template))
        }
        if let pullToRefresh {
            root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components/0/props/pullToRefresh", to: .bool(pullToRefresh))
        }
        if let formFields {
            root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components/1/props/fields", to: formFields)
        }
        return try ServerUIRendererFixture.changing(root, path: "/capabilities",
            to: .array((ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.grid@1" }
                + ["sh.collection@1", "sh.form@1", "sh.pinned-actions@1"]).sorted().map(JSONValue.string)))
    }

    private func host(_ source: any UKServerUICollectionSource, json: JSONValue, forms: [String: UKServerUIFormFactory]? = nil,
                      size: CGSize) throws -> (UKServerUIRenderer, UKServerUIPage, UIWindow) {
        let forms = try forms ?? ["demo-edit": UKServerUIFormFactory(fields: ["name": .text, "enabled": .toggle], selectionOnly: false, open: {
            try ServerUIValueForm(identity: .init(ownerId: "demo", recordId: "idle"),
                fields: [.text("name", "Name", "Original", required: true), .toggle("enabled", "Enabled", false)]) { _ in }
        })]
        let renderer = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(json),
            context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop(),
            records: UKServerUIRecords(collections: ["demo-items": source], forms: forms))
        let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
        let page = try ServerUIRendererFixture.root(renderer)
        return (renderer, page, window)
    }

    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                                CGSize(width: 744, height: 1133), CGSize(width: 1024, height: 768)]

    // MARK: U1: only changed rows are touched

    func testListReconfiguresOnlyTheRowsThatChanged() throws {
        let list = UKServerUIRecordList()
        var configured: [String] = []
        list.configured = { configured.append($0) }
        let controller = UIViewController()
        controller.view.addSubview(list)
        list.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        let window = HostedPage.show(controller, size: CGSize(width: 320, height: 400))
        defer { window.isHidden = true }
        let rows = ["a", "b", "c"].reduce(into: [String: UIView]()) { $0[$1] = FixedRow() }
        list.apply(keys: ["a", "b", "c"], rows: rows, surface: .page)
        XCTAssertTrue(HostedPage.until { Set(configured) == ["a", "b", "c"] })
        HostedPage.wait(0.5)
        configured.removeAll()
        list.apply(keys: ["a", "b", "c"], rows: rows, changed: ["b"], surface: .page)
        HostedPage.wait(0.2)
        XCTAssertEqual(configured, ["b"], "Only the changed row reconfigures; an identical apply touches nothing else")
        configured.removeAll()
        list.apply(keys: ["a", "b", "c"], rows: rows, changed: [], surface: .page)
        HostedPage.wait(0.2)
        XCTAssertTrue(configured.isEmpty)
        configured.removeAll()
        list.apply(keys: ["a", "b"], rows: rows, changed: [], surface: .page)
        HostedPage.wait(0.2)
        XCTAssertEqual(configured, ["b"], "Dropping the last row moves the module's last corner to its neighbour only")
    }

    func testCollectionKeepsUnchangedRowsAndRebuildsOnlyTheChangedOne() throws {
        for size in Self.sizes {
            let source = ServerUIRecordFixtureSource()
            let (_, page, window) = try host(source, json: recordFixture(), size: size)
            defer { window.isHidden = true }
            let collection = try XCTUnwrap(page.nodes["record-list"]?.view as? UKServerUICollectionView)
            XCTAssertTrue(HostedPage.until { collection.rows.count == 3 })
            var marks: Set<String> = []
            let before = collection.rows
            for (key, view) in before { (view as? UKRowButton)?.onTap = { marks.insert(key) } }
            source.items[1] = ServerUIRowItem(id: "second", title: "Second, renamed")
            XCTAssertTrue(HostedPage.until { collection.rows.keys.contains("second") && collection.rows["second"].flatMap { Self.find(in: $0) { ($0 as? UILabel)?.text == "Second, renamed" } } != nil })
            for (key, view) in collection.rows { XCTAssertTrue(view === before[key], "A changed row is updated in place, never replaced") }
            (collection.rows["first"] as? UKRowButton)?.onTap?()
            (collection.rows["second"] as? UKRowButton)?.onTap?()
            XCTAssertTrue(marks.contains("first"), "An unchanged row is not rebuilt: it keeps its own handler")
            XCTAssertFalse(marks.contains("second"), "A changed row is reconfigured: its handler is replaced")
            HostedPage.hideTracked()
        }
    }

    // MARK: U2: paging without a button

    func testRecipeGridPagesFromTheViewportAndShowsNoLoadMoreButton() throws {
        for size in Self.sizes {
            let source = ServerUIRecordFixtureSource(recipes: true)
            let (_, page, window) = try host(source, json: recordFixture(template: "recipes"), size: size)
            defer { window.isHidden = true }
            let collection = try XCTUnwrap(page.nodes["record-list"]?.view as? UKServerUICollectionView)
            XCTAssertTrue(HostedPage.until { !collection.rows.isEmpty })
            collection.viewportChanged()
            XCTAssertTrue(HostedPage.until { source.displayed > 0 }, "A card near the end of the viewport asks for the next page")
            XCTAssertEqual(source.loadMoreCalls, 0, "The viewport pages; nothing calls loadMore from a button")
            XCTAssertNil(Self.find(in: collection) { ($0 as? UIButton)?.configuration?.title == "Load More" || ($0 as? UILabel)?.text == "Load More" })
            XCTAssertNil(Self.find(in: collection) { $0.accessibilityLabel == "Loading More Recipes" })
            source.loadingMoreValue = true
            XCTAssertTrue(HostedPage.until { Self.find(in: collection) { $0.accessibilityLabel == "Loading More Recipes" } != nil },
                          "The next page shows the footer spinner")
            HostedPage.hideTracked()
        }
    }

    // MARK: U3: refresh is opt-in

    func testPullToRefreshExistsOnlyWhereTheCollectionOptsIn() throws {
        for size in Self.sizes {
            for optsIn in [false, true] {
                let (_, page, window) = try host(ServerUIRecordFixtureSource(), json: recordFixture(pullToRefresh: optsIn ? true : nil), size: size)
                defer { window.isHidden = true }
                let body = try XCTUnwrap(page.body)
                XCTAssertTrue(HostedPage.until { (body.refreshControl != nil) == optsIn },
                              "Pull-to-refresh follows the authored opt-in (default off)")
                HostedPage.hideTracked()
            }
        }
    }

    func testCollectionDocumentPullToRefreshDecodesAndDefaultsOff() throws {
        let off = try ServerUIRendererFixture.publication(recordFixture())
        let on = try ServerUIRendererFixture.publication(recordFixture(pullToRefresh: true))
        guard case .collection(let plain) = off.document.pages[0].surface.components[0],
              case .collection(let refreshing) = on.document.pages[0].surface.components[0] else { return XCTFail("Expected collections") }
        XCTAssertFalse(plain.pullsToRefresh)
        XCTAssertTrue(refreshing.pullsToRefresh)
    }

    // MARK: U5 and U6: stable bar items, rejected nodes

    func testFormBarItemsKeepTheirIdentityAcrossObservationTicks() async throws {
        for size in Self.sizes {
            let session = try ServerUIValueForm(identity: .init(ownerId: "demo", recordId: "item"),
                fields: [.text("name", "Name", "Original", required: true), .toggle("enabled", "Enabled", false)]) { _ in }
            let factory = UKServerUIFormFactory(fields: ["name": .text, "enabled": .toggle], selectionOnly: false, open: { session })
            let (_, page, window) = try host(ServerUIRecordFixtureSource(), json: recordFixture(), forms: ["demo-edit": factory], size: size)
            defer { window.isHidden = true }
            for _ in 0..<10 { await Task.yield() }
            let settled = await HostedPage.settle { page.formView?.session === session }
            XCTAssertTrue(settled)
            await HostedPage.pump(passes: 10)
            let items = ServerUIRendererFixture.barItems(page).map(ObjectIdentifier.init)
            XCTAssertFalse(items.isEmpty)
            for index in 0..<4 {
                try session.set(.string("Edited \(index)"), group: session.groups[0].id, field: "name")
                await HostedPage.pump(passes: 5)
            }
            XCTAssertEqual(ServerUIRendererFixture.barItems(page).map(ObjectIdentifier.init), items,
                           "Observation ticks update the bar items in place; they never create new ones")
            HostedPage.hideTracked()
        }
    }

    func testAFormSessionThatDoesNotMatchItsAuthoredControlIsRejectedNotATrap() async throws {
        let fields = JSONValue.array([.object(["key": .string("files"), "label": .string("Files"), "control": .string("attachment")])])
        for size in Self.sizes {
            let files = ServerUIFormValue(key: "files", label: "Files", control: .attachment, rule: .string(maxLength: 40), value: .string(""))
            let session = try ServerUIValueForm(identity: .init(ownerId: "demo", recordId: "hostile"), fields: [files]) { _ in }
            let factory = UKServerUIFormFactory(fields: ["files": .attachment], selectionOnly: false, open: { session })
            let (renderer, page, window) = try host(ServerUIRecordFixtureSource(), json: recordFixture(formFields: fields),
                                                    forms: ["demo-edit": factory], size: size)
            defer { window.isHidden = true }
            var failures: [UKServerUIRendererError] = []
            renderer.onError = { failures.append($0) }
            for _ in 0..<10 { await Task.yield() }
            let settled = await HostedPage.settle { !failures.isEmpty }
            XCTAssertTrue(settled, "A session the authored control cannot drive is reported, not trapped")
            XCTAssertNil(page.formView?.session)
            XCTAssertNotNil(page.view.window, "The page and its last-good content survive")
            HostedPage.hideTracked()
        }
    }

    func testRejectedNodeStandInIsInertAndReportsTheRendererError() {
        var reported: [UKServerUIRendererError] = []
        let view = UKServerUIRejected.view("test", pointer: "/document/x") { reported.append($0) }
        XCTAssertTrue(view.isHidden)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertEqual(reported, [.init(code: .unavailableSource, pointer: "/document/x")])
    }

    // MARK: U9: enabled state follows busy state

    func testBusyStateRevisionChangesWhenNavigationSettles() throws {
        let (renderer, window, _) = try ServerUIRendererFixture.host()
        defer { window.isHidden = true }
        let before = renderer.busyState.revision
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        alert.addAction(.init(title: "OK", style: .cancel))
        try ServerUIRendererFixture.root(renderer).present(alert, animated: false)
        XCTAssertGreaterThan(renderer.busyState.revision, before, "Presenting an alert is a busy input")
    }

    private static func find(in view: UIView, where match: (UIView) -> Bool) -> UIView? {
        if match(view) { return view }
        for child in view.subviews { if let found = find(in: child, where: match) { return found } }
        return nil
    }
}

/// A collection source over row or recipe records that counts what the host asks of it.
@MainActor @Observable
final class ServerUIRecordFixtureSource: UKServerUICollectionSource {
    let template: ServerUICompositionDocument.Collection.Template
    var items = [ServerUIRowItem(id: "first", title: "First"), ServerUIRowItem(id: "second", title: "Second"),
                 ServerUIRowItem(id: "third", title: "Third")]
    var loadingMoreValue = false
    var searchText = ""
    var hasPendingIntent = false
    private(set) var displayed = 0
    private(set) var loadMoreCalls = 0
    private let recipes: [RecipeCard]

    init(recipes: Bool = false, recipeCount: Int = 6) {
        template = recipes ? .recipes : .rows
        self.recipes = recipes ? Array(FoodFixtures.catalog.prefix(recipeCount)) : []
    }

    var records: [UKServerUIRecord] { template == .recipes ? recipes.map(UKServerUIRecord.recipe) : items.map(UKServerUIRecord.row) }
    var loading: Bool { false }
    var error: String? { nil }
    var hasMore: Bool { template == .recipes }
    var loadingMore: Bool { loadingMoreValue }
    func load() async throws {}
    func loadMore() async throws { loadMoreCalls += 1 }
    func select(_ record: UKServerUIRecord) throws {}
    func displayed(_ record: UKServerUIRecord) { displayed += 1 }
}

/// A row with a real height, so the self-sizing list settles instead of collapsing and re-dequeuing its cells.
private final class FixedRow: UIView {
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 60) }
}
