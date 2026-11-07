import XCTest

/// The Home weather card's header, option D (`.agents/design/weather-card-header.md`): the numeral never truncates, the condition
/// stays on one line below accessibility sizes (and scrolls as a ticker only when it overflows), Reduce Motion wraps it, and the
/// card button keeps a 44 pt target. Runs on iPhone, iPhone Duo (folded and unfolded) and iPad, whichever simulator the run is on.
///
/// The ticker's text is hidden from accessibility, so the tests read its state from the invisible `home.weather.condition` element
/// the app adds under `FENTON_TICKER_PROBE=1` (`TickerLabel`'s probe): `overflow`, `running`, `finished`, `wraps`, `lines`.
@MainActor
final class WeatherHeaderJourneyTests: JourneyTestCase {
    /// The Duo unfolded is the one phone family that rotates here (landscape unfolds it to two screens).
    override class var rotatingFamilies: [FentonHomeApp.Family] { [.iPad, .iPhoneDuo] }

    /// The text sizes, as raw `UIContentSizeCategory` values. With reuse on a launch sets the size in place on the class's resident
    /// app (`AppReuse.setTextSize`); AX5 is the exception and launches fresh with the launch argument (`app-reuse.md`, rule 1), so the
    /// tests of AX5 keep their old fidelity.
    static let large = "UICTContentSizeCategoryL"
    static let xxxLarge = "UICTContentSizeCategoryXXXL"
    static let ax2 = "UICTContentSizeCategoryAccessibilityL"
    static let ax5 = FentonHomeApp.ax5[1]

    /// "Rain": fits every column.
    static let shortCondition = "rainy"
    /// A label far wider than any column on the supported devices (the gallery title-cases an unknown condition).
    static let longCondition = "heavy-thunderstorm-with-hail-and-damaging-wind-gusts-across-the-entire-county-tonight"

    // MARK: - Helpers

    private func launch(condition: String, size: String?, settings: [FentonHomeApp.SystemSetting] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "weather"
        app.launchEnvironment["FENTON_GALLERY_WEATHER_CONDITION"] = condition
        app.launchEnvironment["FENTON_TICKER_PROBE"] = "1"
        app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment(settings)) { _, new in new }
        // Through `startApp`: with reuse on the class keeps one resident app per launch signature, reset per test (`app-reuse.md`). The
        // gallery builds its store and fixtures per gallery, so nothing survives a reset. AX5 launches (arguments) are fresh by signature.
        guard let size else { return finishLaunch(startApp(app)) } // The system's own size (the simulator's default, Large).
        guard size != Self.ax5, AppReuse.isOn else {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
            return finishLaunch(startApp(app))
        }
        let running = startApp(app)
        _ = finishLaunch(running)
        // The size is set in place after the reset. A change of size shows once the numeral (whose font follows the size) has a new
        // height; the ack comes 100 ms after the change, before the layout is known to be done.
        let numeral = element("home.weather.numeral", in: running)
        let before = (try? numeral.snapshot())?.frame.height ?? 0
        XCTAssertTrue(AppReuse.setTextSize(running, size), "The app did not acknowledge the text size \(size)")
        if size != Self.large {
            let end = Date().addingTimeInterval(8)
            while Date() < end, (try? numeral.snapshot())?.frame.height == before { usleep(50_000) }
        }
        return running
    }

    private func finishLaunch(_ app: XCUIApplication) -> XCUIApplication {
        XCTAssertTrue(app.buttons["home.weather.card"].appears(timeout: 15), "The weather card did not appear")
        return app
    }

    private struct TickerState {
        var values: [String: Int] = [:]
        init(_ label: String) {
            for pair in label.split(separator: " ") {
                let parts = pair.split(separator: "=")
                if parts.count == 2, let number = Int(parts[1]) { values[String(parts[0])] = number }
            }
        }
        subscript(key: String) -> Int { values[key] ?? -1 }
    }

    /// The ticker's state, once its line has been measured (a `lines` count above 0).
    private func state(_ app: XCUIApplication, timeout: TimeInterval = 10) -> TickerState {
        let probe = app.descendants(matching: .any)["home.weather.condition"].firstMatch
        XCTAssertTrue(probe.appears(timeout: timeout), "The ticker probe is missing (FENTON_TICKER_PROBE)")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, TickerState(probe.label)["lines"] < 1 { usleep(100_000) }
        return TickerState(probe.label)
    }

    /// Keeps the card's screenshot, and writes it to `FENTON_WEATHER_HEADER_SHOTS` when that names a folder.
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["FENTON_WEATHER_HEADER_SHOTS"], !folder.isEmpty {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(layout)-\(name).png"))
        }
    }

    // MARK: - Numeral

    /// The reading is never cut: the invisible `home.weather.numeral` element has the numeral's own frame, which is at least as wide
    /// as it is tall (a three-character reading in a thin font), and it stays inside the card.
    private func assertNumeralWhole(_ app: XCUIApplication, _ size: String, file: StaticString = #filePath, line: UInt = #line) {
        let numeral = app.descendants(matching: .any)["home.weather.numeral"].firstMatch
        let module = app.descendants(matching: .any)["home.weather"].firstMatch
        XCTAssertTrue(numeral.appears(timeout: 8), file: file, line: line)
        // One snapshot each instead of a request per frame read.
        guard let numeralFrame = (try? numeral.snapshot())?.frame, let moduleFrame = (try? module.snapshot())?.frame else {
            XCTFail("The numeral or the card left the tree at \(size)", file: file, line: line)
            return
        }
        XCTAssertGreaterThanOrEqual(numeralFrame.width, 0.9 * numeralFrame.height, "The numeral looks cut at \(size): \(numeralFrame)", file: file, line: line)
        XCTAssertLessThanOrEqual(numeralFrame.maxX, moduleFrame.maxX + 0.5, "The numeral leaves the card at \(size)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(numeralFrame.minX, moduleFrame.minX, "The numeral leaves the card at \(size)", file: file, line: line)
    }

    private func numeralWhole(_ name: String, _ size: String, _ condition: String) {
        let app = launch(condition: condition, size: size)
        assertNumeralWhole(app, "\(name) \(condition)")
    }

    /// One test per size and condition (`testWeatherNumeralWhole<Size><Condition>`).
    func testWeatherNumeralWholeLargeShort() { numeralWhole("Large", Self.large, Self.shortCondition) }
    func testWeatherNumeralWholeLargeLong() { numeralWhole("Large", Self.large, Self.longCondition) }
    func testWeatherNumeralWholeXXXLargeShort() { numeralWhole("xxxLarge", Self.xxxLarge, Self.shortCondition) }
    func testWeatherNumeralWholeXXXLargeLong() { numeralWhole("xxxLarge", Self.xxxLarge, Self.longCondition) }
    func testWeatherNumeralWholeAX5Short() { numeralWhole("AX5", Self.ax5, Self.shortCondition) }
    func testWeatherNumeralWholeAX5Long() { numeralWhole("AX5", Self.ax5, Self.longCondition) }

    // MARK: - Condition

    private func conditionOneLine(_ name: String, _ size: String) {
        let app = launch(condition: Self.longCondition, size: size)
        let ticker = state(app)
        XCTAssertEqual(ticker["lines"], 1, "The condition wraps at \(name)")
        XCTAssertEqual(ticker["wraps"], 0, name)
    }

    func testWeatherConditionOneLineLarge() { conditionOneLine("Large", Self.large) }
    func testWeatherConditionOneLineXXXLarge() { conditionOneLine("xxxLarge", Self.xxxLarge) }

    func testConditionWrapsAtAccessibilitySizes() {
        let app = launch(condition: Self.longCondition, size: Self.ax5)
        let ticker = state(app)
        XCTAssertEqual(ticker["wraps"], 1)
        XCTAssertGreaterThan(ticker["lines"], 1, "A long condition wraps at AX5")
        XCTAssertEqual(ticker["running"], 0)
        assertNumeralWhole(app, "AX5")
    }

    func testTickerStartsOnlyWhenTheConditionOverflows() {
        var app = launch(condition: Self.shortCondition, size: Self.large)
        var ticker = state(app)
        XCTAssertEqual(ticker["overflow"], 0, "A short condition fits")
        XCTAssertEqual(ticker["running"], 0, "A short condition does not tick")
        XCTAssertEqual(ticker["lines"], 1)
        // Reuse resets the same app; without it the first launch has to end before the second.
        if !AppReuse.isOn { app.terminate() }

        app = launch(condition: Self.longCondition, size: Self.large)
        ticker = state(app)
        XCTAssertEqual(ticker["overflow"], 1, "The long condition overflows its column")
        XCTAssertEqual(ticker["lines"], 1)
        let probe = app.descendants(matching: .any)["home.weather.condition"].firstMatch
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'running=1'"), object: probe)
        XCTAssertEqual(XCTWaiter().wait(for: [running], timeout: 8), .completed, "The ticker never started: \(probe.label)")
    }

    func testReduceMotionWrapsTheConditionInsteadOfTicking() {
        let app = launch(condition: Self.longCondition, size: Self.large, settings: [.reduceMotion])
        let ticker = state(app)
        XCTAssertEqual(ticker["wraps"], 1)
        XCTAssertEqual(ticker["running"], 0)
        XCTAssertGreaterThan(ticker["lines"], 1, "With Reduce Motion the long condition wraps")
        assertNumeralWhole(app, "Large, Reduce Motion")
    }

    // MARK: - Accessibility

    private func cardKeepsItsName(_ name: String, _ size: String) {
        let app = launch(condition: Self.longCondition, size: size)
        let card = app.buttons["home.weather.card"]
        let facts = try? card.snapshot()
        XCTAssertTrue(facts?.label.hasPrefix("Open seven-day weather forecast. ") ?? false, facts?.label ?? "no card")
        XCTAssertTrue(card.isHittable, name)
        XCTAssertGreaterThanOrEqual(facts?.frame.height ?? 0, 44, name)
        XCTAssertGreaterThanOrEqual(facts?.frame.width ?? 0, 44, name)
        // The condition and the range read in order: the range is its own element under the card's button.
        let today = app.descendants(matching: .any)["home.weather.today"].firstMatch
        XCTAssertTrue(today.appears(timeout: 8), name)
        XCTAssertTrue(today.label.hasPrefix("Today "), today.label)
    }

    func testWeatherCardNameLarge() { cardKeepsItsName("Large", Self.large) }
    func testWeatherCardNameAX5() { cardKeepsItsName("AX5", Self.ax5) }

    private func audit(condition: String) throws {
        guard ProcessInfo.processInfo.environment["FENTON_SKIP_AUDIT"] != "1" else { return }
        // The system's own size: an audit of a page under an in-place size override reports element-less issues the plain launch does
        // not (about 11, 2 s apiece to resolve), and the simulator's size is Large.
        let app = launch(condition: condition, size: nil)
        try FentonHomeApp.audit(app, ax5Page: { self.launch(condition: condition, size: Self.ax5) }, presenter: nil)
    }

    func testHeaderWithAShortConditionPassesTheAccessibilityAudit() throws { try audit(condition: Self.shortCondition) }

    func testHeaderWithATickingConditionPassesTheAccessibilityAudit() throws { try audit(condition: Self.longCondition) }

    // MARK: - Evidence

    private func captureHeader(_ label: String, _ size: String, _ name: String, _ condition: String) {
        let app = launch(condition: condition, size: size)
        _ = state(app)
        shoot(app, "header-\(label)-\(name)")
    }

    /// The card at Large, xxxLarge and AX2 with a short and a long label (screenshots for the PR), one test each.
    func testCaptureWeatherHeaderLargeShort() { captureHeader("large", Self.large, "short", Self.shortCondition) }
    func testCaptureWeatherHeaderLargeLong() { captureHeader("large", Self.large, "long", Self.longCondition) }
    func testCaptureWeatherHeaderXXXLargeShort() { captureHeader("xxxlarge", Self.xxxLarge, "short", Self.shortCondition) }
    func testCaptureWeatherHeaderXXXLargeLong() { captureHeader("xxxlarge", Self.xxxLarge, "long", Self.longCondition) }
    func testCaptureWeatherHeaderAX2Short() { captureHeader("ax2", Self.ax2, "short", Self.shortCondition) }
    func testCaptureWeatherHeaderAX2Long() { captureHeader("ax2", Self.ax2, "long", Self.longCondition) }
}
