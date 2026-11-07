import XCTest

/// What the weather card's label ticker costs while it runs (`.agents/design/motion.md` §9 ticker exception,
/// `.agents/testing/apple/performance.md`, "Weather card ticker"; runner: `tools/ios_tickerperf.sh`).
///
/// The app records a `TickerRun` signpost interval for every run (`TickerLabel`). These tests measure ten seconds of a ticking
/// label with `XCTOSSignpostMetric` (the interval), `XCTCPUMetric` and, on iOS 26 and later, `XCTHitchMetric`, and compare the same
/// ten seconds with a label that fits (nothing moving). Simulator hitch ratios and GPU cost are false: the simulator runs only
/// with `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` (the runner sets it) and the numbers it gives are CPU. The device budgets are in
/// the performance doc; running on a physical phone needs the owner's say-so.
///
/// Budgets (asserted by the runner from the metrics' CPU time, recorded in the doc): the ticking card costs at most 10% of one core
/// more than the still card over ten seconds, and the hitch time ratio stays under 5 ms/s (Apple's "good").
@MainActor
final class WeatherTickerPerformanceTests: JourneyTestCase {
    /// These tests measure animation, so their launches keep it on (``JourneyTestCase/measuresAnimation``).
    override class var measuresAnimation: Bool { true }

    static let longCondition = WeatherHeaderJourneyTests.longCondition
    static let seconds: TimeInterval = 10

    private func requireOptIn() throws {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["FENTON_PERF_ON_SIMULATOR"] != "1" {
            throw XCTSkip("Set TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1 to measure the ticker on a simulator.")
        }
        #endif
    }

    private func launch(condition: String) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "weather"
        app.launchEnvironment["FENTON_GALLERY_WEATHER_CONDITION"] = condition
        app.launchEnvironment["FENTON_TICKER_PROBE"] = "1"
        app.launch()
        return app
    }

    private func metrics(_ app: XCUIApplication) -> [XCTMetric] {
        var metrics: [XCTMetric] = [
            XCTCPUMetric(application: app),
            XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "TickerRun"),
        ]
        if #available(iOS 26, *) { metrics.append(XCTHitchMetric(application: app)) }
        return metrics
    }

    private func options() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    /// Ten seconds with the ticker running (the hold and the first travel of a pass).
    func testTickerRunningCost() throws {
        try requireOptIn()
        let app = launch(condition: Self.longCondition)
        let probe = app.descendants(matching: .any)["home.weather.condition"].firstMatch
        XCTAssertTrue(probe.appears(timeout: 15))
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'running=1'"), object: probe)
        XCTAssertEqual(XCTWaiter().wait(for: [running], timeout: 15), .completed, "The ticker never started: \(probe.label)")
        measure(metrics: metrics(app), options: options()) {
            Thread.sleep(forTimeInterval: Self.seconds)
        }
    }

    /// The same ten seconds with a label that fits: the floor the ticker's cost is read against.
    func testStillCardCost() throws {
        try requireOptIn()
        let app = launch(condition: "rainy")
        XCTAssertTrue(app.buttons["home.weather.card"].appears(timeout: 15))
        measure(metrics: metrics(app), options: options()) {
            Thread.sleep(forTimeInterval: Self.seconds)
        }
    }
}
