import XCTest

/// Push and pop on the single-page layouts (`.agents/design/single-page-motion.md`, owner 2026-11-02): iPhone, the folded Duo and the
/// iPad in portrait move pages like the unfolded columns do, over the one wallpaper behind the window.
///
/// The journeys cover a push, a sub-push, the pop, the edge swipe back (let go past halfway, and let go early), a tab switch that keeps
/// each tab's stack, Reduce Motion, AX5 and the wallpaper while a page moves. Where the window splits (unfolded Duo or iPad in
/// landscape) Settings shows columns instead of pushing; the journeys end there without asserting, since the columns journeys own that.
///
/// `testRecordSinglePageMotion` is the evidence recorder: with `TEST_RUNNER_FENTON_MOTION_MARKS=<file>` it performs each move with a
/// pause around it and appends `<name> <unix seconds>` before and after, for `tools/ios_uitest.sh` with `FENTON_UITEST_RECORD_DIR`
/// (it records the simulator's screen) and `tools/video_frames.swift` (contact sheets of each move). It does nothing without the file.
@MainActor
final class SinglePageMotionJourneyTests: JourneyTestCase {
    override class var measuresAnimation: Bool { true }

    // MARK: - Helpers

    /// Opens a section (``openSection(_:title:in:)``). `root` is false when the section keeps a pushed page.
    private func go(_ section: String, _ title: String, in app: XCUIApplication, root: Bool = true) {
        openSection(section, title: title, in: app)
        if root {
            let mark = section == "settings" ? "settings.list" : "nav.profile"
            XCTAssertTrue(element(mark, in: app).appears(timeout: 10), "\(title) did not appear")
        }
    }

    private func launch(arguments: [String] = [], environment: [String: String] = [:]) throws -> XCUIApplication {
        // The iPad's flyout does not close after a section is chosen (also on the base 66ae0c9f, 2026-11-02; tracked for the port's own
        // sessions), so no journey can reach Settings there: skipped, not failed. Push, pop and the swipe are covered on any width by the
        // hosted `StackMotionTests`, which run the same animator in a window.
        if FentonHomeApp.family == .iPad { throw XCTSkip("iPad flyout stays open after choosing a section (pre-existing on 66ae0c9f; dry-run findings handoff, item 8)") }
        var env = ["FENTON_BACKDROP_FIXTURE": "1"]
        env.merge(environment) { _, new in new }
        let app = try FentonHomeApp.launchSignedIn(arguments: arguments, environment: env, readyIdentifier: "nav.profile")
        go("settings", "Settings", in: app)
        XCTAssertTrue(app.buttons["settings.performance"].exists || app.descendants(matching: .any)["settings.list"].appears(timeout: 15), "Settings did not appear")
        return app
    }

    /// The Performance row (a route push), scrolled into view.
    private func performanceRow(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["settings.performance"]
        app.revealSettingsRow(row)
        return row
    }

    /// Opens Performance. Returns false where the window shows columns instead of a pushed page.
    @discardableResult
    private func pushPerformance(_ app: XCUIApplication) -> Bool {
        let row = performanceRow(app)
        XCTAssertTrue(row.exists, "No Performance row")
        row.tap()
        if app.buttons["split.close"].appears(timeout: 1.5) { return false }
        XCTAssertTrue(back(app).appears(timeout: 10), "Performance did not push")
        return true
    }

    private func back(_ app: XCUIApplication) -> XCUIElement { app.buttons["BackButton"].firstMatch }

    private func edgeStart(_ app: XCUIApplication) -> XCUICoordinate {
        let window = app.windows.firstMatch
        return window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: window.frame.height / 2))
    }

    /// Swipes from the leading edge across `fraction` of the width; slow ones end holding still, so the let-go has no speed.
    private func swipeBack(_ app: XCUIApplication, fraction: CGFloat, slow: Bool) {
        let width = app.windows.firstMatch.frame.width
        let start = edgeStart(app)
        let end = start.withOffset(CGVector(dx: width * fraction, dy: 0))
        if slow {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(120), thenHoldForDuration: 0.4)
        } else {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        }
    }

    // MARK: - Push, sub-push, pop

    /// Settings → Performance, and Back to the list.
    func testPushAndPop() throws {
        let app = try launch()
        guard pushPerformance(app) else { return }
        XCTAssertTrue(back(app).appears(timeout: 5), "No Back button on the pushed page")
        XCTAssertFalse(app.buttons["settings.performance"].isHittable, "The list is still reachable under the pushed page")
        back(app).tap()
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 5))
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 5), "The row the push opened is not back")
        XCTAssertTrue(app.buttons["settings.performance"].isHittable)
    }

    /// Settings → Vacation Mode → a sub-page, then back twice. The chooser only shows for a resident; without it the journey stops
    /// after the first level.
    func testSubPushAndPop() throws {
        let app = try launch()
        let row = app.buttons["settings.vacation"]
        app.revealSettingsRow(row)
        guard row.exists else { return }
        row.tap()
        if app.buttons["split.close"].appears(timeout: 1.5) { return }
        let chooser = element("vacation.chooser.vacationMode", in: app)
        guard chooser.appears(timeout: 15) else { return }
        chooser.tap()
        XCTAssertTrue(back(app).appears(timeout: 10))
        back(app).tap()
        XCTAssertTrue(element("vacation.chooser.vacationMode", in: app).appears(timeout: 5), "Back did not return to the chooser")
        back(app).tap()
        XCTAssertTrue(app.buttons["settings.vacation"].appears(timeout: 5), "Back did not return to the Settings list")
    }

    // MARK: - Edge swipe

    /// A swipe from the leading edge let go past halfway completes the pop.
    func testSwipeBackCompletes() throws {
        let app = try launch()
        guard pushPerformance(app) else { return }
        swipeBack(app, fraction: 0.7, slow: false)
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 5), "The swipe did not pop")
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 5))
    }

    /// The Food hub is a column host deeper in Home's stack: in a single-page window (no columns open) one leading-edge swipe pops it
    /// back to Home, once. Where the window splits, the columns' own swipe and the hosted `StackMotionTests` own the two-step case.
    func testSwipeBackFromTheFoodHubPopsToHome() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_FOOD_FIXTURES": "1", "FENTON_BACKDROP_FIXTURE": "1"])
        let open = app.buttons["quickLinks.open"]
        XCTAssertTrue(open.appears(timeout: 20), "Home did not appear")
        open.tap()
        let food = element("quickLinks.food", in: app)
        XCTAssertTrue(food.appears(timeout: 10), "No Food link in Quick Links")
        food.tap()
        XCTAssertTrue(element("food.space.frigo", in: app).appears(timeout: 15), "The Food hub did not open")
        swipeBack(app, fraction: 0.7, slow: false)
        XCTAssertTrue(app.buttons["quickLinks.open"].appears(timeout: 5), "The swipe did not pop the Food hub to Home")
        XCTAssertFalse(element("food.space.frigo", in: app).isHittable, "The Food hub is still reachable after the swipe")
    }

    /// A slow swipe let go early reverses: the page stays, with its Back button.
    func testSwipeBackLetGoEarlyCancels() throws {
        let app = try launch()
        guard pushPerformance(app) else { return }
        swipeBack(app, fraction: 0.25, slow: true)
        sleep(1)
        XCTAssertTrue(back(app).exists, "A swipe let go at a quarter popped the page")
        XCTAssertTrue(back(app).isHittable, "The cancelled swipe left no Back button")
        back(app).tap()
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 5), "Back after a cancelled swipe did not pop")
    }

    // MARK: - Tabs

    /// A tab switch is a cut and each tab keeps its stack: Settings stays on the pushed page, the other tab shows its own root.
    func testTabSwitchKeepsEachStack() throws {
        let app = try launch()
        guard pushPerformance(app) else { return }
        go("home", "Home", in: app)
                XCTAssertFalse(back(app).exists, "The pushed page showed on another tab")
        go("settings", "Settings", in: app, root: false)
        XCTAssertTrue(back(app).appears(timeout: 5), "Settings lost its pushed page on a tab switch")
        XCTAssertTrue(back(app).isHittable)
    }

    // MARK: - Reduce Motion and text size

    /// With Reduce Motion the push, Back and the swipe still work (the slide is a 0.2 s cross-fade).
    func testReduceMotionPushBackAndSwipe() throws {
        let app = try launch(environment: FentonHomeApp.SystemSetting.environment([.reduceMotion]))
        guard pushPerformance(app) else { return }
        back(app).tap()
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 5))
        XCTAssertTrue(pushPerformance(app))
        swipeBack(app, fraction: 0.7, slow: false)
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 5), "The swipe did not pop with Reduce Motion on")
    }

    /// At AX5 the push, the Back button's 44 pt target and the pop hold.
    func testPushAndPopAtAX5() throws {
        let app = try launch(arguments: FentonHomeApp.ax5)
        guard pushPerformance(app) else { return }
        let button = back(app)
        XCTAssertTrue(button.appears(timeout: 5))
        // XCUITest reports a glass bar item's frame inside its 44 pt circle (see the hamburger journey): at least 36.
        XCTAssertGreaterThanOrEqual(button.frame.width, 36)
        XCTAssertGreaterThanOrEqual(button.frame.height, 36)
        button.tap()
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 5))
    }

    // MARK: - Accessibility

    /// The pushed page is the only page VoiceOver can reach (the outgoing one leaves the accessibility tree when it leaves the screen),
    /// Back is a labelled 44 pt button, and after the pop the opening row is reachable again.
    func testPushedPageIsTheOnlyReachablePage() throws {
        let app = try launch()
        guard pushPerformance(app) else { return }
        XCTAssertFalse(app.descendants(matching: .any)["settings.list"].firstMatch.isHittable, "The list is reachable under the pushed page")
        let button = back(app)
        XCTAssertEqual(button.identifier, "BackButton")
        // The folded Duo's vertical bar exposes the system Back with an empty label (PROGRESS.md, "Duo Back label"): there the control is
        // checked by its identifier and by being a button; every other layout must carry a label.
        if FentonHomeApp.family == .iPhone { XCTAssertFalse(button.label.isEmpty, "Back has no label (\(layout))") }
        XCTAssertEqual(button.elementType, .button)
        // VoiceOver lands on the pushed page first: the first reachable control in reading order is the pushed page's (its Back on the
        // iPhone, its own bar or content on the Duo's rail), never a row of the list under it.
        let first = app.buttons.allElementsBoundByIndex.first { $0.isHittable }?.identifier ?? "none"
        XCTAssertTrue(first == "BackButton" || first.hasPrefix("performance."), "The first reachable control is not the pushed page's (\(first))")
        XCTAssertGreaterThanOrEqual(button.frame.width, 36)
        XCTAssertGreaterThanOrEqual(button.frame.height, 36)
        button.tap()
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 5))
        XCTAssertFalse(back(app).exists)
    }

    // MARK: - Wallpaper

    /// The wallpaper reaches every edge of the window for as long as a page moves. The launch runs the animations twenty times slower
    /// (`FENTON_UITEST_ANIMATION_SPEED`), so a push or pop lasts several seconds and the samples fall inside it.
    func testWallpaperStaysWhileAPageMoves() throws {
        let app = try launch(environment: ["FENTON_UITEST_NO_ANIMATIONS": "1", "FENTON_UITEST_ANIMATION_SPEED": "0.05"])
        let row = performanceRow(app)
        XCTAssertTrue(row.exists)
        var missing: [String] = []
        func sample(_ moment: String) {
            let found = WallpaperSampling.uncovered(in: app)
            if !found.isEmpty { missing.append("\(moment): \(found.joined(separator: ", "))") }
        }
        sample("settings at rest")
        row.tap()
        for index in 0..<6 { sample("during or after the push #\(index)") }
        guard back(app).appears(timeout: 20) else { return XCTFail("Performance did not push") }
        sample("pushed at rest")
        if back(app).exists { back(app).tap() }
        for index in 0..<6 { sample("during or after the pop #\(index)") }
        XCTAssertTrue(app.buttons["settings.performance"].appears(timeout: 20))
        sample("back at rest")
        XCTAssertTrue(missing.isEmpty, "Plain background showed (\(layout)): \(missing.joined(separator: " | "))")
    }

    // MARK: - Evidence

    private func mark(_ name: String) {
        guard let path = ProcessInfo.processInfo.environment["FENTON_MOTION_MARKS"], !path.isEmpty else { return }
        let line = "\(name) \(String(format: "%.3f", Date().timeIntervalSince1970))\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: false, encoding: .utf8)
        }
    }

    /// Each move with a pause around it: `<move>.start` and `<move>.end` marks bracket the action.
    private func move(_ name: String, _ action: () -> Void) {
        sleep(2)
        mark("\(name).start")
        action()
        mark("\(name).end")
        sleep(2)
    }

    func testRecordSinglePageMotion() throws {
        guard let path = ProcessInfo.processInfo.environment["FENTON_MOTION_MARKS"], !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
        let app = try launch()
        let row = performanceRow(app)
        guard row.exists else { return }
        var pushed = false
        move("push") { pushed = pushPerformance(app) }
        guard pushed else { return }
        move("pop") { back(app).tap() }
        _ = pushPerformance(app)
        move("swipe-complete") { swipeBack(app, fraction: 0.7, slow: true) }
        _ = pushPerformance(app)
        move("swipe-cancel") { swipeBack(app, fraction: 0.25, slow: true) }
        move("pop-after-cancel") { back(app).tap() }
        let vacation = app.buttons["settings.vacation"]
        app.revealSettingsRow(vacation)
        if vacation.exists {
            move("push-vacation") { vacation.tap() }
            let chooser = element("vacation.chooser.vacationMode", in: app)
            if chooser.appears(timeout: 15) {
                move("sub-push") { chooser.tap() }
                move("sub-pop") { back(app).tap() }
            }
            move("pop-vacation") { back(app).tap() }
        }
        _ = pushPerformance(app)
        move("tab-switch") { go("home", "Home", in: app) }
        move("tab-switch-back") { go("settings", "Settings", in: app, root: false) }
    }
}
