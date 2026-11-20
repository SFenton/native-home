import XCTest

/// Sections that take sides (`FENTON_GALLERY=fold-sides`; `sh.fold-sides@1`) on a `foldSides: auto` page, flat, partly folded and flat
/// again. The gallery's `foldSides.pose.partly` and `.flat` buttons publish the fold the way the shell does, so the journey runs on every family and
/// checks what the window can show: where it is wide enough to split (an iPad in landscape, the unfolded Duo) every section sits wholly on one side of the
/// band and the sides come back to one column when flat; in a narrower window (an iPhone, the folded Duo's outer display) the band changes nothing.
@MainActor
final class FoldSidesJourneyTests: JourneyTestCase {
    private let ids = ["s1", "s2", "s3", "s4"]
    private let bandWidth: CGFloat = 40.4

    /// The families that rotate (iPhone is portrait-locked) turn to landscape, where a window can split.
    private static var rotates: Bool { [FentonHomeApp.Family.iPad, .iPhoneDuo].contains(FentonHomeApp.family) }

    override func tearDown() {
        MainActor.assumeIsolated { if Self.rotates { XCUIDevice.shared.orientation = .portrait } }
        super.tearDown()
    }

    private func launch(arguments: [String] = [], settings: [FentonHomeApp.SystemSetting] = []) -> XCUIApplication {
        if Self.rotates { XCUIDevice.shared.orientation = .landscapeLeft }
        let configured = FentonHomeApp.makeApp()
        configured.launchArguments += arguments
        if !settings.isEmpty { configured.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment(settings)) { $1 } }
        configured.launchEnvironment["FENTON_GALLERY"] = "fold-sides"
        let app = startApp(configured)
        XCTAssertTrue(element("foldSides.pose", in: app).appears(timeout: 20), "the gallery never drew")
        XCTAssertFalse(element("foldSides.failure", in: app).exists, "the gallery's composition was refused")
        XCTAssertTrue(element("s1", in: app).appears(timeout: 10), "the page's sections never drew")
        return app
    }

    private func frames(in app: XCUIApplication) -> [CGRect] { ids.map { element($0, in: app).frame } }

    /// Whether the window can split: landscape and each side at least 360 pt.
    private func splits(_ app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch.frame
        return window.width > window.height && window.width / 2 >= 360
    }

    private func pose(_ name: String, in app: XCUIApplication) {
        element("foldSides.pose.\(name)", in: app).tap()
        let marker = element("foldSides.pose", in: app)
        let settled = NSPredicate(format: "label == %@", name)
        wait(for: [expectation(for: settled, evaluatedWith: marker)], timeout: 5)
        settleScreen()
        usleep(900_000)
    }

    func testSectionsTakeSidesWhilePartlyFoldedAndReturnWhenFlat() throws {
        let app = launch()
        let window = app.windows.firstMatch.frame
        let splits = window.width > window.height && window.width / 2 >= 360
        let flat = frames(in: app)
        XCTAssertEqual(Set(flat.map { Int($0.minX) }).count, 1, "flat, the sections are one column")
        XCTAssertEqual(flat.map(\.minY), flat.map(\.minY).sorted(), "flat, in document order")

        pose("partly", in: app)
        let partly = frames(in: app)
        if splits {
            let mid = window.midX
            for index in [0, 2] { XCTAssertLessThanOrEqual(partly[index].maxX, mid - bandWidth / 2 + 1, "\(ids[index]) is wholly on the leading side") }
            for index in [1, 3] { XCTAssertGreaterThanOrEqual(partly[index].minX, mid + bandWidth / 2 - 1, "\(ids[index]) is wholly on the trailing side") }
            XCTAssertEqual(partly[0].minX, partly[2].minX, accuracy: 1, "the leading side is one stack")
            XCTAssertEqual(partly[1].minX, partly[3].minX, accuracy: 1, "the trailing side is one stack")
            XCTAssertGreaterThan(partly[2].minY, partly[0].minY, "the third section stacks under the first")
            XCTAssertGreaterThan(partly[3].minY, partly[1].minY, "the fourth section stacks under the second")
            XCTAssertEqual(partly[1].minY, partly[0].minY, accuracy: 1, "the two sides start level")
            let rail = element("rail", in: app).frame, note = element("notice", in: app).frame
            for strip in [rail, note] {
                XCTAssertLessThan(strip.minX, mid - bandWidth / 2, "the top strip starts before the band")
                XCTAssertGreaterThan(strip.maxX, mid + bandWidth / 2, "and runs over it")
            }
            XCTAssertGreaterThanOrEqual(partly[0].minY, note.maxY - 1, "both sides start under the strip")
            keepScreenshot(app, "fold-sides-partly")
        } else {
            XCTAssertEqual(partly, flat, "a window too narrow to split stays one column")
        }

        pose("flat", in: app)
        let back = frames(in: app)
        for (index, frame) in back.enumerated() {
            XCTAssertEqual(frame.minX, flat[index].minX, accuracy: 1, "\(ids[index]) returns to its flat place")
            XCTAssertEqual(frame.minY, flat[index].minY, accuracy: 1, "\(ids[index]) returns to its flat place")
        }
    }

    func testTheReadingOrderIsTheSameInEveryPose() throws {
        let app = launch()
        let before = ids.map { element($0, in: app).label }
        XCTAssertTrue(before.allSatisfy { !$0.isEmpty }, "every section speaks")
        pose("partly", in: app)
        XCTAssertEqual(Set(ids.map { element($0, in: app).label }), Set(before), "the same sections speak partly folded")
        pose("flat", in: app)
        XCTAssertEqual(ids.map { element($0, in: app).label }, before)
    }

    /// The posture reflow opens a `LayoutChange` interval for the fold columns (`Telemetry.Name.layoutChange`, page `FoldColumns`), so the move
    /// can be measured with `XCTOSSignpostMetric`. Only a window that splits changes pose, so the others skip.
    func testThePostureReflowRecordsTheLayoutChangeSignpost() throws {
        let app = launch()
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width > window.height && window.width / 2 >= 360, "this window is too narrow to split, so no pose reflow runs")
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        let reflow = XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "LayoutChange")
        measure(metrics: [reflow], options: options) {
            pose("partly", in: app)
            pose("flat", in: app)
        }
    }

    /// At the largest text size the wrapped rail heads the leading column and the trailing side starts level with it.
    func testAtTheLargestTextSizeTheRailHeadsTheLeadingColumn() throws {
        let app = launch(arguments: FentonHomeApp.ax5)
        try XCTSkipUnless(splits(app), "this window is too narrow to split")
        pose("partly", in: app)
        let mid = app.windows.firstMatch.frame.midX
        let rail = element("rail", in: app).frame
        XCTAssertLessThanOrEqual(rail.maxX, mid - bandWidth / 2 + 1, "the wrapped rail stops short of the band")
        XCTAssertEqual(element("s2", in: app).frame.minY, rail.minY, accuracy: 1, "the trailing side starts level with the rail")
        XCTAssertGreaterThanOrEqual(element("s2", in: app).frame.minX, mid + bandWidth / 2 - 1, "two sides at every size")
        keepScreenshot(app, "fold-sides-partly-ax5")
    }

    /// With Reduce Motion the reflow cross-fades; the picture it ends on is the same two sides.
    func testWithReduceMotionThePostureChangeEndsOnTheSameSides() throws {
        let app = launch(settings: [.reduceMotion])
        try XCTSkipUnless(splits(app), "this window is too narrow to split")
        let flat = frames(in: app)
        pose("partly", in: app)
        let mid = app.windows.firstMatch.frame.midX
        XCTAssertLessThanOrEqual(element("s1", in: app).frame.maxX, mid - bandWidth / 2 + 1)
        XCTAssertGreaterThanOrEqual(element("s2", in: app).frame.minX, mid + bandWidth / 2 - 1)
        keepScreenshot(app, "fold-sides-partly-reduce-motion")
        pose("flat", in: app)
        for (index, frame) in frames(in: app).enumerated() { XCTAssertEqual(frame.minY, flat[index].minY, accuracy: 1, "\(ids[index]) returns") }
    }
}
