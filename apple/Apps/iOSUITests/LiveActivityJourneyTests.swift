import XCTest

/// The Live Activity cards in the debug gallery (`live-activity`): the Lock Screen card (L4), the Dynamic Island stand-ins
/// (compact, minimal, expanded E2c) and the small family, over fixtures, with their buttons, on iPhone, iPhone Duo and iPad
/// (`.agents/platforms/apple/live-activities-per-job.md` §8, §8a, §12). Names, roles, reading order, 44 pt targets, AX5 layout,
/// the 160 pt height limit with two-line titles, the vacuum's round buttons, the compact island's rigid width and the expanded
/// island's clipping check.
@MainActor
final class LiveActivityJourneyTests: JourneyTestCase {
    /// Launches (or resets) the gallery on `scenario`.
    ///
    /// The gallery reads its scenario from `FENTON_GALLERY_SCENARIO` per gallery, so the class keeps one resident app and a
    /// test's scenario is a reset (`app-reuse.md`). AX5 (`arguments`) launches fresh by signature.
    private func launch(_ scenario: String, arguments: [String] = [], identifier: String? = nil) -> XCUIApplication {
        func start() -> XCUIApplication {
            let app = FentonHomeApp.makeApp()
            app.launchEnvironment["FENTON_GALLERY"] = "live-activity"
            app.launchEnvironment["FENTON_GALLERY_SCENARIO"] = scenario
            app.launchArguments += arguments
            return startApp(app)
        }
        var app = start()
        func first(_ app: XCUIApplication) -> XCUIElement {
            identifier.map { element($0, in: app) } ?? app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'liveactivity.'")).firstMatch
        }
        // The first launch after a simulator boots can stall; one relaunch separates that from a card that really did not draw.
        if !first(app).appears(timeout: 20) {
            app.terminate()
            app = start() // A terminated resident is relaunched.
        }
        XCTAssertTrue(first(app).appears(timeout: 30), "\(scenario) did not draw")
        return app
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].label.replacing("Last action: ", with: "")
    }

    // MARK: Tree snapshots

    /// Every node under `root` (not `root` itself) in tree order: what `descendants(matching: .any)` reaches, from one snapshot
    /// instead of one request per read.
    private func descendants(of root: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
        var found: [any XCUIElementSnapshot] = []
        func walk(_ node: any XCUIElementSnapshot) {
            for child in node.children { found.append(child); walk(child) }
        }
        walk(root)
        return found
    }

    /// The first descendant with identifier `id`.
    private func first(_ id: String, in root: any XCUIElementSnapshot) -> (any XCUIElementSnapshot)? {
        descendants(of: root).first { $0.identifier == id }
    }

    /// One snapshot of the element `id` (the app's tree when `id` is nil); fails the test when it is not there.
    private func snapshot(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> (any XCUIElementSnapshot)? {
        do { return try element(id, in: app).snapshot() } catch {
            XCTFail("\(id) has no snapshot: \(error)", file: file, line: line)
            return nil
        }
    }

    /// The first button under `root` named `name` (its label or identifier, as `buttons[name]` matches).
    private func button(_ name: String, in root: any XCUIElementSnapshot) -> (any XCUIElementSnapshot)? {
        descendants(of: root).first { $0.elementType == .button && ($0.label == name || $0.identifier == name) }
    }

    /// The first static text under `root` named `name`.
    private func text(_ name: String, in root: any XCUIElementSnapshot) -> (any XCUIElementSnapshot)? {
        descendants(of: root).first { $0.elementType == .staticText && ($0.label == name || $0.identifier == name) }
    }

    /// A snapshot node is at least 43 pt each way (`assertTarget`'s rule, from the node's frame).
    private func assertTarget(_ node: any XCUIElementSnapshot, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(node.frame.width, 43, node.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(node.frame.height, 43, node.label, file: file, line: line)
    }

    /// The cards a group draws, from one snapshot of the app.
    private func cards(in app: XCUIApplication) -> [any XCUIElementSnapshot] {
        guard let root = try? app.snapshot() else { return [] }
        return descendants(of: root).filter { $0.identifier.hasPrefix("liveactivity.card.") }
    }

    // MARK: Size

    /// The Lock Screen limit is 160 pt; a taller view is cut off by the system, so every card must fit.
    private func assertEveryCardFits(group: String) {
        let app = launch(group, identifier: nil)
        let found = cards(in: app)
        XCTAssertFalse(found.isEmpty, "\(group) drew no cards")
        for card in found {
            let frame = card.frame
            XCTAssertLessThanOrEqual(frame.height, 160, "\(card.identifier) is \(Int(frame.height)) pt tall")
            XCTAssertGreaterThan(frame.height, 60, "\(card.identifier) drew almost nothing")
            XCTAssertLessThanOrEqual(frame.width, 371, "\(card.identifier) is wider than a Lock Screen")
        }
        keepScreenshot(app, "live-activity-\(group)-\(layout)")
    }

    func testCardsFitLockScreenHeightJobs() { assertEveryCardFits(group: "jobs") }
    func testCardsFitLockScreenHeightComplete() { assertEveryCardFits(group: "complete") }
    func testCardsFitLockScreenHeightVacuums() { assertEveryCardFits(group: "vacuums") }
    func testCardsFitLockScreenHeightHotFlash() { assertEveryCardFits(group: "hotflash") }
    func testCardsFitLockScreenHeightStates() { assertEveryCardFits(group: "states") }
    func testCardsFitLockScreenHeightStack() { assertEveryCardFits(group: "stack") }
    func testCardsFitLockScreenHeightProblems() { assertEveryCardFits(group: "problems") }
    func testCardsFitLockScreenHeightProblemsFlipped() { assertEveryCardFits(group: "problems-flipped") }

    /// Every fixture card is in the catalog: the groups together hold more than 60 cards (the old loop's total). One launch
    /// of the `catalog` scenario counts them all.
    func testCardsFitLockScreenHeightCoversTheCatalog() {
        let app = launch("catalog", identifier: nil)
        XCTAssertGreaterThan(cards(in: app).count, 60, "every fixture card was measured")
    }

    /// A wrapped title is taller than one line: the one-line height comes from a fresh "fan" launch, closed before the
    /// scenario launches, so the step stands alone.
    private func assertTitleWraps(scenario: String, label: String) {
        let short = launch("fan", identifier: "liveactivity.lockscreen")
        guard let shortCard = snapshot("liveactivity.lockscreen", in: short), let shortTitle = first("liveactivity.title", in: shortCard) else {
            return XCTFail("the one-line title is missing")
        }
        let oneLine = shortTitle.frame.height
        let app = launch(scenario, identifier: "liveactivity.lockscreen")
        guard let card = snapshot("liveactivity.lockscreen", in: app), let title = first("liveactivity.title", in: card) else {
            return XCTFail("\(scenario): the title is missing")
        }
        XCTAssertTrue(title.label.hasPrefix(label), "\(scenario): \(title.label)")
        XCTAssertGreaterThan(title.frame.height, oneLine * 1.6, "\(scenario) wraps to a second line instead of truncating")
        XCTAssertLessThanOrEqual(card.frame.height, 160, "\(scenario) is \(Int(card.frame.height)) pt tall")
        // The corner mark stays top-right and the title does not run under it.
        XCTAssertLessThanOrEqual(title.frame.maxX, card.frame.maxX - 16 - 24, scenario)
        keepScreenshot(app, "live-activity-\(scenario)-\(layout)")
    }

    /// Long titles wrap to two lines (a card cannot scroll its title), still inside the 160 pt limit.
    func testLongTitleWrapsFanXLong() {
        assertTitleWraps(scenario: "fan-xlong", label: expectations[.tileClosetFanTitle])
    }

    func testLongTitleWrapsHotFlash() {
        assertTitleWraps(scenario: "hotflash-alex-bysam", label: "Hot Flash · Alex's side · by Sam")
    }

    /// The vacuum's long headline wraps too.
    func testLongTitleWrapsVacuumLong() {
        let closet = launch("vacuum-long", identifier: "liveactivity.lockscreen")
        guard let vacuum = snapshot("liveactivity.lockscreen", in: closet), let big = first("liveactivity.value", in: vacuum) else {
            return XCTFail("the vacuum card is missing")
        }
        XCTAssertTrue(big.label.contains("Vacuuming \(expectations[.tileClosetTitle])"), big.label)
        XCTAssertLessThanOrEqual(vacuum.frame.height, 160)
        keepScreenshot(closet, "live-activity-vacuum-long-\(layout)")
    }

    /// Row 1 is the glyph, the title and the mark; row 2 the value with the buttons beside it; row 3 the bar only with progress.
    func testLockScreenFanRowsInOrder() {
        let fan = launch("fan", identifier: "liveactivity.lockscreen")
        guard let lock = snapshot("liveactivity.lockscreen", in: fan),
              let title = first("liveactivity.title", in: lock), let value = first("liveactivity.value", in: lock),
              let stop = button("Stop Guest Bath Fan", in: lock), let bar = first("liveactivity.bar", in: lock) else {
            return XCTFail("the fan card is missing its title, value, Stop button or bar")
        }
        XCTAssertLessThanOrEqual(title.frame.maxY, value.frame.minY + 1, "the title is row 1, the value row 2")
        XCTAssertLessThan(value.frame.minX, stop.frame.minX, "the button sits right of the value")
        XCTAssertLessThanOrEqual(abs(stop.frame.midY - value.frame.midY), 12, "the button is in the value's row")
        XCTAssertGreaterThanOrEqual(bar.frame.minY, max(value.frame.maxY, stop.frame.maxY) - 8, "the bar is row 3")
    }

    func testLockScreenDryerHasNoBar() {
        let laundry = launch("dryer", identifier: "liveactivity.lockscreen")
        guard let lock = snapshot("liveactivity.lockscreen", in: laundry) else { return }
        XCTAssertNil(first("liveactivity.bar", in: lock), "a count-up has no progress, so no bar")
    }

    // MARK: Vacuum

    /// A vacuum has no time and no bar anywhere, and its Pause, Resume and Dock are 44 pt round icon buttons with spoken labels.
    private func assertVacuumCard(scenario: String, primary: String, big: String) {
        let app = launch(scenario, identifier: "liveactivity.lockscreen")
        guard let lock = snapshot("liveactivity.lockscreen", in: app),
              let primaryButton = button("\(primary) Main Floor Vacuum", in: lock), let dock = button("Dock Main Floor Vacuum", in: lock) else {
            return XCTFail("\(scenario): the \(primary) and Dock buttons are missing")
        }
        for button in [primaryButton, dock] {
            assertTarget(button)
            XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1, "\(button.label) is round (a square target)")
        }
        XCTAssertLessThan(primaryButton.frame.minX, dock.frame.minX, "\(primary) reads first")
        XCTAssertNil(text(primary, in: lock), "an icon button has no text pill")
        XCTAssertEqual(first("liveactivity.value", in: lock)?.label, big, scenario)
        let times = descendants(of: lock).filter { $0.elementType == .staticText && $0.label.range(of: #"\d+:\d\d"#, options: .regularExpression) != nil }
        XCTAssertEqual(times.count, 0, "\(scenario) shows no time")
        XCTAssertNil(first("liveactivity.bar", in: lock), "\(scenario) shows no bar")
        let card = lock
        XCTAssertLessThan(card.frame.height, 125, "\(scenario) is \(Int(card.frame.height)) pt tall")
        keepScreenshot(app, "live-activity-\(scenario)-\(layout)")
    }

    func testVacuumCardRunning() { assertVacuumCard(scenario: "vacuum", primary: "Pause", big: "Vacuuming Kitchen") }
    func testVacuumCardPaused() { assertVacuumCard(scenario: "vacuum-paused", primary: "Resume", big: "Paused in Kitchen") }

    /// A press still reaches the control map by id.
    func testVacuumCardPauseTapSendsAction() {
        let app = launch("vacuum", identifier: "liveactivity.lockscreen")
        element("liveactivity.lockscreen", in: app).buttons["Pause Main Floor Vacuum"].tap()
        XCTAssertEqual(lastAction(app), "pause job.vacuum.main_floor")
    }

    // MARK: Names, roles and order

    /// Buttons are named for their device, are at least 44 pt, and read in order with Done last.
    func testCardButtonsStack() {
        let stack = launch("stack")
        guard let root = try? stack.snapshot() else { return XCTFail("no tree") }
        for name in ["Stop Guest Bath Fan", "Stop Dishwasher"] {
            guard let found = button(name, in: root) else { XCTFail("\(name) is missing"); continue }
            assertTarget(found)
        }
        XCTAssertNil(button("Stop Washing Machine", in: root), "laundry has no buttons")
        XCTAssertNil(button("Stop Dryer", in: root))
    }

    func testCardButtonsProblemCard() {
        let problem = launch("problem-navigation-stuck", identifier: "liveactivity.lockscreen")
        guard let root = try? problem.snapshot(), let lock = first("liveactivity.lockscreen", in: root),
              let resume = button("Resume Main Floor Vacuum", in: lock), let dock = button("Dock Main Floor Vacuum", in: lock),
              let done = button("Done Main Floor Vacuum", in: lock) else {
            return XCTFail("the problem card is missing its Resume, Dock or Done button")
        }
        for button in [resume, dock, done] { assertTarget(button) }
        XCTAssertLessThan(resume.frame.minX, dock.frame.minX, "the primary button reads first")
        XCTAssertLessThan(dock.frame.minX, done.frame.minX, "Done is last")
        guard let phrase = descendants(of: root).first(where: { $0.label.hasPrefix("Main Floor Vacuum, needs help") }) else {
            return XCTFail("the needs-help sentence is missing")
        }
        XCTAssertEqual(phrase.label, "Main Floor Vacuum, needs help: Stuck in Kitchen. Move it somewhere flat, then tap Resume.")
        XCTAssertLessThan(phrase.frame.minY, resume.frame.minY + 1, "the card is read before its buttons")
    }

    /// A warning reads "needs attention".
    func testProblemCardMopWarning() {
        let warning = launch("problem-mop-clean_water_empty")
        let phrase = warning.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Main Floor Vacuum, needs attention'")).firstMatch
        XCTAssertTrue(phrase.exists)
        XCTAssertTrue(phrase.label.hasPrefix("Main Floor Vacuum, needs attention: Clean water tank empty."))
    }

    /// A chip is part of the sentence.
    func testProblemCardVendorError88() {
        let numbered = launch("problem-vendor-unknown_error_88")
        XCTAssertGreaterThan(numbered.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH 'Error 88'")).count, 0)
    }

    /// A job card is a title and a live figure in one element, with the words that make the figure a sentence.
    func testJobCardDryerReadsTitleAndFigure() {
        let dryer = launch("dryer")
        XCTAssertGreaterThan(dryer.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Dryer, running for'")).count, 0,
                             "a count-up reads \"running for\"")
    }

    func testJobCardVacuumPausedReadsTitleAndFigure() {
        let vacuum = launch("vacuum-paused")
        XCTAssertGreaterThan(vacuum.descendants(matching: .any).matching(NSPredicate(format: "label == 'Main Floor Vacuum'")).count, 0, "the device is the title")
        XCTAssertGreaterThan(vacuum.descendants(matching: .any).matching(NSPredicate(format: "label == 'Paused in Kitchen'")).count, 0, "the headline is the big line")
        XCTAssertTrue(vacuum.buttons["Resume Main Floor Vacuum"].exists && vacuum.buttons["Dock Main Floor Vacuum"].exists)
    }

    func testJobCardHotFlashReadsTitleAndFigure() {
        let hot = launch("hotflash-bysam")
        XCTAssertGreaterThan(hot.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Hot Flash' AND label CONTAINS 'Your side · by Sam'")).count, 0)
    }

    func testJobCardWasherCompleteReadsTitleAndFigure() {
        let complete = launch("washer-complete")
        XCTAssertGreaterThan(complete.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Complete'")).count, 0)
        XCTAssertEqual(complete.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Stop'")).count, 0, "a finished card has no buttons")
    }

    // MARK: Pending

    /// A button shows the card as pending at once and puts its pill away (optimistic, until Home Assistant confirms).
    func testStopShowsStoppingAndHidesTheButton() {
        let app = launch("fan", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: app)
        lock.buttons["Stop Guest Bath Fan"].tap()
        XCTAssertEqual(lastAction(app), "stop job.fan.guest")
        XCTAssertTrue(lock.staticTexts["Stopping…"].appears(timeout: 5))
        XCTAssertFalse(lock.buttons["Stop Guest Bath Fan"].exists)
        keepScreenshot(app, "live-activity-stopping-pressed-\(layout)")
    }

    func testAStalePendingStateGivesTheButtonBackWithNotConfirmed() {
        let app = launch("fan-pending-stale", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: app)
        XCTAssertTrue(lock.buttons["Stop Guest Bath Fan"].exists, "the controls come back")
        XCTAssertTrue(lock.staticTexts["Not confirmed"].exists)
        XCTAssertFalse(lock.staticTexts["Stopping…"].exists)
        let pending = launch("fan-pending", identifier: "liveactivity.lockscreen")
        XCTAssertTrue(element("liveactivity.lockscreen", in: pending).staticTexts["Stopping…"].exists)
        XCTAssertFalse(element("liveactivity.lockscreen", in: pending).staticTexts["Not confirmed"].exists)
    }

    func testANoticeReplacesTheFigureForOneUpdate() {
        let app = launch("fan-notice", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: app)
        XCTAssertTrue(lock.staticTexts["Couldn't reach Home"].exists)
        XCTAssertTrue(lock.buttons["Stop Guest Bath Fan"].exists, "the button is back")
    }

    func testDoneOnAProblemShowsCompleting() {
        let app = launch("problem-navigation-stuck", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: app)
        lock.buttons["Done Main Floor Vacuum"].tap()
        XCTAssertEqual(lastAction(app), "done job.vacuum.main_floor")
        XCTAssertTrue(lock.staticTexts["Completing…"].appears(timeout: 5))
    }

    // MARK: Large text

    /// At the largest text size nothing runs off the screen, the figure wraps under the title and the targets hold.
    private func assertAX5CardStaysOnScreen(_ scenario: String) {
        let app = launch(scenario, arguments: FentonHomeApp.ax5, identifier: "liveactivity.lockscreen")
        guard let root = try? app.snapshot(), let lock = first("liveactivity.lockscreen", in: root) else { return XCTFail("\(scenario): no card") }
        let window = descendants(of: root).first { $0.elementType == .window }?.frame ?? root.frame
        XCTAssertLessThanOrEqual(lock.frame.maxX, window.maxX + 0.5, scenario)
        XCTAssertGreaterThanOrEqual(lock.frame.minX, window.minX - 0.5, scenario)
        for button in descendants(of: lock).filter({ $0.elementType == .button }) {
            assertTarget(button)
            XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX + 0.5, "\(scenario) \(button.label) runs off the screen")
            XCTAssertGreaterThanOrEqual(button.frame.minX, lock.frame.minX - 0.5, "\(scenario) \(button.label) runs off the card")
        }
        keepScreenshot(app, "live-activity-\(scenario)-ax5-\(layout)")
    }

    func testAX5CardFanStaysOnScreen() { assertAX5CardStaysOnScreen("fan") }
    func testAX5CardVacuumStaysOnScreen() { assertAX5CardStaysOnScreen("vacuum") }
    func testAX5CardVacuumLongStaysOnScreen() { assertAX5CardStaysOnScreen("vacuum-long") }
    func testAX5CardFanXLongStaysOnScreen() { assertAX5CardStaysOnScreen("fan-xlong") }
    func testAX5CardDishwasherLongStaysOnScreen() { assertAX5CardStaysOnScreen("dishwasher-long") }
    func testAX5CardHotFlashAlexBySamStaysOnScreen() { assertAX5CardStaysOnScreen("hotflash-alex-bysam") }
    func testAX5CardHotFlashCoolingStaysOnScreen() { assertAX5CardStaysOnScreen("hotflash-cooling") }
    func testAX5CardProblemNavigationStuckStaysOnScreen() { assertAX5CardStaysOnScreen("problem-navigation-stuck") }
    func testAX5CardProblemVendorError88StaysOnScreen() { assertAX5CardStaysOnScreen("problem-vendor-unknown_error_88") }

    // MARK: Island

    /// The island stand-ins and the small family draw on every device.
    private func assertIslandPresentations(_ scenario: String) {
        let app = launch(scenario, identifier: "liveactivity.lockscreen")
        guard let root = try? app.snapshot() else { return XCTFail("\(scenario): no tree") }
        for kind in ["compact", "minimal", "expanded"] {
            XCTAssertNotNil(first("liveactivity.island.\(kind)", in: root), "\(scenario) \(kind)")
        }
        XCTAssertNotNil(first("liveactivity.small", in: root))
        let buttons = first("liveactivity.island.expanded", in: root).map { descendants(of: $0).filter { $0.elementType == .button } } ?? []
        XCTAssertFalse(buttons.isEmpty, "\(scenario): the expanded island has a button")
        for button in buttons { assertTarget(button) }
        app.swipeUp()
        keepScreenshot(app, "live-activity-islands-\(scenario)-\(layout)")
    }

    func testIslandPresentationsFan() { assertIslandPresentations("fan") }
    func testIslandPresentationsProblemNavigationStuck() { assertIslandPresentations("problem-navigation-stuck") }

    /// The expanded island (E2c) on the smallest, a standard and the largest camera region with an `H:MM:SS` value: only the glyph
    /// and the corner mark sit beside the camera, the value sits below it in the full width beside the buttons without being
    /// clipped, and the bar spans the block.
    func testTheExpandedIslandNeverClipsALongTimeOnEveryCameraWidth() {
        let app = launch("island-widths", identifier: "liveactivity.islandsize.older-pro")
        let expected: [String: CGFloat] = ["older-pro": 104.5, "narrow-camera": 120, "pro-max": 128]
        guard let root = try? app.snapshot() else { return XCTFail("no tree") }
        for (size, regionWidth) in expected {
            guard let island = first("liveactivity.islandsize.\(size)", in: root) else { XCTFail(size); continue }
            let all = descendants(of: island)
            func find(_ id: String, in nodes: [any XCUIElementSnapshot]? = nil) -> (any XCUIElementSnapshot)? { (nodes ?? all).first { $0.identifier == id } }
            guard let trailing = find("liveactivity.island.trailing.bounds"), let leading = find("liveactivity.island.leading.bounds"),
                  let shape = find("liveactivity.island.shape") else {
                XCTFail("\(size) draws both regions")
                continue
            }
            XCTAssertEqual(trailing.frame.width, regionWidth, accuracy: 1, "\(size) trailing region")
            XCTAssertEqual(leading.frame.width, regionWidth, accuracy: 1, "\(size) leading region")
            XCTAssertLessThanOrEqual(trailing.frame.maxX, shape.frame.maxX - 17, "\(size) the region stays inside the island")
            // Beside the camera: the glyph and the mark only, no text.
            func texts(under id: String) -> Int { find(id).map { descendants(of: $0).filter { $0.elementType == .staticText }.count } ?? 0 }
            XCTAssertEqual(texts(under: "liveactivity.island.trailing"), 0, "\(size) nothing but the corner mark beside the camera on the right")
            XCTAssertEqual(texts(under: "liveactivity.island.leading"), 0, "\(size) nor on the left")
            // Below the camera: title over value, buttons on the right, bar under both.
            guard let bottom = find("liveactivity.island.bottom") else { XCTFail("\(size) has no bottom region"); continue }
            XCTAssertGreaterThan(bottom.frame.minY, trailing.frame.maxY - 1, "\(size) the bottom region sits under the camera row")
            let below = descendants(of: bottom)
            let stops = below.filter { $0.elementType == .button }
            guard let value = find("liveactivity.value", in: below), let title = find("liveactivity.title", in: below), let stop = stops.first else {
                XCTFail("\(size): the bottom region needs a title, a value and a button")
                continue
            }
            XCTAssertLessThanOrEqual(title.frame.maxY, value.frame.minY + 1, "\(size) the title is over the value")
            XCTAssertLessThanOrEqual(value.frame.maxX, stop.frame.minX + 0.5, "\(size) the value stops before the buttons")
            XCTAssertGreaterThanOrEqual(value.frame.minX, shape.frame.minX, size)
            XCTAssertLessThanOrEqual(stop.frame.maxX, shape.frame.maxX - 17, "\(size) the buttons stay inside the island")
            XCTAssertLessThanOrEqual(abs(stop.frame.midY - value.frame.midY), 30, "\(size) the buttons are in line with the title-and-value block")
            // The value at its natural 32 pt width fits the room beside the buttons before any scaling.
            if let probe = first("liveactivity.probe.\(size)", in: root) {
                XCTAssertLessThanOrEqual(probe.frame.width, value.frame.width, "\(size): \"1:04:42\" at 32 pt is \(Int(probe.frame.width)) pt, the room \(Int(value.frame.width))")
            } else {
                XCTFail("\(size) probe")
            }
            guard let bar = find("liveactivity.bar", in: below) else { XCTFail("\(size) a countdown has a bar"); continue }
            XCTAssertGreaterThanOrEqual(bar.frame.minY, value.frame.maxY - 8, "\(size) the bar is under the block")
            for button in stops { assertTarget(button) }
        }
        keepScreenshot(app, "live-activity-island-widths-\(layout)")
    }

    /// The compact island's time is as wide as its hidden template ("00:00", or "0:00:00" from an hour), not as wide as the room
    /// the island offers, and a vacuum's word is capped at 56 pt.
    func testTheCompactTimeHasTheWidthOfItsTemplateNotTheRoomTheIslandOffers() {
        let app = launch("compact-widths", identifier: "liveactivity.probe.compact.short")
        guard let root = try? app.snapshot(), let shortProbe = first("liveactivity.probe.compact.short", in: root),
              let hoursProbe = first("liveactivity.probe.compact.hours", in: root) else { return XCTFail("the compact probes are missing") }
        let short = shortProbe.frame.width, hours = hoursProbe.frame.width
        XCTAssertGreaterThan(hours, short + 4, "the H:MM:SS template is wider")
        let trailing = descendants(of: root).filter { $0.identifier == "liveactivity.compact.trailing.bounds" }
        XCTAssertEqual(trailing.count, 4, "MM:SS, H:MM:SS, and two vacuum words")
        guard trailing.count == 4 else { return }
        XCTAssertEqual(trailing[0].frame.width, short, accuracy: 1, "42:00 takes the 00:00 template width")
        XCTAssertEqual(trailing[1].frame.width, hours, accuracy: 1, "1:04:42 takes the 0:00:00 template width")
        // The stand-in leaves 112 pt beside its ring; a time that reported its widest possible width would take all of it.
        XCTAssertLessThan(trailing[0].frame.width, 60)
        XCTAssertLessThan(trailing[1].frame.width, 70)
        for index in [2, 3] {
            XCTAssertLessThanOrEqual(trailing[index].frame.width, 56.5, "a word is capped at 56 pt")
            XCTAssertGreaterThan(trailing[index].frame.width, 20)
        }
        keepScreenshot(app, "live-activity-compact-widths-\(layout)")
    }

    /// A vacuum in the expanded island: glyph and mark beside the camera, the headline as the big line, round buttons, no bar.
    func testTheExpandedVacuumHasRoundButtonsAndNoBar() {
        let app = launch("vacuum", identifier: "liveactivity.lockscreen")
        guard let root = try? app.snapshot(), let expanded = first("liveactivity.island.expanded", in: root) else {
            return XCTFail("the expanded island is missing")
        }
        guard let pause = button("Pause Main Floor Vacuum", in: expanded), let dock = button("Dock Main Floor Vacuum", in: expanded) else {
            return XCTFail("the expanded island is missing Pause or Dock")
        }
        for button in [pause, dock] {
            assertTarget(button)
            XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1, button.label)
        }
        XCTAssertEqual(first("liveactivity.value", in: expanded)?.label, "Vacuuming Kitchen")
        XCTAssertNil(first("liveactivity.bar", in: expanded))
        guard let compact = first("liveactivity.island.compact", in: root) else { return XCTFail("the compact island is missing") }
        XCTAssertGreaterThan(text("Kitchen", in: compact)?.frame.width ?? 0, 0, "the compact island says the room")
        app.swipeUp()
        keepScreenshot(app, "live-activity-vacuum-island-\(layout)")
    }

    // MARK: Accessibility audit

    func testStackPassesAccessibilityAudit() throws {
        let app = launch("stack")
        try FentonHomeApp.audit(app) { self.launch("stack", arguments: FentonHomeApp.ax5) }
    }

    func testLiveActivityVacuumsPassesAccessibilityAudit() throws {
        let app = launch("vacuums")
        try FentonHomeApp.audit(app) { self.launch("vacuums", arguments: FentonHomeApp.ax5) }
    }

    func testLiveActivityProblemCardPassesAccessibilityAudit() throws {
        let problems = launch("problem-navigation-stuck")
        try FentonHomeApp.audit(problems) { self.launch("problem-navigation-stuck", arguments: FentonHomeApp.ax5) }
    }

    // MARK: A real activity

    /// Real activities (started locally from fixture content, no Home Assistant and no Apple servers) on the real Lock
    /// Screen: the app starts them, the simulator locks, and SpringBoard shows the cards the extension drew. The simulator
    /// cannot take an ActivityKit push (`xcrun simctl push` refuses it), so this is the closest a host run gets.
    func testRealActivitiesShowOnTheLockScreen() throws {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_LIVE_ACTIVITY"] = "1"
        app.launchEnvironment["FENTON_LIVE_ACTIVITY_FIXTURE"] = "stack"
        // About the real Lock Screen and backgrounding: its own fresh launch (`app-reuse.md` rules 5 and 6).
        AppReuse.willLaunchOutside()
        app.launch()
        sleep(8)
        let lock = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: lock) else { throw XCTSkip("This runtime has no lock button hook") }
        _ = XCUIDevice.shared.perform(lock)
        sleep(2)
        _ = XCUIDevice.shared.perform(lock)
        sleep(6)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "live-activity-real-lockscreen-\(layout)"
        shot.lifetime = .keepAlways
        add(shot)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The first request asks "Allow Live Activities from S+H?" under the activity; allowing keeps it.
        let allow = springboard.buttons["Allow"]
        if allow.appears(timeout: 3) { allow.tap() }
        let tree = XCTAttachment(string: springboard.debugDescription)
        tree.name = "springboard-tree-\(layout)"
        tree.lifetime = .keepAlways
        add(tree)
        let rows = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Guest Bath Fan' OR label CONTAINS 'Dishwasher'"))
        if !rows.firstMatch.appears(timeout: 10) {
            // A simulator that already answered "Don't Allow" never shows the activity: Settings, S+H, Live Activities.
            throw XCTSkip("Live Activities are off for this app on this simulator; turn them on in Settings and rerun")
        }
        XCUIDevice.shared.press(.home)
    }
}
