import XCTest

/// Scroll cost budgets for the surfaces that were slow, on the simulator (`.agents/testing/apple/performance.md`, "Scroll
/// cost").
///
/// Each test opens a surface, then asks the app's scroll cost probe (`ScrollCostProbe`) to scroll the front scroll view by
/// itself for 8 s, twice. The probe reports the main thread's CPU time per run-loop turn, which is what a dropped frame is
/// made of: a turn that computes longer than the frame budget is a hitch whatever the display says. Nothing touches the app
/// while it measures (an XCUITest swipe, or a poll for an element, would put the accessibility snapshot it asks for into the
/// number). `tools/ios_scrollcost.sh` runs the same probe over every page and sheet.
///
/// Run with `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`; the live tests also need sign-in
/// (`TEST_RUNNER_FENTON_HASS_TOKEN`). Without it every test skips, so the normal journeys never run this class.
@MainActor
final class ScrollSurfacesPerformanceTests: JourneyTestCase {
    /// These tests measure animation, so their launches keep it on (``JourneyTestCase/measuresAnimation``).
    override class var measuresAnimation: Bool { true }


    // MARK: - Budgets

    /// What a surface may cost. Set from the post-fix numbers (iPhone 17 Pro simulator, optimized build, 2026-10-16):
    /// fixtures p95 turn 3.1 to 3.7 ms and worst 8 to 12 ms; live pages p95 1.6 to 2.4 ms, worst 6 to 9.4 ms.
    enum Budget {
        /// The 95th percentile of the main thread's CPU time per run-loop turn while scrolling, in ms (a 120 Hz frame is 8.3).
        static let fixtureP95 = 6.0
        static let livePageP95 = 3.5
        /// A long Chores page on fixtures: every row that scrolls in is a new `List` cell, sized and built by SwiftUI and UIKit
        /// (about 40% of the main thread's samples, none of it ours), so it sits above the 6 ms fixture budget. After the
        /// header fade stopped updating the view graph per frame it reads p95 6.8 to 7.7 ms and 32 to 57 turns over 8 ms
        /// (before: 7.3 to 7.8 ms, 54 to 61). The budget holds that line, it does not bless it.
        static let longListP95 = 8.0
        static let longListTurnsOver8 = 70.0
        /// Turns that computed longer than 8 ms in a scroll run: none. Before the fix every live page had 18 to 26.
        static let turnsOver8 = 0.0
        /// The longest turn in the (warm) second scroll run, in ms.
        static let worstTurn = 16.0
        /// Main-thread time spent applying live entity updates in one 8 s run, in ms. Before the fix 260 to 440.
        static let entityUpdates = 25.0
        /// Main-thread CPU time of a live page standing still for 8 s, in ms. Before the fix 420 to 640.
        static let idleMain = 100.0
    }

    /// The probe's `key=value` line as numbers.
    struct Reading {
        var values: [String: Double] = [:]
        var fits = false

        init(_ line: String) {
            fits = line.hasPrefix("no scroll view")
            for pair in line.split(separator: " ") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let number = Double(parts[1]) { values[String(parts[0])] = number }
            }
        }

        subscript(key: String) -> Double { values[key] ?? 0 }
    }

    // MARK: - Surfaces

    /// One scrolling surface from the debug gallery's fixtures.
    struct Surface {
        var name: String
        var gallery: String
        var environment: [String: String] = [:]
        /// Identifier of an element that exists once the surface is ready.
        var ready: String
    }

    static let offline = ["FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_CLEAN": "1"]
    static let gridWorkload = Surface(name: "Grid workload", gallery: "performance", environment: ["FENTON_GALLERY_PERF": "grid"], ready: "perf.grid")
    static let livingRoom = Surface(name: "Living Room", gallery: "rooms", environment: offline.merging(["FENTON_GALLERY_ROOM": "living-room"]) { $1 }, ready: "room.scroll.living-room")
    static let climate = Surface(name: "Climate", gallery: "climate", environment: ["FENTON_GALLERY_CLEAN": "1"], ready: "climate.scroll")
    static let chores = Surface(name: "Chores", gallery: "chores", environment: ["FENTON_GALLERY_CLEAN": "1"], ready: "todo.page.chores")
    /// A house as long as the real one (12 more chores in each of Alex's lists): the short fixture page barely scrolls.
    static let choresLongHouse = Surface(name: "Chores (long house)", gallery: "chores", environment: ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_CHORES": "12"], ready: "todo.page.chores")
    static let settings = Surface(name: "Settings", gallery: "settings", environment: ["FENTON_GALLERY_CLEAN": "1"], ready: "settings.list")
    static let foodHub = Surface(name: "Food hub", gallery: "food", environment: ["FENTON_GALLERY_ROUTE": "hub"], ready: "food.scroll")
    static let recipes = Surface(name: "Recipes", gallery: "food", environment: ["FENTON_GALLERY_ROUTE": "recipes"], ready: "recipes.grid")
    static let admin = Surface(name: "Admin settings", gallery: "household-settings", environment: ["FENTON_GALLERY_HOUSEHOLD": "admin", "FENTON_GALLERY_CLEAN": "1"], ready: "household.admin")

    // MARK: - Running

    /// Seconds each measurement lasts (the probe's `FENTON_SCROLLCOST_SECONDS`).
    static let seconds = 8

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private func requireMeasurableDevice() throws {
        #if targetEnvironment(simulator)
        if Self.environment["FENTON_PERF_ON_SIMULATOR"] != "1" {
            throw XCTSkip("Set TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1 to measure scroll cost on a simulator.")
        }
        #endif
    }

    /// Posts one of the probe's Darwin notifications.
    private func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Runs one probe measurement and returns its line. Nothing touches the app while it measures.
    private func probe(_ app: XCUIApplication, scrolling: Bool) -> String {
        post(scrolling ? "com.sfenton.home.scrollcost.scroll" : "com.sfenton.home.scrollcost.idle")
        sleep(UInt32(Self.seconds) + 3)
        let element = app.descendants(matching: .any)["diagnostics.scrollcost"].firstMatch
        XCTAssertTrue(element.appears(timeout: 10), "The scroll cost probe is not in the app")
        return element.label
    }

    private func launchGallery(_ surface: Surface) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = surface.gallery
        app.launchEnvironment["FENTON_TELEMETRY"] = "1"
        app.launchEnvironment["FENTON_SCROLLCOST"] = "1"
        app.launchEnvironment["FENTON_SCROLLCOST_SECONDS"] = "\(Self.seconds)"
        app.launchEnvironment.merge(surface.environment) { $1 }
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)[surface.ready].firstMatch.appears(timeout: 40),
                      "\(surface.name) did not open (\(surface.ready))")
        return app
    }

    /// Records one line as an attachment and in the TSV `tools/scrollcost_report.py` reads
    /// (`TEST_RUNNER_FENTON_SCROLLCOST_OUT`, default `/tmp/fenton-scrollcost.tsv`).
    private func record(_ surface: String, _ kind: String, _ line: String) {
        let row = "SCROLLCOST\t\(surface)\t\(kind)\t\(line)"
        add(XCTAttachment(string: row))
        let path = Self.environment["FENTON_SCROLLCOST_OUT"] ?? "/tmp/fenton-scrollcost.tsv"
        guard let data = (row + "\n").data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    /// Scrolls twice after a settle and holds the second (warm) run to the budget.
    private func assertScrollWithinBudget(_ name: String, app: XCUIApplication, p95: Double, turnsOver8: Double = Budget.turnsOver8) {
        sleep(6) // first-appearance work (images, shaders, the first layout of every tile) settles before measuring
        var last = Reading("")
        for _ in 0..<2 {
            let line = probe(app, scrolling: true)
            record(name, "scroll", line)
            last = Reading(line)
            // A surface that fits the screen has nothing to scroll: recorded, not measured.
            if last.fits { return }
        }
        XCTAssertLessThanOrEqual(last["p95_ms"], p95, "\(name): p95 main-thread turn while scrolling")
        XCTAssertLessThanOrEqual(last["over8"], turnsOver8, "\(name): turns over 8 ms while scrolling")
        XCTAssertLessThanOrEqual(last["worst_ms"], Budget.worstTurn, "\(name): longest main-thread turn while scrolling")
    }

    // MARK: - Fixtures

    func testGridWorkloadScrollStaysWithinBudget() throws {
        try requireMeasurableDevice()
        assertScrollWithinBudget("Grid workload", app: launchGallery(Self.gridWorkload), p95: Budget.fixtureP95)
    }

    func testRoomPageScrollStaysWithinBudget() throws {
        try requireMeasurableDevice()
        assertScrollWithinBudget("Living Room", app: launchGallery(Self.livingRoom), p95: Budget.fixtureP95)
    }

    func testClimateScrollStaysWithinBudget() throws {
        try requireMeasurableDevice()
        assertScrollWithinBudget("Climate", app: launchGallery(Self.climate), p95: Budget.fixtureP95)
    }

    func testChoresScrollStaysWithinBudget() throws {
        try requireMeasurableDevice()
        assertScrollWithinBudget("Chores", app: launchGallery(Self.chores), p95: Budget.fixtureP95)
    }

    /// Owner, 2026-10-17: Chores and Settings did not scroll smoothly. Both are real `List`s; the header fade's scroll reader
    /// cost them a fifth to a third of their main-thread time (`.agents/testing/apple/performance.md`, Round 3).
    func testChoresLongHouseScrollStaysWithinBudget() throws {
        try requireMeasurableDevice()
        assertScrollWithinBudget("Chores (long house)", app: launchGallery(Self.choresLongHouse), p95: Budget.longListP95, turnsOver8: Budget.longListTurnsOver8)
    }

    func testSettingsScrollStaysWithinBudget() throws {
        try requireMeasurableDevice()
        assertScrollWithinBudget("Settings", app: launchGallery(Self.settings), p95: Budget.fixtureP95)
    }

    func testFoodHubScrollStaysWithinBudget() throws {
        try requireMeasurableDevice()
        assertScrollWithinBudget("Food hub", app: launchGallery(Self.foodHub), p95: Budget.fixtureP95)
    }

    func testRecipesScrollStaysWithinBudget() throws {
        try requireMeasurableDevice()
        assertScrollWithinBudget("Recipes", app: launchGallery(Self.recipes), p95: Budget.fixtureP95)
    }

    func testAdminSettingsScrollStaysWithinBudget() throws {
        try requireMeasurableDevice()
        assertScrollWithinBudget("Admin settings", app: launchGallery(Self.admin), p95: Budget.fixtureP95)
    }

    // MARK: - Live (signed in with the token, against the house)

    private func launchLive(open path: String? = nil) throws -> XCUIApplication {
        try requireMeasurableDevice()
        var launch = ["FENTON_TELEMETRY": "1", "FENTON_SCROLLCOST": "1", "FENTON_SCROLLCOST_SECONDS": "\(Self.seconds)"]
        if let path { launch["FENTON_SCROLLCOST_OPEN"] = path }
        let app = try FentonHomeApp.launchSignedIn(environment: launch, readyIdentifier: "diagnostics.scrollcost")
        sleep(14) // the first states, the weather and the images settle
        return app
    }

    /// Live updates arrive about five times a second. Applying them used to take about 9 ms of the main thread each, which
    /// is longer than a 120 Hz frame, so a page stuttered whatever it showed. They are diffed off the main thread now.
    func testLiveEntityUpdatesStayOffTheMainThread() throws {
        let app = try launchLive(open: "chores")
        let line = probe(app, scrolling: false)
        record("Live Chores", "idle", line)
        let idle = Reading(line)
        XCTAssertGreaterThan(idle["deliveries"], 0, "No live updates arrived in \(Self.seconds) s; the house is quiet or the sign-in failed")
        XCTAssertLessThanOrEqual(idle["update_ms"], Budget.entityUpdates, "Main-thread time applying live updates")
        XCTAssertLessThanOrEqual(idle["main_ms"], Budget.idleMain, "Main-thread CPU time of a page standing still")
        XCTAssertLessThanOrEqual(idle["over8"], 0, "Turns over 8 ms on a page standing still")
    }

    func testLiveRoomPageScrollStaysWithinBudget() throws {
        assertScrollWithinBudget("Live Living Room", app: try launchLive(open: "living-room"), p95: Budget.livePageP95)
    }

    func testLiveClimateScrollStaysWithinBudget() throws {
        assertScrollWithinBudget("Live Climate", app: try launchLive(open: "thermostat"), p95: Budget.livePageP95)
    }

    func testLiveChoresScrollStaysWithinBudget() throws {
        assertScrollWithinBudget("Live Chores", app: try launchLive(open: "chores"), p95: Budget.livePageP95)
    }

    func testLiveSettingsScrollStaysWithinBudget() throws {
        assertScrollWithinBudget("Live Settings", app: try launchLive(open: "settings"), p95: Budget.livePageP95)
    }

    func testLiveHomeScrollStaysWithinBudget() throws {
        assertScrollWithinBudget("Live Home", app: try launchLive(), p95: Budget.livePageP95)
    }
}
