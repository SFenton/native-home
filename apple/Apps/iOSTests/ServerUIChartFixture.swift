import Accessibility
@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Fixture

/// A page that holds one `chart` or `linear-gauge` of the shared corpus (`chart-*`, `linear-gauge-*`), with the records flow's collection driven by hand.
///
/// The corpus case's third page's components stand on the first page (or in the document's sheet, which follows the system appearance), so what the
/// Studio previews is what these draw.
@MainActor
struct ServerUIChartFixture {
    let host: UKServerUIRenderer
    let window: UIWindow
    let page: UKServerUIPage
    let store: EntityStore
    let collection: ServerUIRowCollection
    let caller: HostedCaller

    /// `count` records of a flow: a label, a level and a position.
    static func records(_ count: Int, level: (Int) -> Double = { 10 + Double($0 * 10) }) -> [JSONValue] {
        (0..<count).map { .object(["label": .string("H\($0)"), "level": .number(level($0)), "position": .number(Double($0))]) }
    }

    /// Sets `path` under `section` (the props, by default) of the first component to `value`; `.null` removes it.
    static func setting(_ path: [String], to value: JSONValue, in components: [JSONValue], under section: String = "props") -> [JSONValue] {
        func put(_ node: JSONValue, _ path: ArraySlice<String>) -> JSONValue {
            guard case .object(var object) = node, let key = path.first else { return value }
            if path.count == 1, case .null = value { object[key] = nil } else { object[key] = put(object[key] ?? .object([:]), path.dropFirst()) }
            return .object(object)
        }
        guard let first = components.first else { return components }
        return [put(first, [section] + path[...])] + components.dropFirst()
    }

    static func show(_ file: String, width: CGFloat, height: CGFloat = 1180, dark: Bool = false, entities: [EntityState] = [],
                     records: [JSONValue]? = nil, phase: ServerUIRowCollection.Phase = .ready, category: UIContentSizeCategory? = nil,
                     reduceMotion: Bool? = nil, inSheet: Bool = false, dropping capability: String? = nil, adding added: [String] = [], removing removed: [String] = [], edit: ([JSONValue]) -> [JSONValue] = { $0 }) throws -> Self {
        UKMotion.reduceMotionOverride = reduceMotion
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/\(file).json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        let components = edit(try XCTUnwrap(pages[2]["components"]?.array))
        json = try ServerUIRendererFixture.changing(json, path: inSheet ? "/document/modals/0/components" : "/document/pages/0/components", to: .array(components))
        // What stood on the first page must not repeat the ids that moved.
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: inSheet ? .array([]) : XCTUnwrap(pages[0]["components"]))
        if let capability, let held = json["capabilities"]?.array {
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(held.filter { $0.string != capability }))
        }
        if !added.isEmpty || !removed.isEmpty, let held = json["capabilities"]?.array?.compactMap(\.string) {
            // The manifest is exactly what the document needs, sorted: a test that changes what is drawn changes it to match.
            let manifest = Set(held).union(added).subtracting(removed).sorted().map(JSONValue.string)
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(manifest))
        }
        let publication = try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
        let store = EntityStore()
        store.replaceAll(entities)
        let collection = ServerUIRowCollection()
        if let records { try collection.apply(records: records, phase: phase) }
        let caller = HostedCaller()
        let renderer = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: caller),
                                              backdrop: ServerUIRendererFixture.backdrop(), collections: ["records-flow": collection])
        let window = HostedPage.show(renderer, size: HostedPage.inScene(CGSize(width: width, height: height)))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        if let category { window.traitOverrides.preferredContentSizeCategory = category }
        HostedPage.wait(0.2)
        var page = try ServerUIRendererFixture.root(renderer)
        if inSheet {
            renderer.activate(.present(modalId: "modal-swatch", arguments: .init(), ifPresented: .reject), from: page)
            HostedPage.wait(0.6)
            page = try XCTUnwrap(renderer.modal?.topViewController as? UKServerUIPage, "the sheet's page")
            // A sheet with `appearance: system` takes the system's setting, which differs by simulator (the Duo's is dark): set it on the sheet.
            if !dark {
                renderer.modal?.overrideUserInterfaceStyle = .light
                page.overrideUserInterfaceStyle = .light
                page.view.overrideUserInterfaceStyle = .light
            }
        }
        page.view.layoutIfNeeded()
        return Self(host: renderer, window: window, page: page, store: store, collection: collection, caller: caller)
    }

    func settle() {
        HostedPage.wait(0.2)
        page.view.layoutIfNeeded()
        HostedPage.layoutTracked()
    }

    func chart(_ id: String = "c") throws -> UKChartView { try XCTUnwrap(page.nodes[id]?.view as? UKChartView, "no chart named \(id)") }
    func gauge(_ id: String = "g") throws -> UKLinearGaugeView { try XCTUnwrap(page.nodes[id]?.view as? UKLinearGaugeView, "no gauge named \(id)") }

    static func all<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, in: $0) }
    }

    /// The elements of a path: its move-to and close-subpath counts.
    static func counts(of path: CGPath?) -> (moves: Int, closes: Int, boundary: CGRect) {
        var moves = 0, closes = 0
        path?.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint: moves += 1
            case .closeSubpath: closes += 1
            default: break
            }
        }
        return (moves, closes, path?.boundingBoxOfPath ?? .null)
    }

    // MARK: Contrast

    /// The WCAG relative luminance of an opaque sRGB colour.
    private static func luminance(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGFloat {
        func channel(_ value: CGFloat) -> CGFloat { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// The contrast ratio of `ink` (its alpha laid over `ground`) against `ground`, both resolved in `traits`.
    static func contrast(_ ink: UIColor, over ground: UIColor, in traits: UITraitCollection) -> CGFloat {
        var (gr, gg, gb, ga) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var (ir, ig, ib, ia) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        ground.resolvedColor(with: traits).getRed(&gr, green: &gg, blue: &gb, alpha: &ga)
        ink.resolvedColor(with: traits).getRed(&ir, green: &ig, blue: &ib, alpha: &ia)
        let blended = luminance(ir * ia + gr * (1 - ia), ig * ia + gg * (1 - ia), ib * ia + gb * (1 - ia))
        let base = luminance(gr, gg, gb)
        return (max(blended, base) + 0.05) / (min(blended, base) + 0.05)
    }
}
