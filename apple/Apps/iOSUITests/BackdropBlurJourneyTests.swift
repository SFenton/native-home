import XCTest

/// Settings → Appearance → Background Blur (`.agents/patterns/page-backdrop.md`, "Background Blur") on the Settings gallery
/// (`FENTON_GALLERY=settings` with `FENTON_BACKDROP_FIXTURE=1`: the shell's page chrome and a fixture house photo, no
/// sign-in): the slider is one named adjustable control that speaks its percentage, targets are 44 pt, Reset to Default
/// works, the page passes the accessibility audit with an AX5 relaunch, and the wallpaper keeps rendering, sharper or softer
/// to match the setting, after it changes. Runs on iPhone, the folded iPhone Duo and iPad.
@MainActor
final class BackdropBlurJourneyTests: JourneyTestCase {
    private static let sliderID = "settings.backdropBlur"
    private static let resetID = "settings.backdropBlur.reset"
    private static let step = 5

    /// - Parameter fixture: Draw the fixture house photo behind the page. The accessibility audits run without it: the
    ///   fixture is far brighter than the real photo (it exists so wallpaper can be told from the plain base), and the scrim
    ///   is tuned for the real one (`page-backdrop.md` R5).
    private func launch(arguments: [String] = [], blur: Int? = nil, fixture: Bool = true,
                        environment extra: [String: String] = [:]) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchArguments += arguments
        app.launchEnvironment["FENTON_GALLERY"] = "settings"
        app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        // The fixture and the saved blur are gallery settings (`FENTON_GALLERY_BACKDROP_*`; the gallery builds its backdrop store per
        // generation), so a reset applies them and the class keeps one resident app. AX5 (`arguments`) and the system settings
        // (`extra`) are launch signature: they launch their own app (`app-reuse.md`).
        app.launchEnvironment["FENTON_GALLERY_BACKDROP_FIXTURE"] = fixture ? "1" : "0"
        if let blur { app.launchEnvironment["FENTON_GALLERY_BACKDROP_BLUR"] = String(blur) }
        app.launchEnvironment.merge(extra) { _, new in new }
        let running = startApp(app)
        XCTAssertTrue(element("settings.list", in: running).appears(timeout: 30), "The Settings list did not appear")
        return running
    }

    private func slider(_ app: XCUIApplication) -> XCUIElement { element(Self.sliderID, in: app) }

    /// Scrolls until `target` can be tapped.
    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        let list = element("settings.list", in: app)
        for _ in 0..<12 where !target.isHittable { list.swipeUp(velocity: .slow) }
    }

    /// The slider's percentage from its spoken value ("50 percent").
    private func percent(of control: XCUIElement) -> Int? {
        (control.value as? String).flatMap { Int($0.split(separator: " ").first ?? "") }
    }

    /// Drags the thumb to a fraction of the track. The row is one adjustable element (`PercentSliderRow`), which XCUITest
    /// calls `Other`, so `adjust(toNormalizedSliderPosition:)` is not available: the drag is a real touch on the slider
    /// under it. The thumb sits in the lower half of the row; a few heights are tried until the value moves.
    private func setSlider(_ app: XCUIApplication, to fraction: CGFloat) {
        let control = slider(app)
        reveal(control, in: app)
        XCTAssertTrue(control.exists)
        let wanted = Int((fraction * 100).rounded())
        let thumbRadius: CGFloat = 14
        func x(_ percent: Int) -> CGFloat {
            control.frame.minX + thumbRadius + CGFloat(percent) / 100 * (control.frame.width - 2 * thumbRadius)
        }
        let window = app.windows.firstMatch
        for heightFraction in [0.72, 0.82, 0.6, 0.9] {
            guard let current = percent(of: control), abs(current - wanted) > 3 else { return }
            let y = control.frame.minY + control.frame.height * heightFraction
            let origin = window.frame.origin
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x(current) - origin.x, dy: y - origin.y))
            // Past either end the thumb stops at the end.
            let targetX = wanted == 0 ? control.frame.minX - 30 : (wanted == 100 ? control.frame.maxX + 30 : x(wanted))
            let end = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: targetX - origin.x, dy: y - origin.y))
            start.press(forDuration: 0.2, thenDragTo: end)
            if percent(of: control) == current {
                // The drag did not take (a thumb at the very end): a tap on the track jumps there.
                let tapX = min(max(x(wanted), control.frame.minX + thumbRadius), control.frame.maxX - thumbRadius)
                window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tapX - origin.x, dy: y - origin.y)).tap()
            }
        }
    }

    // MARK: - Wallpaper sampling

    /// How sharp the wallpaper is along the page's leading margin: the largest brightness change over 4 pt between
    /// samples down the margin, where the fixture's cream bands cross. A sharp photo steps through each band edge; a
    /// blurred one eases through it.
    private func edgeSteepness(_ app: XCUIApplication) -> (steepest: Double, lowest: Double, highest: Double)? {
        guard let capture = RenderedContrast.Capture.screen() else { return nil }
        let window = app.windows.firstMatch.frame
        let x = Int(4 * capture.scale)
        guard x < capture.width else { return nil }
        let samples: [Double] = stride(from: window.minY + window.height * 0.25, to: window.minY + window.height * 0.75, by: 2).compactMap { y in
            let row = Int(y * capture.scale)
            guard row >= 0, row < capture.height else { return nil }
            let i = (row * capture.width + x) * 4
            return Double(capture.pixels[i]) + Double(capture.pixels[i + 1]) + Double(capture.pixels[i + 2])
        }
        guard samples.count > 4 else { return nil }
        let steps = zip(samples, samples.dropFirst(2)).map { abs($0 - $1) }
        return (steps.max() ?? 0, samples.min() ?? 0, samples.max() ?? 0)
    }

    /// The same, after the wallpaper has settled on the setting: polls until two reads agree.
    private func settledSteepness(_ app: XCUIApplication) -> (steepest: Double, lowest: Double, highest: Double) {
        var last = edgeSteepness(app)
        for _ in 0..<20 {
            settleScreen()
            let next = edgeSteepness(app)
            if let last, let next, abs(last.steepest - next.steepest) < 0.5 { return next }
            last = next
        }
        return last ?? (0, 0, 0)
    }

    /// With `FENTON_BLUR_SHOTS_DIR` set, also writes the screenshot there.
    private func saveShot(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["FENTON_BLUR_SHOTS_DIR"] else { return }
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(layout).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    // MARK: - Journeys

    /// One adjustable control named for VoiceOver with its value spoken as a percentage; Reset is a 44 pt button, disabled
    /// at the default.
    func testSliderIsOneNamedControlWithPercentValueAndTargets() {
        let app = launch()
        let control = slider(app)
        reveal(control, in: app)
        XCTAssertTrue(control.appears(timeout: 5), "No Background Blur slider")
        XCTAssertEqual(control.label, "Background Blur")
        XCTAssertEqual(control.value as? String, "50 percent")
        XCTAssertGreaterThanOrEqual(control.frame.height, 43)
        XCTAssertGreaterThanOrEqual(control.frame.width, 43)
        XCTAssertTrue(app.staticTexts["Appearance"].exists, "No Appearance header")
        let reset = app.buttons[Self.resetID]
        reveal(reset, in: app)
        XCTAssertTrue(reset.exists)
        assertTarget(reset)
        XCTAssertEqual(reset.label, "Reset to Default")
        XCTAssertFalse(reset.isEnabled, "Reset is enabled at the default")
        keepScreenshot(app, "backdrop-blur-row-\(layout)")
        saveShot("settings-blur-50")
    }

    /// Moving the slider changes its spoken value and enables Reset; Reset puts it back to 50 percent.
    func testSlidingChangesTheValueAndResetRestoresTheDefault() {
        let app = launch()
        setSlider(app, to: 0.8)
        let control = slider(app)
        let moved = percent(of: control) ?? 50
        XCTAssertTrue((70...90).contains(moved), "Dragging to 80% left the slider at \(String(describing: control.value))")
        XCTAssertEqual(moved % BackdropBlurJourneyTests.step, 0, "The slider moves in steps of 5")
        let reset = app.buttons[Self.resetID]
        reveal(reset, in: app)
        XCTAssertTrue(reset.isEnabled, "Reset stays disabled off the default")
        reset.tap()
        let restored = expectation(for: NSPredicate(format: "value == '50 percent'"), evaluatedWith: control)
        wait(for: [restored], timeout: 5)
        XCTAssertFalse(reset.isEnabled)
    }

    /// The wallpaper stays on screen through the setting's whole range, and its edges follow the setting: sharp at 0,
    /// softer at the default, softest at 100. Each setting is a launch at that saved value (`FENTON_BACKDROP_BLUR`).
    func testWallpaperEdgesFollowTheSetting() {
        var measured: [Int: (steepest: Double, lowest: Double, highest: Double)] = [:]
        for blur in [50, 0, 100] {
            let app = launch(blur: blur)
            measured[blur] = settledSteepness(app)
            saveShot("wallpaper-blur-\(blur)")
        }
        guard let normal = measured[50], let sharp = measured[0], let soft = measured[100] else { return XCTFail("no measurements") }
        // The fixture photo is far brighter than the plain base under the densest scrim.
        for (blur, edge) in measured { XCTAssertGreaterThan(edge.highest, 120, "No wallpaper at \(blur)%: brightest sample \(edge.highest)") }
        XCTAssertGreaterThan(sharp.steepest, normal.steepest * 3, "0% is not much sharper than the default: \(sharp.steepest) vs \(normal.steepest)")
        XCTAssertGreaterThan(normal.steepest, soft.steepest * 1.3, "The default is not softer than 0% and sharper than 100%: \(normal.steepest) vs \(soft.steepest)")
    }

    /// Dragging the slider to 0 re-renders the wallpaper sharp, live, with the photo on screen throughout.
    func testDraggingTheSliderSharpensTheWallpaper() {
        let app = launch()
        let normal = settledSteepness(app)
        XCTAssertGreaterThan(normal.highest, 120, "No wallpaper at the default: brightest sample \(normal.highest)")
        setSlider(app, to: 0)
        XCTAssertEqual(slider(app).value as? String, "0 percent")
        let sharp = settledSteepness(app)
        saveShot("wallpaper-after-drag-to-0")
        XCTAssertGreaterThan(sharp.highest, 120, "No wallpaper at 0%")
        XCTAssertGreaterThan(sharp.steepest, normal.steepest * 3, "Dragging to 0% did not sharpen it: \(sharp.steepest) vs \(normal.steepest)")
    }

    /// A relaunch at a saved setting draws the wallpaper at it from the start.
    func testWallpaperStartsAtTheSavedSetting() {
        let app = launch(blur: 0)
        let sharp = settledSteepness(app)
        XCTAssertGreaterThan(sharp.highest, 120, "No wallpaper")
        let value = slider(app)
        reveal(value, in: app)
        XCTAssertEqual(value.value as? String, "0 percent")
    }

    /// The Settings page with the slider passes the accessibility audit, with an AX5 relaunch (name/role/value, order,
    /// targets and text scaling).
    func testSettingsWithSliderPassesAccessibilityAudit() throws {
        let app = launch(fixture: false)
        settleScreen()
        try FentonHomeApp.audit(app, ax5Page: {
            let large = self.launch(arguments: FentonHomeApp.ax5, fixture: false)
            settleScreen()
            return large
        })
    }

    /// At AX5 the slider's row still reads whole and keeps 44 pt targets.
    func testSliderRowKeepsTargetsAtAX5() {
        let app = launch(arguments: FentonHomeApp.ax5)
        let control = slider(app)
        reveal(control, in: app)
        XCTAssertTrue(control.exists)
        XCTAssertEqual(control.label, "Background Blur")
        XCTAssertGreaterThanOrEqual(control.frame.height, 43)
        let reset = app.buttons[Self.resetID]
        reveal(reset, in: app)
        assertTarget(reset)
        keepScreenshot(app, "backdrop-blur-row-ax5-\(layout)")
    }

    /// Reduce Transparency draws the plain background and says why in the section footer; the slider still works.
    func testReduceTransparencyExplainsThePlainBackground() {
        let app = launch(environment: FentonHomeApp.SystemSetting.environment([.reduceTransparency]))
        let control = slider(app)
        reveal(control, in: app)
        XCTAssertTrue(control.exists)
        let footer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Reduce Transparency is on'")).firstMatch
        XCTAssertTrue(footer.appears(timeout: 5), "No Reduce Transparency footer")
    }
}
