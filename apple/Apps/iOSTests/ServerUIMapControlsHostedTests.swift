import HassCore
import UIKit
import XCTest
@testable import HassUI

/// A configured vacuum map with authored corner buttons and a flip, driven through the server-UI renderer on the card widths of the iPhone,
/// Duo and iPad. It covers the resolver (`UKServerUIMapControls`: shown, dimmed with a reason, rules, press routing), the frame's wiring and
/// observation, and a flipped map's taps.
@MainActor
final class ServerUIMapControlsHostedTests: XCTestCase {
    private static let widths: [CGFloat] = [393, 466, 834]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    private static let symbol = #"{"type":"sf-symbol","name":"star","rendering":"canonical","unavailable":"fallback"}"#
    private static let hot = #"{"type":"compare","op":"eq","left":{"type":"read","from":{"type":"source","sourceId":"source-entity","path":["state"]},"as":"string","missing":"unavailable"},"right":{"type":"literal","value":"on"}}"#

    private static func map(_ groups: String) -> String {
        #"{"kind":"map","overlay":"rooms","height":300,"runtimeHeight":460,"label":"Demo Map","loadingText":"Reading Map","unavailableText":"No Map","locate":true,"controls":"# + groups + "}"
    }

    private static let locate = #"{"id":"locate","icon":{"type":"sf-symbol","name":"scope","rendering":"canonical","unavailable":"fallback"},"label":"Locate","hint":"Asks the robot to play a sound.","action":{"type":"map","command":"locate"}}"#
    private static let clean = #"{"id":"clean","icon":"# + symbol + #","label":"Clean","action":{"type":"source-command","command":"clean"}}"#
    private static let fan = #"{"id":"fan","icon":"# + symbol + #","label":"Fan","action":{"type":"call-service","domain":"light","service":"toggle","target":{"entity_id":{"type":"literal","value":"light.demo_kitchen"}}},"enabledWhen":{"condition":"# + hot + #","whenUnknown":"disabled"}}"#
    private static let authored = "[" + #"{"corner":"top-leading","axis":"column","buttons":["# + locate + #"]},{"corner":"top-trailing","axis":"row","buttons":["# + clean + "," + fan + "]}]"

    private struct Shown {
        let host: UKServerUIRenderer
        let window: UIWindow
        let caller: ConfiguredVacuumCaller
        let store: EntityStore
        let vacuumView: UKServerUIVacuumView
        let controls: UKMapControlsView
        let frame: UKVacuumMapFrame
        let map: UKValetudoMapView
    }

    /// Shows the page with the vacuum control and waits until its buttons are drawn.
    private func show(width: CGFloat, groups: String = authored, orientation: String? = nil, state: String = "docked", lamp: String = "off",
                      services: Set<String>? = nil, leftOnly: Bool = false, rotation: Double? = nil) async throws -> Shown {
        let descriptor = try ConfiguredVacuumFixture.descriptor()
        let store = ConfiguredVacuumFixture.store(descriptor)
        store.apply([.init(entityId: descriptor.entityId, state: state), .init(entityId: "switch.demo_lamp", state: lamp)])
        let caller = ConfiguredVacuumCaller()
        let loader = ConfiguredVacuumFixture.loader(leftOnly: leftOnly)
        let publication = try ConfiguredVacuumFixture.publication(Self.map(groups), orientation: orientation, rotation: rotation,
            extra: ["sh.call-service@1", "sh.conditions@1", "sh.enabled-when@1", "sh.operands@1"])
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: caller),
            backdrop: ServerUIRendererFixture.backdrop(),
            vacuums: .init(loader: { _ in loader }, services: services ?? ConfiguredVacuumFixture.services.union(["vacuum.locate", "light.toggle"])))
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 900)))
        let page = try ServerUIRendererFixture.root(host)
        await HostedPage.settle {
            guard let view = page.nodes["robot-control"]?.view as? UKServerUIVacuumView else { return false }
            return HostedPage.descendants(of: view).contains { ($0 as? UKMapControlsView)?.drawnGroups.isEmpty == false }
        }
        let view = try XCTUnwrap(page.nodes["robot-control"]?.view as? UKServerUIVacuumView, "width \(width)")
        HostedPage.layoutTracked()
        return Shown(host: host, window: window, caller: caller, store: store, vacuumView: view, controls: try find(UKMapControlsView.self, in: view),
                     frame: try find(UKVacuumMapFrame.self, in: view), map: try find(UKValetudoMapView.self, in: view))
    }

    private func find<T: UIView>(_ type: T.Type, in root: UIView) throws -> T {
        try XCTUnwrap(HostedPage.descendants(of: root).compactMap { $0 as? T }.first, "no \(T.self) in the view tree")
    }

    // MARK: Resolver and wiring

    /// Locate, a command the vacuum offers and a rule-driven service button draw in their corners, and each runs its own action.
    func testAuthoredButtonsDrawInTheirCornersAndRun() async throws {
        for width in Self.widths {
            let shown = try await show(width: width)
            defer { shown.window.isHidden = true }
            XCTAssertEqual(shown.controls.occupiedCorners, [.topLeading, .topTrailing], "width \(width)")
            let locate = try XCTUnwrap(shown.controls.button(identifier: "vacuum.locate"), "width \(width)")
            let clean = try XCTUnwrap(shown.controls.button(identifier: "map.control.clean"), "width \(width)")
            let fan = try XCTUnwrap(shown.controls.button(identifier: "map.control.fan"), "width \(width)")
            XCTAssertEqual([locate, clean, fan].map(\.accessibilityLabel), ["Locate", "Clean", "Fan"])
            XCTAssertEqual(locate.accessibilityHint, "Asks the robot to play a sound.")
            XCTAssertFalse(locate.accessibilityTraits.contains(.notEnabled))
            XCTAssertFalse(clean.accessibilityTraits.contains(.notEnabled), "the clean script is offered")
            XCTAssertTrue(fan.accessibilityTraits.contains(.notEnabled), "the lamp is off, so the rule says no (width \(width))")
            XCTAssertEqual(fan.accessibilityValue, "Not available right now")
            locate.sendActions(for: .touchUpInside)
            let located = await HostedPage.settle { shown.caller.calls.contains { $0.hasPrefix("vacuum.locate") } }
            XCTAssertTrue(located, "Locate keeps its service call: \(shown.caller.calls)")
            let before = shown.caller.calls.count
            clean.sendActions(for: .touchUpInside)
            let ran = await HostedPage.settle { shown.caller.calls.count > before }
            XCTAssertTrue(ran, "a source command runs through the vacuum source")
            let calls = shown.caller.calls.count
            fan.sendActions(for: .touchUpInside)
            hostedSettle(0.2)
            XCTAssertEqual(shown.caller.calls.count, calls, "a dimmed button does nothing")
        }
    }

    /// The rule that dimmed the button lifts when its entity changes, and only the buttons redraw: the map is not rebuilt.
    func testAnEntityOnlyAButtonReadsRedrawsTheButtonsAndNotTheMap() async throws {
        for width in Self.widths {
            let shown = try await show(width: width)
            defer { shown.window.isHidden = true }
            let maps = shown.frame.mapRenderCount, controls = shown.frame.controlRenderCount
            shown.store.apply([.init(entityId: "switch.demo_lamp", state: "on")])
            let lifted = await HostedPage.settle { shown.controls.button(identifier: "map.control.fan")?.accessibilityTraits.contains(.notEnabled) == false }
            XCTAssertTrue(lifted, "the rule now says yes (width \(width))")
            XCTAssertGreaterThan(shown.frame.controlRenderCount, controls, "the buttons observed it")
            XCTAssertEqual(shown.frame.mapRenderCount, maps, "the map's layers were not rebuilt for a change only a button reads (width \(width))")
            shown.controls.button(identifier: "map.control.fan")?.sendActions(for: .touchUpInside)
            let toggled = await HostedPage.settle { shown.caller.calls.contains("light.toggle") }
            XCTAssertTrue(toggled, "the enabled service button calls its service")
        }
    }

    /// With the script the command needs missing from Home Assistant, the command is dimmed and says why; pressing it calls nothing.
    func testABlockedCommandIsDimmedWithItsReason() async throws {
        for width in Self.widths {
            let services = ConfiguredVacuumFixture.services.subtracting(["script.demo_clean"]).union(["vacuum.locate"])
            let shown = try await show(width: width, services: services)
            defer { shown.window.isHidden = true }
            let clean = try XCTUnwrap(shown.controls.button(identifier: "map.control.clean"), "width \(width)")
            XCTAssertTrue(clean.accessibilityTraits.contains(.notEnabled))
            XCTAssertEqual(clean.accessibilityValue, "This service is not available in Home Assistant.")
            clean.sendActions(for: .touchUpInside)
            hostedSettle(0.2)
            XCTAssertTrue(shown.caller.calls.isEmpty, "a dimmed command does nothing: \(shown.caller.calls)")
        }
    }

    /// An unreachable robot hides Locate and dims what it cannot do, each with the reason spoken.
    func testAnUnavailableRobotHidesLocateAndDimsItsCommands() async throws {
        for width in Self.widths {
            let shown = try await show(width: width, state: "unavailable")
            defer { shown.window.isHidden = true }
            XCTAssertNil(shown.controls.button(identifier: "vacuum.locate"), "Locate is hidden while the robot is unavailable (width \(width))")
            for button in ["map.control.clean"] {
                guard let control = shown.controls.button(identifier: button) else { continue }
                XCTAssertTrue(control.accessibilityTraits.contains(.notEnabled), "\(button) is dimmed (width \(width))")
                XCTAssertFalse((control.accessibilityValue ?? "").isEmpty, "\(button) speaks its reason (width \(width))")
            }
            XCTAssertNotNil(shown.controls.button(identifier: "map.control.fan"), "a service button follows its own rules (width \(width))")
        }
    }

    /// An authored top corner makes room for the fallback's words; the default map keeps the margins it always had.
    func testAnAuthoredTopRowClearsTheFallbackWords() async throws {
        for width in Self.widths {
            let shown = try await show(width: width)
            defer { shown.window.isHidden = true }
            let fallback = try XCTUnwrap(HostedPage.descendants(of: shown.frame).compactMap { $0 as? UIStackView }
                .first { $0.accessibilityIdentifier == "vacuum.map.fallback" })
            XCTAssertEqual(fallback.layoutMargins.top, 60, "the buttons' row is cleared (width \(width))")
        }
    }

    // MARK: Flip

    /// The horizontal fractions of the map's width (across its middle row) where a tap lands on the room.
    private func roomColumns(_ map: UKValetudoMapView) throws -> [Double] {
        let scene = try XCTUnwrap(map.scene)
        let size = map.bounds.size
        return stride(from: 0.02, through: 0.98, by: 0.02).filter {
            scene.room(at: CGPoint(x: size.width * $0, y: size.height / 2), size: size) != nil
        }
    }

    /// A map flipped horizontally draws its room on the other side, and a tap there lands on it.
    func testATapOnAFlippedMapLandsOnTheRightRoom() async throws {
        for width in Self.widths {
            let plain = try await show(width: width, leftOnly: true, rotation: 0)
            let plainColumns = try roomColumns(plain.map)
            XCTAssertFalse(plainColumns.isEmpty, "the room is hit somewhere (width \(width))")
            XCTAssertTrue(plainColumns.allSatisfy { $0 < 0.5 }, "the room is on the left of a plain map: \(plainColumns) (width \(width))")
            plain.window.isHidden = true
            HostedPage.hideTracked()
            let flipped = try await show(width: width, orientation: #"{"flipHorizontal":true,"flipVertical":false}"#, leftOnly: true, rotation: 0)
            defer { flipped.window.isHidden = true }
            let columns = try roomColumns(flipped.map)
            XCTAssertEqual(columns.count, plainColumns.count, "the same room, mirrored (width \(width))")
            XCTAssertTrue(columns.allSatisfy { $0 > 0.5 }, "the room is on the right once flipped: \(columns) (width \(width))")
            XCTAssertNotNil(flipped.controls.button(identifier: "vacuum.locate"), "the buttons are not mirrored")
            XCTAssertEqual(flipped.controls.frame(of: .topLeading)?.minX, 8, "Locate stays at top leading on a flipped map (width \(width))")
        }
    }
}
