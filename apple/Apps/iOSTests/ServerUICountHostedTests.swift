@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - The count operand, drawn

/// Hosted UX and accessibility checks for the count operand (`sh.count@1`): a tab badge and a text that follow how many of several entities match,
/// flipped live, at the widths of the iPhone, the folded and unfolded iPhone Duo and the iPad.
///
/// The text is the Studio's own corpus case `count-operand-doors-line`; the badges are the first-slice fixture with a count in the first tab's badge.
/// Every entity id is an invented `demo_` one.
@MainActor
final class ServerUICountHostedTests: XCTestCase {
    /// iPhone 390, folded Duo 466, unfolded Duo 868 and iPad 744 points, as the other hosted badge tests.
    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                                CGSize(width: 868, height: 678), CGSize(width: 744, height: 1133)]
    private static let doors = ["binary_sensor.demo_door_front", "binary_sensor.demo_door_back", "binary_sensor.demo_door_garage", "binary_sensor.demo_window_study"]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixtures

    private func states(_ on: Set<Int>, unavailable: Set<Int> = []) -> [EntityState] {
        Self.doors.enumerated().map { EntityState(entityId: $0.element, state: unavailable.contains($0.offset) ? "unavailable" : on.contains($0.offset) ? "on" : "off") }
    }

    /// The `count` operand over the first `entries` doors, an `on` test each; `people` puts a viewer filter on the entry at that position.
    private func countOperand(entries: Int = 4, people: [Int: [String]] = [:]) -> JSONValue {
        .object(["type": .string("count"), "of": .array((0..<entries).map { index in
            var entry: [String: JSONValue] = ["test": .object(["type": .string("state"), "sourceId": .string("count-\(index)"),
                                                               "path": .array([.string("state")]), "in": .array([.string("on")])])]
            if let ids = people[index] { entry["viewer"] = .object(["personEntityIds": .array(ids.map(JSONValue.string))]) }
            return .object(entry)
        })])
    }

    /// The first-slice fixture with `badge` as the first tab's badge value and a source for each door.
    private func badgeJSON(_ badge: JSONValue) throws -> JSONValue {
        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "document/navigation/tabs/0/badge", to: .object(["type": .string("value"), "value": badge]))
        let sources = try XCTUnwrap(json["document"]?["dataSources"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "document/dataSources", to: .array(sources + Self.doors.enumerated().map { index, id in
            .object(["id": .string("count-\(index)"), "kind": .string("ha-entity"), "entityId": .object(["type": .string("literal"), "value": .string(id)])])
        }))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities + ["sh.badges@1", "sh.operands@1", "sh.count@1"]
        return try ServerUIRendererFixture.changing(json, path: "capabilities", to: .array(Set(capabilities).sorted().map(JSONValue.string)))
    }

    private func badgeHost(_ json: JSONValue, size: CGSize, store: EntityStore) throws -> (UKServerUIRenderer, UIWindow) {
        let renderer = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(json),
                                              context: UKContext(store: store, caller: HostedCaller()),
                                              backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(renderer, size: size)
        HostedPage.layoutTracked()
        return (renderer, window)
    }

    /// The tab item's badge and spoken value, and the flyout row's badge, of the first tab.
    private func shown(_ renderer: UKServerUIRenderer) throws -> (badge: String?, value: String?, row: String?) {
        let item = try XCTUnwrap(renderer.stacks[.tab("tab-alpha")]?.tabBarItem)
        let row = HostedPage.descendants(of: renderer.view).compactMap { $0 as? UKFlyoutRow }.first { $0.accessibilityIdentifier == "tab-alpha" }
        return (item.badgeValue, item.accessibilityValue, row?.destination.badge)
    }

    private func waitForBadge(_ renderer: UKServerUIRenderer, _ badge: String?) -> Bool {
        HostedPage.until { (try? self.shown(renderer))?.badge == badge && (try? self.shown(renderer))?.row == badge }
    }

    /// The Studio's `count-operand-doors-line` case, its third page moved to the page the renderer opens first.
    private func doorsLine() throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/count-operand-doors-line.json")))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    private func texts(in view: UIView) -> [UKServerUIText] {
        ((view as? UKServerUIText).map { [$0] } ?? []) + view.subviews.flatMap { texts(in: $0) }
    }

    // MARK: A count in a badge

    /// The badge follows the count in place: a number while some match, nothing at 0 (the contract's badge rule), and an entity that is
    /// unavailable is skipped without blanking the others.
    func testACountBadgeFollowsTheEntitiesAndDrawsNothingAtZeroAtEveryFamilyWidth() throws {
        let json = try badgeJSON(countOperand())
        for size in Self.sizes {
            let store = EntityStore()
            store.replaceAll(states([0, 2]))
            let (renderer, window) = try badgeHost(json, size: size, store: store)
            defer { window.isHidden = true }
            XCTAssertTrue(waitForBadge(renderer, "2"), "\(size): two doors open: \(String(describing: try? shown(renderer)))")
            XCTAssertEqual(try shown(renderer).value, "2", "\(size): the tab item speaks the count once")
            store.apply(states([0, 1, 2, 3]))
            XCTAssertTrue(waitForBadge(renderer, "4"), "\(size): every one open")
            store.apply(states([]))
            XCTAssertTrue(waitForBadge(renderer, nil), "\(size): 0 draws no badge")
            XCTAssertNil(try shown(renderer).value, "\(size): and says no count")
            store.apply(states([1], unavailable: [0]))
            XCTAssertTrue(waitForBadge(renderer, "1"), "\(size): an unavailable door is not counted and does not stop the others")
            store.apply(states([], unavailable: [0, 1, 2, 3]))
            XCTAssertTrue(waitForBadge(renderer, nil), "\(size): nothing can be told: no badge")
            HostedPage.hideTracked()
        }
    }

    /// A count's own reads give an unavailable entity as its text, as the Studio does: a test for `unavailable` counts it, and a house of unavailable
    /// doors counted for `on` is a known 0 (no badge) rather than a count that cannot be told.
    func testACountReadsAnUnavailableEntityAsItsTextAtEveryFamilyWidth() throws {
        var json = try badgeJSON(countOperand())
        json = try ServerUIRendererFixture.changing(json, path: "document/navigation/tabs/0/badge", to: .object(["type": .string("value"), "value":
            .object(["type": .string("count"), "of": .array((0..<4).map { index in
                .object(["test": .object(["type": .string("state"), "sourceId": .string("count-\(index)"), "path": .array([.string("state")]),
                                          "in": .array([.string("unavailable")])])])
            })])]))
        for size in Self.sizes {
            let store = EntityStore()
            store.replaceAll(states([2], unavailable: [0, 1, 3]))
            let (renderer, window) = try badgeHost(json, size: size, store: store)
            defer { window.isHidden = true }
            XCTAssertTrue(waitForBadge(renderer, "3"), "\(size): three doors are unavailable: \(String(describing: try? shown(renderer)))")
            store.apply(states([0, 1, 2, 3]))
            XCTAssertTrue(waitForBadge(renderer, nil), "\(size): none unavailable: 0, no badge")
            HostedPage.hideTracked()
        }
    }

    /// An entry marked for a person counts only while that person is looking; the count waits, keeping its badge, until the viewer is known.
    func testACountThatFollowsWhoIsLookingWaitsForTheViewerAtEveryFamilyWidth() throws {
        let json = try badgeJSON(countOperand(entries: 3, people: [0: ["person.demo_sam"], 1: ["person.demo_alex"]]))
        for size in Self.sizes {
            let store = EntityStore()
            store.replaceAll(states([0, 1, 2]) + [EntityState(entityId: "person.demo_sam", state: "home", attributes: ["user_id": .string("user-sam")]),
                                                  EntityState(entityId: "person.demo_alex", state: "home", attributes: ["user_id": .string("user-alex")])])
            let (renderer, window) = try badgeHost(json, size: size, store: store)
            defer { window.isHidden = true }
            XCTAssertTrue(waitForBadge(renderer, nil), "\(size): before the viewer is known nothing is drawn")
            renderer.viewerSource.set(HassUser(id: "user-sam", name: nil, isOwner: false, isAdmin: false))
            XCTAssertTrue(waitForBadge(renderer, "2"), "\(size): Sam's door and the one for everyone: \(String(describing: try? shown(renderer)))")
            renderer.viewerSource.set(HassUser(id: "user-alex", name: nil, isOwner: false, isAdmin: false))
            store.apply(states([1, 2]))
            XCTAssertTrue(waitForBadge(renderer, "2"), "\(size): Alex's door and the one for everyone")
            store.apply(states([2]))
            XCTAssertTrue(waitForBadge(renderer, "1"), "\(size): only the entry for everyone is open")
            renderer.viewerSource.set(HassUser(id: "user-nobody", name: nil, isOwner: false, isAdmin: false))
            XCTAssertTrue(waitForBadge(renderer, "1"), "\(size): a viewer who is in no entry still counts the one for everyone")
            HostedPage.hideTracked()
        }
    }

    // MARK: A count in a text

    private func open(width: CGFloat, store: EntityStore) async throws -> (UKServerUIRenderer, UKServerUIPage, UIWindow) {
        let host = try UKServerUIRenderer(publication: doorsLine(), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 1180)))
        HostedPage.wait(0.1)
        let root = try ServerUIRendererFixture.root(host)
        root.view.layoutIfNeeded()
        let appeared = await HostedPage.settle { root.presence.isOnScreen }
        XCTAssertTrue(appeared, "UIKit must report the page on screen")
        return (host, root, window)
    }

    /// The words a rule over the count says follow the doors, flipped one at a time; the text is one static element that says what it draws.
    func testACountTextSaysHowManyAreOpenAndIsOneAccessibleElementAtEveryFamilyWidth() async throws {
        for width in [390, 744, 1024] as [CGFloat] {
            let store = EntityStore()
            store.replaceAll(states([]))
            let (_, page, window) = try await open(width: width, store: store)
            func says(_ words: String) async -> Bool {
                await HostedPage.settle { self.texts(in: page.view).contains { $0.accessibilityLabel == words } }
            }
            let closed = await says("All closed")
            XCTAssertTrue(closed, "width \(width): no door open: \(texts(in: page.view).map { $0.accessibilityLabel ?? "" })")
            store.apply(states([1]))
            let one = await says("One open")
            XCTAssertTrue(one, "width \(width)")
            store.apply(states([1, 3]))
            let two = await says("2 open")
            XCTAssertTrue(two, "width \(width)")
            let text = try XCTUnwrap(texts(in: page.view).first { $0.accessibilityLabel == "2 open" })
            XCTAssertTrue(text.isAccessibilityElement, "width \(width)")
            XCTAssertTrue(text.accessibilityTraits.contains(.staticText), "width \(width)")
            XCTAssertFalse(text.accessibilityTraits.contains(.updatesFrequently), "a count that follows doors is not a ticking value")
            store.apply(states([0, 1, 2, 3]))
            let all = await says("4 open")
            XCTAssertTrue(all, "width \(width)")
            window.isHidden = true
            HostedPage.hideTracked()
        }
    }
}
