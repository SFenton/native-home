import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - A device fact degrades a node and the layout commits

/// Forces each OS gap in turn (a symbol this OS cannot draw, a chrome priority and rail below their OS versions, a shared group before
/// glass) and asserts the publication still validates and mounts. The older OS is modelled by `UKServerUIPreflight.override`, so the
/// same test runs on any simulator and on all three device families.
@MainActor
final class ServerUIDeviceGapHostedTests: XCTestCase {
    private typealias Fixture = ServerUIRendererFixture

    override func tearDown() async throws {
        UKServerUIPreflight.override = nil
        UKGlassEra.override = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    nonisolated private static let fallback = ServerUIDeviceFacts.fallbackSymbol

    private func facts(hasGlass: Bool = true, priority: Bool = true, rail: Bool = true,
                       draws: @escaping @Sendable (String) -> Bool = { _ in true }) -> ServerUIDeviceFacts {
        ServerUIDeviceFacts(hasGlass: hasGlass, supportsPriority: priority, supportsHorizontalOnlyRail: rail, drawsSymbol: draws)
    }

    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    // MARK: Symbols

    func testASymbolTheOSCannotDrawDrawsTheFallbackAndTheLayoutCommits() async throws {
        UKServerUIPreflight.override = facts(draws: { $0 == Self.fallback })
        let publication = try Fixture.publication()
        let degrades = try UKServerUIPreflight.validate(publication)
        XCTAssertTrue(degrades.contains(ServerUIDegradation(.symbol, at: "/document/pages/0/icon/name")), "each degrade is reported")
        XCTAssertTrue(degrades.allSatisfy { $0.kind == .symbol })
        XCTAssertNoThrow(try UKServerUIRenderer.preflight(publication), "a device fact never rejects the document")

        let (renderer, window, _) = try Fixture.host(publication: publication, size: HostedPage.phoneSize)
        defer { window.isHidden = true }
        let page = try Fixture.root(renderer)
        XCTAssertFalse(try Fixture.root(renderer).nodes.isEmpty, "the layout committed")
        let tab = try XCTUnwrap(publication.document.navigation.tabs.first)
        XCTAssertEqual(tab.icon.drawn, Self.fallback, "the UIKit layer resolves the drawn name from the preflight facts")
        XCTAssertNotEqual(tab.icon.name, Self.fallback, "Core keeps the authored name")
        let drawn = try await eventually { Fixture.barItems(page).contains { $0.image != nil } }
        XCTAssertTrue(drawn, "a bar item draws the fallback glyph")
    }

    func testAStateTileWhoseNodeIconIsMissingDrawsTheFallbackAndTheLayoutCommits() async throws {
        UKServerUIPreflight.override = facts(draws: { $0 == Self.fallback })
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf:
            apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/state-style-authored-vacuum.json")))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try Fixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try Fixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        let publication = try Fixture.publication(json)
        let degrades = try UKServerUIPreflight.validate(publication)
        XCTAssertTrue(degrades.contains { $0.pointer.hasSuffix("/icon/name") && $0.pointer.contains("/components/0/") },
                      "the tile's node icon is reported, not thrown")

        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "vacuum.demo_robot", state: "unavailable")])
        let renderer = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: HostedCaller()),
                                              backdrop: Fixture.backdrop())
        renderer.stateStylesEnabled = true
        let window = HostedPage.show(renderer, size: HostedPage.phoneSize)
        defer { window.isHidden = true }
        let page = try Fixture.root(renderer)
        let tile = try XCTUnwrap(page.nodes["demo-tile"]?.view as? UKGlassTileView)
        let drawsFallback = try await eventually { tile.model.symbol == Self.fallback }
        XCTAssertTrue(drawsFallback, "an unavailable entity shows the node icon, which degraded to the fallback")
    }

    func testAnUnreachableSurfacesMissingSymbolNoLongerRejectsThePublication() throws {
        UKServerUIPreflight.override = facts(draws: { $0 != "not.a.real.symbol.serverui" })
        let json = try Fixture.changing(Fixture.json(), path: "/document/pages/2/icon/name", to: .string("not.a.real.symbol.serverui"))
        let publication = try Fixture.publication(json)
        let degrades = try UKServerUIPreflight.validate(publication)
        XCTAssertEqual(degrades, [ServerUIDegradation(.symbol, at: "/document/pages/2/icon/name")])
        XCTAssertEqual(publication.document.pages[2].surface.icon.drawn, Self.fallback)
    }

    /// The live published revision still carries `"unavailable": "reject"`; it is an alias of `fallback` and degrades, never rejects.
    func testTheLegacyRejectAliasOnARealSymbolDegradesToTheFallback() throws {
        UKServerUIPreflight.override = facts(draws: { $0 == Self.fallback })
        for word in ["reject", "fallback"] {
            let json = try Fixture.changing(Fixture.json(), path: "/document/navigation/tabs/0/icon/unavailable", to: .string(word))
            let publication = try Fixture.publication(json)
            let degrades = try UKServerUIPreflight.validate(publication)
            XCTAssertTrue(degrades.contains { $0.kind == .symbol }, "\(word): the symbol degrades")
            XCTAssertNoThrow(try UKServerUIRenderer.preflight(publication), "\(word): nothing rejects for a device gap")
            XCTAssertEqual(publication.document.navigation.tabs[0].icon.drawn, Self.fallback)
        }
    }

    /// The Core name never depends on install order; only the UIKit answer follows the preflight facts.
    func testTheCoreSymbolNameIsTheSameBeforeAndAfterTheFactsInstall() throws {
        let publication = try Fixture.publication()
        let icon = try XCTUnwrap(publication.document.navigation.tabs.first).icon
        UKServerUIPreflight.override = nil
        let authored = icon.name
        UKServerUIPreflight.override = facts(draws: { $0 == Self.fallback })
        XCTAssertEqual(icon.name, authored)
        XCTAssertEqual(icon.drawn, Self.fallback)
        UKServerUIPreflight.override = facts(draws: { _ in true })
        XCTAssertEqual(icon.name, authored)
        XCTAssertEqual(icon.drawn, authored)
    }

    func testAnInvalidDocumentStillRejects() throws {
        let json = try Fixture.changing(Fixture.json(), path: "/document/navigation/initialTabId", to: .null)
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(Fixture.publication(json))) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.pointer, "/document/navigation/initialTabId")
        }
    }

    // MARK: Chrome

    func testPriorityAndRailBelowTheirOSesActAsNormalAndTheLayoutCommits() async throws {
        UKServerUIPreflight.override = facts(priority: false, rail: false)
        var json = try Fixture.json()
        json = try Fixture.changing(json, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("low"))
        json = try Fixture.changing(json, path: "/document/navigation/chrome/groups/1/items/0/rail", to: .string("horizontal-only"))
        let publication = try Fixture.publication(json)
        let degrades = try UKServerUIPreflight.validate(publication)
        XCTAssertEqual(degrades.map(\.kind), [.priority, .rail])
        XCTAssertEqual(degrades.map(\.pointer), ["/document/navigation/chrome/groups/1/items/0/priority",
                                                 "/document/navigation/chrome/groups/1/items/0/rail"])
        XCTAssertNoThrow(try UKServerUIRenderer.preflight(publication))

        let (renderer, window, _) = try Fixture.host(publication: publication, size: HostedPage.phoneSize)
        defer { window.isHidden = true }
        let page = try Fixture.root(renderer)
        let drawn = try await eventually { Fixture.barItems(page).contains { $0.accessibilityIdentifier == "chrome-palette" } }
        XCTAssertTrue(drawn, "the degraded item is still in the bar")
        if #available(iOS 27.0, *) {
            let item = try XCTUnwrap(Fixture.barItems(page).first { $0.accessibilityIdentifier == "chrome-palette" })
            XCTAssertEqual(item.visibilityPriority, .standard, "a priority this OS does not honour acts as normal")
        }
    }

    func testASharedGroupBeforeGlassActsAsSeparateAndTheLayoutCommits() async throws {
        UKGlassEra.override = false
        UKServerUIPreflight.override = facts(hasGlass: false)
        let json = try Fixture.changing(Fixture.json(), path: "/document/navigation/chrome/groups/0/horizontal", to: .string("shared@1"))
        let publication = try Fixture.publication(json)
        let degrades = try UKServerUIPreflight.validate(publication)
        XCTAssertEqual(degrades, [ServerUIDegradation(.sharedGroup, at: "/document/navigation/chrome/groups/0/horizontal")])
        XCTAssertNoThrow(try UKServerUIRenderer.preflight(publication), "the old rejection is gone")

        let (renderer, window, _) = try Fixture.host(publication: publication, size: HostedPage.phoneSize)
        defer { window.isHidden = true }
        let page = try Fixture.root(renderer)
        let mounted = try await eventually { !Fixture.barItems(page).isEmpty }
        XCTAssertTrue(mounted)
        // A vertical rail (the folded Duo) groups items whatever the policy says; only the horizontal bar shows the degrade.
        if page.context.shell?.inVerticalBar != true {
            XCTAssertTrue(page.navigationItem.leadingItemGroups.isEmpty, "before glass the group is separate items, not a shared-material group")
        }
    }

    func testTheSameSharedGroupOnGlassKeepsItsSharedMaterial() async throws {
        UKGlassEra.override = true
        UKServerUIPreflight.override = facts(hasGlass: true)
        let json = try Fixture.changing(Fixture.json(), path: "/document/navigation/chrome/groups/0/horizontal", to: .string("shared@1"))
        let publication = try Fixture.publication(json)
        XCTAssertEqual(try UKServerUIPreflight.validate(publication), [])
        let (renderer, window, _) = try Fixture.host(publication: publication, size: HostedPage.phoneSize)
        defer { window.isHidden = true }
        let page = try Fixture.root(renderer)
        let grouped = try await eventually { !page.navigationItem.leadingItemGroups.isEmpty }
        XCTAssertTrue(grouped)
    }

    func testAStyleActionSymbolTheOSCannotDrawDrawsTheFallbackAndKeepsItsCall() throws {
        UKServerUIPreflight.override = facts(draws: { $0 == Self.fallback })
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf:
            apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/state-style-built-in-only-tile.json")))
        let binding = "/document/pages/2/components/0/binding"
        json = try Fixture.changing(json, path: binding + "/entityId", to: .string("lock.demo_front"))
        json = try Fixture.changing(json, path: binding + "/builtIn", to: .string("lock"))
        let publication = try Fixture.publication(json)
        guard case .stateTile(let tile) = publication.document.pages[2].surface.components[0] else { return XCTFail("no state tile") }
        let face = UKServerUIStateTileViews.face(for: tile, library: publication.document.stateStyles, capability: true,
                                                 state: EntityState(entityId: "lock.demo_front", state: "locked"),
                                                 request: .init(isInFlight: false, failed: false, isUnknown: false))
        let spec = try XCTUnwrap(face.spec)
        XCTAssertEqual(spec.symbol, Self.fallback, "the action's authored symbol degrades, it does not draw nothing")
        XCTAssertEqual(spec.call?.service, "unlock", "the call the disc runs is untouched")
        XCTAssertNotEqual(face.model.symbol, "lock.fill", "the face glyph is not the undrawable symbol either")
        XCTAssertNotNil(UIImage(systemName: face.model.symbol))
    }
}
