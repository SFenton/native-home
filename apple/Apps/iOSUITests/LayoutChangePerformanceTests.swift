import XCTest

/// What the animated layout changes cost (`.agents/design/mockups/proposals/motion-timings`, `.agents/design/motion.md` §10,
/// `.agents/testing/apple/performance.md`, "Layout changes"; runner: `tools/ios_motionperf.sh`).
///
/// The app records a `LayoutChange` signpost interval for each (`measuresMotion`: the value changing until the `standard` or
/// `quick` animation has settled). These tests flip Custom Lights' manual-control switch, which inserts and removes the mode row
/// and the light tiles (the heaviest of the changes), ten times, and measure `XCTOSSignpostMetric` on `LayoutChange`,
/// `XCTCPUMetric` and, on iOS 26 and later, `XCTHitchMetric`. Simulator hitch ratios and GPU cost are false: the simulator runs
/// only with `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` (the runner sets it), and the numbers it gives are CPU. A physical device
/// run needs the owner's say-so.
@MainActor
final class LayoutChangePerformanceTests: JourneyTestCase {
    /// These tests measure animation, so their launches keep it on (``JourneyTestCase/measuresAnimation``).
    override class var measuresAnimation: Bool { true }

    private func requireOptIn() throws {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["FENTON_PERF_ON_SIMULATOR"] != "1" {
            throw XCTSkip("Set TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1 to measure layout changes on a simulator.")
        }
        #endif
    }

    private func launch(reduceMotion: Bool) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "custom-lights"
        app.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        if reduceMotion { app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment([.reduceMotion])) { _, new in new } }
        app.launch()
        return app
    }

    private func metrics(_ app: XCUIApplication) -> [XCTMetric] {
        var metrics: [XCTMetric] = [
            XCTCPUMetric(application: app),
            XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "LayoutChange"),
        ]
        if #available(iOS 26, *) { metrics.append(XCTHitchMetric(application: app)) }
        return metrics
    }

    /// Flips the switch ten times (off and on is two changes), waiting out each animation.
    private func flip(_ app: XCUIApplication, reduceMotion: Bool) {
        let toggle = app.descendants(matching: .any)["customLights.manual"].firstMatch
        XCTAssertTrue(toggle.appears(timeout: 20), "The Custom Lights gallery did not open")
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: metrics(app), options: options) {
            for _ in 0..<5 {
                toggle.tap()
                Thread.sleep(forTimeInterval: reduceMotion ? 0.3 : 0.7)
            }
        }
    }

    // MARK: Remote action set

    /// Media STREAMER on the Media page (gallery state): Power turns it on as playing, so its tile swaps Power beside the chevron for
    /// previous / play-pause / next and a volume slider below (the full-row tile animates its height, ``TileActionSetTransition``);
    /// Next stops it, and the swap runs back. Each swap is one `LayoutChange` signpost with `page: TileActionSet`.
    private func flipRemoteActionSet(reduceMotion: Bool) {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "media-page"
        app.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        if reduceMotion { app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment([.reduceMotion])) { _, new in new } }
        app.launch()
        let tile = expectations[.mediaStreamerCard]
        let power = app.descendants(matching: .any)["\(tile).action.power"].firstMatch
        XCTAssertTrue(power.appears(timeout: 30), "The Media gallery did not open")
        power.tap() // On to off: the first press only readies the cycle.
        Thread.sleep(forTimeInterval: 0.5)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: metrics(app), options: options) {
            for _ in 0..<3 {
                let turnOn = app.descendants(matching: .any)["\(tile).action.power"].firstMatch
                if turnOn.appears(timeout: 5) { turnOn.tap() }
                Thread.sleep(forTimeInterval: reduceMotion ? 0.6 : 1.2)
                let next = app.descendants(matching: .any)["\(tile).action.next"].firstMatch
                if next.appears(timeout: 5) { next.tap() }
                Thread.sleep(forTimeInterval: reduceMotion ? 0.6 : 1.2)
            }
        }
    }

    // MARK: Vacuum setting rows

    /// The Studio vacuum's Cleaning Settings: Mode between Vacuum and Mop and Vacuum collapses the Water row and opens it again
    /// (``VacuumRowReveal``: height `standard`, content `quick`; Reduce Motion cross-fades). Each change is one `LayoutChange`
    /// interval with page `Vacuum.settingRows`. Two menu picks per change, so three changes each way per iteration.
    private func flipVacuumMode(reduceMotion: Bool) {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "vacuums"
        app.launchEnvironment["FENTON_GALLERY_VACUUM"] = JourneyExpectations.gallery[.vacuumMusicRoomMapId]
        app.launchEnvironment["FENTON_GALLERY_TAB"] = "controls"
        app.launchEnvironment["FENTON_GALLERY_SCENARIO"] = "docked"
        if reduceMotion { app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment([.reduceMotion])) { _, new in new } }
        app.launch()
        let mode = app.descendants(matching: .any)["vacuum.setting.Mode"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 30), "The vacuum sheet did not open")
        for _ in 0..<8 where !mode.isHittable { app.swipeUp(velocity: .slow) }
        func choose(_ title: String) {
            mode.tap()
            let item = app.buttons[title].firstMatch
            if item.waitForExistence(timeout: 5) { item.tap() }
            Thread.sleep(forTimeInterval: reduceMotion ? 0.4 : 0.7)
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: metrics(app), options: options) {
            for _ in 0..<3 {
                choose("Vacuum")
                choose("Vacuum and Mop")
            }
        }
    }

    /// The Water row collapsing and returning with the `standard` height and `quick` fade.
    func testVacuumSettingRowCost() throws {
        try requireOptIn()
        flipVacuumMode(reduceMotion: false)
    }

    /// The same with Reduce Motion on: the height changes at once and the row cross-fades.
    func testVacuumSettingRowCostReduceMotion() throws {
        try requireOptIn()
        flipVacuumMode(reduceMotion: true)
    }

    /// A remote's action set changing shape: the fade (`quick`), the height (`standard`) and the fade in, ~0.8 s each way.
    func testRemoteActionSetChangeCost() throws {
        try requireOptIn()
        flipRemoteActionSet(reduceMotion: false)
    }

    /// The same with Reduce Motion on: a 0.2 s cross-fade and no height animation.
    func testRemoteActionSetChangeCostReduceMotion() throws {
        try requireOptIn()
        flipRemoteActionSet(reduceMotion: true)
    }

    /// The inserts and removals with the `standard` animation.
    func testManualControlInsertCost() throws {
        try requireOptIn()
        flip(launch(reduceMotion: false), reduceMotion: false)
    }

    /// The same with Reduce Motion on: the change applies at once, so the cost is the layout alone.
    func testManualControlInsertCostReduceMotion() throws {
        try requireOptIn()
        flip(launch(reduceMotion: true), reduceMotion: true)
    }
}
