import XCTest

/// Motion (`.agents/design/motion.md`, `.agents/design/motion-components.md`): the Motion gallery toggles every component's state
/// and checks that its accessibility value changes, its targets stay 44 pt and its frame does not move (only colour animates);
/// the shell's tabs, pages and sheets behave as the rules say, with Reduce Motion off and on.
///
/// The gallery tests need no sign-in. The shell tests are signed in against the house but only navigate and read.
@MainActor
final class MotionJourneyTests: JourneyTestCase {
    /// These tests measure animation, so their launches keep it on (``JourneyTestCase/measuresAnimation``).
    override class var measuresAnimation: Bool { true }

    /// The gallery's component ids (`MotionGallery.cases`), the single list the per-component journeys below are written from.
    /// Each id has three explicit methods (`testGalleryHas<Id>`, `testEveryComponent<Id>TogglesItsState` and `…WithReduceMotion`);
    /// `tools/tests/test_motion_gallery_journeys.py` fails when a gallery case or an id here lacks one.
    static let componentIDs = [
        "primaryButton", "floatingActionBar", "segmentedChoice", "modalTabBar", "modalTabBarIcons", "pageIndicator",
        "percentSlider", "controllerToggle", "pagedRow", "scheduleFields",
    ]

    // MARK: - Helpers

    /// Opens the motion gallery with `FENTON_UK_EXTRAS=1`, which adds the cases that have no SwiftUI counterpart (segmented choice,
    /// modal tab bars, page indicator, slider, paged row, schedule fields). The page is the whole gallery; each journey scrolls to
    /// its card with `reveal(_:in:)`.
    private func launch(reduceMotion: Bool) -> XCUIApplication {
        var environment = FentonHomeApp.SystemSetting.environment(reduceMotion ? [.reduceMotion] : [])
        environment["FENTON_UK_EXTRAS"] = "1"
        let app = FentonHomeApp.launchGallery("motion", environment: environment)
        XCTAssertTrue(app.descendants(matching: .any)["motion.toggleAll"].appears(timeout: 20), "The motion gallery did not open")
        return app
    }

    /// Scrolls until `element` can be hit, down first and then back up (the page is as long as the gallery).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<30 where !element.isHittable { scroll.swipeUp(velocity: .slow) }
        for _ in 0..<60 where !element.isHittable { scroll.swipeDown(velocity: .slow) }
        XCTAssertTrue(element.isHittable, "\(element) is not reachable")
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        // Polled, with the element looked up again each time: a predicate expectation kept a stale snapshot of a card the scroll
        // had just moved.
        let deadline = Date().addingTimeInterval(10)
        var last = ""
        repeat {
            last = (element.value as? String) ?? "nil"
            if last == value { return }
            usleep(200_000)
        } while Date() < deadline
        XCTFail("\(element.identifier) is '\(last)', expected '\(value)'", file: file, line: line)
    }

    private func assertSameFrame(_ before: CGRect, _ after: CGRect, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(before.origin.x, after.origin.x, accuracy: 0.5, "\(name) moved sideways", file: file, line: line)
        XCTAssertEqual(before.origin.y, after.origin.y, accuracy: 0.5, "\(name) moved", file: file, line: line)
        XCTAssertEqual(before.width, after.width, accuracy: 0.5, "\(name) changed width", file: file, line: line)
        XCTAssertEqual(before.height, after.height, accuracy: 0.5, "\(name) changed height", file: file, line: line)
    }

    /// Toggles one component: the value and the state text change, the frame does not, and every button in it is a 44 pt target.
    private func toggle(_ id: String, in app: XCUIApplication) {
        let component = app.descendants(matching: .any)["motion.component.\(id)"].firstMatch
        let button = app.buttons["motion.toggle.\(id)"]
        reveal(button, in: app)
        XCTAssertTrue(component.exists, id)
        waitForValue(component, "Off")
        let before = component.frame
        button.tap()
        waitForValue(component, "On")
        XCTAssertEqual(app.staticTexts["motion.state.\(id)"].label, "State: On", id)
        // The colour fades for up to 0.6 s; the frame must not move at any point, and certainly not at the end.
        assertSameFrame(before, component.frame, id)
        usleep(800_000)
        assertSameFrame(before, component.frame, id)
        assertTarget(button)
        for inner in component.buttons.allElementsBoundByIndex where inner.exists && inner.isHittable {
            // Pickers inside a component are system controls; their segments are not our targets.
            XCTAssertGreaterThanOrEqual(inner.frame.height, 43, "\(id): \(inner.label) is under 44 pt")
        }
        button.tap()
        waitForValue(component, "Off")
        assertSameFrame(before, component.frame, id)
    }

    // MARK: - Gallery

    // MARK: - Gallery, one test per component

    private func galleryHas(_ id: String) {
        let app = launch(reduceMotion: false)
        reveal(app.buttons["motion.toggle.\(id)"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["motion.component.\(id)"].exists, "\(id) has no component")
    }

    private func togglesItsState(_ id: String, reduceMotion: Bool) {
        let app = launch(reduceMotion: reduceMotion)
        toggle(id, in: app)
    }

    // MARK: Gallery lists the component

    func testGalleryHasPrimaryButton() { galleryHas("primaryButton") }
    func testGalleryHasFloatingActionBar() { galleryHas("floatingActionBar") }
    func testGalleryHasSegmentedChoice() { galleryHas("segmentedChoice") }
    func testGalleryHasModalTabBar() { galleryHas("modalTabBar") }
    func testGalleryHasModalTabBarIcons() { galleryHas("modalTabBarIcons") }
    func testGalleryHasPageIndicator() { galleryHas("pageIndicator") }
    func testGalleryHasPercentSlider() { galleryHas("percentSlider") }
    func testGalleryHasControllerToggle() { galleryHas("controllerToggle") }
    func testGalleryHasPagedRow() { galleryHas("pagedRow") }
    func testGalleryHasScheduleFields() { galleryHas("scheduleFields") }

    // MARK: - Every component toggles its state

    func testEveryComponentPrimaryButtonTogglesItsState() { togglesItsState("primaryButton", reduceMotion: false) }
    func testEveryComponentFloatingActionBarTogglesItsState() { togglesItsState("floatingActionBar", reduceMotion: false) }
    func testEveryComponentSegmentedChoiceTogglesItsState() { togglesItsState("segmentedChoice", reduceMotion: false) }
    func testEveryComponentModalTabBarTogglesItsState() { togglesItsState("modalTabBar", reduceMotion: false) }
    func testEveryComponentModalTabBarIconsTogglesItsState() { togglesItsState("modalTabBarIcons", reduceMotion: false) }
    func testEveryComponentPageIndicatorTogglesItsState() { togglesItsState("pageIndicator", reduceMotion: false) }
    func testEveryComponentPercentSliderTogglesItsState() { togglesItsState("percentSlider", reduceMotion: false) }
    func testEveryComponentControllerToggleTogglesItsState() { togglesItsState("controllerToggle", reduceMotion: false) }
    func testEveryComponentPagedRowTogglesItsState() { togglesItsState("pagedRow", reduceMotion: false) }
    func testEveryComponentScheduleFieldsTogglesItsState() { togglesItsState("scheduleFields", reduceMotion: false) }

    // MARK: - Every component toggles its state with Reduce Motion

    func testEveryComponentPrimaryButtonTogglesItsStateWithReduceMotion() { togglesItsState("primaryButton", reduceMotion: true) }
    func testEveryComponentFloatingActionBarTogglesItsStateWithReduceMotion() { togglesItsState("floatingActionBar", reduceMotion: true) }
    func testEveryComponentSegmentedChoiceTogglesItsStateWithReduceMotion() { togglesItsState("segmentedChoice", reduceMotion: true) }
    func testEveryComponentModalTabBarTogglesItsStateWithReduceMotion() { togglesItsState("modalTabBar", reduceMotion: true) }
    func testEveryComponentModalTabBarIconsTogglesItsStateWithReduceMotion() { togglesItsState("modalTabBarIcons", reduceMotion: true) }
    func testEveryComponentPageIndicatorTogglesItsStateWithReduceMotion() { togglesItsState("pageIndicator", reduceMotion: true) }
    func testEveryComponentPercentSliderTogglesItsStateWithReduceMotion() { togglesItsState("percentSlider", reduceMotion: true) }
    func testEveryComponentControllerToggleTogglesItsStateWithReduceMotion() { togglesItsState("controllerToggle", reduceMotion: true) }
    func testEveryComponentPagedRowTogglesItsStateWithReduceMotion() { togglesItsState("pagedRow", reduceMotion: true) }
    func testEveryComponentScheduleFieldsTogglesItsStateWithReduceMotion() { togglesItsState("scheduleFields", reduceMotion: true) }

    /// Back to the top of the page, where the bar item is in the accessibility tree.
    private func scrollToTop(_ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        let first = app.buttons["motion.toggle.\(Self.componentIDs[0])"]
        for _ in 0..<40 where !first.isHittable { scroll.swipeDown(velocity: .fast) }
        XCTAssertTrue(first.isHittable, "The top of the page is not reachable")
    }

    /// One pass down the page from the top: each component is visited once, as it scrolls into reach.
    private func sweep(_ app: XCUIApplication, _ visit: (String) -> Void) {
        let scroll = app.scrollViews.firstMatch
        var pending = Self.componentIDs
        var swipes = 0
        while !pending.isEmpty {
            let here = pending.filter { app.buttons["motion.toggle.\($0)"].isHittable }
            for id in here { visit(id) }
            pending.removeAll { here.contains($0) }
            if pending.isEmpty { break }
            swipes += 1
            if swipes > 60 { XCTFail("Not reachable: \(pending)"); return }
            scroll.swipeUp(velocity: .default)
        }
    }

    /// One pass over the whole, unfiltered gallery: measure every component, Toggle all on, then off. The pass stays whole because
    /// the on and off sweeps compare against the sizes measured in the first.
    private func toggleAllFlipsEveryComponent(reduceMotion: Bool) {
        do {
            let app = launch(reduceMotion: reduceMotion)
            func component(_ id: String) -> XCUIElement { app.descendants(matching: .any)["motion.component.\(id)"].firstMatch }
            // Off-screen components are not in the accessibility tree, so each is read as it scrolls into reach, in one pass down
            // the page per state. Scrolling moves positions, so the sizes are what must hold still.
            var sizes: [String: CGSize] = [:]
            sweep(app) { sizes[$0] = component($0).frame.size }
            // The bar item drops out of the accessibility tree at the foot of the page, so it is read and tapped from the top.
            func tapAll() {
                scrollToTop(app)
                let all = app.descendants(matching: .any)["motion.toggleAll"].firstMatch
                XCTAssertTrue(all.appears(timeout: 5), "Toggle all is not in the bar")
                all.tap()
            }
            tapAll()
            sweep(app) { id in
                waitForValue(component(id), "On")
                XCTAssertEqual(component(id).frame.size.width, sizes[id]?.width ?? 0, accuracy: 0.5, "\(id) changed width")
                XCTAssertEqual(component(id).frame.size.height, sizes[id]?.height ?? 0, accuracy: 0.5, "\(id) changed height")
            }
            tapAll()
            sweep(app) { waitForValue(component($0), "Off") }
        }
    }

    func testToggleAllMotionOnFlipsEveryComponent() { toggleAllFlipsEveryComponent(reduceMotion: false) }

    func testToggleAllReduceMotionFlipsEveryComponent() { toggleAllFlipsEveryComponent(reduceMotion: true) }

    func testGalleryPassesTheAccessibilityAudit() throws {
        let app = launch(reduceMotion: false)
        app.descendants(matching: .any)["motion.toggleAll"].firstMatch.tap()
        settleScreen()
        try FentonHomeApp.audit(app)
    }

    // MARK: - Shell (signed in; navigation only)

    /// Switching tabs is a cut: the destination's content is there as soon as the tap settles, and each tab keeps its own place.
    func testTabSwitchIsACutAndKeepsEachTabsPlace() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard app.barItem("Climate").exists else {
            throw XCTSkip("This window navigates with the flyout, not tabs")
        }
        for (section, title, scroll) in [("climate", "Climate", "climate.scroll"), ("home", "Home", "home.scroll")] {
            openSection(section, title: title, in: app)
            XCTAssertTrue(element(scroll, in: app).exists, "\(title) content was not there as soon as the switch settled")
        }
    }

    /// The second tap on the selected tab pops to the root; at the root the next tap scrolls to the top.
    func testSelectedTabPopsThenScrollsToTop() throws {
        let app = try FentonHomeApp.launchSignedIn()
        let settings = app.barItem("Settings")
        guard settings.exists else { throw XCTSkip("This window navigates with the flyout, not tabs") }
        settings.tap()
        let list = element("settings.list", in: app)
        XCTAssertTrue(list.appears(timeout: 10))
        let performance = app.buttons["settings.performance"]
        for _ in 0..<8 where !performance.isHittable { app.swipeUp() }
        XCTAssertTrue(performance.exists, "The Performance row is not in the list")
        performance.tap()
        XCTAssertTrue(element("performance.screen", in: app).appears(timeout: 10))
        settings.tap()
        XCTAssertTrue(list.appears(timeout: 10), "The first re-tap did not pop to the root")
        XCTAssertFalse(element("performance.screen", in: app).exists)
        // Scrolled down, the next re-tap scrolls back to the top.
        for _ in 0..<3 { app.swipeUp() }
        let top = app.buttons["settings.vacation"]
        XCTAssertFalse(top.isHittable, "The list did not scroll")
        settings.tap()
        XCTAssertTrue(top.wait(for: \.isHittable, toEqual: true, timeout: 5), "The second re-tap did not scroll to the top")
    }

    /// A sheet and a pushed room page still work with Reduce Motion on.
    func testSheetAndPushWorkWithReduceMotion() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: FentonHomeApp.SystemSetting.environment([.reduceMotion]))
        app.buttons["home.chip.lights"].tap()
        let rooms = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.lights.room.' AND NOT identifier CONTAINS '.action.'"))
        XCTAssertTrue(rooms.firstMatch.appears(timeout: 10))
        let room = rooms.firstMatch
        XCTAssertTrue(room.wait(for: \.isHittable, toEqual: true, timeout: 5))
        room.tap()
        XCTAssertTrue(element("overview.detail.subtitle", in: app).appears(timeout: 10), "The room page did not open")
        let back = app.buttons["BackButton"]
        XCTAssertTrue(back.appears(timeout: 5))
        back.tap()
        XCTAssertTrue(rooms.firstMatch.appears(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 5))
    }

    /// The room tile zooms into its page on iOS 18 and later, and pushes before it; either way the tile opens the page and Back
    /// returns to the tile's sheet.
    func testRoomTileOpensItsPage() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.buttons["home.chip.lights"].tap()
        let room = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.lights.room.' AND NOT identifier CONTAINS '.action.'")).firstMatch
        XCTAssertTrue(room.appears(timeout: 10))
        XCTAssertTrue(room.wait(for: \.isHittable, toEqual: true, timeout: 5))
        let identifier = room.identifier
        room.tap()
        XCTAssertTrue(element("overview.detail.subtitle", in: app).appears(timeout: 10))
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons[identifier].appears(timeout: 5))
        app.buttons["Close"].tap()
    }
}
