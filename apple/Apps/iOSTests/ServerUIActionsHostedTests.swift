@testable import HassCore
import HassDesign
import os
import UIKit
import XCTest
@testable import HassUI

// MARK: - Authored rules, calls and bound controls

/// Hosted journeys for `visibleWhen`, `call-service` and `bound-control` (note 06). Each runs unchanged at the widths of the parent's
/// iPhone, Duo (folded and unfolded) and iPad destinations.
@MainActor
final class ServerUIActionsHostedTests: XCTestCase {
    /// One width per family: iPhone, Duo folded, Duo unfolded, iPad.
    private static let widths: [CGFloat] = [390, 540, 720, 1024]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    private static let bound = ["sh.bound-control@1", "sh.call-service@1", "sh.operands@1"]
    private static let fan = "fan.demo_bath_fan"

    private static func call(_ service: String, optimistic: String? = nil, confirmed: Bool = false, data: String = "") -> String {
        let optimistic = optimistic.map { ",\"optimistic\":[{\"sourceId\":\"guest-fan\",\"value\":\"\($0)\",\"revertAfterSeconds\":30,\"failsOnTimeout\":false}]" } ?? ""
        let confirmation = confirmed ? ",\"confirmation\":{\"type\":\"additional\",\"style\":\"alert\",\"title\":\"Are you sure?\",\"message\":\"It runs now.\",\"confirmLabel\":\"Do it\",\"cancelLabel\":\"Cancel\",\"destructive\":false,\"exemptUserIds\":[\"nobody\"]}" : ""
        return "{\"type\":\"call-service\",\"domain\":\"fan\",\"service\":\"\(service)\",\"target\":{\"entity_id\":{\"type\":\"literal\",\"value\":\"\(fan)\"}}\(data)\(optimistic)\(confirmation)}"
    }

    private static let isOn = "{\"type\":\"state\",\"sourceId\":\"guest-fan\",\"path\":[\"state\"],\"in\":[\"on\"]}"

    private static func row(id: String, surface: String = "row", on: String, off: String) -> String {
        "{\"id\":\"\(id)\",\"title\":\"Guest Fan\",\"type\":\"bound-control\",\"layout\":{\"span\":1},\"props\":{\"kind\":\"toggle\",\"surface\":\"\(surface)\",\"isOn\":\(isOn),\"unavailableText\":\"Unavailable\"},\"icon\":{\"type\":\"sf-symbol\",\"name\":\"fan\",\"rendering\":\"canonical\",\"unavailable\":\"reject\"},\"onAction\":\(on),\"offAction\":\(off)}"
    }

    private static let note = "{\"id\":\"note\",\"title\":\"Note\",\"type\":\"text\",\"layout\":{\"span\":1},\"visibleWhen\":\(isOn),\"props\":{\"value\":{\"type\":\"literal\",\"value\":\"Running\"},\"style\":\"body\",\"unavailableText\":\"None\"}}"

    private static let kick = "{\"id\":\"kick\",\"title\":\"Kick\",\"type\":\"bound-control\",\"layout\":{\"span\":1},\"props\":{\"kind\":\"button\",\"unavailableText\":\"U\"},\"action\":\(call("turn_on", confirmed: true))}"

    private func renderer(width: CGFloat, state: String = "off", components: [String], sources: [String] = [], caller: HostedCaller,
                           entities: [EntityState] = [], capabilities more: [String], localState: [JSONValue] = [], seed: String? = nil,
                           edit: (JSONValue) throws -> JSONValue = { $0 }) async throws -> (UKServerUIRenderer, EntityStore, UIWindow) {
        var root = try ServerUIRendererFixture.json()
        let decoder = JSONDecoder()
        func json(_ text: String) throws -> JSONValue { try decoder.decode(JSONValue.self, from: Data(text.utf8)) }
        let original = try XCTUnwrap(root["document"]?["pages"]?.array?.first?["components"]?.array)
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(original + components.map(json)))
        let existing = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        let extra = ["{\"id\":\"guest-fan\",\"kind\":\"ha-entity\",\"entityId\":{\"type\":\"literal\",\"value\":\"\(Self.fan)\"}}"] + sources
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(existing + extra.map(json)))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities + more
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(Array(Set(capabilities)).sorted().map(JSONValue.string)))
        if !localState.isEmpty {
            let fields = root["document"]?["localState"]?.array ?? []
            root = try ServerUIRendererFixture.changing(root, path: "/document/localState", to: .array(fields + localState))
        }
        root = try edit(root)
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "off"), EntityState(entityId: Self.fan, state: state)] + entities)
        let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(root),
                                          context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop())
        host.viewerSource.seed(userID: seed)
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 900)))
        await HostedPage.pump(passes: 3)
        return (host, store, window)
    }

    /// Lets the observation hops the last change started land. The bound nodes have no common "done" flag across tests, so this
    /// suspends for a few passes (a suspension runs the main-actor tasks a spin would starve); a test that can name the state it
    /// waits for uses ``HostedPage/settle(passes:step:_:)`` instead.
    private func settle() async {
        for _ in 0..<6 { await Task.yield() }
        await HostedPage.pump(passes: 3)
    }

    // MARK: visibleWhen

    func testVisibleWhenTogglesInPlaceAndTheGridReflows() async throws {
        for width in Self.widths {
            let (host, store, window) = try await renderer(width: width, components: [Self.note], caller: HostedCaller(), capabilities: ["sh.visible-when@1"])
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            let view = try XCTUnwrap(page.nodes["note"]?.view)
            XCTAssertTrue(view.isHidden, "off: the rule says hidden (width \(width))")
            store.apply([EntityState(entityId: Self.fan, state: "on")])
            await settle()
            XCTAssertFalse(view.isHidden)
            XCTAssertTrue(page.nodes["note"]?.view === view, "the node is the same view: no reload")
            page.view.layoutIfNeeded()
            XCTAssertGreaterThan(view.frame.height, 0)
            store.apply([EntityState(entityId: Self.fan, state: "off")])
            await settle()
            XCTAssertTrue(view.isHidden)
            // `unavailable` keeps what was last shown (the default whenUnknown).
            store.apply([EntityState(entityId: Self.fan, state: "on")])
            await settle()
            store.apply([EntityState(entityId: Self.fan, state: "unavailable")])
            await settle()
            XCTAssertFalse(view.isHidden, "an unknown answer leaves the node as it was")
            HostedPage.hideTracked()
        }
    }

    // MARK: call-service

    func testToggleRowSendsTheAuthoredCallWithOptimisticFeedback() async throws {
        for width in Self.widths {
            let caller = HostedCaller()
            let components = [Self.row(id: "fan-row", on: Self.call("turn_on", optimistic: "on"), off: Self.call("turn_off", optimistic: "off"))]
            let (host, _, window) = try await renderer(width: width, components: components, caller: caller, capabilities: Self.bound)
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            let control = try XCTUnwrap(page.nodes["fan-row"]?.view as? UKServerUILocalControl)
            let toggle = try XCTUnwrap(control.drawnControl as? UISwitch ?? HostedPage.descendants(of: control).compactMap { $0 as? UISwitch }.first)
            XCTAssertFalse(toggle.isOn)
            toggle.isOn = true
            toggle.sendActions(for: .valueChanged)
            XCTAssertEqual(host.callRunner.pendingState(Self.fan), "on", "optimistic state shows at once")
            await host.callRunner.waitForCalls()
            XCTAssertEqual(caller.calls, ["fan.turn_on"])
            XCTAssertEqual(caller.data.first?["entity_id"] as? String, Self.fan)
            HostedPage.hideTracked()
        }
    }

    func testAFailedCallRollsTheOptimisticValueBack() async throws {
        let caller = HostedCaller()
        caller.fails = true
        let components = [Self.row(id: "fan-row", on: Self.call("turn_on", optimistic: "on"), off: Self.call("turn_off", optimistic: "off"))]
        let (host, _, window) = try await renderer(width: 390, components: components, caller: caller, capabilities: Self.bound)
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        let control = try XCTUnwrap(page.nodes["fan-row"]?.view as? UKServerUILocalControl)
        let toggle = try XCTUnwrap(control.drawnControl as? UISwitch)
        toggle.isOn = true
        toggle.sendActions(for: .valueChanged)
        await host.callRunner.waitForCalls()
        await settle()
        XCTAssertNil(host.callRunner.pendingState(Self.fan), "a rejected call shows Home Assistant's own value again")
        XCTAssertFalse(toggle.isOn)
    }

    func testAuthoredConfirmationAsksBeforeAnythingIsSent() async throws {
        for width in Self.widths {
            let caller = HostedCaller()
            let (host, _, window) = try await renderer(width: width, components: [Self.kick], caller: caller, capabilities: Self.bound)
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            let button = try XCTUnwrap(HostedPage.descendants(of: page.nodes["kick"]?.view ?? UIView()).compactMap { $0 as? UKPrimaryButton }.first)
            button.sendActions(for: .touchUpInside)
            await HostedPage.settle { FeatureHost.alert(on: host) != nil }
            XCTAssertTrue(caller.calls.isEmpty, "asks first")
            let alert = try XCTUnwrap(FeatureHost.alert(on: host))
            XCTAssertEqual(alert.title, "Are you sure?")
            XCTAssertEqual(alert.actions.map(\.title), ["Cancel", "Do it"])
            XCTAssertTrue(FeatureHost.answer(alert, "Cancel"))
            await host.callRunner.waitForCalls()
            XCTAssertTrue(caller.calls.isEmpty, "cancel sends nothing")
            button.sendActions(for: .touchUpInside)
            await HostedPage.settle { FeatureHost.alert(on: host) != nil }
            XCTAssertTrue(FeatureHost.answer(try XCTUnwrap(FeatureHost.alert(on: host)), "Do it"))
            await host.callRunner.waitForCalls()
            XCTAssertEqual(caller.calls, ["fan.turn_on"])
            HostedPage.hideTracked()
        }
    }

    // MARK: Accessibility

    func testBoundControlsAreLabelledAndKeepTheirTraits() async throws {
        for width in Self.widths {
            let components = [Self.row(id: "fan-row", on: Self.call("turn_on"), off: Self.call("turn_off")),
                              Self.row(id: "fan-tile", surface: "tile", on: Self.call("turn_on"), off: Self.call("turn_off")), Self.kick]
            let (host, _, window) = try await renderer(width: width, components: components, caller: HostedCaller(), capabilities: Self.bound)
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            let row = try XCTUnwrap(page.nodes["fan-row"]?.view)
            let toggle = try XCTUnwrap((row as? UKServerUILocalControl)?.drawnControl as? UISwitch)
            XCTAssertTrue(HostedPage.labels(in: row).contains("Guest Fan"), "the row says what it controls (width \(width))")
            XCTAssertTrue(toggle.isAccessibilityElement || toggle.accessibilityLabel != nil || row.isAccessibilityElement || !(row.accessibilityElements ?? []).isEmpty)
            let tile = try XCTUnwrap(page.nodes["fan-tile"]?.view as? UKGlassTileView)
            XCTAssertEqual(tile.accessibilityIdentifier, "fan-tile.tile")
            XCTAssertFalse((tile.accessibilityElements ?? []).isEmpty)
            let button = try XCTUnwrap(HostedPage.descendants(of: page.nodes["kick"]?.view ?? UIView()).compactMap { $0 as? UKPrimaryButton }.first)
            XCTAssertTrue(button.accessibilityTraits.contains(.button))
            XCTAssertEqual(button.accessibilityIdentifier, "kick")
            HostedPage.hideTracked()
        }
    }

    // MARK: Performance

    /// 300 predicate nodes, each reading its own entity; one entity changes. The change must touch one node's observation only.
    /// Signposted (`ServerUI.visibleWhen`) for Instruments; the budget follows `.agents/testing/apple/performance.md`.
    func testOneEntityChangeTouchesOnlyTheNodesThatReadIt() async throws {
        let count = 300
        let sources = (0..<count).map { "{\"id\":\"s\($0)\",\"kind\":\"ha-entity\",\"entityId\":{\"type\":\"literal\",\"value\":\"sensor.demo_perf_\($0)\"}}" }
        let leaves = (0..<count).map {
            "{\"id\":\"n\($0)\",\"title\":\"N\",\"type\":\"text\",\"layout\":{\"span\":1},\"visibleWhen\":{\"type\":\"state\",\"sourceId\":\"s\($0)\",\"path\":[\"state\"],\"in\":[\"on\"]},\"props\":{\"value\":{\"type\":\"literal\",\"value\":\"v\"},\"style\":\"body\",\"unavailableText\":\"None\"}}"
        }
        let nodes = (0..<3).map { group in
            "{\"id\":\"g\(group)\",\"title\":\"G\",\"type\":\"section\",\"layout\":{\"span\":1},\"props\":{\"header\":\"G\",\"footer\":\"\",\"style\":\"plain\",\"density\":\"thin\",\"hasGlyphs\":false,\"spacing\":{\"type\":\"token\",\"name\":\"m\"}},\"children\":[" + leaves[(group * 100)..<(group * 100 + 100)].joined(separator: ",") + "]}"
        }
        let entities = (0..<count).map { EntityState(entityId: "sensor.demo_perf_\($0)", state: "off") }
        let (host, store, window) = try await renderer(width: 390, components: nodes, sources: sources, caller: HostedCaller(), entities: entities,
                                                capabilities: ["sh.visible-when@1", "sh.section@1"])
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        XCTAssertTrue((0..<count).allSatisfy { page.nodes["n\($0)"]?.view.isHidden == true })
        let signposter = OSSignposter(subsystem: "app.sh.hosted", category: "ServerUI.visibleWhen")
        var samples: [Double] = []
        let rounds = 20
        for round in 0..<rounds {
            let target = round * 7
            let node = try XCTUnwrap(page.nodes["n\(target)"]?.view)
            let clock = ContinuousClock()
            let state = signposter.beginInterval("one-entity-change")
            let start = clock.now
            store.apply([EntityState(entityId: "sensor.demo_perf_\(target)", state: "on")])
            // The sample ends when the observation has re-run and shown the node, polled by suspending (the re-run is a main-actor
            // task a spinning wait would starve); the one-millisecond step bounds how far the reading can overshoot the re-run.
            let shownNode = await HostedPage.settle(passes: 2000, step: .milliseconds(1)) { !node.isHidden }
            let elapsed = start.duration(to: clock.now)
            signposter.endInterval("one-entity-change", state)
            XCTAssertTrue(shownNode, "the changed entity's node shows after its observation re-runs (round \(round))")
            samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
            let shown = (0..<count).filter { page.nodes["n\($0)"]?.view.isHidden == false }
            XCTAssertEqual(shown.count, round + 1, "only the changed entity's node changed")
        }
        samples.sort()
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        print("PERF visibleWhen 300 nodes, one change: p50 \(samples[samples.count / 2]) ms, p95 \(p95) ms, worst \(samples.last ?? 0) ms")
        XCTAssertLessThan(p95, 16, "one entity change stays inside a 60 Hz frame on the main thread")
    }

    // MARK: Viewer, tabs, local tabs and the pending-command guard

    private static func note(id: String = "note", rule: String) -> String {
        "{\"id\":\"\(id)\",\"title\":\"Note\",\"type\":\"text\",\"layout\":{\"span\":1},\"visibleWhen\":\(rule),\"props\":{\"value\":{\"type\":\"literal\",\"value\":\"Hi\"},\"style\":\"body\",\"unavailableText\":\"None\"}}"
    }

    func testViewerRulesResolveFromTheCachedUserAtTheFirstFrameAndFollowTheLoadedUser() async throws {
        let mine = Self.note(id: "mine", rule: "{\"type\":\"viewer\",\"userIds\":[\"u1\"]}")
        let theirs = Self.note(id: "theirs", rule: "{\"type\":\"viewer\",\"userIds\":[\"u2\"]}")
        let admin = Self.note(id: "admin", rule: "{\"type\":\"viewer\",\"isAdmin\":true}")
        let adminHidden = Self.note(id: "admin-hidden", rule: "{\"type\":\"viewer\",\"isAdmin\":true}")
            .replacingOccurrences(of: "\"visibleWhen\"", with: "\"whenUnknown\":\"hide\",\"visibleWhen\"")
        for width in Self.widths {
            let (host, _, window) = try await renderer(width: width, components: [mine, theirs, admin, adminHidden], caller: HostedCaller(),
                                                 capabilities: ["sh.visible-when@1"], seed: "u1")
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            // Nothing has been loaded from the connection: the seeded id alone answers on the first frame.
            XCTAssertNil(host.viewerSource.user)
            XCTAssertEqual(page.nodes["mine"]?.view.isHidden, false, "the seeded user's own rule shows without a flicker (width \(width))")
            XCTAssertEqual(page.nodes["theirs"]?.view.isHidden, true)
            XCTAssertEqual(page.nodes["admin"]?.view.isHidden, false, "isAdmin is unknown: a never-answered keep rule shows")
            XCTAssertEqual(page.nodes["admin-hidden"]?.view.isHidden, true, "whenUnknown hide holds the node back until the connection says")
            host.viewerSource.set(HassUser(id: "u1", name: "One", isOwner: false, isAdmin: true))
            await settle()
            XCTAssertEqual(page.nodes["admin"]?.view.isHidden, false)
            XCTAssertEqual(page.nodes["admin-hidden"]?.view.isHidden, false)
            XCTAssertEqual(page.nodes["mine"]?.view.isHidden, false)
            HostedPage.hideTracked()
        }
    }

    func testTabRuleLeavesAndRejoinsTheBarInPlaceAndNeverRemovesTheSelectedTab() async throws {
        let tabRule = "{\"type\":\"state\",\"sourceId\":\"guest-fan\",\"path\":[\"state\"],\"in\":[\"on\"]}"
        for width in Self.widths {
            let (host, store, window) = try await renderer(width: width, components: [], caller: HostedCaller(), capabilities: ["sh.visible-when@1"]) { root in
                let tabs = try XCTUnwrap(root["document"]?["navigation"]?["tabs"]?.array)
                guard case .object(var second) = tabs[1] else { throw ServerUIRecordFailure.invalidField }
                second["visibleWhen"] = try JSONDecoder().decode(JSONValue.self, from: Data(tabRule.utf8))
                return try ServerUIRendererFixture.changing(root, path: "/document/navigation/tabs/1", to: .object(second))
            }
            defer { window.isHidden = true }
            XCTAssertFalse(host.isTabShown("tab-beta"), "the rule starts false (width \(width))")
            XCTAssertEqual(host.tabController.viewControllers?.count, 1)
            let first = host.tabController.viewControllers?.first
            store.apply([EntityState(entityId: Self.fan, state: "on")])
            await settle()
            XCTAssertTrue(host.isTabShown("tab-beta"))
            XCTAssertEqual(host.tabController.viewControllers?.count, 2)
            XCTAssertTrue(host.tabController.viewControllers?.first === first, "the existing stack is untouched")
            try host.routeExternal(tabID: "tab-beta")
            await settle()
            store.apply([EntityState(entityId: Self.fan, state: "off")])
            await settle()
            XCTAssertFalse(host.isTabShown("tab-beta"))
            XCTAssertEqual(host.tabController.viewControllers?.count, 2, "the tab being shown stays until the person leaves it")
            HostedPage.hideTracked()
        }
    }

    func testLocalTabsSelectOnceWhenARuleNewlyMatchesAndThePersonsChoiceStands() async throws {
        let tabs = """
        {"id":"tabs","title":"Tabs","type":"local-tabs","layout":{"span":1},
         "props":{"stateId":"panel","transition":"canonical-swap@1","automatic":[{"tabId":"b","selectedWhen":\(Self.isOn)}]},
         "tabs":[{"id":"a","label":"A","children":[]},{"id":"b","label":"B","children":[]}]}
        """
        let state = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"id":"panel","type":"choice","initial":"a","options":[{"id":"a","label":"A"},{"id":"b","label":"B"}]}
        """.utf8))
        for width in Self.widths {
            let (host, store, window) = try await renderer(width: width, components: [tabs], caller: HostedCaller(),
                capabilities: ["sh.local-tabs@1", "sh.local-state@1", "sh.selected-when@1"], localState: [state])
            defer { window.isHidden = true }
            XCTAssertEqual(host.localState.values["panel"], .string("a"), "no rule matches at first (width \(width))")
            store.apply([EntityState(entityId: Self.fan, state: "on")])
            await settle()
            XCTAssertEqual(host.localState.values["panel"], .string("b"), "the rule newly matches: its panel is selected")
            let page = try ServerUIRendererFixture.root(host)
            try host.perform(.setLocal(stateId: "panel", value: .string("a")), from: page)
            await settle()
            XCTAssertEqual(host.localState.values["panel"], .string("a"), "the person's own choice stands while the rule keeps holding")
            HostedPage.hideTracked()
        }
    }

    func testANodeWithACallOnItsWayIsNotHiddenUnderTheFinger() async throws {
        let caller = HostedCaller()
        let row = Self.row(id: "fan-row", on: Self.call("turn_on", optimistic: "on"), off: Self.call("turn_off", optimistic: "off"))
            .replacingOccurrences(of: "\"layout\":{\"span\":1},", with: "\"layout\":{\"span\":1},\"visibleWhen\":\(Self.isOn),")
        let (host, store, window) = try await renderer(width: 390, state: "on", components: [row], caller: caller, capabilities: Self.bound + ["sh.visible-when@1"])
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        let view = try XCTUnwrap(page.nodes["fan-row"]?.view)
        XCTAssertFalse(view.isHidden)
        let control = try XCTUnwrap(view as? UKServerUILocalControl)
        let toggle = try XCTUnwrap(control.drawnControl as? UISwitch ?? HostedPage.descendants(of: control).compactMap { $0 as? UISwitch }.first)
        XCTAssertTrue(toggle.isOn)
        toggle.isOn = false
        toggle.sendActions(for: .valueChanged)
        await settle()
        XCTAssertEqual(host.callRunner.pendingState(Self.fan), "off", "the optimistic value now says the rule is false")
        XCTAssertFalse(view.isHidden, "the control with a call on its way stays on screen")
        store.apply([EntityState(entityId: Self.fan, state: "off")])
        await host.callRunner.waitForCalls()
        await settle()
        XCTAssertTrue(view.isHidden, "once the call is settled the rule applies")
    }
}
