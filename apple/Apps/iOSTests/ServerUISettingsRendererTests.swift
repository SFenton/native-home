@testable import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Injected settings controls

@MainActor
final class ServerUISettingsRendererTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func publication(kind: String = "household-toggle", item: String = "lamp", title: String = "Alpha",
                             domain: String = "household", controlTitle: String = "Demo Lamp",
                             pageIndex: Int = 0, columns: Bool = false, systemRoute: Bool = false) throws -> ServerUICompositionPublication {
        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "capabilities",
            to: .array((ServerUICompositionPublication.firstSliceCapabilities + ["sh.settings-controls@1"]
                + (columns ? ["sh.navigation-columns@1"] : [])
                + (systemRoute ? ["sh.native-extensions@1"] : [])).sorted().map(JSONValue.string)))
        let sources = try XCTUnwrap(json["document"]?["dataSources"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "document/dataSources", to: .array(sources + [
            .object(["id": .string("settings"), "kind": .string("model"), "model": .string("settings-provider@1"),
                     "inputs": .object(["providerId": .string("private-settings"), "domain": .string(domain)])]),
        ]))
        let control: JSONValue = .object([
            "id": .string("test-control"), "title": .string(controlTitle), "type": .string("settings-control"),
            "layout": .object(["span": .number(1)]),
            "icon": .object(["type": .string("sf-symbol"), "name": .string("lightbulb"),
                             "rendering": .string("canonical"), "unavailable": .string("reject")]),
            "props": .object(["sourceId": .string("settings"), "kind": .string(kind), "item": .string(item), "subtitle": .string("")]),
        ])
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        if systemRoute {
            let pageID = try XCTUnwrap(pages.first?["id"]?.string)
            let tabID = try XCTUnwrap(json["document"]?["navigation"]?["tabs"]?.array?.first?["id"]?.string)
            json = try ServerUIRendererFixture.changing(json, path: "document/extensions", to: .object([
                "type": "native-extensions@1", "watch": "stub@1", "cameras": .array([]),
                "routes": .array([.object(["id": "home-link", "path": "home", "pageId": .string(pageID),
                    "tabId": .string(tabID), "title": "Home", "summary": "Your house", "icon": "house.fill"])]),
            ]))
        }
        let components = try XCTUnwrap(pages[pageIndex]["components"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "document/pages/\(pageIndex)/components",
                                                   to: .array(components + [control]))
        if columns {
            for index in pages.indices {
                json = try ServerUIRendererFixture.changing(json, path: "document/pages/\(index)/navigation", to: .object([
                    "type": .string("navigation-columns"), "placeholder": .string("Select an Item"), "standalone": .bool(false),
                ]))
            }
        }
        json = try ServerUIRendererFixture.changing(json, path: "document/pages/0/title", to: .string(title))
        return try ServerUIRendererFixture.publication(json)
    }

    func testNativeBackAndWideExitUseTheRealFeedbackDraftGuard() async throws {
        for wide in [false, true] {
            let model = FeedbackFormModel(kind: .bug, services: FeedbackServices(filer: FeedbackFixtureFiler()))
            let provider = UKServerUIFeedbackProvider(id: "private-settings", model: model, platform: .ios,
                isCurrentSession: { true }) { _ in
                FeedbackDiagnostics(app: "Test", system: "iOS", device: "Fixture", window: "Fixture",
                                    homeAssistant: "Fixture", accessibility: "Default", locale: "en")
            }
            let publication = try publication(kind: "feedback-field", item: "description", domain: "feedback",
                                              controlTitle: "Description", pageIndex: 1, columns: wide, systemRoute: true)
            let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
                backdrop: ServerUIRendererFixture.backdrop(), settingsProviders: ["private-settings": provider])
            let window = HostedPage.show(host, size: wide ? HostedPage.splitSize : HostedPage.inScene(CGSize(width: 390, height: 844)))
            defer { window.isHidden = true }
            if wide { host.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: host.tabController) }
            await FeatureHost.settleAsync(0.1)
            let root = try ServerUIRendererFixture.root(host)
            try host.perform(.push(.init(pageId: publication.document.pages[1].id, arguments: .init(),
                                        origin: .sender, duplicate: .reuseNearest)), from: root)
            let stack = try XCTUnwrap(host.stacks[root.root])
            let settled = await FeatureHost.settleAsync(until: {
                host.tabController.view.isUserInteractionEnabled && stack.transitionCoordinator == nil
                    && root.columns?.isTransitioning != true
            })
            XCTAssertTrue(settled, "The push must finish before testing an exit.")
            let detail = try XCTUnwrap((wide ? root.columns?.entries.last?.controller : stack.topViewController) as? UKServerUIPage)
            model.descriptionText = "Keep this feedback until explicitly discarded."
            let beforeRoute = host.navigation.snapshot
            XCTAssertThrowsError(try host.openSystemRoute(RouteRequest(path: "home")))
            XCTAssertEqual(host.navigation.snapshot, beforeRoute, "A system route must not bypass a dirty native exit guard.")
            var wideApproved = false
            if wide {
                XCTAssertTrue(try XCTUnwrap(root.columns).isWide)
                XCTAssertEqual(host.nativeExitGate?.blocksExit(root), true, "The root must discover its wide detail's provider.")
                detail.requestColumnExit { wideApproved = true }
            } else {
                XCTAssertNil(stack.popViewController(animated: false))
                XCTAssertTrue(stack.topViewController === detail)
            }
            let confirmed = await FeatureHost.settleAsync(until: {
                guard let alert = FeatureHost.alert(on: host) else { return false }
                return !alert.isBeingPresented && alert.transitionCoordinator == nil
            })
            XCTAssertTrue(confirmed, "A dirty feedback draft must present a discard decision.")
            XCTAssertTrue(model.hasUnsavedInput)
            XCTAssertFalse(wideApproved)
            let alert = try XCTUnwrap(FeatureHost.alert(on: host))
            XCTAssertTrue(FeatureHost.answer(alert, "Discard Changes", dismissing: false))
            let exited = await FeatureHost.settleAsync(until: {
                wide ? wideApproved : stack.topViewController === root
            })
            XCTAssertTrue(exited, "Discard must finish the originally requested \(wide ? "column" : "native Back") exit.")
            XCTAssertFalse(model.hasUnsavedInput)
            if wide { XCTAssertTrue(wideApproved) }
            else { XCTAssertTrue(stack.topViewController === root) }
            HostedPage.hideTracked()
        }
    }

    func testMissingTargetAndExpiredSessionRejectBeforeRendering() throws {
        let publication = try publication()
        let context = UKContext(store: EntityStore(), caller: HostedCaller())
        XCTAssertThrowsError(try UKServerUIRenderer(publication: publication, context: context,
                                                    backdrop: ServerUIRendererFixture.backdrop()))
        let empty = UKServerUIHouseholdProvider(id: "private-settings", targets: [:], isCurrentSession: { true })
        XCTAssertThrowsError(try UKServerUIRenderer(publication: publication, context: context,
                                                    backdrop: ServerUIRendererFixture.backdrop(), settingsProviders: ["private-settings": empty]))
        let stale = UKServerUIHouseholdProvider(id: "private-settings", targets: [:], isCurrentSession: { false })
        XCTAssertThrowsError(try UKServerUISettingsProviders.validate(publication.document, providers: ["private-settings": stale]))
    }

    func testFeedbackFieldMeasuresRequestedWidthBeforeItsFrameCatchesUp() throws {
        let model = FeedbackFormModel(kind: .bug, services: FeedbackServices(filer: FeedbackFixtureFiler()))
        model.descriptionText = String(repeating: "This description must wrap without clipping or losing text. ", count: 16)
        let provider = UKServerUIFeedbackProvider(id: "private-settings", model: model, platform: .ios,
                                                 isCurrentSession: { true }) { _ in
            FeedbackDiagnostics(app: "Test", system: "iOS", device: "Fixture", window: "Fixture",
                                homeAssistant: "Fixture", accessibility: "AX5", locale: "en")
        }
        let renderer = try UKServerUIRenderer(
            publication: publication(kind: "feedback-field", item: "description", domain: "feedback", controlTitle: "Description"),
            context: UKContext(store: EntityStore(), caller: HostedCaller()),
            backdrop: ServerUIRendererFixture.backdrop(), settingsProviders: ["private-settings": provider])
        var heights: [CGFloat] = []
        for width in [390.0, 744.0, 1024.0] {
            let window = HostedPage.show(renderer, size: CGSize(width: width, height: 900))
            let page = try ServerUIRendererFixture.root(renderer)
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            page.view.setNeedsLayout()
            page.view.layoutIfNeeded()
            let atom = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKServerUISettingsAtom }.first)
            let field = try XCTUnwrap(atom.content as? UKFeedbackTextView)
            field.bounds.size.width = 320
            let available = width - 32
            let measured = atom.gridHeight(forWidth: available)
            let expected = ceil(field.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude)).height)
            XCTAssertEqual(measured, expected, accuracy: 1)
            XCTAssertGreaterThan(measured, field.minimumHeight)
            XCTAssertEqual(field.accessibilityLabel, "Description")
            XCTAssertEqual(field.text, model.descriptionText)
            heights.append(measured)
            window.isHidden = true
        }
        XCTAssertGreaterThan(heights[0], heights[2])
    }

    func testCanonicalTileFitsAllFamiliesAndRetainsIdentityAcrossCompatiblePublication() throws {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "off"), EntityState(entityId: "lock.demo_car", state: "locked")])
        let caller = HostedCaller()
        let target = try HouseholdSettingsTarget(kind: .toggle, entityId: "switch.demo_lamp", title: "Demo Lamp")
        let adapter = HouseholdSettingsTargetAdapter(target: target, store: store, caller: caller)
        let car = HouseholdSettingsTargetAdapter(target: try .init(kind: .readOnly, entityId: "lock.demo_car", title: "Car Doors"), store: store, caller: caller)
        let provider = UKServerUIHouseholdProvider(id: "private-settings", targets: ["lamp": adapter, "car": car], isCurrentSession: { true })
        let backdrop = try ServerUIRendererFixture.backdrop()
        let renderer = try UKServerUIRenderer(publication: publication(), context: UKContext(store: store, caller: caller),
                                               backdrop: backdrop, settingsProviders: ["private-settings": provider])
        for width in [390.0, 744.0, 1024.0] {
            let window = HostedPage.show(renderer, size: CGSize(width: width, height: 900))
            let page = try ServerUIRendererFixture.root(renderer)
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            page.view.setNeedsLayout()
            page.view.layoutIfNeeded()
            let atom = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKServerUISettingsAtom }.first)
            XCTAssertGreaterThan(atom.gridHeight(forWidth: width - 32), 44)
            XCTAssertTrue(atom.content is UKGlassTileView)
            let content = atom.content
            XCTAssertNoThrow(try renderer.apply(publication: publication(title: "Updated"), backdrop: backdrop))
            XCTAssertTrue(atom.content === content)
            window.isHidden = true
        }
        let page = try ServerUIRendererFixture.root(renderer)
        let old = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKServerUISettingsAtom }.first)
        try renderer.apply(publication: publication(kind: "household-read-only", item: "car"), backdrop: backdrop)
        let replacement = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKServerUISettingsAtom }.first)
        XCTAssertFalse(old === replacement)
        try adapter.flip(expected: adapter.controller.toggle(target.entityId))
        XCTAssertTrue(provider.protectsPublication)
        XCTAssertThrowsError(try renderer.apply(publication: publication(title: "Changed"), backdrop: backdrop))
    }

    /// With every house-configuration household list empty, a toggle the document places still acts with its authored glyph, and a
    /// reading the document places stays a flat state tile.
    func testToggleWithNoHouseConfigListsStillActsAndAReadingStaysFlat() throws {
        let source = HouseConfigSource()
        try HouseConfigSource.$scoped.withValue(source) {
            XCTAssertTrue(HouseholdSettingsConfig.Admin.securityTiles.isEmpty && HouseholdSettingsConfig.Admin.relayTiles.isEmpty
                && HouseholdSettingsConfig.Admin.showSpecificTiles.isEmpty && HouseholdSettingsConfig.Admin.autoResetTiles.isEmpty)
            let store = EntityStore()
            store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "off"), EntityState(entityId: "sensor.demo_car", state: "on")])
            let caller = HostedCaller()
            let lamp = HouseholdSettingsTargetAdapter(target: try .init(kind: .toggle, entityId: "switch.demo_lamp", title: "Demo Lamp"),
                                                      store: store, caller: caller)
            let car = HouseholdSettingsTargetAdapter(target: try .init(kind: .readOnly, entityId: "sensor.demo_car", title: "Car"),
                                                     store: store, caller: caller)
            let provider = UKServerUIHouseholdProvider(id: "private-settings", targets: ["lamp": lamp, "car": car], isCurrentSession: { true })
            let backdrop = try ServerUIRendererFixture.backdrop()
            for (kind, item) in [("household-toggle", "lamp"), ("household-read-only", "car")] {
                let renderer = try UKServerUIRenderer(publication: publication(kind: kind, item: item),
                                                       context: UKContext(store: store, caller: caller), backdrop: backdrop,
                                                       settingsProviders: ["private-settings": provider])
                let window = HostedPage.show(renderer, size: CGSize(width: 390, height: 900))
                let page = try ServerUIRendererFixture.root(renderer)
                page.view.layoutIfNeeded()
                let atom = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKServerUISettingsAtom }.first)
                let tile = try XCTUnwrap(atom.content as? UKGlassTileView)
                if kind == "household-toggle" {
                    XCTAssertEqual(tile.model.behavior, .perform(PowerToggleActions.actionId), "A toggle with no house lists is still a working toggle.")
                    XCTAssertEqual(tile.model.actions.first?.symbol, "power", "The disc draws the action glyph.")
                    XCTAssertEqual(tile.model.symbol, "lightbulb", "The face keeps the authored icon.")
                } else {
                    XCTAssertEqual(tile.model.behavior, .inert, "A reading stays state only.")
                    XCTAssertTrue(tile.model.actions.isEmpty)
                }
                window.isHidden = true
            }
        }
    }

    /// The Auto-Lock role names only the disc glyph: the lock it controls, open while off.
    func testAutoLockRoleDrawsTheLockOnTheDisc() async throws {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "off")])
        let caller = HostedCaller()
        let lamp = HouseholdSettingsTargetAdapter(target: try .init(kind: .toggle, entityId: "switch.demo_lamp", title: "Demo Lamp"),
                                                  store: store, caller: caller)
        let provider = UKServerUIHouseholdProvider(id: "private-settings", targets: ["lamp": lamp], autoLock: ["lamp"], isCurrentSession: { true })
        let renderer = try UKServerUIRenderer(publication: publication(), context: UKContext(store: store, caller: caller),
                                               backdrop: try ServerUIRendererFixture.backdrop(), settingsProviders: ["private-settings": provider])
        let window = HostedPage.show(renderer, size: CGSize(width: 390, height: 900))
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(renderer)
        page.view.layoutIfNeeded()
        let atom = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKServerUISettingsAtom }.first)
        let tile = try XCTUnwrap(atom.content as? UKGlassTileView)
        XCTAssertEqual(tile.model.actions.first?.symbol, "lock.open")
        store.apply([EntityState(entityId: "switch.demo_lamp", state: "on")])
        // Suspend between checks so the redraw, which rides on a MainActor task, can run.
        let end = Date().addingTimeInterval(5)
        func shown() -> String? { (atom.content as? UKGlassTileView)?.model.actions.first?.symbol }
        while shown() != "lock.fill", Date() < end { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(shown(), "lock.fill")
    }
}
