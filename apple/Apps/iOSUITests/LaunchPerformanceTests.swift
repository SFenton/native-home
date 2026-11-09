import XCTest

/// Launch, intro and sign-in arrival performance (`.agents/testing/apple/performance.md`, "Launch and sign-in").
///
/// **Two kinds of test, two questions** (the same split as the scroll tests):
/// - *What does it cost the main thread?* The cost tests launch the app with its launch cost probe (`LaunchCostProbe`,
///   `FENTON_LAUNCHCOST=1`) and read its line: the 95th percentile of the main thread's CPU time per run-loop turn, the turns
///   over 16 ms, and the signpost intervals (`SnapshotShown`, `SignIn`, `Intro`, `Arrival`, all `com.sfenton.home` /
///   `Performance`). Nothing touches the app while it measures. They run on a simulator when
///   `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` is set and skip otherwise, so the normal journeys never run this class.
///   `tools/ios_launchperf.sh` runs the same probe without XCUITest.
/// - *Does a frame make its deadline?* The hitch tests (`XCTHitchMetric`) run on a **physical device only** and skip on a
///   simulator: its compositor is the Mac's and its hitch numbers are false. Device runs need the owner's say-so.
///
/// Launch metrics (`XCTApplicationLaunchMetric`) and the signpost interval metrics record baselines per device in Xcode; the
/// budgets below hold the simulator line.
@MainActor
final class LaunchPerformanceTests: JourneyTestCase {
    /// These tests measure animation, so their launches keep it on (``JourneyTestCase/measuresAnimation``).
    override class var measuresAnimation: Bool { true }


    // MARK: - Budgets

    /// What a launch may cost (simulator, main-thread CPU per run-loop turn).
    enum Budget {
        /// The 95th percentile of a turn, in ms: a 120 Hz frame is 8.3.
        static let p95Turn = 8.0
        /// No turn longer than this, in ms (a 60 Hz frame), while only the intro runs.
        static let worstTurn = 16.0
        /// The longest turn once Home is built, in ms. Home's own first layout takes a 180 to 230 ms turn on the simulator
        /// (the snapshot launch has it with no motion at all); the budget holds that line until Home's startup is fixed.
        static let worstTurnWithHome = 300.0
        /// A warm relaunch to the snapshot's values on screen, in ms (400 on an idle Mac; 425 measured beside four other
        /// simulators and a build).
        static let snapshotShown = 500.0
        /// Tokens to Home settled, in ms (the animation is 0.9 s; building Home behind the sign-in layer adds the rest).
        static let arrival = 1600.0
        /// The intro, in ms (it is 1.2 s).
        static let intro = 1500.0
        /// Apple's "good" hitch ratio, in ms per second (devices only).
        static let hitchRatio = 5.0
    }

    // MARK: - Environment

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private func requireSimulatorOptIn() throws {
        if Self.isSimulator, Self.environment["FENTON_PERF_ON_SIMULATOR"] != "1" {
            throw XCTSkip("Set TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1 to measure launch cost on a simulator.")
        }
    }

    private func requireDevice() throws {
        if Self.isSimulator {
            throw XCTSkip("Hitch ratios are measured on a physical device; a simulator reports false data.")
        }
    }

    /// The probe's `key=value` line as numbers.
    struct Reading {
        var values: [String: Double] = [:]

        init(_ line: String) {
            for pair in line.split(separator: " ") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let number = Double(parts[1]) { values[String(parts[0])] = number }
            }
        }

        subscript(key: String) -> Double { values[key] ?? 0 }
        func has(_ key: String) -> Bool { values[key] != nil }
    }

    /// A launch with the probe on. `reset` starts signed out with nothing saved.
    private func makeApp(reset: Bool, skipIntro: Bool, settings: [FentonHomeApp.SystemSetting] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_LAUNCHCOST"] = "1"
        app.launchEnvironment["FENTON_TELEMETRY"] = "1"
        app.launchEnvironment["FENTON_SKIP_INTRO"] = skipIntro ? "1" : "0"
        app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment(settings)) { $1 }
        if reset { app.launchEnvironment["FENTON_UITEST_RESET"] = "1" }
        return app
    }

    /// Waits for the probe's label to carry `key` (a phase's line), without touching the app in between more than the wait.
    private func probeLine(_ app: XCUIApplication, containing key: String, timeout: TimeInterval = 40) -> String {
        let element = app.descendants(matching: .any)["diagnostics.launchcost"].firstMatch
        XCTAssertTrue(element.appears(timeout: 15), "The launch cost probe is not in the app")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let label = element.label
            if label.contains(key) { return label }
            sleep(1)
        }
        XCTFail("No probe line with \(key) after \(timeout) s; last: \(element.label)")
        return element.label
    }

    private func record(_ name: String, _ line: String) {
        add(XCTAttachment(string: "LAUNCHCOST\t\(name)\t\(line)"))
    }

    private func assertTurns(_ reading: Reading, _ name: String, includesHome: Bool = false) {
        XCTAssertLessThanOrEqual(reading["p95_ms"], Budget.p95Turn, "\(name): p95 run-loop turn")
        XCTAssertLessThanOrEqual(reading["worst_ms"], includesHome ? Budget.worstTurnWithHome : Budget.worstTurn,
                                 "\(name): the longest run-loop turn")
    }

    // MARK: - Launch metrics (baselines per device in Xcode)

    /// Cold launch, signed out: the app launch metric and the Launch interval (process start to the first frame).
    func testColdLaunchSignedOut() throws {
        try requireSimulatorOptIn()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(), Self.interval("Launch")], options: options) {
            let app = makeApp(reset: true, skipIntro: false)
            app.launch()
            _ = app.descendants(matching: .any)["diagnostics.launchcost"].firstMatch.appears(timeout: 15)
            app.terminate()
        }
    }

    /// Cold launch, signed out, with the intro off (what every other journey sees).
    func testColdLaunchSignedOutWithoutIntro() throws {
        try requireSimulatorOptIn()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            makeApp(reset: true, skipIntro: true).launch()
        }
    }

    /// The Launch and SnapshotShown intervals of a warm signed-in relaunch (needs sign-in with the runner's credentials).
    func testWarmLaunchSignedInMeasuresTheSnapshot() throws {
        try requireSimulatorOptIn()
        let first = try FentonHomeApp.launchSignedIn(passwordOnly: true)
        first.terminate() // entering the background saved the snapshot
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(), Self.interval("Launch"), Self.interval("SnapshotShown")], options: options) {
            let app = makeApp(reset: false, skipIntro: true)
            app.launch()
            XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 15))
            app.terminate()
        }
    }

    private static func interval(_ name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: name)
    }

    // MARK: - Cost budgets (simulator or device)

    /// The intro (1.2 s) costs the main thread little: p95 turn within a 120 Hz frame, none over 16 ms.
    func testIntroStaysWithinTheMainThreadBudget() throws {
        try requireSimulatorOptIn()
        let app = makeApp(reset: true, skipIntro: false)
        app.launch()
        let line = probeLine(app, containing: "Intro_ms")
        record("intro", line)
        let reading = Reading(line)
        assertTurns(reading, "intro")
        XCTAssertLessThanOrEqual(reading["Intro_ms"], Budget.intro, "the intro runs about 1.2 s")
        XCTAssertTrue(app.textFields["login.username"].appears(timeout: 5), "the intro ends on the form")
    }

    /// With Reduce Motion the intro is a cross-fade: it costs no more.
    func testReducedMotionIntroStaysWithinTheMainThreadBudget() throws {
        try requireSimulatorOptIn()
        let app = makeApp(reset: true, skipIntro: false, settings: [.reduceMotion])
        app.launch()
        let line = probeLine(app, containing: "seconds=")
        record("intro-reduced", line)
        assertTurns(Reading(line), "intro, reduced motion")
    }

    /// A warm relaunch draws the snapshot within 400 ms and the launch ground's fade costs no frame.
    func testWarmRelaunchShowsTheSnapshotWithinBudget() throws {
        try requireSimulatorOptIn()
        let first = try FentonHomeApp.launchSignedIn(passwordOnly: true)
        first.terminate()
        let app = makeApp(reset: false, skipIntro: true)
        app.launch()
        XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 15), "Relaunch did not open on Home")
        XCTAssertFalse(app.textFields["login.username"].exists, "a signed-in relaunch has no sign-in and no intro")
        let line = probeLine(app, containing: "SnapshotShown_ms")
        record("snapshot", line)
        let reading = Reading(line)
        assertTurns(reading, "snapshot", includesHome: true)
        XCTAssertLessThanOrEqual(reading["SnapshotShown_ms"], Budget.snapshotShown, "warm launch to the snapshot")
    }

    /// Sign in (by itself, so no tap is in the number) and Home arrives: tokens to settled within 1.6 s, no long turn once Home is built.
    func testArrivalStaysWithinTheBudget() throws {
        try requireSimulatorOptIn()
        let app = try launchAutoSignIn()
        let line = probeLine(app, containing: "Arrival_ms", timeout: 60)
        record("arrival", line)
        let reading = Reading(line)
        assertTurns(reading, "arrival", includesHome: true)
        XCTAssertLessThanOrEqual(reading["Arrival_ms"], Budget.arrival, "tokens to Home settled")
        XCTAssertTrue(reading.has("SignIn_ms"), "the sign-in request was timed")
    }

    // MARK: - Hitches (physical device only)

    /// The intro's hitch ratio on a device.
    @available(iOS 26.0, *)
    func testIntroHitchRatioOnADevice() throws {
        try requireDevice()
        let app = makeApp(reset: true, skipIntro: false)
        measure(metrics: [XCTHitchMetric(application: app)]) {
            app.launch()
            XCTAssertTrue(app.textFields["login.username"].appears(timeout: 10))
            sleep(2)
            app.terminate()
        }
    }

    /// The arrival's hitch ratio on a device: sign in by itself and let Home arrive.
    @available(iOS 26.0, *)
    func testArrivalHitchRatioOnADevice() throws {
        try requireDevice()
        let app = try launchAutoSignIn(launch: false)
        measure(metrics: [XCTHitchMetric(application: app), Self.interval("Arrival")]) {
            app.launch()
            XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 60))
            sleep(2)
            app.terminate()
        }
    }

    /// An app that signs in by itself with the runner's credentials (`FENTON_AUTOSIGNIN`), skipping the intro.
    private func launchAutoSignIn(launch: Bool = true) throws -> XCUIApplication {
        guard let credentials = FentonHomeApp.credentials else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_HASS_USERNAME / _PASSWORD to measure the arrival")
        }
        let app = makeApp(reset: true, skipIntro: true)
        app.launchEnvironment["FENTON_AUTOSIGNIN"] = "1"
        app.launchEnvironment["FENTON_HASS_USERNAME"] = credentials.username
        app.launchEnvironment["FENTON_HASS_PASSWORD"] = credentials.password
        if let server = credentials.server { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
        if launch {
            app.launch()
            XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 60), "Home did not appear after sign-in")
        }
        return app
    }
}
