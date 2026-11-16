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
/// style. Every key must equal the golden value, except the named, reviewed differences in ``differences``.
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

    private static func snapshot(_ view: UKGlassTileView) -> Snapshot {
        let model = view.model
        var result: Snapshot = [
            "title": model.title, "subtitle": model.subtitle ?? "", "symbol": model.symbol,
            "active": "\(model.isActive)", "error": "\(model.isError)", "unavailable": "\(model.isUnavailable)",
            "warning": "\(model.isWarning)",
            "look.class": model.look?.stateClass.rawValue ?? "", "look.icon": model.look?.icon ?? "",
            "look.text": model.look?.text ?? "", "look.indicator": model.look?.indicator.rawValue ?? "",
            "ax.label": view.accessibilityLabel ?? "", "ax.value": view.accessibilityValue ?? "",
            "discs": "\(model.actions.count)",
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
                host.pageContext.store.apply([EntityState(entityId: door.entity, state: state)])
                await HostedPage.pump(passes: 30)
                all["\(door.tile)/\(state)"] = Self.snapshot(view)
            }
        }
        for failing in [false, true] {
            for door in Self.doors {
                let start = door.states[0]
                let caller = HostedCaller()
                caller.fails = failing
                let (host, window) = try ServerUISecurityHostedFixture.host(caller: caller)
                defer { window.isHidden = true }
                host.pageContext.store.apply([EntityState(entityId: door.entity, state: start)])
                await HostedPage.pump(passes: 30)
                let view = try tile(host, door.tile)
                let disc = try XCTUnwrap(view.model.actions.first?.id)
                let name = "\(door.tile)/tap-\(failing ? "fails" : "sends")"
                view.onPerform?(disc)
                await HostedPage.pump(passes: 2)
                all["\(name)/during"] = Self.snapshot(view)
                await HostedPage.pump(passes: 20)
                all["\(name)/after"] = Self.snapshot(view)
                all["\(name)/calls"] = ["calls": caller.calls.joined(separator: ",")]
                if !failing {
                    let moving = door.tile == "demo-lock-control" ? "unlocking" : "opening"
                    host.pageContext.store.apply([EntityState(entityId: door.entity, state: moving)])
                    await HostedPage.pump(passes: 30)
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

    /// Keys where the generic tile reads differently by design, by journey (`*` is every journey): the reviewed departures.
    private static let differences: [String: Set<String>] = [:]

    func testTheLoweredTileDrawsWhatTheDoorAtomDrew() async throws {
        let now = try await journeys()
        guard let data = try? Data(contentsOf: Self.goldenURL) else {
            try JSONEncoder.sorted.encode(now).write(to: Self.goldenURL)
            return XCTFail("Recorded \(Self.goldenURL.path); review and commit it")
        }
        let golden = try JSONDecoder().decode([String: Snapshot].self, from: data)
        XCTAssertEqual(Set(golden.keys), Set(now.keys))
        var report: [String] = []
        for (name, expected) in golden.sorted(by: { $0.key < $1.key }) {
            guard let actual = now[name] else { continue }
            for key in Set(expected.keys).union(actual.keys).sorted() where expected[key] != actual[key] {
                let allowed = Self.differences[name]?.contains(key) == true || Self.differences["*"]?.contains(key) == true
                report.append("\(allowed ? "ALLOWED" : "DIFF") \(name) \(key): golden=\(expected[key] ?? "nil") now=\(actual[key] ?? "nil")")
            }
        }
        print("DOOR-EQUIVALENCE\n" + report.joined(separator: "\n"))
        XCTAssertTrue(report.allSatisfy { $0.hasPrefix("ALLOWED") }, report.filter { !$0.hasPrefix("ALLOWED") }.joined(separator: "\n"))
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
