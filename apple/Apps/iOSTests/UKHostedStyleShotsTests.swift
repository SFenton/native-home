import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Stills of the style parts for the evidence set: the header stack at the default and the largest accessibility size, the ticker, symbols by
/// state, the rgba ink and the choice icons. Writes `$WGSTYLE_DIR/<case>-<light|dark>.png`; does nothing without the directory.
@MainActor
final class UKHostedStyleShotsTests: XCTestCase {
    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func publication(_ file: String) throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/\(file).json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    private func still(_ file: String, name: String, to out: URL, dark: Bool, large: Bool = false, height: CGFloat = 260,
                       entities: [EntityState] = []) throws {
        let store = EntityStore()
        store.replaceAll(entities)
        let host = try UKServerUIRenderer(publication: publication(file), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: 800, height: height)))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        if large { window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge }
        HostedPage.wait(0.5)
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        window.isHidden = true
    }

    func testWriteStills() throws {
        guard let path = ProcessInfo.processInfo.environment["WGSTYLE_DIR"] else { return }
        let out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let rainy = EntityState(entityId: "weather.demo_home", state: "rainy", attributes: ["temperature": .number(72), "wind_bearing": .number(45)])
        for dark in [false, true] {
            try still("stack-collapse-both-with-regrouping", name: "header-default", to: out, dark: dark)
            try still("stack-collapse-both-with-regrouping", name: "header-accessibility", to: out, dark: dark, large: true, height: 520)
            try still("text-style-overflow-ticker", name: "ticker", to: out, dark: dark, height: 160)
            try still("symbol-part-by-state", name: "symbol-rainy", to: out, dark: dark, height: 160, entities: [rainy])
            try still("symbol-part-rotate-by-value", name: "symbol-turned", to: out, dark: dark, height: 160, entities: [rainy])
            try still("text-style-ink-rgba", name: "ink-rgba", to: out, dark: dark, height: 160)
            try still("text-style-ink-pair-of-rgba", name: "ink-pair", to: out, dark: dark, height: 160)
            try still("choice-icons-symbols-and-hints", name: "choice-icons", to: out, dark: dark, height: 200)
            try still("stack-surface-module", name: "stack-module", to: out, dark: dark, height: 160)
        }
    }
}
