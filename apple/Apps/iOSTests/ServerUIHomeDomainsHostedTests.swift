import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Parent-run complete recipe evidence

/// Network-isolated definitions; the parent runs these journeys on the three device families.
@MainActor
final class ServerUIHomeDomainsHostedTests: XCTestCase {
    private func publication() throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try ServerUICompositionPublication.decode(Data(contentsOf:
            apple.appendingPathComponent("Tests/HassCoreTests/ServerUIHomeDomainsFixture.json")))
    }

    private func host(caller: any HassServiceCalling = HostedCaller()) throws -> UKServerUIRenderer {
        let publication = try publication()
        try UKServerUIRenderer.preflight(publication)
        let weather = publication.document.dataSources.compactMap { source -> String? in
            if case .homeWeather(_, let config) = source { return config.weatherEntityId }
            return nil
        }
        let cameras = publication.document.dataSources.compactMap { source -> ServerUICameraDescriptor? in
            if case .camera(_, let config) = source { return config }
            return nil
        }
        let ids = publication.document.dataSources.flatMap { source -> [String] in
            if case .homeStatus(_, let config) = source { return config.entityIds }
            if case .homeLight(_, let entity, let members) = source { return [entity] + members }
            if case .climate(_, let config) = source {
                return config.commandEntityIds + [config.sensorEntityId, config.occupancyEntityId].compactMap { $0 }
                    + (config.tracking.map { [$0.policyEntityId] + $0.rooms.flatMap { [$0.selectedEntityId, $0.criticalEntityId, $0.occupiedOnlyEntityId] } } ?? [])
            }
            return []
        }
        let store = EntityStore()
        store.replaceAll(Set(ids).map { EntityState(entityId: $0, state: $0.hasPrefix("sensor.") ? "72" : "on") })
        let reader = ServerUIWeatherReader(entityIds: Set(weather)) { entity, _ in
            .object([entity: .object(["forecast": .array([])])])
        }
        let cameraReader = UKCameraReadProvider(descriptors: cameras, appear: { _ in }, disappear: { _ in },
            retry: { _ in }, snapshotURL: { _ in nil }, offline: { false })
        return try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: caller),
            backdrop: ServerUIRendererFixture.backdrop(), cameraPool: CameraStreamPool(modes: [], observesApp: false),
            weatherReader: reader, cameraReader: cameraReader)
    }

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testHomeCompositionKeepsMeasuredStatusAndWeatherAtAllFamilyWidthsAndAX5() throws {
        for width: CGFloat in [390, 744, 1024] {
            let host = try host()
            let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 900)))
            defer { window.isHidden = true }
            window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            HostedPage.layoutTracked()
            let root = try XCTUnwrap(host.stacks[host.navigation.snapshot.selection]?.viewControllers.first as? UKServerUIPage)
            let rail = try XCTUnwrap(root.nodes["hc-status-rail"]?.view as? UKChipRailView)
            let weather = try XCTUnwrap(root.nodes["hc-weather-summary"]?.view)
            XCTAssertEqual(rail.mode, .wrap)
            XCTAssertGreaterThan(rail.bounds.height, 0)
            XCTAssertGreaterThan(weather.bounds.height, 0)
            XCTAssertNotNil(root.nodes["hc-home-guests-visible"]?.view)
            XCTAssertNil(host.pageContext.connection)
            host.bindings.apply(host.publication.document.dataSources)
            XCTAssertTrue(root.nodes["hc-status-rail"]?.view === rail)
            XCTAssertTrue(root.nodes["hc-weather-summary"]?.view === weather)
        }
    }

    func testConditionalGuestsRemainAttachedUntilTheirActualCommandCompletes() async throws {
        let caller = GuestHeldCaller()
        defer { caller.finish() }
        let host = try host(caller: caller)
        let home = try XCTUnwrap(host.publication.document.pages.first { $0.id == "page-home" })
        let section = home.surface.components[2]
        XCTAssertTrue(host.bindings.roomVisible(section))
        let power = try XCTUnwrap(host.bindings.powers["hc-guest-0"])
        let id = try XCTUnwrap(host.bindings.entityID(for: "hc-guest-0").value)
        try power.perform(entityID: id, spec: power.projection(entityID: id, symbol: "person").spec)
        for _ in 0..<30 where caller.continuation == nil { await Task.yield() }
        XCTAssertNotNil(caller.continuation)
        guard case .homeStatus(_, let guests) = host.bindings.definitions["hc-guests-status"] else { return XCTFail("Guest aggregate") }
        host.pageContext.store.apply(guests.entityIds.map { EntityState(entityId: $0, state: "off") })
        power.actions[id]?.overlay.reset(id)
        XCTAssertTrue(host.bindings.roomVisible(section), "A hidden aggregate must not remove an in-flight child.")
        caller.finish()
        await power.actions[id]?.waitForCalls()
        for _ in 0..<30 where power.hasPendingIntent { await Task.yield() }
        XCTAssertFalse(host.bindings.roomVisible(section))
    }

    func testRoomPowerUpdatesDetailAndPinsSourceUntilTheHeldCallCompletes() async throws {
        let caller = GuestHeldCaller()
        defer { caller.finish() }
        let host = try host(caller: caller)
        let source = try XCTUnwrap(host.bindings.lights.values.first { !$0.memberEntityIds.isEmpty })
        let memberID = try XCTUnwrap(source.memberEntityIds.first)
        let member = try XCTUnwrap(host.bindings.lights.values.first { $0.entityId == memberID })
        let task = try source.performRoomPower(title: "Demo Room", expected: source.roomPower(title: "Demo Room"))
        XCTAssertEqual(member.shown?.state, "off")
        for _ in 0..<30 where caller.continuation == nil { await Task.yield() }
        source.actions.overlay.reset(source.entityId)
        source.memberEntityIds.forEach { source.actions.overlay.reset($0) }
        XCTAssertTrue(source.hasPendingIntent)
        let old = try XCTUnwrap(host.publication.document.dataSources.first { host.bindings.lights[$0.id] === source })
        let changed = host.publication.document.dataSources.map {
            $0.id == old.id ? ServerUICompositionDocument.Source.homeLight(id: old.id, entityId: "light.demo_other") : $0
        }
        XCTAssertThrowsError(try host.bindings.validateReplacement(changed))
        caller.finish()
        await task.value
        XCTAssertFalse(source.hasPendingIntent)
    }

    func testOverviewSubtitleSeamUsesOnlyCompatibleScopedSources() throws {
        let host = try host()
        let ids = host.publication.document.dataSources.compactMap { source -> String? in
            if case .homeStatus(let id, let config) = source, config.projection == .lights, config.format == .room { return id }
            return nil
        }
        XCTAssertNotNil(try host.bindings.homeOverviewSubtitle(.lights, sourceIds: ids))
        XCTAssertThrowsError(try host.bindings.homeOverviewSubtitle(.lights, sourceIds: ["hc-guests-status"]))
        XCTAssertThrowsError(try host.bindings.homeOverviewSubtitle(.lights, sourceIds: ids + ids))
    }

    func testClimateRoomLinksAndPredictionPresentationsMeasureAndKeepIdentityAtAllWidths() throws {
        let host = try host()
        func controls(_ values: [ServerUICompositionDocument.Component]) -> [ServerUIClimateControl] {
            values.flatMap { component in
                let own: [ServerUIClimateControl]
                if case .climate(let value) = component { own = [value] } else { own = [] }
                return own + controls(component.childComponents)
            }
        }
        let all = controls(host.publication.document.pages.flatMap(\.surface.components)
                           + host.publication.document.modals.flatMap(\.surface.components))
        for width: CGFloat in [390, 744, 1024] {
            for definition in all.filter({ [.roomTile, .link].contains($0.props.kind) || $0.props.presentation != nil }) {
                let adapter = try XCTUnwrap(host.bindings.climates[definition.props.sourceId])
                let view = UKServerUIClimateControl()
                let page = UIViewController()
                page.view.addSubview(view)
                let window = HostedPage.show(page, size: HostedPage.inScene(CGSize(width: width, height: 900)))
                defer { window.isHidden = true }
                window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                view.configure(definition, adapter: adapter, context: host.pageContext)
                let height = view.gridHeight(forWidth: width - 48)
                XCTAssertGreaterThan(height, 0)
                XCTAssertTrue(height.isFinite)
                view.frame = CGRect(x: 24, y: 24, width: width - 48, height: height)
                HostedPage.layoutTracked()
                let children = view.subviews
                view.configure(definition, adapter: adapter, context: host.pageContext)
                XCTAssertEqual(view.subviews, children)
                let accessible = try XCTUnwrap(FeatureHost.view(definition.node.id, in: view))
                if definition.props.presentation == .metric {
                    XCTAssertTrue(accessible.isAccessibilityElement)
                    XCTAssertEqual(accessible.accessibilityLabel, definition.node.title)
                    XCTAssertNotNil(accessible.accessibilityValue)
                }
            }
        }
    }
}

@MainActor
private final class GuestHeldCaller: HassServiceCalling {
    var continuation: CheckedContinuation<Void, Never>?
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}
