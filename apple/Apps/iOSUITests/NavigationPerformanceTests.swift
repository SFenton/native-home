import XCTest

/// What navigation costs: tab switches, pushes and pops of a room page, sheets and zooms, measured by the app itself
/// (`NavigationTelemetry`, `NavigationMeasurement`) and read back through its `diagnostics.navperf` element
/// (`.agents/design/motion.md` §10, `.agents/testing/apple/performance.md`, "Navigation").
///
/// **Simulator** tests assert the CPU budgets: the transition's 95th-percentile run-loop turn at most 8 ms, none over 16 ms, a tab
/// tap to its first frame at most 50 ms at the 95th percentile. Simulator hitch ratios and GPU cost are false and not asserted.
/// They run only with `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` (`tools/ios_navperf.sh` sets it), so the normal journeys skip them.
/// **Device** tests (`testDevice...`) measure with `XCTOSSignpostMetric.navigationTransitionMetric` and the app's own signposts,
/// and skip on a simulator; they need the owner's say-so before a planner runs them.
@MainActor
final class NavigationPerformanceTests: JourneyTestCase {
    /// These tests measure animation, so their launches keep it on (``JourneyTestCase/measuresAnimation``).
    override class var measuresAnimation: Bool { true }

    enum Budget {
        /// The 95th percentile of a transition's run-loop turn, in ms (a 120 Hz frame is 8.3).
        static let turnP95 = 8.0
        /// The longest turn of any transition.
        static let worstTurn = 16.0
        /// The longest turn of a Settings → Performance push: that page lays out about forty rows in the turn that builds it. The base
        /// (system push, 66ae0c9f) took 139 ms in that turn; the single-page push takes 77 ms. A page build, not the animation, whose
        /// p95 turn is held to `turnP95` like every other.
        static let settingsPageBuildTurn = 100.0
        /// Tab tap to the destination's first frame, 95th percentile.
        static let tabFirstFrameP95 = 50.0
        /// Push or sheet tap to settled (the system transition plus the page).
        static let settled = 600.0
    }

    static let repeats = 10

    // MARK: - Running

    private func requireSimulatorOptIn() throws {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["FENTON_PERF_ON_SIMULATOR"] != "1" {
            throw XCTSkip("Set TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1 to measure navigation cost on a simulator.")
        }
        #endif
    }

    private func requireDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Navigation transition metrics are only meaningful on a physical device.")
        #endif
    }

    private func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// The probe's numbers as `key=value`.
    struct Reading {
        var values: [String: Double] = [:]
        init(_ line: String) {
            for pair in line.split(separator: " ") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let number = Double(parts[1]) { values[String(parts[0])] = number }
            }
        }
        subscript(key: String) -> Double? { values[key] }
    }

    private func report(_ app: XCUIApplication) -> Reading {
        post("com.sfenton.home.navperf.report")
        let element = app.descendants(matching: .any)["diagnostics.navperf"].firstMatch
        XCTAssertTrue(element.appears(timeout: 10), "The navigation probe is not in the app")
        let predicate = NSPredicate(format: "label != 'ready' AND label != 'reset'")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        return Reading(element.label)
    }

    /// Prints and attaches one `NAVPERF` row per surface for `tools/ios_navperf.sh`.
    private func record(_ scenario: String, _ reading: Reading) {
        for key in reading.values.keys.sorted() where key.hasSuffix(".n") {
            let surface = String(key.dropLast(2))
            func value(_ suffix: String) -> String { reading["\(surface).\(suffix)"].map { String(format: "%.2f", $0) } ?? "-" }
            let row = "NAVPERF\t\(FentonHomeApp.family)\t\(scenario)\t\(surface)\tn=\(value("n"))\tfirst.p50=\(value("first.p50"))\tfirst.p95=\(value("first.p95"))"
                + "\tsettled.p50=\(value("settled.p50"))\tsettled.p95=\(value("settled.p95"))\tturn.p95=\(value("turn.p95"))\tturn.worst=\(value("turn.worst"))"
            print(row)
            add(XCTAttachment(string: row))
            append(row + "\n")
        }
    }

    /// Appends to the TSV `tools/ios_navperf.sh` reads (`TEST_RUNNER_FENTON_NAVPERF_OUT`, default `/tmp/fenton-navperf.tsv`).
    private func append(_ text: String) {
        let path = ProcessInfo.processInfo.environment["FENTON_NAVPERF_OUT"] ?? "/tmp/fenton-navperf.tsv"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    private func assertWithinCPUBudget(_ reading: Reading, surfaces: [String], scenario: String, worstTurn: Double = Budget.worstTurn) {
        for surface in surfaces {
            XCTAssertGreaterThan(reading["\(surface).n"] ?? 0, 0, "\(scenario): no \(surface) was measured")
            if let turn = reading["\(surface).turn.p95"] {
                XCTAssertLessThanOrEqual(turn, Budget.turnP95, "\(scenario): \(surface) p95 run-loop turn")
            }
            if let worst = reading["\(surface).turn.worst"] {
                XCTAssertLessThanOrEqual(worst, worstTurn, "\(scenario): \(surface) longest run-loop turn")
            }
        }
    }

    private func launchGallery(_ page: String, environment: [String: String] = [:]) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery(page, environment: environment.merging(["FENTON_TELEMETRY": "1", "FENTON_NAVPERF": "1"]) { $1 })
        return app
    }

    private func launchLive() throws -> XCUIApplication {
        try requireSimulatorOptIn()
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_TELEMETRY": "1", "FENTON_NAVPERF": "1"])
        sleep(10) // The first states, the weather and the images settle.
        return app
    }

    private func tab(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.tabBars.buttons[title].exists ? app.tabBars.buttons[title] : app.toolbars.buttons[title]
    }

    // MARK: - Simulator (CPU budgets)

    /// The five tabs, in the order a person walks them, ending on Home.
    private static let tabs = [("security", "Security"), ("climate", "Climate"), ("chores", "Chores"), ("settings", "Settings"), ("home", "Home")]

    /// Every tab three times, then back to Home: a cut each time. A tab's first visit builds its page, which is not a cut and is
    /// reported on its own (`tab first visit`, not asserted); the budgets hold for the revisits, which is what a cut costs.
    func testTabCycleStaysWithinBudget() throws {
        let app = try launchLive()
        guard tab("Climate", in: app).exists else { throw XCTSkip("This window navigates with the flyout, not tabs") }
        post("com.sfenton.home.navperf.reset")
        for (section, title) in Self.tabs {
            openSection(section, title: title, in: app)
            usleep(1_500_000) // The page's first layout and images settle before the next tap.
        }
        record("tab first visit", report(app))
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<3 {
            for (section, title) in Self.tabs {
                openSection(section, title: title, in: app)
                usleep(400_000)
            }
        }
        let reading = report(app)
        record("tab cycle", reading)
        assertWithinCPUBudget(reading, surfaces: ["tabSwitch"], scenario: "tab cycle")
        if let first = reading["tabSwitch.first.p95"] {
            XCTAssertLessThanOrEqual(first, Budget.tabFirstFrameP95, "Tab tap to the destination's first frame, p95")
        }
    }

    /// Home, away and back to Home again: the revisit is instant, and costs what a cut costs.
    func testHomeRevisitStaysWithinBudget() throws {
        let app = try launchLive()
        guard tab("Climate", in: app).exists else { throw XCTSkip("This window navigates with the flyout, not tabs") }
        // Climate's first visit builds it; the revisits are what is measured.
        openSection("climate", title: "Climate", in: app)
        sleep(2)
        openSection("home", title: "Home", in: app)
        sleep(1)
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<Self.repeats {
            openSection("climate", title: "Climate", in: app)
            openSection("home", title: "Home", in: app)
            XCTAssertTrue(app.buttons["home.chip.lights"].exists, "Home was not there on the revisit")
        }
        let reading = report(app)
        record("home revisit", reading)
        assertWithinCPUBudget(reading, surfaces: ["tabSwitch"], scenario: "home revisit")
        if let first = reading["tabSwitch.first.p95"] {
            XCTAssertLessThanOrEqual(first, Budget.tabFirstFrameP95, "Home revisit first frame, p95")
        }
    }

    /// A room page pushed and popped ten times from the Rooms gallery (fixtures, no house).
    func testPushAndPopRoomStaysWithinBudget() throws {
        try requireSimulatorOptIn()
        let app = launchGallery("rooms")
        let living = app.buttons["gallery.room.living-room"]
        XCTAssertTrue(living.appears(timeout: 30))
        sleep(2)
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<Self.repeats {
            living.tap()
            XCTAssertTrue(element("room.scroll.living-room", in: app).appears(timeout: 10))
            let back = app.buttons["BackButton"]
            XCTAssertTrue(back.appears(timeout: 5))
            back.tap()
            XCTAssertTrue(living.appears(timeout: 5))
        }
        let reading = report(app)
        record("push/pop room", reading)
        // Pop is recorded when UIKit reports the page leaving; on the simulators it has not been (`.agents/patterns/motion.md`,
        // Departures), so only the push is required here, and a pop that is measured is held to the same budget.
        assertWithinCPUBudget(reading, surfaces: ["push"] + (reading["pop.n"] == nil ? [] : ["pop"]), scenario: "push/pop room")
        if let settled = reading["push.settled.p95"] { XCTAssertLessThanOrEqual(settled, Budget.settled, "Push tap to settled, p95") }
    }

    /// Settings → Performance pushed and popped ten times in the signed-in shell: the single-page push and pop of `UKStackMotion`
    /// (`.agents/design/single-page-motion.md` S6). Where the window shows columns instead (unfolded Duo or iPad landscape) nothing is
    /// pushed and the test ends without asserting.
    func testSettingsPushAndPopStaysWithinBudget() throws {
        let app = try launchLive()
        openSection("settings", title: "Settings", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].appears(timeout: 10))
        let row = app.buttons["settings.performance"]
        app.revealSettingsRow(row)
        // One push and pop first, unmeasured: the first visit builds the page, which is not what the transition costs.
        row.tap()
        if app.buttons["split.close"].appears(timeout: 1) { return }
        XCTAssertTrue(app.buttons["BackButton"].firstMatch.appears(timeout: 10))
        app.buttons["BackButton"].firstMatch.tap()
        app.revealSettingsRow(row)
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<Self.repeats {
            row.tap()
            if app.buttons["split.close"].appears(timeout: 1) { return }
            XCTAssertTrue(app.navigationBars["Performance"].appears(timeout: 10))
            let back = app.buttons["BackButton"].firstMatch
            XCTAssertTrue(back.appears(timeout: 5))
            back.tap()
            XCTAssertTrue(app.navigationBars["Settings"].appears(timeout: 5))
            app.revealSettingsRow(row)
        }
        let reading = report(app)
        record("settings push/pop", reading)
        assertWithinCPUBudget(reading, surfaces: ["push", "pop"], scenario: "settings push/pop", worstTurn: Budget.settingsPageBuildTurn)
        if let settled = reading["push.settled.p95"] { XCTAssertLessThanOrEqual(settled, Budget.settled, "Push tap to settled, p95") }
    }

    /// A sheet opened and closed ten times (Quick Links, from the Rooms gallery).
    func testSheetOpenAndCloseStaysWithinBudget() throws {
        try requireSimulatorOptIn()
        let app = launchGallery("rooms")
        let open = app.buttons["gallery.quickLinks"]
        // The button is below the list of rooms.
        for _ in 0..<12 where !(open.exists && open.isHittable) { app.swipeUp() }
        XCTAssertTrue(open.appears(timeout: 30))
        sleep(2)
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<Self.repeats {
            open.tap()
            let close = app.buttons["quickLinks.close"]
            XCTAssertTrue(close.appears(timeout: 10))
            XCTAssertTrue(close.wait(for: \.isHittable, toEqual: true, timeout: 5))
            close.tap()
            XCTAssertTrue(open.appears(timeout: 5))
            XCTAssertTrue(open.wait(for: \.isHittable, toEqual: true, timeout: 5))
        }
        let reading = report(app)
        record("sheet open/close", reading)
        assertWithinCPUBudget(reading, surfaces: ["sheetPresent", "sheetDismiss"], scenario: "sheet open/close")
        if let settled = reading["sheetPresent.settled.p95"] { XCTAssertLessThanOrEqual(settled, Budget.settled, "Sheet present to settled, p95") }
    }

    /// A camera card zooming into its viewer and back ten times (iOS 18 and later; before it, the sheet, recorded as one). The
    /// zoom is for a tile that is the thing it opens, never inside a sheet (owner, 2026-10-22).
    func testZoomOpenAndCloseStaysWithinBudget() throws {
        let app = try launchLive()
        let card = app.buttons["home.camera.front_door"]
        XCTAssertTrue(card.appears(timeout: 20))
        XCTAssertTrue(card.wait(for: \.isHittable, toEqual: true, timeout: 5))
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<Self.repeats {
            card.tap()
            let close = app.buttons["sheet.close"]
            XCTAssertTrue(close.appears(timeout: 10))
            XCTAssertTrue(close.wait(for: \.isHittable, toEqual: true, timeout: 5))
            close.tap()
            XCTAssertTrue(card.appears(timeout: 5))
            XCTAssertTrue(card.wait(for: \.isHittable, toEqual: true, timeout: 5))
        }
        let reading = report(app)
        record("zoom camera", reading)
        if #available(iOS 18, *) {
            assertWithinCPUBudget(reading, surfaces: ["zoomOpen"] + (reading["zoomClose.n"] == nil ? [] : ["zoomClose"]), scenario: "zoom camera")
        } else {
            assertWithinCPUBudget(reading, surfaces: ["sheetPresent"], scenario: "zoom camera (sheet fallback)")
        }
    }

    // MARK: - Device (signposts and Apple's transition metric)

    /// Tab switches, pushes and sheets on a phone, with Apple's navigation transition metric and the app's own signposts.
    func testDeviceNavigationTransitionMetrics() throws {
        try requireDevice()
        let app = launchGallery("rooms")
        let living = app.buttons["gallery.room.living-room"]
        XCTAssertTrue(living.appears(timeout: 30))
        var metrics: [XCTMetric] = [XCTOSSignpostMetric.navigationTransitionMetric]
        for name in ["Push", "Pop", "SheetPresent", "SheetDismiss"] {
            metrics.append(XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: name))
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: metrics, options: options) {
            living.tap()
            _ = element("room.scroll.living-room", in: app).appears(timeout: 10)
            let back = app.buttons["BackButton"]
            _ = back.appears(timeout: 5)
            back.tap()
            _ = living.appears(timeout: 5)
            let open = app.buttons["gallery.quickLinks"]
            for _ in 0..<12 where !(open.exists && open.isHittable) { app.swipeUp() }
            open.tap()
            let close = app.buttons["quickLinks.close"]
            _ = close.appears(timeout: 10)
            close.tap()
            // Back to the top: the gallery is a lazy list, so the room button is gone once Quick Links is scrolled to.
            for _ in 0..<12 where !(living.exists && living.isHittable) { app.swipeDown() }
        }
    }

    /// The zoom from a camera card into its viewer on a phone (iOS 18 and later).
    func testDeviceZoomTransitionMetrics() throws {
        try requireDevice()
        guard #available(iOS 18, *) else { throw XCTSkip("The zoom transition needs iOS 18") }
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_TELEMETRY": "1"])
        let card = app.buttons["home.camera.front_door"]
        XCTAssertTrue(card.appears(timeout: 20))
        let metrics: [XCTMetric] = [
            XCTOSSignpostMetric.navigationTransitionMetric,
            XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "ZoomOpen"),
            XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "ZoomClose"),
        ]
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: metrics, options: options) {
            card.tap()
            _ = app.buttons["sheet.close"].appears(timeout: 10)
            app.buttons["sheet.close"].tap()
            _ = card.appears(timeout: 5)
        }
    }
}
