import XCTest

/// A fitted sheet is exactly as tall as its content, its header and the system's home-indicator area: no empty band under the last
/// control (owner, 2026-10-28, `proposals/sheet-bottom-gap`, option B; `.agents/patterns/modal-sheet.md`, Height).
///
/// UIKit measures a custom detent up from the bottom safe area and adds that area itself (34 pt on an iPhone and the folded Duo, 20 pt on
/// an iPad), so a detent that also counted it left that much empty ground under the content: the page's scroller read 34 pt more
/// viewport than content. Each test attaches the sheet-fit probe (`FENTON_SHEETFIT_PROBE=1`: detent, page area, insets, chrome, moves).
/// `TEST_RUNNER_FENTON_SHEETFIT_LEGACY=1` draws the sheets as they were before (the detent counts the safe area) to measure the same
/// build both ways; those runs are expected to fail the assertions below.
@MainActor
final class SheetBottomGapJourneyTests: JourneyTestCase {
    /// What the empty band measured before (89 pt on an iPhone 17 Pro, 92 on the folded Duo, 63 on an iPad) less the system's bottom
    /// safe area (34, 34, 20; an iPhone draws a sheet at 0.96): the controls end one page padding above the home-indicator area.
    private let maxGapUnderTheLastControl: CGFloat = 72

    private var probeEnvironment: [String: String] {
        var environment = ["FENTON_SHEETFIT_RESET": "1", "FENTON_SHEETFIT_PROBE": "1"]
        if ProcessInfo.processInfo.environment["FENTON_SHEETFIT_LEGACY"] == "1" { environment["FENTON_SHEETFIT_LEGACY"] = "1" }
        return environment
    }

    private func probe(_ app: XCUIApplication) -> String {
        // One snapshot (existence and value together); an absent probe is "no probe".
        guard let facts = try? app.descendants(matching: .any)["sheet.fit.probe"].firstMatch.snapshot() else { return "no probe" }
        return facts.value as? String ?? "no probe"
    }

    private func attach(_ name: String, _ text: String) {
        let note = XCTAttachment(string: text)
        note.name = name
        note.lifetime = .keepAlways
        add(note)
    }

    /// `key=value` from the probe's `root=[content=... viewport=...]` reading.
    private func reading(_ key: String, in probe: String) -> CGFloat? {
        probe.components(separatedBy: "root=[").dropFirst().first?.components(separatedBy: "\(key)=").dropFirst().first
            .flatMap { Double($0.prefix { $0.isNumber || $0 == "." }) }.map { CGFloat($0) }
    }

    /// Launches (or resets) the camera viewer gallery with the viewer open on `stream`. The stream is `FENTON_GALLERY_CAMERA_VIEWER_OPEN`
    /// (the `-cameraViewerOpen` argument's gallery-setting form), so each test is a reset of the class's resident app
    /// (`app-reuse.md`). `FENTON_SHEETFIT_RESET=1` stays in the launch signature, and a reset under it also clears the remembered
    /// sheet heights (`GalleryReset`), so every test still sees a sheet's first presentation as a fresh launch did.
    private func openCamera(_ stream: String) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "camera-viewer"
        configured.launchEnvironment["FENTON_GALLERY_CAMERA_VIEWER_OPEN"] = stream
        configured.launchEnvironment.merge(probeEnvironment) { _, new in new }
        let app = startApp(configured)
        XCTAssertTrue(app.buttons["camera.control.snapshot"].appears(timeout: 20), "The viewer did not open")
        settleScreen() // The presentation, the settle delay and any correction.
        return app
    }

    /// The gap from the window's bottom edge to the lowest control, recorded with the probe; and the page's slack: how much more
    /// viewport than content the page's scroller has, which is the empty band itself.
    private func assertNoBandUnderTheControls(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let controls = app.switches["camera.control.record"].frame
        let gap = window.maxY - controls.maxY
        let probe = probe(app)
        attach("gap-\(name)", "\(name): window \(window) lastControl \(controls) gap=\(gap) probe \(probe)")
        keepScreenshot(app, "sheet-gap-\(name)-\(layout)")
        XCTAssertTrue(window.contains(controls), "\(name): the last control is not on screen: \(controls)", file: file, line: line)
        if FentonHomeApp.family == .iPhoneDuo {
            // Folded and beside a vertical hinge every sheet fills the height from the bottom (owner, 2026-10-31,
            // `DuoSheetPolicy.fillsHeight`), so a short viewer has ground under its controls by design; the controls still sit on screen.
            return
        }
        XCTAssertLessThan(gap, maxGapUnderTheLastControl, "\(name): empty ground under the controls: \(gap) pt", file: file, line: line)
        if let content = reading("content", in: probe), let viewport = reading("viewport", in: probe) {
            XCTAssertLessThan(viewport - content, 8, "\(name): the sheet holds \(viewport - content) pt more than its content (the safe area counted twice)", file: file, line: line)
        }
    }

    func testFrontDoorViewerHasNoBandUnderItsControls() {
        assertNoBandUnderTheControls(openCamera("front_door"), "front-door")
    }

    func testDrivewayViewerHasNoBandUnderItsControls() {
        assertNoBandUnderTheControls(openCamera("garage_camera"), "driveway")
    }

    /// Quick Links, a sheet that is not the camera viewer: the last tile ends one page padding above the home-indicator area.
    func testQuickLinksHasNoBandUnderItsTiles() {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "rooms"
        app.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        app.launchEnvironment["FENTON_GALLERY_QUICK_LINKS"] = "1"
        app.launchEnvironment.merge(probeEnvironment) { _, new in new }
        _ = startApp(app) // `FENTON_GALLERY_*` switches only: a reset of the class's resident app (see ``openCamera(_:)``)
        let last = app.descendants(matching: .any)["quickLinks.sprinklers"].firstMatch
        XCTAssertTrue(last.appears(timeout: 30), "Quick Links did not open")
        settleScreen()
        let window = app.windows.firstMatch.frame
        // Where the tiles outgrow the largest sheet (the folded Duo: Security System takes a row, owner 2026-11-01) the sheet scrolls;
        // the band is checked with the last tile scrolled into view.
        // Scroll until the last tile stops moving (the bottom), not merely until it is on screen: a tile that only just fits would
        // be measured while content still scrolls under it.
        var previousMaxY = CGFloat.nan
        var lastFrame = last.frame
        for _ in 0..<8 where lastFrame.maxY > window.maxY || previousMaxY.isFinite && lastFrame.maxY != previousMaxY {
            previousMaxY = lastFrame.maxY
            app.scrollViews.firstMatch.swipeUp()
            settleScreen()
            lastFrame = last.frame
        }
        let bar = app.navigationBars["Quick Links"].firstMatch.frame
        let gap = window.maxY - lastFrame.maxY
        attach("gap-quick-links", "quick-links: window \(window) bar \(bar) sheetVisible=\(window.maxY - bar.minY) lastTile \(lastFrame) gap=\(gap)")
        keepScreenshot(app, "sheet-gap-quick-links-\(layout)")
        XCTAssertTrue(window.contains(lastFrame), "The last tile is not on screen: \(lastFrame)")
        XCTAssertLessThan(gap, maxGapUnderTheLastControl, "Quick Links has empty ground under its tiles: \(gap) pt")
    }
}
