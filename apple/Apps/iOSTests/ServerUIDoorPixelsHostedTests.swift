import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Door tile stills for the before and after pair

/// Writes a still of the Security fixture page for each door state to `$DOOR_SHOTS_DIR/<scenario>.png`, with the tile's spoken label
/// and value in `ax.json`, at the folded Duo's width. It runs once on the tree that still has the bespoke door atom and once on the
/// lowered tile, and `tools/expo_pair_compare.py` judges the two folders. It does nothing without the directory.
@MainActor
final class ServerUIDoorPixelsHostedTests: XCTestCase {
    private struct Scenario {
        let name: String
        let tile: String
        let entity: String
        let state: String
        let words: String
    }

    private static let scenarios: [Scenario] = {
        let lock = ("demo-lock-control", "lock.demo_unit"), garage = ("demo-garage-control", "cover.demo_unit")
        return [
            Scenario(name: "lock-locked", tile: lock.0, entity: lock.1, state: "locked", words: "Locked"),
            Scenario(name: "lock-unlocked", tile: lock.0, entity: lock.1, state: "unlocked", words: "Unlocked"),
            Scenario(name: "lock-locking", tile: lock.0, entity: lock.1, state: "locking", words: "Locking"),
            Scenario(name: "lock-jammed", tile: lock.0, entity: lock.1, state: "jammed", words: "Jammed"),
            Scenario(name: "lock-unavailable", tile: lock.0, entity: lock.1, state: "unavailable", words: "Unavailable"),
            Scenario(name: "garage-closed", tile: garage.0, entity: garage.1, state: "closed", words: "Closed"),
            Scenario(name: "garage-open", tile: garage.0, entity: garage.1, state: "open", words: "Open"),
            Scenario(name: "garage-opening", tile: garage.0, entity: garage.1, state: "opening", words: "Opening"),
            Scenario(name: "garage-closing", tile: garage.0, entity: garage.1, state: "closing", words: "Closing"),
            Scenario(name: "garage-unavailable", tile: garage.0, entity: garage.1, state: "unavailable", words: "Unavailable"),
        ]
    }()

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func still(_ window: UIWindow, to url: URL) throws {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: url)
    }

    func testWriteTheDoorStills() async throws {
        guard let path = ProcessInfo.processInfo.environment["DOOR_SHOTS_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var ax: [String: [String]] = [:]
        // The folded Duo is 1398 x 2034 px at 3x.
        let size = CGSize(width: 466, height: 678)

        func capture(_ name: String, _ view: UKGlassTileView, _ window: UIWindow) async throws {
            await HostedPage.pump(passes: 40)
            try still(window, to: directory.appendingPathComponent(name + ".png"))
            ax[name] = [view.accessibilityLabel ?? "", view.accessibilityValue ?? ""]
        }

        for scenario in Self.scenarios {
            let (host, window, _) = try ServerUISecurityHostedFixture.host(size: size)
            defer { window.isHidden = true }
            let view = try XCTUnwrap(ServerUIRendererFixture.root(host).nodes[scenario.tile]?.view as? UKGlassTileView)
            // The other door sits at rest, so the still differs from the pair's other half only in the door under test.
            let others = [EntityState(entityId: "lock.demo_unit", state: "locked"), EntityState(entityId: "cover.demo_unit", state: "closed")]
            host.pageContext.store.apply(others.filter { $0.entityId != scenario.entity } + [EntityState(entityId: scenario.entity, state: scenario.state)])
            let landed = await HostedPage.settle { (view.accessibilityValue ?? "").hasPrefix(scenario.words) }
            XCTAssertTrue(landed, "\(scenario.name) read \(view.accessibilityValue ?? "nil")")
            try await capture(scenario.name, view, window)
        }
        for failing in [false, true] {
            let caller = HostedCaller()
            caller.fails = failing
            let (host, window) = try ServerUISecurityHostedFixture.host(caller: caller, size: size)
            defer { window.isHidden = true }
            let view = try XCTUnwrap(ServerUIRendererFixture.root(host).nodes["demo-garage-control"]?.view as? UKGlassTileView)
            await HostedPage.pump(passes: 10)
            view.onPerform?(try XCTUnwrap(view.model.actions.first?.id))
            await HostedPage.settle { failing ? view.model.isError : view.model.actions.first?.phase == .inFlight }
            try await capture(failing ? "garage-error" : "garage-sending", view, window)
        }
        try JSONEncoder().encode(ax).write(to: directory.appendingPathComponent("ax.json"))
    }
}
