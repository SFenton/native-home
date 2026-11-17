import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Synthetic configured source

@MainActor
final class ConfiguredVacuumCaller: HassServiceCalling {
    var calls: [String] = []
    var targets: [String?] = []
    var hold = false
    private var continuation: CheckedContinuation<Void, Error>?
    private var started: CheckedContinuation<Void, Never>?
    struct Failure: Error {}

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append("\(domain).\(service)")
        targets.append(data["entity_id"] as? String)
        if hold {
            try await withCheckedThrowingContinuation {
                continuation = $0
                started?.resume()
                started = nil
            }
        }
    }

    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func complete(failing: Bool = false) {
        let current = continuation
        continuation = nil
        if failing { current?.resume(throwing: Failure()) } else { current?.resume() }
    }
}

@MainActor
enum ConfiguredVacuumFixture {
    static func descriptor() throws -> ServerUIVacuumDescriptor {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(ServerUIVacuumDescriptor.self,
            from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIVacuumDescriptorFixture.json")))
    }

    static func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// - Parameters:
    ///   - orientation: The source's `orientation` (`sh.surface-orientation@1`), when authored.
    ///   - extra: Capability ids the content needs beyond the kind's own (the map's `controls` adds its own).
    static func publication(_ primitive: String, autoClean: Bool = false, revision: Double = 1, orientation: String? = nil, rotation: Double? = nil,
                            extra needs: [String] = [], overlayPill: Bool = false) throws -> ServerUICompositionPublication {
        var root = try ServerUIRendererFixture.json()
        var descriptor = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(descriptor()))
        if let rotation { descriptor = try ServerUIRendererFixture.changing(descriptor, path: "/mapRotationDegrees", to: .number(rotation)) }
        if let orientation { descriptor = try ServerUIRendererFixture.changing(descriptor, path: "/orientation", to: json(orientation)) }
        if autoClean {
            descriptor = try ServerUIRendererFixture.changing(descriptor, path: "/autoCleanControl",
                to: .object(["title": "Demo Auto-Clean", "entityId": "switch.demo_pause", "kind": "pause"]))
        }
        var sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        sources.append(.object(["id": .string("source-robot"), "kind": .string("model"),
            "model": .string("vacuum@1"), "inputs": descriptor]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(sources))
        var nodes = try XCTUnwrap(root["document"]?["pages"]?.array?[0]["components"]?.array)
        nodes.append(.object(["id": .string("robot-control"), "title": .string("Demo Control"),
            "type": .string("vacuum-control"), "layout": .object(["span": .number(1)]),
            "props": .object(["sourceId": .string("source-robot"), "primitive": try json(primitive)])]))
        if overlayPill {
            // The control becomes the base of an overlay with a status pill at the centre (`sh.overlay@1`).
            let base = try XCTUnwrap(nodes.popLast())
            let pill = try json(#"{"id":"centre-pill","title":"Pill","type":"status-pill","layout":{"span":1},"icon":{"type":"sf-symbol","name":"bolt.fill","rendering":"canonical","unavailable":"fallback"},"props":{"value":{"type":"literal","value":"87%"},"detail":{"type":"literal","value":""},"tone":"ok","unavailableText":"Unavailable"}}"#)
            nodes.append(.object(["id": .string("over-map"), "title": .string("Over Map"), "type": .string("overlay"),
                "layout": .object(["span": .number(1)]),
                "props": try json(#"{"anchors":[{"childId":"centre-pill","anchor":"center","inset":{"type":"token","name":"zero"}}]}"#),
                "children": .array([base, pill])]))
        }
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(nodes))
        let kind = try json(primitive)["kind"]?.string
        let extra = kind == "auto-clean" ? ["sh.vacuum-auto-clean@1"] : kind == "map" ? ["sh.vacuum-map@1"]
            : kind == "area-editor" ? ["sh.vacuum-map@1", "sh.vacuum-area@1"]
            : kind == "outcomes" || kind == "report" ? ["sh.vacuum-outcomes@1"] : ["sh.vacuum-controls@1"]
        var capabilities = ServerUICompositionPublication.firstSliceCapabilities + ["sh.vacuum@1"] + extra + needs
        if primitive.contains("\"controls\"") { capabilities.append("sh.surface-controls@1") }
        if primitive.contains("source-command") { capabilities.append("sh.vacuum-controls@1") }
        if orientation != nil { capabilities.append("sh.surface-orientation@1") }
        if overlayPill { capabilities += ["sh.overlay@1", "sh.status-pill@1"] }
        capabilities = Array(Set(capabilities))
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        root = try ServerUIRendererFixture.changing(root, path: "/revision", to: .number(revision))
        return try ServerUIRendererFixture.publication(root)
    }

    static func store(_ d: ServerUIVacuumDescriptor) -> EntityStore {
        let store = EntityStore()
        store.replaceAll([
            EntityState(entityId: d.entityId, state: "docked"),
            EntityState(entityId: d.batteryEntityId, state: "90"),
            EntityState(entityId: d.errorEntityId, state: "None"),
            EntityState(entityId: d.statusFlagEntityId, state: "ready"),
            EntityState(entityId: d.statusEntityId, state: "docked"),
            EntityState(entityId: d.passesEntityId, state: "1", attributes: ["options": .array([.string("1"), .string("2")])]),
            EntityState(entityId: d.zones[0].entityId, state: "off"),
            EntityState(entityId: "switch.demo_pause", state: "on"),
        ])
        return store
    }

    /// - Parameter leftOnly: The segment covers only the left 20 of the map's 50 columns, so a flip is visible in where a tap lands.
    static func loader(leftOnly: Bool = false) -> ValetudoMapLoader {
        let loader = ValetudoMapLoader { _ in throw URLError(.notConnectedToInternet) }
        let pixels = (0...50).flatMap { y in (0...(leftOnly ? 20 : 50)).flatMap { x in [Int32(x), Int32(y)] } }
        // A second, unconfigured segment on the right keeps the map's bounds the full width when the room covers only the left part.
        let right = (0...50).flatMap { y in (40...50).flatMap { x in [Int32(x), Int32(y)] } }
        let edge: [ValetudoMap.Layer] = leftOnly ? [.init(type: "segment", pixels: right, name: "Demo Extra", segmentId: "2")] : []
        loader.show(ValetudoMap(layers: [.init(type: "segment", pixels: pixels, name: "Demo Segment", segmentId: "1")] + edge,
            entities: [.init(type: "robot_position", points: [100, 100])], pixelSize: 5, size: (500, 500)), provenance: .live)
        return loader
    }

    static let services: Set<String> = ["vacuum.start", "vacuum.pause", "vacuum.return_to_base",
        "input_boolean.turn_on", "input_boolean.turn_off", "input_select.select_option", "script.demo_clean", "script.demo_area"]

    static func source(caller: ConfiguredVacuumCaller) throws -> UKServerUIVacuumSource {
        let d = try descriptor(), loader = loader()
        return UKServerUIVacuumSource(descriptor: d, context: UKContext(store: store(d), caller: caller),
            environment: .init(loader: { _ in loader }, services: services))
    }
}

// MARK: - Command, confirmation and draft regressions

/// Fixture-only hosted cases are compatible with the parent's iPhone, Duo and iPad test runs.
@MainActor
final class ServerUIConfiguredVacuumTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    /// The Auto-Clean switch is lowered at compile time to a bound toggle: the page draws a generic row with a switch, not the vacuum view.
    func testLoweredAutoCleanToggleMeasuresAndRetainsLiveBindingAcrossFamilyWidths() throws {
        for width: CGFloat in [355, 390, 768, 1024] {
            let store = ConfiguredVacuumFixture.store(try ConfiguredVacuumFixture.descriptor())
            let publication = try ConfiguredVacuumFixture.publication(#"{"kind":"auto-clean"}"#, autoClean: true)
            let host = try UKServerUIRenderer(publication: publication,
                context: UKContext(store: store, caller: ConfiguredVacuumCaller()), backdrop: ServerUIRendererFixture.backdrop(),
                vacuums: .init(loader: { _ in ConfiguredVacuumFixture.loader() }, services: ConfiguredVacuumFixture.services))
            let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 900)))
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            HostedPage.layoutTracked()
            let view = try XCTUnwrap(page.nodes["robot-control"]?.view)
            XCTAssertFalse(view is UKServerUIVacuumView, "a lowered kind carries no vacuum view (width \(width))")
            let control = try XCTUnwrap(view as? UKServerUILocalControl, "width \(width)")
            let toggle = try XCTUnwrap(control.drawnControl as? UKModuleToggleRow, "the row with its glyph and subtitle is the module toggle row (width \(width))")
            XCTAssertEqual(toggle.row.rowContent.symbol, "clock.arrow.circlepath")
            XCTAssertEqual(toggle.row.rowContent.subtitle, "Paused", "the pause switch is on: width \(width)")
            XCTAssertGreaterThanOrEqual(view.systemLayoutSizeFitting(CGSize(width: width - 32, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height, 44)
            XCTAssertFalse(toggle.isOn)
            store.apply([.init(entityId: "switch.demo_pause", state: "off")])
            XCTAssertTrue(HostedPage.until { toggle.isOn })
            XCTAssertEqual(toggle.row.rowContent.subtitle, "Enabled")
            try host.apply(publication: ConfiguredVacuumFixture.publication(#"{"kind":"auto-clean"}"#, autoClean: true, revision: 2),
                           backdrop: ServerUIRendererFixture.backdrop())
            XCTAssertTrue(page.nodes["robot-control"]?.view === view)
        }
    }

    /// The card is lowered to a state tile: it draws the robot's state and battery and carries the Start or pause disc.
    func testLoweredCardDrawsTheRobotTileAtEveryFamilyWidth() async throws {
        let primitive = #"{"kind":"card","icon":{"type":"sf-symbol","name":"fan","rendering":"canonical","unavailable":"reject"},"commands":["start_pause","dock"],"destination":{"type":"push","pageId":"page-echo","arguments":{},"origin":"sender","duplicate":"reuse-nearest"}}"#
        for width: CGFloat in [393, 466, 834] {
            let store = ConfiguredVacuumFixture.store(try ConfiguredVacuumFixture.descriptor())
            let host = try UKServerUIRenderer(publication: ConfiguredVacuumFixture.publication(primitive),
                context: UKContext(store: store, caller: ConfiguredVacuumCaller()), backdrop: ServerUIRendererFixture.backdrop(),
                vacuums: .init(loader: { _ in ConfiguredVacuumFixture.loader() }, services: ConfiguredVacuumFixture.services))
            let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 852)))
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            await HostedPage.settle { page.nodes["robot-control"]?.view is UKGlassTileView }
            let tile = try XCTUnwrap(page.nodes["robot-control"]?.view as? UKGlassTileView, "width \(width)")
            XCTAssertEqual(tile.model.title, "Demo Control")
            XCTAssertEqual(tile.model.look?.text, "Docked", "width \(width)")
            XCTAssertEqual(tile.model.subtitle, "Docked \u{2022} 90%", "width \(width)")
            XCTAssertFalse(tile.model.actions.isEmpty, "the Start or pause and Dock discs are on the tile")
            XCTAssertNil(tile.model.fillRGB, "a docked robot keeps the neutral face (width \(width))")
            let start = try XCTUnwrap(tile.model.actions.first { $0.id == "disc:start_pause" }, "width \(width)")
            XCTAssertEqual(start.verb, "Start")
            XCTAssertEqual(start.symbol, "play.fill")
            store.apply([EntityState(entityId: "vacuum.demo_robot", state: "cleaning")])
            let purple = await HostedPage.settle { tile.model.fillRGB == 0x7A3FB0 }
            XCTAssertTrue(purple, "a working robot draws the cleaning purple (width \(width))")
            let pause = try XCTUnwrap(tile.model.actions.first { $0.id == "disc:start_pause" })
            XCTAssertEqual(pause.verb, "Pause")
            XCTAssertEqual(pause.symbol, "pause.fill")
            store.apply([EntityState(entityId: "vacuum.demo_robot", state: "docked")])
            store.apply([EntityState(entityId: "vacuum.demo_robot", state: "unavailable")])
            let landed = await HostedPage.settle { tile.model.look?.stateClass == .unknown }
            XCTAssertTrue(landed, "an unreachable robot draws the unknown face (width \(width))")
            HostedPage.hideTracked()
        }
    }

    func testDraftIsLocalDiscardRestoresAndUseRevalidatesLiveReadiness() throws {
        let source = try ConfiguredVacuumFixture.source(caller: ConfiguredVacuumCaller())
        let first = MapGridRect(x0: 5, x1: 20, y0: 5, y1: 20)
        let second = MapGridRect(x0: 10, x1: 30, y0: 10, y1: 30)
        source.controller?.areaSelection = first
        source.beginDraft()
        source.draft = second
        XCTAssertEqual(source.controller?.areaSelection, first)
        XCTAssertTrue(source.isPinned)
        source.discardDraft()
        XCTAssertEqual(source.draft, first)
        XCTAssertFalse(source.isPinned)
        source.beginDraft()
        source.draft = second
        source.controller?.store.apply([EntityState(entityId: source.descriptor.entityId, state: "cleaning")])
        XCTAssertFalse(source.useDraft())
        XCTAssertEqual(source.controller?.areaSelection, first)
        source.controller?.store.apply([EntityState(entityId: source.descriptor.entityId, state: "docked")])
        XCTAssertTrue(source.useDraft())
        XCTAssertEqual(source.controller?.areaSelection, second)
        XCTAssertEqual(source.command(.clean)?.kind, .cleanArea, "Clean follows the committed target.")
        XCTAssertFalse(source.isPinned)
    }

    func testSwitchConfirmationCannotApplyAfterItsCapturedAreaChanges() throws {
        let source = try ConfiguredVacuumFixture.source(caller: ConfiguredVacuumCaller())
        let first = MapGridRect(x0: 5, x1: 20, y0: 5, y1: 20)
        let second = MapGridRect(x0: 10, x1: 30, y0: 10, y1: 30)
        source.controller?.areaSelection = first
        let presenter = UIViewController(), window = HostedPage.show(presenter)
        defer { window.isHidden = true }
        var proceeded = false
        source.switchTarget(.rooms, from: presenter) { proceeded = true }
        let alert = try XCTUnwrap(FeatureHost.alert(on: presenter))
        XCTAssertEqual(alert.preferredStyle, .alert)
        XCTAssertEqual(alert.title, AlertCopy.switchToRooms.title)
        source.controller?.areaSelection = second
        XCTAssertTrue(FeatureHost.answer(alert, AlertCopy.switchToRooms.confirm.title))
        XCTAssertFalse(proceeded)
        XCTAssertEqual(source.controller?.areaSelection, second)
        XCTAssertNotNil(source.failure)
    }

    func testPendingSourceAndControlCannotBeRemovedByPublication() throws {
        let publication = try ConfiguredVacuumFixture.publication(#"{"kind":"status","metric":"battery"}"#)
        let d = try ConfiguredVacuumFixture.descriptor(), store = ConfiguredVacuumFixture.store(d)
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: ConfiguredVacuumCaller()),
            backdrop: ServerUIRendererFixture.backdrop(), vacuums: .init(services: ConfiguredVacuumFixture.services))
        let source = try XCTUnwrap(host.bindings.vacuums["source-robot"])
        source.beginDraft()
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication()))
        source.discardDraft()
        XCTAssertNoThrow(try host.validateUpdate(ServerUIRendererFixture.publication()))
    }

    func testReopeningMountedEditorStartsANewPinnedDraftWithoutChangingCommittedArea() throws {
        let d = try ConfiguredVacuumFixture.descriptor(), loader = ConfiguredVacuumFixture.loader()
        let host = try UKServerUIRenderer(
            publication: ConfiguredVacuumFixture.publication(#"{"kind":"area-editor","height":650,"onUse":{"type":"back"},"discardLabel":"Discard","onDiscard":{"type":"back"}}"#),
            context: UKContext(store: ConfiguredVacuumFixture.store(d), caller: ConfiguredVacuumCaller()),
            backdrop: ServerUIRendererFixture.backdrop(),
            vacuums: .init(loader: { _ in loader }, services: ConfiguredVacuumFixture.services))
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        let view = try XCTUnwrap(page.nodes["robot-control"]?.view)
        let parent = try XCTUnwrap(view.superview), source = try XCTUnwrap(host.bindings.vacuums["source-robot"])
        XCTAssertTrue(source.draftActive)
        source.draft = MapGridRect(x0: 5, x1: 20, y0: 5, y1: 20)
        view.removeFromSuperview()
        XCTAssertFalse(source.draftActive)
        XCTAssertNil(source.controller?.areaSelection)
        parent.addSubview(view)
        XCTAssertTrue(source.draftActive)
        XCTAssertNil(source.draft, "Reopening starts from the committed target, not the discarded draft.")
    }

    func testRetainedOutcomeViewRefreshesForANewCapturedReport() throws {
        let d = try ConfiguredVacuumFixture.descriptor()
        let host = try UKServerUIRenderer(publication: ConfiguredVacuumFixture.publication(#"{"kind":"outcomes"}"#),
            context: UKContext(store: ConfiguredVacuumFixture.store(d), caller: ConfiguredVacuumCaller()),
            backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host), source = try XCTUnwrap(host.bindings.vacuums["source-robot"])
        let view = try XCTUnwrap(page.nodes["robot-control"]?.view)
        guard case .typed(var report) = VacuumWhileAway.read(["while_away_outcomes": VacuumOutcomeFixtures.sample]) else {
            return XCTFail("Expected a typed synthetic report.")
        }
        let originalName = try XCTUnwrap(report.rooms.first?.roomName)
        source.openReport(report)
        XCTAssertTrue(HostedPage.until { HostedPage.labels(in: view).contains(originalName) })
        XCTAssertTrue(source.isPinned)
        source.closeReport()
        XCTAssertFalse(source.isPinned)
        report.rooms[0].roomName = "Updated Synthetic Room"
        source.openReport(report)
        XCTAssertTrue(HostedPage.until { HostedPage.labels(in: view).contains("Updated Synthetic Room") })
        XCTAssertFalse(HostedPage.labels(in: view).contains(originalName))
    }

    func testMapRemainsNoZoomAndStatusKeepsAuthoredAccessibleTitleAtAX5() throws {
        let map = #"{"kind":"map","overlay":"rooms","height":300,"runtimeHeight":460,"label":"Demo Map","loadingText":"Reading Map","unavailableText":"No Map","locate":false}"#
        let d = try ConfiguredVacuumFixture.descriptor(), store = ConfiguredVacuumFixture.store(d), loader = ConfiguredVacuumFixture.loader()
        let host = try UKServerUIRenderer(publication: ConfiguredVacuumFixture.publication(map),
            context: UKContext(store: store, caller: ConfiguredVacuumCaller()), backdrop: ServerUIRendererFixture.backdrop(),
            vacuums: .init(loader: { _ in loader }, services: ConfiguredVacuumFixture.services))
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        let view = try XCTUnwrap(page.nodes["robot-control"]?.view as? UKServerUIVacuumView)
        let canvas = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UKValetudoMapView }.first)
        XCTAssertFalse(canvas.gestureRecognizers?.contains { $0 is UIPinchGestureRecognizer } ?? false)
        XCTAssertEqual(canvas.accessibilityLabel, "Demo Map")
        XCTAssertLessThanOrEqual(view.gridHeight(forWidth: 600), 332, "The authored 300 pt map cap excludes its 16 pt insets.")
        let status = try ConfiguredVacuumFixture.publication(#"{"kind":"status","metric":"battery"}"#)
        try host.apply(publication: status, backdrop: XCTUnwrap(host.pageContext.backdrop))
        page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        page.view.layoutIfNeeded()
        HostedPage.wait(0.1)
        XCTAssertTrue(page.nodes["robot-control"]?.view === view)
        let tile = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UKGlassTileView }.first)
        XCTAssertEqual(tile.model.title, "Demo Control")
        XCTAssertEqual(tile.model.spokenValue, "90%")
        XCTAssertEqual(tile.model.behavior, .inert)
        XCTAssertGreaterThan(view.gridHeight(forWidth: 300), 44)
    }
}
