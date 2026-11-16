import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - What a default state tile draws, measured on any tree

/// Writes what a default generic state tile draws (height, icon colour, disc ground and disc glyph) to `$TILE_PROBE_FILE` as JSON. It uses only
/// APIs that exist on `t3/native-ingest` before `sh.tile-ink@1`, so the same file runs on that base and on a lane that adds the ink fields, and the
/// two outputs can be compared. It does nothing without the file.
@MainActor
final class ServerUIDefaultsProbeHostedTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func rgba(_ color: UIColor?, in view: UIView) -> [Double] {
        guard let color else { return [] }
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        color.resolvedColor(with: view.traitCollection).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { Double(($0 * 255).rounded()) / 255 }
    }

    func testWritesTheDefaultStateTileMeasurements() throws {
        guard let path = ProcessInfo.processInfo.environment["TILE_PROBE_FILE"], !path.isEmpty else { throw XCTSkip("no probe file") }
        var report: [String: Any] = [:]
        for (name, width, withDisc) in [("plain170", CGFloat(170), false), ("disc260", CGFloat(260), true)] {
            let items = [TileActionItem(id: "pause", verb: "Pause", symbol: "pause.fill")]
            let model = withDisc
                ? UKGlassTileModel(title: "Robot", subtitle: "Docked", symbol: "fan", family: .neutral, isActive: false,
                                   behavior: .perform("pause"), actions: items, identifier: "tile")
                : UKGlassTileModel(title: "Robot", subtitle: "Docked", symbol: "fan", family: .neutral, isActive: false, kind: .state, identifier: "tile")
            let tile = UKGlassTileView(model: model, environment: UKTileEnvironment())
            let host = UIViewController()
            host.view.addSubview(tile)
            let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: 300, height: 400)))
            let height = tile.gridHeight(forWidth: width)
            tile.frame = CGRect(x: 0, y: 0, width: width, height: height)
            HostedPage.wait(0.2)
            tile.layoutIfNeeded()
            let images = HostedPage.descendants(of: tile).compactMap { $0 as? UIImageView }.filter { $0.image != nil }
            let discs = HostedPage.descendants(of: tile).filter { String(describing: type(of: $0)) == "UKTileActionDisc" }
            report[name] = [
                "height": Double(height),
                "imageTints": images.map { rgba($0.tintColor, in: tile) + [Double($0.alpha)] },
                "discGround": discs.map { rgba($0.backgroundColor, in: $0) },
                "discGlyphTints": discs.flatMap { disc in HostedPage.descendants(of: disc).compactMap { $0 as? UIImageView }.map { rgba($0.tintColor, in: disc) } },
            ] as [String: Any]
            window.isHidden = true
            HostedPage.hideTracked()
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }
}
