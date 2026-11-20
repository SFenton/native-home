import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Recording-only room composition fixture

@MainActor
extension ServerUIRendererFixture {
    static func roomsJSON() throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let rooms = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIRoomsFixture.json")))
        var root = try json()
        let sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        let components = try XCTUnwrap(root["document"]?["pages"]?.array?[0]["components"]?.array)
        root = try changing(root, path: "/document/dataSources", to: .array(sources + (try XCTUnwrap(rooms["sources"]?.array))))
        root = try changing(root, path: "/document/pages/0/components", to: .array(components + (try XCTUnwrap(rooms["components"]?.array))))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities + [
            "sh.room-navigation@1", "sh.room-card@1", "sh.room-chip@1", "sh.room-section@1", "sh.room-visibility@1",
        ]
        return try changing(root, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
    }

    static func roomHost(size: CGSize = CGSize(width: 390, height: 844), json: JSONValue? = nil,
                         caller: HostedCaller = HostedCaller()) throws -> (UKServerUIRenderer, UIWindow, HostedCaller) {
        let store = EntityStore()
        store.replaceAll([
            EntityState(entityId: "switch.demo_room", state: "off"),
            EntityState(entityId: "input_boolean.demo_visible", state: "on"),
            EntityState(entityId: "counter.demo_a", state: "1"),
            EntityState(entityId: "counter.demo_b", state: "5"),
        ])
        let host = try UKServerUIRenderer(publication: publication(json ?? roomsJSON()),
                                          context: UKContext(store: store, caller: caller), backdrop: backdrop())
        let window = HostedPage.show(host, size: HostedPage.inScene(size))
        HostedPage.wait(0.1)
        return (host, window, caller)
    }
}

// MARK: - All-family-compatible hosted journeys

@MainActor
private final class RoomPowerHeldCaller: HassServiceCalling {
    var pending: CheckedContinuation<Void, Error>?
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
}

@MainActor
final class ServerUIRoomsRendererTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testRoomChipRailMeasuresAtAllFamilyWidthsAndSurvivesPublication() throws {
        var value = try ServerUIRendererFixture.roomsJSON()
        let children = try XCTUnwrap(value["document"]?["pages"]?.array?[0]["components"]?.array?[1]["children"]?.array)
        let rail: JSONValue = .object(["id": "room-rail", "title": "Overview", "type": "status-rail",
            "layout": .object(["span": .number(1)]), "props": .object([:]), "children": .array([children[1]])])
        value = try ServerUIRendererFixture.changing(value, path: "/document/pages/0/components/1/children", to: .array([children[0], rail]))
        let capabilities = try XCTUnwrap(value["capabilities"]?.array) + [.string("sh.status-rail@1")]
        value = try ServerUIRendererFixture.changing(value, path: "/capabilities",
            to: .array(capabilities.sorted { ($0.string ?? "") < ($1.string ?? "") }))
        for width: CGFloat in [355, 390, 768, 1024] {
            let (host, window, _) = try ServerUIRendererFixture.roomHost(size: CGSize(width: width, height: 900), json: value)
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            HostedPage.layoutTracked()
            let rail = try XCTUnwrap(page.nodes["room-rail"]?.view as? UKChipRailView)
            let chip = try XCTUnwrap(page.nodes["room-chip-demo"]?.view)
            XCTAssertGreaterThan(rail.gridHeight(forWidth: width - 32), 0)
            XCTAssertTrue(HostedPage.descendants(of: rail).contains { $0 === chip })
            let next = try ServerUIRendererFixture.changing(value, path: "/revision", to: .number(2))
            try host.apply(publication: ServerUIRendererFixture.publication(next), backdrop: ServerUIRendererFixture.backdrop())
            XCTAssertTrue(page.nodes["room-chip-demo"]?.view === chip)
        }
    }

    // MARK: Status rail follows the fold

    private let foldBand = CGRect(x: 455.3, y: 0, width: 40.4, height: 682)

    /// A Studio page with one status rail, hosted in the unfolded Duo's inner display.
    private func railHost(category: UIContentSizeCategory?) throws -> (UKServerUIRenderer, UIWindow, UKChipRailView) {
        var value = try ServerUIRendererFixture.roomsJSON()
        let children = try XCTUnwrap(value["document"]?["pages"]?.array?[0]["components"]?.array?[1]["children"]?.array)
        let rail: JSONValue = .object(["id": "room-rail", "title": "Overview", "type": "status-rail",
            "layout": .object(["span": .number(1)]), "props": .object([:]), "children": .array([children[1]])])
        value = try ServerUIRendererFixture.changing(value, path: "/document/pages/0/components/1/children", to: .array([children[0], rail]))
        let capabilities = try XCTUnwrap(value["capabilities"]?.array) + [.string("sh.status-rail@1")]
        value = try ServerUIRendererFixture.changing(value, path: "/capabilities",
            to: .array(capabilities.sorted { ($0.string ?? "") < ($1.string ?? "") }))
        let (host, window, _) = try ServerUIRendererFixture.roomHost(size: CGSize(width: 951, height: 682), json: value)
        let page = try ServerUIRendererFixture.root(host)
        if let category { page.traitOverrides.preferredContentSizeCategory = category }
        HostedPage.layoutTracked()
        return (host, window, try XCTUnwrap(page.nodes["room-rail"]?.view as? UKChipRailView))
    }

    private func settleFold(_ rail: UIView) {
        HostedPage.wait(0.3)
        rail.window?.layoutIfNeeded()
        rail.layoutIfNeeded()
    }

    /// A live posture change reaches the rail with no re-render, and a scrolling rail keeps crossing the band both ways.
    func testScrollRailFollowsALiveFoldAndStillCrossesTheBand() throws {
        let (_, window, rail) = try railHost(category: nil)
        defer { window.isHidden = true }
        XCTAssertEqual(rail.mode, .scroll)
        XCTAssertNil(rail.hinge, "flat: no band")
        UKHinge.hasFold = true
        UKHinge.frame = foldBand
        settleFold(rail)
        XCTAssertEqual(rail.hinge, foldBand, "partly folded: the rail took the band without a render")
        let scroller = try XCTUnwrap(HostedPage.descendants(of: rail).first { $0.accessibilityIdentifier == "chipRail.scroll" })
        XCTAssertEqual(scroller.frame.width, rail.bounds.width, accuracy: 0.5, "a scrolling rail crosses the band, no 24 pt gap")
        XCTAssertEqual(rail.appliedTrailingInset(railFrame: rail.convert(rail.bounds, to: nil)), 0)
        UKHinge.frame = nil
        settleFold(rail)
        XCTAssertNil(rail.hinge, "flat again: the band is gone")
        XCTAssertEqual(scroller.frame.width, rail.bounds.width, accuracy: 0.5)
    }

    /// The wrap counterpart: an accessibility-size rail follows the fold too, and while partly folded its chips end
    /// ``ChipRailMetrics/hingeGap`` before the band; flat, it draws exactly the frames it drew before the fold.
    func testWrappedRailFollowsALiveFoldAndKeepsClearOfTheBand() throws {
        let (_, window, rail) = try railHost(category: .accessibilityExtraExtraExtraLarge)
        defer { window.isHidden = true }
        XCTAssertEqual(rail.mode, .wrap)
        func chipFrames() -> [CGRect] {
            HostedPage.descendants(of: rail).filter { $0 is UKRoomChipView || $0 is UKStatusChipView }.map { $0.convert($0.bounds, to: nil) }
        }
        let flat = chipFrames()
        XCTAssertFalse(flat.isEmpty)
        XCTAssertEqual(rail.appliedTrailingInset(railFrame: rail.convert(rail.bounds, to: nil)), 0, "no band, no inset")
        UKHinge.hasFold = true
        UKHinge.frame = foldBand
        settleFold(rail)
        XCTAssertEqual(rail.hinge, foldBand)
        let folded = chipFrames()
        XCTAssertFalse(folded.isEmpty)
        for frame in folded {
            XCTAssertLessThanOrEqual(frame.maxX, foldBand.minX - ChipRailMetrics.hingeGap + 0.5, "chip \(frame) ends before the band's gap")
        }
        UKHinge.frame = nil
        settleFold(rail)
        XCTAssertNil(rail.hinge)
        XCTAssertEqual(chipFrames(), flat, "flat again: the same frames as before the fold")
    }

    /// Lying flat the hinge band is nil, so a wrapped rail draws the frames it always did.
    func testWrappedRailIsUnchangedWhenLyingFlat() throws {
        let (_, window, rail) = try railHost(category: .accessibilityExtraExtraExtraLarge)
        defer { window.isHidden = true }
        let before = HostedPage.descendants(of: rail).map { $0.convert($0.bounds, to: nil) }
        UKHinge.hasFold = true
        UKHinge.frame = nil
        settleFold(rail)
        XCTAssertEqual(HostedPage.descendants(of: rail).map { $0.convert($0.bounds, to: nil) }, before)
    }

    func testLiveVisibilityAndRankingKeepRetainedRoomTiles() throws {
        let (host, window, _) = try ServerUIRendererFixture.roomHost()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let grid = try XCTUnwrap(root.nodes["room-grid-demo"]?.view as? UKServerUIRoomNavigationGrid)
        let card = try XCTUnwrap(root.nodes["room-card-demo"]?.view as? UKGlassTileView)
        let original = grid.items.map(\.view)
        XCTAssertEqual(original.map(\.accessibilityIdentifier), ["room-grid-demo.room-b", "room-grid-demo.room-a"])
        host.pageContext.store.apply([EntityState(entityId: "counter.demo_a", state: "100")])
        HostedPage.wait(0.1)
        XCTAssertEqual(grid.items.map(\.view), original, "Live counter changes must not reorder a visible grid.")
        host.pageContext.store.apply([EntityState(entityId: "input_boolean.demo_visible", state: "off")])
        XCTAssertTrue(HostedPage.until { grid.items.count == 1 })
        XCTAssertNil(card.superview)
        host.pageContext.store.apply([EntityState(entityId: "input_boolean.demo_visible", state: "on"),
                                     EntityState(entityId: "switch.demo_room", state: "on")])
        XCTAssertTrue(HostedPage.until { grid.items.count == 2 && card.model.subtitle == "Running" })
        XCTAssertEqual(grid.items.map(\.view), original)
        XCTAssertTrue(root.nodes["room-card-demo"]?.view === card)
        XCTAssertNotNil(card.superview)
    }

    func testBodyOpensDetailsWithoutSendingTheSeparatePowerDiscIntent() throws {
        let (host, window, caller) = try ServerUIRendererFixture.roomHost()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let card = try XCTUnwrap(root.nodes["room-card-demo"]?.view as? UKGlassTileView)
        let disc = try XCTUnwrap(card.accessibilityElements?.compactMap { $0 as? UKTileActionDisc }.first)
        XCTAssertEqual(disc.accessibilityIdentifier, "room-card-demo.action.power")
        XCTAssertEqual(card.model.behavior, .navigate)
        XCTAssertTrue(card.accessibilityActivate())
        XCTAssertTrue(HostedPage.until { host.navigation.snapshot.stacks[.tab("tab-alpha")]?.last == "page-echo" })
        XCTAssertTrue(caller.calls.isEmpty)
    }

    /// A contact `room-card` draws the authored subtitle source or `showState` line, and VoiceOver reads it with the state.
    func testContactCardDrawsAndSpeaksWhatTheCompositionAuthors() throws {
        func card(showState: Bool, sources: [String]) throws -> UKGlassTileView {
            let json = try ServerUIRendererFixture.roomsJSON()
            guard case .object(var props) = try XCTUnwrap(json["document"]?["pages"]?.array?[0]["components"]?.array?[1]["children"]?.array?[0]["props"]) else {
                throw XCTSkip("room-card props are not an object")
            }
            props["kind"] = .string("contact")
            props["showState"] = .bool(showState)
            props["subtitleSourceIds"] = .array(sources.map(JSONValue.string))
            props["action"] = nil
            props["power"] = nil
            props["stateLabels"] = .array([])
            let edited = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components/1/children/0/props", to: .object(props))
            let (host, window, _) = try ServerUIRendererFixture.roomHost(json: edited)
            addTeardownBlock { window.isHidden = true }
            host.pageContext.store.apply([EntityState(entityId: "switch.demo_room", state: "on")])
            HostedPage.wait(0.1)
            return try XCTUnwrap(ServerUIRendererFixture.root(host).nodes["room-card-demo"]?.view as? UKGlassTileView)
        }
        let plain = try card(showState: false, sources: [])
        XCTAssertEqual(plain.model.subtitle ?? "", "")
        XCTAssertEqual(plain.model.spokenValue, "Open")
        let shown = try card(showState: true, sources: [])
        XCTAssertFalse((shown.model.subtitle ?? "").isEmpty)
        XCTAssertTrue(try XCTUnwrap(shown.model.spokenValue).hasPrefix("Open"))
        let sourced = try card(showState: false, sources: ["source-room-visible"])
        let drawn = try XCTUnwrap(sourced.model.subtitle)
        XCTAssertFalse(drawn.isEmpty)
        XCTAssertEqual(sourced.model.spokenValue, drawn == "Open" ? "Open" : "Open, \(drawn)")
    }

    func testMovingARetainedChipToAnEarlierSectionCannotBeDetachedByItsOldOwner() throws {
        let (host, window, _) = try ServerUIRendererFixture.roomHost()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let chip = try XCTUnwrap(root.nodes["room-chip-demo"]?.view)
        var json = try ServerUIRendererFixture.roomsJSON()
        var components = try XCTUnwrap(json["document"]?["pages"]?.array?[0]["components"]?.array)
        let children = try XCTUnwrap(components[1]["children"]?.array)
        components[1] = try ServerUIRendererFixture.changing(components[1], path: "/children", to: .array([children[0]]))
        var destination = try ServerUIRendererFixture.changing(components[1], path: "/id", to: .string("earlier-section"))
        destination = try ServerUIRendererFixture.changing(destination, path: "/children", to: .array([children[1]]))
        components.insert(destination, at: 1)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components))
        try host.apply(publication: ServerUIRendererFixture.publication(json), backdrop: ServerUIRendererFixture.backdrop())
        let section = try XCTUnwrap(root.nodes["earlier-section"]?.view)
        XCTAssertTrue(root.nodes["room-chip-demo"]?.view === chip)
        XCTAssertTrue(HostedPage.descendants(of: section).contains { $0 === chip })
    }

    func testPowerDiscSendsOnlyExplicitPowerWithoutOpeningTheBody() throws {
        let (host, window, caller) = try ServerUIRendererFixture.roomHost()
        defer { window.isHidden = true }
        let card = try XCTUnwrap(ServerUIRendererFixture.root(host).nodes["room-card-demo"]?.view as? UKGlassTileView)
        let disc = try XCTUnwrap(card.accessibilityElements?.compactMap { $0 as? UKTileActionDisc }.first)
        disc.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until { caller.calls == ["switch.turn_on"] })
        XCTAssertEqual(caller.data.first?["entity_id"] as? String, "switch.demo_room")
        XCTAssertEqual(host.navigation.snapshot.stacks[.tab("tab-alpha")], ["page-orbit"])
    }

    func testLiveAcknowledgmentCannotEndTheActualPowerCallOrHideItsControl() throws {
        let store = EntityStore(), caller = RoomPowerHeldCaller()
        store.replaceAll([EntityState(entityId: "switch.demo_room", state: "off"),
                          EntityState(entityId: "input_boolean.demo_visible", state: "on")])
        let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(ServerUIRendererFixture.roomsJSON()),
                                          context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host)
        defer {
            caller.pending?.resume()
            caller.pending = nil
            window.isHidden = true
        }
        let card = try XCTUnwrap(ServerUIRendererFixture.root(host).nodes["room-card-demo"]?.view as? UKGlassTileView)
        let disc = try XCTUnwrap(card.accessibilityElements?.compactMap { $0 as? UKTileActionDisc }.first)
        disc.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until { caller.pending != nil })
        let renamed = try ServerUIRendererFixture.changing(ServerUIRendererFixture.roomsJSON(),
            path: "/document/pages/0/title", to: .string("Updated room title"))
        XCTAssertNoThrow(try host.validateUpdate(ServerUIRendererFixture.publication(renamed)))
        let hidden = try ServerUIRendererFixture.changing(renamed,
            path: "/document/pages/0/components/1/props/visibility",
            to: .object(["sourceId": .string("source-room-visible"), "states": .array([.string("off")])]))
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(hidden))) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .interactionBlocked)
        }
        store.apply([EntityState(entityId: "switch.demo_room", state: "on"),
                     EntityState(entityId: "input_boolean.demo_visible", state: "off")])
        let power = try XCTUnwrap(host.bindings.powers["source-room-power"])
        XCTAssertTrue(power.hasPendingIntent)
        XCTAssertEqual(power.projection(entityID: "switch.demo_room", symbol: "powerplug").spec.phase, .inFlight)
        XCTAssertThrowsError(try host.bindings.validateReplacement([]))
        HostedPage.wait(0.1)
        XCTAssertNotNil(card.superview)
        caller.pending?.resume()
        caller.pending = nil
        XCTAssertTrue(HostedPage.until { !power.hasPendingIntent && card.superview == nil })
        XCTAssertNoThrow(try host.validateUpdate(ServerUIRendererFixture.publication(hidden)))
    }

    func testRoomChoiceDismissesBeforePushAndRecordsOneConfiguredVisit() async throws {
        var json = try ServerUIRendererFixture.roomsJSON()
        let grid = try XCTUnwrap(json["document"]?["pages"]?.array?[0]["components"]?.array?.last)
        let modalGrid = try ServerUIRendererFixture.changing(grid, path: "/id", to: .string("modal-room-grid"))
        var components = try XCTUnwrap(json["document"]?["modals"]?.array?[0]["components"]?.array)
        components.append(modalGrid)
        json = try ServerUIRendererFixture.changing(json, path: "/document/modals/0/components", to: .array(components))
        json = try ServerUIRendererFixture.changing(json, path: "/document/modals/0/presentation/close/visibility", to: .string("all-depths"))
        let (host, window, caller) = try ServerUIRendererFixture.roomHost(json: json)
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        guard case .button(let button) = host.publication.document.navigation.chrome.groups[1].items[0] else { return XCTFail("Fixture modal action") }
        try host.perform(button.action, from: root)
        let presented = await FeatureHost.settleAsync(until: {
            host.modal?.presentingViewController != nil && host.modal?.transitionCoordinator == nil
        })
        XCTAssertTrue(presented)
        let modal = try XCTUnwrap(host.modal), page = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
        let local = try XCTUnwrap(page.definition.components.compactMap { component -> ServerUICompositionDocument.Action? in
            if case .navigationTile(let tile) = component, case .push = tile.action { return tile.action }
            return nil
        }.first)
        try host.perform(local, from: page)
        let pushedReady = await FeatureHost.settleAsync(until: { modal.transitionCoordinator == nil && modal.topViewController !== page })
        XCTAssertTrue(pushedReady)
        let pushed = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
        XCTAssertNotNil(ServerUIRendererFixture.barItems(pushed).first { $0.accessibilityIdentifier == "server-ui.sheet.close" })
        XCTAssertTrue(pushed.accessibilityPerformEscape())
        let popped = await FeatureHost.settleAsync(until: { modal.transitionCoordinator == nil && modal.topViewController === page })
        XCTAssertTrue(popped)
        let navigationGrid = try XCTUnwrap(page.nodes["modal-room-grid"]?.view as? UKServerUIRoomNavigationGrid)
        let room = try XCTUnwrap(navigationGrid.items.map(\.view).compactMap { $0 as? UKGlassTileView }
            .first { $0.accessibilityIdentifier == "modal-room-grid.room-a" })
        XCTAssertTrue(room.accessibilityActivate())
        XCTAssertTrue(room.accessibilityActivate())
        let dismissed = await FeatureHost.settleAsync(until: {
            host.modal == nil && host.stacks[.tab("tab-alpha")]?.transitionCoordinator == nil
        })
        XCTAssertTrue(dismissed)
        await host.bindings.roomVisits?.waitForCalls()
        XCTAssertEqual(caller.calls, ["script.turn_on"])
        XCTAssertEqual(caller.data.first?["entity_id"] as? String, "script.demo_visit")
        XCTAssertEqual(JSONValue(any: caller.data.first?["variables"]), .object(["room": .string("demo-a")]))
        XCTAssertEqual(host.navigation.snapshot.stacks[.tab("tab-alpha")], ["page-orbit", "page-echo"])
    }

    /// Parent runs this same hosted case on iPhone, Duo and iPad; no family-specific exclusion.
    func testRoomPrimitivesKeepAccessibleBodyDiscChipAndHeadingAtAX5() throws {
        let (host, window, _) = try ServerUIRendererFixture.roomHost()
        defer { window.isHidden = true }
        host.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge),
                                        forChild: host.tabController)
        host.view.layoutIfNeeded()
        let root = try ServerUIRendererFixture.root(host)
        let card = try XCTUnwrap(root.nodes["room-card-demo"]?.view as? UKGlassTileView)
        let chip = try XCTUnwrap(root.nodes["room-chip-demo"]?.view as? UKRoomChipView)
        XCTAssertTrue(card.accessibilityElements?.contains { $0 is UKTileActionDisc } == true)
        XCTAssertTrue(chip.isAccessibilityElement)
        XCTAssertFalse(chip.accessibilityLabel?.isEmpty ?? true)
        let headers = HostedPage.descendants(of: root.view).filter { $0.accessibilityTraits.contains(.header) }
        XCTAssertTrue(headers.contains { ($0 as? UILabel)?.text == "Demo devices" })
        XCTAssertGreaterThan(card.gridHeight(forWidth: 320), 44)
    }
}
