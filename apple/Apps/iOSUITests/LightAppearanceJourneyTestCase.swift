import XCTest

/// The base of the light-appearance sheet journeys: sheets follow the system appearance while pages stay dark
/// (`.agents/design/direction-g.md`, Layers: Sheets; plan decision 6). Each area class launches with `FENTON_APPEARANCE=light`
/// (the real system path has its own class), checks by pixel that the sheet is light and the page behind stays dark, and runs the
/// accessibility audit (contrast, Dynamic Type at AX5, targets) on the sheet in light, on iPhone, iPhone Duo (folded) and iPad.
/// The dark passes of the same sheets are the feature journeys; `tools/ios_uitest.sh --appearance light` runs those in light too.
/// The old single `LightSheetsJourneyTests` class was split by sheet (`contracts/test-map.json`) so a change to one sheet runs
/// only that sheet's light audit; nothing here is specific to one sheet.
@MainActor
class LightAppearanceJourneyTestCase: JourneyTestCase {
    /// A gallery page with the sheets pinned to `appearance` (nil leaves it to the simulator and the runner). With app reuse on
    /// it resets the resident app instead of launching (``AppReuse``; the pinned appearance and AX5 are part of the launch
    /// signature, so each gets its own process).
    /// - Parameter fresh: Launches the process even with reuse on, for a test that is about the process or the simulator's
    ///   own appearance (the system-appearance class).
    func gallery(_ page: String, environment: [String: String] = [:], arguments: [String] = [],
                 appearance: String? = "light", fresh: Bool = false) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = page
        if let appearance { app.launchEnvironment["FENTON_APPEARANCE"] = appearance }
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += arguments
        if fresh {
            app.launch()
            return app
        }
        return startApp(app)
    }

    /// Waits for `id` to be on screen and hittable, then lets the presentation settle (mid-animation frames fail
    /// contrast and clipping).
    func waitReady(_ id: String, in app: XCUIApplication, what: String) {
        let ready = element(id, in: app)
        XCTAssertTrue(ready.appears(timeout: 30), "\(what) did not open")
        XCTAssertTrue(ready.wait(for: \.isHittable, toEqual: true, timeout: 10), "\(what) is still presenting")
        settleScreen()
    }

    /// Luminance samples down the sheet's left gutter, 3 pt inside its edge: the sheet's own ground, which no cell,
    /// title or control reaches (they are inset 16 pt). The sheet's left edge is its navigation bar's.
    func sheetSamples(_ app: XCUIApplication) -> [Double] {
        guard let capture = RenderedContrast.Capture.screen() else { return [] }
        let bar = app.navigationBars.containing(NSPredicate(format: "label == 'Close'")).firstMatch
        let top = bar.exists ? bar.frame : app.buttons["Close"].firstMatch.frame
        // The folded Duo draws Close on a side rail and insets its sheet about 8 pt from the window's edge, with the
        // content (and its tiles) starting 23 pt in: the navigation bar's own left edge is inside Climate's room tiles
        // there, so the column 14 pt in from the window is the sheet's ground (2026-10-16).
        let window = app.windows.firstMatch.frame
        let left = FentonHomeApp.family == .iPhoneDuo ? window.minX + 11
            : bar.exists ? top.minX : max(0, top.maxX - 400)
        return stride(from: top.maxY + 40, to: top.maxY + 400, by: 45).compactMap {
            RenderedContrast.luminance(at: CGPoint(x: left + 3, y: $0), in: capture)
        }
    }

    func assertSheet(_ app: XCUIApplication, isLight: Bool, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        let samples = sheetSamples(app)
        XCTAssertFalse(samples.isEmpty, "No pixels sampled \(message)", file: file, line: line)
        let matching = samples.filter { isLight ? $0 > 0.7 : $0 < 0.2 }
        XCTAssertGreaterThanOrEqual(matching.count * 2, samples.count,
                                    "\(message) sheet should be \(isLight ? "light" : "dark"); luminance \(samples)",
                                    file: file, line: line)
    }

    /// The wallpaper at the window's left edge, where no page content sits: dark under G's scrim.
    func assertPageIsDark(_ app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let capture = RenderedContrast.Capture.screen() else { return XCTFail("No capture", file: file, line: line) }
        let window = app.windows.firstMatch.frame
        let samples = [0.35, 0.5, 0.65].compactMap {
            RenderedContrast.luminance(at: CGPoint(x: 3, y: window.height * $0), in: capture)
        }
        XCTAssertTrue(samples.allSatisfy { $0 < 0.3 }, "\(message): the page behind should stay dark; luminance \(samples)",
                      file: file, line: line)
    }

    /// Opens the sheet through `launch` (called again with AX5 for the Dynamic Type check), asserts it is light, keeps
    /// a screenshot and audits it.
    func auditLight(_ name: String, launch: @escaping ([String]) -> XCUIApplication) throws {
        let app = launch([])
        assertSheet(app, isLight: true, name)
        keepScreenshot(app, "light-\(name)-\(layout)")
        try FentonHomeApp.audit(app) { launch(FentonHomeApp.ax5) }
    }
}
