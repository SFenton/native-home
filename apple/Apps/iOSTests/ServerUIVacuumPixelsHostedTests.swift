import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Vacuums page and sheet stills for the before and after pair

/// Writes a still of the owner's Vacuums page, and of the vacuum sheet its first card opens, for each bootstrap file in
/// `$VAC_DIR/in` to `$VAC_DIR/out/<name>-page.png` and `-sheet.png`, at the folded Duo's width, with the window's spoken labels in
/// `<name>.ax.json`. The publication is `$VAC_DIR/publication.json`. It runs once on the tree that still has the bespoke atoms and once on
/// the lowered one, on the same simulator; `tools/expo_pair_compare.py` judges the two folders. It does nothing without the directory.
@MainActor
final class ServerUIVacuumPixelsHostedTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    /// The services a connected Home Assistant lists: without them the old atoms dim every command, which a running app never shows.
    private static let services: Set<String> = {
        let byDomain = ["vacuum": ["start", "pause", "stop", "return_to_base", "locate", "clean_spot"], "script": ["turn_on"],
                        "input_boolean": ["turn_on", "turn_off"], "switch": ["turn_on", "turn_off"], "input_select": ["select_option"],
                        "input_text": ["set_value"], "automation": ["turn_on", "turn_off"]]
        return Set(byDomain.flatMap { domain, names in names.map { domain + "." + $0 } })
    }()

    private func still(_ window: UIWindow, to url: URL) throws {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: url)
    }

    private func labels(_ view: UIView) -> [String] {
        var found = [view.accessibilityLabel].compactMap { $0 }.filter { !$0.isEmpty }
        for element in view.accessibilityElements ?? [] {
            if let child = element as? UIView { found += labels(child) } else if let label = (element as? NSObject)?.accessibilityLabel { found.append(label) }
        }
        for child in view.subviews { found += labels(child) }
        return found
    }

    /// The window's labels, with the sheet's first.
    private func spoken(_ window: UIWindow) -> [String] {
        var all: [String] = []
        var controller = window.rootViewController
        while let next = controller?.presentedViewController { all += labels(next.view); controller = next }
        return all + labels(window)
    }

    private func trace(_ text: String, _ directory: URL) {
        let url = directory.appendingPathComponent("trace.txt")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (old + text + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func testWriteTheVacuumStills() async throws {
        guard let path = ProcessInfo.processInfo.environment["VAC_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        let out = directory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let inputs = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("in"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let size = CGSize(width: 466, height: 678)
        var ax: [String: [String]] = [:]

        for input in inputs {
            let name = input.deletingPathExtension().lastPathComponent
            for appearance in [UIUserInterfaceStyle.dark, .light] where appearance == .dark || name == "stub" {
                let label = appearance == .dark ? name : name + "-light"
                var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: directory.appendingPathComponent("publication.json")))
                // The Vacuums page is the page the renderer opens first.
                let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
                let index = try XCTUnwrap(pages.firstIndex { $0["id"]?.string == "page-vacuums" })
                json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[index]["components"]))
                json = try ServerUIRendererFixture.changing(json, path: "/document/pages/\(index)/components", to: XCTUnwrap(pages[0]["components"]))
                trace("before publication", out)
                let publication = try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
                let states = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: input))
                let store = EntityStore()
                var entities: [EntityState] = []
                if case .object(let table)? = states["entities"] {
                    for (id, value) in table {
                        var attributes: [String: JSONValue] = [:]
                        if case .object(let found)? = value["attributes"] { attributes = found }
                        entities.append(EntityState(entityId: id, state: value["state"]?.string ?? "unknown", attributes: attributes))
                    }
                }
                store.replaceAll(entities)
                trace("before host", out)
                let host: UKServerUIRenderer
                do {
                    host = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: HostedCaller()),
                                                  backdrop: ServerUIRendererFixture.backdrop(), vacuums: .init(services: Self.services))
                } catch {
                    trace("host error \(type(of: error)) \(String(reflecting: error))", out)
                    throw error
                }
                trace("before window", out)
                let window = HostedPage.show(host, size: HostedPage.inScene(size))
                window.overrideUserInterfaceStyle = appearance
                defer { HostedPage.hideTracked(); window.isHidden = true }
                await HostedPage.pump(passes: 60)
                for tile in HostedPage.descendants(of: window).compactMap({ $0 as? UKGlassTileView }) {
                    let frame = tile.convert(tile.bounds, to: nil)
                    trace("\(label) tile \(tile.model.title) frame=\(frame) minWidth=\(tile.gridMinimumWidth) fits=\(tile.gridHeight(forWidth: frame.width)) "
                        + "actions=\(tile.model.actions.count) kind=\(tile.model.kind) family=\(String(describing: tile.model.family)) "
                        + "active=\(tile.model.isActive) warn=\(tile.model.isWarning) fill=\(String(describing: tile.model.fillRGB))", out)
                }
                // Probe: does a fresh measurement of the grids change a tile's frame?
                for grid in HostedPage.descendants(of: window).compactMap({ $0 as? UKDynamicGridView }) {
                    let heights = grid.subviews.map { Int($0.frame.height) }
                    grid.invalidateMeasure(); grid.setNeedsLayout(); window.layoutIfNeeded()
                    trace("\(label) grid heights \(heights) -> \(grid.subviews.map { Int($0.frame.height) }) cfg=\(grid.configuration)", out)
                }
                trace("before page still", out)
                try still(window, to: out.appendingPathComponent("\(label)-page.png"))
                ax["\(label)-page"] = spoken(window)

                // The same entry point a tap uses: the card's own action.
                trace("before root", out)
                let root = try ServerUIRendererFixture.root(host, "tab-home")
                let card = try XCTUnwrap(root.nodes["device-node-bd3d50a4f8c7c30f"]?.view, "the Main Floor card")
                let tile = try XCTUnwrap(HostedPage.descendants(of: card).first { $0 is UKGlassTileView } ?? (card as? UKGlassTileView))
                trace("before tap", out)
                _ = tile.perform(NSSelectorFromString("tapped"))
                HostedPage.settlePresentations(of: host)
                await HostedPage.pump(passes: 80)
                XCTAssertNotNil(host.presentedViewController ?? window.rootViewController?.presentedViewController, "\(label): the sheet opened")
                trace("before sheet still", out)
                try still(window, to: out.appendingPathComponent("\(label)-sheet.png"))
                ax["\(label)-sheet"] = spoken(window)
            }
        }
        try JSONEncoder().encode(ax).write(to: out.appendingPathComponent("ax.json"))
    }
}
