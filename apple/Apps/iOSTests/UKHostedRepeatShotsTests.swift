import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Stills of the repeat for the evidence set: a forecast-style horizontal paged repeat and a vertical list. The page pins itself dark, so the stills are dark. Writes
/// `$WGFLOW_DIR/<case>-<light|dark>.png`; does nothing without the directory.
@MainActor
final class UKHostedRepeatShotsTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func still(_ file: String, name: String, width: CGFloat = 800, to out: URL, dark: Bool, height: CGFloat, props: [String: JSONValue] = [:],
                       records: [JSONValue]?, phase: ServerUIRowCollection.Phase = .ready) throws {
        let shown = try ServerUIRepeatFixture.show(file, width: width, height: height, dark: dark, props: props, phase: phase, records: records)
        shown.settle()
        HostedPage.wait(0.4)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let window = shown.window
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        window.isHidden = true
    }

    /// The repeat at the unfolded Duo's 669 pt (regular width: Previous and Next beside the dots), drawn on its own on the page's ground colour.
    private func unfoldedDuo(to out: URL) throws {
        let (container, _, window) = ServerUIRepeatFixture.standalone(width: 669)
        defer { window.isHidden = true }
        try XCTUnwrap(ServerUIRepeatFixture.image(of: container).pngData()).write(to: out.appendingPathComponent("forecast-paged-unfolded-duo-dark.png"))
    }

    func testWriteStills() throws {
        guard let path = ProcessInfo.processInfo.environment["WGFLOW_DIR"] else { return }
        let out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try unfoldedDuo(to: out)
        for dark in [true] {
            try still("repeat-paging-full", name: "forecast-paged", to: out, dark: dark, height: 240, records: ServerUIRepeatFixture.records(24))
            try still("repeat-vertical", name: "list-vertical", to: out, dark: dark, height: 420, records: ServerUIRepeatFixture.records(6))
            try still("repeat-placeholder", name: "list-placeholders", to: out, dark: dark, height: 420,
                      props: ["axis": .string("vertical")], records: nil, phase: .loading)
        }
    }
}
