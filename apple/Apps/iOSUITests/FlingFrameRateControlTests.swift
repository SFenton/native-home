import XCTest

/// Control for the fling frame-rate question: under a real touch fling, what rate does the phone's display run, in Apple's own
/// Settings app and in S+H's Settings page? Each test flicks 12 times up and 12
/// times down with the same gesture as `FastScrollPerformanceTests.strongFlick`, after a 1 s head start (8 s with `--trace`, so
/// `xctrace` can attach). S+H's pages are measured by the app itself (`FlingFpsProbe` via `FrameMonitor`, read back by
/// ``printInAppStats(_:)``); only Apple's Settings control needs `tools/ios_flingfps.sh --trace`, which records an Animation Hitches
/// trace around the test (`.agents/testing/apple/performance.md`, Rounds 6 and 7).
///
/// Device only: skips on a simulator unless `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`.
@MainActor
final class FlingFrameRateControlTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Leaves the phone on the home screen, pass or fail (Apple's Settings or the app must not stay open on the owner's phone).
    override func tearDown() {
        #if !targetEnvironment(simulator)
        MainActor.assumeIsolated { XCUIDevice.shared.press(.home) }
        #endif
        super.tearDown()
    }

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Seconds to wait before the first flick: 8 when a trace must attach (the default), 1 with `TEST_RUNNER_FENTON_FLING_NOTRACE=1`
    /// (the in-app numbers need no recorder).
    private static var headStart: TimeInterval { environment["FENTON_FLING_NOTRACE"] == "1" ? 1 : 8 }

    private func requireDevice() throws {
        #if targetEnvironment(simulator)
        if Self.environment["FENTON_PERF_ON_SIMULATOR"] != "1" {
            throw XCTSkip("Frame rate is measured on a physical device. Set TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1 to run anyway.")
        }
        #endif
    }

    /// Logs the state that changes the display rate: Low Power Mode and thermal state.
    private func logDeviceState(suffix: String = "") {
        let thermal = ProcessInfo.processInfo.thermalState
        print("FLINGFPS\(suffix.isEmpty ? "" : "-" + suffix) lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled) thermalState=\(thermal.rawValue)")
    }

    /// The experiment switches a run forwards (`TEST_RUNNER_FENTON_PERF_DISABLE`, `TEST_RUNNER_FENTON_GALLERY_FLYOUT`, set by
    /// `tools/ios_flingfps.sh --disable ... --flyout`): the layers left out and the phone's flyout chrome for gallery pages.
    private func applyExperiment(_ app: XCUIApplication) {
        app.launchEnvironment["FENTON_FLINGFPS"] = "1"
        app.launchEnvironment["FENTON_TELEMETRY"] = "1"
        for key in ["FENTON_PERF_DISABLE", "FENTON_GALLERY_FLYOUT"] {
            if let value = Self.environment[key], !value.isEmpty { app.launchEnvironment[key] = value }
        }
    }

    private func strongFlick(_ element: XCUIElement, from: CGVector, to: CGVector) {
        element.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.01, thenDragTo: element.coordinate(withNormalizedOffset: to),
                   withVelocity: FastScrollPerformanceTests.strongFlickVelocity, thenHoldForDuration: 0)
    }

    /// Waits for a trace to attach, then 12 flicks up and 12 down with 2 s between direction changes.
    private func flingSequence(_ scroll: XCUIElement, app: XCUIApplication? = nil, headStart: TimeInterval = 8) {
        print("FLINGFPS begin")
        Thread.sleep(forTimeInterval: headStart)
        print("FLINGFPS flicks-up")
        for _ in 0..<12 { strongFlick(scroll, from: CGVector(dx: 0.5, dy: 0.8), to: CGVector(dx: 0.5, dy: 0.2)) }
        Thread.sleep(forTimeInterval: 2)
        print("FLINGFPS flicks-down")
        for _ in 0..<12 { strongFlick(scroll, from: CGVector(dx: 0.5, dy: 0.2), to: CGVector(dx: 0.5, dy: 0.8)) }
        Thread.sleep(forTimeInterval: 2)
        print("FLINGFPS end")
        if let app { printInAppStats(app) }
    }

    /// Prints the frame numbers the app collected itself (`FlingFpsProbe`, `FENTON_FLINGFPS=1`): one `FLINGFPS-STATS` line per page,
    /// then the device state at the end of the run. `tools/ios_flingfps.sh` collects these lines; no trace is needed.
    private func printInAppStats(_ app: XCUIApplication) {
        let probe = app.descendants(matching: .any)["diagnostics.flingfps"].firstMatch
        if probe.waitForExistence(timeout: 5) { print(probe.label) } else { print("FLINGFPS-STATS probe missing") }
        logDeviceState(suffix: "end")
    }

    /// Apple's Settings app: the control.
    func testFlingAppleSettings() throws {
        try requireDevice()
        logDeviceState()
        let app = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        app.launch()
        for label in ["General", "Privacy & Security"] {
            let row = app.cells.staticTexts[label].firstMatch
            if row.waitForExistence(timeout: 5) { row.tap(); break }
        }
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "No list in Apple's Settings")
        flingSequence(list)
    }

    /// S+H's Settings page from the gallery fixtures.
    func testFlingSettings() throws {
        try requireDevice()
        logDeviceState()
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "settings"
        app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        applyExperiment(app)
        app.launch()
        let scroll = app.descendants(matching: .any)["settings.list"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 30), "Settings did not open")
        flingSequence(scroll, app: app, headStart: Self.headStart)
    }

    /// S+H's Recipes grid from the gallery fixtures: is the rate Settings-specific or shared by long S+H pages?
    func testFlingRecipes() throws {
        try requireDevice()
        logDeviceState()
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "food"
        app.launchEnvironment["FENTON_GALLERY_ROUTE"] = "recipes"
        applyExperiment(app)
        app.launch()
        let scroll = app.descendants(matching: .any)["recipes.grid"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 30), "Recipes did not open")
        flingSequence(scroll, app: app, headStart: Self.headStart)
    }

    /// S+H's Settings page signed in to the live server. Skips without `TEST_RUNNER_FENTON_PERF_LIVE=1` and credentials.
    func testFlingLiveSettings() throws {
        try requireDevice()
        guard Self.environment["FENTON_PERF_LIVE"] == "1" else { throw XCTSkip("Set TEST_RUNNER_FENTON_PERF_LIVE=1 (with credentials).") }
        logDeviceState()
        var launch = ["FENTON_TELEMETRY": "1"]
        if let value = Self.environment["FENTON_PERF_DISABLE"], !value.isEmpty { launch["FENTON_PERF_DISABLE"] = value }
        let app = try FentonHomeApp.launchSignedIn(environment: launch)
        let flyout = app.buttons["nav.open"]
        if flyout.exists {
            flyout.tap()
            app.buttons["nav.settings"].tap()
        } else {
            app.tabBars.buttons["Settings"].tap()
        }
        let scroll = app.descendants(matching: .any)["settings.list"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 15), "Settings did not open")
        flingSequence(scroll)
    }
}
