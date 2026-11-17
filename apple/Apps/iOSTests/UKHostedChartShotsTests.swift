import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Stills of the chart and the linear gauge for the evidence set: on the page (always dark) and in a light sheet. Writes
/// `$WGCHART_DIR/<family>-<case>-<dark|light-sheet>.png`; does nothing without the directory.
@MainActor
final class UKHostedChartShotsTests: XCTestCase {
    typealias F = ServerUIChartFixture

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    /// The device family, which the run names (`WGCHART_FAMILY`; the Duo's simulator is a phone by idiom and by screen); a tablet or a phone without it.
    private var family: String {
        if let named = ProcessInfo.processInfo.environment["WGCHART_FAMILY"] { return named }
        if UIDevice.current.userInterfaceIdiom == .pad { return "ipad" }
        return UIScreen.main.bounds.width >= 600 ? "duo" : "iphone"
    }

    private func still(_ file: String, name: String, to out: URL, inSheet: Bool, plain: Bool = false, category: UIContentSizeCategory? = nil,
                       edit: (([JSONValue]) -> [JSONValue])? = nil) throws {
        let width: CGFloat = family == "iphone" ? 390 : (family == "duo" ? 669 : 820)
        let shown = try F.show(file, width: width, height: 420, dark: !inSheet, category: category, inSheet: inSheet, dropping: plain ? "sh.text-style@1" : nil,
                                  edit: edit ?? (plain ? Self.plainInks : { $0 }))
        shown.settle()
        HostedPage.wait(0.5)
        try write(shown.window, name: name, to: out, inSheet: inSheet)
        shown.window.isHidden = true
    }

    private func write(_ window: UIWindow, name: String, to out: URL, inSheet: Bool) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("\(family)-\(name)-\(inSheet ? "light-sheet" : "dark").png"))
    }

    /// The span gauge with the marker the weather rail draws: white, with a 1.5 pt border of black at 45%.
    private static func borderedMarker(_ components: [JSONValue]) -> [JSONValue] {
        let ink = JSONValue.object(["type": .string("rgba"), "red": .number(0), "green": .number(0), "blue": .number(0), "alpha": .number(0.45)])
        return F.setting(["marker", "border"], to: .object(["ink": ink, "width": .number(1.5)]), in: components)
    }

    /// The bar chart at the unfolded Duo's 669 pt, drawn on its own (a window cannot be that wide on every simulator): the plot fills the width.
    private func unfoldedDuoStill(to out: URL) throws {
        guard family == "duo" else { return }
        let source = try F.show("chart-bar-axis", width: 669, height: 420, dark: true)
        let content = try XCTUnwrap(try source.chart().content)
        let speech = try XCTUnwrap(try source.chart().speech)
        source.window.isHidden = true
        let view = UKChartView()
        view.apply(content, speech: speech)
        let container = UIView()
        container.backgroundColor = UIColor(red: 17 / 255, green: 23 / 255, blue: 35 / 255, alpha: 1)
        container.addSubview(view)
        let height = view.sizeThatFits(.init(width: 669, height: 400)).height
        view.frame = .init(x: 0, y: 12, width: 669, height: height)
        container.frame = .init(x: 0, y: 0, width: 669, height: height + 24)
        let controller = UIViewController()
        controller.view = container
        let window = UIWindow(frame: container.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.isHidden = false
        for _ in 0..<2 { container.setNeedsLayout(); container.layoutIfNeeded(); view.layoutIfNeeded() }
        XCTAssertEqual(view.plotFrame.maxX, view.bounds.width, accuracy: 0.5, "the plot reaches the trailing edge")
        // A free window draws blank through drawHierarchy, so the layer tree is rendered (as the repeat's unfolded still is).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(bounds: container.bounds, format: format)
        _ = renderer.image { container.layer.render(in: $0.cgContext) }
        HostedPage.wait(0.1)
        let image = renderer.image { container.layer.render(in: $0.cgContext) }
        try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("duo-unfolded-chart-bar-dark.png"))
        window.isHidden = true
    }

    /// The chart without the document's own white inks, so the sheet draws the default ones.
    private static func plainInks(_ components: [JSONValue]) -> [JSONValue] {
        F.setting(["axis", "labelInk"], to: .null, in: F.setting(["axis", "gridInk"], to: .null, in: components))
    }

    func testWriteStills() throws {
        guard let path = ProcessInfo.processInfo.environment["WGCHART_DIR"] else { return }
        let out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for inSheet in [false, true] {
            try still("chart-bar-axis", name: "chart-bar", to: out, inSheet: inSheet, plain: inSheet)
            try still("chart-line-look", name: "chart-line", to: out, inSheet: inSheet)
            try still("linear-gauge-ink-pairs", name: "gauge", to: out, inSheet: inSheet)
            try still("chart-ink-pair", name: "chart-ink-pair", to: out, inSheet: inSheet)
            try still("linear-gauge-span", name: "gauge-span-border", to: out, inSheet: inSheet, edit: Self.borderedMarker)
        }
        try still("chart-bar-axis", name: "chart-bar-ax5", to: out, inSheet: false, category: .accessibilityExtraExtraExtraLarge)
        try unfoldedDuoStill(to: out)
    }
}
