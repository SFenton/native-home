import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A pan recognizer that reports what the test says.
private final class ShotPan: UIPanGestureRecognizer {
    var scriptedState: UIGestureRecognizer.State = .possible
    var point = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set {}
    }
    override func location(in view: UIView?) -> CGPoint { point }
}

// MARK: - Tile contract stills

/// Writes the stills of the tile contract (swipe bubble, state words, tile ink, grid groups) to `$TC_DIR`, and the bubble's measured metrics to
/// `$TC_DIR/bubble-metrics.txt`. It does nothing without the directory, so it never runs in a gate.
@MainActor
final class UKHostedTileContractShotsTests: XCTestCase {
    private var directory: URL? {
        ProcessInfo.processInfo.environment["TC_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func still(_ view: UIView, as name: String) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }

    /// A card of `width` on a backdrop the shot crops to, styled `style`.
    private func stage(_ style: UIUserInterfaceStyle, width: CGFloat, height: CGFloat = 150) -> (UIView, UIViewController, UIWindow) {
        let host = UIViewController()
        let window = HostedPage.show(host)
        window.overrideUserInterfaceStyle = style
        let backdrop = UIView(frame: CGRect(x: 0, y: 100, width: width + 40, height: height))
        backdrop.backgroundColor = style == .dark ? UIColor(white: 0.1, alpha: 1) : UIColor(white: 0.93, alpha: 1)
        host.view.addSubview(backdrop)
        return (backdrop, host, window)
    }

    // MARK: Swipe

    func testSwipeBubbleStillsAtEachTileWidth() throws {
        guard let directory else { throw XCTSkip("TC_DIR is not set") }
        var lines = ["width,value,bubble.x,bubble.y,bubble.width,bubble.height,font,fontSize"]
        for width: CGFloat in [170, 179, 192] {
            for (name, fractions) in [("min", [0.5, 0.0]), ("mid", [0.3, 0.55]), ("max", [0.5, 1.0])] {
                let (backdrop, _, window) = stage(.dark, width: width)
                defer { window.isHidden = true }
                let view = UKBrightnessTileView(title: "Lamp", tint: .systemYellow, percent: 40)
                view.frame = CGRect(x: 20, y: 56, width: width, height: 90)
                backdrop.addSubview(view)
                backdrop.clipsToBounds = false
                view.layoutIfNeeded()
                let tile = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UKGlassTileView }.first)
                let controller = try XCTUnwrap(tile.swipe)
                let pan = ShotPan()
                for (index, fraction) in fractions.enumerated() {
                    pan.scriptedState = index == 0 ? .began : .changed
                    pan.point = CGPoint(x: tile.bounds.width * fraction, y: 40)
                    controller.perform(NSSelectorFromString("panned:"), with: pan)
                }
                HostedPage.wait(0.35)
                try still(backdrop, as: "swipe-\(name)-w\(Int(width))")
                let label = HostedPage.descendants(of: controller.bubble).compactMap { $0 as? UILabel }.first
                let frame = controller.bubble.frame
                lines.append("\(Int(width)),\(name),\(frame.minX),\(frame.minY),\(frame.width),\(frame.height),\(label?.font.fontName ?? "?"),\(label?.font.pointSize ?? 0)")
                controller.cancel()
            }
        }
        try lines.joined(separator: "\n").write(to: directory.appendingPathComponent("bubble-metrics.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Words

    func testWordsStill() throws {
        guard directory != nil else { throw XCTSkip("TC_DIR is not set") }
        let (backdrop, _, window) = stage(.dark, width: 392, height: 120)
        defer { window.isHidden = true }
        let words = UKLightWords(on: "Lit", off: "Dark", unavailable: "No Answer", level: "{value} percent")
        for (index, percent) in [60, 0].enumerated() {
            let view = UKBrightnessTileView(title: "Lamp", tint: .systemYellow, percent: percent)
            view.words = words
            view.frame = CGRect(x: 20 + CGFloat(index) * 200, y: 16, width: 180, height: 90)
            backdrop.addSubview(view)
            view.layoutIfNeeded()
        }
        try still(backdrop, as: "words-drawn")
    }

    // MARK: Ink

    func testInkStills() throws {
        guard directory != nil else { throw XCTSkip("TC_DIR is not set") }
        for style in [UIUserInterfaceStyle.dark, .light] {
            for ink in [TileInkDefault.muted, .primary] {
                let (backdrop, _, window) = stage(style, width: 392, height: 120)
                defer { window.isHidden = true }
                var environment = UKTileEnvironment()
                environment.surface = .sheet
                environment.inkDefault = ink
                for (index, unavailable) in [false, true].enumerated() {
                    let model = UKGlassTileModel(title: "Fan", subtitle: unavailable ? "Unavailable" : "Off", symbol: "fan", family: .neutral,
                                                 isActive: false, isUnavailable: unavailable, kind: .toggle)
                    let tile = UKGlassTileView(model: model, environment: environment)
                    tile.frame = CGRect(x: 20 + CGFloat(index) * 200, y: 16, width: 180, height: tile.gridHeight(forWidth: 180))
                    backdrop.addSubview(tile)
                }
                HostedPage.wait(0.15)
                try still(backdrop, as: "ink-\(ink == .primary ? "primary" : "muted")-\(style == .dark ? "dark" : "light")")
            }
        }
    }

    // MARK: Groups

    func testGroupsStill() throws {
        guard directory != nil else { throw XCTSkip("TC_DIR is not set") }
        let groups = ServerUIGridGroups(items: [
            .init(id: "on", title: "On", states: [.active]),
            .init(id: "off", title: "Off", states: [.idle]),
            .init(id: "gone", title: "Not Answering", states: [.unavailable]),
        ])
        let (backdrop, _, window) = stage(.dark, width: 353, height: 430)
        defer { window.isHidden = true }
        let grid = UKDynamicGridView()
        backdrop.addSubview(grid)
        let faces: [(String, Bool, Bool)] = [("Lamp", false, false), ("Desk", true, false), ("Hall", false, false), ("Porch", false, true)]
        let tiles = faces.map { name, active, unavailable in
            UKGlassTileView(model: UKGlassTileModel(title: name, subtitle: unavailable ? "Unavailable" : active ? "On" : "Off", symbol: "lightbulb",
                                                    family: .neutral, isActive: active, isUnavailable: unavailable, kind: .toggle),
                            environment: UKTileEnvironment())
        }
        let grouping = UKServerUIGridGrouping(groups, gridID: "shot", grid: grid, surface: .page)
        grid.regroupItems(grouping.items(tiles.map { ($0, 1) }))
        let width = backdrop.bounds.width - 40
        grid.frame = CGRect(x: 20, y: 10, width: width, height: grid.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        grid.layoutIfNeeded()
        HostedPage.wait(0.15)
        try still(backdrop, as: "groups")
    }
}
