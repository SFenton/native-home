import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - A list fed by a Data Flow

/// Hosted UX and accessibility checks for a `row-collection` whose rows come from a Data Flow (`sh.pipeline@1`, `sh.list-parts@1`).
///
/// Each test runs at the iPhone, iPhone Duo and iPad widths (a simulator narrower than a width draws it at its own, as the other hosted
/// layout tests do). The documents are the Studio's own corpus cases; the flow is the document's, run by the app's own session over a feed
/// and a service the test drives by hand. With `FENTON_SHOT_DIR` set (a `TEST_RUNNER_` variable), the list is also written as stills.
@MainActor
final class ServerUIFlowListHostedTests: XCTestCase {
    /// The widths of the three families: iPhone, folded Duo and iPad.
    private static let widths: [CGFloat] = [390, 744, 1024]
    private static let clock = ServerUIClock(now: "2026-11-16T09:00:00", utcOffsetMinutes: 0)

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    /// A feed the test drives by hand: it records its one subscription and hands over each push or failure.
    @MainActor
    final class ManualFeed: ServerUIFlowFeed {
        private(set) var subscriptions: [ServerUIFlow.Subscription] = []
        private var handler: (@Sendable (Result<JSONValue, Error>) -> Void)?
        func subscribe(_ subscription: ServerUIFlow.Subscription, handler: @escaping @Sendable (Result<JSONValue, Error>) -> Void) -> @Sendable () -> Void {
            subscriptions.append(subscription)
            self.handler = handler
            return {}
        }
        func push(_ value: JSONValue) { handler?(.success(value)) }
        func drop() { handler?(.failure(NSError(domain: "feed", code: 1))) }
    }

    struct Dropped: Error {}

    private func corpus(_ file: String) throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/\(file).json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    private func publication(_ json: JSONValue) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    /// `list-parts-row-action`'s own document, with its list (on the third page) moved onto the page the renderer opens first.
    private func rowActionPublication() throws -> ServerUICompositionPublication {
        var json = try corpus("list-parts-row-action")
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        // The list asks to be pulled (`refreshable`), as a page that wants the pull says.
        var components = try XCTUnwrap(pages[2]["components"]?.array)
        guard case .object(var list) = components[0], case .object(var props)? = list["props"] else { throw XCTSkip("the list moved") }
        props["refreshable"] = .bool(true)
        list["props"] = .object(props)
        components[0] = .object(list)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        return try publication(json)
    }

    /// The overdue chores case, which holds a `ha-subscription` flow, with a list of its rows added to the first page.
    private func subscriptionPublication() throws -> ServerUICompositionPublication {
        var json = try corpus("pipeline-overdue-chores")
        let list: JSONValue = .object([
            "id": "rows", "title": "rows", "type": "row-collection", "layout": .object(["span": .number(1)]),
            "props": .object(["providerId": "overdue", "loadingText": "Loading", "emptyText": "Nothing here",
                              "unavailableText": "Unavailable", "errorText": "Could not update", "staleText": "Out of date"]),
        ])
        var components = try XCTUnwrap(json["document"]?["pages"]?.array?[0]["components"]?.array)
        components.append(list)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components))
        // The case's own record `collection` (on the third page) wants a records provider; the list replaces it.
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: .array([]))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array?.compactMap(\.string))
        let kept = capabilities.filter { $0 != "sh.collection@1" } + ["sh.row-collection@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(kept.sorted().map { .string($0) }))
        return try publication(json)
    }

    private func flow(_ id: String, in publication: ServerUICompositionPublication) throws -> ServerUIFlow {
        for case .pipeline(let source, let flow) in publication.document.dataSources where source == id { return flow }
        throw XCTSkip("the document has no flow \(id)")
    }

    private func environment() -> (viewer: ServerUIViewer?, locale: Locale?) { (ServerUIViewer(userId: "user-2", isAdmin: false, personEntityId: nil), Locale(identifier: "en_US")) }

    /// Opens the publication at `width`, the list being filled by `session`'s collection.
    private func open(_ publication: ServerUICompositionPublication, id: String, session: ServerUIFlowSession, width: CGFloat)
        throws -> (UKServerUIRenderer, UKServerUIPage, UKServerUIRowCollection) {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "off")])
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop(), collections: [id: session.collection])
        _ = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 1180)))
        HostedPage.wait(0.1)
        let root = try ServerUIRendererFixture.root(host)
        root.view.layoutIfNeeded()
        let list = try XCTUnwrap(root.nodes["rows"]?.view as? UKServerUIRowCollection, "width \(width)")
        return (host, root, list)
    }

    private func all<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, in: $0) }
    }

    /// Every accessibility label under `view`, including elements a container hands out itself.
    private func spoken(_ view: UIView) -> [String] {
        var labels = [view.accessibilityLabel, (view as? UILabel)?.text].compactMap { $0 }
        for element in view.accessibilityElements ?? [] {
            if let child = element as? UIView { labels += spoken(child) } else if let label = (element as? NSObject)?.accessibilityLabel { labels.append(label) }
        }
        for child in view.subviews { labels += spoken(child) }
        return labels
    }

    private func settle(_ condition: () -> Bool) {
        for _ in 0..<60 where !condition() { HostedPage.wait(0.05) }
    }

    /// Writes the page as a still when a shot directory is set.
    private func shoot(_ view: UIView, _ name: String, width: CGFloat) {
        guard let directory = ProcessInfo.processInfo.environment["FENTON_SHOT_DIR"], !directory.isEmpty else { return }
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(Int(width)).png"))
    }

    // MARK: Rows, tap, refresh

    /// The rows are buttons with one spoken name each, at least 44 pt tall; a tap runs the row action; a pull runs the flow again; an
    /// empty answer says why; a failed call keeps the rows and says they are out of date.
    func testARowFlowDrawsTapsRefreshesAndKeepsItsRowsAtEveryFamilyWidth() async throws {
        let publication = try rowActionPublication()
        let flow = try self.flow("upcoming", in: publication)
        for width in Self.widths {
            var calls = 0
            var answer: Result<JSONValue, Error> = .success(.object(["todo.demo_chores": .object(["items": .array([
                .object(["uid": "a", "summary": "Water the plants", "status": "needs_action", "due": "2026-11-17"]),
                .object(["uid": "b", "summary": "Pay the rates", "status": "needs_action", "due": "2026-11-20"]),
            ])])]))
            let host = ServerUIFlowHost(call: { _, _, _, _, _ in calls += 1; return try answer.get() }, environment: { self.environment() }, clock: { Self.clock })
            let session = ServerUIFlowSession(flow: flow, collection: ServerUIRowCollection(), host: host)
            let (renderer, root, list) = try open(publication, id: "upcoming", session: session, width: width)
            session.start()
            await HostedPage.settle { list.rows.count == 2 }
            await HostedPage.pump(passes: 5)
            XCTAssertEqual(list.rows.count, 2, "width \(width): phase \(session.collection.phase), calls \(calls), publications \(session.publications), model rows \(session.collection.rows.count)")

            let buttons = all(UKRowButton.self, in: list)
            XCTAssertEqual(buttons.count, 2, "width \(width): a row is a button when the list has a row action")
            for button in buttons {
                XCTAssertTrue(button.isAccessibilityElement, "width \(width)")
                XCTAssertTrue(button.accessibilityTraits.contains(.button), "width \(width)")
                // The tappable element is the row the button wraps (the button itself is a wrapper the list does not size): measure its
                // frame in the page's coordinates, and check that a touch at its centre reaches the button.
                root.view.layoutIfNeeded()
                let frame = button.row.convert(button.row.bounds, to: root.view)
                XCTAssertGreaterThanOrEqual(frame.height, 44, "width \(width): the row is a 44 pt target")
                let hit = root.view.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil)
                XCTAssertTrue(hit.map { $0 === button || $0.isDescendant(of: button) } ?? false, "width \(width): a touch on the row reaches its button, got \(String(describing: hit))")
            }
            let names = buttons.compactMap(\.accessibilityLabel)
            XCTAssertTrue(names.contains { $0.contains("Water the plants") && $0.contains("Due tomorrow") }, "width \(width): \(names)")
            XCTAssertTrue(names.contains { $0.contains("Pay the rates") && $0.contains("Due in 4 days") }, "width \(width): \(names)")
            shoot(root.view, "01-rows", width: width)

            // A tap runs the row's action (a push).
            let before = renderer.stacks[.tab("tab-alpha")]?.viewControllers.count ?? 0
            try XCTUnwrap(buttons.first).sendActions(for: .touchUpInside)
            await HostedPage.pump(passes: 25)
            XCTAssertEqual(renderer.stacks[.tab("tab-alpha")]?.viewControllers.count, before + 1, "width \(width): the row action pushed a page")
            renderer.stacks[.tab("tab-alpha")]?.popViewController(animated: false)
            await HostedPage.pump(passes: 10)

            // The flow runs again on a pull, and a failed call keeps the rows.
            let asked = calls
            answer = .failure(Dropped())
            // The pull is the page's own refresh control: its action runs the list's refresh and ends the spinner.
            let refresh = try XCTUnwrap(root.pageScroll?.refreshControl, "width \(width): a list that refreshes puts a refresh control on the page")
            refresh.beginRefreshing()
            refresh.sendActions(for: .valueChanged)
            await HostedPage.settle { !refresh.isRefreshing }
            await HostedPage.pump(passes: 5)
            XCTAssertFalse(refresh.isRefreshing, "width \(width): the pull ended")
            XCTAssertEqual(calls, asked + 1, "width \(width): one pull, one call")
            XCTAssertEqual(session.collection.phase, .stale)
            XCTAssertEqual(list.rows.count, 2, "width \(width): the rows stay when the call fails")
            XCTAssertTrue(spoken(list).contains("Out of date"), "width \(width)")
            shoot(root.view, "02-stale", width: width)

            // An empty answer says so, and its line under the title.
            answer = .success(.object([:]))
            refresh.sendActions(for: .valueChanged)
            await HostedPage.settle { session.collection.phase == .ready && list.rows.isEmpty }
            await HostedPage.pump(passes: 5)
            XCTAssertEqual(session.collection.phase, .ready)
            XCTAssertTrue(list.rows.isEmpty, "width \(width)")
            let said = spoken(list)
            XCTAssertTrue(said.contains("Nothing here"), "width \(width): \(said)")
            XCTAssertTrue(said.contains("Nothing is due."), "width \(width): the empty message is spoken: \(said)")
            shoot(root.view, "03-empty", width: width)
            session.stop()
            HostedPage.hideTracked()
        }
    }

    // MARK: Resubscribe

    /// A reconnect keeps the rows the way HAKit does it. Nothing reaches the session when the socket drops (HAKit only clears the
    /// subscription's identifier), so the rows, the phase and the row views stay as they are; after the resend the server pushes the whole
    /// list and it replaces the rows in place. A subscription the server refuses is a failure: the rows stay and read as out of date until the
    /// next push. Either way there is one subscription, never a second.
    func testAReconnectAndARefusedSubscriptionKeepTheLastGoodRowsAtEveryFamilyWidth() throws {
        let publication = try subscriptionPublication()
        let flow = try self.flow("overdue", in: publication)
        func push(_ items: [(String, String, String)]) -> JSONValue {
            .object(["items": .array(items.map { .object(["uid": .string($0.0), "summary": .string($0.1), "status": "needs_action", "due": .string($0.2)]) })])
        }
        for width in Self.widths {
            let feed = ManualFeed()
            let session = ServerUIFlowSession(flow: flow, collection: ServerUIRowCollection(),
                                              host: ServerUIFlowHost(feed: feed, environment: { self.environment() }, clock: { Self.clock }))
            let (_, root, list) = try open(publication, id: "overdue", session: session, width: width)
            session.start()
            XCTAssertEqual(session.collection.phase, .loading)
            XCTAssertTrue(spoken(list).contains("Loading"), "width \(width)")

            feed.push(push([("a", "Take the bins out", "2026-11-10"), ("b", "Wash the dishes", "2026-11-12")]))
            settle { list.rows.count == 2 }
            HostedPage.wait(0.1)
            let first = try XCTUnwrap(list.rows["a"], "width \(width)")
            XCTAssertEqual(list.rows.count, 2)
            XCTAssertTrue(spoken(list).contains { $0.contains("Take the bins out") && $0.contains("6 days overdue") }, "width \(width)")
            shoot(root.view, "04-feed-ready", width: width)

            // The socket drops and comes back: HAKit sends the one subscription again, and nothing reaches the session until the server's
            // full list does. The page shows what it had, unchanged, the whole time.
            HostedPage.wait(0.2)
            XCTAssertEqual(session.collection.phase, .ready, "width \(width): a reconnect is not a failure")
            XCTAssertTrue(list.rows["a"] === first, "width \(width): the row view is kept")
            XCTAssertEqual(list.rows.count, 2, "width \(width): the rows stay through the reconnect")
            XCTAssertFalse(spoken(list).contains("Out of date"), "width \(width)")
            feed.push(push([("a", "Take the bins out", "2026-11-10"), ("b", "Wash the dishes", "2026-11-12"), ("c", "Mow the lawn", "2026-11-13")]))
            settle { list.rows.count == 3 }
            HostedPage.wait(0.1)
            XCTAssertEqual(session.collection.phase, .ready, "width \(width)")
            XCTAssertTrue(list.rows["a"] === first, "width \(width): the same row view after the full list")
            shoot(root.view, "05-feed-reconnected", width: width)

            // A subscription the server refuses keeps the rows and says so; the next push recovers.
            feed.drop()
            settle { session.collection.phase == .stale }
            HostedPage.wait(0.1)
            XCTAssertEqual(session.collection.phase, .stale, "width \(width)")
            XCTAssertTrue(list.rows["a"] === first, "width \(width): the row view is kept, nothing reloads")
            XCTAssertEqual(list.rows.count, 3, "width \(width): the last good rows stay")
            XCTAssertTrue(spoken(list).contains("Out of date"), "width \(width)")
            shoot(root.view, "06-feed-refused", width: width)
            feed.push(push([("a", "Take the bins out", "2026-11-10")]))
            settle { list.rows.count == 1 }
            XCTAssertEqual(session.collection.phase, .ready, "width \(width)")
            XCTAssertFalse(spoken(list).contains("Out of date"), "width \(width)")
            XCTAssertEqual(feed.subscriptions.count, 1, "width \(width): one subscription, never a second")
            session.stop()
            HostedPage.hideTracked()
        }
    }
}
