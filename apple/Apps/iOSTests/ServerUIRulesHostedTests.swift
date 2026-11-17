@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - `enabledWhen` on bound controls (`sh.enabled-when@1`)

/// Hosted UX and accessibility checks for a control that follows an `enabledWhen` rule, at the widths of the parent's iPhone, Duo
/// (folded and unfolded) and iPad destinations.
@MainActor
final class ServerUIRulesHostedTests: XCTestCase {
    private static let widths: [CGFloat] = [390, 540, 720, 1024]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private static let capabilities = ["sh.bound-control@1", "sh.call-service@1", "sh.operands@1", "sh.enabled-when@1"]
    private static let fan = "fan.demo_bath_fan"
    private static let isOn = "{\"type\":\"state\",\"sourceId\":\"guest-fan\",\"path\":[\"state\"],\"in\":[\"on\"]}"
    private static let call = "{\"type\":\"call-service\",\"domain\":\"fan\",\"service\":\"turn_on\",\"target\":{\"entity_id\":{\"type\":\"literal\",\"value\":\"\(fan)\"}}}"

    /// A toggle row that can be used only while the fan is on; `unknown` is what it does when the fan cannot be read.
    private static func row(unknown: String) -> String {
        "{\"id\":\"fan-row\",\"title\":\"Guest Fan\",\"type\":\"bound-control\",\"layout\":{\"span\":1},\"enabledWhen\":{\"condition\":\(isOn),\"whenUnknown\":\"\(unknown)\"},\"props\":{\"kind\":\"toggle\",\"surface\":\"row\",\"isOn\":\(isOn),\"unavailableText\":\"Unavailable\"},\"icon\":{\"type\":\"sf-symbol\",\"name\":\"fan\",\"rendering\":\"canonical\",\"unavailable\":\"reject\"},\"onAction\":\(call),\"offAction\":\(call)}"
    }

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

    private func settle() async {
        for _ in 0..<6 { await Task.yield() }
        await HostedPage.pump(passes: 3)
    }

    private func control(_ host: UKServerUIRenderer) throws -> UKServerUILocalControl {
        let page = try ServerUIRendererFixture.root(host)
        return try XCTUnwrap(page.nodes["fan-row"]?.view as? UKServerUILocalControl)
    }

    func testARuleThatSaysNoDisablesTheControlInPlaceAndTellsVoiceOver() async throws {
        for width in Self.widths {
            let (host, store, window) = try await renderer(width: width, components: [Self.row(unknown: "disabled")], caller: HostedCaller(),
                                                           capabilities: Self.capabilities)
            defer { window.isHidden = true }
            let view = try control(host)
            let drawn = try XCTUnwrap(view.drawnControl)
            XCTAssertFalse(drawn.isUserInteractionEnabled, "off: the rule says no (width \(width))")
            XCTAssertTrue(drawn.accessibilityTraits.contains(.notEnabled), "VoiceOver reads it as dimmed")
            store.apply([EntityState(entityId: Self.fan, state: "on")])
            await settle()
            XCTAssertTrue(try control(host) === view, "the same view: no reload")
            XCTAssertTrue(try XCTUnwrap(view.drawnControl).isUserInteractionEnabled)
            XCTAssertFalse(try XCTUnwrap(view.drawnControl).accessibilityTraits.contains(.notEnabled))
            HostedPage.hideTracked()
        }
    }

    func testAnUnreadableFanFollowsWhatTheRuleSaysForUnknown() async throws {
        for (unknown, expected) in [("disabled", false), ("enabled", true)] {
            let (host, _, window) = try await renderer(width: 390, state: "unavailable", components: [Self.row(unknown: unknown)],
                                                       caller: HostedCaller(), capabilities: Self.capabilities)
            defer { window.isHidden = true }
            XCTAssertEqual(host.isEnabled(node: try XCTUnwrap(ServerUIRendererFixtureNode.node(host, "fan-row"))), expected)
            HostedPage.hideTracked()
        }
    }

    func testAKeepRuleRepeatsTheLastAnswerWhenTheFanGoesUnreadable() async throws {
        let (host, store, window) = try await renderer(width: 390, state: "on", components: [Self.row(unknown: "keep")], caller: HostedCaller(),
                                                       capabilities: Self.capabilities)
        defer { window.isHidden = true }
        let node = try XCTUnwrap(ServerUIRendererFixtureNode.node(host, "fan-row"))
        XCTAssertTrue(host.isEnabled(node: node))
        store.apply([EntityState(entityId: Self.fan, state: "unavailable")])
        await settle()
        XCTAssertTrue(host.isEnabled(node: node), "keep: the last answer stands while the fan is unreadable")
    }
}

/// Finds a document node by id for the hosted rule tests.
@MainActor
private enum ServerUIRendererFixtureNode {
    static func node(_ host: UKServerUIRenderer, _ id: String) -> ServerUICompositionDocument.Node? {
        for page in host.publication.document.pages {
            for case .boundControl(let control) in page.surface.components where control.node.id == id { return control.node }
        }
        return nil
    }
}
