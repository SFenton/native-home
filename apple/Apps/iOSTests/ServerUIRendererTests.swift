import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Synthetic fixture

/// Reuses the frozen schema-2 conformance input, not a bundled dashboard or an acceptance shortcut.
@MainActor
enum ServerUIRendererFixture {
    static func json() throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUICompositionFixture.json")))
    }

    static func publication(_ json: JSONValue? = nil) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(JSONEncoder().encode(json ?? self.json()))
    }

    static func changing(_ value: JSONValue, path: String, to replacement: JSONValue) throws -> JSONValue {
        let segments = path.split(separator: "/").map(String.init)
        func replace(_ value: JSONValue, _ depth: Int) throws -> JSONValue {
            guard depth < segments.count else { return replacement }
            switch value {
            case .object(var object):
                if depth == segments.count - 1 {
                    object[segments[depth]] = replacement
                    return .object(object)
                }
                object[segments[depth]] = try replace(XCTUnwrap(object[segments[depth]]), depth + 1)
                return .object(object)
            case .array(var array):
                let index = try XCTUnwrap(Int(segments[depth]))
                array[index] = try replace(array[index], depth + 1)
                return .array(array)
            default: throw NSError(domain: "SyntheticFixturePath", code: 1)
            }
        }
        return try replace(value, 0)
    }

    static func backdrop() throws -> HouseBackdropStore {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "server-ui-renderer-\(UUID().uuidString)"))
        return HouseBackdropStore(verifiedPhoto: image,
                                  directory: URL.temporaryDirectory.appendingPathComponent("server-ui-renderer-\(UUID().uuidString)"),
                                  blur: BackdropBlurSettings(defaults: defaults))
    }

    static func host(publication: ServerUICompositionPublication? = nil,
                     size: CGSize = CGSize(width: 390, height: 844)) throws -> (UKServerUIRenderer, UIWindow, HostedCaller) {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "off")])
        let caller = HostedCaller()
        let host = try UKServerUIRenderer(publication: publication ?? self.publication(),
                                          context: UKContext(store: store, caller: caller), backdrop: backdrop())
        let window = HostedPage.show(host, size: HostedPage.inScene(size))
        HostedPage.wait(0.1)
        return (host, window, caller)
    }

    static func root(_ renderer: UKServerUIRenderer, _ id: String = "tab-alpha") throws -> UKServerUIPage {
        try XCTUnwrap(renderer.stacks[.tab(id)]?.viewControllers.first as? UKServerUIPage)
    }

    static func barItems(_ page: UKServerUIPage) -> [UIBarButtonItem] {
        let item = page.navigationItem
        return (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? [])
            + (item.leadingItemGroups + item.trailingItemGroups).flatMap(\.barButtonItems)
    }

    static func liveJSON() throws -> JSONValue {
        func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
        var root = try self.json()
        var sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        sources += try XCTUnwrap(json("""
            [{"id":"source-panel","kind":"model","model":"alarm-mode@1",
              "inputs":{"entityId":{"type":"literal","value":"alarm_control_panel.demo_panel"}}},
             {"id":"source-stock","kind":"model","model":"inventory-summary@1",
              "inputs":{"totalEntityId":{"type":"literal","value":"sensor.demo_total"},
                        "expiringEntityId":{"type":"literal","value":"sensor.demo_expiry"},
                        "spaceEntityIds":[{"type":"literal","value":"sensor.demo_space"}]},
              "labels":{"singular":"Unit","plural":"Units","expiringSuffix":"Due","separator":" / ",
                        "loadingText":"Reading stock","unavailableText":"Stock unavailable"}}]
            """).array)
        root = try changing(root, path: "/document/dataSources", to: .array(sources))
        let props = "/document/pages/0/components/0/children/1/props"
        root = try changing(root, path: props + "/selected", to: .string("none"))
        root = try changing(root, path: props + "/subtitle", to: json(#"{"type":"literal","value":""}"#))
        root = try changing(root, path: props + "/alarm", to: json("""
            {"sourceId":"source-panel","projection":"alarm-navigation@1",
             "states":[
               {"state":"disarmed","appearance":{"icon":{"type":"sf-symbol","name":"shield.slash",
                 "rendering":"canonical","unavailable":"reject"},"fill":{"type":"solid-rgb","red":67,"green":160,"blue":71},"text":"At rest"}},
               {"state":"armed_home","appearance":{"icon":{"type":"sf-symbol","name":"shield.lefthalf.filled",
                 "rendering":"canonical","unavailable":"reject"},"fill":{"type":"solid-rgb","red":30,"green":136,"blue":229},"text":"Guarding"}}],
             "fallback":{"icon":{"type":"sf-symbol","name":"shield","rendering":"canonical","unavailable":"reject"},
               "fill":{"type":"solid-rgb","red":84,"green":110,"blue":122},"text":"Panel"},
             "loadingText":"Reading panel","unavailableText":"Panel unavailable","errorText":"No response","hiddenText":"Private"}
            """))
        root = try changing(root, path: "/document/pages/2/components/0/props/value", to: json("""
            {"type":"read","from":{"type":"source","sourceId":"source-stock","path":["stateText"]},"as":"string","missing":"unavailable"}
            """))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities
            + ["sh.alarm-mode@1", "sh.inventory-summary@1", "sh.tile-presentation@1"]
        return try changing(root, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
    }
}

// MARK: - Authored settings link

@MainActor
final class ServerUISettingsLinkTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testCanonicalRowUsesAuthoredCopyAndPushesDestination() throws {
        var root = try ServerUIRendererFixture.json()
        var components = try XCTUnwrap(root["document"]?["pages"]?.array?[0]["components"]?.array)
        let link = try JSONDecoder().decode(JSONValue.self, from: Data("""
            {"id":"settings-demo","type":"settings-link","title":"Sample setting",
             "layout":{"span":1},"icon":{"type":"sf-symbol","name":"gearshape","rendering":"canonical","unavailable":"reject"},
             "props":{"subtitle":"Open details","hint":"Opens details","showsChevron":true},
             "action":{"type":"push","pageId":"page-echo","arguments":{},"origin":"sender","duplicate":"reuse-nearest"}}
            """.utf8))
        components.append(link)
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(components))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities + ["sh.settings-link@1"]
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities",
                                                     to: .array(capabilities.sorted().map(JSONValue.string)))
        let (host, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(root))
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        let wrapper = try XCTUnwrap(page.nodes["settings-demo"]?.view as? UKServerUISettingsLink)
        let row = wrapper.cell
        XCTAssertGreaterThan(wrapper.bounds.height, 44)
        XCTAssertEqual(row.accessibilityLabel, UKRowView.accessibilityLabel(title: "Sample setting", subtitle: "Open details"))
        XCTAssertEqual(row.accessibilityHint, "Opens details")
        XCTAssertTrue(row.accessibilityTraits.contains(.button))
        row.sendActions(for: .touchUpInside)
        HostedPage.wait(0.1)
        XCTAssertEqual((host.stacks[.tab("tab-alpha")]?.topViewController as? UKServerUIPage)?.surfaceID, "page-echo")
    }
}

// MARK: - Configured live adapter lifetimes

@MainActor
private final class ServerUIDelayedCaller: HassServiceCalling {
    var calls: [String] = []
    var targets: [String?] = []
    private var continuation: CheckedContinuation<Void, Error>?
    private var started: CheckedContinuation<Void, Never>?
    struct Failure: Error {}

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append("\(domain).\(service)")
        targets.append(data["entity_id"] as? String)
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func complete(failing: Bool = false) {
        let continuation = continuation
        self.continuation = nil
        if failing { continuation?.resume(throwing: Failure()) } else { continuation?.resume() }
    }
}

@MainActor
final class ServerUILiveAdaptersTests: XCTestCase {
    func testSupportingTextUsesCanonicalTypeAndInkAcrossFamiliesAndTextSizes() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            var json = try ServerUIRendererFixture.json()
            var nodes = try XCTUnwrap(json["document"]?["pages"]?.array?[0]["components"]?.array)
            for style in ["subheadline", "footnote", "section-title"] {
                nodes.append(.object(["id": .string("supporting-" + style), "type": "text", "title": "Details",
                    "layout": .object(["span": .number(1)]), "props": .object([
                        "value": .object(["type": "literal", "value": "Supporting details wrap with larger text."]),
                        "style": .string(style), "unavailableText": "Unavailable"])]))
            }
            json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(nodes))
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities",
                to: .array((ServerUICompositionPublication.firstSliceCapabilities + ["sh.supporting-text-styles@1", "sh.section-title@1"]).sorted().map(JSONValue.string)))
            let (renderer, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(json), size: size)
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(renderer)
            let canonicalHeading = UKBedroomSectionHeader(title: "Supporting details wrap with larger text.")
            canonicalHeading.isHidden = true
            renderer.view.addSubview(canonicalHeading)
            let canonicalLabel = try XCTUnwrap(HostedPage.descendants(of: canonicalHeading).compactMap { $0 as? UILabel }.first)
            for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                renderer.traitOverrides.preferredContentSizeCategory = category
                HostedPage.wait(0.1)
                for (name, style) in [("subheadline", UIFont.TextStyle.subheadline), ("footnote", .footnote), ("section-title", .title3)] {
                    let view = try XCTUnwrap(page.nodes["supporting-" + name]?.view)
                    let label = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UILabel }.first)
                    let expectedSize = name == "section-title" ? canonicalLabel.font.pointSize
                        : UIFont.preferredFont(forTextStyle: style, compatibleWith: label.traitCollection).pointSize
                    XCTAssertEqual(label.font.pointSize, expectedSize)
                    let ink = name == "section-title" ? UKDesignInk.primary : UKDesignInk.secondary
                    XCTAssertEqual(label.textColor.resolvedColor(with: label.traitCollection), ink.resolvedColor(with: label.traitCollection))
                    XCTAssertEqual(view.accessibilityTraits, name == "section-title" ? .header : .staticText)
                    if name == "section-title" {
                        XCTAssertEqual(label.font, canonicalLabel.font)
                    }
                    XCTAssertGreaterThanOrEqual(view.bounds.height, label.sizeThatFits(CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)).height)
                    XCTAssertEqual(view.accessibilityLabel, label.text)
                }
            }
        }
    }

    private let panel = "alarm_control_panel.demo_panel"

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func liveHost(caller: any HassServiceCalling, state: String = "disarmed") throws -> (UKServerUIRenderer, UIWindow) {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: panel, state: state)])
        let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(ServerUIRendererFixture.liveJSON()),
                                          context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop())
        let size = HostedPage.inScene(CGSize(width: 390, height: 844))
        let window = HostedPage.show(host, size: size)
        HostedPage.wait(0.1)
        return (host, window)
    }

    func testTrackedNetworkLifetimePinsSourceAndComponentWithoutAnOptimisticOverlay() async throws {
        let caller = ServerUIDelayedCaller()
        defer { caller.complete() }
        // The flap guard's release is fired by hand below, so no clock decides when the held error shows.
        let flapGuard = HandScheduler()
        UKStateTileTransition.schedulerOverride = flapGuard
        let (host, window) = try liveHost(caller: caller)
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let tile = try XCTUnwrap(root.nodes["node-open-echo"]?.view as? UKGlassTileView)
        let source = try XCTUnwrap(host.bindings.alarms["source-panel"])
        let disc = try XCTUnwrap(tile.accessibilityElements?.compactMap { $0 as? UKTileActionDisc }.first)
        disc.sendActions(for: .touchUpInside)
        await caller.waitForStart()
        XCTAssertEqual(caller.calls, ["alarm_control_panel.alarm_arm_home"])
        XCTAssertEqual(caller.targets, [panel])
        XCTAssertTrue(source.hasPendingIntent)
        XCTAssertFalse(try XCTUnwrap(source.actions).isPending(panel), "Tracked alarm network lifetime has no optimistic override.")
        XCTAssertEqual(source.projection.spec.phase, .inFlight)
        XCTAssertThrowsError(try source.reserve())

        var candidate = try ServerUIRendererFixture.liveJSON()
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/document/dataSources/2/inputs/entityId/value", to: .string("alarm_control_panel.demo_other"))
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(candidate)))
        candidate = try ServerUIRendererFixture.liveJSON()
        let children = try XCTUnwrap(candidate["document"]?["pages"]?.array?[0]["components"]?.array?[0]["children"]?.array)
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/document/pages/0/components/0/children", to: .array([children[0]]))
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(candidate)))
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/document/pages/1/components", to: .array([children[1]]))
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(candidate)), "Moving the same ID to a different sender surface is not a harmless rebinding.")
        candidate = try ServerUIRendererFixture.liveJSON()
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/document/pages/0/components/0/children/1/action/pageId", to: .string("page-lattice"))
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(candidate)))

        let completion = source.completion
        caller.complete(failing: true)
        await completion?.value
        XCTAssertFalse(source.hasPendingIntent)
        XCTAssertTrue(source.projection.failed)
        // The flap guard holds the whole look, an error included, until the in-progress look has shown for 1.0 s
        // (.agents/design/state-styled-tile.md, Flap guard: "An error waits too."). The release is a MainActor task, so the test must
        // suspend to let it run; spinning the run loop inside this MainActor test body never would.
        await HostedPage.settle { !flapGuard.pending.isEmpty || tile.model.subtitle == "No response" }
        flapGuard.fire()
        XCTAssertTrue(tile.model.isError)
        XCTAssertEqual(tile.model.subtitle, "No response")
        try host.validateUpdate(ServerUIRendererFixture.publication(candidate))
    }

    /// Runs on the parent's iPhone, Duo and iPad hosted families: body and disc are separate accessible controls.
    func testNavigationBodyNeverSendsAnAlarmCommandAndLiveAppearanceKeepsTheTile() throws {
        let caller = HostedCaller(), (host, window) = try liveHost(caller: caller)
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let tile = try XCTUnwrap(root.nodes["node-open-echo"]?.view as? UKGlassTileView)
        XCTAssertEqual(tile.model.fillRGB, 0x43a047)
        XCTAssertEqual(tile.model.subtitle, "At rest")
        host.pageContext.store.apply([EntityState(entityId: panel, state: "armed_home")])
        HostedPage.until { tile.model.subtitle == "Guarding" }
        XCTAssertEqual(tile.model.fillRGB, 0x1e88e5)
        XCTAssertEqual(tile.model.symbol, "shield.lefthalf.filled")
        let disc = try XCTUnwrap(tile.accessibilityElements?.compactMap { $0 as? UKTileActionDisc }.first)
        XCTAssertEqual(disc.accessibilityLabel, "Disarm Inspect Sample")
        XCTAssertTrue(disc.accessibilityTraits.contains(.button))
        let body = try XCTUnwrap(tile.accessibilityElements?.first as? UKTileAccessibilityElement)
        XCTAssertTrue(body.accessibilityActivate())
        XCTAssertTrue(caller.calls.isEmpty)
        XCTAssertNil(FeatureHost.alert(on: root))
        XCTAssertEqual(host.navigation.snapshot.stacks[.tab("tab-alpha")]?.last, "page-echo")
        XCTAssertTrue(root.nodes["node-open-echo"]?.view === tile)
    }

    func testDisarmRequiresProviderConfirmationCancellationAndExecutionRevalidation() async throws {
        let caller = HostedCaller(), (host, window) = try liveHost(caller: caller, state: "armed_home")
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let tile = try XCTUnwrap(root.nodes["node-open-echo"]?.view as? UKGlassTileView)
        let source = try XCTUnwrap(host.bindings.alarms["source-panel"])
        func disc() throws -> UKTileActionDisc {
            try XCTUnwrap(tile.accessibilityElements?.compactMap { $0 as? UKTileActionDisc }.first)
        }
        try disc().sendActions(for: .touchUpInside)
        var alert = try XCTUnwrap(FeatureHost.alert(on: root))
        let firstPresented = await FeatureHost.settleAsync(until: { !alert.isBeingPresented })
        XCTAssertTrue(firstPresented)
        XCTAssertEqual(alert.title, StateStyle.alarmDisarmConfirmation.title)
        XCTAssertEqual(alert.message, StateStyle.alarmDisarmConfirmation.message)
        XCTAssertTrue(caller.calls.isEmpty)
        XCTAssertTrue(source.hasPendingIntent)
        let cancelled = try XCTUnwrap(source.confirmation)
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(ServerUIRendererFixture.liveJSON())))
        let replacement = try ServerUIRendererFixture.changing(ServerUIRendererFixture.liveJSON(),
            path: "/document/dataSources/2/inputs/entityId/value", to: .string("alarm_control_panel.demo_other"))
        XCTAssertThrowsError(try host.bindings.validateReplacement(ServerUIRendererFixture.publication(replacement).document.dataSources))
        XCTAssertTrue(FeatureHost.answer(alert, "Cancel"))
        XCTAssertFalse(source.hasPendingIntent)
        XCTAssertThrowsError(try source.execute(cancelled))
        let cancelDismissed = await FeatureHost.settleAsync(until: { FeatureHost.alert(on: root) == nil })
        XCTAssertTrue(cancelDismissed)

        var failures: [UKServerUIRendererError] = []
        host.onError = { failures.append($0) }
        try disc().sendActions(for: .touchUpInside)
        alert = try XCTUnwrap(FeatureHost.alert(on: root))
        let secondPresented = await FeatureHost.settleAsync(until: { !alert.isBeingPresented })
        XCTAssertTrue(secondPresented)
        host.pageContext.store.apply([EntityState(entityId: panel, state: "disarmed")])
        let disarmed = await FeatureHost.settleAsync(until: { tile.model.subtitle == "At rest" })
        XCTAssertTrue(disarmed)
        XCTAssertTrue(FeatureHost.answer(alert, "Disarm"))
        XCTAssertFalse(source.hasPendingIntent)
        XCTAssertTrue(caller.calls.isEmpty, "A stale Disarm question must not turn into Arm Home.")
        XCTAssertEqual(failures.last?.code, .unavailableSource)
        let staleDismissed = await FeatureHost.settleAsync(until: { FeatureHost.alert(on: root) == nil })
        XCTAssertTrue(staleDismissed)

        host.pageContext.store.apply([EntityState(entityId: panel, state: "armed_home")])
        let armed = await FeatureHost.settleAsync(until: { tile.model.subtitle == "Guarding" })
        XCTAssertTrue(armed)
        try disc().sendActions(for: .touchUpInside)
        alert = try XCTUnwrap(FeatureHost.alert(on: root))
        let thirdPresented = await FeatureHost.settleAsync(until: { !alert.isBeingPresented })
        XCTAssertTrue(thirdPresented)
        XCTAssertTrue(FeatureHost.answer(alert, "Disarm"))
        let completion = try XCTUnwrap(source.completion)
        await completion.value
        XCTAssertEqual(caller.calls, ["alarm_control_panel.alarm_disarm"])
        XCTAssertEqual(caller.data.first?["entity_id"] as? String, panel)
    }

    func testUnavailableAndLoadingAlarmDiscCannotSendButNavigationStaysEnabled() throws {
        let caller = HostedCaller(), (host, window) = try liveHost(caller: caller, state: "unavailable")
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let tile = try XCTUnwrap(root.nodes["node-open-echo"]?.view as? UKGlassTileView)
        let source = try XCTUnwrap(host.bindings.alarms["source-panel"])
        XCTAssertEqual(tile.model.subtitle, "Panel unavailable")
        XCTAssertTrue(tile.isEnabled)
        XCTAssertThrowsError(try source.reserve())
        let disc = try XCTUnwrap(tile.accessibilityElements?.compactMap { $0 as? UKTileActionDisc }.first)
        XCTAssertFalse(disc.isEnabled)
        XCTAssertTrue(caller.calls.isEmpty)
        let store = EntityStore()
        let loading = UKServerUIAlarmSource(entityID: panel, context: UKContext(store: store, caller: caller).with { $0.valuesPending = true })
        XCTAssertThrowsError(try loading.reserve())
        store.replaceAll([EntityState(entityId: panel, state: "arming")])
        XCTAssertEqual(loading.projection.spec.phase, .ready)
        XCTAssertEqual(loading.projection.spec.verb, "Disarm")
        store.apply([EntityState(entityId: panel, state: "pending")])
        XCTAssertEqual(loading.projection.spec.phase, .ready)
        store.apply([EntityState(entityId: panel, state: "disarming")])
        XCTAssertEqual(loading.projection.spec.phase, .inFlight)
        let readOnly = UKServerUIAlarmSource(entityID: panel, context: UKContext(store: store))
        XCTAssertThrowsError(try readOnly.reserve())
    }

    func testInventoryUsesLiveBoxesExplicitUnavailableCopyAndOnlyTheSelectedCountInputs() throws {
        let publication = try ServerUIRendererFixture.publication(ServerUIRendererFixture.liveJSON())
        let store = EntityStore()
        var context = UKContext(store: store)
        context.valuesPending = true
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: context)
        guard case .text(let text) = publication.document.pages[2].surface.components[0] else { return XCTFail("Expected summary read") }
        XCTAssertEqual(bindings.string(text.value).value, "Reading stock")
        store.replaceAll([EntityState(entityId: "sensor.demo_total", state: "1"),
                          EntityState(entityId: "sensor.demo_expiry", state: "2")])
        let bag = UKObservationBag()
        var values: [String?] = []
        bag.observe { values.append(bindings.string(text.value).value) }
        XCTAssertEqual(values, ["1 Unit / 2 Due"])
        store.apply([EntityState(entityId: "sensor.demo_unrelated", state: "50"),
                     EntityState(entityId: "sensor.demo_space", state: "8")])
        HostedPage.wait(0.02)
        XCTAssertEqual(values.count, 1, "A nonzero total observes no unrelated or fallback-space boxes.")
        store.apply([EntityState(entityId: "sensor.demo_total", state: "0")])
        XCTAssertTrue(HostedPage.until { values.last ?? nil == "8 Units / 2 Due" })
        store.apply([EntityState(entityId: "sensor.demo_space", state: "NaN")])
        XCTAssertTrue(HostedPage.until { values.last ?? nil == "Stock unavailable" })
        XCTAssertEqual(bindings.string(text.value).value, "Stock unavailable")
        bag.removeAll()
    }
}

// MARK: - Acceptance and native composition

@MainActor
final class ServerUIRendererPreflightTests: XCTestCase {
    func testInventorySourceCannotPassWithoutCollectionHost() throws {
        var json = try ServerUIRendererFixture.json()
        var sources = try XCTUnwrap(json["document"]?["dataSources"]?.array)
        sources.append(.object([
            "id": .string("source-items"), "kind": .string("model"), "model": .string("inventory-list@1"),
            "inputs": .object(["space": .string("fridge")])
        ]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources))
        let capabilities = (ServerUICompositionPublication.firstSliceCapabilities + ["sh.inventory-list@1"]).sorted()
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.map(JSONValue.string)))
        let publication = try ServerUIRendererFixture.publication(json)
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(publication)) {
            XCTAssertEqual($0 as? UKServerUIRendererError,
                           UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources/2"))
        }
        let client = EverShelfClient(caller: EverShelfFixtureServer.sample())
        func registry(space: InventorySpace) throws -> UKServerUIRecords {
            let provider = try InventoryCompositionProvider(sourceID: "source-items", space: space,
                model: InventoryListModel(space: space, client: client))
            return UKServerUIRecords(collections: ["source-items": UKServerUIInventoryCollection(provider)])
        }
        XCTAssertNoThrow(try UKServerUIRenderer.preflight(publication, records: registry(space: .fridge)))
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(publication, records: registry(space: .pantry)))
    }

    func testUnsupportedScrimAndIndependentInitialWithTabsFailBeforeHosting() throws {
        let fixture = try ServerUIRendererFixture.json()
        let gradient: JSONValue = .object([
            "type": .string("gradient"),
            "stops": .array([.object(["location": .number(0), "opacity": .number(0.2)]),
                             .object(["location": .number(1), "opacity": .number(0.4)])]),
            "increasedContrastBoost": .number(0.05),
        ])
        for (path, value) in [
            ("/document/theme/background/scrim", gradient),
            ("/document/navigation/initialTabId", .null),
        ] {
            let publication = try ServerUIRendererFixture.publication(ServerUIRendererFixture.changing(fixture, path: path, to: value))
            XCTAssertThrowsError(try UKServerUIRenderer.preflight(publication)) {
                XCTAssertEqual(($0 as? UKServerUIRendererError)?.pointer, path)
            }
        }
    }
}

@MainActor
final class ServerUIRendererNavigationTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testConfiguredChromeAndGridUseCanonicalNativeViewsWithoutLegacyItems() throws {
        let (host, window, _) = try ServerUIRendererFixture.host()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let grid = try XCTUnwrap(root.nodes["node-orbit-grid"]?.view as? UKDynamicGridView)
        XCTAssertEqual(grid.configuration.minCellWidth, 150)
        XCTAssertEqual(grid.configuration.spacing, 12)
        XCTAssertEqual(root.body?.padding, UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        XCTAssertFalse(root.isSectionRoot)
        XCTAssertTrue(root.nodes["node-output"]?.view is UKGlassTileView)
        let allItems = ServerUIRendererFixture.barItems(root)
        XCTAssertTrue(allItems.contains { $0.accessibilityIdentifier == "chrome-inspect" })
        XCTAssertTrue(allItems.contains { $0.accessibilityIdentifier == "chrome-palette" && $0.accessibilityLabel == "Palette" })
        XCTAssertFalse(allItems.contains { $0.accessibilityIdentifier == "quickLinks.open" || $0.accessibilityIdentifier == "nav.profile" })
    }

    func testAuthoredTilePresentationUsesNativeFaceAndRetainsIdentity() throws {
        var json = try ServerUIRendererFixture.json()
        let props = "/document/pages/0/components/0/children/1/props"
        let presentation: JSONValue = .object([
            "layout": .string("anchored-bottom"), "titleLines": .number(2),
            "fill": .object(["type": .string("solid-rgb"), "red": .number(42), "green": .number(128), "blue": .number(255)]),
            "bodyHint": .string("Opens the sample page"),
        ])
        json = try ServerUIRendererFixture.changing(json, path: props + "/presentation", to: presentation)
        json = try ServerUIRendererFixture.changing(json, path: props + "/selected", to: .string("none"))
        var capabilities = try XCTUnwrap(json["capabilities"]?.array)
        capabilities.insert(.string("sh.tile-presentation@1"), at: capabilities.count - 1)
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities))
        let (host, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(json))
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let tile = try XCTUnwrap(root.nodes["node-open-echo"]?.view as? UKGlassTileView)
        XCTAssertEqual(tile.environment.layout, .anchoredBottom)
        XCTAssertEqual(tile.environment.titleLines, 2)
        XCTAssertEqual(tile.model.fillRGB, 0x2a80ff)
        XCTAssertEqual(tile.model.bodyHint, "Opens the sample page")
        XCTAssertFalse(tile.model.isActive)
        let body = try XCTUnwrap(tile.accessibilityElements?.first as? UKTileAccessibilityElement)
        XCTAssertEqual(body.accessibilityHint, "Opens the sample page")

        json = try ServerUIRendererFixture.changing(json, path: "/revision", to: .number(2))
        json = try ServerUIRendererFixture.changing(json, path: props + "/presentation/fill/red", to: .number(20))
        try host.apply(publication: ServerUIRendererFixture.publication(json), backdrop: root.context.backdrop!)
        XCTAssertTrue(root.nodes["node-open-echo"]?.view === tile)
        XCTAssertEqual(tile.model.fillRGB, 0x1480ff)
    }

    func testEmptyNavigationSubtitleMatchesCanonicalNoSubtitleLayout() throws {
        var json = try ServerUIRendererFixture.json()
        let props = "/document/pages/0/components/0/children/1/props"
        json = try ServerUIRendererFixture.changing(json, path: props + "/subtitle",
                                                  to: .object(["type": .string("literal"), "value": .string("")]))
        json = try ServerUIRendererFixture.changing(json, path: props + "/presentation", to: .object([
            "layout": .string("anchored-bottom"), "titleLines": .number(2),
            "fill": .object(["type": .string("standard")]),
        ]))
        var capabilities = try XCTUnwrap(json["capabilities"]?.array)
        capabilities.insert(.string("sh.tile-presentation@1"), at: capabilities.count - 1)
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities))
        let (host, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(json))
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let tile = try XCTUnwrap(root.nodes["node-open-echo"]?.view as? UKGlassTileView)
        XCTAssertNil(tile.model.subtitle)

        func titleFrame(_ model: UKGlassTileModel) throws -> CGRect {
            let view = UKGlassTileView(model: model)
            root.view.addSubview(view)
            defer { view.removeFromSuperview() }
            view.configure(model, environment: tile.environment, animated: false)
            view.frame = CGRect(x: 0, y: 0, width: 342, height: 112)
            view.layoutIfNeeded()
            let label = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UILabel }
                .first { $0.text == model.title && !$0.isHidden })
            return view.convert(label.bounds, from: label)
        }

        var canonical = tile.model
        canonical.subtitle = nil
        let canonicalFrame = try titleFrame(canonical)
        XCTAssertEqual(try titleFrame(tile.model), canonicalFrame, "An empty authored subtitle reserves no text spacing")
        var emptySubtitle = canonical
        emptySubtitle.subtitle = ""
        XCTAssertEqual(canonicalFrame.minY - (try titleFrame(emptySubtitle)).minY, 2, accuracy: 0.01,
                       "The regression distinguishes canonical absence from a nonnil empty subtitle")
    }

    func testNavigationSubtitlePreservesNonemptyLiteralAndLiveReadValues() throws {
        var json = try ServerUIRendererFixture.json()
        let subtitle = "/document/pages/0/components/0/children/1/props/subtitle"
        json = try ServerUIRendererFixture.changing(json, path: subtitle,
                                                  to: .object(["type": .string("literal"), "value": .string("Configured subtitle")]))
        let (host, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(json))
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let tile = try XCTUnwrap(root.nodes["node-open-echo"]?.view as? UKGlassTileView)
        XCTAssertEqual(tile.model.subtitle, "Configured subtitle")
        host.pageContext.store.apply([EntityState(entityId: "switch.demo_lamp", state: "off",
                                                  attributes: ["subtitle": .string("Live subtitle")])])
        json = try ServerUIRendererFixture.changing(json, path: "/revision", to: .number(2))
        json = try ServerUIRendererFixture.changing(json, path: subtitle, to: .object([
            "type": .string("read"), "as": .string("string"), "missing": .string("unavailable"),
            "from": .object(["type": .string("source"), "sourceId": .string("source-entity"),
                             "path": .array([.string("attributes"), .string("subtitle")])]),
        ]))
        try host.apply(publication: ServerUIRendererFixture.publication(json), backdrop: root.context.backdrop!)
        XCTAssertEqual(tile.model.subtitle, "Live subtitle")
        host.pageContext.store.apply([EntityState(entityId: "switch.demo_lamp", state: "off",
                                                  attributes: ["subtitle": .string("")])])
        HostedPage.until { tile.model.subtitle == nil }
        XCTAssertNil(tile.model.subtitle)
        host.pageContext.store.apply([EntityState(entityId: "switch.demo_lamp", state: "off",
                                                  attributes: ["subtitle": .string("Updated subtitle")])])
        HostedPage.until { tile.model.subtitle == "Updated subtitle" }
        XCTAssertEqual(tile.model.subtitle, "Updated subtitle")
    }

    func testArbitraryPushTabPathsAndCancelledInteractivePopKeepTheirInstances() throws {
        let (host, window, _) = try ServerUIRendererFixture.host()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        guard case .grid(let grid) = root.definition.components[0],
              case .navigationTile(let tile) = grid.children[1] else { return XCTFail("Fixture navigation tile") }
        try host.perform(tile.action, from: root)
        HostedPage.until { host.stacks[.tab("tab-alpha")]?.transitionCoordinator == nil }
        let nav = try XCTUnwrap(host.stacks[.tab("tab-alpha")])
        let detail = try XCTUnwrap(nav.topViewController as? UKServerUIPage)
        XCTAssertEqual(detail.surfaceID, "page-echo")
        XCTAssertEqual(host.navigation.snapshot.stacks[.tab("tab-alpha")], ["page-orbit", "page-echo"])
        let delegate = try XCTUnwrap(nav.delegate as? UKServerUIStackDelegate)
        let motion = try XCTUnwrap(delegate.motion)
        motion.beginSwipe()
        motion.updateSwipe(progress: 0.2)
        motion.endSwipe(progress: 0.2, velocity: 0, cancelled: true)
        HostedPage.until { nav.transitionCoordinator == nil }
        XCTAssertTrue(nav.topViewController === detail)
        XCTAssertEqual(host.navigation.snapshot.stacks[.tab("tab-alpha")]?.count, 2)

        try host.perform(.selectTab(tabId: "tab-beta"), from: detail)
        let beta = try ServerUIRendererFixture.root(host, "tab-beta")
        try host.perform(.selectTab(tabId: "tab-alpha"), from: beta)
        XCTAssertTrue(nav.topViewController === detail)
        XCTAssertTrue(nav.viewControllers.first === root)

        try host.perform(.back, from: detail)
        HostedPage.until { nav.transitionCoordinator == nil }
        XCTAssertEqual(host.navigation.snapshot.stacks[.tab("tab-alpha")], ["page-orbit"])
        XCTAssertTrue(nav.topViewController === root)
    }

    func testPublicationAndEntityUpdatesRetainUnaffectedControllersTilesAndPowerModel() throws {
        let (host, window, _) = try ServerUIRendererFixture.host()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let tile = try XCTUnwrap(root.nodes["node-output"]?.view as? UKGlassTileView)
        let power = try XCTUnwrap(host.bindings.powers["source-power"])
        let box = host.pageContext.store.entity("switch.demo_lamp")
        var next = try ServerUIRendererFixture.json()
        next = try ServerUIRendererFixture.changing(next, path: "/revision", to: .number(2))
        next = try ServerUIRendererFixture.changing(next, path: "/document/pages/2/title", to: .string("Revised Detail"))
        let accepted = try ServerUIRendererFixture.publication(next)
        try host.apply(publication: accepted, backdrop: root.context.backdrop!)
        host.pageContext.store.apply([EntityState(entityId: "switch.demo_lamp", state: "on")])
        HostedPage.until { tile.model.subtitle == "On" }
        XCTAssertTrue(try ServerUIRendererFixture.root(host) === root)
        XCTAssertTrue(root.nodes["node-output"]?.view === tile)
        XCTAssertTrue(host.bindings.powers["source-power"] === power)
        XCTAssertTrue(host.pageContext.store.entity("switch.demo_lamp") === box)
        XCTAssertEqual(tile.model.subtitle, "On")
    }

    /// The same hosted accessibility journey runs unchanged on iPhone, Duo and iPad.
    func testVoiceOverPowerActivationUsesCanonicalSemanticsAndSendsOneExplicitCall() async throws {
        let (host, window, caller) = try ServerUIRendererFixture.host()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let tile = try XCTUnwrap(root.nodes["node-output"]?.view as? UKGlassTileView)
        let body = try XCTUnwrap(tile.accessibilityElements?.first as? UKTileAccessibilityElement)
        XCTAssertEqual(body.accessibilityLabel, "Sample Output")
        XCTAssertEqual(body.accessibilityValue, "Off")
        XCTAssertTrue(body.accessibilityTraits.contains(.button))
        XCTAssertTrue(body.accessibilityActivate())
        let power = try XCTUnwrap(host.bindings.powers["source-power"])
        let actions = try XCTUnwrap(power.actions["switch.demo_lamp"])
        await actions.waitForCalls()
        XCTAssertEqual(caller.calls, ["switch.turn_on"])
        XCTAssertEqual(caller.data.first?["entity_id"] as? String, "switch.demo_lamp")
    }

    func testFullHeightModalHasLocalPathAndBlocksTabSwitchThenDismissesBeforePush() throws {
        let (host, window, _) = try ServerUIRendererFixture.host()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let palette = host.publication.document.navigation.chrome.groups[1].items[0]
        guard case .button(let button) = palette else { return XCTFail("Fixture chrome button") }
        try host.perform(button.action, from: root)
        HostedPage.until { host.modal?.presentingViewController != nil && host.modal?.transitionCoordinator == nil }
        let modal = try XCTUnwrap(host.modal)
        let page = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
        XCTAssertEqual(modal.options.height, .full)
        XCTAssertEqual(modal.options.width, .form)
        XCTAssertTrue(modal.options.closeStaysInBar)
        XCTAssertEqual(page.context.surface, .sheet)
        XCTAssertFalse(modal.view.gestureRecognizers?.contains { $0.name == "UKStackMotion.edgePan" } == true,
                       "A composed sheet keeps UIKit's modal navigation, not the wallpaper-page edge driver.")
        XCTAssertNotNil(ServerUIRendererFixture.barItems(page).first { $0.accessibilityIdentifier == "server-ui.sheet.close" })
        let selection = host.navigation.snapshot.selection
        XCTAssertThrowsError(try host.perform(.selectTab(tabId: "tab-beta"), from: page))
        XCTAssertEqual(host.navigation.snapshot.selection, selection)

        guard case .navigationTile(let local) = page.definition.components[1],
              case .navigationTile(let external) = page.definition.components[2] else { return XCTFail("Fixture sheet tiles") }
        try host.perform(local.action, from: page)
        HostedPage.until { modal.transitionCoordinator == nil }
        XCTAssertEqual(host.navigation.snapshot.presentations.last?.pages, ["page-echo"])
        XCTAssertTrue(modal.viewControllers.first === page)
        let pushed = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
        let delegate = try XCTUnwrap(modal.delegate as? UKServerUIStackDelegate)
        XCTAssertNil(delegate.navigationController(modal, animationControllerFor: .pop, from: pushed, to: page),
                     "The canonical modal owns push/pop animation and its inset lifecycle.")
        XCTAssertNil(ServerUIRendererFixture.barItems(pushed).first { $0.accessibilityIdentifier == "server-ui.sheet.close" })
        XCTAssertTrue(pushed.accessibilityPerformEscape())
        HostedPage.until { modal.transitionCoordinator == nil }
        XCTAssertEqual(host.navigation.snapshot.presentations.last?.pages, [])
        try host.perform(external.action, from: page)
        HostedPage.until { host.modal == nil && host.stacks[selection]?.transitionCoordinator == nil }
        XCTAssertTrue(host.navigation.snapshot.presentations.isEmpty)
        XCTAssertEqual(host.navigation.snapshot.stacks[selection], ["page-orbit", "page-echo"])
        XCTAssertTrue(host.tabController.view.isUserInteractionEnabled)
    }

    func testConfiguredFittingUsesCanonicalScrollerAndCloseAtEveryDepth() throws {
        for follows in ["root", "top-page"] {
            var json = try ServerUIRendererFixture.json()
            json = try ServerUIRendererFixture.changing(json, path: "/document/modals/0/presentation/height", to: .object([
                "type": .string("fitted"), "follows": .string(follows), "firstOpen": .string("canonical@1"),
            ]))
            json = try ServerUIRendererFixture.changing(json, path: "/document/modals/0/presentation/close/visibility", to: .string("all-depths"))
            let capabilities = ServerUICompositionPublication.firstSliceCapabilities + ["sh.sheet-fit@1"]
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
            let (host, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(json))
            let root = try ServerUIRendererFixture.root(host)
            guard case .button(let button) = host.publication.document.navigation.chrome.groups[1].items[0] else {
                return XCTFail("Fixture modal button")
            }
            try host.perform(button.action, from: root)
            HostedPage.until { host.modal?.presentingViewController != nil && host.modal?.transitionCoordinator == nil }
            let modal = try XCTUnwrap(host.modal)
            let page = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
            XCTAssertEqual(modal.options.height, follows == "root" ? .fitted : .fittedToTopPage)
            XCTAssertTrue(page.sheetFitScrollView === page.body)
            XCTAssertNil(modal.options.predictedContentHeight)
            guard case .navigationTile(let local) = page.definition.components[1] else { return XCTFail("Fixture sheet tile") }
            try host.perform(local.action, from: page)
            HostedPage.until { modal.transitionCoordinator == nil }
            let pushed = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
            XCTAssertNotNil(ServerUIRendererFixture.barItems(pushed).first { $0.accessibilityIdentifier == "server-ui.sheet.close" })
            try host.perform(.dismiss(scope: .currentModal), from: pushed)
            HostedPage.until { host.modal == nil }
            XCTAssertTrue(host.tabController.view.isUserInteractionEnabled)
            window.isHidden = true
        }
    }

    func testConfiguredGridMatchesCanonicalDynamicTypeScaling() throws {
        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components/0/props/minimum", to: .string("tile-dynamic-type@1"))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities + ["sh.grid-dynamic-type@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        let (host, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(json))
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let grid = try XCTUnwrap(root.nodes["node-orbit-grid"]?.view as? UKDynamicGridView)
        let identity = grid
        for category in [UIContentSizeCategory.extraSmall, .accessibilityExtraExtraExtraLarge] {
            root.traitOverrides.preferredContentSizeCategory = category
            root.view.layoutIfNeeded()
            HostedPage.wait(0.05)
            XCTAssertTrue(root.nodes["node-orbit-grid"]?.view === identity)
            XCTAssertEqual(grid.configuration.minCellWidth, UKFont.scaled(150, relativeTo: .subheadline, traits: root.traitCollection), accuracy: 0.01)
        }
    }

    func testPendingNodeTargetReplacementRejectsWithoutBlockingUnrelatedCopy() async throws {
        var fixture = try ServerUIRendererFixture.json()
        guard case .array(let sources) = fixture["document"]?["dataSources"] else { return XCTFail("Fixture sources") }
        let other: JSONValue = .object([
            "id": .string("source-other"), "kind": .string("model"), "model": .string("power-toggle@1"),
            "inputs": .object(["entityId": .object(["type": .string("literal"), "value": .string("switch.demo_other")])]),
        ])
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/dataSources", to: .array(sources + [other]))
        let (host, window, caller) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(fixture))
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        guard case .grid(let grid) = root.definition.components[0], case .actionTile(let tile) = grid.children[0] else {
            return XCTFail("Fixture power tile")
        }
        XCTAssertNoThrow(try host.perform(.domain(tile.action), from: root, symbol: tile.icon.name))
        XCTAssertTrue(host.bindings.powers["source-power"]?.hasPendingIntent == true)
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/revision", to: .number(2))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/pages/0/title", to: .string("Revised Canvas"))
        XCTAssertNoThrow(try host.validateUpdate(ServerUIRendererFixture.publication(fixture)))
        fixture = try ServerUIRendererFixture.changing(fixture,
            path: "/document/pages/0/components/0/children/0/binding/sourceId", to: .string("source-other"))
        fixture = try ServerUIRendererFixture.changing(fixture,
            path: "/document/pages/0/components/0/children/0/action/sourceId", to: .string("source-other"))
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(fixture))) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .interactionBlocked)
        }
        XCTAssertEqual(host.bindings.entityID(for: "source-power").value, "switch.demo_lamp")
        XCTAssertEqual(host.publication.revision, 1)
        let power = try XCTUnwrap(host.bindings.powers["source-power"])
        await power.actions["switch.demo_lamp"]?.waitForCalls()
        XCTAssertEqual(caller.calls, ["switch.turn_on"])
        host.pageContext.store.apply([EntityState(entityId: "switch.demo_lamp", state: "on")])
        let completed = await FeatureHost.settleAsync(until: { !power.hasPendingIntent })
        XCTAssertTrue(completed)
        XCTAssertNoThrow(try host.validateUpdate(ServerUIRendererFixture.publication(fixture)))
    }

    func testMovingAKeyedNodeBetweenColumnAndGridKeepsItAttachedAndRetainsIdentity() throws {
        let fixture = try ServerUIRendererFixture.json()
        guard case .array(let pages) = fixture["document"]?["pages"],
              case .array(let components) = pages[0]["components"],
              case .object(var grid) = components[0],
              case .array(let children) = grid["children"] else { return XCTFail("Fixture grid") }
        let (host, window, _) = try ServerUIRendererFixture.host()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let nativeGrid = try XCTUnwrap(root.nodes["node-orbit-grid"]?.view as? UKDynamicGridView)
        let nativeTile = try XCTUnwrap(root.nodes["node-open-echo"]?.view)
        grid["children"] = .array([children[0]])
        var next = try ServerUIRendererFixture.changing(fixture, path: "/revision", to: .number(2))
        next = try ServerUIRendererFixture.changing(next, path: "/document/pages/0/components",
                                                   to: .array([.object(grid), children[1]]))
        let backdrop = try XCTUnwrap(root.context.backdrop)
        try host.apply(publication: ServerUIRendererFixture.publication(next), backdrop: backdrop)
        XCTAssertFalse(nativeTile.superview === nativeGrid)
        next = try ServerUIRendererFixture.changing(fixture, path: "/revision", to: .number(3))
        try host.apply(publication: ServerUIRendererFixture.publication(next), backdrop: backdrop)
        XCTAssertTrue(nativeTile.superview === nativeGrid)
        XCTAssertTrue(root.nodes["node-open-echo"]?.view === nativeTile)
        XCTAssertTrue(nativeGrid.items.last?.view === nativeTile)
    }

    func testGenericFlyoutUsesConfiguredOrderAndKeepsRowsWhenValuesChange() throws {
        let flyout = UKNavigationFlyoutView(shell: nil, onDismiss: {}, onSelect: { _ in })
        var rows = [
            UKFlyoutDestination(id: "zeta", title: "First", symbol: "square", identifier: "zeta"),
            UKFlyoutDestination(id: "alpha", title: "Second", symbol: "circle", identifier: "alpha"),
        ]
        flyout.update(destinations: rows, selection: "zeta", isOpen: false)
        let before = HostedPage.descendants(of: flyout).compactMap { $0 as? UKFlyoutRow }
        rows[0] = UKFlyoutDestination(id: "zeta", title: "Renamed", symbol: "square", identifier: "zeta")
        flyout.update(destinations: rows, selection: "alpha", isOpen: false)
        let after = HostedPage.descendants(of: flyout).compactMap { $0 as? UKFlyoutRow }
        XCTAssertEqual(after.map(\.destination.id), ["zeta", "alpha"])
        XCTAssertTrue(before[0] === after[0])
        XCTAssertEqual(after[0].accessibilityLabel, "Renamed")
        XCTAssertTrue(after[1].accessibilityTraits.contains(.selected))

        rows.reverse()
        flyout.update(destinations: rows, selection: "alpha", isOpen: false)
        let reordered = HostedPage.descendants(of: flyout).compactMap { $0 as? UKFlyoutRow }
        XCTAssertTrue(reordered[0] === after[1])
        let stack = try XCTUnwrap(reordered[0].superview as? UIStackView)
        XCTAssertEqual(stack.customSpacing(after: stack.arrangedSubviews[0]), UIStackView.spacingUseDefault)
        XCTAssertEqual(stack.customSpacing(after: reordered[0]), stack.spacing)
        XCTAssertEqual(stack.customSpacing(after: reordered[1]), 0)
    }
}
