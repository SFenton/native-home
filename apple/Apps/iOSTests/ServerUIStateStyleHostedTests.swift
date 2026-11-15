import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Authored state styles on the tile

/// A `state-tile` over an authored style (`sh.state-style@1`), rendered by the host from the Studio's shared corpus document.
///
/// The document is `accept/state-style-authored-vacuum.json`: a saved style over a vacuum, with a tile that overrides the cleaning
/// text and the returning icon. The tile's page swaps components with the root page so the test reaches it.
@MainActor
final class ServerUIStateStyleHostedTests: XCTestCase {
    private static let tileID = "demo-tile"
    /// One width per family: iPhone, Duo folded and iPad portrait (each clamped to the scene it runs in).
    private static let widths: [CGFloat] = [393, 466, 834]
    private var scheduler = HandScheduler()

    override func setUp() async throws {
        try await super.setUp()
        scheduler = HandScheduler()
        UKStateTileTransition.schedulerOverride = scheduler
    }

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private static func corpus(_ name: String, styleId: String? = nil) throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf:
            apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/state-style-\(name).json")))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        let tileComponents = try XCTUnwrap(pages[2]["components"])
        let rootComponents = try XCTUnwrap(pages[0]["components"])
        // Swap the two pages' components, so every id stays unique and the tile sits on the root page.
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: tileComponents)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: rootComponents)
        if let styleId {
            json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components/0/binding/styleId", to: .string(styleId))
        }
        return try ServerUIRendererFixture.publication(json)
    }

    private func host(_ publication: ServerUICompositionPublication, width: CGFloat, state: String, capability: Bool = true)
        async throws -> (UKServerUIRenderer, UIWindow, UKGlassTileView, EntityStore, HostedCaller) {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "vacuum.demo_robot", state: state)])
        let caller = HostedCaller()
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: caller),
                                         backdrop: ServerUIRendererFixture.backdrop())
        host.stateStylesEnabled = capability
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 852)))
        let page = try ServerUIRendererFixture.root(host)
        await HostedPage.settle { page.nodes[Self.tileID]?.view is UKGlassTileView }
        let tile = try XCTUnwrap(page.nodes[Self.tileID]?.view as? UKGlassTileView)
        return (host, window, tile, store, caller)
    }

    func testAnAuthoredStyleRendersOnTheTileAndFollowsTheLiveState() async throws {
        for width in Self.widths {
            let (_, window, tile, store, _) = try await host(Self.corpus("authored-vacuum"), width: width, state: "cleaning")
            defer { window.isHidden = true }
            // The tile's override beats the style's rule for the text; the rule's icon and the colour class stay.
            XCTAssertEqual(tile.model.look?.text, "Vacuuming", "width \(width)")
            XCTAssertEqual(tile.model.look?.icon, "fan")
            XCTAssertEqual(tile.model.look?.stateClass, .resting)
            XCTAssertTrue(tile.model.isActive)
            XCTAssertEqual(tile.model.look?.indicator, .pulse)
            XCTAssertFalse(tile.model.look?.hasAction ?? true, "the vacuum style authors no action: no disc to tap")

            store.apply([EntityState(entityId: "vacuum.demo_robot", state: "returning")])
            var landed = await HostedPage.settle { tile.model.look?.icon == "house" }
            XCTAssertTrue(landed, "width \(width)")
            XCTAssertEqual(tile.model.look?.icon, "house", "an icon override")
            XCTAssertEqual(tile.model.look?.indicator, .arc, "an authored arc stands in the disc's place")
            XCTAssertEqual(tile.model.look?.stateClass, .inProgress, "a colour token never changes the class")
            XCTAssertEqual(tile.model.look?.colour, .init(.inProgress, active: true), "the lit palette token sets the face")

            // The in-progress look is on screen, so the flap guard holds the next one until its release fires. The hand scheduler
            // fires every pending timer on each pass (the arc's effect timer may be there too), so no wall clock decides how long
            // the hold lasts, and the pass that follows the release finds the paused look shown.
            store.apply([EntityState(entityId: "vacuum.demo_robot", state: "paused")])
            landed = await HostedPage.settle {
                self.scheduler.fire()
                return tile.model.look?.stateClass == .warning
            }
            XCTAssertTrue(landed, "the paused look shows once the flap guard releases (width \(width))")
            XCTAssertEqual(tile.model.look?.stateClass, .warning)
            XCTAssertTrue(tile.model.isWarning)
            XCTAssertEqual(tile.model.look?.text, "Paused", "Home Assistant's own state name when the rule gives no words")

            store.apply([EntityState(entityId: "vacuum.demo_robot", state: "unavailable")])
            landed = await HostedPage.settle { tile.model.look?.stateClass == .unknown }
            XCTAssertTrue(landed, "width \(width)")
            XCTAssertEqual(tile.model.look?.indicator, StateTileLook.Indicator.none, "unknown never shows an arc")
            HostedPage.hideTracked()
        }
    }

    func testADeviceWithoutTheCapabilityShowsTheBuiltInStyleAndRejectsNothing() async throws {
        for width in Self.widths {
            let (_, window, tile, _, _) = try await host(Self.corpus("authored-vacuum"), width: width, state: "cleaning", capability: false)
            defer { window.isHidden = true }
            XCTAssertEqual(tile.model.look?.text, "Cleaning", "the robot style's own words, not the override's (width \(width))")
            XCTAssertEqual(tile.model.look?.indicator, .breathe)
            HostedPage.hideTracked()
        }
    }

    func testAnUnknownStyleIdFallsBackToTheTilesBuiltInStyle() async throws {
        for width in Self.widths {
            let (_, window, tile, _, _) = try await host(Self.corpus("authored-vacuum", styleId: "removed-style"), width: width, state: "cleaning")
            defer { window.isHidden = true }
            // The built-in robot style with the tile's overrides: the override still names the text.
            XCTAssertEqual(tile.model.look?.text, "Vacuuming", "width \(width)")
            XCTAssertEqual(tile.model.look?.icon, "fan", "the built-in robot style gives no glyph, so the tile's own icon stands")
            XCTAssertEqual(tile.model.look?.indicator, .pulse)
            HostedPage.hideTracked()
        }
    }

    func testAStyleWithAnActionRunsItsServiceOnTheBoundEntity() async throws {
        for width in Self.widths {
            var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/state-style-request-lifecycle.json")))
            let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
            let tileComponents = try XCTUnwrap(pages[2]["components"])
            let rootComponents = try XCTUnwrap(pages[0]["components"])
            // Swap the two pages' components, so every id stays unique and the tile sits on the root page.
            json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: tileComponents)
            json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: rootComponents)
            let store = EntityStore()
            store.replaceAll([EntityState(entityId: "media_player.demo_player", state: "off")])
            let caller = HostedCaller()
            let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(json),
                                             context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop())
            let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 852)))
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            await HostedPage.settle { page.nodes[Self.tileID]?.view is UKGlassTileView }
            let tile = try XCTUnwrap(page.nodes[Self.tileID]?.view as? UKGlassTileView)
            XCTAssertEqual(tile.model.look?.hasAction, true, "width \(width)")
            XCTAssertEqual(tile.model.look?.icon, "play.fill")
            XCTAssertEqual(tile.model.behavior, .perform("player"))
            let action = try XCTUnwrap(tile.model.actions.first)
            XCTAssertEqual(action.verb, "Turn On")
            tile.onPerform?(action.id)
            let sent = await HostedPage.settle { caller.calls == ["media_player.turn_on"] }
            XCTAssertTrue(sent, "the call is the authored service on the bound entity (width \(width))")
            HostedPage.hideTracked()
        }
    }

    // MARK: The colour layer

    private static func look(_ style: StateStyle, _ state: String, colour: StateColour?, request: UKStateTileLooks.Request = .init(),
                              hasDisc: Bool = true) -> (StateTileLook, StateResolution) {
        var resolution = style.resolve(EntityState(entityId: "x.demo", state: state), entityId: "x.demo")
        resolution.colour = colour
        let look = UKStateTileLooks.look(resolution, request: request, icon: "fan", text: resolution.words, isActive: resolution.isActive, hasDisc: hasDisc)
        return (look, resolution)
    }

    func testLitOnReturningKeepsInProgressTheArcAndTheSpokenClass() {
        let (look, _) = Self.look(.robot, "returning", colour: .lit, hasDisc: false)
        XCTAssertEqual(look.stateClass, .inProgress)
        XCTAssertEqual(look.indicator, .arc)
        XCTAssertEqual(look.colour, .init(.inProgress, active: true), "the face is lit")
        XCTAssertEqual(StateTileLook.spokenValue(text: look.text, stateClass: look.stateClass), "Returning, in progress")
        XCTAssertFalse(look.acceptsTaps)
    }

    func testLitOnALockStateWithARequestInFlightIsInProgress() {
        let (look, _) = Self.look(.lock, "locked", colour: .lit, request: .init(isInFlight: true))
        XCTAssertEqual(look.stateClass, .inProgress, "the request decides the class, not the token")
        XCTAssertEqual(look.colour, .init(.inProgress, active: true))
    }

    func testLitOnALockStateWithAFailedRequestIsAnErrorWithTheErrorFace() {
        let (look, resolution) = Self.look(.lock, "locked", colour: .lit, request: .init(failed: true))
        XCTAssertEqual(look.stateClass, .error)
        XCTAssertEqual(look.colour, .init(.error, active: resolution.isActive), "the error face, not the token's")
        XCTAssertEqual(look.indicator, .wiggle)
    }

    func testATokenNeverChangesTheSpokenValue() {
        for state in ["locked", "unlocked", "locking", "open", "jammed"] {
            let plain = Self.look(.lock, state, colour: nil).0
            for token in StateColour.allCases {
                let tokened = Self.look(.lock, state, colour: token).0
                XCTAssertEqual(StateTileLook.spokenValue(text: tokened.text, stateClass: tokened.stateClass),
                               StateTileLook.spokenValue(text: plain.text, stateClass: plain.stateClass), "\(state) \(token)")
                XCTAssertEqual(tokened.stateClass, plain.stateClass)
                XCTAssertEqual(tokened.indicator, plain.indicator)
            }
        }
    }

    func testATokenSetsOnlyTheLitFaceOfARestingState() {
        XCTAssertEqual(Self.look(.switch, "on", colour: .unlit).0.colour, .init(.resting, active: false))
        XCTAssertEqual(Self.look(.switch, "off", colour: .lit).0.colour, .init(.resting, active: true))
    }

    func testAWarningAnErrorAndAnUnknownStateKeepTheirClassFace() {
        XCTAssertEqual(Self.look(.lock, "open", colour: .unlit).0.colour, .init(.warning, active: true))
        XCTAssertEqual(Self.look(.lock, "jammed", colour: .unlit).0.colour, .init(.error, active: true))
        XCTAssertEqual(Self.look(.lock, "open", colour: .unlit).0.stateClass, .warning)
    }

    func testAColourTokenDoesNotOverrideTheUnknownFace() {
        var resolution = StateStyle.robot.resolve(EntityState(entityId: "vacuum.demo_x", state: "docked"), entityId: "vacuum.demo_x")
        resolution.colour = .lit
        let look = UKStateTileLooks.look(resolution, request: .init(isUnknown: true), icon: "fan", text: "Unavailable", isActive: false,
                                         hasDisc: false)
        XCTAssertEqual(look.stateClass, .unknown, "an unreachable entity is the unknown class whatever the style says")
    }
}
