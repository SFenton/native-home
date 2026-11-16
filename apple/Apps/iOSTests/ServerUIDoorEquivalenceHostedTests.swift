import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - The door tile and the lowered state tile draw the same

/// Renders the Security fixture's lock and garage door tiles for every state and request phase and compares what each tile shows
/// with `Fixtures/ServerUIDoorGolden.json`.
///
/// The golden file was recorded from the bespoke `door-tile` atom (`UKServerUISecurityViews`, `UKServerUIDoorSource`) before it was
/// deleted. The same journeys now run through the compile-time lowering onto a `state-tile` over the built-in `garage-door` or `lock`
/// style. Every key must equal the golden value, except the Designer's revised expectations in ``revised``, which are exact.
@MainActor
final class ServerUIDoorEquivalenceHostedTests: XCTestCase {
    typealias Snapshot = [String: String]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Journeys

    private struct Door {
        let tile: String
        let entity: String
        let states: [String]
    }

    private static let doors = [
        Door(tile: "demo-lock-control", entity: "lock.demo_unit",
             states: ["locked", "unlocked", "locking", "unlocking", "open", "jammed", "unavailable", "unknown", "stuck"]),
        Door(tile: "demo-garage-control", entity: "cover.demo_unit",
             states: ["closed", "open", "opening", "closing", "stopped", "unavailable", "unknown"]),
    ]

    /// The words the tile reads for each state: the fixture's authored text, "Unknown" for a state it does not author, "Unavailable"
    /// for an entity that is not there. The test waits for them, never for a time.
    private static let words: [String: String] = [
        "locked": "Locked", "unlocked": "Unlocked", "locking": "Locking", "unlocking": "Unlocking", "open": "Unknown",
        "jammed": "Jammed", "unavailable": "Unavailable", "unknown": "Unavailable", "stuck": "Unknown",
        "closed": "Closed", "opening": "Opening", "closing": "Closing", "stopped": "Unknown",
    ]

    /// Applies `state` and suspends until the tile's accessibility value says it, within a bound that counts passes.
    private func show(_ state: String, of door: Door, in host: UKServerUIRenderer, _ view: UKGlassTileView) async {
        host.pageContext.store.apply([EntityState(entityId: door.entity, state: state)])
        var expected = Self.words[state] ?? state
        if door.tile == "demo-garage-control", state == "open" { expected = "Open" }
        let landed = await HostedPage.settle { (view.accessibilityValue ?? "").hasPrefix(expected) }
        XCTAssertTrue(landed, "\(door.tile) never read \(expected) for \(state); read \(view.accessibilityValue ?? "nil")")
    }

    private static func snapshot(_ view: UKGlassTileView) -> Snapshot {
        let model = view.model
        var result: Snapshot = [
            "title": model.title, "subtitle": model.subtitle ?? "", "symbol": model.symbol,
            "active": "\(model.isActive)", "error": "\(model.isError)", "unavailable": "\(model.isUnavailable)",
            "warning": "\(model.isWarning)",
            "look.class": model.look?.stateClass.rawValue ?? "", "look.icon": model.look?.icon ?? "",
            "look.text": model.look?.text ?? "", "look.indicator": model.look?.indicator.rawValue ?? "",
            "ax.label": view.accessibilityLabel ?? "", "ax.value": view.accessibilityValue ?? "",
            "discs": "\(model.actions.count)", "fill": model.fillRGB.map { String($0, radix: 16) } ?? "-",
        ]
        for (index, action) in model.actions.enumerated() {
            result["disc\(index)"] = "\(action.id)|\(action.verb)|\(action.symbol)|\(action.phase)|\(action.isOn.map(String.init) ?? "-")|\(action.isError)"
        }
        return result
    }

    private func tile(_ host: UKServerUIRenderer, _ id: String) throws -> UKGlassTileView {
        let page = try ServerUIRendererFixture.root(host)
        return try XCTUnwrap(page.nodes[id]?.view as? UKGlassTileView, id)
    }

    /// Every journey, by name: each state, then the request phases of a tap and of a tap that fails.
    private func journeys() async throws -> [String: Snapshot] {
        var all: [String: Snapshot] = [:]
        for door in Self.doors {
            let (host, window, _) = try ServerUISecurityHostedFixture.host()
            defer { window.isHidden = true }
            let view = try tile(host, door.tile)
            for state in door.states {
                await show(state, of: door, in: host, view)
                all["\(door.tile)/\(state)"] = Self.snapshot(view)
            }
        }
        // A cold launch or a reconnect: the store has no state for the door yet.
        for door in Self.doors {
            let (host, window, _) = try ServerUISecurityHostedFixture.host(omitting: [door.entity])
            defer { window.isHidden = true }
            await HostedPage.pump(passes: 20)
            all["\(door.tile)/no-state"] = Self.snapshot(try tile(host, door.tile))
        }
        for failing in [false, true] {
            for door in Self.doors {
                let start = door.states[0]
                let caller = HostedCaller()
                caller.fails = failing
                let (host, window) = try ServerUISecurityHostedFixture.host(caller: caller)
                defer { window.isHidden = true }
                host.pageContext.store.apply([EntityState(entityId: door.entity, state: start)])
                await HostedPage.pump(passes: 5)
                let view = try tile(host, door.tile)
                let disc = try XCTUnwrap(view.model.actions.first?.id)
                let name = "\(door.tile)/tap-\(failing ? "fails" : "sends")"
                view.onPerform?(disc)
                // The tile redraws one turn after the tap: wait for what the request does to it, not for a time.
                await HostedPage.settle { failing ? view.model.isError : view.model.actions.first?.phase == .inFlight }
                all["\(name)/during"] = Self.snapshot(view)
                await HostedPage.settle { !caller.calls.isEmpty }
                await HostedPage.pump(passes: 10)
                all["\(name)/after"] = Self.snapshot(view)
                all["\(name)/calls"] = ["calls": caller.calls.joined(separator: ",")]
                if !failing {
                    let moving = door.tile == "demo-lock-control" ? "unlocking" : "opening"
                    await show(moving, of: door, in: host, view)
                    // The optimistic value clears one turn after the real state lands; the lock's disc stays in flight while it moves.
                    if door.tile == "demo-garage-control" { await HostedPage.settle { view.model.actions.first?.phase != .inFlight } }
                    all["\(name)/confirmed"] = Self.snapshot(view)
                }
            }
        }
        return all
    }

    // MARK: Golden

    private static var goldenURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ServerUIDoorGolden.json")
    }

    /// What the golden says no longer, by journey: the expectation the Designer set (`build/design/native-ingest/door-disc-verdict.md`,
    /// option 3). A garage door whose request is on its way keeps the disc of the state it asked for, like every other state tile: the
    /// old atom kept the verb and on-state of the state it had left ("Open", off), an accident of its code, so VoiceOver now reads
    /// "Reverse <title>, On, in progress". Nothing is drawn differently: the arc stands in for the disc's fill and glyph while it shows.
    /// The comparison stays exact against this value.
    private static let revised: [String: Snapshot] = [
        "demo-garage-control/tap-sends/during": ["disc0": "door|Reverse|door.garage.open|inFlight|true|false"],
        "demo-garage-control/tap-sends/after": ["disc0": "door|Reverse|door.garage.open|inFlight|true|false"],
    ]

    func testTheLoweredTileDrawsWhatTheDoorAtomDrew() async throws {
        let now = try await journeys()
        guard let data = try? Data(contentsOf: Self.goldenURL) else {
            try JSONEncoder.sorted.encode(now).write(to: Self.goldenURL)
            return XCTFail("Recorded \(Self.goldenURL.path); review and commit it")
        }
        let golden = try JSONDecoder().decode([String: Snapshot].self, from: data)
        XCTAssertEqual(Set(golden.keys), Set(now.keys))
        var report: [String] = []
        for (name, recorded) in golden.sorted(by: { $0.key < $1.key }) {
            guard let actual = now[name] else { continue }
            let expected = recorded.merging(Self.revised[name] ?? [:]) { _, new in new }
            for key in Set(expected.keys).union(actual.keys).sorted() where expected[key] != actual[key] {
                report.append("DIFF \(name) \(key): expected=\(expected[key] ?? "nil") now=\(actual[key] ?? "nil")")
            }
        }
        print("DOOR-EQUIVALENCE\n" + report.joined(separator: "\n"))
        XCTAssertTrue(report.isEmpty, report.joined(separator: "\n"))
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
